# shellcheck shell=bash disable=SC2034 # the trt_* variables are the functions' results, for the caller
# Finds and checks a TensorRT download: the archive NVIDIA publishes, a
# directory holding it, or an extracted tree. Sourced by configure.sh and by
# the PKGBUILD's prepare(); it only defines functions, reads the source and
# never writes to it, extracts it or runs anything from it.
#
# A source path is one of:
#   - an archive file (a tar, e.g. TensorRT-...-Release-external.tar.zst);
#   - an extracted tree: a directory whose include/ holds NvInferVersion.h;
#   - a directory holding exactly one TensorRT-*.tar.* archive (preferred:
#     it can be checked against the pinned SHA-256; archives named for the
#     ARM build do not count when exactly one other is there), else exactly
#     one extracted tree one level down (e.g. TensorRT-11.4.0.106/).
# The libraries are in lib/ or, as some TensorRT archives ship them, in
# targets/x86_64-linux-gnu/lib/ (with or without a lib/ link to it); either
# is accepted, and the tree is packaged as shipped.
# trt_check_archive and trt_check_tree refuse devices, fifos and sockets,
# and symbolic links whose target is absolute or leads out of the tree.
# The ARM build of TensorRT (aarch64, or sbsa as NVIDIA also labels it) is
# refused by its file name (trt_locate), by its member names (trt_scan,
# trt_check_archive) and, for an extracted tree, by the machine of
# lib/libnvinfer.so (trt_scan): the recipe packages the x86_64 build.
# Functions return 1 with a message on stderr when the source is not usable.
#
# The caller may set trt_expected_archive (the archive file name the recipe
# packages), trt_expected_version (the recipe's version) and
# trt_download_url (where to get it): the ARM refusal names them.

# trt_name_version <name>: the version in a TensorRT file or directory name
# (TensorRT-11.4.0.106..., TensorRT-Enterprise-11.4.0.106-...); nothing when
# the name holds none.
trt_name_version() {
    [[ $1 =~ (^|/)TensorRT-(Enterprise-)?([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(-|/|$) ]] &&
        echo "${BASH_REMATCH[3]}"
    return 0
}

# trt_arm_refusal <path> [version]: the message for an ARM build, on stderr;
# returns 1. <version> is the ARM build's (default: read from <path>'s
# name); when it is not the recipe's, the message says that NVIDIA
# publishes it for ARM only, and which x86_64 version to download.
trt_arm_refusal() {
    local hint="download the Linux x86_64 one" arm=${2:-} want=${trt_expected_version:-}
    [[ -n $arm ]] || arm=$(trt_name_version "${1##*/}")
    [[ -n $want ]] || want=$(trt_name_version "${trt_expected_archive:-}")
    [[ -z ${trt_expected_archive:-} ]] || hint+=": ${trt_expected_archive}"
    [[ -z ${trt_download_url:-} ]] || hint+=" from ${trt_download_url}"
    if [[ -n $arm && -n $want && $arm != "$want" ]]; then
        hint+=" (NVIDIA publishes TensorRT $arm for ARM only; the x86_64 one to download is $want)"
    fi
    echo "$1: this is the ARM (aarch64) build of TensorRT; $hint" >&2
    return 1
}

# trt_arm_name <file name>: whether the name is NVIDIA's for an ARM build
# (TensorRT-...-Linux-aarch64-... or -Linux-sbsa-...).
trt_arm_name() {
    case $1 in
        *-Linux-aarch64-* | *-Linux-sbsa-*) return 0 ;;
    esac
    return 1
}

# trt_arm_members <listing>: whether a listing of member or file names (one
# per line, with or without a top directory, plain or as bsdtar's mtree
# lines) holds an ARM build's names: a Python wheel for linux_aarch64, or a
# targets/aarch64-linux-gnu or targets/sbsa-linux directory.
trt_arm_members() {
    grep -qE -e '_aarch64\.whl( |$)' -e '(^|/)targets/(aarch64-linux-gnu|sbsa-linux)(/| |$)' <<<"$1"
}

# trt_arm_elf <tree>: whether the tree's libnvinfer (lib/libnvinfer.so*, or
# the same in targets/*/lib/) is an ELF file for aarch64 (e_machine 0xb7,
# bytes 18-19, little-endian). Reads 20 bytes of one library; a file that
# is not ELF (or cannot be read) is not judged here.
trt_arm_elf() {
    local f bytes
    local -a b
    for f in "$1"/lib/libnvinfer.so* "$1"/targets/*/lib/libnvinfer.so*; do
        [[ -f $f ]] || continue
        bytes=$(od -An -tx1 -w20 -N20 -- "$f" 2>/dev/null) || continue
        read -r -a b <<<"$bytes"
        ((${#b[@]} == 20)) || continue
        [[ ${b[0]}${b[1]}${b[2]}${b[3]} == 7f454c46 ]] || continue
        [[ ${b[18]}${b[19]} == b700 ]] && return 0
        return 1
    done
    return 1
}

# trt_refuse_arm_listing <shown path> <listing>: returns 1, with the ARM
# refusal, when an archive's member listing is the ARM build's. Its version
# is read from the archive's top directory (TensorRT-<version>/), else from
# the file name (which may have been changed).
trt_refuse_arm_listing() {
    local v
    trt_arm_members "$2" || return 0
    v=$(trt_name_version "$(head -n 1 <<<"$2")")
    [[ -n $v ]] || v=$(trt_name_version "${1##*/}")
    trt_arm_refusal "$1" "$v"
}

