#!/usr/bin/env bash
# Builds nvidia-optical-flow/PKGBUILD end to end against a FAKE SDK (tiny
# text files with the SDK's documented names, zipped with bsdtar) and checks
# the package with bsdtar: the installed tree, the environment file, the
# licences, that nothing lands outside /opt/nvidia/optical-flow and
# /usr/share, and the checksum: a zip selected with configure.sh --write
# builds, a mismatching or missing checksum stops the build. A tree builds
# without one; a tree without FRUC has no library path lines; FRUC shipped
# as NvFRUC.so gets a libNvFRUC.so link, and under the NvOFFRUC names is
# packaged under them; a hostile selection.conf is never executed and does
# not change `makepkg --printsrcinfo`; a zip or tree with a symbolic link
# out of it or a special file stops the build, also when the tree changed
# after configure.sh --write. Everything happens
# under mktemp: the recipe files are copied there and makepkg's BUILDDIR,
# PKGDEST, SRCDEST and LOGDEST point there, so this working tree gets no
# src/, pkg/ or package. Needs makepkg, fakeroot, bsdtar and sha256sum; no
# GPU, no network, no NVIDIA download.
# Usage: nvidia-optical-flow/tests/pkgbuild-test.sh. Exits non-zero on any
# failure, 77 when a needed tool is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)

for tool in makepkg fakeroot bsdtar sha256sum; do
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
not() { ! "$@"; }

