#!/usr/bin/env bash
# The licence guard: fails when a file that must never be committed is about
# to be. This repository holds recipes only; nothing from NVIDIA (SDK files,
# libraries, headers, models, archives, licence PDFs) may enter it.
#
#   check-no-nvidia.sh [--staged]        # the index (default; pre-commit and
#                                        # pre-merge-commit hooks)
#   check-no-nvidia.sh --all             # every tracked and untracked, not
#                                        # ignored file of the work tree
#   check-no-nvidia.sh --range REV...    # every file added or modified by the
#                                        # commits `git rev-list REV...` lists
#                                        # (pre-push hook), e.g.
#                                        #   --range origin/main..main
#                                        #   --range main --not --remotes=origin
#
# --all looks at the work tree only, not at the history; --range covers
# commits. Hooks can be bypassed with --no-verify: the guard is a safety net,
# not an access control.
#
# Every added, modified or type-changed entry is checked (a rename counts as
# an addition; only deletions are skipped). An entry fails when:
#   - its path matches an NVIDIA or binary pattern (libraries, models,
#     archives, PDFs, SDK headers, a VideoFX/, ARSDK/, Audio_Effects_SDK/
#     or .ngc/ component, an NGC download directory such as
#     nvvfxgreenscreen_v1.3.0.0_lib_linux/ or afx_denoiser_v3.0.0-lib/, an
#     unpacked Optical Flow SDK directory (Optical_Flow_SDK_<version>/, in
#     any letter case), an SDK's top-level name directly under a recipe
#     directory such as maxine-afx/features/, maxine-ar/Changelog.txt or
#     nvidia-optical-flow/NvOFInterface/ or nvidia-tensorrt/python/, or an
#     unpacked TensorRT-<version>/ directory);
#   - it is a submodule (gitlink), or, in --all, a nested repository;
#   - it is a symbolic link whose target is absolute or leaves the repository;
#   - its content is larger than 1 MiB, starts with a binary or archive magic
#     number (ELF, gzip, zip, PDF, xz, zstd, bzip2, ar, POSIX tar), has a NUL
#     byte in its first 8 KiB, or carries a marker of an NVIDIA file: an
#     NVIDIA copyright line, the licence agreement's title on a line of its
#     own, or the first lines of an SDK's README, Changelog,
#     install_feature.sh or download_features.sh.
# Staged and committed content is read from the object database with git
# cat-file (read-only), so what is checked is what would be committed or
# pushed. Exit status: 0 clean, 1 offending files, 2 usage or git error.
set -euo pipefail

