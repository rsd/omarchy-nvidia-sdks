#!/usr/bin/env bash
# Downloads the NVIDIA Maxine Audio Effects SDK (the core, then a library for
# each selected feature and, per sample rate and GPU architecture, its model
# package) with the NGC CLI that you installed and configured yourself. See
# README.md, "Downloading".
#
# The NGC names follow NVIDIA's own features/download_features.sh:
#   core     resource nvidia/maxine/maxine_linux_audio_effects_sdk:<X.Y.Z>
#   library  model    nvidia/maxine/afx_<feature>:<X.Y.Z>-lib
#   models   model    nvidia/maxine/afx_<feature>:<X.Y.Z>-<rate>-sm<N>
# An effect is named as that script names it, <feature>-<rate>: denoiser-48k,
# studio_voice-16k, superres-16k_to_48k.
#
# It first asks NGC, read-only (`ngc registry ... info --format_type json`),
# for the size and file count of every item, compares that with what is in
# the destination, prints a table on stderr and asks before downloading.
# Each item is downloaded into DEST/.partial/, checked against the size and
# file count NGC reported, and only then moved into DEST. A failed item is
# retried, then reported; the other items continue and the exit status is 1.
# An item NGC answers with HTTP 402 (the key works, but the account is not
# entitled to the model: Early Access or an entitlement) is not retried: its
# feature is skipped, named with the page to request access on, and left out
# of the next steps; that alone does not fail the run, unless it leaves no
# feature to build.
# The models' own .md5 files are checked by assemble.sh when the package is
# built.
#
# This script never reads ~/.ngc, never handles an API key and never passes
# one on a command line: authentication is entirely the NGC CLI's business.
# It never runs NVIDIA's download_features.sh, never runs sudo and never
# installs anything; --build runs configure.sh --write and makepkg -f in
# this directory, nothing more.
#
# Exit status: 0 success (features skipped for HTTP 402 are listed), 1
# failure, 2 usage error.
set -euo pipefail

prog=download.sh
here=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<'USAGE'
Usage: download.sh [--dest DIR] [--archs LIST|auto|all] [--preset broadcast|all]
                   [--features LIST] [--version 3.0.0] [--retries N]
                   [--yes] [--dry-run] [--build]
       download.sh --list [--archs LIST|auto|all] [--version V] [--dry-run]

  --dest DIR       download directory (default: ~/Downloads/maxine/afx-sdk)
  --archs LIST     GPU architectures: auto (default, from nvidia-smi), all
                   (75 80 86 89 90 100 120), or sm_120 / sm120 / 120,
                   comma or space separated
  --preset NAME    broadcast (default: denoiser-48k, dereverb-48k,
                   dereverb_denoiser-48k, studio_voice-48k) or all (the ten
                   effects that are not Early Access)
  --features LIST  effects instead of a preset, comma separated, each
                   <feature>-<rate> as in --list (e.g. denoiser-16k,
                   superres-16k_to_48k, speaker_focus-48k)
  --version V      the NGC tag of the SDK (default: 3.0.0)
  --retries N      extra attempts for an item that fails (default: 2)
  --yes            do not ask; required without a terminal
  --dry-run        probe and show the table, print the download commands on
                   stdout; download and create nothing
  --build          after a fully successful run: configure.sh --write, then
                   makepkg -f (never installs, never sudo)
  --list           the known effects, what they do and their sizes
  -h, --help       this help

The SDK core is always fetched. Documentation: README.md
USAGE
}

die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
warn() { printf '%s: WARNING: %s\n' "$prog" "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }
usage_error() {
    printf '%s: %s\n' "$prog" "$*" >&2
    printf 'Run %s --help for the options.\n' "$prog" >&2
    exit 2
}
q() { printf '%q' "$1"; }
# cmdline <word...>: the words as one shell command line.
cmdline() {
    local line
    line=$(printf '%q ' "$@")
    printf '%s\n' "${line% }"
}
# human <bytes>: MiB below 1 GiB, else GiB.
human() {
    LC_ALL=C awk -v b="$1" 'BEGIN {
        if (b >= 1073741824) printf "%.2f GiB", b / 1073741824
        else printf "%.1f MiB", b / 1048576
    }'
}
in_list() { # in_list <word> <list...>
    local word=$1 item
    shift
    for item in "$@"; do [[ $item == "$word" ]] && return 0; done
    return 1
}

