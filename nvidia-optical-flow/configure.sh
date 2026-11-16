#!/usr/bin/env bash
# Shows what an NVIDIA Optical Flow SDK download holds and saves the source
# the PKGBUILD builds, with the SHA-256 of the zip, in
# nvidia-optical-flow/selection.conf (git-ignored: it holds a local path).
#
#   configure.sh [--src PATH]           what the source holds (read-only)
#   configure.sh [--src PATH] --write   validate it and save the selection
#   configure.sh --show                 print the current selection.conf
#
# PATH is the SDK zip (optical_flow_sdk_<x.y.z>.zip), a directory holding
# exactly one such zip, or an extracted SDK tree. It defaults to
# $NVIDIA_OF_SRC, else the NVIDIA_OF_SRC of the current selection.conf, else
# this directory; the output says which. A path that holds a newline is
# refused. The source is read with `assemble.sh --scan` (the same detection
# and refusals as the build): a zip's member names are listed, nothing is
# extracted or written there. This script uses no network and never runs
# sudo.
#
# Without --write the output begins with these lines, one each, for
# scripts:
#   version <x.y.z>
#   source <absolute path>     the zip, or the tree's directory
#   layout zip|tree
#   sha256 <hex>|none          the zip's SHA-256; none for a tree
#   features <list>            components present: api fruc tracker-src samples
# then a report for people. It exits 0 when the API headers are found, and
# non-zero, with the reason and the download instructions, otherwise (no
# headers, two zips, a version other than the PKGBUILD's pkgver).
#
# --write validates the source the same way and replaces selection.conf
# atomically (a temporary file, then mv) with NVIDIA_OF_SRC (the zip itself
# when a directory holding it was given) and, for a zip, SHA256: NVIDIA
# publishes no checksum, so the one of your download is recorded and the
# build verifies the zip against it. See selection.sh for the file's format.
#
# --conf FILE reads and writes FILE instead of the selection.conf next to
# this script. The build reads selection.conf next to the PKGBUILD it runs:
# from an AUR clone, where this script is under src/, give
# --conf <the clone>/selection.conf. That directory is also where the
# printed `makepkg` commands run.
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
usage() {
    cat >&2 <<EOF
usage: $prog [--src PATH] [--conf FILE] [--write]
       $prog [--conf FILE] --show
EOF
    exit 2
}

