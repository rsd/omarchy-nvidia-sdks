#!/usr/bin/env bash
# Shows what a Maxine AR SDK download holds and saves the selection the
# PKGBUILD builds, in maxine-ar/selection.conf (git-ignored: it holds a local
# path).
#
#   configure.sh [--src DIR]                  what is present, what the SDK
#                                             offers, the current selection
#   configure.sh [--src DIR] [--archs LIST|all] [--features LIST|all] --write
#                                             validate and save a selection
#   configure.sh [--src DIR] --archs ... | --features ...
#                                             validate only, save nothing
#   configure.sh --show                       print the current selection.conf
#   configure.sh --detect-gpu                 ask nvidia-smi for the GPU's
#                                             architecture (opt-in only)
#
# DIR defaults to $MAXINE_AR_SRC, else the MAXINE_AR_SRC of the current
# selection.conf, else ~/Downloads/maxine/ar-sdk; the output says which. A
# path that holds a newline is refused. The source is read with `assemble.sh
# --scan` (the same layout detection and refusals as the build); nothing is extracted or written there. This script uses no
# network and never runs ngc, NVIDIA's install_feature.sh or sudo. It runs
# nvidia-smi only for --detect-gpu: the query wakes a sleeping discrete GPU.
#
# --write validates the selection against what is present (a feature or
# architecture that is not there is an error naming the command that fetches
# it) and replaces selection.conf atomically (a temporary file, then mv). An
# option left out keeps the value of the current selection.conf, else the
# default (architectures sm_120, features all). See selection.sh for the
# file's format and the PKGBUILD for the precedence (environment variable >
# selection.conf > default).
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

prog=${0##*/}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=selection.sh
. "$here/selection.sh"
conf=$here/selection.conf

die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
warn() { printf '%s: WARNING: %s\n' "$prog" "$*" >&2; }
usage() {
    cat >&2 <<EOF
usage: $prog [--src DIR]
       $prog [--src DIR] [--archs "sm_120 sm_89" | all] [--features "f1 f2" | all] [--write]
       $prog --show
       $prog --detect-gpu
EOF
    exit 2
}

src_arg='' archs_arg='' features_arg='' write=0 show=0 detect=0
while (($#)); do
    case $1 in
        --src | --archs | --features)
            (($# >= 2)) || usage
            case $1 in
                --src) src_arg=$2 ;;
                --archs) archs_arg=$2 ;;
                --features) features_arg=$2 ;;
            esac
            shift 2
            ;;
        --write) write=1 && shift ;;
        --show) show=1 && shift ;;
        --detect-gpu) detect=1 && shift ;;
        *) usage ;;
    esac
done
if ((show || detect)); then
    # Each is used alone.
    [[ $((show + detect + write)) == 1 && -z $src_arg$archs_arg$features_arg ]] || usage
fi

# The SDK offered by this repository's PKGBUILD (its pkgver line; read, not
# sourced).
version=$(sed -n 's/^pkgver=\([0-9][0-9.]*\)$/\1/p' "$here/PKGBUILD")
[[ $version =~ ^([0-9]+)\.([0-9]+)\. ]] || die "no pkgver= line in $here/PKGBUILD"
major_minor=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}

# The seven features NVIDIA documents for the AR SDK 1.2.0.0 Linux (the SDK's
# features/README.md and Linux installation guide; the same list as
# download.sh) and the architectures NVIDIA's feature installer fetches models
# for. The documentation calls its list non-exhaustive.
offered=(nvargazeredirection nvarfaceboxdetection nvarlandmarkdetection nvarfaceexpressions
    nvarbodydetection nvarbodyposeestimation nvarlipsync)
declare -A offered_name=(
    [nvargazeredirection]="Eye contact (gaze estimation and redirection)"
    [nvarfaceboxdetection]="Face bounding box detection and tracking"
    [nvarlandmarkdetection]="Facial landmark detection and tracking (68 or 126 points)"
    [nvarfaceexpressions]="Face expression estimation (blendshapes, head pose)"
    [nvarbodydetection]="Body detection"
    [nvarbodyposeestimation]="Body pose estimation (2D and 3D keypoints)"
    [nvarlipsync]="Lip synchronisation to an audio track"
)
model_archs=(75 80 86 89 90 100 120)

