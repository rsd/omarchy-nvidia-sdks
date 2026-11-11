#!/usr/bin/env bash
# Builds maxine-ar/PKGBUILD end to end against a FAKE SDK tree (tiny text
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
# Usage: maxine-ar/tests/pkgbuild-test.sh. Exits non-zero on any
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

# The fake SDK tree (tree mode), with models for three architectures, the
# core's face model (no architecture in its name), an engine cache and one
# dangling link (the AR SDK 1.2.0.0 core ships none; the build keeps them).
sdk=$tmp/sdk/ARSDK
fake "$sdk/lib/libnvARPose.so" "$sdk/lib/libNVCVImage.so" "$sdk/include/nvAR.h" \
    "$sdk/external/cuda/lib/libcudart.so.12" "$sdk/external/tensorrt/lib/libnvinfer.so.10" \
    "$sdk/share/NVIDIA-Software-License-Agreement-2025.05.05.pdf" \
    "$sdk/share/product-specific-terms-for-nvidia-ai-products-2025.05.05.pdf" "$sdk/share/external/ThirdPartyLicenses.txt" \
    "$sdk/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so" \
    "$sdk/features/nvarfaceboxdetection/lib/libnvARFaceBoxDetection.so" \
    "$sdk/features/nvarfaceboxdetection/license/NVIDIA-Models-Community-License-2025-04-15.pdf" \
    "$sdk/features/nvarfaceboxdetection/license/NVIDIA-Software-License-Agreement-2025.05.05.pdf" \
    "$sdk/features/nvarlandmarkdetection/license/NVIDIA-Models-Community-License-2025-04-15.pdf" \
    "$sdk/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg" \
    "$sdk/lib/models/faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg" \
    "$sdk/lib/models/faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg" \
    "$sdk/lib/models/face_model3.nvf" \
    "$sdk/lib/models/cache/stale.bin"
mkdir -p "$sdk/external/cuda/include"
ln -s /etc/alternatives/omarchy-nvidia-sdks-test-libcudnn "$sdk/external/cuda/include/cudnn.h"
cat >"$sdk/share/arsdk_version.h" <<'EOF'
#ifndef ARSDK_VERSION_H
#define ARSDK_VERSION_H

#define NVIDIA_AR_SDK_VERSION_MAJOR 1
#define NVIDIA_AR_SDK_VERSION_MINOR 2
#define NVIDIA_AR_SDK_VERSION_RELEASE 0
#define NVIDIA_AR_SDK_VERSION_BUILD 0
#define NVIDIA_AR_SDK_VERSION 1, 2, 0, 0
#define NVIDIA_AR_SDK_VERSION_MAJOR_MINOR 1, 2
#define NVIDIA_AR_SDK_VERSION_STRING "1.2.0.0"

#endif
EOF

# The recipe, copied: what the PKGBUILD reads from the repository.
repo=$tmp/repo
mkdir -p "$repo/maxine-ar" "$repo/tools/maxine-probe" "$repo/docs"
cp "$top/maxine-ar/PKGBUILD" "$top/maxine-ar/assemble.sh" "$top/maxine-ar/selection.sh" "$repo/maxine-ar/"
cp -r "$top/tools/os-release-shim" "$repo/tools/"
cp "$top/tools/maxine-probe/fake-os-release" "$repo/tools/maxine-probe/"
cp "$top/docs/usage.md" "$repo/docs/"
cp "$top/LICENSE-MIT" "$top/LICENSE-APACHE" "$repo/"