prog=${0##*/}
max_size=$((1024 * 1024))

usage() {
    echo "usage: $prog [--staged | --all | --range REV...]" >&2
    exit 2
}

mode=staged range=()
if (($# > 0)); then
    case $1 in
        --staged) (($# == 1)) || usage; mode=staged ;;
        --all) (($# == 1)) || usage; mode=all ;;
        --range) (($# >= 2)) || usage; mode=range; shift; range=("$@") ;;
        *) usage ;;
    esac
fi

top=$(git rev-parse --show-toplevel 2>/dev/null) ||
    { echo "$prog: not inside a git work tree" >&2; exit 2; }
cd "$top"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# Prints the reason when the path is forbidden, nothing otherwise. A path may
# hold any byte but NUL (spaces, newlines): it is matched with patterns and
# parameter expansion only, never split with read.
path_reason() {
    local path=$1 base lcbase rest component
    base=${path##*/}
    lcbase=${base,,}

    # Build output (also in .gitignore).
    case /$path/ in
        */build/* | */target/*) echo "build output"; return ;;
    esac
    case $path in
        maxine-vfx/src/* | maxine-vfx/pkg/* | maxine-ar/src/* | maxine-ar/pkg/* | \
            maxine-afx/src/* | maxine-afx/pkg/* | nvidia-optical-flow/src/* | nvidia-optical-flow/pkg/* | \
            nvidia-tensorrt/src/* | nvidia-tensorrt/pkg/*)
            echo "makepkg work directory"; return ;;
    esac

    # An SDK unpacked straight into a recipe directory (MAXINE_*_SRC and
    # NVIDIA_OF_SRC default to it, and a tree there needs no VideoFX/, ARSDK/ or
    # Audio_Effects_SDK/ component): the SDKs' top-level names. The recipe's
    # own files (PKGBUILD, *.sh, README.md, tests/) are none of them; an
    # SDK's README.md is caught by its content.
    case $path in
        maxine-vfx/* | maxine-ar/* | maxine-afx/*)
            rest=${path#*/}
            case $rest in
                lib/* | include/* | features/* | external/* | share/* | samples/* | \
                    licenses/* | nvafx/* | bin/* | docs/* | version.h | Changelog.txt)
                    echo "SDK tree in the recipe directory (${path%%/*}/${rest%%/*})"; return ;;
            esac
            ;;
        nvidia-optical-flow/*)
            # The Optical Flow SDK's top-level directories, and those of the
            # tree its PKGBUILD installs (/opt/nvidia/optical-flow).
            rest=${path#*/}
            case $rest in
                NvOFInterface/* | NvOFBasicSamples/* | NvOFTracker/* | NvOFFRUC/* | Common/* | \
                    include/* | fruc/* | samples/* | tracker/* | licenses/* | lib/* | bin/*)
                    echo "SDK tree in the recipe directory (${path%%/*}/${rest%%/*})"; return ;;
            esac
            ;;
        nvidia-tensorrt/*)
            # The TensorRT tarball's top-level directories, targets/ among them
            # (targets/x86_64-linux-gnu/; the recipe's own README.md, tests/
            # and scripts are none of them).
            rest=${path#*/}
            case $rest in
                include/* | lib/* | bin/* | python/* | samples/* | data/* | doc/* | targets/*)
                    echo "SDK tree in the recipe directory (${path%%/*}/${rest%%/*})"; return ;;
            esac
            ;;
    esac

    # NVIDIA SDK file names.
    case $base in
        nvVideoEffects.h | nvCVImage.h | nvCVStatus.h | nvVFX*.h | nvAudioEffects.h | videofx_version.h | \
            nvAR.h | nvAR_defs.h | nvOpticalFlow*.h | NvFRUC.h | NvOFTracker.h | \
            NvInfer*.h | NvOnnxParser*.h | NvOnnxConfig.h)
            echo "NVIDIA SDK header"; return ;;
        VFXSDK_*) echo "NVIDIA SDK archive"; return ;;
    esac

    # Binary and archive extensions (case-insensitive). Libraries are known
    # by their suffix, whatever their name.
    case $lcbase in
        *.pkg.tar*) echo "built package"; return ;;
        *.so | *.so.* | *.a) echo "library"; return ;;
        *.trtpkg | *.engine) echo "TensorRT model"; return ;;
        *.trtpkg.*) echo "TensorRT model sidecar"; return ;;
        *.tgz | *.tar | *.tar.* | *.zip | *.whl) echo "archive"; return ;;
        *.pdf) echo "PDF document"; return ;;
        *.log) echo "log file"; return ;;
    esac

    # SDK trees and the NGC configuration: any path component.
    case /${path,,}/ in
        */external/cuda/* | */external/tensorrt/*) echo "bundled CUDA or TensorRT"; return ;;
    esac
    case /$path/ in
        */VideoFX/*) echo "SDK tree (VideoFX/)"; return ;;
        */ARSDK/*) echo "SDK tree (ARSDK/)"; return ;;
        */Audio_Effects_SDK/*) echo "SDK tree (Audio_Effects_SDK/)"; return ;;
        */.ngc/*) echo "NGC configuration"; return ;;
    esac

    # NGC download directories: a directory component (not the file name)
    # shaped <name>_v<digit>..., e.g. nvvfxgreenscreen_v1.3.0.0_lib_linux,
    # ar_sdk_core_v1.2.0.0_linux, afx_denoiser_v3.0.0-lib. The afx_ shape
    # needs its underscore, so the recipe directory maxine-afx/ never matches.
    # The same loop refuses an unpacked Optical Flow SDK, whose zip
    # optical_flow_sdk_<version>.zip holds Optical_Flow_SDK_<version>/; a
    # file named like it (docs/optical_flow_sdk_notes.md) is not refused.
    rest=''
    [[ $path != */* ]] || rest=${path%/*}
    while [[ -n $rest ]]; do
        component=${rest%%/*}
        case $component in
            vfx_sdk_core_v[0-9]* | nvvfx*_v[0-9]* | nvafx*_v[0-9]* | \
                ar_sdk_core_v[0-9]* | nvar*_v[0-9]* | \
                maxine_linux_audio_effects_sdk_v[0-9]* | afx_*_v[0-9]*)
                echo "NGC download directory"; return ;;
        esac
        # The Optical Flow SDK's zip unpacked (its top-level directory).
        case ${component,,} in
            optical_flow_sdk_*) echo "SDK tree (Optical_Flow_SDK_*/)"; return ;;
        esac
        # The TensorRT tarball unpacked (TensorRT-<version>.Linux.../).
        case $component in
            TensorRT-*) echo "SDK tree (TensorRT-*/)"; return ;;
        esac
        if [[ $rest == */* ]]; then rest=${rest#*/}; else rest=''; fi
    done
}

# Prints the reason when a symbolic link at <path> pointing to <target> is
# forbidden: an absolute target, or one that leaves the repository.
link_reason() {
    local path=$1 target=$2 rest component depth=0
    [[ -n $target ]] || return 0
    if [[ $target == /* ]]; then
        echo "symbolic link to an absolute path"
        return
    fi
    # The link's directory, then the target, resolved lexically.
    rest=''
    [[ $path != */* ]] || rest=${path%/*}/
    rest+=$target
    while [[ -n $rest ]]; do
        component=${rest%%/*}
        case $component in
            '' | .) ;;
            ..) depth=$((depth - 1)) ;;
            *) depth=$((depth + 1)) ;;
        esac
        if ((depth < 0)); then
            echo "symbolic link leaving the repository"
            return
        fi
        if [[ $rest == */* ]]; then rest=${rest#*/}; else rest=''; fi
    done
}

hex() { od -An -v -tx1 | tr -d ' \n'; }

# Text that marks an NVIDIA file under any name (extended regular
# expressions, matched case-insensitively): copyright lines of SDK headers,
# sources and licence files, the licence agreement's title on a line of its
# own (prose that names the agreement is fine), the first lines of the SDKs'
# README.md (VFX, AR, Audio Effects), Changelog.txt, the VFX and AR
# features/install_feature.sh and the Audio Effects
# features/download_features.sh. The bracketed spaces keep this script from
# matching its own patterns.
markers=(
    -e 'copyright.*nvidia[ ]corporation'
    -e 'nvidia[ ]corporation.*all[ ]rights[ ]reserved'
    -e '^[[:space:]]*nvidia[ ]software[ ]license[ ]agreement[[:space:]]*$'
    -e '^nvidia[ ]video[ ]effects[ ]sdk[[:space:]]*$'
    -e '^nvidia[ ]augmented[ ]reality[ ]sdk[[:space:]]*$'
    -e '^nvidia[ ]audioeffects[ ]sdk[[:space:]]*$'
    -e '^changelog[ ][(]v[0-9]+[.][0-9]'
    -e 'feature[ ]installation[ ]script[ ]for[ ]vfx[ ]sdk'
    -e 'feature[ ]installation[ ]script[ ]for[ ]arsdk'
    -e '^#[ ]set[ ]ngc[ ]org/team[ ]below[ ]if[ ]needed'
)

# Prints the reason when the content of <file> (a regular file of <size>
# bytes) is forbidden, nothing otherwise.
content_reason() {
    local file=$1 size=$2 magic
    if ((size > max_size)); then
        echo "larger than 1 MiB ($size bytes)"
        return
    fi
    magic=$(head -c 8 -- "$file" | hex)
    case $magic in
        7f454c46*) echo "ELF binary"; return ;;
        1f8b*) echo "gzip data"; return ;;
        504b0304*) echo "zip data"; return ;;
        25504446*) echo "PDF document"; return ;;
        fd377a585a*) echo "xz data"; return ;;
        28b52ffd*) echo "zstd data"; return ;;
        425a68*) echo "bzip2 data"; return ;;
        213c617263683e0a*) echo "ar archive"; return ;;
    esac
    # POSIX tar: "ustar" at offset 257. (head may stop tail early.)
    if ((size >= 262)) && [[ $({ tail -c +258 -- "$file" || true; } | head -c 5 | hex) == 7573746172 ]]; then
        echo "tar archive"
        return
    fi
    if (($(head -c 8192 -- "$file" | tr -dc '\000' | wc -c) > 0)); then
        echo "binary data (a NUL byte in the first 8 KiB)"
        return
    fi
    if LC_ALL=C grep -qaiE "${markers[@]}" -- "$file"; then
        echo "NVIDIA file content (copyright line or SDK marker)"
    fi
}