# The effects NVIDIA's features/download_features.sh knows for SDK 3.0.0
# Linux, then its two Early Access ones. The NVIDIA Broadcast names are a
# mapping by function: NVIDIA does not document one.
known_effects=(denoiser-16k denoiser-48k dereverb-16k dereverb-48k
    dereverb_denoiser-16k dereverb_denoiser-48k superres-8k_to_16k superres-16k_to_48k
    studio_voice-16k studio_voice-48k)
early_access=(speaker_focus-16k speaker_focus-48k)
declare -A feature_what=(
    [denoiser]="Noise removal (background noise in speech)"
    [dereverb]="Room echo removal (reverberation)"
    [dereverb_denoiser]="Noise and room echo removal in one effect"
    [superres]="Audio super resolution: raises the sample rate (8k to 16k, 16k to 48k)"
    [studio_voice]="Studio Voice: high quality, low latency (with mic profiles)"
    [speaker_focus]="Speaker focus: keeps the main speaker (Early Access)"
)
declare -A feature_broadcast=(
    [denoiser]="Noise Removal"
    [dereverb]="Room Echo Removal"
    [dereverb_denoiser]="Noise Removal with Room Echo Removal"
    [superres]="none"
    [studio_voice]="Studio Voice"
    [speaker_focus]="none"
)
preset_broadcast=(denoiser-48k dereverb-48k dereverb_denoiser-48k studio_voice-48k)
# http402: an answer of HTTP 402 Payment Required in ngc's output (grep -iE):
# the key is valid, but the account is not entitled to the item.
http402='payment required|(error|status|response|http|code)[^0-9]{0,20}402([^0-9]|$)|(^|[^0-9.])402[[:space:]]+(payment|response|client)'
# access_text <feature>: why it is skipped, and where to ask for access.
access_text() {
    local f=$1 r effects=''
    while IFS= read -r r; do effects+="${effects:+, }$f-$r"; done < <(rates_of "$f")
    printf '%s: your NGC key works, but your account has no access to this model (HTTP 402: Early Access or an entitlement); request access on https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_%s\n' \
        "$effects" "$f"
}
# The architectures NVIDIA's download script maps a GPU to.
model_archs=(75 80 86 89 90 100 120)
troubleshooting="README.md, \"Downloading\""

dest_arg="$HOME/Downloads/maxine/afx-sdk"
archs_arg=auto
preset_arg='' features_arg=''
version=3.0.0
retries=2
yes=0 dry_run=0 build=0 list_only=0
download_opts=0 # --dest, --preset, --features, --retries, --yes or --build given

while (($#)); do
    case $1 in
        --dest | --archs | --preset | --features | --version | --retries)
            (($# >= 2)) || usage_error "option $1 needs a value"
            case $1 in
                --dest) dest_arg=$2 download_opts=1 ;;
                --archs) archs_arg=$2 ;;
                --preset) preset_arg=$2 download_opts=1 ;;
                --features) features_arg=$2 download_opts=1 ;;
                --version) version=$2 ;;
                --retries) retries=$2 download_opts=1 ;;
            esac
            shift 2
            ;;
        --yes) yes=1 download_opts=1 && shift ;;
        --build) build=1 download_opts=1 && shift ;;
        --dry-run) dry_run=1 && shift ;;
        --list) list_only=1 && shift ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) usage_error "unknown argument: $1" ;;
    esac
done

if ((list_only && download_opts)); then
    usage_error "--list takes only --archs, --version and --dry-run"
fi
[[ $version =~ ^[0-9]+(\.[0-9]+){2}$ ]] ||
    usage_error "invalid version '$version' (expected the three-number NGC tag such as 3.0.0)"
[[ $retries =~ ^[0-9]{1,3}$ ]] ||
    usage_error "invalid --retries '$retries' (a number of extra attempts, such as 2)"
