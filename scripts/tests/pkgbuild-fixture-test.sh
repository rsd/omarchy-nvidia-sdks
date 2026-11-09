#!/usr/bin/env bash
# Builds maxine-vfx/PKGBUILD end to end against a FAKE SDK tree (tiny text
# files with the SDK's names, a version header in the SDK's format) and
# checks the package with bsdtar: the environment file, nothing under /etc,
# the shim, the licences, the pruned models. A second and third build take
# their selection from selection.conf, the third with an environment
# variable overriding the file; a hostile selection.conf is never executed
# and does not change `makepkg --printsrcinfo`. Everything happens under mktemp:
# the recipe files are copied there and makepkg's BUILDDIR, PKGDEST, SRCDEST
# and LOGDEST point there, so this working tree gets no src/, pkg/ or
# package. Needs makepkg, fakeroot, bsdtar and a C compiler (the shim); no
# GPU, no network, no NVIDIA download.
# Usage: scripts/tests/pkgbuild-fixture-test.sh. Exits non-zero on any
# failure, 77 when a needed tool is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)

for tool in makepkg fakeroot bsdtar make cc; do
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

fake() { # fake <file>...: tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}

# The fake SDK tree (tree mode), with models for three architectures, an
# engine cache and one dangling link as the SDK ships them.
sdk=$tmp/sdk/VideoFX
fake "$sdk/lib/libVideoFX.so" "$sdk/lib/libNVCVImage.so" "$sdk/include/nvVideoEffects.h" \
    "$sdk/external/cuda/lib/libcudart.so.12" "$sdk/external/tensorrt/lib/libnvinfer.so.10" \
    "$sdk/share/NVIDIA-Software-License-Agreement.pdf" "$sdk/share/external/ThirdPartyLicenses.txt" \
    "$sdk/features/nvvfxgreenscreen/lib/libnvVFXGreenScreen.so" \
    "$sdk/features/nvvfxbackgroundblur/lib/libnvVFXBackgroundBlur.so" \
    "$sdk/lib/models/AIGS_288x512_120_m0.engine.trtpkg" \
    "$sdk/lib/models/AIGS_288x512_89_m0.engine.trtpkg" \
    "$sdk/lib/models/AIGS_288x512_86_m0.engine.trtpkg" \
    "$sdk/lib/models/cache/stale.bin"
mkdir -p "$sdk/external/cuda/include"
ln -s /etc/alternatives/omarchy-nvidia-sdks-test-libcudnn "$sdk/external/cuda/include/cudnn.h"
cat >"$sdk/share/videofx_version.h" <<'EOF'
#ifndef __VIDEOFX_VERSION_H__
#define __VIDEOFX_VERSION_H__

#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_MAJOR 1
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_MINOR 3
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_RELEASE 0
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_BUILD 0

#endif
EOF

# The recipe, copied: what the PKGBUILD reads from the repository.
repo=$tmp/repo
mkdir -p "$repo/maxine-vfx" "$repo/tools/maxine-probe" "$repo/docs"
cp "$top/maxine-vfx/PKGBUILD" "$top/maxine-vfx/assemble.sh" "$top/maxine-vfx/selection.sh" "$repo/maxine-vfx/"
cp -r "$top/tools/os-release-shim" "$repo/tools/"
cp "$top/tools/maxine-probe/fake-os-release" "$repo/tools/maxine-probe/"
cp "$top/docs/usage.md" "$repo/docs/"
cp "$top/LICENSE-MIT" "$top/LICENSE-APACHE" "$repo/"

# build <name> [VAR=value...]: makepkg -f in the copied recipe directory,
# with only the given MAXINE_VFX_* variables; the log in $log, the status in
# $status, the package (when there is exactly one) in $pkg.
log='' status=0 pkg=''
build() {
    local name=$1
    shift
    mkdir -p "$tmp/$name/build" "$tmp/$name/pkgdest" "$tmp/srcdest" "$tmp/logdest"
    log=$tmp/$name/makepkg.log status=0 pkg=''
    (
        cd "$repo/maxine-vfx" &&
            env -u LD_PRELOAD -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
                -u MAXINE_VFX_SRC -u MAXINE_VFX_ARCHS -u MAXINE_VFX_FEATURES \
                BUILDDIR="$tmp/$name/build" PKGDEST="$tmp/$name/pkgdest" SRCDEST="$tmp/srcdest" \
                LOGDEST="$tmp/logdest" PKGEXT=.pkg.tar "$@" \
                makepkg -f -d --nosign --noconfirm
    ) >"$log" 2>&1 || status=$?
    local -a pkgs=("$tmp/$name"/pkgdest/maxine-vfx-sdk-local-*.pkg.tar)
    if ((${#pkgs[@]} == 1)) && [[ -f ${pkgs[0]} ]]; then pkg=${pkgs[0]}; fi
}
# built <description>: the last build succeeded with one package.
built() {
    if ((status == 0)) && [[ -n $pkg ]]; then
        ok "$1: ${pkg##*/}"
        return 0
    fi
    fail "$1: makepkg exits $status, package '${pkg}'"
    cat "$log"
    exit 1
}
logged() { grep -qF -- "$1" "$log"; } # logged <fragment>: the last build log has it
env_file() { bsdtar -xOf "$pkg" usr/share/maxine-vfx/maxine-vfx.env | grep -v '^#'; }

# The PKGBUILD's metadata, before any selection.conf exists.
srcinfo() { (cd "$repo/maxine-vfx" && env -u MAXINE_VFX_SRC -u MAXINE_VFX_ARCHS -u MAXINE_VFX_FEATURES makepkg --printsrcinfo); }
srcinfo_before=$(srcinfo)

build env MAXINE_VFX_SRC="$tmp/sdk" MAXINE_VFX_ARCHS="sm_120 sm_89"
built "makepkg -f -d builds the package from the environment"
check "prepare() prints where each value came from" \
    logged "MAXINE_VFX_SRC=$tmp/sdk (from environment)"
check "the features default to all" logged "MAXINE_VFX_FEATURES=all (from default)"
check "nothing was written into the copied recipe directory" \
    test -z "$(find "$repo/maxine-vfx" -mindepth 1 -maxdepth 1 \( -name src -o -name pkg -o -name '*.pkg.tar*' \) -print -quit)"

listing=$(bsdtar -tf "$pkg")
has() { grep -qxF -- "$1" <<<"$listing"; }
not() { ! "$@"; }
R=/opt/nvidia/maxine/videofx
r=${R#/}

# The environment file, line by line (comments aside).
want="MAXINE_VFX_ROOT=$R
MAXINE_VFX_MODEL_DIR=$R/lib/models
MAXINE_VFX_LIBRARY_PATH=$R/lib:$R/features/nvvfxbackgroundblur/lib:$R/features/nvvfxgreenscreen/lib:$R/external/cuda/lib:$R/external/tensorrt/lib
LD_LIBRARY_PATH=$R/lib:$R/features/nvvfxbackgroundblur/lib:$R/features/nvvfxgreenscreen/lib:$R/external/cuda/lib:$R/external/tensorrt/lib
MAXINE_VFX_OS_RELEASE_SHIM=/usr/lib/maxine-vfx/os-release-shim.so
OMA_BROADCAST_OS_RELEASE=/usr/lib/maxine-vfx/fake-os-release
MAXINE_VFX_FEATURES=nvvfxbackgroundblur,nvvfxgreenscreen
MAXINE_VFX_ARCHS=sm_89,sm_120"
got=$(bsdtar -xOf "$pkg" usr/share/maxine-vfx/maxine-vfx.env | grep -v '^#')
if [[ $got == "$want" ]]; then
    ok "the environment file has exactly the expected keys and values"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
not_preload() { ! bsdtar -xOf "$pkg" usr/share/maxine-vfx/maxine-vfx.env | grep -q '^LD_PRELOAD='; }
check "the environment file does not set LD_PRELOAD" not_preload

check "nothing under /etc" test -z "$(grep -E '^etc(/|$)' <<<"$listing" || true)"
check "the shim is packaged" has usr/lib/maxine-vfx/os-release-shim.so
check "the shim is an ELF library" \
    test "$(bsdtar -xOf "$pkg" usr/lib/maxine-vfx/os-release-shim.so | head -c 4 | od -An -tx1 | tr -d ' \n')" = 7f454c46
check "the replacement os-release is packaged" has usr/lib/maxine-vfx/fake-os-release
check "the usage document is packaged" has usr/share/doc/maxine-vfx-sdk-local/usage.md

lic=usr/share/licenses/maxine-vfx-sdk-local
check "LICENSE-MIT is packaged" has "$lic/LICENSE-MIT"
check "LICENSE-APACHE is packaged" has "$lic/LICENSE-APACHE"
verbose=$(bsdtar -tvf "$pkg")
link_to() { grep -qF -- "$1 -> $2" <<<"$verbose"; } # link_to <path> <target>
check "the SDK licence PDF is linked" \
    link_to "$lic/NVIDIA-Software-License-Agreement.pdf" "$R/share/NVIDIA-Software-License-Agreement.pdf"
check "the third-party licences are linked" \
    link_to "$lic/ThirdPartyLicenses.txt" "$R/share/external/ThirdPartyLicenses.txt"

check "the sm_120 model is packaged" has "$r/lib/models/AIGS_288x512_120_m0.engine.trtpkg"
check "the sm_89 model is packaged" has "$r/lib/models/AIGS_288x512_89_m0.engine.trtpkg"
check "the sm_86 model is pruned" not has "$r/lib/models/AIGS_288x512_86_m0.engine.trtpkg"
check "the engine cache is not packaged" test -z "$(grep -F "$r/lib/models/cache" <<<"$listing" || true)"
check "the green screen library is packaged" has "$r/features/nvvfxgreenscreen/lib/libnvVFXGreenScreen.so"
check "the background blur library is packaged" has "$r/features/nvvfxbackgroundblur/lib/libnvVFXBackgroundBlur.so"
check "the SDK's dangling link is kept as shipped" \
    link_to "$r/external/cuda/include/cudnn.h" /etc/alternatives/omarchy-nvidia-sdks-test-libcudnn
check "the build summary noted the dangling link" grep -qF 'dangling symbolic links kept as shipped by NVIDIA' "$log"

echo "== selection.conf"
lib=$r/features
printf '# test selection\nMAXINE_VFX_SRC=%s\nMAXINE_VFX_ARCHS=sm_86\nMAXINE_VFX_FEATURES=nvvfxgreenscreen\n' \
    "$tmp/sdk" >"$repo/maxine-vfx/selection.conf"
check "selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build conf
built "makepkg -f -d builds from selection.conf alone"
check "the source came from selection.conf" logged "MAXINE_VFX_SRC=$tmp/sdk (from selection.conf)"
check "the architectures came from selection.conf" logged "MAXINE_VFX_ARCHS=sm_86 (from selection.conf)"
check "the features came from selection.conf" logged "MAXINE_VFX_FEATURES=nvvfxgreenscreen (from selection.conf)"
check "the build summary lists the feature left out" logged "nvvfxbackgroundblur (present, not selected)"
listing=$(bsdtar -tf "$pkg")
check "the selected sm_86 model is packaged" has "$r/lib/models/AIGS_288x512_86_m0.engine.trtpkg"
check "the sm_120 model is pruned" not has "$r/lib/models/AIGS_288x512_120_m0.engine.trtpkg"
check "the selected feature is packaged" has "$lib/nvvfxgreenscreen/lib/libnvVFXGreenScreen.so"
check "the feature left out is not packaged" test -z "$(grep -F "$lib/nvvfxbackgroundblur" <<<"$listing" || true)"
check "the environment file lists the packaged feature only" grep -qx "MAXINE_VFX_FEATURES=nvvfxgreenscreen" <<<"$(env_file)"
check "the library path lists the packaged feature only" \
    grep -qx "LD_LIBRARY_PATH=$R/lib:$R/features/nvvfxgreenscreen/lib:$R/external/cuda/lib:$R/external/tensorrt/lib" <<<"$(env_file)"
check "the environment file lists sm_86" grep -qx "MAXINE_VFX_ARCHS=sm_86" <<<"$(env_file)"

build override MAXINE_VFX_ARCHS=sm_120
built "makepkg -f -d with an environment variable over selection.conf"
check "the architectures came from the environment" logged "MAXINE_VFX_ARCHS=sm_120 (from environment)"
check "the features still came from selection.conf" logged "MAXINE_VFX_FEATURES=nvvfxgreenscreen (from selection.conf)"
listing=$(bsdtar -tf "$pkg")
check "the overriding sm_120 model is packaged" has "$r/lib/models/AIGS_288x512_120_m0.engine.trtpkg"
check "the file's sm_86 model is not" not has "$r/lib/models/AIGS_288x512_86_m0.engine.trtpkg"
check "the environment file lists sm_120" grep -qx "MAXINE_VFX_ARCHS=sm_120" <<<"$(env_file)"

pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile lines are literal
printf 'MAXINE_VFX_SRC=$(touch %s)\nMAXINE_VFX_ARCHS=`touch %s`\n' "$pwned" "$pwned" >"$repo/maxine-vfx/selection.conf"
check "a hostile selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build hostile
check "a hostile selection.conf stops the build" test "$status" -ne 0
check "it names the line" logged "selection.conf:1: the value of MAXINE_VFX_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
check "no package was built from it" test -z "$pkg"
rm -f "$repo/maxine-vfx/selection.conf"

# A relative MAXINE_VFX_SRC would be resolved against makepkg's $srcdir.
build relative MAXINE_VFX_SRC=sdk
check "a relative MAXINE_VFX_SRC from the environment stops the build" test "$status" -ne 0
check "it says the path must be absolute" logged "environment: MAXINE_VFX_SRC must be an absolute path"
check "no package was built with it" test -z "$pkg"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