src_arg='' conf_arg='' write=0 show=0
while (($#)); do
    case $1 in
        --src)
            (($# >= 2)) || usage
            src_arg=$2
            shift 2
            ;;
        --conf)
            (($# >= 2)) || usage
            conf_arg=$2
            shift 2
            ;;
        --write) write=1 && shift ;;
        --show) show=1 && shift ;;
        *) usage ;;
    esac
done
if ((show)); then
    ((!write)) && [[ -z $src_arg ]] || usage
fi

# The SDK version this directory's PKGBUILD packages (its pkgver line; read,
# not sourced).
version=$(sed -n 's/^pkgver=\([0-9][0-9.]*\)$/\1/p' "$here/PKGBUILD")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no pkgver= line in $here/PKGBUILD"

q() { printf '%q' "$1"; } # a path as a shell word, for the printed commands

# The selection.conf read and written: --conf, else the one next to this
# script; builddir is the directory it is in (the PKGBUILD's, for the build).
if [[ -n $conf_arg ]]; then
    [[ $conf_arg != *$'\n'* && $conf_arg != */ && -d $(dirname -- "$conf_arg") ]] ||
        die "--conf $(q "$conf_arg"): not a file name in an existing directory"
    [[ ! -d $conf_arg && ${conf_arg##*/} != . && ${conf_arg##*/} != .. ]] ||
        die "--conf $(q "$conf_arg"): is a directory, not a file name"
    conf=$(cd -- "$(dirname -- "$conf_arg")" && pwd)/${conf_arg##*/}
fi
builddir=${conf%/*}
conf_opt='' # repeated in the printed commands when not the default
[[ $conf == "$here/selection.conf" ]] || conf_opt=" --conf $(q "$conf")"

instructions() {
    cat >&2 <<EOF
To get the SDK: sign in to the NVIDIA Developer Program at
  https://developer.nvidia.com/opticalflow/download
accept the licence and download optical_flow_sdk_${version}.zip yourself (it may
not be redistributed). Then select it:
  $(q "$here/$prog") --src ~/Downloads/optical_flow_sdk_${version}.zip --write$conf_opt
EOF
}

# show_selection: the current selection.conf, or the default.
show_selection() {
    if ! nvidia_of_read_selection "$conf"; then
        echo "   $conf is not valid (see above); fix it or write it again with --write$conf_opt"
        return 1
    fi
    if [[ ! -e $conf ]]; then
        echo "   no selection.conf ($conf): the build uses the environment or the default"
        echo "   (NVIDIA_OF_SRC=$builddir, no checksum)"
    else
        echo "   $conf:"
        echo "   NVIDIA_OF_SRC=${nvidia_of_file_src:-(not set: $builddir)}"
        echo "   SHA256=${nvidia_of_file_sha256:-(not set: none)}"
    fi
    local key
    for key in NVIDIA_OF_SRC NVIDIA_OF_SHA256; do
        [[ -z ${!key:-} ]] ||
            echo "   note: $key is set in this environment ($key=${!key}); it overrides the file when you build here"
    done
}

if ((show)); then
    echo "Current selection:"
    show_selection
    exit
fi

# The source: --src, else the environment, else selection.conf, else here.
if [[ -n $src_arg ]]; then
    src=$src_arg src_from=--src
elif [[ -n ${NVIDIA_OF_SRC:-} ]]; then
    src=$NVIDIA_OF_SRC src_from="the environment (NVIDIA_OF_SRC)"
else
    nvidia_of_read_selection "$conf" ||
        die "$conf is not valid (see above); give --src, or fix it"
    if [[ -n $nvidia_of_file_src ]]; then
        src=$nvidia_of_file_src src_from=$conf
    else
        src=$builddir src_from="the default (the directory of $(q "$conf"))"
    fi
fi
[[ $src != *$'\n'* ]] ||
    die "the source path $(q "$src") contains a newline, which is not supported: rename it"
if [[ ! -e $src ]]; then
    printf '%s: source not found: %s (from %s)\n' "$prog" "$src" "$src_from" >&2
    instructions
    exit 1
fi
src=$(realpath -- "$src")
if ! scan_out=$(bash "$here/assemble.sh" --scan --src "$src" --version "$version"); then
    printf '%s: cannot use %s (from %s; see the message above)\n' "$prog" "$src" "$src_from" >&2
    instructions
    exit 1
fi
declare -A scan=()
while IFS= read -r line; do
    key=${line%% *}
    case $key in
        version | source | layout | sha256 | features | root | api | fruc-header | fruc-lib | cudart)
            scan[$key]=${line#* } ;;
        *) die "unexpected line from assemble.sh --scan: $line" ;;
    esac
done <<<"$scan_out"
for key in version source layout sha256 features root api fruc-header fruc-lib cudart; do
    [[ -n ${scan[$key]:-} ]] || die "assemble.sh --scan gave no $key line"
done

if ((write)); then
    tmpfile=$(mktemp "$builddir/.selection.conf.XXXXXX")
    trap 'rm -f -- "$tmpfile"' EXIT
    {
        echo "# The nvidia-optical-flow build selection, written by configure.sh. The"
        echo "# PKGBUILD reads it as KEY=value lines (never executed); NVIDIA_OF_SRC"
        echo "# and NVIDIA_OF_SHA256 in the environment override it. SHA256 is the"
        echo "# checksum of the zip as selected; the build verifies the zip against it."
        echo "NVIDIA_OF_SRC=${scan[source]}"
        [[ ${scan[sha256]} == none ]] || echo "SHA256=${scan[sha256]}"
    } >"$tmpfile"
    nvidia_of_read_selection "$tmpfile" 2>/dev/null ||
        die "the path ${scan[source]} cannot be stored in selection.conf (it holds \$, a backtick, a quote" \
            "or a control character): rename it, or set NVIDIA_OF_SRC in the environment instead"
    chmod 644 -- "$tmpfile"
    mv -fT -- "$tmpfile" "$conf"
    trap - EXIT
    echo "Wrote $conf:"
    grep -v '^#' "$conf" | sed 's/^/  /'
    [[ ${scan[sha256]} != none ]] ||
        echo "  (an extracted tree has no checksum: it is packaged as it is)"
    echo "  features: ${scan[features]}"
    echo "Next: (cd $(q "$builddir") && makepkg -f)"
    exit 0
fi

# The machine-readable lines, then the report.
for key in version source layout sha256 features; do
    printf '%s %s\n' "$key" "${scan[$key]}"
done
echo
echo "NVIDIA Optical Flow SDK ${scan[version]} in ${scan[source]}"
echo "  from          $src_from"
if [[ ${scan[layout]} == zip ]]; then
    echo "  layout        zip (extracted into makepkg's src/ at build time, never here)"
    echo "  SHA-256       ${scan[sha256]} (of this file; --write records it)"
else
    echo "  layout        extracted tree"
    echo "  SHA-256       none: an extracted tree has no checksum"
fi
echo "  API headers   ${scan[api]}/ (nvOpticalFlowCommon.h, nvOpticalFlowCuda.h)"
if [[ ${scan[fruc-lib]} != - ]]; then
    echo "  FRUC          ${scan[fruc-header]}, ${scan[fruc-lib]}"
    [[ ${scan[cudart]} == - ]] || echo "                bundled CUDA runtime: ${scan[cudart]}"
else
    echo "  FRUC          not present"
fi
in_features() { [[ " ${scan[features]} " == *" $1 "* ]]; }
if in_features tracker-src; then echo "  tracker       NvOFTracker/ (source only: packaged as documentation, not built)"; else echo "  tracker       not present"; fi
if in_features samples; then echo "  samples       NvOFBasicSamples/ (source only: packaged as documentation, not built)"; else echo "  samples       not present"; fi
echo
echo "Current selection:"
show_selection || true
echo
echo "Commands:"
echo "  save this source (and the zip's checksum):"
echo "    $(q "$here/$prog") --src $(q "${scan[source]}") --write$conf_opt"
echo "  build:"
echo "    (cd $(q "$builddir") && makepkg -f)"