failures=0
report() {
    local shown=$1
    [[ $shown != *[[:cntrl:]]* ]] || printf -v shown '%q' "$1"
    printf '%s: %s\n' "$shown" "$2"
    failures=$((failures + 1))
}

# check_object <path> <mode> <object id>: an index or tree entry.
check_object() {
    local path=$1 objmode=$2 oid=$3 reason size
    reason=$(path_reason "$path")
    if [[ -z $reason ]]; then
        case $objmode in
            160000) reason="submodule (gitlink)" ;;
            120000) reason=$(link_reason "$path" "$(git cat-file blob "$oid")") ;;
            100644 | 100755)
                size=$(git cat-file -s "$oid")
                if ((size > max_size)); then
                    reason="larger than 1 MiB ($size bytes)"
                else
                    git cat-file blob "$oid" >"$tmp/blob"
                    reason=$(content_reason "$tmp/blob" "$size")
                fi
                ;;
            *) reason="unexpected entry (mode $objmode)" ;;
        esac
    fi
    [[ -z $reason ]] || report "$path" "$reason"
}

# Reads `git diff --raw -z --no-abbrev --no-renames` records on stdin and
# checks each entry once.
check_raw() {
    local meta path dstmode dstoid
    local -A seen=()
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        read -r _ dstmode _ dstoid _ <<<"${meta#:}"
        # An unmerged entry has no object yet (git refuses to commit it).
        [[ $dstmode != 000000 ]] || continue
        [[ -z ${seen[$dstmode:$dstoid:$path]:-} ]] || continue
        seen[$dstmode:$dstoid:$path]=1
        check_object "$path" "$dstmode" "$dstoid"
    done
}

