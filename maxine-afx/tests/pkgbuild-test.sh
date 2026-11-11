#!/usr/bin/env bash
# Builds maxine-afx/PKGBUILD end to end against a FAKE SDK (tiny text files
# with the SDK's names, a version header in the SDK's format, tarballs and
# .md5 sidecars made here) and checks the package with bsdtar: the
# environment file, nothing under /etc, the shim, the licences, the models
# and their short-name links. The first build reads an NGC download from the
# environment; the second a tree from selection.conf, the third with an
# environment variable overriding the file; a hostile selection.conf is
# never executed and does not change `makepkg --printsrcinfo`. Everything
# happens under mktemp: the recipe files are copied there and makepkg's
# BUILDDIR, PKGDEST, SRCDEST and LOGDEST point there, so this working tree
# gets no src/, pkg/ or package. Needs makepkg, fakeroot, bsdtar and a C
# compiler (the shim); no GPU, no network, no NVIDIA download.
# Usage: maxine-afx/tests/pkgbuild-test.sh. Exits non-zero on any failure,
# 77 when a needed tool is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)

for tool in makepkg fakeroot bsdtar make cc md5sum; do
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
so_links() { # so_links <dir> <stem>
    fake "$1/$2.so.3.0.0"
    ln -s "$2.so.3.0.0" "$1/$2.so.3"
    ln -s "$2.so.3" "$1/$2.so"
}
core_files() { # core_files <root>
    so_links "$1/nvafx/lib" libnv_audiofx
    fake "$1/nvafx/include/nvAudioEffects.h" "$1/external/cuda/lib/libcudart.so.12" \
        "$1/licenses/NVIDIA Software License Agreement.pdf" "$1/external/ThirdPartyLicenses.txt" \
        "$1/features/README.md"
    printf '#define NVAUDIOEFFECTS_%s_VERSION %s\n' MAJOR 3 MINOR 0 PATCH 0 BUILD 12 >"$1/version.h"
}
feature_files() { # feature_files <dir> <feature>
    fake "$1/include/$2.h" "$1/licenses/NVIDIA Models Community License.pdf"
    so_links "$1/lib" "libnv_audiofx_$2"
}
add_models() { # add_models <dir> <feature> <rate> <sm> <file>...
    local dir=$1/afx_${2}_v3.0.0-${3}-sm$4 f
    shift 4
    for f in "$@"; do
        fake "$dir/$f"
        md5sum <"$dir/$f" | head -c 32 >"$dir/$f.md5"
    done
}

# The fake NGC download: core, denoiser (48k sm_120 and sm_89), studio voice
# (48k sm_120).
dl=$tmp/dl
stage=$tmp/stage
core_files "$stage/core/Audio_Effects_SDK"
mkdir -p "$dl/maxine_linux_audio_effects_sdk_v3.0.0"
tar -czf "$dl/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" \
    -C "$stage/core" Audio_Effects_SDK
for f in denoiser studio_voice; do
    feature_files "$stage/$f" "$f"
    mkdir -p "$dl/afx_${f}_v3.0.0-lib"
    tar -czf "$dl/afx_${f}_v3.0.0-lib/feature_libs.tar.gz" -C "$stage/$f" include lib licenses
done
add_models "$dl" denoiser 48k 120 denoiser_48k_10752.trtpkg
add_models "$dl" denoiser 48k 89 denoiser_48k_10752.trtpkg
add_models "$dl" studio_voice 48k 120 studio_voice_high_quality_48k_1.trtpkg
# The fake SDK tree: denoiser and dereverb, models for sm_120 and sm_86.
sdk=$tmp/sdk/Audio_Effects_SDK
core_files "$sdk"
feature_files "$sdk/features/denoiser" denoiser
feature_files "$sdk/features/dereverb" dereverb
fake "$sdk/features/denoiser/models/sm_120/denoiser_48k_10752.trtpkg" \
    "$sdk/features/denoiser/models/sm_86/denoiser_48k_10752.trtpkg" \
    "$sdk/features/dereverb/models/sm_120/dereverb_16k_10752.trtpkg" \
    "$sdk/features/dereverb/models/sm_86/dereverb_16k_10752.trtpkg"

