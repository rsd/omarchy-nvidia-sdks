#!/usr/bin/env bash
# Tests scripts/aur.sh, the generator of the recipes' AUR copies, against a
# snapshot of this working tree committed into a scratch repository (the
# generator's --from-git mode: the helpers are fetched from it as
# git+file://, so no network and no push are needed):
#   - every recipe: the generated PKGBUILD reads nothing from a working tree,
#     pins the snapshot's commit, has the Maintainer line, and its .SRCINFO
#     is that of the PKGBUILD alone in an empty directory, whatever the
#     MAXINE_*/NVIDIA_* environment and ~/Downloads hold;
#   - --aur writes exactly PKGBUILD, .SRCINFO and LICENSE into the top of a
#     git clone, --check finds them current, then stale; a directory that is
#     not the top of a clone, or holds another file, is refused;
#   - maxine-vfx is built end to end from a directory holding only the
#     generated PKGBUILD (an AUR clone) against a FAKE SDK tree: makepkg
#     fetches the pinned helpers, verifies their checksum, and reads
#     selection.conf from that directory;
#   - nvidia-optical-flow, in such a clone: configure.sh is where the header
#     says, the build's advice for a zip without a checksum names a command
#     that works there (configure.sh --conf <the clone>/selection.conf), and
#     the build then succeeds from the selection.conf it writes.
# Everything happens under mktemp. Needs git, makepkg, fakeroot, bsdtar and
# a C compiler (the shim); no GPU, no network, no NVIDIA download.
# Usage: scripts/tests/aur-test.sh. Exits non-zero on any failure, 77 when a
# needed tool is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
aur_sh=$top/scripts/aur.sh

for tool in git makepkg fakeroot bsdtar make cc; do
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

# The snapshot: every tracked and untracked, not ignored file of the working
# tree, as it is now (so that uncommitted changes are tested), committed.
snap=$tmp/snap
mkdir -p "$snap"
(cd "$top" && git ls-files -z -co --exclude-standard) |
    while IFS= read -r -d '' f; do [[ -e $top/$f ]] && printf '%s\0' "$f"; done |
    (cd "$top" && tar --null -T - -cf -) | tar -xf - -C "$snap"
git -C "$snap" init -q -b main
git -C "$snap" add -A
git -C "$snap" -c user.name=test -c user.email=test@example.invalid commit -qm snapshot
commit=$(git -C "$snap" rev-parse HEAD)

gen() { "$aur_sh" --from-git "$snap" "$@"; } # gen <args>: the generator, from the snapshot

for recipe in maxine-vfx maxine-ar maxine-afx nvidia-optical-flow nvidia-tensorrt; do
    echo "== $recipe"
    out=$tmp/gen/$recipe
    mkdir -p "$out/recipe" "$out/home/Downloads"
    if ! gen --recipe "$recipe" >"$out/recipe/PKGBUILD" 2>"$out/err"; then
        fail "$recipe: the generator succeeds"
        cat "$out/err"
        continue
    fi
    p=$out/recipe/PKGBUILD
    check "$recipe: the first line is the Maintainer line" \
        test "$(head -n 1 "$p")" = '# Maintainer: Raul Dias <raul@dias.com.br>'
    check "$recipe: nothing is read from a working tree" not grep -q 'startdir/\.\.' "$p"
    check "$recipe: the helpers are read from \$srcdir" grep -qx '_repo=omarchy-nvidia-sdks' "$p"
    check "$recipe: the snapshot's commit is pinned" grep -qx "_commit=$commit" "$p"
    check "$recipe: the header no longer says it is built from this working tree" \
        not grep -q 'built from this working tree' "$p"
    check "$recipe: the header's build examples run in the clone" \
        not grep -nE '^# Build \(from|^#   \./configure\.sh|source=\(\) is empty|gitignored|git-ignored' "$p"
    check "$recipe: bash -n" bash -n "$p"
    gen --recipe "$recipe" --srcinfo >"$out/SRCINFO"
    # A fresh --printsrcinfo of the PKGBUILD alone, in a clean environment.
    (cd "$out/recipe" && env -i PATH="$PATH" HOME="$out/home" LC_ALL=C makepkg --printsrcinfo) >"$out/fresh"
    check "$recipe: .SRCINFO is a fresh makepkg --printsrcinfo" cmp -s "$out/SRCINFO" "$out/fresh"
    check "$recipe: .SRCINFO lists the pinned helpers" \
        grep -qxF "	source = omarchy-nvidia-sdks::git+file://$snap#commit=$commit" "$out/SRCINFO"
    check "$recipe: git is a make dependency" grep -qxF '	makedepends = git' "$out/SRCINFO"
    # The builder's variables, a selection.conf and a ~/Downloads copy next to
    # the generator do not reach the .SRCINFO.
    printf 'NVIDIA_TRT_SRC=/nonexistent\n' >"$tmp/selection.conf"
    : >"$out/home/Downloads/TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst"
    (cd "$tmp" && HOME="$out/home" NVIDIA_TRT_SRC=/nonexistent MAXINE_VFX_SRC=/nonexistent \
        NVIDIA_OF_SRC=/nonexistent gen --recipe "$recipe" --srcinfo) >"$out/SRCINFO.env"
    check "$recipe: the environment does not change the .SRCINFO" cmp -s "$out/SRCINFO" "$out/SRCINFO.env"
    rm -f "$tmp/selection.conf"
