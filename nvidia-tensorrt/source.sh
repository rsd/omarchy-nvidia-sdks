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
#     it can be checked against the pinned SHA-256), else exactly one
#     extracted tree one level down (e.g. TensorRT-11.4.0.106/).
# The libraries are in lib/ or, as some TensorRT archives ship them, in
# targets/x86_64-linux-gnu/lib/ (with or without a lib/ link to it); either
# is accepted, and the tree is packaged as shipped.
# trt_check_archive and trt_check_tree refuse devices, fifos and sockets,
# and symbolic links whose target is absolute or leads out of the tree.
# Functions return 1 with a message on stderr when the source is not usable.

# trt_locate <path>: sets trt_layout (archive or tree) and trt_path (the
# absolute path of the archive file or of the tree's root).
trt_locate() {
    local src=$1 f
    local -a archives=() trees=()
    trt_layout='' trt_path=''
    if [[ $src == *$'\n'* ]]; then
        echo "the source path contains a newline, which is not supported: rename it" >&2
        return 1
    fi
    if [[ -f $src ]]; then
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
    for f in "$src"/TensorRT-*.tar.*; do
        [[ -f $f ]] && archives+=("$f")
    done
    if ((${#archives[@]} > 1)); then
        {
            echo "$src holds ${#archives[@]} TensorRT archives; keep one there, or name the archive itself:"
            printf '  %s\n' "${archives[@]}"
        } >&2
        return 1
    fi
    if ((${#archives[@]} == 1)); then
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
# trt_features. Returns 1 when the archive cannot be read or holds no
# include/NvInferVersion.h.
trt_scan() {
    local layout=$1 path=$2 listing header prefix
    trt_version='' trt_root_entry='' trt_missing=() trt_features=()
    if [[ $layout == tree ]]; then
        listing=$(cd "$path" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n')
        trt_version=$(trt_header_version <"$path/include/NvInferVersion.h")
        trt_scan_names "$listing"
        return 0
    fi
    listing=$(bsdtar -tf "$path") || { echo "$path: cannot read the archive (damaged or not a tar?)" >&2; return 1; }
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

# trt_check_archive <archive> [root entry]: refuses a device, fifo or socket
# member and a symbolic link whose target is absolute or climbs out of the
# root entry (the TensorRT tree's top directory in the archive; else the
# archive's top), from bsdtar's mtree listing, before anything is
# extracted. Names are as bsdtar encodes them (a space is \040). A link is
# judged by its names only; the extracted tree is checked again, with the
# links resolved, by trt_check_tree.
trt_check_archive() {
    local path=$1 root=${2:-} mt line name rest type target dir rel
    mt=$(bsdtar -cf - --format=mtree --options='!all,type,link' "@$path" 2>&1) ||
        { echo "$path: cannot read the archive (damaged or not a tar?): $mt" >&2; return 1; }
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
