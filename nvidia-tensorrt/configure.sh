#!/usr/bin/env bash
# Checks a TensorRT download and saves the source the PKGBUILD builds from,
# in nvidia-tensorrt/selection.conf (git-ignored: it holds a local path).
#
#   configure.sh [--src PATH]           check the source and report it
#   configure.sh [--src PATH] --write   check it and save it in selection.conf
#   configure.sh --show                 print the current selection.conf
#
# PATH is the archive NVIDIA publishes, a directory holding exactly one
# TensorRT-*.tar.* archive, or an extracted tree (see source.sh). It
# defaults to $NVIDIA_TRT_SRC, else the NVIDIA_TRT_SRC of the current
# selection.conf, else ~/Downloads; the output says which.
#
# The check is offline and read-only: the archive is listed and its version
# header read with bsdtar, nothing is extracted or written next to it. It
# verifies that the version (read from include/NvInferVersion.h) is this
# recipe's pkgver, that the headers and libraries a consumer needs are
# present, and, for an archive, that its SHA-256 is the one pinned in the
# PKGBUILD (_trt_archive, _trt_sha256). When _trt_sha256 is empty (NVIDIA
# publishes no checksum for the release), the archive must carry the name
# _trt_archive and its SHA-256 is only reported, for you to compare with
# your download. An extracted tree has no checksum to verify. The ARM
# (aarch64) build is refused, by its file name or its contents. A device,
# fifo or socket, or a symbolic link whose target is absolute or leads out
# of the tree, is refused (in an archive, judged from bsdtar's listing; the
# build checks the extracted tree again). This script uses no network and
# never runs sudo.
#
# A valid source prints these machine-readable lines first, one per line,
# then a report for people:
#   version <major.minor.patch.build>
#   source <absolute path of the archive or of the tree's root>
#   layout archive|tree
#   sha256 <64 hex digits>|none
#   features <space-separated: headers libs, then trtexec python samples when present>
# and exits 0; otherwise it prints the reason on stderr and exits 1 (2 for
# a usage error).
#
# --write replaces selection.conf atomically (a temporary file, then mv)
# with NVIDIA_TRT_SRC=<source> and, for an archive, NVIDIA_TRT_SHA256. See
# selection.sh for the file's format and the PKGBUILD for the precedence
# (environment variable > selection.conf > default).
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

