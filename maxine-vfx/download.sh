#!/usr/bin/env bash
# Download the NVIDIA Maxine Video Effects SDK files with your own, already
# configured NGC CLI. See docs/download.md for the manual steps and for the
# account, access and key setup that must be done first.
#
# This script never reads ~/.ngc, never handles an API key and never passes
# one on a command line: authentication is entirely the NGC CLI's business.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: download.sh [--dest DIR] [--archs "sm_120 sm_89" | all]
                   [--version 1.3.0.0]
                   [--features "nvvfxgreenscreen nvvfxbackgroundblur"]
                   [--dry-run]
       download.sh --list [--dry-run]

Downloads, with the NGC CLI you configured yourself (`ngc config set`):
  - the SDK core            nvidia/maxine/vfx_sdk_core:<version>_linux
  - one library per feature nvidia/maxine/<feature>:<version>_lib_linux
  - the models of every feature, once per GPU architecture
                            nvidia/maxine/<feature>:<version>_models_linux_sm<N>
    Some features have no model package; that is reported, not an error.

Options:
  --dest DIR        download directory (default: ~/Downloads/maxine)
  --archs LIST      GPU architectures: sm_120, sm120 or 120 (compute capability
                    without the dot), space or comma separated, or `all` alone
                    (all = 75 80 86 89 90 100 120). Default: sm_120. Find yours
                    once: nvidia-smi --query-gpu=compute_cap --format=csv,noheader
                    (12.0 means sm_120). Each architecture adds the models of
                    every feature that has them: check the size first with
                    ngc registry model info <feature>:<version>_models_linux_sm<N>
  --version X.Y.Z.W SDK version (default: 1.3.0.0)
  --features LIST   features to fetch (default: nvvfxgreenscreen nvvfxbackgroundblur)
  --list            only run the read-only discovery command
                    ngc registry model list "nvidia/maxine/nvvfx*"   and exit
  --dry-run         print the ngc commands, run nothing
  -h, --help        show this help

An item whose directory already exists in the destination is skipped.
Documentation: docs/download.md
USAGE
}

die() {
    printf 'download.sh: %s\n' "$*" >&2
    exit 1
}

default_features="nvvfxgreenscreen nvvfxbackgroundblur"
# The architectures of the 1.3.0.0 Linux model packages.
all_archs=(75 80 86 89 90 100 120)
list_pattern="nvidia/maxine/nvvfx*"

dest="$HOME/Downloads/maxine"
archs_arg="sm_120"
version="1.3.0.0"
features_arg="$default_features"
dry_run=0
list_only=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dest | --archs | --version | --features)
            [ "$#" -ge 2 ] || die "option $1 needs a value"
            case "$1" in
                --dest) dest="$2" ;;
                --archs) archs_arg="$2" ;;
                --version) version="$2" ;;
                --features) features_arg="$2" ;;
            esac
            shift 2
            ;;
        --list)
            list_only=1
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown argument: $1"
            ;;
    esac
done

# --list: the read-only discovery command only.
if [ "$list_only" -eq 1 ]; then
    if [ "$dry_run" -eq 1 ]; then
        printf 'ngc registry model list "%s"\n' "$list_pattern"
        exit 0
    fi
    command -v ngc >/dev/null 2>&1 ||
        die "the NGC CLI ('ngc') is not on PATH. Install and configure it first: see docs/download.md"
    exec ngc registry model list "$list_pattern"
fi

[ -n "$dest" ] || die "--dest must not be empty"