done
check "nvidia-tensorrt: the .SRCINFO is the download case" \
    grep -q '^	source = TensorRT-Enterprise-.*::https://developer.nvidia.com/downloads/' "$tmp/gen/nvidia-tensorrt/SRCINFO"

echo "== --aur and --check"
clone=$tmp/aur/maxine-vfx-sdk-local
git init -q -b master "$clone"
check "--aur writes into the top of a git clone" gen --recipe maxine-vfx --aur "$clone"
check "it writes exactly PKGBUILD, .SRCINFO and LICENSE" \
    test "$(cd "$clone" && find . -mindepth 1 -maxdepth 1 ! -name .git -printf '%P\n' | LC_ALL=C sort | tr '\n' ' ')" = ".SRCINFO LICENSE PKGBUILD "
check "LICENSE is the 0BSD text" grep -qxF 'purpose with or without fee is hereby granted.' "$clone/LICENSE"
check "--check finds them current" gen --recipe maxine-vfx --check "$clone"
check "git's index of the clone is untouched" test -z "$(git -C "$clone" ls-files)"
echo '# edited' >>"$clone/PKGBUILD"
check "--check fails on an edited PKGBUILD" not gen --recipe maxine-vfx --check "$clone"
gen --recipe maxine-vfx --aur "$clone"
touch "$clone/stray"
check "--aur refuses a clone holding another file" not gen --recipe maxine-vfx --aur "$clone"
rm -f "$clone/stray"
mkdir -p "$clone/sub"
check "--aur refuses a directory inside a clone" not gen --recipe maxine-vfx --aur "$clone/sub"
rmdir "$clone/sub"
check "--aur refuses a directory that is not a clone" not gen --recipe maxine-vfx --aur "$tmp/gen"
check "an unknown recipe is a usage error" \
    test "$(set +e; gen --recipe tools >/dev/null 2>&1; echo $?)" = 2