# build <name> [VAR=value...]: makepkg -f in the copied recipe directory,
# with only the given MAXINE_AR_* variables; the log in $log, the status in
# $status, the package (when there is exactly one) in $pkg.
log='' status=0 pkg=''
build() {
    local name=$1
    shift
    mkdir -p "$tmp/$name/build" "$tmp/$name/pkgdest" "$tmp/srcdest" "$tmp/logdest"
    log=$tmp/$name/makepkg.log status=0 pkg=''
    (
        cd "$repo/maxine-ar" &&
            env -u LD_PRELOAD -u MAXINE_OS_RELEASE -u MAXINE_OS_RELEASE_DEBUG \
                -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
                -u MAXINE_AR_SRC -u MAXINE_AR_ARCHS -u MAXINE_AR_FEATURES \
                BUILDDIR="$tmp/$name/build" PKGDEST="$tmp/$name/pkgdest" SRCDEST="$tmp/srcdest" \
                LOGDEST="$tmp/logdest" PKGEXT=.pkg.tar "$@" \
                makepkg -f -d --nosign --noconfirm
    ) >"$log" 2>&1 || status=$?
    local -a pkgs=("$tmp/$name"/pkgdest/maxine-ar-sdk-local-*.pkg.tar)
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
env_file() { bsdtar -xOf "$pkg" usr/share/maxine-ar/maxine-ar.env | grep -v '^#'; }

# The PKGBUILD's metadata, before any selection.conf exists.
srcinfo() { (cd "$repo/maxine-ar" && env -u MAXINE_AR_SRC -u MAXINE_AR_ARCHS -u MAXINE_AR_FEATURES makepkg --printsrcinfo); }
srcinfo_before=$(srcinfo)

build env MAXINE_AR_SRC="$tmp/sdk" MAXINE_AR_ARCHS="sm_120 sm_89"
built "makepkg -f -d builds the package from the environment"
check "prepare() prints where each value came from" \
    logged "MAXINE_AR_SRC=$tmp/sdk (from environment)"
check "the features default to all" logged "MAXINE_AR_FEATURES=all (from default)"
check "nothing was written into the copied recipe directory" \
    test -z "$(find "$repo/maxine-ar" -mindepth 1 -maxdepth 1 \( -name src -o -name pkg -o -name '*.pkg.tar*' \) -print -quit)"

listing=$(bsdtar -tf "$pkg")
has() { grep -qxF -- "$1" <<<"$listing"; }
not() { ! "$@"; }
R=/opt/nvidia/maxine/arsdk
r=${R#/}

# The environment file, line by line (comments aside).
want="MAXINE_AR_ROOT=$R
MAXINE_AR_MODEL_DIR=$R/lib/models
MAXINE_AR_LIBRARY_PATH=$R/lib:$R/features/nvarfaceboxdetection/lib:$R/features/nvarlandmarkdetection/lib:$R/external/cuda/lib:$R/external/tensorrt/lib
LD_LIBRARY_PATH=$R/lib:$R/features/nvarfaceboxdetection/lib:$R/features/nvarlandmarkdetection/lib:$R/external/cuda/lib:$R/external/tensorrt/lib
MAXINE_AR_OS_RELEASE_SHIM=/usr/lib/maxine-ar/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-ar/fake-os-release
MAXINE_AR_FEATURES=nvarfaceboxdetection,nvarlandmarkdetection
MAXINE_AR_ARCHS=sm_89,sm_120"
got=$(bsdtar -xOf "$pkg" usr/share/maxine-ar/maxine-ar.env | grep -v '^#')
if [[ $got == "$want" ]]; then
    ok "the environment file has exactly the expected keys and values"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
not_preload() { ! bsdtar -xOf "$pkg" usr/share/maxine-ar/maxine-ar.env | grep -q '^LD_PRELOAD='; }
check "the environment file does not set LD_PRELOAD" not_preload

check "nothing under /etc" test -z "$(grep -E '^etc(/|$)' <<<"$listing" || true)"
check "the shim is packaged" has usr/lib/maxine-ar/os-release-shim.so
check "the shim is an ELF library" \
    test "$(bsdtar -xOf "$pkg" usr/lib/maxine-ar/os-release-shim.so | head -c 4 | od -An -tx1 | tr -d ' \n')" = 7f454c46
check "the replacement os-release is packaged" has usr/lib/maxine-ar/fake-os-release
check "the usage document is packaged" has usr/share/doc/maxine-ar-sdk-local/usage.md

lic=usr/share/licenses/maxine-ar-sdk-local
check "LICENSE-MIT is packaged" has "$lic/LICENSE-MIT"
check "LICENSE-APACHE is packaged" has "$lic/LICENSE-APACHE"
verbose=$(bsdtar -tvf "$pkg")
link_to() { grep -qF -- "$1 -> $2" <<<"$verbose"; } # link_to <path> <target>
check "the SDK licence PDF is linked" \
    link_to "$lic/NVIDIA-Software-License-Agreement-2025.05.05.pdf" "$R/share/NVIDIA-Software-License-Agreement-2025.05.05.pdf"
check "the product-specific terms are linked" \
    link_to "$lic/product-specific-terms-for-nvidia-ai-products-2025.05.05.pdf" \
    "$R/share/product-specific-terms-for-nvidia-ai-products-2025.05.05.pdf"
check "the third-party licences are linked" \
    link_to "$lic/ThirdPartyLicenses.txt" "$R/share/external/ThirdPartyLicenses.txt"
check "the models' licence is linked from the first feature that ships it" \
    link_to "$lic/NVIDIA-Models-Community-License-2025-04-15.pdf" \
    "$R/features/nvarfaceboxdetection/license/NVIDIA-Models-Community-License-2025-04-15.pdf"
models_links=$(grep -cF -- "$lic/NVIDIA-Models-Community-License-2025-04-15.pdf" <<<"$listing" || true)
check "the models' licence is linked once (got $models_links)" test "$models_links" -eq 1
check "the SDK's own licence PDF wins over a feature's copy of the same name" \
    not link_to "$lic/NVIDIA-Software-License-Agreement-2025.05.05.pdf" \
    "$R/features/nvarfaceboxdetection/license/NVIDIA-Software-License-Agreement-2025.05.05.pdf"

check "the sm_120 model is packaged" has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
check "the sm_89 model is packaged" has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg"
check "the sm_86 model is pruned" not has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg"
check "the core's face model (no architecture) is kept" has "$r/lib/models/face_model3.nvf"
check "the engine cache is not packaged" test -z "$(grep -F "$r/lib/models/cache" <<<"$listing" || true)"
check "the landmark detection library is packaged" has "$r/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so"
check "the face box detection library is packaged" has "$r/features/nvarfaceboxdetection/lib/libnvARFaceBoxDetection.so"
check "the SDK's dangling link is kept as shipped" \
    link_to "$r/external/cuda/include/cudnn.h" /etc/alternatives/omarchy-nvidia-sdks-test-libcudnn
check "the build summary noted the dangling link" grep -qF 'dangling symbolic links kept as shipped by NVIDIA' "$log"

echo "== selection.conf"
lib=$r/features
printf '# test selection\nMAXINE_AR_SRC=%s\nMAXINE_AR_ARCHS=sm_86\nMAXINE_AR_FEATURES=nvarlandmarkdetection\n' \
    "$tmp/sdk" >"$repo/maxine-ar/selection.conf"
check "selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build conf
built "makepkg -f -d builds from selection.conf alone"
check "the source came from selection.conf" logged "MAXINE_AR_SRC=$tmp/sdk (from selection.conf)"
check "the architectures came from selection.conf" logged "MAXINE_AR_ARCHS=sm_86 (from selection.conf)"
check "the features came from selection.conf" logged "MAXINE_AR_FEATURES=nvarlandmarkdetection (from selection.conf)"
check "the build summary lists the feature left out" logged "nvarfaceboxdetection (present, not selected)"
listing=$(bsdtar -tf "$pkg")
check "the selected sm_86 model is packaged" has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg"
check "the sm_120 model is pruned" not has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
check "the selected feature is packaged" has "$lib/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so"
check "the feature left out is not packaged" test -z "$(grep -F "$lib/nvarfaceboxdetection" <<<"$listing" || true)"
check "the environment file lists the packaged feature only" grep -qx "MAXINE_AR_FEATURES=nvarlandmarkdetection" <<<"$(env_file)"
check "the library path lists the packaged feature only" \
    grep -qx "LD_LIBRARY_PATH=$R/lib:$R/features/nvarlandmarkdetection/lib:$R/external/cuda/lib:$R/external/tensorrt/lib" <<<"$(env_file)"
check "the environment file lists sm_86" grep -qx "MAXINE_AR_ARCHS=sm_86" <<<"$(env_file)"

build override MAXINE_AR_ARCHS=sm_120
built "makepkg -f -d with an environment variable over selection.conf"
check "the architectures came from the environment" logged "MAXINE_AR_ARCHS=sm_120 (from environment)"
check "the features still came from selection.conf" logged "MAXINE_AR_FEATURES=nvarlandmarkdetection (from selection.conf)"
listing=$(bsdtar -tf "$pkg")
check "the overriding sm_120 model is packaged" has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
check "the file's sm_86 model is not" not has "$r/lib/models/faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg"
check "the environment file lists sm_120" grep -qx "MAXINE_AR_ARCHS=sm_120" <<<"$(env_file)"

pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile lines are literal
printf 'MAXINE_AR_SRC=$(touch %s)\nMAXINE_AR_ARCHS=`touch %s`\n' "$pwned" "$pwned" >"$repo/maxine-ar/selection.conf"
check "a hostile selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build hostile
check "a hostile selection.conf stops the build" test "$status" -ne 0
check "it names the line" logged "selection.conf:1: the value of MAXINE_AR_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
check "no package was built from it" test -z "$pkg"
rm -f "$repo/maxine-ar/selection.conf"

# A relative MAXINE_AR_SRC would be resolved against makepkg's $srcdir.
build relative MAXINE_AR_SRC=sdk
check "a relative MAXINE_AR_SRC from the environment stops the build" test "$status" -ne 0
check "it says the path must be absolute" logged "environment: MAXINE_AR_SRC must be an absolute path"
check "no package was built with it" test -z "$pkg"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