# trt_refuse_arm_archive <archive> [shown path]: the same for an archive
# file, named as <shown path> (default <archive>); an archive that cannot be
# listed is not judged here (returns 0). For a checksum mismatch, so that
# the ARM build is reported as such rather than as a damaged download.
trt_refuse_arm_archive() {
    local listing
    listing=$(bsdtar -tf "$1" 2>/dev/null) || return 0
    trt_refuse_arm_listing "${2:-$1}" "$listing"
}

# trt_locate <path>: sets trt_layout (archive or tree), trt_path (the
# absolute path of the archive file or of the tree's root) and
# trt_arm_skipped (the ARM archives set aside in a directory, if any).
trt_locate() {
    local src=$1 f
    local -a archives=() arm=() trees=()
    trt_layout='' trt_path='' trt_arm_skipped=()
    if [[ $src == *$'\n'* ]]; then
        echo "the source path contains a newline, which is not supported: rename it" >&2
        return 1
    fi
    if [[ -f $src ]]; then
        trt_arm_name "${src##*/}" && { trt_arm_refusal "$src"; return 1; }
        case ${src##*/} in
            *.tar | *.tar.*) ;;
            *)
                echo "$src: not a tar archive (expected a name such as TensorRT-*.tar.zst)" >&2
                return 1
                ;;
        esac
        trt_layout=archive trt_path=$(realpath -- "$src")
        return 0
    fi
    if [[ ! -d $src ]]; then
        echo "$src: not found (neither a TensorRT archive nor a directory)" >&2
        return 1
    fi
    if [[ -f $src/include/NvInferVersion.h ]]; then
        trt_layout=tree trt_path=$(realpath -- "$src")
        return 0
    fi
    # Archives named for the ARM build are set aside when exactly one other
    # archive is there: that one is the x86_64 build to use.
    for f in "$src"/TensorRT-*.tar.*; do
        [[ -f $f ]] || continue
        if trt_arm_name "${f##*/}"; then
            arm+=("$f")
        else
            archives+=("$f")
        fi
    done
    if ((${#archives[@]} == 1)); then
        trt_arm_skipped=("${arm[@]}")
    else
        archives+=("${arm[@]}")
    fi
    if ((${#archives[@]} > 1)); then
        {
            echo "$src holds ${#archives[@]} TensorRT archives; keep one there, or name the archive itself:"
            for f in "${archives[@]}"; do
                if trt_arm_name "${f##*/}"; then
                    echo "  $f (the ARM (aarch64) build: not this one)"
                else
                    echo "  $f"
                fi
            done
        } >&2
        return 1
    fi
    if ((${#archives[@]} == 1)); then
        trt_arm_name "${archives[0]##*/}" && { trt_arm_refusal "${archives[0]}"; return 1; }
        trt_layout=archive trt_path=$(realpath -- "${archives[0]}")
        return 0
    fi
    for f in "$src"/*/include/NvInferVersion.h; do
        [[ -f $f ]] && trees+=("${f%/include/NvInferVersion.h}")
    done
    if ((${#trees[@]} > 1)); then
        {
            echo "$src holds ${#trees[@]} extracted TensorRT trees; name one of them:"
            printf '  %s\n' "${trees[@]}"
        } >&2
        return 1
    fi
    if ((${#trees[@]} == 1)); then
        trt_layout=tree trt_path=$(realpath -- "${trees[0]}")
        return 0
    fi
    echo "$src holds no TensorRT archive (TensorRT-*.tar.*) and no extracted tree (include/NvInferVersion.h)" >&2
    return 1
}

# trt_header_version: reads NvInferVersion.h on stdin and prints the version,
# major.minor.patch.build. TensorRT defines NV_TENSORRT_MAJOR and the others
# either as numbers or as other macros (e.g. TRT_MAJOR_ENTERPRISE); both are
# followed. Prints nothing when the version is not found.
trt_header_version() {
    local line name value part v i
    local -A defs=()
    local -a parts=()
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%%//*}
        line=${line%%/\**}
        if [[ $line =~ ^[[:space:]]*#[[:space:]]*define[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*$ ]]; then
            name=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
            [[ -n ${defs[$name]:-} ]] || defs[$name]=$value
        fi
    done
    for part in MAJOR MINOR PATCH BUILD; do
        v=${defs[NV_TENSORRT_$part]:-${defs[TRT_${part}_ENTERPRISE]:-}}
        # A macro defined as another macro: follow a few levels.
        for ((i = 0; i < 4; i++)); do
            [[ $v =~ ^[A-Za-z_] && -n ${defs[$v]:-} ]] || break
            v=${defs[$v]}
        done
        [[ $v =~ ^[0-9]+$ ]] || return 0
        parts+=("$((10#$v))")
    done
    (
        IFS=.
        echo "${parts[*]}"
    )
}

# The files a usable tree must hold, relative to its root (a library by its
# name stem: lib/<stem>.so or a versioned lib/<stem>.so.<n>, or the same in
# targets/x86_64-linux-gnu/lib/).
trt_required_headers=(include/NvInferVersion.h include/NvInfer.h include/NvOnnxParser.h)
trt_required_libs=(libnvinfer libnvinfer_plugin libnvonnxparser)

# trt_scan_names <listing>: from a newline-separated list of paths relative
# to the root (directories may end in /), sets trt_missing (the required
# files absent) and trt_features (headers libs, then whichever of trtexec
# python samples are present).
trt_scan_names() {
    local listing=$1 h l
    trt_missing=() trt_features=()
    local headers_ok=1 libs_ok=1
    for h in "${trt_required_headers[@]}"; do
        grep -qxF -- "$h" <<<"$listing" || { trt_missing+=("$h"); headers_ok=0; }
    done
    for l in "${trt_required_libs[@]}"; do
        grep -qE "^(targets/x86_64-linux-gnu/)?lib/${l}\.so(\.[0-9.]+)?$" <<<"$listing" ||
            { trt_missing+=("lib/$l.so"); libs_ok=0; }
    done
    ((headers_ok)) && trt_features+=(headers)
    ((libs_ok)) && trt_features+=(libs)
    grep -qxE '(targets/x86_64-linux-gnu/)?bin/trtexec' <<<"$listing" && trt_features+=(trtexec)
    grep -qE '^python/.*\.whl$' <<<"$listing" && trt_features+=(python)
    grep -qE '^(targets/x86_64-linux-gnu/)?samples/.' <<<"$listing" && trt_features+=(samples)
    return 0
}

# trt_scan <layout> <path>: sets trt_version (empty when the header gives
# none), trt_root_entry (for an archive: the top directory inside it, empty
# when the files are at its top; for a tree: empty), trt_missing and
# trt_features. Returns 1 when the archive cannot be read, holds no
# include/NvInferVersion.h, or is the ARM build (its member names; for a
# tree, also the machine of lib/libnvinfer.so).
trt_scan() {
    local layout=$1 path=$2 listing header prefix
    trt_version='' trt_root_entry='' trt_missing=() trt_features=()
    if [[ $layout == tree ]]; then
        listing=$(cd "$path" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n')
        if trt_arm_members "$listing" || trt_arm_elf "$path"; then
            trt_arm_refusal "$path" "$(trt_header_version <"$path/include/NvInferVersion.h" 2>/dev/null)"
            return 1
        fi
        trt_version=$(trt_header_version <"$path/include/NvInferVersion.h")
        trt_scan_names "$listing"
        return 0
    fi
    listing=$(bsdtar -tf "$path") || { echo "$path: cannot read the archive (damaged or not a tar?)" >&2; return 1; }
    trt_refuse_arm_listing "$path" "$listing" || return 1
    # The version header, at the top or one directory down; its entry name
    # as stored (it may start with ./).
    header=$(grep -m1 -E '^(\./)?([^/]+/)?include/NvInferVersion\.h$' <<<"$listing" || true)
    if [[ -z $header ]]; then
        echo "$path: no include/NvInferVersion.h in the archive: this is not a TensorRT archive" >&2
        return 1
    fi
    prefix=${header%include/NvInferVersion.h}
    trt_root_entry=${prefix#./}
    trt_root_entry=${trt_root_entry%/}
    trt_version=$(bsdtar -xOqf "$path" "$header" | trt_header_version) ||
        { echo "$path: cannot read $header from the archive" >&2; return 1; }
    trt_scan_names "$(awk -v p="$prefix" 'index($0, p) == 1 { s = substr($0, length(p) + 1); sub(/\/$/, "", s); if (s != "") print s }' <<<"$listing")"
}

# trt_lexically_inside <relative path>: whether it never climbs above where
# it starts (a .. beyond the start), read as names only.
trt_lexically_inside() {
    local part depth=0
    local -a parts=()
    IFS=/ read -r -a parts <<<"$1"
    for part in "${parts[@]}"; do
        case $part in
            '' | .) ;;
            ..)
                ((depth > 0)) || return 1
                depth=$((depth - 1))
                ;;
            *) depth=$((depth + 1)) ;;
        esac
    done
}

# trt_check_archive <archive> [root entry] [shown path]: refuses the ARM
# build (by its member names, named as <shown path>, default <archive>), a
# device, fifo or socket member and a symbolic link whose target is
# absolute or climbs out of the root entry (the TensorRT tree's top
# directory in the archive; else the archive's top), from bsdtar's mtree
# listing, before anything is extracted. Names are as bsdtar encodes them
# (a space is \040). A link is judged by its names only; the extracted tree
# is checked again, with the links resolved, by trt_check_tree.
trt_check_archive() {
    local path=$1 root=${2:-} shown=${3:-$1} mt line name rest type target dir rel
    mt=$(bsdtar -cf - --format=mtree --options='!all,type,link' "@$path" 2>&1) ||
        { echo "$path: cannot read the archive (damaged or not a tar?): $mt" >&2; return 1; }
    if trt_arm_members "$mt"; then
        trt_arm_refusal "$shown"
        return 1
    fi
    while IFS= read -r line; do
        [[ -n $line && $line != '#'* && $line != /* ]] || continue
        name=${line%% *} rest=" ${line#* } "
        name=${name#./}
        if [[ $rest != *' type='* ]]; then
            echo "$path: no type for member $name in bsdtar's listing; refusing the archive" >&2
            return 1
        fi
        type=${rest#* type=} type=${type%% *}
        case $type in
            file | dir) ;;
            link)
                target=${rest#* link=} target=${target%% *}
                if [[ $target == /* ]]; then
                    echo "$path: member $name is a symbolic link to an absolute path ($target); refusing the archive" >&2
                    return 1
                fi
                if [[ $name == */* ]]; then dir=${name%/*}; else dir=.; fi
                rel=$dir/$target
                [[ -z $root || $rel != "$root"/* ]] || rel=${rel#"$root"/}
                if ! trt_lexically_inside "$rel"; then
                    echo "$path: member $name is a symbolic link leading out of the TensorRT tree ($target); refusing the archive" >&2
                    return 1
                fi
                ;;
            *)
                echo "$path: member $name is a special file ($type: a device, fifo or socket); refusing the archive" >&2
                return 1
                ;;
        esac
    done <<<"$mt"
}

# trt_check_tree <dir>: refuses a device, fifo or socket in the tree and a
# symbolic link whose target is absolute or, resolved, lies outside it.
trt_check_tree() {
    local top special link target resolved
    top=$(realpath -- "$1") || return 1
    special=$(find "$top" -mindepth 1 \( ! -type f ! -type d ! -type l \) -printf '%P\n' -quit)
    if [[ -n $special ]]; then
        echo "$top: $special is a special file (a device, fifo or socket); refusing the tree" >&2
        return 1
    fi
    # The absolute links first, so that a link to one (a chain) is not the
    # one named.
    while IFS= read -r -d '' link; do
        target=$(readlink -- "$link")
        if [[ $target == /* ]]; then
            echo "$top: ${link#"$top"/}: a symbolic link to an absolute path ($target); refusing the tree" >&2
            return 1
        fi
    done < <(find "$top" -mindepth 1 -type l -print0 | sort -z)
    while IFS= read -r -d '' link; do
        target=$(readlink -- "$link")
        if ! resolved=$(realpath -m -- "${link%/*}/$target" 2>/dev/null) ||
            [[ $resolved != "$top" && $resolved != "$top"/* ]]; then
            echo "$top: ${link#"$top"/}: a symbolic link leaving the TensorRT tree ($target); refusing the tree" >&2
            return 1
        fi
    done < <(find "$top" -mindepth 1 -type l -print0 | sort -z)
}

# trt_sha256 <file>: prints the file's SHA-256 (64 lowercase hex digits).
trt_sha256() {
    local sum
    sum=$(sha256sum -- "$1") || return 1
    printf '%s\n' "${sum%% *}"
}