echo "== maxine-vfx built from an AUR clone"
fake() { # fake <file>...: tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}
sdk=$tmp/sdk/VideoFX
fake "$sdk/lib/libVideoFX.so" "$sdk/lib/libNVCVImage.so" "$sdk/include/nvVideoEffects.h" \
    "$sdk/external/cuda/lib/libcudart.so.12" "$sdk/external/tensorrt/lib/libnvinfer.so.10" \
    "$sdk/share/NVIDIA-Software-License-Agreement.pdf" \
    "$sdk/features/nvvfxgreenscreen/lib/libnvVFXGreenScreen.so" \
    "$sdk/lib/models/AIGS_288x512_120_m0.engine.trtpkg" \
    "$sdk/lib/models/AIGS_288x512_86_m0.engine.trtpkg"
cat >"$sdk/share/videofx_version.h" <<'EOF'
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_MAJOR 1
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_MINOR 3
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_RELEASE 0
#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_BUILD 0
EOF
build=$tmp/build
rm -f "$clone/.SRCINFO" "$clone/LICENSE" # makepkg needs only the PKGBUILD
printf 'MAXINE_VFX_SRC=%s\nMAXINE_VFX_ARCHS=sm_86\n' "$tmp/sdk" >"$clone/selection.conf"
mkdir -p "$build/b" "$build/pkgdest" "$build/srcdest" "$build/home"
status=0
(
    cd "$clone" &&
        env -u LD_PRELOAD -u MAXINE_OS_RELEASE -u MAXINE_OS_RELEASE_DEBUG \
            -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
            -u MAXINE_VFX_SRC -u MAXINE_VFX_ARCHS -u MAXINE_VFX_FEATURES \
            BUILDDIR="$build/b" PKGDEST="$build/pkgdest" SRCDEST="$build/srcdest" \
            LOGDEST="$build" PKGEXT=.pkg.tar \
            makepkg -f -d --nosign --noconfirm
) >"$build/log" 2>&1 || status=$?
pkgs=("$build"/pkgdest/maxine-vfx-sdk-local-*.pkg.tar)
if ((status == 0)) && [[ -f ${pkgs[0]} ]]; then
    ok "makepkg builds the generated PKGBUILD from a clone holding only it: ${pkgs[0]##*/}"
    listing=$(bsdtar -tf "${pkgs[0]}")
    has() { grep -qxF -- "$1" <<<"$listing"; }
    logged() { grep -qF -- "$1" "$build/log"; }
    check "makepkg verified the pinned helpers' checksum" grep -q 'omarchy-nvidia-sdks \.\.\. Passed' "$build/log"
    check "the selection came from selection.conf next to the PKGBUILD" \
        logged "MAXINE_VFX_SRC=$tmp/sdk (from selection.conf)"
    check "the shim was built from the pinned source" has usr/lib/maxine-vfx/os-release-shim.so
    check "the replacement os-release is packaged" has usr/lib/maxine-vfx/fake-os-release
    check "the usage document is packaged" has usr/share/doc/maxine-vfx-sdk-local/usage.md
    check "this repository's licence is packaged" has usr/share/licenses/maxine-vfx-sdk-local/LICENSE-MIT
    check "the selected sm_86 model is packaged" has opt/nvidia/maxine/videofx/lib/models/AIGS_288x512_86_m0.engine.trtpkg
    check "the sm_120 model is pruned" not has opt/nvidia/maxine/videofx/lib/models/AIGS_288x512_120_m0.engine.trtpkg
    check "no build path is in the environment file" \
        not grep -qF "$build" <<<"$(bsdtar -xOf "${pkgs[0]}" usr/share/maxine-vfx/maxine-vfx.env)"
    check "nothing but the selection was left in the clone" \
        test "$(cd "$clone" && find . -mindepth 1 -maxdepth 1 ! -name .git -printf '%P\n' | LC_ALL=C sort | tr '\n' ' ')" = "PKGBUILD selection.conf "
else
    fail "makepkg builds the generated PKGBUILD from a clone holding only it (status $status)"
    cat "$build/log"
fi

echo "== nvidia-optical-flow from an AUR clone: the advice works there"
# A clone named after the pkgbase, with BUILDDIR its parent: src/ is the
# clone's, whatever the builder's makepkg.conf says.
ofc=$tmp/aur/nvidia-optical-flow-sdk-local
mkdir -p "$ofc" "$tmp/of/pkgdest" "$tmp/of/srcdest" "$tmp/of/stage/Optical_Flow_SDK_5.0.7/NvOFInterface"
gen --recipe nvidia-optical-flow >"$ofc/PKGBUILD"
fake "$tmp/of/stage/Optical_Flow_SDK_5.0.7/NvOFInterface/nvOpticalFlowCommon.h" \
    "$tmp/of/stage/Optical_Flow_SDK_5.0.7/NvOFInterface/nvOpticalFlowCuda.h" \
    "$tmp/of/stage/Optical_Flow_SDK_5.0.7/LICENSE.txt"
ofzip=$tmp/of/dl/optical_flow_sdk_5.0.7.zip
mkdir -p "$tmp/of/dl"
(cd "$tmp/of/stage" && bsdtar -a -cf "$ofzip" Optical_Flow_SDK_5.0.7)
ofmk() { # ofmk <log> [VAR=value...] -- <makepkg args>: makepkg in the clone
    local log=$1
    shift
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    (
        cd "$ofc" &&
            env -u NVIDIA_OF_SRC -u NVIDIA_OF_SHA256 BUILDDIR="$tmp/aur" PKGDEST="$tmp/of/pkgdest" \
                SRCDEST="$tmp/of/srcdest" LOGDEST="$tmp/of" PKGEXT=.pkg.tar "${vars[@]}" \
                makepkg "$@" --nosign --noconfirm
    ) >"$log" 2>&1 || status=$?
}
ofmk "$tmp/of/fetch.log" -- -o --noprepare
ofcfg=src/omarchy-nvidia-sdks/nvidia-optical-flow/configure.sh
check "makepkg -o --noprepare fetches configure.sh where the header says" test -x "$ofc/$ofcfg"
check "the header's example names it with --conf selection.conf" \
    grep -qF "#   $ofcfg --conf selection.conf --src ~/Downloads/optical_flow_sdk_5.0.7.zip --write" "$ofc/PKGBUILD"
ofmk "$tmp/of/nosum.log" NVIDIA_OF_SRC="$ofzip" -- -f -d
check "a zip without a recorded checksum stops the build" test "$status" -ne 0
advice=$(sed -n 's/.*no checksum is recorded for .* Run: \(.*\) (or build with NVIDIA_OF_SHA256=.*/\1/p' "$tmp/of/nosum.log")
check "the message names configure.sh with the clone's selection.conf" \
    test "$advice" = "$ofc/$ofcfg --conf $ofc/selection.conf --src $ofzip --write"
check "it names the checksum for the environment instead" \
    grep -qF "NVIDIA_OF_SHA256=$(sha256sum "$ofzip" | cut -d' ' -f1) in the environment" "$tmp/of/nosum.log"
# The advice, run as printed (from another directory), then the build.
read -r -a advice_words <<<"$advice"
(cd / && "${advice_words[@]}") >"$tmp/of/configure.log" 2>&1 || true
check "running it writes the selection.conf next to the PKGBUILD" \
    grep -qx "SHA256=$(sha256sum "$ofzip" | cut -d' ' -f1)" "$ofc/selection.conf"
check "and nothing next to configure.sh" test ! -e "$ofc/src/omarchy-nvidia-sdks/nvidia-optical-flow/selection.conf"
check "the header's relative form reads the same file" \
    grep -qxF "   NVIDIA_OF_SRC=$ofzip" <<<"$(cd "$ofc" && "$ofcfg" --conf selection.conf --show)"
ofmk "$tmp/of/build.log" -- -f -d
ofpkgs=("$tmp"/of/pkgdest/nvidia-optical-flow-sdk-local-*.pkg.tar)
if ((status == 0)) && [[ -f ${ofpkgs[0]} ]]; then
    ok "then makepkg builds it: ${ofpkgs[0]##*/}"
    check "from the clone's selection.conf" grep -qF "NVIDIA_OF_SRC=$ofzip (from selection.conf)" "$tmp/of/build.log"
    check "the headers are packaged" grep -qxF opt/nvidia/optical-flow/include/nvOpticalFlowCuda.h <<<"$(bsdtar -tf "${ofpkgs[0]}")"
else
    fail "then makepkg builds it (status $status)"
    cat "$tmp/of/build.log"
fi

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
