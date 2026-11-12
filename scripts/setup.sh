#!/usr/bin/env bash
# Guided setup of the Maxine SDK packages of this repository: checks the
# machine, offers each SDK's optional downloads, finds and validates your own
# NGC download of each SDK you choose, and walks through configure.sh,
# makepkg, the installation, the features an SDK adds after its install
# (NVIDIA's download_features.sh for the Audio Effects SDK) and a read-only
# check of the result. It asks before every step that changes anything (the
# default answer is always no) and prints the command it would run, so every
# step can also be done by hand. Running it again is safe: what is already
# done (a valid download, a selection.conf, a built package, the installed
# version, copied features) is detected and kept.
#
# The SDKs are data, not code: one descriptor per SDK in scripts/setup.d/
# (format: scripts/setup.d/README), PARSED as KEY=value text, never sourced.
# The optional downloads of an SDK are read from the array literals of its
# download.sh, as text; nothing of download.sh is run to read them.
#
# What it never does: accept a licence, log in to NGC, run `ngc config`, read
# ~/.ngc or any other credential, run `makepkg -i` or `-s`, run `pacman -R`,
# or run sudo without your explicit yes. Prompts are read from stdin and
# written to stderr; the script never opens /dev/tty itself (download.sh,
# which it offers to run, asks on the terminal on its own).
#
# MAXINE_SETUP_ROOT (empty by default) is a prefix for the system paths it
# reads and writes (/opt and /usr/share), for tests. The download directories
# are under $HOME. See --help.
#
# Exit status: 0 done (an SDK you skipped is not a failure), 1 a hard blocker
# or a failed step, 2 usage error.
set -euo pipefail
# The key, first of all: taken into a shell variable that is not exported and
# removed from the environment before any external command runs, so that no
# child but NVIDIA's download_features.sh ever receives it (/proc/<pid>/environ
# of every child keeps what it was started with). xtrace is off while the key
# is read, so that a `bash -x` run does not print it; the key step refuses to
# run under xtrace (see post_step).
case $- in *x*) setup_xtrace=1 ;; *) setup_xtrace=0 ;; esac
set +x
declare +x env_key=${NGC_API_KEY-}
unset NGC_API_KEY
((!setup_xtrace)) || set -x

prog=setup.sh
repo=$(cd "$(dirname "$0")/.." && pwd)
sys_root=${MAXINE_SETUP_ROOT:-}
desc_dir=$repo/scripts/setup.d