in_list() { # in_list <word> <list...>
    local word=$1 item
    shift
    for item in "$@"; do [[ $item == "$word" ]] && return 0; done
    return 1
}
# split_list <list>: words split on spaces or commas, duplicates dropped.
split_list() {
    local word
    local -A seen=()
    local -a words
    read -r -a words <<<"${1//,/ }"
    for word in "${words[@]}"; do
        [[ -n ${seen[$word]:-} ]] && continue
        seen[$word]=1
        printf '%s\n' "$word"
    done
}
sort_numbers() { (($# == 0)) || printf '%s\n' "$@" | sort -n -u; }
sort_names() { (($# == 0)) || printf '%s\n' "$@" | LC_ALL=C sort -u; }
q() { printf '%q' "$1"; } # a path as a shell word, for the printed commands

# show_selection: the current selection.conf, or the defaults.
show_selection() {
    if ! maxine_ar_read_selection "$conf"; then
        echo "   $conf is not valid (see above); fix it or write it again with --write"
        return 1
    fi
    if [[ ! -e $conf ]]; then
        echo "   no selection.conf ($conf): the build uses the environment or the defaults"
        echo "   (MAXINE_AR_SRC=$here, MAXINE_AR_ARCHS=sm_120, MAXINE_AR_FEATURES=all)"
    else
        echo "   $conf:"
        echo "   MAXINE_AR_SRC=${maxine_ar_file_src:-(not set: $here)}"
        echo "   MAXINE_AR_ARCHS=${maxine_ar_file_archs:-(not set: sm_120)}"
        echo "   MAXINE_AR_FEATURES=${maxine_ar_file_features:-(not set: all)}"
    fi
    local key
    for key in MAXINE_AR_SRC MAXINE_AR_ARCHS MAXINE_AR_FEATURES; do
        [[ -z ${!key:-} ]] ||
            echo "   note: $key is set in this environment ($key=${!key}); it overrides the file when you build here"
    done
}

if ((show)); then
    echo "Current selection:"
    show_selection
    exit
fi

if ((detect)); then
    warn "running nvidia-smi: the query wakes a sleeping discrete GPU"
    command -v nvidia-smi >/dev/null 2>&1 ||
        die "nvidia-smi not found (it comes with the NVIDIA driver, nvidia-utils)"
    gpus=$(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader) ||
        die "nvidia-smi failed"
    suggest=()
    echo "GPUs (nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader):"
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        name=${line%,*} cap=${line##*,}
        cap=${cap//[[:space:]]/}
        if [[ ! $cap =~ ^([1-9][0-9]?)\.([0-9])$ ]]; then
            echo "  $name: compute capability '$cap' not understood"
            continue
        fi
        n=${BASH_REMATCH[1]}${BASH_REMATCH[2]}
        if in_list "$n" "${model_archs[@]}"; then
            echo "  $name: compute capability $cap -> sm_$n (NVIDIA's feature installer fetches models for it)"
            in_list "sm_$n" "${suggest[@]}" || suggest+=("sm_$n")
        elif ((n < 75)); then
            echo "  $name: compute capability $cap -> sm_$n, not supported: the SDK needs Turing (sm_75) or newer"
        else
            echo "  $name: compute capability $cap -> sm_$n, for which NVIDIA's feature installer fetches no models"
        fi
    done <<<"$gpus"
    if ((${#suggest[@]} > 0)); then
        echo "Suggested: $prog --archs \"${suggest[*]}\" --write"
    fi
    exit 0
fi

# The source, read by assemble.sh --scan: --src, else the environment, else
# the current selection.conf, else ~/Downloads/maxine/ar-sdk.
if [[ -n $src_arg ]]; then
    src=$src_arg src_from=--src
elif [[ -n ${MAXINE_AR_SRC:-} ]]; then
    src=$MAXINE_AR_SRC src_from="the environment (MAXINE_AR_SRC)"
else
    maxine_ar_read_selection "$conf" ||
        die "$conf is not valid (see above); give --src, or fix it"
    if [[ -n $maxine_ar_file_src ]]; then
        src=$maxine_ar_file_src src_from=$conf
    else
        src=$HOME/Downloads/maxine/ar-sdk src_from="the default (~/Downloads/maxine/ar-sdk)"
    fi
fi
# $(realpath ...) would drop a trailing newline and name another directory.
[[ $src != *$'\n'* ]] ||
    die "the source path $(q "$src") contains a newline, which is not supported: rename the directory"
[[ -d $src ]] || die "source directory not found: $src (from $src_from; set --src or MAXINE_AR_SRC; see docs/download.md)"
src=$(realpath -- "$src")
scan_out=$(bash "$here/assemble.sh" --scan --src "$src" --version "$version") ||
    die "cannot use $src (see the message above)"
layout='' sdk_version='' sdk_source='' all_archs='' unknown=0 present=()
declare -A feature_archs=()
while IFS= read -r line; do
    case $line in
        layout=*) layout=${line#layout=} ;;
        version=*) sdk_version=${line#version=} ;;
        source=*) sdk_source=${line#source=} ;;
        archs=*) all_archs=${line#archs=} ;;
        models_unknown=*) unknown=${line#models_unknown=} ;;
        feature=*' archs='*)
            line=${line#feature=}
            present+=("${line%% archs=*}")
            feature_archs[${line%% archs=*}]=${line#* archs=}
            ;;
        *) die "unexpected line from assemble.sh --scan: $line" ;;
    esac
done <<<"$scan_out"
[[ $layout == tree || $layout == download ]] || die "assemble.sh --scan gave no layout"
present_sms=()
[[ $all_archs == - ]] || mapfile -t present_sms < <(split_list "${all_archs//sm_/}")

# arch_numbers <list|all>: sets arch_all (1 for all) and arch_sms (numbers).
arch_all=0 arch_sms=()
arch_numbers() {
    local word
    local -a words
    arch_all=0 arch_sms=()
    mapfile -t words < <(split_list "$1")
    ((${#words[@]} > 0)) || die "--archs is empty"
    for word in "${words[@]}"; do
        if [[ $word == all ]]; then
            ((${#words[@]} == 1)) || die "'all' must be the only --archs entry, got '$1'"
            arch_all=1
        elif [[ $word =~ ^(sm_?)?([1-9][0-9]{1,2})$ ]]; then
            in_list "${BASH_REMATCH[2]}" "${arch_sms[@]}" || arch_sms+=("${BASH_REMATCH[2]}")
        else
            die "invalid architecture '$word': use sm_120, sm120 or 120 (the compute capability" \
                "without the dot), or all"
        fi
    done
    mapfile -t arch_sms < <(sort_numbers "${arch_sms[@]}")
}

# feature_names <list|all>: sets feat_all and feat_names (sorted).
feat_all=0 feat_names=()
feature_names() {
    local word
    local -a words
    feat_all=0 feat_names=()
    mapfile -t words < <(split_list "$1")
    ((${#words[@]} > 0)) || die "--features is empty"
    for word in "${words[@]}"; do
        if [[ $word == all ]]; then
            ((${#words[@]} == 1)) || die "'all' must be the only --features entry, got '$1'"
            feat_all=1
        elif [[ $word =~ ^[A-Za-z0-9_-]+$ ]]; then
            feat_names+=("$word")
        else
            die "invalid feature name '$word'"
        fi
    done
    mapfile -t feat_names < <(sort_names "${feat_names[@]}")
}

lib_cmd() { echo "ngc registry model download-version \"nvidia/maxine/$1:${version}_lib_linux\" --dest $(q "$src")"; }
models_cmd() { echo "ngc registry model download-version \"nvidia/maxine/$1:${version}_models_linux_sm$2\" --dest $(q "$src")"; }
tree_note="An SDK tree is packaged as it is: to add features or architectures, download them with NGC into a directory of their own (docs/download.md) and select that one with --src."

if [[ -n $archs_arg$features_arg ]] || ((write)); then
    # The selection: the options, else the current file, else the defaults.
    maxine_ar_file_archs='' maxine_ar_file_features=''
    if [[ -z $archs_arg || -z $features_arg ]]; then
        maxine_ar_read_selection "$conf" ||
            die "$conf is not valid (see above); give both --archs and --features to replace it"
    fi
    archs_value=${archs_arg:-${maxine_ar_file_archs:-sm_120}}
    features_value=${features_arg:-${maxine_ar_file_features:-all}}
    arch_numbers "$archs_value"
    feature_names "$features_value"

    errors=()
    if ((feat_all)); then
        ((${#present[@]} > 0)) || errors+=("no feature is present in $src: nothing to package. Fetch one, e.g.: $(lib_cmd nvargazeredirection)")
        selected=("${present[@]}")
    else
        for f in "${feat_names[@]}"; do
            in_list "$f" "${present[@]}" && continue
            if [[ $layout == tree ]]; then
                errors+=("feature $f is not present in the SDK tree $sdk_source. $tree_note")
            else
                errors+=("feature $f is not present in $src. Fetch it: $(lib_cmd "$f") (and its models for each architecture, if it has any)")
            fi
        done
        selected=("${feat_names[@]}")
    fi
    if ((!arch_all)) && ((${#present_sms[@]} > 0)); then
        for n in "${arch_sms[@]}"; do
            if [[ $layout == tree ]]; then
                in_list "$n" "${present_sms[@]}" ||
                    errors+=("the SDK tree has no models for sm_$n (it has ${all_archs//,/ }). $tree_note")
                continue
            fi
            for f in "${selected[@]}"; do
                fa=${feature_archs[$f]:--}
                [[ $fa == - ]] && continue
                mapfile -t fsms < <(split_list "$fa")
                in_list "sm_$n" "${fsms[@]}" ||
                    errors+=("feature $f has no models for sm_$n in $src. Fetch them: $(models_cmd "$f" "$n")")
            done
        done
    fi
    if ((${#errors[@]} > 0)); then
        printf '%s: %s\n' "$prog" "${errors[@]}" >&2
        exit 1
    fi

    if ((arch_all)); then
        new_archs=all
    else
        new_archs=$(printf 'sm_%s\n' "${arch_sms[@]}" | paste -sd ,)
    fi
    if ((feat_all)); then new_features=all; else new_features=$(IFS=,; echo "${feat_names[*]}"); fi
    if ((${#present_sms[@]} == 0)) && ((!arch_all)); then
        warn "$src holds no models: the packaged features will not run without their models"
    fi

    echo "Source: $src (from $src_from)"
    if ((!write)); then
        echo "Valid selection (not saved; add --write to save it in $conf):"
        echo "  MAXINE_AR_SRC=$src"
        echo "  MAXINE_AR_ARCHS=$new_archs"
        echo "  MAXINE_AR_FEATURES=$new_features"
        exit 0
    fi
    tmpfile=$(mktemp "$here/.selection.conf.XXXXXX")
    trap 'rm -f -- "$tmpfile"' EXIT
    {
        echo "# The maxine-ar build selection, written by configure.sh. The PKGBUILD"
        echo "# reads it as KEY=value lines (never executed); an environment variable"
        echo "# of the same name overrides a line. Change it with configure.sh --write."
        echo "MAXINE_AR_SRC=$src"
        echo "MAXINE_AR_ARCHS=$new_archs"
        echo "MAXINE_AR_FEATURES=$new_features"
    } >"$tmpfile"
    # What the PKGBUILD will accept: a path with $, a quote or a control
    # character cannot be stored.
    maxine_ar_read_selection "$tmpfile" 2>/dev/null ||
        die "the path $src cannot be stored in selection.conf (it holds \$, a backtick, a quote" \
            "or a control character): rename it, or set MAXINE_AR_SRC in the environment instead"
    chmod 644 -- "$tmpfile"
    mv -f -- "$tmpfile" "$conf"
    trap - EXIT
    echo "Wrote $conf:"
    grep -v '^#' "$conf" | sed 's/^/  /'
    if [[ $layout == tree ]] && ((!feat_all)) && ((${#selected[@]} < ${#present[@]})); then
        echo "  note: in an SDK tree the model files are not tied to a feature: lib/models keeps those of the features left out"
    fi
    echo "Next: (cd $(q "$here") && makepkg -f)"
    exit 0
fi

# The report.
echo "Maxine AR SDK in $src"
echo "  from     $src_from"
echo "  layout   $layout ($sdk_source)"
echo "  version  $sdk_version"
echo
if [[ $layout == download ]]; then
    echo "1. Present in the download (feature: architectures of its models):"
    if ((${#present[@]} == 0)); then
        echo "   no feature (no nvar*_v${major_minor}.*_lib_linux/ directory): fetch at least one, see below"
    fi
    for f in "${present[@]}"; do
        fa=${feature_archs[$f]}
        printf '   %-26s %s\n' "$f" "$([[ $fa == - ]] && echo "no models" || echo "${fa//,/ }")"
    done
else
    echo "1. Present in the SDK tree:"
    echo "   features  ${present[*]:-none (no features/<feature>/lib/*.so)}"
    echo "   models    ${all_archs//,/ } (for the tree as a whole: in a tree, model files are not tied to a feature)"
    ((unknown == 0)) || echo "   models    $unknown file(s) whose name carries no architecture (kept by the build)"
fi
echo
echo "2. Documented by NVIDIA for the SDK ${version} Linux (a non-exhaustive list):"
for f in "${offered[@]}"; do
    mark=' '
    in_list "$f" "${present[@]}" && mark=x
    printf '   [%s] %-26s %s\n' "$mark" "$f" "${offered_name[$f]}"
done
for f in "${present[@]}"; do
    in_list "$f" "${offered[@]}" || printf '   [x] %-26s %s\n' "$f" "(present, not in the table above)"
done
echo "   Their sizes on NGC and the closest NVIDIA Broadcast name: $(q "$here/download.sh") --list"
echo
echo "3. GPU architectures NVIDIA's feature installer fetches ${version} Linux models for:"
line='  '
for n in "${model_archs[@]}"; do
    mark=' '
    in_list "$n" "${present_sms[@]}" && mark=x
    line+=" [$mark] sm_$n"
done
echo "$line"
for n in "${present_sms[@]}"; do
    in_list "$n" "${model_archs[@]}" || echo "   [x] sm_$n (present, not in the list above)"
done
echo
echo "4. Current selection:"
show_selection || true
echo
suggest_archs=sm_120
if [[ -n ${maxine_ar_file_archs:-} ]]; then
    suggest_archs=$maxine_ar_file_archs
elif ((${#present_sms[@]} > 0)) && ! in_list 120 "${present_sms[@]}"; then
    suggest_archs=$(printf 'sm_%s\n' "${present_sms[@]}" | paste -sd ,)
fi
echo "Commands:"
if ((${#present[@]} > 0)); then
    echo "  save a selection (validated against what is present):"
    echo "    $(q "$0") --src $(q "$src") --archs $(q "$suggest_archs") --features ${maxine_ar_file_features:-all} --write"
fi
if [[ $layout == download ]]; then
    echo "  fetch more into the same directory, with your own NGC CLI (download.sh shows the sizes and asks first):"
    echo "    $(q "$here/download.sh") --dest $(q "$src") --features <feature>,... --archs sm_<N>,..."
    echo "    $(q "$here/download.sh") --dest $(q "$src") --preset all"
    echo "  or by hand:"
    echo "    $(lib_cmd '<feature>')"
    echo "    $(models_cmd '<feature>' '<N>')"
    echo "  then run this again and build."
else
    echo "  $tree_note"
fi
echo "  build:"
echo "    (cd $(q "$here") && makepkg -f)"
