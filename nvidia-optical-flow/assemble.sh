#!/usr/bin/env bash
# Builds the NVIDIA Optical Flow SDK tree that the nvidia-optical-flow
# PKGBUILD packages (prepare()), from the user's own download. Nothing is
# downloaded, nothing from the download is executed, and the source is never
# modified.
#
#   assemble.sh --scan --src PATH --version 5.0.7
#   assemble.sh --src PATH --dest DIR --work DIR --version 5.0.7 \
#       [--sha256 HEX] [--state FILE]
#
# PATH is one of:
#   - the SDK zip as NVIDIA's download page serves it
#     (optical_flow_sdk_<x.y.z>.zip; any name ending in .zip is read);
#   - a directory holding exactly one optical_flow_sdk_*.zip (more than one
#     is an error: which one is meant is not guessed);
#   - an already-extracted SDK tree (a directory without such a zip).
# The layout inside is found by searching, not by fixed paths, because only
# NVIDIA's documented package contents are known: the API headers
# nvOpticalFlowCommon.h and nvOpticalFlowCuda.h (required, side by side; the
# copy in a directory named NvOFInterface wins when there are several), the
# FRUC header and library (optional) under either name family: NvFRUC.h
# with libNvFRUC.so or NvFRUC.so, or NvOFFRUC.h with libNvOFFRUC.so or
# NvOFFRUC.so (a library in a path naming linux or ubuntu wins, then the
# shallowest; a header and a library are a pair whatever their family), the
# CUDA runtime bundled next to that library (libcudart.so*), and the
# NvOFBasicSamples/ and NvOFTracker/ source trees beside the API header
# directory. When the source directory holds a PKGBUILD (it is this recipe
# directory), its src/, pkg/ and tests/ subdirectories and the recipe's own
# files are not part of the tree.
#
# The version comes from the zip's name (optical_flow_sdk_<x.y.z>.zip), else
# from the SDK's top-level directory (Optical_Flow_SDK_<x.y.z>, in any
# letter case), else from the API header's NV_OF_API_MAJOR_VERSION and
# NV_OF_API_MINOR_VERSION; it must equal --version (the major and minor
# parts when only the header gives one). Two sources that disagree are an
# error naming both.
#
# --scan prints, one per line:
#   version <x.y.z>          (or <x.y> when only the header gives it)
#   source <absolute path>   the zip, or the tree's directory
#   layout zip|tree
#   sha256 <hex>|none        the zip's SHA-256; none for a tree
#   features <list>          the components present, in this order:
#                            api fruc tracker-src samples
#   root <path>|.            the SDK's top-level directory in the source
#   api <path>               the API header directory
#   fruc-header <path>|-     the FRUC header
#   fruc-lib <path>|-        the FRUC library
#   cudart <name>...|-       the bundled CUDA runtime files next to it
# (paths relative to the zip's top or the tree's directory). Warnings go to
# stderr, among them one whenever an NvOFFRUC/ directory is present but no
# FRUC header and library pair is found (it names the headers and libraries
# that directory holds). A zip is read with `bsdtar -t` (names only), with
# bsdtar's mtree listing (the member types and link targets) and, for the
# version fallback, `bsdtar -xO` of the API header to a pipe; nothing is
# written.
#
# Refused, in --scan as in the build: a member or file that is a device, a
# fifo or a socket, and a symbolic link whose target is absolute or leads
# out of the zip's top or the tree's directory (for a zip, judged from the
# names before anything is extracted; the assembled DEST is checked again
# with the links resolved).
#
# Without --scan, a zip is first copied into --work (which must not exist
# or be empty), and only that copy is read from then on: it is checked
# against --sha256 (required for a zip: configure.sh --write records it; a
# mismatch stops the build), every member name is checked (an absolute name
# or a .. component is refused), and it is extracted with bsdtar into
# --work/tree; the copy is then removed. Hashing, listing and extracting
# one private copy means a download replaced during the build cannot slip
# past the checksum. A tree takes no checksum (NVIDIA publishes none; --sha256 with a
# tree is an error). DEST, which must not exist or be empty, receives:
#   include/             every *.h of the API header directory
#   fruc/include/        the FRUC header, under the name it has (fruc)
#   fruc/lib/            the FRUC library as shipped, a link under its other
#                        name (with or without the lib prefix, e.g.
#                        NvFRUC.so for libNvFRUC.so), and the bundled
#                        libcudart.so* files              (fruc)
#   tracker/             NvOFTracker/, the source tree   (tracker-src)
#   samples/             NvOFBasicSamples/, the source tree (samples)
#   <top-level files>    the SDK's top-level files (readme, licence, release
#                        notes), as shipped
#   licenses/            every other file named *licen[cs]e*, *eula* or
#                        copying* (e.g. Common/External/FreeImage/
#                        licence-fi.txt), named after its path with / as _
# A symbolic link in DEST whose target is absolute or leaves DEST, and a
# device, fifo or socket in DEST, stop the build. --state FILE records FEATURES=<comma list> and FRUC_LIB=<name> for
# package().
set -euo pipefail