# The recipe, copied: what the PKGBUILD reads from the repository.
repo=$tmp/repo
mkdir -p "$repo/maxine-afx" "$repo/tools/maxine-probe" "$repo/docs"
cp "$top/maxine-afx/PKGBUILD" "$top/maxine-afx/assemble.sh" "$top/maxine-afx/selection.sh" "$repo/maxine-afx/"
cp -r "$top/tools/os-release-shim" "$repo/tools/"
cp "$top/tools/maxine-probe/fake-os-release" "$repo/tools/maxine-probe/"
cp "$top/docs/usage.md" "$repo/docs/"
cp "$top/LICENSE-MIT" "$top/LICENSE-APACHE" "$repo/"

# build <name> [VAR=value...]: makepkg -f in the copied recipe directory,
# with only the given MAXINE_AFX_* variables; the log in $log, the status in
# $status, the package (when there is exactly one) in $pkg.
log='' status=0 pkg=''
build() {
    local name=$1
    shift
    mkdir -p "$tmp/$name/build" "$tmp/$name/pkgdest" "$tmp/srcdest" "$tmp/logdest"
    log=$tmp/$name/makepkg.log status=0 pkg=''
    (
        cd "$repo/maxine-afx" &&
            env -u LD_PRELOAD -u MAXINE_OS_RELEASE -u MAXINE_OS_RELEASE_DEBUG \
                -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
                -u MAXINE_AFX_SRC -u MAXINE_AFX_ARCHS -u MAXINE_AFX_FEATURES \
                BUILDDIR="$tmp/$name/build" PKGDEST="$tmp/$name/pkgdest" SRCDEST="$tmp/srcdest" \
                LOGDEST="$tmp/logdest" PKGEXT=.pkg.tar "$@" \
                makepkg -f -d --nosign --noconfirm
    ) >"$log" 2>&1 || status=$?
    local -a pkgs=("$tmp/$name"/pkgdest/maxine-afx-sdk-local-*.pkg.tar)
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
env_file() { bsdtar -xOf "$pkg" usr/share/maxine-afx/maxine-afx.env | grep -v '^#'; }
srcinfo() { (cd "$repo/maxine-afx" && env -u MAXINE_AFX_SRC -u MAXINE_AFX_ARCHS -u MAXINE_AFX_FEATURES makepkg --printsrcinfo); }
srcinfo_before=$(srcinfo)
check "the metadata names the package, version and provides" \
    grep -qxF $'\tprovides = maxine-afx-sdk=3.0.0.12' <<<"$srcinfo_before"

R=/opt/nvidia/maxine/afx
r=${R#/}
lib=usr/share/licenses/maxine-afx-sdk-local

echo "== from an NGC download, by the environment"
build env MAXINE_AFX_SRC="$dl"
built "makepkg -f -d builds the package from the environment"
check "prepare() prints where each value came from" logged "MAXINE_AFX_SRC=$dl (from environment)"
check "the architectures default to sm_120" logged "MAXINE_AFX_ARCHS=sm_120 (from default)"
check "nothing was written into the copied recipe directory" \
    test -z "$(find "$repo/maxine-afx" -mindepth 1 -maxdepth 1 \( -name src -o -name pkg -o -name '*.pkg.tar*' \) -print -quit)"
listing=$(bsdtar -tf "$pkg")
has() { grep -qxF -- "$1" <<<"$listing"; }
want="MAXINE_AFX_ROOT=$R
MAXINE_AFX_FEATURES_DIR=$R/features
MAXINE_AFX_LIBRARY_PATH=$R/nvafx/lib:$R/features/denoiser/lib:$R/features/studio_voice/lib:$R/external/cuda/lib
LD_LIBRARY_PATH=$R/nvafx/lib:$R/features/denoiser/lib:$R/features/studio_voice/lib:$R/external/cuda/lib
MAXINE_AFX_OS_RELEASE_SHIM=/usr/lib/maxine-afx/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-afx/fake-os-release
MAXINE_AFX_FEATURES=denoiser,studio_voice
MAXINE_AFX_ARCHS=sm_120
MAXINE_AFX_RATES=48k"
got=$(env_file)
if [[ $got == "$want" ]]; then
    ok "the environment file has exactly the expected keys and values"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
check "the environment file does not set LD_PRELOAD" not grep -q '^LD_PRELOAD=' <<<"$got"
check "nothing under /etc" test -z "$(grep -E '^etc(/|$)' <<<"$listing" || true)"
check "the shim is packaged" has usr/lib/maxine-afx/os-release-shim.so
check "the shim is an ELF library" \
    test "$(bsdtar -xOf "$pkg" usr/lib/maxine-afx/os-release-shim.so | head -c 4 | od -An -tx1 | tr -d ' \n')" = 7f454c46
check "the replacement os-release is packaged" has usr/lib/maxine-afx/fake-os-release
check "the usage document is packaged" has usr/share/doc/maxine-afx-sdk-local/usage.md
check "the core library is packaged" has "$r/nvafx/lib/libnv_audiofx.so.3.0.0"
check "the version header is packaged" has "$r/version.h"
check "a feature library is packaged" has "$r/features/studio_voice/lib/libnv_audiofx_studio_voice.so.3.0.0"
check "the sm_120 model is in features/<f>/models/sm_120" has "$r/features/denoiser/models/sm_120/denoiser_48k_10752.trtpkg"
check "the sm_89 model is not packaged" not has "$r/features/denoiser/models/sm_89/denoiser_48k_10752.trtpkg"
check "no .md5 sidecar is packaged" test -z "$(grep -F '.md5' <<<"$listing" || true)"
verbose=$(bsdtar -tvf "$pkg")
link_to() { grep -qF -- "$1 -> $2" <<<"$verbose"; } # link_to <path> <target>
check "the short-name model link is packaged" \
    link_to "$r/features/denoiser/models/sm_120/denoiser_48k.trtpkg" denoiser_48k_10752.trtpkg
check "LICENSE-MIT is packaged" has "$lib/LICENSE-MIT"
check "the SDK licence is linked" \
    link_to "$lib/NVIDIA Software License Agreement.pdf" "$R/licenses/NVIDIA Software License Agreement.pdf"
check "the third-party licences are linked" link_to "$lib/ThirdPartyLicenses.txt" "$R/external/ThirdPartyLicenses.txt"
check "the models' licence is linked from the first feature" \
    link_to "$lib/NVIDIA Models Community License.pdf" "$R/features/denoiser/licenses/NVIDIA Models Community License.pdf"
check "the build summary counted the checksums" logged "checksums 2 model file(s) verified"

echo "== from an SDK tree, by selection.conf"
printf '# test selection\nMAXINE_AFX_SRC=%s\nMAXINE_AFX_ARCHS=sm_86\nMAXINE_AFX_FEATURES=dereverb\n' \
    "$tmp/sdk" >"$repo/maxine-afx/selection.conf"
check "selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build conf
built "makepkg -f -d builds from selection.conf alone"
check "the source came from selection.conf" logged "MAXINE_AFX_SRC=$tmp/sdk (from selection.conf)"
check "the build summary lists the feature left out" logged "denoiser (present, not selected)"
listing=$(bsdtar -tf "$pkg")
check "the selected sm_86 model is packaged" has "$r/features/dereverb/models/sm_86/dereverb_16k_10752.trtpkg"
check "the sm_120 model is pruned" not has "$r/features/dereverb/models/sm_120/dereverb_16k_10752.trtpkg"
check "the feature left out is not packaged" test -z "$(grep -F "$r/features/denoiser" <<<"$listing" || true)"
check "the environment file lists the packaged feature only" \
    grep -qx "LD_LIBRARY_PATH=$R/nvafx/lib:$R/features/dereverb/lib:$R/external/cuda/lib" <<<"$(env_file)"
check "the environment file lists sm_86 and 16k" \
    test "$(env_file | grep -E '^MAXINE_AFX_(ARCHS|RATES)=')" = $'MAXINE_AFX_ARCHS=sm_86\nMAXINE_AFX_RATES=16k'

build override MAXINE_AFX_ARCHS=sm_120
built "makepkg -f -d with an environment variable over selection.conf"
check "the architectures came from the environment" logged "MAXINE_AFX_ARCHS=sm_120 (from environment)"
check "the environment file lists sm_120" grep -qx "MAXINE_AFX_ARCHS=sm_120" <<<"$(env_file)"

pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile lines are literal
printf 'MAXINE_AFX_SRC=$(touch %s)\nMAXINE_AFX_ARCHS=`touch %s`\n' "$pwned" "$pwned" >"$repo/maxine-afx/selection.conf"
check "a hostile selection.conf does not change makepkg --printsrcinfo" test "$(srcinfo)" = "$srcinfo_before"
build hostile
check "a hostile selection.conf stops the build" test "$status" -ne 0
check "it names the line" logged "selection.conf:1: the value of MAXINE_AFX_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
check "no package was built from it" test -z "$pkg"
rm -f "$repo/maxine-afx/selection.conf"

build relative MAXINE_AFX_SRC=sdk
check "a relative MAXINE_AFX_SRC from the environment stops the build" test "$status" -ne 0
check "it says the path must be absolute" logged "environment: MAXINE_AFX_SRC must be an absolute path"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
