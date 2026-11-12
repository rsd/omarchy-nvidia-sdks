#!/usr/bin/env bash
# Tests for nvidia-optical-flow/configure.sh, selection.sh and the scan of
# assemble.sh. The fixtures are FAKE: tiny text files with the SDK's
# documented names, zipped with bsdtar, all under mktemp. The scripts run
# from a copy of nvidia-optical-flow/ under mktemp, so selection.conf is
# never written into the working tree. sudo, curl and wget are stubs first on
# PATH that record any call; none may happen.
# Usage: nvidia-optical-flow/tests/configure-test.sh. Exits non-zero on any
# failure, 77 when bsdtar or sha256sum is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
recipe=$(cd "$here/.." && pwd)

for tool in bsdtar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "skipped: $tool not found"; exit 77; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { # check <description> <command...>
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}
says() { grep -qF -- "$1" <<<"$out"; } # says <fragment>: the last output has it
not() { ! "$@"; }

fake() { # fake <file>...: tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}
# sdk_tree <dir> [fruc-lib-name|none]: a fake SDK top-level directory as
# NVIDIA documents it.
sdk_tree() {
    local d=$1 lib=${2:-libNvFRUC.so}
    fake "$d/NvOFInterface/nvOpticalFlowCommon.h" "$d/NvOFInterface/nvOpticalFlowCuda.h" \
        "$d/NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp" "$d/NvOFTracker/inc/NvOFTracker.h" \
        "$d/Common/External/FreeImage/licence-fi.txt" "$d/Read_Me.pdf" "$d/LicenseAgreement.pdf"
    if [[ $lib != none ]]; then
        fake "$d/NvOFFRUC/Interface/NvFRUC.h" "$d/NvOFFRUC/NvOFFRUCSample/bin/ubuntu/$lib" \
            "$d/NvOFFRUC/NvOFFRUCSample/bin/ubuntu/libcudart.so.11.6.55"
    fi
}
# make_zip <zip> <stage dir>: the stage's content, zipped.
make_zip() { (cd "$2" && bsdtar -a -cf "$1" -- *); }
sha() { sha256sum -- "$1" | cut -d' ' -f1; }

# The scripts, copied: selection.conf goes next to them.
of=$tmp/nvidia-optical-flow
mkdir -p "$of"
cp "$recipe/configure.sh" "$recipe/selection.sh" "$recipe/assemble.sh" "$recipe/PKGBUILD" "$of/"
cfg=$of/configure.sh
conf=$of/selection.conf
real_conf_before=$(if [[ -e $recipe/selection.conf ]]; then sha256sum <"$recipe/selection.conf"; else echo absent; fi)

stubs=$tmp/stubs calls=$tmp/calls
mkdir -p "$stubs"
: >"$calls"
for tool in sudo curl wget; do
    printf '#!/bin/sh\necho "%s $*" >>%q\nexit 99\n' "$tool" "$calls" >"$stubs/$tool"
done
chmod +x "$stubs"/*

out='' status=0
run_env() { # run_env [VAR=value...] -- <args...>
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    out=$(env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 PATH="$stubs:$PATH" HOME="$tmp/home" \
        "${vars[@]}" "$cfg" "$@" 2>&1) || status=$?
}
run() { run_env -- "$@"; }
passes() { ((status == 0)) || { echo "$out"; return 1; }; }
fails_with() { # fails_with <fragment>
    ((status != 0)) || { echo "unexpectedly succeeded: $out"; return 1; }
    says "$1" || { echo "$out"; return 1; }
}
head5() { # head5 <expected>: the first five lines of the last output
    local got
    got=$(head -n 5 <<<"$out")
    [[ $got == "$1" ]] || { echo "got:"$'\n'"$got"$'\n'"want:"$'\n'"$1"; return 1; }
}

# Fixtures.
fx=$tmp/fx
sdk_tree "$fx/stage/Optical_Flow_SDK_5.0.7"
mkdir -p "$fx/dl" "$fx/two"
zip=$fx/dl/optical_flow_sdk_5.0.7.zip
make_zip "$zip" "$fx/stage"
zsum=$(sha "$zip")
tree=$fx/stage/Optical_Flow_SDK_5.0.7

echo "== a valid zip"
run --src "$zip"
check "configure.sh accepts the zip" passes
check "the first five lines are the machine-readable summary" head5 "version 5.0.7
source $zip
layout zip
sha256 $zsum
features api fruc tracker-src samples"
check "the report names the bundled CUDA runtime" says "bundled CUDA runtime: libcudart.so.11.6.55"
check "the report names the FRUC library" says "bin/ubuntu/libNvFRUC.so"
check "the read-only run writes no selection.conf" test ! -e "$conf"
check "the zip was not extracted next to it" test "$(find "$fx/dl" -mindepth 1 | wc -l)" = 1

echo "== a valid tree"
run --src "$tree"
check "configure.sh accepts an extracted tree" passes
check "a tree has no checksum" head5 "version 5.0.7
source $tree
layout tree
sha256 none
features api fruc tracker-src samples"
run --src "$fx/stage"
check "the directory above the tree works too" passes
check "it reports the tree layout" says "layout tree"

echo "== a directory holding the zip"
run --src "$fx/dl"
check "configure.sh finds the one zip in a directory" passes
check "the source line names the zip itself" head5 "version 5.0.7
source $zip
layout zip
sha256 $zsum
features api fruc tracker-src samples"
run_env NVIDIA_OF_SRC="$fx/dl" --
check "the source defaults to NVIDIA_OF_SRC" passes
check "and says so" says "from          the environment (NVIDIA_OF_SRC)"

echo "== errors"
cp "$zip" "$fx/two/optical_flow_sdk_5.0.7.zip"
cp "$zip" "$fx/two/optical_flow_sdk_5.0.7 (1).zip"
run --src "$fx/two"
check "two zips in one directory are an error" fails_with "holds 2 SDK zips"
check "the error gives the download instructions" says "https://developer.nvidia.com/opticalflow/download"

sdk_tree "$fx/old/Optical_Flow_SDK_5.0.6"
mkdir -p "$fx/olddl"
make_zip "$fx/olddl/optical_flow_sdk_5.0.6.zip" "$fx/old"
run --src "$fx/olddl/optical_flow_sdk_5.0.6.zip"
check "another version is an error naming both" fails_with "is the Optical Flow SDK 5.0.6, but this PKGBUILD packages 5.0.7"
run --src "$fx/old/Optical_Flow_SDK_5.0.6"
check "another version as a tree is an error too" fails_with "SDK 5.0.6, but this PKGBUILD packages 5.0.7"

mkdir -p "$fx/mixed"
make_zip "$fx/mixed/optical_flow_sdk_5.0.7.zip" "$fx/old"
run --src "$fx/mixed/optical_flow_sdk_5.0.7.zip"
check "a zip name and a top-level directory that disagree are an error" \
    fails_with "the zip's name says version 5.0.7 but its top-level directory Optical_Flow_SDK_5.0.6 says 5.0.6"

fake "$fx/noapi/Optical_Flow_SDK_5.0.7/NvOFBasicSamples/a.cpp" "$fx/noapi/Optical_Flow_SDK_5.0.7/NvOFInterface/nvOpticalFlowCommon.h"
mkdir -p "$fx/noapidl"
make_zip "$fx/noapidl/optical_flow_sdk_5.0.7.zip" "$fx/noapi"
run --src "$fx/noapidl/optical_flow_sdk_5.0.7.zip"
check "a zip without both API headers is an error" fails_with "no Optical Flow API headers"
check "the error gives the download instructions" says "download optical_flow_sdk_5.0.7.zip yourself"
run --src "$fx/noapi"
check "a tree without both API headers is an error" fails_with "no Optical Flow API headers"
run --src "$tmp/nowhere"
check "a missing source is an error with the instructions" fails_with "source not found: $tmp/nowhere"
check "it gives the download page" says "https://developer.nvidia.com/opticalflow/download"
fake "$tmp/notzip.txt"
run --src "$tmp/notzip.txt"
check "a file that is not a zip is an error" fails_with "is not a .zip file"

sdk_tree "$fx/twoapi/sdk/Optical_Flow_SDK_5.0.7"
fake "$fx/twoapi/other/inc/nvOpticalFlowCommon.h" "$fx/twoapi/other/inc/nvOpticalFlowCuda.h"
run --src "$fx/twoapi"
check "a second header copy beside NvOFInterface/ is not ambiguous" passes
fake "$fx/twoapi/sdk2/NvOFInterface/nvOpticalFlowCommon.h" "$fx/twoapi/sdk2/NvOFInterface/nvOpticalFlowCuda.h"
run --src "$fx/twoapi"
check "two NvOFInterface/ directories are an error" fails_with "several API header directories"

echo "== FRUC under either library name, or absent"
sdk_tree "$fx/fruc2/Optical_Flow_SDK_5.0.7" NvFRUC.so
mkdir -p "$fx/fruc2dl"
make_zip "$fx/fruc2dl/optical_flow_sdk_5.0.7.zip" "$fx/fruc2"
run --src "$fx/fruc2dl/optical_flow_sdk_5.0.7.zip"
check "FRUC as NvFRUC.so is found" passes
check "fruc is among the features" grep -qx 'features api fruc tracker-src samples' <<<"$out"
check "the report names NvFRUC.so" says "bin/ubuntu/NvFRUC.so"
sdk_tree "$fx/nofruc/Optical_Flow_SDK_5.0.7" none
run --src "$fx/nofruc"
check "a tree without FRUC is accepted" passes
check "fruc is not among the features" grep -qx 'features api tracker-src samples' <<<"$out"
check "the report says FRUC is not present" says "FRUC          not present"
fake "$fx/nofruc/Optical_Flow_SDK_5.0.7/NvOFFRUC/Interface/NvFRUC.h"
run --src "$fx/nofruc"
check "a FRUC header without its library is accepted" passes
check "with a warning" says "no FRUC library (libNvFRUC.so, NvFRUC.so, libNvOFFRUC.so or NvOFFRUC.so) is: FRUC is not packaged"
check "and without fruc" grep -qx 'features api tracker-src samples' <<<"$out"
sdk_tree "$fx/twofruc/Optical_Flow_SDK_5.0.7"
fake "$fx/twofruc/Optical_Flow_SDK_5.0.7/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvFRUC.so"
run --src "$fx/twofruc"
check "two FRUC libraries at the same depth are not guessed" says "several FRUC libraries"
check "FRUC is then not packaged" grep -qx 'features api tracker-src samples' <<<"$out"

echo "== FRUC under the NvOFFRUC names"
fam=$fx/fam/Optical_Flow_SDK_5.0.7
sdk_tree "$fam" none
fake "$fam/NvOFFRUC/Interface/NvOFFRUC.h" "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvOFFRUC.so" \
    "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/libcudart.so.12"
mkdir -p "$fx/famdl"
make_zip "$fx/famdl/optical_flow_sdk_5.0.7.zip" "$fx/fam"
run --src "$fx/famdl/optical_flow_sdk_5.0.7.zip"
check "NvOFFRUC.h with libNvOFFRUC.so is found" passes
check "fruc is among the features with the NvOFFRUC names" grep -qx 'features api fruc tracker-src samples' <<<"$out"
check "the report names NvOFFRUC.h and libNvOFFRUC.so" \
    says "FRUC          Optical_Flow_SDK_5.0.7/NvOFFRUC/Interface/NvOFFRUC.h, Optical_Flow_SDK_5.0.7/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvOFFRUC.so"
check "there is no NvOFFRUC/ warning when the pair is found" not says "an NvOFFRUC/ directory is present"
rm "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvOFFRUC.so"
fake "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/NvOFFRUC.so"
run --src "$fam"
check "NvOFFRUC.so without the lib prefix is found" grep -qx 'features api fruc tracker-src samples' <<<"$out"
check "the report names NvOFFRUC.so" says "bin/linux/NvOFFRUC.so"
mixed=$fx/mixedfam/Optical_Flow_SDK_5.0.7
sdk_tree "$mixed" none
fake "$mixed/NvOFFRUC/Interface/NvFRUC.h" "$mixed/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvOFFRUC.so"
run --src "$mixed"
check "a header and a library of different families are a pair" grep -qx 'features api fruc tracker-src samples' <<<"$out"
renamed=$fx/renamed/Optical_Flow_SDK_5.0.7
sdk_tree "$renamed" none
fake "$renamed/NvOFFRUC/Interface/NvFRUCv2.h" "$renamed/NvOFFRUC/NvOFFRUCSample/bin/linux/libNvFRUCv2.so" \
    "$renamed/NvOFFRUC/NvOFFRUCSample/README.txt"
run --src "$renamed"
check "an NvOFFRUC/ directory without a known pair is accepted" passes
check "with a warning naming what it holds" \
    says "WARNING: an NvOFFRUC/ directory is present, but no FRUC header (NvFRUC.h or NvOFFRUC.h) and library (libNvFRUC.so, NvFRUC.so, libNvOFFRUC.so or NvOFFRUC.so) pair was found; the headers and libraries under it: NvOFFRUC/Interface/NvFRUCv2.h NvOFFRUC/NvOFFRUCSample/bin/linux/libNvFRUCv2.so."
check "and without fruc" grep -qx 'features api tracker-src samples' <<<"$out"
rm -rf "${renamed:?}/NvOFFRUC/Interface" "${renamed:?}/NvOFFRUC/NvOFFRUCSample/bin"
run --src "$renamed"
check "an NvOFFRUC/ directory without headers or libraries is named as such" says "the headers and libraries under it: none."
fake "$renamed/NvOFFRUC/Interface/NvOFFRUC.h"
run --src "$renamed"
check "a header alone in NvOFFRUC/ gives the NvOFFRUC/ warning too" says "the headers and libraries under it: NvOFFRUC/Interface/NvOFFRUC.h."
sdk_tree "$fx/nofruc2/Optical_Flow_SDK_5.0.7" none
run --src "$fx/nofruc2"
check "without an NvOFFRUC/ directory there is no such warning" not says "an NvOFFRUC/ directory is present"

echo "== the version from the API header"
fake "$fx/hdr/sdk/NvOFInterface/nvOpticalFlowCuda.h"
printf '#define NV_OF_API_MAJOR_VERSION 5\n#define NV_OF_API_MINOR_VERSION 0\n' \
    >"$fx/hdr/sdk/NvOFInterface/nvOpticalFlowCommon.h"
run --src "$fx/hdr/sdk"
check "a renamed tree takes its version from the API header" passes
check "the version line has the major and minor parts" grep -qx 'version 5.0' <<<"$out"
check "a warning says why" says "the version comes from the API header only (5.0)"
sed -i 's/MAJOR_VERSION 5/MAJOR_VERSION 4/' "$fx/hdr/sdk/NvOFInterface/nvOpticalFlowCommon.h"
run --src "$fx/hdr/sdk"
check "an API header of another version is an error" fails_with "holds the Optical Flow API 4.0"
: >"$fx/hdr/sdk/NvOFInterface/nvOpticalFlowCommon.h"
run --src "$fx/hdr/sdk"
check "no version anywhere is an error" fails_with "cannot tell the SDK version"

echo "== hostile archives"
mkdir -p "$fx/evil/a"
fake "$fx/evil/a/x.txt"
(cd "$fx/evil/a" && bsdtar -a -cf "$fx/evil/optical_flow_sdk_5.0.7.zip" -s ',^,../,' x.txt)
if bsdtar -tf "$fx/evil/optical_flow_sdk_5.0.7.zip" | grep -q '^\.\./'; then
    run --src "$fx/evil/optical_flow_sdk_5.0.7.zip"
    check "a member name with .. is refused" fails_with "has a .. component"
else
    echo "skip a member name with .. (bsdtar did not write one)"
fi

# A zip with a symbolic link: absolute, or leading out of the zip.
for kind in abs up; do
    lk=$fx/link-$kind
    sdk_tree "$lk/Optical_Flow_SDK_5.0.7"
    if [[ $kind == abs ]]; then target=/etc/shadow; else target=../../../../etc; fi
    ln -s "$target" "$lk/Optical_Flow_SDK_5.0.7/NvOFBasicSamples/AppOFCuda/data"
    mkdir -p "$lk-dl"
    make_zip "$lk-dl/optical_flow_sdk_5.0.7.zip" "$lk"
    run --src "$lk-dl/optical_flow_sdk_5.0.7.zip"
    if [[ $kind == abs ]]; then
        check "a zip with a link to an absolute path is refused" fails_with "is a symbolic link to an absolute path (/etc/shadow); refusing the archive"
    else
        check "a zip with a link leading out of it is refused" fails_with "is a symbolic link leading out of the archive (../../../../etc)"
    fi
    run --src "$lk/Optical_Flow_SDK_5.0.7"
    if [[ $kind == abs ]]; then
        check "a tree with a link to an absolute path is refused" fails_with "a symbolic link to an absolute path (/etc/shadow)"
    else
        check "a tree with a link leaving it is refused" fails_with "a symbolic link leaving the SDK tree (../../../../etc)"
    fi
done
ln -s ../AppOFCuda.cpp "$fx/link-abs/Optical_Flow_SDK_5.0.7/NvOFBasicSamples/AppOFCuda/inside"
rm "$fx/link-abs/Optical_Flow_SDK_5.0.7/NvOFBasicSamples/AppOFCuda/data"
run --src "$fx/link-abs/Optical_Flow_SDK_5.0.7"
check "a tree with a link that stays inside is accepted" passes
# A special file: a fifo in a tree; a character device in an archive, made
# from an mtree description (no root needed; a zip cannot hold one, but
# bsdtar reads a tar named .zip as well).
spec=$fx/spec/Optical_Flow_SDK_5.0.7
sdk_tree "$spec"
mkfifo "$spec/NvOFBasicSamples/AppOFCuda/pipe"
run --src "$spec"
check "a tree with a fifo is refused" fails_with "NvOFBasicSamples/AppOFCuda/pipe is a special file (a device, fifo or socket); refusing the tree"
rm "$spec/NvOFBasicSamples/AppOFCuda/pipe"
mkdir -p "$fx/devdl"
(
    cd "$fx/spec" && {
        echo '#mtree'
        find Optical_Flow_SDK_5.0.7 -type d -printf './%p type=dir mode=0755\n'
        find Optical_Flow_SDK_5.0.7 -type f -printf './%p type=file mode=0644\n'
        echo './Optical_Flow_SDK_5.0.7/NvOFBasicSamples/null type=char mode=0644 device=native,1,3'
    } >"$fx/dev.mtree" && bsdtar -cf "$fx/devdl/optical_flow_sdk_5.0.7.zip" "@$fx/dev.mtree"
)
run --src "$fx/devdl/optical_flow_sdk_5.0.7.zip"
check "an archive with a device is refused" \
    fails_with "member Optical_Flow_SDK_5.0.7/NvOFBasicSamples/null is a special file (char: a device, fifo or socket); refusing the archive"

echo "== --write and --show"
run --src "$fx/dl" --write
check "--write succeeds" passes
check "it records the zip and its SHA-256" \
    test "$(grep -v '^#' "$conf")" = "NVIDIA_OF_SRC=$zip"$'\n'"SHA256=$zsum"
check "the recorded checksum is the zip's" grep -qx "SHA256=$(sha "$zip")" "$conf"
check "no temporary file is left" test -z "$(find "$of" -name '.selection.conf.*' -print -quit)"
run --show
check "--show prints the checksum" says "SHA256=$zsum"
check "--show prints the source" says "NVIDIA_OF_SRC=$zip"
run_env NVIDIA_OF_SHA256="$(printf '0%.0s' {1..64})" -- --show
check "--show notes an overriding environment" says "note: NVIDIA_OF_SHA256 is set in this environment"
run
check "configure.sh defaults to the source in selection.conf" passes
check "and says so" says "from          $conf"
run --src "$tree" --write
check "--write of a tree succeeds" passes
check "a tree is recorded without a checksum" test "$(grep -v '^#' "$conf")" = "NVIDIA_OF_SRC=$tree"
run --src "$fx/two" --write
check "--write of an invalid source fails" fails_with "holds 2 SDK zips"
check "and keeps the previous selection" test "$(grep -v '^#' "$conf")" = "NVIDIA_OF_SRC=$tree"
run --show --write
check "--show with --write is a usage error" test "$status" = 2
rm -f "$conf"
run --show
check "--show without selection.conf says so" says "no selection.conf"

echo "== selection.sh"
# The parser runs in its own bash, from the copied selection.sh.
# shellcheck disable=SC2016 # the scripts for bash -c expand their own arguments
read_sel='. "$1"; nvidia_of_read_selection "$2" && printf "%s|%s\n" "$nvidia_of_file_src" "$nvidia_of_file_sha256"'
parse() { # parse <content>: nvidia_of_read_selection on it; status and output
    printf '%s' "$1" >"$tmp/sel.conf"
    status=0
    out=$(bash -c "$read_sel" _ "$of/selection.sh" "$tmp/sel.conf" 2>&1) || status=$?
}
parse $'# c\n\nNVIDIA_OF_SRC=/a b/x.zip\nSHA256='"${zsum^^}"$'\n'
check "a valid file parses" passes
check "a path with a space is kept, the checksum in lower case" test "$out" = "/a b/x.zip|$zsum"
pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile lines are literal
parse 'NVIDIA_OF_SRC=$(touch '"$pwned"')'
check "a \$ in a value is refused" fails_with "sel.conf:1: the value of NVIDIA_OF_SRC must not contain"
check "nothing was executed" test ! -e "$pwned"
parse $'NVIDIA_OF_SRC=relative/x.zip\n'
check "a relative path is refused" fails_with "must be an absolute path"
parse $'NVIDIA_OF_SRC=/x.zip\nSHA256=1234\n'
check "a short checksum is refused" fails_with "sel.conf:2: SHA256 must be 64 hexadecimal digits"
parse $'SHA256='"$zsum"$'\n'
check "a checksum without a source is refused" fails_with "SHA256 is set without NVIDIA_OF_SRC"
parse $'NVIDIA_OF_SRC=/x.zip\nNVIDIA_OF_SRC=/y.zip\n'
check "a duplicate key is refused" fails_with "sel.conf:2: NVIDIA_OF_SRC is set twice"
parse $'MAXINE_AFX_SRC=/x\n'
check "an unknown key is refused" fails_with "unknown key MAXINE_AFX_SRC"
parse $'NVIDIA_OF_SRC=/x\tz\n'
check "a tab is refused" fails_with "a control character"

printf 'NVIDIA_OF_SRC=%s\nSHA256=%s\n' "$zip" "$zsum" >"$tmp/sel.conf"
# shellcheck disable=SC2016 # the script for bash -c expands its own arguments
resolve() { # resolve [VAR=value...]: nvidia_of_resolve in its own bash; prints src|sha|from|from
    env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 "$@" bash -c '. "$1"; nvidia_of_resolve "$2" /default &&
        printf "%s|%s|%s|%s\n" "$nvidia_of_src" "$nvidia_of_sha256" "$nvidia_of_src_from" "$nvidia_of_sha256_from"' \
        _ "$of/selection.sh" "$tmp/sel.conf"
}
check "the file's checksum applies to the file's source" \
    test "$(resolve)" = "$zip|$zsum|sel.conf|sel.conf"
check "and to the same path from the environment" \
    test "$(resolve NVIDIA_OF_SRC="$zip")" = "$zip|$zsum|environment|sel.conf"
check "but not to another source from the environment" \
    test "$(resolve NVIDIA_OF_SRC=/other.zip)" = "/other.zip||environment|none"
check "NVIDIA_OF_SHA256 from the environment wins" \
    test "$(resolve NVIDIA_OF_SHA256="${zsum^^}" NVIDIA_OF_SRC=/other.zip)" = "/other.zip|$zsum|environment|environment"
check "a relative NVIDIA_OF_SRC from the environment is refused" not resolve NVIDIA_OF_SRC=rel 2>/dev/null
check "an invalid NVIDIA_OF_SHA256 is refused" not resolve NVIDIA_OF_SHA256=abc 2>/dev/null
rm -f "$tmp/sel.conf"
check "without a file the default applies, with no checksum" test "$(resolve)" = "/default||default|none"

echo "== nothing else"
check "no stubbed tool was called" test ! -s "$calls"
real_conf_after=$(if [[ -e $recipe/selection.conf ]]; then sha256sum <"$recipe/selection.conf"; else echo absent; fi)
check "the working tree's selection.conf is untouched" test "$real_conf_after" = "$real_conf_before"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