die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
warn() { printf '%s: WARNING: %s\n' "$prog" "$*" >&2; }
usage_error() {
    printf '%s: %s\n' "$prog" "$*" >&2
    printf 'Run %s --help for the options.\n' "$prog" >&2
    exit 2
}
say() { printf '%s\n' "$*"; }
# q <word>: the word as a shell word; plain words (paths, lists) unquoted.
q() {
    if [[ $1 =~ ^[A-Za-z0-9_./:,=+@%-]+$ ]]; then
        printf '%s' "$1"
    else
        printf '%q' "$1"
    fi
}
# cmdline <word...>: the words as one shell command line.
cmdline() {
    local word line=''
    for word in "$@"; do line+="$(q "$word") "; done
    printf '%s\n' "${line% }"
}
show_cmd() { printf '    $ %s\n' "$1"; } # show_cmd <command line>
in_list() { # in_list <word> <list...>
    local word=$1 item
    shift
    for item in "$@"; do [[ $item == "$word" ]] && return 0; done
    return 1
}
gib() { LC_ALL=C awk -v k="$1" 'BEGIN { printf "%.1f GiB", k / 1048576 }'; } # gib <KiB>
csv() { local IFS=,; printf '%s\n' "$*"; }                                     # csv <word...>
home_path() { # home_path <value>: ~/x is $HOME/x
    if [[ $1 == \~/* ]]; then printf '%s\n' "$HOME/${1#\~/}"; else printf '%s\n' "$1"; fi
}

# The descriptors: D[<key>:<field>]. Parsed as text; every value is checked.
desc_fields=(key title package default_src configure checksum_glob byhand_doc check_doc root
    env_file env_prefix core_lib model_dir model_dir_var model_glob feature_lib catalogue
    catalogue_features catalogue_early_access catalogue_what catalogue_default
    post_script post_args post_out)
desc_required=(key title package default_src configure checksum_glob byhand_doc check_doc root
    env_file env_prefix core_lib model_dir model_glob)
declare -A D=()
sdk_keys=()
# read_descriptor <file>: adds one SDK to D and sdk_keys.
read_descriptor() {
    local file=$1 line field value lineno=0 key
    local -A seen=()
    while IFS= read -r line || [[ -n $line ]]; do
        lineno=$((lineno + 1))
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        [[ $line =~ ^([a-z_]+)=(.*)$ ]] || die "$file:$lineno: not a KEY=value line"
        field=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        in_list "$field" "${desc_fields[@]}" || die "$file:$lineno: unknown key $field"
        [[ -z ${seen[$field]:-} ]] || die "$file:$lineno: duplicate key $field"
        [[ $value != *[\$\`\"\'\\[:cntrl:]]* ]] ||
            die "$file:$lineno: a \$, backtick, quote, backslash or control character is not allowed"
        seen[$field]=$value
    done <"$file"
    for field in "${desc_required[@]}"; do
        [[ -n ${seen[$field]:-} ]] || die "$file: no $field="
    done
    key=${seen[key]}
    [[ $key =~ ^[a-z0-9]+$ ]] || die "$file: key must be lower-case letters and digits"
    in_list "$key" "${sdk_keys[@]}" && die "$file: the key $key is used twice"
    [[ ${seen[package]} =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || die "$file: package must be a directory name"
    [[ ${seen[env_prefix]} =~ ^[A-Z][A-Z0-9_]*$ ]] || die "$file: env_prefix must be upper case"
    for field in root env_file; do
        [[ ${seen[$field]} == /* && ${seen[$field]} != *..* ]] || die "$file: $field must be an absolute path"
    done
    for field in configure catalogue core_lib model_dir post_script; do
        [[ -z ${seen[$field]:-} || (${seen[$field]} != /* && ${seen[$field]} != *..*) ]] ||
            die "$file: $field must be a relative path inside its directory"
    done
    # A post_script adds features into feature directories: it needs to know
    # where a feature's library is, and where it downloads to.
    if [[ -n ${seen[post_script]:-} ]]; then
        for field in feature_lib post_out; do
            [[ -n ${seen[$field]:-} ]] || die "$file: post_script needs $field="
        done
    fi
    [[ -z ${seen[feature_lib]:-} || (${seen[feature_lib]} == '{feature}'* && ${seen[feature_lib]} != *..*) ]] ||
        die "$file: feature_lib must begin with {feature} (the feature's directory below model_dir)"
    for field in "${!seen[@]}"; do D[$key:$field]=${seen[$field]}; done
    sdk_keys+=("$key")
}
shopt -s nullglob
desc_files=("$desc_dir"/*.conf)
shopt -u nullglob
((${#desc_files[@]} > 0)) || die "no SDK descriptor in $desc_dir: run this script from a clone of the repository"
for f in "${desc_files[@]}"; do read_descriptor "$f"; done

# The optional downloads of each SDK, read from its download.sh as text.
# parse_list <file> <name>: the words of the array literal `name=(...)` at
# the start of a line (it may span lines), one per line.
parse_list() {
    local file=$1 name=$2 line text='' on=0 w
    local -a words
    while IFS= read -r line || [[ -n $line ]]; do
        if ((!on)); then
            [[ $line == "$name=("* ]] || continue
            on=1 line=${line#"$name=("}
        fi
        if [[ $line == *')'* ]]; then
            text+=" ${line%%)*}"
            break
        fi
        text+=" $line"
    done <"$file"
    ((on)) || return 1
    read -r -a words <<<"$text"
    for w in "${words[@]}"; do
        [[ $w =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
        printf '%s\n' "$w"
    done
}
# parse_map <file> <name>: the [key]="value" lines of `declare -A name=(`,
# as key<TAB>value.
parse_map() {
    local file=$1 name=$2 line on=0
    while IFS= read -r line || [[ -n $line ]]; do
        if ((!on)); then
            [[ $line == "declare -A $name=(" ]] && on=1
            continue
        fi
        [[ $line =~ ^[[:space:]]*\)[[:space:]]*$ ]] && return 0
        [[ $line =~ ^[[:space:]]*\[([A-Za-z0-9_.-]+)\]=\"([^\"\$\`\\]*)\"[[:space:]]*$ ]] || return 1
        printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    done <"$file"
    return 1
}
declare -A cat_names=() cat_default=() cat_desc=() cat_ea=()
load_catalogue() { # load_catalogue <key>
    local key=$1 file arr k v name list
    local -A what=()
    local -a names=() words
    [[ -n ${D[$key:catalogue]:-} ]] || return 0
    file=$repo/${D[$key:package]}/${D[$key:catalogue]}
    [[ -f $file ]] || die "$file not found (the catalogue of the ${D[$key:title]})"
    read -r -a words <<<"${D[$key:catalogue_features]:-}"
    ((${#words[@]} > 0)) || die "${D[$key:title]}: catalogue_features is empty"
    for arr in "${words[@]}"; do
        list=$(parse_list "$file" "$arr") || die "$file: cannot read the array $arr"
        while IFS= read -r name; do
            [[ -n $name ]] && ! in_list "$name" "${names[@]}" && names+=("$name")
        done <<<"$list"
    done
    ((${#names[@]} > 0)) || die "$file: no optional downloads in ${D[$key:catalogue_features]}"
    if [[ -n ${D[$key:catalogue_what]:-} ]]; then
        list=$(parse_map "$file" "${D[$key:catalogue_what]}") || die "$file: cannot read ${D[$key:catalogue_what]}"
        while IFS=$'\t' read -r k v; do [[ -n $k ]] && what[$k]=$v; done <<<"$list"
    fi
    if [[ -n ${D[$key:catalogue_early_access]:-} ]]; then
        list=$(parse_list "$file" "${D[$key:catalogue_early_access]}") ||
            die "$file: cannot read ${D[$key:catalogue_early_access]}"
        while IFS= read -r name; do [[ -n $name ]] && cat_ea[$key:$name]=1; done <<<"$list"
    fi
    if [[ -n ${D[$key:catalogue_default]:-} ]]; then
        list=$(parse_list "$file" "${D[$key:catalogue_default]}") || die "$file: cannot read ${D[$key:catalogue_default]}"
        read -r -a words <<<"${list//$'\n'/ }"
        for name in "${words[@]}"; do
            in_list "$name" "${names[@]}" || die "$file: the default $name is not one of the optional downloads"
        done
        cat_default[$key]="${words[*]}"
    fi
    for name in "${names[@]}"; do
        v=${what[$name]:-${what[${name%%-*}]:-}}
        v=${v% (Early Access)}
        cat_desc[$key:$name]=$v
    done
    cat_names[$key]="${names[*]}"
}
for key in "${sdk_keys[@]}"; do load_catalogue "$key"; done

# show_catalogue <key> [selected...]: the numbered list; [x] marks the given
# selection (default: the default selection).
show_catalogue() {
    local key=$1 name n=0 mark ea
    local -a names sel
    shift
    read -r -a names <<<"${cat_names[$key]}"
    if (($#)); then sel=("$@"); else read -r -a sel <<<"${cat_default[$key]:-}"; fi
    for name in "${names[@]}"; do
        n=$((n + 1))
        mark='[ ]' ea=''
        in_list "$name" "${sel[@]}" && mark='[x]'
        [[ -n ${cat_ea[$key:$name]:-} ]] && ea=' [Early Access]'
        printf '    %2d %s %-26s %s%s\n' "$n" "$mark" "$name" "${cat_desc[$key:$name]}" "$ea"
    done
}
# parse_selection <key> <text>: names, numbers of the list, or all (comma or
# space separated), printed in the order of the list; 1 with a message on
# stderr for an unknown entry.
parse_selection() {
    local key=$1 w name i
    local -a names words picked=() out=()
    read -r -a names <<<"${cat_names[$key]}"
    read -r -a words <<<"${2//,/ }"
    ((${#words[@]} > 0)) || {
        printf 'no feature given\n' >&2
        return 1
    }
    for w in "${words[@]}"; do
        if [[ $w == all ]]; then
            picked+=("${names[@]}")
        elif [[ $w =~ ^[0-9]+$ ]] && ((10#$w >= 1 && 10#$w <= ${#names[@]})); then
            picked+=("${names[10#$w - 1]}")
        elif in_list "$w" "${names[@]}"; then
            picked+=("$w")
        else
            printf "unknown feature '%s' for the %s (one of: %s; a number of the list; or all)\n" \
                "$w" "${D[$key:title]}" "$(csv "${names[@]}")" >&2
            return 1
        fi
    done
    for i in "${names[@]}"; do in_list "$i" "${picked[@]}" && out+=("$i"); done
    printf '%s\n' "${out[*]}"
}

usage() {
    local key
    cat <<USAGE
Usage: scripts/setup.sh [--sdk LIST] [--features-KEY LIST]... [--dry-run]

Guided setup of the local Maxine SDK packages: preflight checks, the optional
downloads of each SDK, your NGC download, configure.sh, makepkg,
installation, the features added after the install, a check of the
installation, and the commands to undo it.

  --sdk LIST           $(csv "${sdk_keys[@]}") (comma separated) or all; without it the
                       script asks for each SDK (default answer: no)
  --features-KEY LIST  the optional downloads of one SDK (KEY as in --sdk),
                       comma separated: names from the lists below, their
                       numbers, or all. Without it the script shows the list
                       and asks: numbers or names, all, or Enter for the
                       default (marked [x]). A dry run takes the default.
  --dry-run            read-only: run the checks and detection, ask nothing,
                       change nothing, and print every command it would run
                       (alias: --print-commands)
  -h, --help           this help

The optional downloads are fetched before the build by the recipe's
download.sh --features LIST, together with the SDK, so the package holds them
and pacman owns them. configure.sh then packages everything in the download.
USAGE
    for key in "${sdk_keys[@]}"; do
        [[ -n ${cat_names[$key]:-} ]] || continue
        printf '\n  --features-%s (%s, from %s/%s):\n' "$key" "${D[$key:title]}" \
            "${D[$key:package]}" "${D[$key:catalogue]}"
        show_catalogue "$key"
    done
    cat <<USAGE

Every question defaults to no. Nothing that changes the system runs without
a yes: sudo is used only for \`pacman -U <package>\`, for copying features
added after the install into the installed tree (cp -R
--no-preserve=ownership, so the copy is owned by root; only the feature
directories asked for, from a new download directory, never a directory
pacman owns), and for removing such copied directories when a newer
package holds them (rm -r, before pacman -U would stop on them). The script never
runs \`ngc config\`, never reads ~/.ngc, never runs \`makepkg -i\`/\`-s\` or
\`pacman -R\`; the undo commands are printed, not run. nvidia-smi is queried
once, which wakes a sleeping discrete GPU.

An Audio Effects effect not in the installed package (chosen after its
install) is fetched by NVIDIA's own features/download_features.sh, which
needs an NGC API key in NGC_API_KEY. The key is taken from the environment
when NGC_API_KEY is set, else asked for without echo. This script never
prints, logs or stores it and never puts it on a command line; it hands it
only to that one script, in its environment. NVIDIA's script itself passes
the key to curl or wget on their command line (visible in the process list
while it runs), which this script cannot prevent.

Environment:
  MAXINE_SETUP_ROOT   prefix for /opt and /usr/share (for tests; empty)
  NGC_API_KEY         the key for NVIDIA's download_features.sh
  <PREFIX>_SRC        a download directory, as for configure.sh and makepkg
                      ($(for key in "${sdk_keys[@]}"; do printf '%s_SRC\n' "${D[$key:env_prefix]}"; done | paste -sd ' '))

The SDKs are described in scripts/setup.d/ (format: scripts/setup.d/README).
Documentation: README.md, docs/download.md, docs/usage.md
USAGE
}

dry_run=0 sdk_arg=''
declare -A features_arg=()
while (($#)); do
    case $1 in
        --sdk | --features-*)
            (($# >= 2)) || usage_error "option $1 needs a value"
            if [[ $1 == --sdk ]]; then
                sdk_arg=$2
            else
                key=${1#--features-}
                in_list "$key" "${sdk_keys[@]}" || usage_error "unknown option $1 (no SDK '$key')"
                [[ -n ${cat_names[$key]:-} ]] || usage_error "the ${D[$key:title]} has no optional downloads"
                features_arg[$key]=$2
            fi
            shift 2
            ;;
        --dry-run | --print-commands) dry_run=1 && shift ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) usage_error "unknown argument: $1" ;;
    esac
done

# ask <question>: y/N on stderr, the answer from stdin; 0 for yes. The
# default (an empty line, end of input) is no. A dry run never asks.
ask() {
    local answer=''
    ((!dry_run)) || return 1
    printf '%s [y/N] ' "$1" >&2
    IFS= read -r answer || true
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

# The packages: read from each PKGBUILD as text (never sourced).
declare -A pkgname=() pkgver=() pkgrel=() pkgurl=() pkgarch=()
# pkgbuild_value <file> <key>: a NAME=value line of a PKGBUILD, unquoted.
pkgbuild_value() {
    sed -n "s/^$2=//p" "$1" | head -n 1 | sed "s/^[('\"]*//; s/[)'\"]*\$//"
}
for key in "${sdk_keys[@]}"; do
    pb=$repo/${D[$key:package]}/PKGBUILD
    [[ -f $pb ]] || die "$pb not found: run this script from a clone of the repository"
    pkgname[$key]=$(pkgbuild_value "$pb" pkgname)
    pkgver[$key]=$(pkgbuild_value "$pb" pkgver)
    pkgrel[$key]=$(pkgbuild_value "$pb" pkgrel)
    pkgurl[$key]=$(pkgbuild_value "$pb" url)
    pkgarch[$key]=$(pkgbuild_value "$pb" arch)
    [[ ${pkgname[$key]} =~ ^[a-z0-9-]+$ && ${pkgver[$key]} =~ ^[0-9.]+$ && ${pkgrel[$key]} =~ ^[0-9]+$ ]] ||
        die "cannot read pkgname, pkgver and pkgrel from $pb"
    [[ -n ${pkgarch[$key]} ]] || pkgarch[$key]=$(uname -m)
done

# The SDKs to set up: --sdk, else asked after the preflight.
chosen=()
if [[ -n $sdk_arg ]]; then
    read -r -a words <<<"${sdk_arg//,/ }"
    ((${#words[@]} > 0)) || usage_error "--sdk needs at least one of $(csv "${sdk_keys[@]}") or all"
    for w in "${words[@]}"; do
        if [[ $w == all ]]; then
            chosen=("${sdk_keys[@]}")
        elif in_list "$w" "${sdk_keys[@]}"; then
            in_list "$w" "${chosen[@]}" || chosen+=("$w")
        else
            usage_error "unknown SDK '$w' ($(csv "${sdk_keys[@]}") or all)"
        fi
    done
    ordered=()
    for key in "${sdk_keys[@]}"; do in_list "$key" "${chosen[@]}" && ordered+=("$key"); done
    chosen=("${ordered[@]}")
fi
# The selections of optional downloads: selection[<key>], space separated.
declare -A selection=()
for key in "${!features_arg[@]}"; do
    sel_text=$(parse_selection "$key" "${features_arg[$key]}" 2>&1) || usage_error "--features-$key: $sel_text"
    selection[$key]=$sel_text
done

((dry_run)) && say "Dry run: read-only; nothing is asked, run or written. The commands are printed."

# 1. Preflight (read-only): explains what is missing, fixes nothing.
say ""
say "== 1. Preflight (read-only)"
blockers=0
if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null 2>&1; then
    say "  Arch Linux: yes"
else
    say "  Arch Linux: no (/etc/arch-release and pacman not found): these packages are for Arch Linux"
fi
if command -v pacman >/dev/null 2>&1; then
    if pacman -Q base-devel >/dev/null 2>&1; then
        say "  base-devel: installed"
    else
        warn "base-devel is not installed (makepkg needs it): sudo pacman -S --needed base-devel"
    fi
else
    printf '%s: pacman not found: this script and the packages need Arch Linux with pacman\n' "$prog" >&2
    blockers=1
fi
if command -v makepkg >/dev/null 2>&1; then
    say "  makepkg: $(command -v makepkg)"
else
    printf '%s: makepkg not found: install it with: sudo pacman -S --needed base-devel\n' "$prog" >&2
    blockers=1
fi
for tool in fakeroot:fakeroot bsdtar:libarchive; do
    if command -v "${tool%%:*}" >/dev/null 2>&1; then
        say "  ${tool%%:*}: found"
    else
        warn "${tool%%:*} not found (makepkg needs it): sudo pacman -S --needed ${tool#*:}"
    fi
done
((blockers == 0)) || exit 1

archs=() # the detected architectures, sm_<N>
if command -v nvidia-smi >/dev/null 2>&1; then
    smi_rc=0
    smi_out=$(nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>&1) || smi_rc=$?
    if ((smi_rc != 0)); then
        warn "nvidia-smi failed ($(head -n 1 <<<"$smi_out")): is the NVIDIA driver (nvidia-utils) loaded?"
    else
        while IFS= read -r line; do
            [[ -n ${line//[[:space:]]/} ]] || continue
            cap=${line##*,} rest=${line%,*}
            driver=${rest##*,} name=${rest%,*}
            cap=${cap//[[:space:]]/} driver=${driver//[[:space:]]/}
            if [[ ! $cap =~ ^([1-9][0-9]?)\.([0-9])$ ]]; then
                say "  GPU: $name, driver $driver, compute capability '$cap' not understood"
                continue
            fi
            n=${BASH_REMATCH[1]}${BASH_REMATCH[2]}
            say "  GPU: $name, driver $driver, compute capability $cap -> sm_$n"
            if ((n < 75)); then
                warn "$name (sm_$n) is not supported: the SDKs need Turing (sm_75) or newer"
                continue
            fi
            in_list "sm_$n" "${archs[@]}" || archs+=("sm_$n")
            if [[ $driver =~ ^[0-9]+(\.[0-9]+)*$ && $(printf '%s\n' 570.26 "$driver" | sort -V | head -n 1) != 570.26 ]]; then
                warn "driver $driver is older than 570.26, which the SDKs need: update nvidia-utils"
            fi
        done <<<"$smi_out"
    fi
else
    warn "nvidia-smi not found (it comes with the NVIDIA driver, nvidia-utils): the GPU architecture cannot be detected"
fi
archs_csv=$(csv "${archs[@]}")
if ((${#archs[@]} > 0)); then
    say "  Architectures to package: ${archs[*]}"
else
    warn "no supported GPU detected: configure.sh needs --archs sm_<N> from you (docs/gpu-support.md)"
fi

# free_kib <dir>: free KiB on the file system of the dir, or its nearest
# existing parent.
free_kib() {
    local d=$1
    while [[ ! -e $d && $d != / ]]; do d=$(dirname -- "$d"); done
    df -Pk -- "$d" 2>/dev/null | awk 'NR == 2 { print $4 }'
}
dl_base=$HOME/Downloads/maxine
dl_need=$((3 * 1048576))           # the default VFX download, about 2.75 GiB
build_need=$((132 * 1048576 / 10)) # tree in src/, its copy in pkg/, the package: 3 x 4.4 GiB
free=$(free_kib "$dl_base")
if [[ $free =~ ^[0-9]+$ ]]; then
    say "  Disk, download directory ($dl_base): $(gib "$free") free"
    ((free >= dl_need)) ||
        warn "less than 3 GiB free for the download in $dl_base: the default Video Effects download is about 2.75 GiB"
fi
free=$(free_kib "$repo")
if [[ $free =~ ^[0-9]+$ ]]; then
    say "  Disk, build directory ($repo): $(gib "$free") free"
    ((free >= build_need)) ||
        warn "less than 13.2 GiB free in $repo: a build holds the SDK tree (about 4.4 GiB) in src/, makepkg's copy of it in pkg/ and the package (about 4.4 GiB); each further SDK needs about as much"
fi
if command -v ngc >/dev/null 2>&1; then
    say "  NGC CLI: $(command -v ngc) (used only by download.sh, with your own configuration)"
else
    say "  NGC CLI: not found. It is needed only to download with download.sh: docs/download.md#3-install-the-ngc-cli"
fi

if ((${#chosen[@]} == 0)); then
    if ((dry_run)); then
        chosen=("${sdk_keys[@]}")
    else
        say ""
        for key in "${sdk_keys[@]}"; do
            ask "Set up the ${D[$key:title]} (${pkgname[$key]} ${pkgver[$key]}-${pkgrel[$key]})?" && chosen+=("$key")
        done
    fi
fi
if ((${#chosen[@]} == 0)); then
    say "No SDK chosen: nothing to do."
    exit 0
fi

# choose_features <key>: the selection of optional downloads (from
# --features-<key>, else asked; a dry run and an empty answer take the
# default).
choose_features() {
    local key=$1 answer text
    local -a sel
    [[ -n ${cat_names[$key]:-} ]] || return 0
    say "  -- Optional downloads of the ${D[$key:title]} ([x]: $([[ -n ${features_arg[$key]:-} ]] && echo "--features-$key" || echo "the default"))"
    if [[ -n ${features_arg[$key]:-} ]]; then
        read -r -a sel <<<"${selection[$key]}"
        show_catalogue "$key" "${sel[@]}"
    else
        show_catalogue "$key"
        selection[$key]=${cat_default[$key]:-}
        if ((!dry_run)); then
            while :; do
                printf 'Optional downloads (numbers or names, all, Enter for the default): ' >&2
                answer=''
                if ! IFS= read -r answer; then
                    printf '\n' >&2
                    break
                fi
                [[ -n ${answer//[[:space:],]/} ]] || break
                if text=$(parse_selection "$key" "$answer"); then
                    selection[$key]=$text
                    break
                fi
            done
        fi
    fi
    if [[ -n ${selection[$key]} ]]; then
        say "  Selected: ${selection[$key]// /, }"
    else
        say "  Selected: none"
    fi
}

# installed_version <key>: the version pacman reports, or nothing.
installed_version() {
    local out
    out=$(pacman -Q "${pkgname[$1]}" 2>/dev/null) || return 0
    printf '%s\n' "${out#* }"
}
# conf_src <key>: <prefix>_SRC of the recipe's selection.conf, parsed by its
# own selection.sh (a repository file that only defines functions; the
# selection.conf is never run).
conf_src() {
    local key=$1 dir=$repo/${D[$1:package]} p
    p=${D[$key:env_prefix],,}
    (
        # shellcheck source=/dev/null
        . "$dir/selection.sh"
        "${p}_read_selection" "$dir/selection.conf" || exit 1
        v=${p}_file_src
        printf '%s\n' "${!v}"
    )
}
# find_pkg <key>: the newest built package of this version, or nothing.
find_pkg() {
    local key=$1 f best=''
    local -a files
    shopt -s nullglob
    files=("$repo/${D[$key:package]}/${pkgname[$key]}-${pkgver[$key]}-${pkgrel[$key]}-"*.pkg.tar*)
    shopt -u nullglob
    for f in "${files[@]}"; do
        [[ $f == *.sig ]] && continue
        [[ -z $best || $f -nt $best ]] && best=$f
    done
    [[ -z $best ]] || printf '%s\n' "$best"
}
# check_md5 <dir> <glob>: every checksum file matching the glob below the
# dir against the file it names (its own name without the last extension);
# sets md5_bad (one line per bad file) and md5_count.
md5_bad=() md5_count=0
check_md5() {
    local sidecar model want got
    md5_bad=() md5_count=0
    while IFS= read -r -d '' sidecar; do
        model=${sidecar%.*}
        if [[ ! -f $model ]]; then
            md5_bad+=("$model is missing (its checksum file $sidecar is there)")
            continue
        fi
        want=$(head -c 32 -- "$sidecar")
        got=$(md5sum <"$model")
        got=${got%% *}
        if [[ ! $want =~ ^[0-9a-fA-F]{32}$ ]]; then
            md5_bad+=("$sidecar does not begin with an MD5 checksum")
        elif [[ ${got,,} != "${want,,}" ]]; then
            md5_bad+=("$model does not match ${sidecar##*/} (MD5 $got, expected ${want,,})")
        else
            md5_count=$((md5_count + 1))
        fi
    done < <(find -H "$1" -type f -name "$2" -print0 2>/dev/null | LC_ALL=C sort -z)
    ((${#md5_bad[@]} == 0))
}
# present_table: the "1. Present in the" section of a configure.sh report
# (stdin) as one line per feature: the feature, then its architectures and
# sample rates. configure.sh prints a download, and an Audio Effects tree,
# one line per feature ("<feature> <archs> [<rates>]"); a Video Effects or
# AR tree as "features <f>..." and "models <archs> (...)" for the tree as a
# whole, which gives each feature the tree's architectures here.
present_table() {
    awk '
        /^1\. Present in the SDK tree:$/ { on = 1; tree = 1; next }
        /^1\. Present in the/ { on = 1; next }
        !on { next }
        /^[[:space:]]*$/ { exit }
        tree && $1 == "features" {
            for (i = 2; i <= NF; i++) { if ($i == "none") break; feats[++n] = $i }
            next
        }
        tree && $1 == "models" {
            for (i = 2; i <= NF; i++) if ($i ~ /^sm_[0-9]+$/) archs = archs " " $i
            next
        }
        tree || $1 == "no" { next }
        { $1 = $1; print }
        END { for (i = 1; i <= n; i++) print feats[i] archs }'
}
# validate <key> <dir>: 0 when configure.sh accepts the download (offline)
# and every checksum matches; else v_reason says why. v_present holds what
# it holds (present_table), v_layout configure.sh's layout (download or
# tree).
v_reason='' v_missing=0 v_present='' v_layout=''
validate() {
    local key=$1 dir=$2 out
    v_reason='' v_missing=0 v_present='' v_layout=''
    if [[ ! -d $dir ]]; then
        v_reason="the directory $dir does not exist" v_missing=1
        return 1
    fi
    if ! out=$("$repo/${D[$key:package]}/${D[$key:configure]}" --src "$dir" 2>&1); then
        if grep -q 'no Maxine .* SDK found in' <<<"$out"; then
            v_reason="no SDK core in $dir" v_missing=1
            return 1
        fi
        v_reason="configure.sh cannot use it: $(grep -m 1 -i 'configure.sh\|assemble.sh\|error' <<<"$out" || head -n 1 <<<"$out")"
        return 1
    fi
    v_present=$(present_table <<<"$out")
    v_layout=$(awk '$1 == "layout" { print $2; exit }' <<<"$out")
    if ! check_md5 "$dir" "${D[$key:checksum_glob]}"; then
        v_reason="bad checksum(s):"
        local x
        for x in "${md5_bad[@]}"; do v_reason+=$'\n'"      $x"; done
        v_reason+=$'\n'"    Delete each file named above and run download.sh again (it fetches only what is missing)."
        return 1
    fi
    return 0
}
# in_present <table> <name>: 0 when the table (present_table) holds the
# optional download <name> (<feature> or <feature>-<rate>): a line of the
# feature with the rate, and with a detected architecture when the line
# names any.
in_present() {
    local table=$1 e=$2 f rate='' line a has_arch
    local -a w
    f=${e%%-*}
    [[ $e == *-* ]] && rate=${e#*-}
    while IFS= read -r line; do
        read -r -a w <<<"$line"
        ((${#w[@]} > 0)) && [[ ${w[0]} == "$f" ]] || continue
        [[ -z $rate ]] || in_list "$rate" "${w[@]:1}" || return 1
        has_arch=0
        for a in "${w[@]:1}"; do [[ $a == sm_* ]] && has_arch=1; done
        ((has_arch && ${#archs[@]} > 0)) || return 0
        for a in "${archs[@]}"; do in_list "$a" "${w[@]:1}" && return 0; done
        return 1
    done <<<"$table"
    return 1
}
in_download() { in_present "$v_present" "$1"; } # in_download <name>: in the last validated download
present_features() { # present_features: the features of the last validated download
    awk 'NF { print $1 }' <<<"$v_present"
}
download_cmd() { # download_cmd <key> <dir> [name...]: download.sh's argv
    local key=$1 dir=$2
    shift 2
    dl_argv=("$repo/${D[$key:package]}/download.sh" --dest "$dir")
    (($#)) && dl_argv+=(--features "$(csv "$@")")
    return 0
}
manual_steps() { # manual_steps <key> <dir> [name...]
    local key=$1
    cat <<EOF
  To get the ${D[$key:title]} ${pkgver[$key]}, do this yourself (this script never does it for you):
    1. Create or log in to your NVIDIA Developer Program account (a plain NGC account is not enough).
    2. Open ${pkgurl[$key]}
       log in, select "Get Access" under "NVIDIA Developer Program" and accept NVIDIA's licence.
    3. Generate a personal API key (include the NGC Catalog service):
       https://org.ngc.nvidia.com/setup/personal-keys
    4. Install the NGC CLI: $repo/docs/download.md#3-install-the-ngc-cli
    5. Run \`ngc config set\` yourself and paste the key there. This script never runs it
       and never reads ~/.ngc.
  Then download it with the optional downloads you selected:
EOF
    download_cmd "$@"
    show_cmd "$(cmdline "${dl_argv[@]}")"
    say "  or by hand, with the ngc commands in $repo/${D[$key:byhand_doc]}"
}

declare -A state=()        # per SDK: installed, would-install, or why it stopped
declare -A dl_packaged=()  # per SDK: the features the download holds (what the build packages)
declare -A dl_present=()   # per SDK: what the download holds, as present_table lines
dl_argv=()
src='' src_from=''
# sdk_src <key>: sets src and src_from: <prefix>_SRC from the environment,
# else the selection.conf's, else the default directory.
sdk_src() {
    local key=$1 var=${D[$1:env_prefix]}_SRC conf=$repo/${D[$1:package]}/selection.conf
    if [[ -n ${!var:-} ]]; then
        src=${!var} src_from="the environment ($var)"
    elif src=$(conf_src "$key" 2>/dev/null) && [[ -n $src ]]; then
        src_from=$conf
    else
        [[ -e $conf ]] && warn "$conf is not valid; looking in the default directory"
        src=$(home_path "${D[$key:default_src]}") src_from="the default directory"
    fi
    return 0
}
build_line() { printf '(cd %s && PKGEXT=.pkg.tar makepkg -f)\n' "$(q "$repo/${D[$1:package]}")"; } # build_line <key>
# tree_steps <key> <tree> [name...]: an SDK tree is packaged as it is, so
# download.sh cannot add to it: the way to package more is a download
# directory of its own, selected instead of the tree, and a rebuild.
tree_steps() {
    local key=$1 tree=$2 dest
    shift 2
    dest=$(home_path "${D[$key:default_src]}")
    [[ $dest != "$tree" && $dest/ != "$tree"/* && $tree/ != "$dest"/* ]] || dest='<a new empty directory>'
    say "  $tree is an SDK tree, which is packaged as it is: download.sh does not add features to it."
    say "  To package them, fetch the SDK with every feature you want into an NGC download directory"
    say "  of its own, select that directory instead of the tree, and rebuild:"
    download_cmd "$key" "$dest" "$@"
    show_cmd "$(cmdline "${dl_argv[@]}")"
    show_cmd "$(cmdline "$repo/${D[$key:package]}/${D[$key:configure]}" --src "$dest" --archs "${archs_csv:-sm_<N>}" --features all --write)"
    show_cmd "$(build_line "$key")"
}

# unowned_in_the_way <key> <package file>: sets in_the_way to the feature
# directories (of an SDK with feature_lib) that the package installs and
# that exist in the installed model directory without a package owning them.
# Read-only: bsdtar -tf, pacman -Qo.
# pacman_owns <path>: a package owns it (read-only pacman -Qo).
pacman_owns() { pacman -Qo "$1" >/dev/null 2>&1; }
in_the_way=()
unowned_in_the_way() {
    local key=$1 pkgfile=$2 prefix dir entry f list
    local -a feats=()
    in_the_way=()
    [[ -n ${D[$key:feature_lib]:-} && -f $pkgfile ]] || return 0
    prefix=${D[$key:root]#/}/${D[$key:model_dir]}/
    dir=$sys_root${D[$key:root]}/${D[$key:model_dir]}
    if ! list=$(bsdtar -tf "$pkgfile" 2>/dev/null); then
        warn "cannot list $pkgfile with bsdtar: feature directories copied in by hand are not checked (pacman -U names any in its way)"
        return 0
    fi
    while IFS= read -r entry; do
        entry=${entry#./}
        [[ $entry == "$prefix"*/* ]] || continue
        f=${entry#"$prefix"}
        f=${f%%/*}
        [[ -n $f ]] && ! in_list "$f" "${feats[@]}" && feats+=("$f")
    done <<<"$list"
    for f in "${feats[@]}"; do
        [[ -e $dir/$f || -L $dir/$f ]] || continue
        pacman_owns "$dir/$f" || in_the_way+=("$dir/$f")
    done
    return 0
}

# process <key>: steps 2 to 5 for one SDK.
process() {
    local key=$1 expected have conf pkgfile answer
    local pkg_dir=$repo/${D[$key:package]}
    local -a sel missing
    expected=${pkgver[$key]}-${pkgrel[$key]}
    conf=$pkg_dir/selection.conf
    say ""
    say "== ${D[$key:title]}: ${pkgname[$key]} $expected"
    have=$(installed_version "$key")
    if [[ $have == "$expected" ]]; then
        say "  Installed: ${pkgname[$key]} $have, the version this recipe builds. Download, build and install skipped."
        state[$key]=installed
        # Only an SDK that adds features after its install has a use for a
        # selection now; for the others it means a rebuild.
        if [[ -n ${D[$key:post_script]:-} ]]; then
            choose_features "$key"
        elif [[ -n ${cat_names[$key]:-} ]]; then
            say "  To add optional downloads, fetch them and rebuild: $(q "$pkg_dir/download.sh") --features <list>"
        fi
        return 0
    fi
    [[ -z $have ]] || say "  Installed: ${pkgname[$key]} $have; this recipe builds $expected."

    # 2. The download, with the optional downloads selected. changed: this
    # run ran download.sh or wrote the selection (a built package is then
    # out of date).
    sdk_src "$key"
    say "  -- 2. Download: $src (from $src_from)"
    choose_features "$key"
    read -r -a sel <<<"${selection[$key]:-}"
    local shown=0 valid=0 fetched=0 changed=0 name
    while :; do
        if validate "$key" "$src"; then
            valid=1
            say "  The download is valid (configure.sh accepts it; $md5_count checksum(s) match)."
            missing=()
            for name in "${sel[@]}"; do in_download "$name" || missing+=("$name"); done
            ((${#missing[@]} > 0)) || break
            say "  Selected but not in the download: ${missing[*]}"
            if [[ $v_layout == tree ]]; then
                tree_steps "$key" "$src" "${sel[@]}"
                say "  Going on with what the tree holds."
                break
            fi
            if ((fetched)); then
                say "  download.sh did not fetch them (see above); going on with what the download holds."
                break
            fi
            download_cmd "$key" "$src" "${missing[@]}"
            show_cmd "$(cmdline "${dl_argv[@]}")"
            ((dry_run)) && break
            if command -v ngc >/dev/null 2>&1 &&
                ask "Run download.sh now for them (it shows the sizes and asks before downloading)?"; then
                "${dl_argv[@]}" || warn "download.sh did not finish (see above)"
                fetched=1 changed=1
                continue
            fi
            say "  Not fetched: the build packages what the download holds."
            break
        fi
        if ((v_missing)); then
            say "  No ${D[$key:title]} ${pkgver[$key]} download in $src."
        else
            say "  The download in $src is not usable: $v_reason"
        fi
        download_cmd "$key" "$src" "${sel[@]}"
        if ((!shown)); then
            if ((v_missing)); then
                manual_steps "$key" "$src" "${sel[@]}"
            else
                say "  To fetch what is missing again:"
                show_cmd "$(cmdline "${dl_argv[@]}")"
            fi
            shown=1
        fi
        if ((dry_run)); then
            break
        fi
        if command -v ngc >/dev/null 2>&1; then
            if ask "Run download.sh now (it shows the sizes and asks before downloading)?"; then
                "${dl_argv[@]}" || warn "download.sh did not finish (see above)"
                changed=1
                continue
            fi
        else
            say "  (download.sh needs the NGC CLI, which is not on PATH.)"
        fi
        printf 'Press Enter to re-check %s, or s to skip the %s: ' "$src" "${D[$key:title]}" >&2
        answer=''
        if ! IFS= read -r answer || [[ $answer == [sS]* ]]; then
            printf '\n' >&2
            break
        fi
    done
    dl_packaged[$key]=$(present_features | tr '\n' ' ')
    dl_present[$key]=$v_present
    ((valid)) || dl_packaged[$key]="$(for name in "${sel[@]}"; do printf '%s ' "${name%%-*}"; done)"
    if ((!valid && !dry_run)); then
        say "  Skipped the ${D[$key:title]}."
        state[$key]="skipped (no valid download)"
        return 0
    fi
    ((valid)) || say "  (The commands below are for after the download.)"

    # 3. The selection.
    say "  -- 3. Selection (selection.conf)"
    local cfg_cmd=() cfg=$pkg_dir/${D[$key:configure]}
    if ((${#archs[@]} > 0)); then
        cfg_cmd=("$cfg" --src "$src" --archs "$archs_csv" --features all --write)
    fi
    if [[ -f $conf ]]; then
        say "  $conf exists; it is kept unless you replace it:"
        "$cfg" --show 2>&1 | sed 's/^/    /' || true
        if ((${#cfg_cmd[@]} > 0)); then
            if ((dry_run)); then
                say "  To replace it with the detected architectures:"
                show_cmd "$(cmdline "${cfg_cmd[@]}")"
            elif ask "Replace it with --src $src --archs $archs_csv --features all?"; then
                "${cfg_cmd[@]}" || {
                    warn "configure.sh failed (see above); the selection.conf is unchanged"
                    state[$key]="stopped (configure.sh failed)"
                    return 1
                }
                changed=1
            fi
        fi
    elif ((${#cfg_cmd[@]} == 0)); then
        say "  No selection.conf. Without a detected GPU, write it yourself:"
        show_cmd "$(cmdline "$cfg" --src "$src" --archs 'sm_<N>' --features all --write)"
        state[$key]="stopped (no selection.conf)"
        ((dry_run)) || return 0
    else
        show_cmd "$(cmdline "${cfg_cmd[@]}")"
        if ((dry_run)); then
            :
        elif ask "Write $conf with this selection?"; then
            "${cfg_cmd[@]}" || {
                warn "configure.sh failed (see above)"
                state[$key]="stopped (configure.sh failed)"
                return 1
            }
            changed=1
        else
            say "  Not written. Run the command above yourself, then this script again."
            state[$key]="stopped (no selection.conf)"
            return 0
        fi
    fi

    # 4. The build.
    say "  -- 4. Build"
    local build_line build=0 why=''
    build_line=$(build_line "$key")
    pkgfile=$(find_pkg "$key")
    # A built package is reused only when it is current: built after the
    # selection.conf and after everything in the download, in an earlier
    # run that changed neither.
    if [[ -n $pkgfile ]]; then
        if ((changed)); then
            why="this run changed the download or the selection"
        elif [[ -e $conf && $conf -nt $pkgfile ]]; then
            why="$conf is newer"
        elif [[ -d $src && -n $(find -H "$src" -newer "$pkgfile" -print -quit 2>/dev/null) ]]; then
            why="the download in $src has newer files"
        fi
        if [[ -n $why ]]; then
            say "  Out of date: $pkgfile ($why); it is rebuilt."
            pkgfile=''
        fi
    fi
    if [[ -n $pkgfile ]]; then
        say "  Already built: $pkgfile (it is current and reused)."
        if ((dry_run)); then
            say "  To rebuild it:"
            show_cmd "$build_line"
        elif ask "Rebuild it anyway?"; then
            build=1
        fi
    else
        show_cmd "$build_line"
        if ((dry_run)); then
            pkgfile=$pkg_dir/${pkgname[$key]}-$expected-${pkgarch[$key]}.pkg.tar
        elif ask "Build the package now (several GiB, takes a while)?"; then
            build=1
        else
            say "  Not built. Run the command above yourself, then this script again."
            state[$key]="stopped (not built)"
            return 0
        fi
    fi
    if ((build)); then
        if ! (cd -- "$pkg_dir" && PKGEXT=.pkg.tar makepkg -f); then
            warn "makepkg failed (see above); nothing was installed"
            state[$key]="stopped (makepkg failed)"
            return 1
        fi
        pkgfile=$(find_pkg "$key")
        [[ -n $pkgfile ]] || {
            warn "makepkg finished but no ${pkgname[$key]}-$expected-*.pkg.tar* is in $pkg_dir"
            state[$key]="stopped (no package)"
            return 1
        }
        say "  Built: $pkgfile"
    fi
    # 5. The installation. Feature directories copied in by hand that the
    # package now holds are in its way: pacman -U stops with "exists in
    # filesystem" on them, so they are removed first (with a yes).
    say "  -- 5. Install"
    local install_line rm_line=''
    install_line="sudo pacman -U $(q "$pkgfile")"
    unowned_in_the_way "$key" "$pkgfile"
    if ((${#in_the_way[@]} > 0)); then
        say "  Not owned by any package, and in the package now (copied in after an earlier install):"
        say "  pacman -U would stop with \"exists in filesystem\". Remove them first:"
        rm_line=$(cmdline sudo rm -r -- "${in_the_way[@]}")
        show_cmd "$rm_line"
    fi
    show_cmd "$install_line"
    if ((dry_run)); then
        state[$key]=would-install
        return 0
    fi
    if [[ -n $rm_line ]]; then
        if ask "Remove ${in_the_way[*]} with sudo (the package installs them again)?"; then
            sudo rm -r -- "${in_the_way[@]}" || {
                warn "the removal failed (see above); nothing was installed"
                state[$key]="stopped (rm failed)"
                return 1
            }
        else
            say "  Not removed, so not installed. Run both commands yourself:"
            show_cmd "$rm_line"
            show_cmd "$install_line"
            state[$key]="built, not installed (unowned feature directories in the way)"
            return 0
        fi
    fi
    if ask "Install it now with sudo?"; then
        if sudo pacman -U "$pkgfile"; then
            state[$key]=installed
            return 0
        fi
        warn "pacman -U failed (see above)"
        state[$key]="stopped (pacman -U failed)"
        return 1
    fi
    say "  Not installed. Install it yourself:"
    show_cmd "$install_line"
    state[$key]="built, not installed"
    return 0
}

failures=0
for key in "${chosen[@]}"; do
    process "$key" || failures=$((failures + 1))
done

# The environment files are parsed as KEY=value text.
env_value() { # env_value <file> <key>
    local line
    [[ -f $1 ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ $line == "$2="* ]]; then
            printf '%s\n' "${line#*=}"
            return 0
        fi
    done <"$1"
    return 1
}
env_path() { printf '%s\n' "$sys_root${D[$1:env_file]}"; } # env_path <key>
# sdk_model_dir <key>: the installed model directory (the env file's
# <prefix>_<model_dir_var>, else root/model_dir).
sdk_model_dir() {
    local key=$1 d='' root
    [[ -n ${D[$key:model_dir_var]:-} ]] &&
        d=$(env_value "$(env_path "$key")" "${D[$key:env_prefix]}_${D[$key:model_dir_var]}" || true)
    if [[ -z $d ]]; then
        root=$(env_value "$(env_path "$key")" "${D[$key:env_prefix]}_ROOT" || true)
        [[ -n $root ]] || root=$sys_root${D[$key:root]}
        d=$root/${D[$key:model_dir]}
    fi
    printf '%s\n' "$d"
}
feature_lib() { local p=${D[$1:feature_lib]}; printf '%s\n' "${p//\{feature\}/$2}"; } # feature_lib <key> <feature>
catalogue_features() { # catalogue_features <key>: the features of the optional downloads
    local name
    local -a names out=()
    read -r -a names <<<"${cat_names[$1]:-}"
    for name in "${names[@]}"; do in_list "${name%%-*}" "${out[@]}" || out+=("${name%%-*}"); done
    printf '%s\n' "${out[*]}"
}

# model_rates <dir>: the sample rates the models below the dir carry in
# their names (an underscore-delimited 48k, 16k or 16k_to_48k, as
# assemble.sh reads them), one per line.
model_rates() {
    local file name
    while IFS= read -r -d '' file; do
        name=${file##*/}
        [[ $name =~ (^|_)([0-9]+k(_to_[0-9]+k)?)(_|\.trtpkg$) ]] && printf '%s\n' "${BASH_REMATCH[2]}"
    done < <(find -H "$1" -type f -name '*.trtpkg' -print0 2>/dev/null)
    return 0
}
# has_effect <dir> <name>: the feature directory of the effect <name>
# (<feature> or <feature>-<rate>) is in the dir, with models of its rate.
has_effect() {
    local f=${2%%-*} rate=''
    [[ $2 == *-* ]] && rate=${2#*-}
    [[ -d $1/$f ]] || return 1
    [[ -z $rate ]] || grep -qxF -- "$rate" <<<"$(model_rates "$1/$f")"
}

# 6. Features added after the install (an SDK with a post_script: NVIDIA's
# own script in the installed tree, which needs an NGC API key). It is
# compared per effect (feature and rate). An effect whose feature is in the
# package but whose rate is not cannot be added here: the feature's
# directory is pacman's, so it goes the packaged way (download.sh, rebuild).
post_step() { # post_step <key>
    local key=$1 name f fdir out script rc w
    local -a sel packaged rates=() effects=() features=() args=() rebuild=()
    fdir=$(sdk_model_dir "$key")
    out=$(home_path "${D[$key:post_out]}")
    script=${D[$key:post_script]}
    read -r -a sel <<<"${selection[$key]:-}"
    local P=${D[$key:env_prefix]}
    if [[ ${state[$key]} == installed ]]; then
        IFS=, read -r -a packaged <<<"$(env_value "$(env_path "$key")" "${P}_FEATURES" || true)"
        IFS=, read -r -a rates <<<"$(env_value "$(env_path "$key")" "${P}_RATES" || true)"
    else
        read -r -a packaged <<<"${dl_packaged[$key]:-}"
    fi
    for name in "${sel[@]}"; do
        f=${name%%-*}
        if in_list "$f" "${packaged[@]}"; then
            if [[ ${state[$key]} == installed ]]; then
                [[ $name != *-* ]] && continue
                # (an env file without <prefix>_RATES: the models alone)
                { ((${#rates[@]} == 0)) || in_list "${name#*-}" "${rates[@]}"; } && has_effect "$fdir" "$name" && continue
            else
                in_present "${dl_present[$key]:-}" "$name" && continue
            fi
            rebuild+=("$name")
            continue
        fi
        has_effect "$fdir" "$name" && continue
        effects+=("$name")
        in_list "$f" "${features[@]}" || features+=("$f")
    done
    say ""
    say "== 6. ${D[$key:title]}: features added after the install"
    if ((${#rebuild[@]} > 0)); then
        say "  In the package, but not at this sample rate: ${rebuild[*]}"
        say "  Their feature directories belong to the package (pacman owns them), so they are not"
        say "  added after the install: fetch them before the build and rebuild the package:"
        sdk_src "$key"
        download_cmd "$key" "$src" "${rebuild[@]}"
        show_cmd "$(cmdline "${dl_argv[@]}")"
        show_cmd "$(build_line "$key")"
        show_cmd "sudo pacman -U $(q "$repo/${D[$key:package]}/${pkgname[$key]}-${pkgver[$key]}-${pkgrel[$key]}-${pkgarch[$key]}.pkg.tar")"
    fi
    if ((${#effects[@]} == 0)); then
        ((${#rebuild[@]} > 0)) && return 0
        say "  Every selected feature is in the package or already present under $fdir: nothing to do."
        return 0
    fi
    say "  Not in the package: ${effects[*]}"
    cat <<TEXT
  NVIDIA's own $script in $fdir fetches them with an NGC API key (in
  NGC_API_KEY), into a new directory below $out
  each time. Early Access effects may need NVIDIA's approval of your NGC
  account. Only their feature directories are copied into the installed
  tree, which pacman does not own: the undo commands at the end name them.
  To have them packaged instead, fetch them with download.sh --features
  before the build.
TEXT
    local -a post_words
    read -r -a post_words <<<"${D[$key:post_args]:-}"
    # post_argv <out>: args, with {out} the given directory
    post_argv() {
        args=()
        for w in "${post_words[@]}"; do
            w=${w//\{list\}/$(csv "${effects[@]}")}
            args+=("${w//\{out\}/$1}")
        done
    }
    # copy_argv <dir>: the copy of the requested feature directories only
    copy_argv() {
        copy=(sudo cp -R --no-preserve=ownership --)
        for f in "${features[@]}"; do copy+=("$1/$f"); done
        copy+=("$fdir/")
    }
    # The commands by hand, with "$dir" a new directory below post_out.
    local dl_line copy_line run_dir
    local -a copy
    post_argv @DIR@
    dl_line="(cd $(q "$fdir") && NGC_API_KEY=<your key> ./$(cmdline "$script" "${args[@]}"))"
    copy_argv @DIR@
    copy_line=$(cmdline "${copy[@]}")
    show_cmd "mkdir -p $(q "$out") && dir=\$(mktemp -d $(q "$out")/run.XXXXXX)"
    show_cmd "${dl_line//@DIR@/\"\$dir\"}"
    show_cmd "${copy_line//@DIR@/\"\$dir\"}"
    ((dry_run)) && return 0
    [[ -x $fdir/$script ]] || {
        warn "$fdir/$script not found or not executable: is ${pkgname[$key]} installed?"
        return 1
    }
    # Never into a directory pacman owns (defence in depth: a packaged
    # feature is never in effects).
    for f in "${features[@]}"; do
        if in_list "$f" "${packaged[@]}" || { [[ -e $fdir/$f ]] && pacman_owns "$fdir/$f"; }; then
            warn "$fdir/$f belongs to the package: it is not changed after the install; nothing was downloaded"
            return 1
        fi
    done
    ask "Download ${features[*]} with NVIDIA's $script now?" || {
        say "  Skipped. Run the commands above yourself when you want them."
        return 0
    }
    if [[ $- == *x* ]]; then
        warn "xtrace (bash -x or set -x) is on: it would print the key; run the script without it for this step. Nothing was downloaded."
        return 1
    fi
    local ngc_key=''
    if [[ -n $env_key ]]; then
        say "  Using the key in NGC_API_KEY from the environment."
        ngc_key=$env_key
    else
        printf 'NGC API key (not shown; Enter alone skips): ' >&2
        IFS= read -rs ngc_key || true
        printf '\n' >&2
    fi
    if [[ -z $ngc_key ]]; then
        say "  No key: skipped."
        return 0
    fi
    mkdir -p -- "$out"
    run_dir=$(mktemp -d -- "$out/run.XXXXXX") || {
        ngc_key=''
        warn "cannot create a download directory in $out"
        return 1
    }
    post_argv "$run_dir"
    copy_argv "$run_dir"
    rc=0
    (
        NGC_API_KEY=$ngc_key
        export NGC_API_KEY
        cd -- "$fdir" && "./$script" "${args[@]}"
    ) || rc=$?
    ngc_key=''
    unset ngc_key
    if ((rc != 0)); then
        warn "$script failed (status $rc, see above); nothing was copied (its download: $run_dir)"
        return 1
    fi
    if ! check_md5 "$run_dir" "${D[$key:checksum_glob]}"; then
        printf '%s: %s\n' "$prog" "${md5_bad[@]}" >&2
        warn "bad checksum in $run_dir: delete it and download again; nothing was copied"
        return 1
    fi
    for f in "${features[@]}"; do
        [[ -d $run_dir/$(feature_lib "$key" "$f") ]] || {
            warn "$script left no $run_dir/$(feature_lib "$key" "$f"); nothing was copied"
            return 1
        }
    done
    say "  Downloaded into $run_dir ($md5_count remaining checksum(s) verified)."
    show_cmd "$(cmdline "${copy[@]}")"
    if ask "Copy ${features[*]} into $fdir with sudo (owned by root)?"; then
        "${copy[@]}" || {
            warn "the copy failed (see above)"
            return 1
        }
        rm -rf -- "$run_dir"
    else
        say "  Not copied. Copy them yourself (the command above), then remove $run_dir."
    fi
}
for key in "${chosen[@]}"; do
    [[ -n ${D[$key:post_script]:-} ]] || continue
    case ${state[$key]:-} in
        installed | would-install) post_step "$key" || failures=$((failures + 1)) ;;
        *) say "" && say "== 6. ${D[$key:title]}: features added after the install: skipped (${pkgname[$key]} is not installed)" ;;
    esac
done

# 7. Verify (read-only).
declare -A row=()
notes=()
verify() { # verify <key>: sets row[$key]
    local key=$1 have envf libpath root corelib d out lib_ok=ok ldd_ok=ok model_ok=ok
    local P=${D[$key:env_prefix]} f n mdir glob g
    have=$(installed_version "$key")
    if [[ -z $have ]]; then
        row[$key]=$(printf '%-6s %-32s %-6s %-8s %-6s %s' "$key" "not installed" - - - -)
        return 0
    fi
    envf=$(env_path "$key")
    if [[ ! -f $envf ]]; then
        row[$key]=$(printf '%-6s %-32s %-6s %-8s %-6s %s' "$key" "${pkgname[$key]} $have" MISSING - - -)
        notes+=("$key: $envf is missing: reinstall the package")
        return 1
    fi
    libpath=$(env_value "$envf" "${P}_LIBRARY_PATH" || true)
    root=$(env_value "$envf" "${P}_ROOT" || true)
    [[ -n $root ]] || root=$sys_root${D[$key:root]}
    mdir=$(sdk_model_dir "$key")
    local -a dirs packaged optional_features=() want=("${archs[@]}") pkg_archs features
    IFS=, read -r -a packaged <<<"$(env_value "$envf" "${P}_FEATURES" || true)"
    if [[ -n ${D[$key:feature_lib]:-} ]]; then
        read -r -a features <<<"$(catalogue_features "$key")"
        for f in "${features[@]}"; do in_list "$f" "${packaged[@]}" || optional_features+=("$f"); done
    fi
    IFS=: read -r -a dirs <<<"$libpath"
    ((${#dirs[@]} > 0)) || { lib_ok=MISSING && notes+=("$key: no ${P}_LIBRARY_PATH in $envf"); }
    for d in "${dirs[@]}"; do
        [[ -d $d ]] && continue
        local opt=''
        for f in "${optional_features[@]}"; do
            [[ $d == "$mdir/$(feature_lib "$key" "$f")" ]] && opt=$f
        done
        if [[ -n $opt ]]; then
            notes+=("$key: $d is not there (optional feature $opt, not in the package; see step 6)")
        else
            lib_ok=MISSING
            notes+=("$key: $d (on the library path) does not exist")
        fi
    done
    corelib=$root/${D[$key:core_lib]}
    if [[ ! -f $corelib ]]; then
        ldd_ok=MISSING
        notes+=("$key: $corelib does not exist")
    elif ! out=$(LD_LIBRARY_PATH=$libpath ldd "$corelib" 2>&1); then
        ldd_ok=FAILED
        notes+=("$key: ldd $corelib failed: $(head -n 1 <<<"$out")")
    elif grep -q 'not found' <<<"$out"; then
        ldd_ok=FAILED
        while IFS= read -r d; do notes+=("$key: ldd $corelib:${d}"); done < <(grep 'not found' <<<"$out")
    fi
    IFS=, read -r -a pkg_archs <<<"$(env_value "$envf" "${P}_ARCHS" || true)"
    glob=${D[$key:model_glob]}
    # The models: per feature (packaged ones, and the optional ones that are
    # there) when the glob names {feature}, per architecture when it names
    # {arch}; else once, and the packaged architectures must cover the GPU.
    local -a check_features=('')
    if [[ $glob == *'{feature}'* ]]; then
        check_features=("${packaged[@]}")
        for f in "${optional_features[@]}"; do [[ -d $mdir/$f ]] && check_features+=("$f"); done
    fi
    ((${#want[@]} > 0)) || want=("${pkg_archs[@]}")
    for f in "${check_features[@]}"; do
        [[ $glob == *'{feature}'* && -z $f ]] && continue
        local optional=0
        in_list "$f" "${optional_features[@]}" && optional=1
        if [[ $glob == *'{arch}'* ]]; then
            for n in "${want[@]}"; do
                g=${glob//\{feature\}/$f}
                g=${g//\{arch\}/$n}
                compgen -G "$mdir/$g" >/dev/null && continue
                if ((optional)); then
                    notes+=("$key: no $n models in $mdir/${g%/*} (optional feature)")
                else
                    model_ok=MISSING
                    notes+=("$key: no $n models in $mdir/${g%/*}")
                fi
            done
        else
            g=${glob//\{feature\}/$f}
            if ! compgen -G "$mdir/$g" >/dev/null; then
                model_ok=MISSING
                notes+=("$key: no $g models in $mdir")
            fi
            for n in "${archs[@]}"; do
                ((${#pkg_archs[@]} == 0)) && break
                in_list "$n" "${pkg_archs[@]}" && continue
                model_ok=MISSING
                notes+=("$key: the package holds models for ${pkg_archs[*]}, not for this GPU's $n: rebuild with --archs")
            done
        fi
    done
    row[$key]=$(printf '%-6s %-32s %-6s %-8s %-6s %s' "$key" "${pkgname[$key]} $have" ok "$lib_ok" "$ldd_ok" "$model_ok")
    [[ $lib_ok$ldd_ok$model_ok == okokok ]]
}
say ""
say "== 7. Check (read-only)"
for key in "${chosen[@]}"; do
    verify "$key" || failures=$((failures + 1))
done
printf '  %-6s %-32s %-6s %-8s %-6s %s\n' SDK package env libpath ldd models
for key in "${chosen[@]}"; do
    say "  ${row[$key]}"
done
for x in "${notes[@]}"; do say "  note: $x"; done
say ""
say "  Per SDK state:"
for key in "${chosen[@]}"; do
    say "    $key: ${state[$key]:-not processed}"
done
say ""
say "Next steps: load the environment file for one program only and preload the shim on it,"
say "as $repo/docs/usage.md describes; the checks by hand are in"
for key in "${chosen[@]}"; do say "  $repo/${D[$key:check_doc]}"; done

# 8. Undo: printed, never run. The copied features: those of an SDK with a
# feature layout that are present but not in its package.
undo_pkgs=() undo_dirs=()
for key in "${sdk_keys[@]}"; do
    [[ -n $(installed_version "$key") ]] && undo_pkgs+=("${pkgname[$key]}")
    [[ -n ${D[$key:post_script]:-} && -n ${D[$key:feature_lib]:-} && -f $(env_path "$key") ]] || continue
    IFS=, read -r -a packaged <<<"$(env_value "$(env_path "$key")" "${D[$key:env_prefix]}_FEATURES" || true)"
    mdir=$(sdk_model_dir "$key")
    read -r -a features <<<"$(catalogue_features "$key")"
    for f in "${features[@]}"; do
        in_list "$f" "${packaged[@]}" && continue
        [[ -d $mdir/$f ]] && undo_dirs+=("$mdir/$f")
    done
done
say ""
say "== 8. Undo (printed, not run)"
if ((${#undo_pkgs[@]} == 0 && ${#undo_dirs[@]} == 0)); then
    say "  Nothing is installed."
else
    if ((${#undo_dirs[@]} > 0)); then
        say "  The copied features (pacman does not own them), first:"
        show_cmd "$(cmdline sudo rm -r -- "${undo_dirs[@]}")"
    fi
    if ((${#undo_pkgs[@]} > 0)); then
        show_cmd "$(cmdline sudo pacman -R "${undo_pkgs[@]}")"
    fi
fi
((dry_run)) && say "" && say "Dry run: nothing was asked, run or written."

((failures == 0)) || exit 1
exit 0