[[ "$version" =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
    die "invalid version '$version' (expected four numbers such as 1.3.0.0)"

# Architectures: sm_120, sm120 or 120, or `all` alone. Normalised to the number.
read -r -a archs_raw <<<"${archs_arg//,/ }"
[ "${#archs_raw[@]}" -gt 0 ] || die "--archs needs at least one value"
archs=()
for a in "${archs_raw[@]}"; do
    if [ "$a" = "all" ]; then
        [ "${#archs_raw[@]}" -eq 1 ] ||
            die "'all' must be the only --archs entry (got '$archs_arg')"
        archs=("${all_archs[@]}")
    elif [[ "$a" =~ ^(sm_?)?([1-9][0-9]{1,2})$ ]]; then
        archs+=("${BASH_REMATCH[2]}")
    else
        die "invalid architecture '$a' (use sm_120, sm120, 120 or all; compute capability without the dot)"
    fi
done
# Drop duplicates, keep the order.
declare -A seen_arch=()
unique_archs=()
for a in "${archs[@]}"; do
    [ -n "${seen_arch[$a]:-}" ] && continue
    seen_arch[$a]=1
    unique_archs+=("$a")
done
archs=("${unique_archs[@]}")

read -r -a features <<<"${features_arg//,/ }"
[ "${#features[@]}" -gt 0 ] || die "--features needs at least one value"
for f in "${features[@]}"; do
    [[ "$f" =~ ^[a-z0-9_]+$ ]] || die "invalid feature name '$f'"
done

if [ "$dry_run" -eq 0 ] && ! command -v ngc >/dev/null 2>&1; then
    die "the NGC CLI ('ngc') is not on PATH. Install and configure it first: see docs/download.md"
fi

fetched=()
skipped=()
no_models=()

# fetch KIND REF DIRNAME
#   KIND     resource or model (the ngc registry sub-command)
#   REF      name:tag as known to NGC
#   DIRNAME  directory the NGC CLI creates below the destination
# Returns 0 when the item is present, skipped or (dry run) planned, and 1 when
# the download fails, with the NGC CLI's exit status in ngc_status. A failed
# download leaves nothing behind. The caller decides if that is fatal.
ngc_status=0
fetch() {
    local kind="$1" ref="$2" dirname="$3"
    local cmd=(ngc registry "$kind" download-version "$ref" --dest "$dest")

    if [ -d "$dest/$dirname" ]; then
        printf 'skip %s: %s already exists\n' "$ref" "$dest/$dirname" >&2
        skipped+=("$ref")
        return 0
    fi
    if [ "$dry_run" -eq 1 ]; then
        local line
        line=$(printf '%q ' "${cmd[@]}")
        printf '%s\n' "${line% }"
        fetched+=("$ref")
        return 0
    fi
    printf 'download %s\n' "$ref" >&2
    ngc_status=0
    "${cmd[@]}" || ngc_status=$?
    if [ "$ngc_status" -eq 0 ]; then
        fetched+=("$ref")
        return 0
    fi
    # The directory did not exist before this call (checked above), so whatever
    # is there now is a partial download. Remove exactly that path, so that the
    # next run retries the item instead of skipping it as already present.
    if [ -n "$dirname" ] && [ -d "$dest/$dirname" ]; then
        rm -rf -- "${dest:?}/${dirname:?}"
    fi
    return 1
}

if [ "$dry_run" -eq 0 ]; then
    mkdir -p "$dest"
fi

fetch resource "nvidia/maxine/vfx_sdk_core:${version}_linux" "vfx_sdk_core_v${version}_linux" ||
    die "download of the SDK core failed with status $ngc_status (nvidia/maxine/vfx_sdk_core:${version}_linux)"

for f in "${features[@]}"; do
    fetch model "nvidia/maxine/${f}:${version}_lib_linux" "${f}_v${version}_lib_linux" ||
        die "download of the library of '$f' failed with status $ngc_status (nvidia/maxine/${f}:${version}_lib_linux). Check the name with: download.sh --list"
done

# Models: tried for every feature and architecture. Some features have none,
# so a failure here is reported and is not fatal.
for f in "${features[@]}"; do
    for a in "${archs[@]}"; do
        if ! fetch model "nvidia/maxine/${f}:${version}_models_linux_sm${a}" \
            "${f}_v${version}_models_linux_sm${a}"; then
            printf 'models download for %s sm_%s failed with status %s. NGC also returns this when the feature has no models for that architecture: check with: ngc registry model list "nvidia/maxine/%s:*"\n' \
                "$f" "$a" "$ngc_status" "$f" >&2
            no_models+=("$f sm_$a")
        fi
    done
done

arch_hint=""
for a in "${archs[@]}"; do
    arch_hint="${arch_hint:+$arch_hint }sm_$a"
done
if [ "${#archs[@]}" -eq "${#all_archs[@]}" ] && [ "${archs[*]}" = "${all_archs[*]}" ]; then
    arch_hint="all"
fi
env_hint="MAXINE_VFX_SRC=$(printf '%q' "$dest") MAXINE_VFX_ARCHS=\"$arch_hint\""
configure_hint="maxine-vfx/configure.sh --src $(printf '%q' "$dest") --archs \"$arch_hint\" --features all --write"

summary() {
    local label_fetched="fetched"
    [ "$dry_run" -eq 1 ] && label_fetched="would fetch"
    printf 'Summary: %s %d, skipped (already present) %d, models not downloaded %d\n' \
        "$label_fetched" "${#fetched[@]}" "${#skipped[@]}" "${#no_models[@]}"
    local x
    for x in "${fetched[@]}"; do printf '  %s: %s\n' "$label_fetched" "$x"; done
    for x in "${skipped[@]}"; do printf '  skipped: %s\n' "$x"; done
    for x in "${no_models[@]}"; do printf '  models not downloaded: %s\n' "$x"; done
    if [ "$dry_run" -eq 1 ]; then
        printf 'dry run: nothing was downloaded\n'
    fi
    printf 'Next step: %s\n' "$configure_hint"
    printf '  then: cd maxine-vfx && makepkg -f\n'
    printf '  or, without selection.conf: cd maxine-vfx && %s makepkg -f\n' "$env_hint"
}

# In a dry run stdout carries only the ngc commands, so notes go to stderr.
if [ "$dry_run" -eq 1 ]; then
    summary >&2
else
    summary
fi