prog=${0##*/}
die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
warn() { printf '%s: WARNING: %s\n' "$prog" "$*" >&2; }
usage() {
    cat >&2 <<EOF
usage: $prog --scan --src PATH --version X.Y.Z
       $prog --src PATH --dest DIR --work DIR --version X.Y.Z [--sha256 HEX] [--state FILE]
EOF
    exit 2
}

scan=0 src='' dest='' work='' version='' sha256_arg='' state=''
while (($#)); do
    case $1 in
        --scan) scan=1 && shift ;;
        --src | --dest | --work | --version | --sha256 | --state)
            (($# >= 2)) || usage
            case $1 in
                --src) src=$2 ;;
                --dest) dest=$2 ;;
                --work) work=$2 ;;
                --version) version=$2 ;;
                --sha256) sha256_arg=$2 ;;
                --state) state=$2 ;;
            esac
            shift 2
            ;;
        *) usage ;;
    esac
done
[[ -n $src && -n $version ]] || usage
if ((scan)); then
    [[ -z $dest$work$state$sha256_arg ]] || usage
else
    [[ -n $dest && -n $work ]] || usage
fi
[[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)*$ ]] || die "invalid --version '$version'"
[[ -z $sha256_arg || $sha256_arg =~ ^[0-9a-fA-F]{64}$ ]] || die "--sha256 must be 64 hexadecimal digits"
sha256_arg=${sha256_arg,,}
command -v bsdtar >/dev/null 2>&1 || die "bsdtar not found (it comes with libarchive)"

[[ $src != *$'\n'* ]] || die "the source path contains a newline, which is not supported: rename it"
[[ -e $src ]] || die "source not found: $src"
src=$(realpath -- "$src")

# The source: a zip, a directory holding one, or a tree.
layout='' zip='' base=''
if [[ -f $src ]]; then
    [[ ${src,,} == *.zip ]] || die "$src is not a .zip file (give the SDK zip, a directory holding it, or an extracted tree)"
    layout=zip zip=$src