retries=$((10#$retries))
if [[ -n $preset_arg && -n $features_arg ]]; then
    usage_error "give --preset or --features, not both"
fi

# The effects: --features, else the preset.
effects=()
if [[ -n $features_arg ]]; then
    read -r -a words <<<"${features_arg//,/ }"
    ((${#words[@]} > 0)) || usage_error "--features needs at least one effect"
    for e in "${words[@]}"; do
        [[ $e =~ ^[a-z0-9_]+-[0-9]+k(_to_[0-9]+k)?$ ]] ||
            usage_error "invalid effect '$e' (expected <feature>-<rate>, such as denoiser-48k or superres-16k_to_48k)"
        in_list "$e" "${effects[@]}" || effects+=("$e")
    done
else
    case ${preset_arg:-broadcast} in
        broadcast) effects=("${preset_broadcast[@]}") ;;
        all) effects=("${known_effects[@]}") ;;
        *) usage_error "unknown preset '$preset_arg' (broadcast or all)" ;;
    esac
fi
((list_only)) && effects=("${known_effects[@]}" "${early_access[@]}")
# The features, in the order of their first effect, and their rates.
features=()
declare -A feature_rates=()
for e in "${effects[@]}"; do
    f=${e%%-*} r=${e#*-}
    in_list "$f" "${features[@]}" || features+=("$f")
    feature_rates[$f]+="$r "
done

# The architectures, as numbers: sm_120, sm120 and 120 are all 120.
read -r -a words <<<"${archs_arg//,/ }"
((${#words[@]} > 0)) || usage_error "--archs needs at least one value"
arch_mode=list
if [[ ${words[*]} == auto || ${words[*]} == all ]]; then
    arch_mode=${words[0]}
elif in_list auto "${words[@]}" || in_list all "${words[@]}"; then
    usage_error "'auto' and 'all' must be the only --archs entry (got '$archs_arg')"
fi
arch_words=()
arch_hint="--archs sm_120 (your GPU's compute capability without the dot: nvidia-smi --query-gpu=compute_cap --format=csv,noheader prints 12.0 for sm_120)"
case $arch_mode in
    list)
        for a in "${words[@]}"; do
            [[ $a =~ ^(sm_?)?([1-9][0-9]{1,2})$ ]] ||
                usage_error "invalid architecture '$a' (use sm_120, sm120 or 120: the compute capability without the dot; or auto, or all)"
            arch_words+=("${BASH_REMATCH[2]}")
        done
        ;;
    all) arch_words=("${model_archs[@]}") ;;
    auto)
        command -v nvidia-smi >/dev/null 2>&1 ||
            die "nvidia-smi not found, so the GPU architecture cannot be detected: pass $arch_hint"
        smi_out=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>&1) ||
            die "nvidia-smi failed ($(head -n 1 <<<"$smi_out")): pass $arch_hint"
        while IFS= read -r line; do
            line=${line//[[:space:]]/}
            [[ -n $line ]] || continue
            [[ $line =~ ^([1-9][0-9]?)\.([0-9])$ ]] ||
                die "nvidia-smi gave the compute capability '$line', which is not understood: pass $arch_hint"
            arch_words+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}")
        done <<<"$smi_out"
        ((${#arch_words[@]} > 0)) || die "nvidia-smi reported no GPU: pass $arch_hint"
        ;;
esac
archs=()
for a in "${arch_words[@]}"; do
    in_list "$a" "${archs[@]}" || archs+=("$a")
done
for a in "${archs[@]}"; do
    ((a >= 75)) || die "sm_$a is not supported: the SDK needs Turing (sm_75) or newer"
    in_list "$a" "${model_archs[@]}" ||
        warn "sm_$a is not an architecture NVIDIA's download script lists; its models will show as \"no model package\""
done
archs_text=$(printf 'sm_%s ' "${archs[@]}")
archs_text=${archs_text% }
[[ $arch_mode == auto ]] && note "GPU architecture (from nvidia-smi): $archs_text"

core_ref="nvidia/maxine/maxine_linux_audio_effects_sdk:${version}"
lib_ref() { echo "nvidia/maxine/afx_$1:${version}-lib"; }
models_ref() { echo "nvidia/maxine/afx_$1:${version}-$2-sm$3"; }
# dir_of <ref>: the directory download-version creates, <name>_v<tag>.
dir_of() {
    local name=${1##*/}
    echo "${name%%:*}_v${name#*:}"
}
# rates_of <feature>: its selected rates, one per line.
rates_of() {
    local -a rs
    read -r -a rs <<<"${feature_rates[$1]}"
    printf '%s\n' "${rs[@]}"
}

# --list --dry-run: the read-only info commands only.
if ((list_only && dry_run)); then
    cmdline ngc registry resource info "$core_ref" --format_type json
    for f in "${features[@]}"; do
        cmdline ngc registry model info "$(lib_ref "$f")" --format_type json
        while IFS= read -r r; do
            for a in "${archs[@]}"; do
                cmdline ngc registry model info "$(models_ref "$f" "$r" "$a")" --format_type json
            done
        done < <(rates_of "$f")
    done
    exit 0
fi

command -v ngc >/dev/null 2>&1 ||
    die "the NGC CLI ('ngc') is not on PATH: install it and configure it yourself (README.md, \"Downloading\")"

# json_number <key> <text>: the first integer value of "key" in the text.
json_number() {
    { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" <<<"$2" || true; } |
        head -n 1 | sed 's/.*:[[:space:]]*//'
}
# probe <kind> <ref>: ngc ... info, read-only, stdout and stderr together.
# Sets p_bytes and p_files and returns 0, or sets p_error (ngc's message:
# the first line that names an error, else the first line) and p_denied,
# and returns 1. p_denied=1 when NGC answered that the item is missing or not
# accessible (403, Access Denied, could not be found); p_402=1 when it
# answered HTTP 402 (the account is not entitled to it); any other failure
# (timeout, 5xx, rate limit, network) leaves both 0: a failed probe. info
# can succeed for a model whose files are gated: the 402 then comes from
# download-version, which the download loop handles the same way.
p_bytes='' p_files='' p_error='' p_denied=0 p_402=0
probe() {
    local kind=$1 ref=$2 out rc=0
    out=$(ngc registry "$kind" info "$ref" --format_type json 2>&1) || rc=$?
    p_bytes=$(json_number totalSizeInBytes "$out")
    p_files=$(json_number totalFileCount "$out")
    p_error='' p_denied=0 p_402=0
    if ((rc == 0)) && [[ -n $p_bytes && -n $p_files ]]; then
        return 0
    fi
    if grep -qiE "$http402" <<<"$out"; then
        p_402=1
    elif grep -qiE 'Error: 403|403 Response|Access Denied|could not be found' <<<"$out"; then
        p_denied=1
    fi
    # An "update available" banner can come first: prefer the error line.
    p_error=$(grep -m 1 -iE 'error|40[23]|denied|not found|payment' <<<"$out" || true)
    [[ -n $p_error ]] || p_error=$(grep -m 1 -v '^[[:space:]]*$' <<<"$out" || true)
    if [[ $p_error =~ \"error\"[[:space:]]*:[[:space:]]*\"(.*)\" ]]; then
        p_error=${BASH_REMATCH[1]}
    fi
    [[ -n $p_error ]] || p_error="ngc exited with status $rc and gave no size"
    p_error=${p_error:0:300}
    return 1
}
# probe_core: the SDK core always exists, so a failure here is the setup's.
probe_core() {
    probe resource "$core_ref" && return 0
    printf '%s: the NGC CLI cannot see the SDK core (%s).\n' "$prog" "$core_ref" >&2
    printf '  ngc said: %s\n' "$p_error" >&2
    cat >&2 <<EOF
  The core always exists, so this points at the NGC CLI setup. Likely causes:
  - the NGC CLI is not configured: run \`ngc config set\` yourself;
  - the API key is invalid or expired;
  - the account has no Maxine access (NVIDIA Developer Program, "Get Access");
  - this machine is offline.
  See $troubleshooting
EOF
    exit 1
}

# local_state <dir>: "<files> <bytes>" of the regular files below it.
local_state() {
    find -H "$1" -type f -printf '%s\n' 2>/dev/null |
        LC_ALL=C awk '{ n++; s += $1 } END { printf "%d %d\n", n, s }'
}

# --list: the known effects, probed by name.
if ((list_only)); then
    probe_core
    core_bytes=$p_bytes
    list_failed=() # "<ref>: <ngc's message>" of each failed probe
    declare -A lib_text=()
    printf '%-24s %-13s' effect library
    for a in "${archs[@]}"; do printf ' %-13s' "sm_$a models"; done
    printf '\n'
    for e in "${effects[@]}"; do
        f=${e%%-*} r=${e#*-}
        printf '%-24s' "$e"
        if [[ -z ${lib_text[$f]:-} ]]; then
            if probe model "$(lib_ref "$f")"; then
                lib_text[$f]=$(human "$p_bytes")
            elif ((p_402)); then
                lib_text[$f]="needs access"
            elif ((p_denied)); then
                lib_text[$f]="not available"
            else
                lib_text[$f]="probe failed"
                list_failed+=("$(lib_ref "$f"): $p_error")
            fi
        fi
        printf ' %-13s' "${lib_text[$f]}"
        if [[ ${lib_text[$f]} != *[0-9]* ]]; then
            printf '\n'
            continue
        fi
        for a in "${archs[@]}"; do
            if probe model "$(models_ref "$f" "$r" "$a")"; then
                printf ' %-13s' "$(human "$p_bytes")"
            elif ((p_402)); then
                printf ' %-13s' "needs access"
            elif ((p_denied)); then
                printf ' %-13s' none
            else
                printf ' %-13s' "probe failed"
                list_failed+=("$(models_ref "$f" "$r" "$a"): $p_error")
            fi
        done
        printf '\n'
    done
    printf '\nSDK core (%s): %s, always fetched. A library is fetched once per feature.\n' \
        "$core_ref" "$(human "$core_bytes")"
    printf '\nWhat each feature does, and the closest NVIDIA Broadcast name (a mapping by\n'
    printf 'function; NVIDIA does not document one):\n'
    for f in "${features[@]}"; do
        printf '  %-20s %s\n  %-20s -> %s\n' "$f" "${feature_what[$f]}" '' "${feature_broadcast[$f]}"
    done
    printf '\nPresets: broadcast = %s; all = the ten that are not Early Access.\n' "${preset_broadcast[*]}"
    printf 'Early Access effects (%s) are fetched only when named in --features.\n' "${early_access[*]}"
    printf '"needs access": NGC answered HTTP 402: the account is not entitled to it (Early Access or an\n'
    printf 'entitlement); request access on its page, https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_<feature>\n'
    if ((${#list_failed[@]} > 0)); then
        note ""
        for x in "${list_failed[@]}"; do warn "probe failed, so the table is incomplete: $x"; done
        note "Run it again later; see $troubleshooting"
        exit 1
    fi
    exit 0
fi

[[ -n $dest_arg ]] || usage_error "--dest must not be empty"
[[ $dest_arg != *$'\n'* ]] || usage_error "the destination must not contain a newline"
dest=$(realpath -m -- "$dest_arg")
staging=$dest/.partial
if [[ -e $dest && ! -d $dest ]]; then
    die "the destination $dest exists and is not a directory"
fi
if [[ -L $staging ]]; then
    die "$staging is a symbolic link: the downloads are staged there and a link is not followed; remove it and run again"
elif [[ -e $staging && ! -d $staging ]]; then
    die "$staging exists and is not a directory: the downloads are staged there; remove it and run again"
fi

# Phase 1, probe (read-only), and phase 2, status: one entry per item.
it_kind=() it_ref=() it_dir=() it_feature=() it_bytes=() it_files=() it_status=()
add_item() { # add_item <kind> <ref> <feature> <bytes> <files> <status>
    it_kind+=("$1")
    it_ref+=("$2")
    it_dir+=("$(dir_of "$2")")
    it_feature+=("$3")
    it_bytes+=("$4")
    it_files+=("$5")
    it_status+=("$6")
}
# classify <ref> <bytes> <files>: present, incomplete or missing in DEST.
classify() {
    local path
    path=$dest/$(dir_of "$1")
    if [[ ! -e $path && ! -L $path ]]; then
        echo missing
    elif [[ -d $path && $(local_state "$path") == "$3 $2" ]]; then
        echo present
    else
        echo incomplete
    fi
}

note "Asking NGC for the size of each item (read-only)..."
probe_core
add_item resource "$core_ref" '' "$p_bytes" "$p_files" "$(classify "$core_ref" "$p_bytes" "$p_files")"
for f in "${features[@]}"; do
    ref=$(lib_ref "$f")
    if ! probe model "$ref"; then
        # An unknown name or no access: the feature is skipped. HTTP 402: the
        # feature is skipped and named. Any other failure is a failed probe:
        # the feature is skipped and the run fails.
        if ((p_402)); then
            add_item model "$ref" "$f" '' '' noaccess
        elif ((p_denied)); then
            add_item model "$ref" "$f" '' '' unavailable
        else
            add_item model "$ref" "$f" '' '' "probefail:$p_error"
        fi
        continue
    fi
    add_item model "$ref" "$f" "$p_bytes" "$p_files" "$(classify "$ref" "$p_bytes" "$p_files")"
    mapfile -t rates < <(rates_of "$f")
    for r in "${rates[@]}"; do
        for a in "${archs[@]}"; do
            ref=$(models_ref "$f" "$r" "$a")
            if probe model "$ref"; then
                add_item model "$ref" "$f" "$p_bytes" "$p_files" "$(classify "$ref" "$p_bytes" "$p_files")"
            elif ((p_402)); then
                add_item model "$ref" "$f" '' '' noaccess
            elif ((p_denied)); then
                add_item model "$ref" "$f" '' '' "nomodels:$r-sm$a"
            else
                add_item model "$ref" "$f" '' '' "probefail:$p_error"
            fi
        done
    done
done

no_access=() # the features skipped because NGC answered HTTP 402
for i in "${!it_ref[@]}"; do
    [[ ${it_status[i]} != noaccess ]] || in_list "${it_feature[i]}" "${no_access[@]}" ||
        no_access+=("${it_feature[i]}")
done
# The other items of a feature that needs access are not fetched.
for i in "${!it_ref[@]}"; do
    if [[ -z ${it_feature[i]} ]] || ! in_list "${it_feature[i]}" "${no_access[@]}"; then continue; fi
    case ${it_status[i]} in incomplete | missing) it_status[i]=skipped ;; esac
done

# Phase 3, the table (stderr).
status_text() {
    case $1 in
        present) echo present ;;
        incomplete) echo "incomplete (will download again)" ;;
        missing) echo "missing (will download)" ;;
        nomodels:*) echo "no model package for ${1#nomodels:}" ;;
        unavailable) echo "unavailable (unknown name or no access)" ;;
        noaccess) echo "no access (HTTP 402: Early Access or an entitlement)" ;;
        skipped) echo "skipped (its feature needs access)" ;;
        probefail:*)
            local reason=${1#probefail:}
            ((${#reason} <= 50)) || reason="${reason:0:47}..."
            echo "probe failed: $reason"
            ;;
    esac
}
{
    printf '\n%-56s %12s %6s  %s\n' item size files status
    for i in "${!it_ref[@]}"; do
        size=- files=-
        if [[ -n ${it_bytes[i]} ]]; then
            size=$(human "${it_bytes[i]}") files=${it_files[i]}
        fi
        printf '%-56s %12s %6s  %s\n' "${it_ref[i]#nvidia/maxine/}" "$size" "$files" "$(status_text "${it_status[i]}")"
    done
} >&2
todo=() todo_bytes=0 unavailable=()
failed=() # "<ref>: <reason>" of each failed probe and each failed download
for i in "${!it_ref[@]}"; do
    case ${it_status[i]} in
        incomplete | missing)
            todo+=("$i")
            todo_bytes=$((todo_bytes + it_bytes[i]))
            ;;
        unavailable) unavailable+=("${it_feature[i]}") ;;
        probefail:*) failed+=("${it_ref[i]}: probe failed: ${it_status[i]#probefail:}") ;;
    esac
done
note ""
if ((${#todo[@]} == 0)); then
    if ((${#unavailable[@]} == 0 && ${#failed[@]} == 0)); then
        note "Nothing to download: everything is present in $dest."
    else
        note "Nothing to download: everything available is present in $dest."
    fi
else
    note "To download: ${#todo[@]} item(s), $(human "$todo_bytes") ($todo_bytes bytes), into $dest"
fi
for f in "${unavailable[@]}"; do
    warn "feature $f is unavailable: the name is not on NGC for $version, or the account has no access to it (the known effects: $prog --list)"
done
for f in "${no_access[@]}"; do
    warn "feature $f is skipped: $(access_text "$f")"
done
for i in "${!it_ref[@]}"; do
    [[ ${it_status[i]} == probefail:* ]] || continue
    warn "probing ${it_ref[i]} failed (${it_status[i]#probefail:}): it is not downloaded and the run fails; run it again later (see $troubleshooting)"
done

# Phase 4, confirm. A dry run prints the commands on stdout instead.
if ((dry_run)); then
    for i in "${todo[@]}"; do
        cmdline ngc registry "${it_kind[i]}" download-version "${it_ref[i]}" --dest "$staging"
    done
    ((${#todo[@]} == 0)) || note "Dry run: the commands above were not run; nothing was downloaded or created."
elif ((${#todo[@]} > 0 && !yes)); then
    ( : </dev/tty) 2>/dev/null ||
        die "there is no terminal to ask for confirmation on: pass --yes to download without asking"
    printf 'Download %d items (%s) into %s? [y/N] ' "${#todo[@]}" "$(human "$todo_bytes")" "$dest" >&2
    answer=''
    read -r answer </dev/tty || true
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || die "not confirmed; nothing was downloaded"
fi

# Phase 5, download into DEST/.partial, verify, then move into DEST.
verify() { [[ -d $1 && $(local_state "$1") == "$3 $2" ]]; } # verify <path> <bytes> <files>
if ((!dry_run && ${#todo[@]} > 0)); then
    mkdir -p -- "$staging"
    # ngc's stderr, where it prints its errors, is shown as it comes and
    # kept here, to spot an HTTP 402. Its stdout goes straight to the
    # terminal, so that its live progress display keeps working.
    ngc_log=$(mktemp "${TMPDIR:-/tmp}/maxine-afx-download.XXXXXX")
    trap 'rm -f -- "$ngc_log"' EXIT
    # it_placed[i]=1: this run moved item i into DEST (removed again when
    # its feature then turns out to need access).
    declare -A it_placed=()
    n=0
    for i in "${todo[@]}"; do
        n=$((n + 1))
        ref=${it_ref[i]} dir=${it_dir[i]} bytes=${it_bytes[i]} files=${it_files[i]}
        f=${it_feature[i]}
        if [[ -n $f ]] && in_list "$f" "${no_access[@]}"; then
            note "[$n/${#todo[@]}] $ref: skipped, feature $f needs access (HTTP 402)"
            rm -rf -- "${staging:?}/${dir:?}"
            it_status[i]=skipped
            continue
        fi
        attempt=0 finished=0
        while ((!finished)); do
            attempt=$((attempt + 1))
            note "[$n/${#todo[@]}] $ref ($(human "$bytes")), attempt $attempt of $((retries + 1))"
            rc=0
            ngc registry "${it_kind[i]}" download-version "$ref" --dest "$staging" \
                >&2 2> >(tee -- "$ngc_log" >&2) || rc=$?
            # The log is complete only once tee has finished.
            wait "$!" 2>/dev/null || true
            if ((rc == 0)) && verify "$staging/$dir" "$bytes" "$files"; then
                # Verified: only now an incomplete copy in DEST makes way.
                if [[ -e $dest/$dir || -L $dest/$dir ]]; then
                    rm -rf -- "${dest:?}/${dir:?}"
                fi
                mv -T -- "$staging/$dir" "$dest/$dir"
                it_placed[$i]=1
                it_status[i]=present
                finished=1
                continue
            fi
            if ((rc != 0)); then
                reason="ngc exited with status $rc"
            elif [[ ! -d $staging/$dir ]]; then
                reason="ngc did not create $staging/$dir"
            else
                read -r got_files got_bytes <<<"$(local_state "$staging/$dir")"
                reason="got $got_files file(s), $got_bytes bytes; NGC reported $files, $bytes"
            fi
            if [[ -n $f ]] && grep -qiE "$http402" "$ngc_log"; then
                # Not entitled: a retry cannot help, and the feature is skipped.
                warn "$ref: NGC answered HTTP 402 (no access to this model): feature $f is skipped"
                rm -rf -- "${staging:?}/${dir:?}"
                it_status[i]=noaccess
                no_access+=("$f")
                # What this run already placed of it in DEST goes again, so
                # that no half feature is left there; what was there before
                # the run stays.
                for j in "${!it_placed[@]}"; do
                    [[ ${it_feature[j]} == "$f" ]] || continue
                    rm -rf -- "${dest:?}/${it_dir[j]:?}"
                    unset 'it_placed[$j]'
                    it_status[j]=skipped
                done
                finished=1
            elif ((attempt > retries)); then
                warn "$ref failed: $reason; giving up after $attempt attempt(s)"
                rm -rf -- "${staging:?}/${dir:?}"
                failed+=("$ref: $reason")
                finished=1
            else
                # The staging copy stays: the NGC CLI can reuse finished files.
                warn "$ref failed: $reason; trying again"
            fi
        done
    done
    # Only a real directory is ours to remove (a link or a file is left alone).
    rm -f -- "$ngc_log"
    if [[ -d $staging && ! -L $staging ]]; then
        rmdir -- "$staging" 2>/dev/null || true
        [[ ! -d $staging ]] ||
            warn "$staging is not empty: it holds files this script did not expect (safe to delete when the script is not running)"
    fi
fi

# Phase 6, the next steps (stdout; stderr in a dry run).
# item_done <status>: the item is present after this run (in a dry run: it
# would be, once downloaded). No model package for an architecture counts.
item_done() {
    case $1 in
        present | nomodels:*) return 0 ;;
        missing | incomplete) ((dry_run)) ;;
        *) return 1 ;;
    esac
}
# ready: the selected features whose library and every models item are done.
core_present=0 ready=()
item_done "${it_status[0]}" && core_present=1
for f in "${features[@]}"; do
    ! in_list "$f" "${no_access[@]}" || continue
    done_all=1
    for i in "${!it_ref[@]}"; do
        [[ ${it_feature[i]} == "$f" ]] || continue
        item_done "${it_status[i]}" || done_all=0
    done
    ((!done_all)) || ready+=("$f")
done
if ((${#failed[@]} > 0)); then
    note ""
    note "Failed (run the same command again to retry them; complete items are skipped):"
    for x in "${failed[@]}"; do note "  $x"; done
fi
if ((${#no_access[@]} > 0)); then
    note ""
    note "Skipped, your account has no access (the rest is not affected):"
    for f in "${no_access[@]}"; do note "  $(access_text "$f")"; done
fi
ok=1
((${#failed[@]} == 0 && ${#unavailable[@]} == 0)) || ok=0

configure_cmd=("$here/configure.sh" --src "$dest" --archs "$archs_text"
    --features "$(IFS=,; echo "${ready[*]}")" --write)
next_steps() {
    if ((!ok)); then
        echo "Next steps, once the failures above are fixed (the --features below leave out every feature with a failure):"
    elif ((dry_run && ${#todo[@]} > 0)); then
        echo "Next steps, once the download is complete:"
    elif ((${#no_access[@]} > 0)); then
        echo "Next steps, without the features that need access ($(IFS=,; echo "${no_access[*]}")):"
    else
        echo "Next steps:"
    fi
    if ((!core_present || ${#ready[@]} == 0)); then
        echo "  The SDK core and at least one feature library must be present first: fix the failures above and run this again."
        return
    fi
    # The architectures and features hold only [a-z0-9_ ,]: quoted by hand.
    echo "  $(q "$here/configure.sh") --src $(q "$dest") --archs \"$archs_text\" --features ${configure_cmd[6]} --write"
    echo "  cd $(q "$here") && makepkg -f"
    echo "  sudo pacman -U $(q "$here")/maxine-afx-sdk-local-*.pkg.tar*"
    echo "  (this script never runs the last one: installing is yours to do)"
}
note ""
if ((dry_run)); then
    next_steps >&2
    ((!build)) || note "--build with --dry-run: nothing was configured or built."
else
    next_steps
fi

if ((build && !dry_run)); then
    if ((!ok)); then
        warn "--build skipped: not everything selected was downloaded"
    elif ((!core_present || ${#ready[@]} == 0)); then
        warn "--build skipped: nothing to build"
    else
        note ""
        note "--build: $(cmdline "${configure_cmd[@]}")"
        "${configure_cmd[@]}" || die "configure.sh failed; the package was not built"
        note "--build: cd $(q "$here") && makepkg -f"
        (cd "$here" && makepkg -f) || die "makepkg failed (see above); nothing was installed"
        note "Built in $here. Install it yourself: sudo pacman -U $(q "$here")/maxine-afx-sdk-local-*.pkg.tar*"
    fi
fi

((ok)) || exit 1
# HTTP 402 alone does not fail the run, unless no feature is left to build.
if ((${#no_access[@]} > 0 && ${#ready[@]} == 0)); then
    warn "every selected feature needs access (HTTP 402): there is nothing to build"
    exit 1
fi
exit 0