check_staged() {
    # Without a HEAD (no commit yet) git compares with the empty tree. In a
    # hook, GIT_INDEX_FILE names the index being committed (commit -a,
    # commit <path>).
    git diff --cached --raw -z --no-abbrev --no-renames --diff-filter=d \
        --ignore-submodules=none >"$tmp/raw" ||
        { echo "$prog: git diff --cached failed" >&2; exit 2; }
    check_raw <"$tmp/raw"
}

check_range() {
    git rev-list "${range[@]}" -- >"$tmp/commits" ||
        { echo "$prog: git rev-list ${range[*]} failed" >&2; exit 2; }
    # -m compares a merge with each of its parents, so what the merge itself
    # brings (a conflict resolution) is checked too.
    git diff-tree --stdin -r -m --root --no-commit-id --raw -z --no-abbrev \
        --no-renames --diff-filter=d --ignore-submodules=none <"$tmp/commits" >"$tmp/raw" ||
        { echo "$prog: git diff-tree failed" >&2; exit 2; }
    check_raw <"$tmp/raw"
}

check_all() {
    local path reason
    git ls-files -z -co --exclude-standard >"$tmp/files" ||
        { echo "$prog: git ls-files failed" >&2; exit 2; }
    while IFS= read -r -d '' path; do
        # An untracked nested repository is listed as dir/.
        path=${path%/}
        reason=$(path_reason "$path")
        if [[ -z $reason ]]; then
            if [[ -L $path ]]; then
                reason=$(link_reason "$path" "$(readlink -- "$path")")
            elif [[ -d $path ]]; then
                reason="submodule or nested repository"
            elif [[ -f $path ]]; then
                reason=$(content_reason "$path" "$(stat -c %s -- "$path")")
            fi
            # Anything else is a tracked file deleted from the work tree.
        fi
        [[ -z $reason ]] || report "$path" "$reason"
    done < <(sort -zu "$tmp/files")
}

case $mode in
    staged) check_staged ;;
    all) check_all ;;
    range) check_range ;;
esac

if ((failures > 0)); then
    echo "This repository holds recipes only; NVIDIA files must never be committed (README, licence rules)." >&2
    exit 1
fi
echo "ok: no NVIDIA or binary files ($mode)"