elif [[ -d $src ]]; then
    mapfile -d '' -t zips < <(find "$src" -mindepth 1 -maxdepth 1 -type f -iname 'optical_flow_sdk_*.zip' -print0 | sort -z)
    if ((${#zips[@]} > 1)); then
        die "$src holds ${#zips[@]} SDK zips ($(for z in "${zips[@]}"; do printf '%s ' "${z##*/}"; done)): keep one, or give the one you mean as the source"
    elif ((${#zips[@]} == 1)); then
        layout=zip zip=${zips[0]}
    else
        layout=tree base=$src
    fi
else
    die "$src is neither a file nor a directory"
fi

empty_or_new() { # empty_or_new <dir> <option>
    if [[ -e $1 || -L $1 ]]; then
        [[ -d $1 && ! -L $1 && -z $(find "$1" -mindepth 1 -maxdepth 1 -print -quit) ]] ||
            die "$2 $1 exists and is not an empty directory"
    fi
    mkdir -p -- "$1"
}
dir_of() { if [[ $1 == */* ]]; then printf '%s\n' "${1%/*}"; else printf '.\n'; fi; }
# lexically_inside <relative path>: whether it never climbs above where it
# starts (.. beyond the start), read as names only.
lexically_inside() {
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
# check_members <archive> <shown name>: refuses a device, fifo or socket
# member, and a symbolic link whose target is absolute or climbs out of the
# archive's top, from bsdtar's mtree listing (names as it encodes them: a
# space is \040). Nothing is extracted.
check_members() {
    local mt line name rest type target
    mt=$(bsdtar -cf - --format=mtree --options='!all,type,link' "@$1" 2>&1) ||
        die "cannot read $2 as an archive: $mt"
    while IFS= read -r line; do
        [[ -n $line && $line != '#'* && $line != /* ]] || continue
        name=${line%% *} rest=" ${line#* } "
        name=${name#./}
        [[ $rest == *' type='* ]] || die "$2: no type for member $name in bsdtar's listing; refusing the archive"
        type=${rest#* type=} type=${type%% *}
        case $type in
            file | dir) ;;
            link)
                target=${rest#* link=} target=${target%% *}
                [[ $target != /* ]] ||
                    die "$2: member $name is a symbolic link to an absolute path ($target); refusing the archive"
                lexically_inside "$(dir_of "$name")/$target" ||
                    die "$2: member $name is a symbolic link leading out of the archive ($target); refusing the archive"
                ;;
            *) die "$2: member $name is a special file ($type: a device, fifo or socket); refusing the archive" ;;
        esac
    done <<<"$mt"
}
# check_links <top> <shown prefix> <link>...: dies when a link's target is
# absolute or, resolved, lies outside <top> (an absolute, resolved path).
# The absolute links first, so that a link to one (a chain) is not the one
# named.
check_links() {
    local top=$1 shown=$2 link target
    shift 2
    for link in "$@"; do
        target=$(readlink -- "$link")
        [[ $target != /* ]] ||
            die "$shown${link#"$top"/}: a symbolic link to an absolute path ($target); refusing to package it"
    done
    for link in "$@"; do check_link "$top" "$link" "$shown${link#"$top"/}"; done
}
# check_link <top> <link> <shown>: dies when the link, resolved, lies
# outside <top>.
check_link() {
    local target resolved
    target=$(readlink -- "$2")
    resolved=$(realpath -m -- "$(dirname -- "$2")/$target" 2>/dev/null) ||
        die "$3: a symbolic link that cannot be resolved ($target); refusing to package it"
    [[ $resolved == "$1" || $resolved == "$1"/* ]] ||
        die "$3: a symbolic link leaving the SDK tree ($target); refusing to package it"
}

# Without --scan, a zip is copied once into --work, and only the copy is
# read: hashed, listed and extracted.
zip_read=$zip
if [[ $layout == zip ]] && ((!scan)); then
    empty_or_new "$work" --work
    work=$(realpath -- "$work")
    mkdir -- "$work/archive" "$work/tree"
    zip_read=$work/archive/${zip##*/}
    cp --reflink=auto -- "$zip" "$zip_read" || die "copying $zip into $work failed"
fi

# entries: the paths of the files in the source, relative to its top.
entries=()
recipe=0
if [[ $layout == zip ]]; then
    listing=$(bsdtar -tf "$zip_read" 2>&1) || die "cannot read $zip as a zip archive: $listing"
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        [[ $name != *[[:cntrl:]]* ]] || die "$zip: a member name holds a control character; refusing the archive"
        case /$name/ in
            //*) die "$zip: absolute member name '$name'; refusing the archive" ;;
            */../*) die "$zip: member name '$name' has a .. component; refusing the archive" ;;
        esac
        name=${name#./}
        [[ $name == */ ]] && continue
        entries+=("$name")
    done <<<"$listing"
    check_members "$zip_read" "$zip"
else
    prune=()
    if [[ -f $base/PKGBUILD ]]; then
        recipe=1
        prune=(\( -path "$base/src" -o -path "$base/pkg" -o -path "$base/tests" \) -prune -o)
    fi
    while IFS= read -r -d '' name; do
        [[ $name != *[[:cntrl:]]* ]] || die "$base: a file name holds a control character ($(printf %q "$name")); rename it"
        entries+=("$name")
    done < <(find "$base" -mindepth 1 "${prune[@]}" \( -type f -o -type l \) -printf '%P\0' | sort -z)
    special=$(find "$base" -mindepth 1 "${prune[@]}" \( ! -type f ! -type d ! -type l \) -printf '%P\n' -quit)
    [[ -z $special ]] || die "$base: $special is a special file (a device, fifo or socket); refusing the tree"
    links=()
    for name in "${entries[@]}"; do
        [[ ! -L $base/$name ]] || links+=("$base/$name")
    done
    check_links "$base" "$base: " "${links[@]}"
fi
declare -A have=()
for name in "${entries[@]}"; do have[$name]=1; done

depth_of() { local s=${1//[!\/]/}; printf '%s\n' "${#s}"; }
join() { local IFS=$1; shift; printf '%s\n' "$*"; }

# The API header directory.
api_dirs=() named=()
for name in "${entries[@]}"; do
    [[ ${name##*/} == nvOpticalFlowCommon.h ]] || continue
    d=$(dir_of "$name")
    if [[ $d == . ]]; then other=nvOpticalFlowCuda.h; else other=$d/nvOpticalFlowCuda.h; fi
    [[ -n ${have[$other]:-} ]] || continue
    api_dirs+=("$d")
    [[ ${d##*/} == NvOFInterface ]] && named+=("$d")
done
where=$src
[[ $layout == zip ]] && where=$zip
if ((${#api_dirs[@]} == 0)); then
    die "no Optical Flow API headers in $where: nvOpticalFlowCommon.h and nvOpticalFlowCuda.h were not found side by side (is this the Optical Flow SDK?)"
fi
if ((${#named[@]} == 1)); then
    api=${named[0]}
elif ((${#api_dirs[@]} == 1)); then
    api=${api_dirs[0]}
else
    die "several API header directories in $where ($(join ' ' "${api_dirs[@]}")): which one is the SDK's is not guessed; give its tree as the source"
fi

# The SDK's top-level directory: the API header directory's parent when it
# is NvOFInterface (NVIDIA's layout), else the single top-level directory.
if [[ ${api##*/} == NvOFInterface ]]; then
    root=$(dir_of "$api")
else
    root=.
    declare -A tops=()
    for name in "${entries[@]}"; do
        [[ $name == */* ]] || { tops=([.]=1) && break; }
        tops[${name%%/*}]=1
    done
    if ((${#tops[@]} == 1)) && [[ -z ${tops[.]:-} ]]; then
        root=${!tops[*]}
    fi
fi
if [[ $root == . ]]; then p=''; else p=$root/; fi

# The version.
want_mm=$(cut -d. -f1-2 <<<"$version")
name_ver='' dir_ver='' hdr_ver=''
ver_re='^optical_flow_sdk_([0-9]+(\.[0-9]+)+)'
if [[ $layout == zip ]]; then
    zname=${zip##*/}
    [[ ${zname,,} =~ $ver_re ]] && name_ver=${BASH_REMATCH[1]}
fi
if [[ $root != . ]]; then
    rname=${root##*/}
elif [[ $layout == tree ]]; then
    rname=${base##*/}
else
    rname=''
fi
[[ ${rname,,} =~ ${ver_re}$ ]] && dir_ver=${BASH_REMATCH[1]}
if [[ $api == . ]]; then hdr=nvOpticalFlowCommon.h; else hdr=$api/nvOpticalFlowCommon.h; fi
if [[ $layout == zip ]]; then
    hdr_text=$(bsdtar -xOf "$zip_read" "$hdr" 2>/dev/null | head -c 1048576 || true)
else
    hdr_text=$(head -c 1048576 -- "$base/$hdr" || true)
fi
hdr_major=$(sed -n 's/^[[:space:]]*#[[:space:]]*define[[:space:]]\{1,\}NV_OF_API_MAJOR_VERSION[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' <<<"$hdr_text" | head -n 1)
hdr_minor=$(sed -n 's/^[[:space:]]*#[[:space:]]*define[[:space:]]\{1,\}NV_OF_API_MINOR_VERSION[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' <<<"$hdr_text" | head -n 1)
[[ -n $hdr_major && -n $hdr_minor ]] && hdr_ver=$hdr_major.$hdr_minor
if [[ -n $name_ver && -n $dir_ver && $name_ver != "$dir_ver" ]]; then
    die "the zip's name says version $name_ver but its top-level directory $rname says $dir_ver"
fi
sdk_ver=${name_ver:-$dir_ver}
if [[ -n $sdk_ver ]]; then
    if [[ -n $hdr_ver && $(cut -d. -f1-2 <<<"$sdk_ver") != "$hdr_ver" ]]; then
        die "$where is named version $sdk_ver but its API header ($hdr) says $hdr_ver"
    fi
    [[ $sdk_ver == "$version" ]] ||
        die "$where is the Optical Flow SDK $sdk_ver, but this PKGBUILD packages $version (pkgver): download $version, or update the recipe"
elif [[ -n $hdr_ver ]]; then
    [[ $hdr_ver == "$want_mm" ]] ||
        die "$where holds the Optical Flow API $hdr_ver ($hdr), but this PKGBUILD packages $version (pkgver)"
    sdk_ver=$hdr_ver
    warn "the version comes from the API header only ($hdr_ver): the zip or directory name (optical_flow_sdk_$version) would give the full version"
else
    die "cannot tell the SDK version of $where: neither the name (optical_flow_sdk_<x.y.z>) nor the API header ($hdr) gives it"
fi

# The optional components.
features=(api)
pick_shallowest() { # pick_shallowest <path>...: the shallowest; ties: the first (sorted)
    local best='' bd=-1 d x
    for x in "$@"; do
        d=$(depth_of "$x")
        if ((bd < 0 || d < bd)); then best=$x bd=$d; fi
    done
    printf '%s\n' "$best"
}
# FRUC under either name family: NvFRUC* or NvOFFRUC*. fruc_dir: an
# NvOFFRUC/ directory is present; fruc_dir_files: its headers and libraries.
fruc_headers=() fruc_libs=() fruc_dir=0 fruc_dir_files=()
for name in "${entries[@]}"; do
    [[ $name == "$p"* ]] || continue
    case ${name##*/} in
        NvFRUC.h | NvOFFRUC.h) fruc_headers+=("$name") ;;
        libNvFRUC.so | NvFRUC.so | libNvOFFRUC.so | NvOFFRUC.so) fruc_libs+=("$name") ;;
    esac
    if [[ /${name#"$p"} == */NvOFFRUC/* ]]; then
        fruc_dir=1
        case ${name##*/} in *.h | *.so | *.so.*) fruc_dir_files+=("$name") ;; esac
    fi
done
fruc_header='' fruc_lib='' cudart=()
((${#fruc_headers[@]} == 0)) || fruc_header=$(pick_shallowest "${fruc_headers[@]}")
if ((${#fruc_libs[@]} > 0)); then
    linux=()
    for name in "${fruc_libs[@]}"; do
        [[ ${name,,} == *linux* || ${name,,} == *ubuntu* ]] && linux+=("$name")
    done
    ((${#linux[@]} > 0)) || linux=("${fruc_libs[@]}")
    best=$(pick_shallowest "${linux[@]}")
    bd=$(depth_of "$best") bdir=$(dir_of "$best")
    tie=()
    for name in "${linux[@]}"; do
        [[ $(depth_of "$name") == "$bd" && $(dir_of "$name") != "$bdir" ]] && tie+=("$name")
    done
    if ((${#tie[@]} > 0)); then
        warn "several FRUC libraries ($(join ' ' "${linux[@]}")): which one is meant is not guessed; FRUC is not packaged"
    else
        # Both names of one family in one directory (libNvFRUC.so and
        # NvFRUC.so): the lib one is kept as the library, the other is
        # shipped as well.
        stem=${best##*/} stem=${stem#lib}
        if [[ $bdir == . ]]; then cand=lib$stem; else cand=$bdir/lib$stem; fi
        if [[ -n ${have[$cand]:-} ]]; then fruc_lib=$cand; else fruc_lib=$best; fi
    fi
fi
if [[ -n $fruc_header && -n $fruc_lib ]]; then
    features+=(fruc)
    fdir=$(dir_of "$fruc_lib")
    for name in "${entries[@]}"; do
        [[ $(dir_of "$name") == "$fdir" && ${name##*/} == libcudart.so* ]] && cudart+=("${name##*/}")
    done
elif [[ -n $fruc_header ]]; then
    warn "the FRUC header $fruc_header is present but no FRUC library (libNvFRUC.so, NvFRUC.so, libNvOFFRUC.so or NvOFFRUC.so) is: FRUC is not packaged"
    fruc_header=''
elif [[ -n $fruc_lib ]]; then
    warn "the FRUC library $fruc_lib is present but no FRUC header (NvFRUC.h or NvOFFRUC.h) is: FRUC is not packaged"
    fruc_lib=''
fi
if [[ -z $fruc_lib ]] && ((fruc_dir)); then
    if ((${#fruc_dir_files[@]} == 0)); then
        found=none
    elif ((${#fruc_dir_files[@]} > 12)); then
        found="$(join ' ' "${fruc_dir_files[@]:0:12}") and $((${#fruc_dir_files[@]} - 12)) more"
    else
        found=$(join ' ' "${fruc_dir_files[@]}")
    fi
    warn "an NvOFFRUC/ directory is present, but no FRUC header (NvFRUC.h or NvOFFRUC.h) and library (libNvFRUC.so, NvFRUC.so, libNvOFFRUC.so or NvOFFRUC.so) pair was found; the headers and libraries under it: $found. FRUC is not packaged: if NVIDIA renamed them, the recipe needs updating"
fi
has_dir() { # has_dir <dir>: some entry lies under it
    local name
    for name in "${entries[@]}"; do [[ $name == "$1"/* ]] && return 0; done
    return 1
}
has_dir "${p}NvOFTracker" && features+=(tracker-src)
has_dir "${p}NvOFBasicSamples" && features+=(samples)

# The checksum.
sha256=none
if [[ $layout == zip ]]; then
    sha256=$(sha256sum -- "$zip_read" | cut -d' ' -f1)
elif [[ -n $sha256_arg ]]; then
    die "a checksum was given (SHA256) but the source $src is an extracted tree, which has none; unset NVIDIA_OF_SHA256, or point NVIDIA_OF_SRC at the zip it was recorded for"
fi

if ((scan)); then
    printf 'version %s\n' "$sdk_ver"
    if [[ $layout == zip ]]; then printf 'source %s\n' "$zip"; else printf 'source %s\n' "$src"; fi
    printf 'layout %s\n' "$layout"
    printf 'sha256 %s\n' "$sha256"
    printf 'features %s\n' "${features[*]}"
    printf 'root %s\n' "$root"
    printf 'api %s\n' "$api"
    printf 'fruc-header %s\n' "${fruc_header:--}"
    printf 'fruc-lib %s\n' "${fruc_lib:--}"
    if ((${#cudart[@]} > 0)); then printf 'cudart %s\n' "${cudart[*]}"; else printf 'cudart -\n'; fi
    exit 0
fi

if [[ $layout == zip ]]; then
    if [[ -z $sha256_arg ]]; then
        die "no checksum is recorded for $zip: NVIDIA publishes none, so it is recorded when you select the zip. Run: configure.sh --src $(printf %q "$zip") --write (or set NVIDIA_OF_SHA256 to its SHA-256)"
    fi
    if [[ $sha256 != "$sha256_arg" ]]; then
        die "checksum mismatch for $zip: SHA-256 $sha256, but $sha256_arg was recorded. The file changed since it was selected (an interrupted or different download): download it again, or, if you replaced it on purpose, record the new one with configure.sh --src $(printf %q "$zip") --write"
    fi
    echo "checksum  SHA-256 of ${zip##*/} verified ($sha256)"
    bsdtar -xf "$zip_read" -C "$work/tree" || die "extracting $zip failed"
    rm -f -- "$zip_read"
    base=$work/tree
else
    echo "checksum  none: the source is an extracted tree (NVIDIA publishes no checksum)"
fi
empty_or_new "$dest" --dest
dest=$(realpath -- "$dest")
from=$base/${p}
[[ $root != . ]] || from=$base

# include/: the API headers.
install -d -- "$dest/include"
while IFS= read -r -d '' f; do
    cp -a --reflink=auto -- "$f" "$dest/include/"
done < <(find "$base/$api" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -iname '*.h' -print0 | sort -z)

fruc_name=''
if [[ -n $fruc_lib ]]; then
    install -d -- "$dest/fruc/include" "$dest/fruc/lib"
    cp -a --reflink=auto -- "$base/$fruc_header" "$dest/fruc/include/${fruc_header##*/}"
    fdir=$base/$(dir_of "$fruc_lib")
    while IFS= read -r -d '' f; do
        cp -a --reflink=auto -- "$f" "$dest/fruc/lib/"
    done < <(find "$fdir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) \
        \( -name 'libNvFRUC.so*' -o -name 'NvFRUC.so*' -o -name 'libNvOFFRUC.so*' -o -name 'NvOFFRUC.so*' \
        -o -name 'libcudart.so*' \) -print0 | sort -z)
    fruc_name=${fruc_lib##*/}
    if [[ $fruc_name == lib* ]]; then otherlib=${fruc_name#lib}; else otherlib=lib$fruc_name; fi
    [[ -e $dest/fruc/lib/$otherlib || -L $dest/fruc/lib/$otherlib ]] ||
        ln -s -- "$fruc_name" "$dest/fruc/lib/$otherlib"
fi
in_features() { [[ " ${features[*]} " == *" $1 "* ]]; }
if in_features tracker-src; then
    cp -a --reflink=auto -- "$from/NvOFTracker" "$dest/tracker"
fi
if in_features samples; then
    cp -a --reflink=auto -- "$from/NvOFBasicSamples" "$dest/samples"
fi

# The SDK's top-level files, and the licence files below it.
for name in "${entries[@]}"; do
    [[ $name == "$p"* ]] || continue
    rel=${name#"$p"}
    if [[ $rel != */* ]]; then
        if ((recipe)); then
            case $rel in
                PKGBUILD | *.sh | selection.conf | .selection.conf.* | README.md | *.pkg.tar*) continue ;;
            esac
        fi
        [[ ${rel,,} != *.zip ]] || continue
        cp -a --reflink=auto -- "$base/$name" "$dest/$rel"
        continue
    fi
    case ${rel##*/} in
        [Ll][Ii][Cc][Ee][Nn][CcSs][Ee]* | *[Ll][Ii][Cc][Ee][Nn][CcSs][Ee]* | *[Ee][Uu][Ll][Aa]* | [Cc][Oo][Pp][Yy][Ii][Nn][Gg]*)
            install -d -- "$dest/licenses"
            cp -a --reflink=auto -- "$base/$name" "$dest/licenses/${rel//\//_}"
            ;;
    esac
done

# No link may point outside the tree, and no device, fifo or socket.
special=$(find "$dest" -mindepth 1 \( ! -type f ! -type d ! -type l \) -printf '%P\n' -quit)
[[ -z $special ]] || die "$special: a special file (a device, fifo or socket); refusing to package it"
mapfile -d '' -t links < <(find "$dest" -type l -print0 | sort -z)
check_links "$dest" '' "${links[@]}"
chmod -R u+rwX,go+rX,go-w -- "$dest"

if [[ -n $state ]]; then
    {
        echo "FEATURES=$(join , "${features[@]}")"
        echo "FRUC_LIB=$fruc_name"
    } >"$state"
fi

echo "Optical Flow SDK $sdk_ver assembled from $where ($layout)"
echo "  API headers   $api -> include/"
if [[ -n $fruc_lib ]]; then
    echo "  FRUC          $fruc_header, $fruc_lib -> fruc/"
    ((${#cudart[@]} == 0)) || echo "                bundled CUDA runtime: ${cudart[*]} (private to fruc/lib)"
else
    echo "  FRUC          not present"
fi
if in_features tracker-src; then echo "  tracker       NvOFTracker/ -> tracker/ (source only, not built)"; fi
if in_features samples; then echo "  samples       NvOFBasicSamples/ -> samples/ (source only, not built)"; fi
echo "  features      $(join , "${features[@]}")"