fake() { # fake <file>...: tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}
sdk_tree() { # sdk_tree <dir> [fruc-lib-name|none]
    local d=$1 lib=${2:-libNvFRUC.so}
    fake "$d/NvOFInterface/nvOpticalFlowCommon.h" "$d/NvOFInterface/nvOpticalFlowCuda.h" \
        "$d/NvOFInterface/nvOpticalFlowD3D11.h" \
        "$d/NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp" "$d/NvOFTracker/inc/NvOFTracker.h" \
        "$d/Common/External/FreeImage/licence-fi.txt" "$d/Read_Me.pdf" "$d/LicenseAgreement.pdf"
    if [[ $lib != none ]]; then
        fake "$d/NvOFFRUC/Interface/NvFRUC.h" "$d/NvOFFRUC/NvOFFRUCSample/bin/ubuntu/$lib" \
            "$d/NvOFFRUC/NvOFFRUCSample/bin/ubuntu/libcudart.so.11.6.55"
    fi
}

# The fake SDK: a zip, a tree without FRUC, a zip whose FRUC is NvFRUC.so.
sdk_tree "$tmp/stage/Optical_Flow_SDK_5.0.7"
mkdir -p "$tmp/dl"
zip=$tmp/dl/optical_flow_sdk_5.0.7.zip
(cd "$tmp/stage" && bsdtar -a -cf "$zip" Optical_Flow_SDK_5.0.7)
nofruc=$tmp/nofruc/Optical_Flow_SDK_5.0.7
sdk_tree "$nofruc" none
sdk_tree "$tmp/stage2/Optical_Flow_SDK_5.0.7" NvFRUC.so
mkdir -p "$tmp/dl2"
zip2=$tmp/dl2/optical_flow_sdk_5.0.7.zip
(cd "$tmp/stage2" && bsdtar -a -cf "$zip2" Optical_Flow_SDK_5.0.7)

# The recipe, copied: what the PKGBUILD reads from the repository.
repo=$tmp/repo
rdir=$repo/nvidia-optical-flow
mkdir -p "$rdir"
cp "$top/nvidia-optical-flow/PKGBUILD" "$top/nvidia-optical-flow/assemble.sh" \
    "$top/nvidia-optical-flow/selection.sh" "$top/nvidia-optical-flow/configure.sh" \
    "$top/nvidia-optical-flow/README.md" "$rdir/"
cp "$top/LICENSE-MIT" "$top/LICENSE-APACHE" "$repo/"

# build <name> [VAR=value...]: makepkg -f in the copied recipe directory,
# with only the given NVIDIA_OF_* variables; the log in $log, the status in
# $status, the package (when there is exactly one) in $pkg.
log='' status=0 pkg=''
build() {
    local name=$1
    shift
    mkdir -p "$tmp/$name/build" "$tmp/$name/pkgdest" "$tmp/srcdest" "$tmp/logdest"
    log=$tmp/$name/makepkg.log status=0 pkg=''
    (
        cd "$rdir" &&
            env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 \
                BUILDDIR="$tmp/$name/build" PKGDEST="$tmp/$name/pkgdest" SRCDEST="$tmp/srcdest" \
                LOGDEST="$tmp/logdest" PKGEXT=.pkg.tar "$@" \
                makepkg -f -d --nosign --noconfirm
    ) >"$log" 2>&1 || status=$?
    local -a pkgs=("$tmp/$name"/pkgdest/nvidia-optical-flow-sdk-local-*.pkg.tar)
    if ((${#pkgs[@]} == 1)) && [[ -f ${pkgs[0]} ]]; then pkg=${pkgs[0]}; fi
}
built() { # built <description>: the last build succeeded with one package.
    if ((status == 0)) && [[ -n $pkg ]]; then
        ok "$1: ${pkg##*/}"
        return 0
    fi
    fail "$1: makepkg exits $status, package '${pkg}'"
    cat "$log"
    exit 1
}
logged() { grep -qF -- "$1" "$log"; } # logged <fragment>: the last build log has it
env_file() { bsdtar -xOf "$pkg" usr/share/nvidia-optical-flow/nvidia-optical-flow.env | grep -v '^#'; }
srcinfo() { (cd "$rdir" && env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 makepkg --printsrcinfo); }
srcinfo_before=$(srcinfo)
check "the metadata names the provides" grep -qxF $'\tprovides = nvidia-optical-flow-sdk=5.0.7' <<<"$srcinfo_before"
check "the metadata depends on nvidia-utils" grep -qxF $'\tdepends = nvidia-utils' <<<"$srcinfo_before"

R=/opt/nvidia/optical-flow
r=${R#/}
lic=usr/share/licenses/nvidia-optical-flow-sdk-local

echo "== a zip selected with configure.sh --write"
(cd "$rdir" && env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 ./configure.sh --src "$tmp/dl" --write >/dev/null)
check "configure.sh recorded the checksum" grep -qx "SHA256=$(sha256sum "$zip" | cut -d' ' -f1)" "$rdir/selection.conf"
check "selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build conf
built "makepkg -f -d builds the package from selection.conf"
check "prepare() prints where the source came from" logged "NVIDIA_OF_SRC=$zip (from selection.conf)"
check "prepare() prints where the checksum came from" logged "(from selection.conf)"
check "the checksum was verified" logged "SHA-256 of optical_flow_sdk_5.0.7.zip verified"
check "nothing was written into the copied recipe directory" \
    test -z "$(find "$rdir" -mindepth 1 -maxdepth 1 \( -name src -o -name pkg -o -name '*.pkg.tar*' \) -print -quit)"
check "the zip was not extracted next to it" test "$(find "$tmp/dl" -mindepth 1 | wc -l)" = 1
listing=$(bsdtar -tf "$pkg")
has() { grep -qxF -- "$1" <<<"$listing"; }
check "the API headers are in include/" has "$r/include/nvOpticalFlowCommon.h"
check "every header of the API directory is in include/" has "$r/include/nvOpticalFlowD3D11.h"
check "the CUDA header is in include/" has "$r/include/nvOpticalFlowCuda.h"
check "the FRUC header is in fruc/include/" has "$r/fruc/include/NvFRUC.h"
check "the FRUC library is in fruc/lib/" has "$r/fruc/lib/libNvFRUC.so"
check "the bundled CUDA runtime is in fruc/lib/" has "$r/fruc/lib/libcudart.so.11.6.55"
check "the samples are a source tree" has "$r/samples/AppOFCuda/AppOFCuda.cpp"
check "NvOFTracker is a source tree" has "$r/tracker/inc/NvOFTracker.h"
check "the SDK's top-level files are kept" has "$r/Read_Me.pdf"
check "the FreeImage licence is in licenses/" has "$r/licenses/Common_External_FreeImage_licence-fi.txt"
check "the recipe README is the documentation" has usr/share/doc/nvidia-optical-flow-sdk-local/README.md
outside=$(grep -v '^\.' <<<"$listing" | grep -vE "^($r|usr/share)(/|$)" | grep -vxE 'opt/|opt/nvidia/|usr/' || true)
check "nothing lands outside $R and /usr/share" test -z "$outside"
check "nothing under /usr/include, /usr/lib or /etc" \
    test -z "$(grep -E '^(usr/include|usr/lib|etc)(/|$)' <<<"$listing" || true)"
check "no profile.d script" test -z "$(grep -F 'profile.d' <<<"$listing" || true)"
want="NVIDIA_OF_ROOT=$R
NVIDIA_OF_INCLUDE_DIR=$R/include
NVIDIA_OF_LIBRARY_PATH=$R/fruc/lib
LD_LIBRARY_PATH=$R/fruc/lib
NVIDIA_OF_FEATURES=api,fruc,tracker-src,samples"
got=$(env_file)
if [[ $got == "$want" ]]; then
    ok "the environment file has exactly the expected keys and values"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
verbose=$(bsdtar -tvf "$pkg")
link_to() { grep -qF -- "$1 -> $2" <<<"$verbose"; } # link_to <path> <target>
check "NvFRUC.so links to the shipped libNvFRUC.so" link_to "$r/fruc/lib/NvFRUC.so" libNvFRUC.so
check "LICENSE-MIT is packaged" has "$lic/LICENSE-MIT"
check "the SDK licence is linked" link_to "$lic/LicenseAgreement.pdf" "$R/LicenseAgreement.pdf"
check "the FreeImage licence is linked" \
    link_to "$lic/Common_External_FreeImage_licence-fi.txt" "$R/licenses/Common_External_FreeImage_licence-fi.txt"
check "the readme is not linked as a licence" not has "$lic/Read_Me.pdf"

echo "== checksums"
build mismatch NVIDIA_OF_SHA256="$(printf '0%.0s' {1..64})"
check "a mismatching checksum stops the build" test "$status" -ne 0
check "it says so" logged "checksum mismatch for $zip"
check "no package was built" test -z "$pkg"
check "the checksum came from the environment" logged "(from environment)"
rm -f "$rdir/selection.conf"
build nosum NVIDIA_OF_SRC="$zip"
check "a zip without a recorded checksum stops the build" test "$status" -ne 0
check "it names the command that records it" logged "no checksum is recorded for $zip"
check "no package was built from it" test -z "$pkg"

echo "== a tree without FRUC, from the environment"
build tree NVIDIA_OF_SRC="$nofruc"
built "makepkg -f -d builds from a tree"
check "prepare() says a tree has no checksum" logged "checksum  none: the source is an extracted tree"
listing=$(bsdtar -tf "$pkg")
check "no fruc/ is packaged" test -z "$(grep -F "$r/fruc" <<<"$listing" || true)"
want="NVIDIA_OF_ROOT=$R
NVIDIA_OF_INCLUDE_DIR=$R/include
NVIDIA_OF_FEATURES=api,tracker-src,samples"
got=$(env_file)
if [[ $got == "$want" ]]; then
    ok "without FRUC there is no NVIDIA_OF_LIBRARY_PATH and no (empty) LD_LIBRARY_PATH"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
build treesum NVIDIA_OF_SRC="$nofruc" NVIDIA_OF_SHA256="$(printf 'a%.0s' {1..64})"
check "a checksum for a tree stops the build" test "$status" -ne 0
check "it says a tree has none" logged "is an extracted tree, which has none"

echo "== FRUC shipped as NvFRUC.so"
build fruc2 NVIDIA_OF_SRC="$zip2" NVIDIA_OF_SHA256="$(sha256sum "$zip2" | cut -d' ' -f1)"
built "makepkg -f -d builds with NvFRUC.so"
verbose=$(bsdtar -tvf "$pkg")
check "NvFRUC.so is packaged as shipped" grep -qE " $r/fruc/lib/NvFRUC.so$" <<<"$verbose"
check "libNvFRUC.so links to it" link_to "$r/fruc/lib/libNvFRUC.so" NvFRUC.so

echo "== FRUC under the NvOFFRUC names"
fam=$tmp/fam/Optical_Flow_SDK_5.0.7
sdk_tree "$fam" none
fake "$fam/NvOFFRUC/Interface/NvOFFRUC.h" "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/NvOFFRUC.so" \
    "$fam/NvOFFRUC/NvOFFRUCSample/bin/linux/libcudart.so.12"
build fam NVIDIA_OF_SRC="$fam"
built "makepkg -f -d builds with NvOFFRUC.h and NvOFFRUC.so"
verbose=$(bsdtar -tvf "$pkg")
check "NvOFFRUC.h is packaged under its name" grep -qE " $r/fruc/include/NvOFFRUC.h$" <<<"$verbose"
check "NvOFFRUC.so is packaged as shipped" grep -qE " $r/fruc/lib/NvOFFRUC.so$" <<<"$verbose"
check "libNvOFFRUC.so links to it" link_to "$r/fruc/lib/libNvOFFRUC.so" NvOFFRUC.so
check "the bundled runtime is packaged with it" grep -qE " $r/fruc/lib/libcudart.so.12$" <<<"$verbose"
check "the environment file names the FRUC library path" grep -qx "LD_LIBRARY_PATH=$R/fruc/lib" <<<"$(env_file)"

echo "== links out of the tree and special files"
evil=$tmp/evil/Optical_Flow_SDK_5.0.7
sdk_tree "$evil"
ln -s /etc/shadow "$evil/NvOFTracker/inc/shadow"
mkdir -p "$tmp/evildl"
(cd "$tmp/evil" && bsdtar -a -cf "$tmp/evildl/optical_flow_sdk_5.0.7.zip" Optical_Flow_SDK_5.0.7)
build evilzip NVIDIA_OF_SRC="$tmp/evildl/optical_flow_sdk_5.0.7.zip" \
    NVIDIA_OF_SHA256="$(sha256sum "$tmp/evildl/optical_flow_sdk_5.0.7.zip" | cut -d' ' -f1)"
check "a zip with a link to an absolute path stops the build" test "$status" -ne 0
check "it names the link" logged "member Optical_Flow_SDK_5.0.7/NvOFTracker/inc/shadow is a symbolic link to an absolute path (/etc/shadow)"
check "nothing was extracted from it" test -z "$(find "$tmp/evilzip/build" -name nvOpticalFlowCommon.h -print -quit)"
build eviltree NVIDIA_OF_SRC="$evil"
check "a tree with a link to an absolute path stops the build" test "$status" -ne 0
check "it says so" logged "NvOFTracker/inc/shadow: a symbolic link to an absolute path (/etc/shadow)"
rm "$evil/NvOFTracker/inc/shadow"
ln -s ../../../../../etc "$evil/NvOFTracker/inc/up"
build evilup NVIDIA_OF_SRC="$evil"
check "a tree with a link leaving it stops the build" test "$status" -ne 0
check "it says so" logged "a symbolic link leaving the SDK tree (../../../../../etc)"
rm "$evil/NvOFTracker/inc/up"
mkfifo "$evil/NvOFTracker/inc/pipe"
build evilfifo NVIDIA_OF_SRC="$evil"
check "a tree with a fifo stops the build" test "$status" -ne 0
check "it names the fifo" logged "NvOFTracker/inc/pipe is a special file (a device, fifo or socket)"
check "no package was built from it" test -z "$pkg"
rm "$evil/NvOFTracker/inc/pipe"

echo "== a tree changed after configure.sh --write"
(cd "$rdir" && env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 ./configure.sh --src "$evil" --write >/dev/null)
check "configure.sh accepted the clean tree" grep -qx "NVIDIA_OF_SRC=$evil" "$rdir/selection.conf"
rm "$evil/NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp"
ln -s /etc/shadow "$evil/NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp"
build swapped
check "a file swapped for a link to /etc/shadow after configure.sh stops the build" test "$status" -ne 0
check "it names the swapped file" logged "NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp: a symbolic link to an absolute path (/etc/shadow)"
check "no package was built from the swapped tree" test -z "$pkg"
rm -f "$rdir/selection.conf"

echo "== hostile input"
pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile line is literal
printf 'NVIDIA_OF_SRC=$(touch %s)\n' "$pwned" >"$rdir/selection.conf"
check "a hostile selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build hostile
check "a hostile selection.conf stops the build" test "$status" -ne 0
check "it names the line" logged "selection.conf:1: the value of NVIDIA_OF_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
rm -f "$rdir/selection.conf"
build relative NVIDIA_OF_SRC=dl
check "a relative NVIDIA_OF_SRC from the environment stops the build" test "$status" -ne 0
check "it says the path must be absolute" logged "environment: NVIDIA_OF_SRC must be an absolute path"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