prog=${0##*/}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=selection.sh
. "$here/selection.sh"
# shellcheck source=source.sh
. "$here/source.sh"
conf=$here/selection.conf

die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
usage() {
    printf 'usage: %s [--src PATH] [--write]\n       %s --show\n' "$prog" "$prog" >&2
    exit 2
}

src_arg='' write=0 show=0
while (($#)); do
    case $1 in
        --src)
            (($# >= 2)) || usage
            src_arg=$2
            shift 2
            ;;
        --write) write=1 && shift ;;
        --show) show=1 && shift ;;
        *) usage ;;
    esac
done
if ((show)) && { ((write)) || [[ -n $src_arg ]]; }; then
    usage
fi
q() { printf '%q' "$1"; } # a path as a shell word, for the printed commands

# What this directory's PKGBUILD packages (its lines, read, not sourced).
pkgbuild_value() { sed -n "s/^$1=\\([A-Za-z0-9._+-]*\\)\$/\\1/p" "$here/PKGBUILD"; }
version=$(pkgbuild_value pkgver)
pinned_archive=$(pkgbuild_value _trt_archive)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no pkgver= line in $here/PKGBUILD"
[[ -n $pinned_archive ]] || die "no _trt_archive= line in $here/PKGBUILD"
# _trt_sha256: 64 hex digits, or empty while NVIDIA publishes no checksum.
grep -q '^_trt_sha256=' "$here/PKGBUILD" || die "no _trt_sha256= line in $here/PKGBUILD"
pinned_sha256=$(sed -n 's/^_trt_sha256=//p' "$here/PKGBUILD" | head -n 1)
[[ -z $pinned_sha256 || $pinned_sha256 =~ ^[0-9a-f]{64}$ ]] ||
    die "_trt_sha256= in $here/PKGBUILD must be 64 lowercase hexadecimal digits, or empty when no checksum is published"
url=$(sed -n "s/^url='\\(.*\\)'\$/\\1/p" "$here/PKGBUILD")
# What source.sh's ARM refusal names.
trt_expected_archive=$pinned_archive trt_expected_version=$version trt_download_url=$url

show_selection() {
    if ! nvidia_trt_read_selection "$conf"; then
        echo "  $conf is not valid (see above); fix it or write it again with --write"
        return 1
    fi
    if [[ ! -e $conf ]]; then
        echo "  no selection.conf ($conf): the build uses NVIDIA_TRT_SRC, else ~/Downloads/<the pinned archive> if it exists, else downloads it"
    else
        echo "  $conf:"
        echo "  NVIDIA_TRT_SRC=${nvidia_trt_file_src:-(not set: ~/Downloads/<the pinned archive> if it exists, else a download)}"
        [[ -z $nvidia_trt_file_sha256 ]] || echo "  NVIDIA_TRT_SHA256=$nvidia_trt_file_sha256"
    fi
    [[ -z ${NVIDIA_TRT_SRC:-} ]] ||
        echo "  note: NVIDIA_TRT_SRC is set in this environment ($NVIDIA_TRT_SRC); it overrides the file when you build here"
}

if ((show)); then
    echo "Current selection:"
    show_selection
    exit
fi

# The source: --src, else the environment, else selection.conf, else
# ~/Downloads (to look at; the build itself uses the exact archive file there, else downloads).
if [[ -n $src_arg ]]; then
    src=$src_arg src_from=--src
elif [[ -n ${NVIDIA_TRT_SRC:-} ]]; then
    src=$NVIDIA_TRT_SRC src_from="the environment (NVIDIA_TRT_SRC)"
else
    nvidia_trt_read_selection "$conf" || die "$conf is not valid (see above); give --src, or fix it"
    if [[ -n $nvidia_trt_file_src ]]; then
        src=$nvidia_trt_file_src src_from=$conf
    else
        src=$HOME/Downloads src_from="the default (~/Downloads; the build looks for the pinned archive there, else downloads it)"
    fi
fi
trt_locate "$src" || die "cannot use $src (from $src_from; see README.md)"

# An archive: its SHA-256 first, so that a damaged download of the pinned
# archive is reported as such. Another archive is read for its version, to
# say which TensorRT it is.
sha256=none checksum_note="an extracted tree: no checksum to verify (an archive is verified against the pinned SHA-256)"
other_archive=''
if [[ $trt_layout == archive ]]; then
    sha256=$(trt_sha256 "$trt_path") || die "cannot read $trt_path"
    name=${trt_path##*/}
    if [[ -z $pinned_sha256 ]]; then
        if [[ $name == "$pinned_archive" ]]; then
            checksum_note="SHA-256 $sha256 (not pinned: NVIDIA publishes no checksum for this release; compare it with your download)"
        else
            other_archive="$trt_path is not the archive this recipe packages: expected $pinned_archive, got $name (SHA-256 $sha256)"
        fi
    elif [[ $sha256 == "$pinned_sha256" ]]; then
        checksum_note="SHA-256 matches the pinned $pinned_archive"
        [[ $name == "$pinned_archive" ]] || checksum_note+=" (the file is named $name)"
    elif ! trt_refuse_arm_archive "$trt_path"; then
        die "cannot use $trt_path (from $src_from; see README.md)"
    elif [[ $name == "$pinned_archive" ]]; then
        die "$trt_path: SHA-256 mismatch: expected $pinned_sha256, got $sha256." \
            "The file is incomplete or damaged: download it again from $url"
    else
        other_archive="$trt_path is not the archive this recipe packages: expected $pinned_archive (SHA-256 $pinned_sha256), got $name (SHA-256 $sha256)"
    fi
fi
trt_scan "$trt_layout" "$trt_path" || die "${other_archive:-cannot use $trt_path}"
if [[ $trt_layout == archive ]]; then
    trt_check_archive "$trt_path" "$trt_root_entry" || die "cannot use $trt_path (see the message above)"
else
    trt_check_tree "$trt_path" || die "cannot use $trt_path (see the message above)"
fi

if [[ -z $trt_version ]]; then
    die "$trt_path: include/NvInferVersion.h defines no NV_TENSORRT_MAJOR, _MINOR, _PATCH and _BUILD"
fi
if [[ $trt_version != "$version" ]]; then
    die "$trt_path holds TensorRT $trt_version, but this recipe packages TensorRT $version (pkgver):" \
        "download $pinned_archive from $url"
fi
[[ -z $other_archive ]] || die "$other_archive"
if ((${#trt_missing[@]} > 0)); then
    die "$trt_path is incomplete; missing: ${trt_missing[*]}"
fi

echo "version $trt_version"
echo "source $trt_path"
echo "layout $trt_layout"
echo "sha256 $sha256"
echo "features ${trt_features[*]}"
echo
echo "TensorRT $trt_version in $trt_path"
echo "  from      $src_from"
if [[ $trt_layout == archive ]]; then
    echo "  layout    archive (top directory: ${trt_root_entry:-none, the files are at its top})"
else
    echo "  layout    extracted tree"
fi
for f in "${trt_arm_skipped[@]}"; do
    echo "  skipped   $f (the ARM (aarch64) build)"
done
echo "  checksum  $checksum_note"
echo "  present   ${trt_features[*]}"
absent=()
for f in trtexec python samples; do
    [[ " ${trt_features[*]} " == *" $f "* ]] || absent+=("$f")
done
((${#absent[@]} == 0)) || echo "  absent    ${absent[*]} (optional)"

if ((!write)); then
    echo
    echo "Current selection:"
    show_selection || true
    echo
    echo "Commands:"
    echo "  save this source:  $(q "$0") --src $(q "$trt_path") --write"
    echo "  build:             (cd $(q "$here") && makepkg -f)"
    exit 0
fi

tmpfile=$(mktemp "$here/.selection.conf.XXXXXX")
trap 'rm -f -- "$tmpfile"' EXIT
{
    echo "# The nvidia-tensorrt build source, written by configure.sh. The PKGBUILD"
    echo "# reads it as KEY=value lines (never executed); NVIDIA_TRT_SRC in the"
    echo "# environment overrides it. Change it with configure.sh --write."
    echo "NVIDIA_TRT_SRC=$trt_path"
    [[ $sha256 == none ]] || echo "NVIDIA_TRT_SHA256=$sha256"
} >"$tmpfile"
# What the PKGBUILD will accept: a path with $, a quote or a control
# character cannot be stored.
nvidia_trt_read_selection "$tmpfile" 2>/dev/null ||
    die "the path $trt_path cannot be stored in selection.conf (it holds \$, a backtick, a quote" \
        "or a control character): rename it, or set NVIDIA_TRT_SRC in the environment instead"
chmod 644 -- "$tmpfile"
mv -f -- "$tmpfile" "$conf"
trap - EXIT
echo
echo "Wrote $conf:"
grep -v '^#' "$conf" | sed 's/^/  /'
echo "Next: (cd $(q "$here") && makepkg -f)"
