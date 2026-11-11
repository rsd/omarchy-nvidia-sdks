#!/usr/bin/env bash
# Tests for maxine-ar/assemble.sh. The fixtures are FAKE: tiny text files
# with the SDK's file names, and tarballs built from them here, all under
# mktemp. Nothing from NVIDIA is read or needed.
# Usage: maxine-ar/tests/assemble-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
assemble=$here/../assemble.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }

fake() { # fake <file>...: creates tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}

version_header() { # version_header <file> <a.b.c.d>
    local IFS=.
    local -a v
    read -r -a v <<<"$2"
    mkdir -p "$(dirname "$1")"
    {
        echo "#define NVIDIA_AR_SDK_VERSION_MAJOR ${v[0]}"
        echo "#define NVIDIA_AR_SDK_VERSION_MINOR ${v[1]}"
        echo "#define NVIDIA_AR_SDK_VERSION_RELEASE ${v[2]}"
        echo "#define NVIDIA_AR_SDK_VERSION_BUILD ${v[3]}"
    } >"$1"
}

core_files() { # core_files <root> <version>: the SDK core without features or models
    fake "$1/lib/libnvARPose.so" "$1/lib/libNVCVImage.so" "$1/include/nvAR.h" \
        "$1/external/cuda/lib/libcudart.so.12" "$1/external/tensorrt/lib/libnvinfer.so.10" \
        "$1/share/NVIDIA-Software-License-Agreement.pdf" "$1/share/external/ThirdPartyLicenses.txt"
    version_header "$1/share/arsdk_version.h" "$2"
}

# make_tree <root> [version]: an assembled tree with landmark detection and
# face box detection, models for sm_120 and sm_89, and a stale engine cache.
make_tree() {
    local root=$1 version=${2:-1.2.0.0}
    core_files "$root" "$version"
    fake "$root/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so" \
        "$root/features/nvarfaceboxdetection/lib/libnvARFaceBoxDetection.so" \
        "$root/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg" \
        "$root/lib/models/faceland_fp16_multiprofile_126_mode0_120.engine.trtpkg" \
        "$root/lib/models/faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg" \
        "$root/lib/models/cache/stale.bin"
    : >"$root/features/nvarlandmarkdetection/nvARLandmarkDetection_dependencies.txt"
}

# add_feature <dir> <feature> <library> [version]: a feature's lib download
add_feature() {
    local dir=$1 f=$2 lib=$3 fver=${4:-1.2.0.0} stage
    stage=$(mktemp -d "$tmp/stage.XXXXXX")
    fake "$stage/$f/lib/$lib"
    mkdir -p "$dir/${f}_v${fver}_lib_linux"
    tar -czf "$dir/${f}_v${fver}_lib_linux/${fver}_lib_linux.tar.gz" -C "$stage" "$f"
}

# add_models <dir> <feature> <version> <sm> <file>...: a models download
add_models() {
    local dir=$1/${2}_v${3}_models_linux_sm$4 f
    shift 4
    for f in "$@"; do fake "$dir/$f"; done
}

# make_core <dir> <bare|subdir>: the core download alone
make_core() {
    local dir=$1 where=$2 stage core=$1
    stage=$(mktemp -d "$tmp/stage.XXXXXX")
    core_files "$stage/ARSDK" 1.2.0.0
    fake "$stage/ARSDK/features/README.md"
    [[ $where == subdir ]] && core=$dir/ar_sdk_core_v1.2.0.0_linux
    mkdir -p "$core"
    tar -czf "$core/ARSDK_linux_1.2.0.0.tgz" -C "$stage" ARSDK
}

# make_download <dir> <bare|subdir> [feature version]: an NGC download of the
# core, landmark detection (models for sm_120 and sm_89) and face box
# detection (no models in this fixture).
make_download() {
    local dir=$1 where=$2 fver=${3:-1.2.0.0}
    make_core "$dir" "$where"
    add_feature "$dir" nvarlandmarkdetection libnvARLandmarkDetection.so "$fver"
    add_feature "$dir" nvarfaceboxdetection libnvARFaceBoxDetection.so "$fver"
    add_models "$dir" nvarlandmarkdetection "$fver" 120 faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg
    add_models "$dir" nvarlandmarkdetection "$fver" 89 faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg
}

listing() { (cd "$1" && find . -printf '%p %s %T@\n' | sort); }

new_dir() { mktemp -d "$tmp/case.XXXXXX"; }

# expect_pass <description> <assemble args...>; the output is left in $out.
out=''
expect_pass() {
    local desc=$1
    shift
    if out=$("$assemble" "$@" 2>&1); then ok "$desc"; else fail "$desc: $out"; fi
}

# expect_fail <description> <message fragment> <assemble args...>
expect_fail() {
    local desc=$1 fragment=$2 status=0
    shift 2
    out=$("$assemble" "$@" 2>&1) || status=$?
    if ((status == 0)); then
        fail "$desc: succeeded"
    elif ! grep -qF -- "$fragment" <<<"$out"; then
        fail "$desc: message lacks '$fragment': $out"
    else
        ok "$desc"
    fi
}

# check <description> <command...>
check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}
says() { grep -qF -- "$1" <<<"$out"; } # says <fragment>: the last output has it
not() { ! "$@"; }

has_core() {
    [[ -f $1/lib/libnvARPose.so && -f $1/share/arsdk_version.h &&
        -f $1/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so &&
        -f $1/features/nvarfaceboxdetection/lib/libnvARFaceBoxDetection.so ]]
}
models() { (cd "$1/lib/models" && find . -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' '); }
state_is() { # state_is <file> <features> <archs>
    [[ $(cat "$1") == "MAXINE_AR_FEATURES=$2"$'\n'"MAXINE_AR_ARCHS=$3" ]]
}

gs120="faceland_fp16_multiprofile_126_mode0_120.engine.trtpkg faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
gs89="faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg"
two=nvarfaceboxdetection,nvarlandmarkdetection

echo "== tree mode"
d=$(new_dir)
make_tree "$d/src"
before=$(listing "$d/src")
expect_pass "tree at the source root" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "the tree is copied" has_core "$d/out"
check "the default sm_120 keeps only the sm_120 models (126 and 68 are no SM) and drops the cache" \
    test "$(models "$d/out")" = "$gs120 "
check "the source tree is untouched" test "$before" = "$(listing "$d/src")"
check "the state file lists the features and sm_120" state_is "$d/state" "$two" sm_120
check "the summary gives the sm_120 model count and size" \
    grep -qE '^  models    sm_120  2 files, [0-9.]+[KMG]?$' <<<"$out"
check "the summary lists the sorted features" says "features  nvarfaceboxdetection nvarlandmarkdetection"
check "the summary prints no file contents" not says "fake faceland"
check "an empty dependencies.txt gives no warning" not says WARNING

d=$(new_dir)
make_tree "$d/src/ARSDK"
expect_pass "tree at <src>/ARSDK" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs sm_120
check "the ARSDK tree is copied into dest itself" has_core "$d/out"

d=$(new_dir)
make_tree "$d/src"
for spelling in sm_120 sm120 120; do
    expect_pass "--archs $spelling" --src "$d/src" --dest "$d/$spelling" --version 1.2.0.0 \
        --archs "$spelling" --state "$d/$spelling.state"
done
check "sm_120, sm120 and 120 keep the same models" \
    test "$(models "$d/sm_120")" = "$(models "$d/sm120")" -a "$(models "$d/sm120")" = "$(models "$d/120")"
check "sm_120, sm120 and 120 give the same state" \
    test "$(cat "$d/sm_120.state")" = "$(cat "$d/sm120.state")" -a "$(cat "$d/sm120.state")" = "$(cat "$d/120.state")"

d=$(new_dir)
make_tree "$d/src"
expect_pass "--archs \"120,sm_89\"" --src "$d/src" --dest "$d/out" --version 1.2.0.0 \
    --archs "120,sm_89" --state "$d/state"
check "both architectures are kept" test "$(models "$d/out")" = "$gs120 $gs89 "
check "the state lists sm_89 and sm_120" state_is "$d/state" "$two" sm_89,sm_120
check "the summary gives one line per architecture" \
    test "$(grep -cE '^  models    sm_(89|120) ' <<<"$out")" = 2

d=$(new_dir)
make_tree "$d/src"
fake "$d/src/lib/models/faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg" "$d/src/lib/models/custom_models_README.md"
expect_pass "--archs all in tree mode" --src "$d/src" --dest "$d/out" --version 1.2.0.0 \
    --archs all --state "$d/state"
check "all keeps every architecture" \
    test "$(models "$d/out")" = "custom_models_README.md $gs120 faceland_fp16_multiprofile_68_mode0_86.engine.trtpkg $gs89 "
check "all lists the architectures found" state_is "$d/state" "$two" sm_86,sm_89,sm_120
check "the summary says all found" says "archs     sm_86 sm_89 sm_120 (all found)"

d=$(new_dir)
make_tree "$d/src"
fake "$d/src/lib/models/custom_models_README.md" "$d/src/lib/models/face_model3.nvf"
expect_pass "model files without an SM number" --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "they are kept" test "$(models "$d/out")" = "custom_models_README.md face_model3.nvf $gs120 "
check "they are listed in a note" says "note: kept 2 model file(s) whose name carries no GPU architecture: custom_models_README.md face_model3.nvf"

d=$(new_dir)
make_tree "$d/src"
expect_fail "'all' with another entry fails" "'all' must be the only --archs entry" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs "all sm_120"
expect_fail "an architecture without models fails" "no models for sm_86 in lib/models; the source has models for sm_89 sm_120" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs "sm_120 sm_86"
expect_fail "the missing architecture names the NGC tag" "nvidia/maxine/<feature>:1.2.0.0_models_linux_sm86" \
    --src "$d/src" --dest "$d/out2" --version 1.2.0.0 --archs 86

d=$(new_dir)
make_tree "$d/src"
fake "$d/src/features/nvarlipsync/lib/libnvARLipSync.so"
expect_pass "a third feature in the tree" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "it is packaged without being named" state_is "$d/state" "$two,nvarlipsync" sm_120

d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/src/features/nvarbroken/include"
expect_pass "a features/ directory without lib/*.so" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "it is noted" says "features/nvarbroken has no lib/*.so"
check "it is not packaged as a feature" state_is "$d/state" "$two" sm_120

d=$(new_dir)
make_tree "$d/src"
printf 'nvarbodydetection nvarfaceboxdetection\nlibfoo.so\n' >"$d/src/features/nvarlandmarkdetection/nvARLandmarkDetection_dependencies.txt"
expect_pass "a dependencies.txt naming an absent feature still passes" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "it warns with the absent feature only" \
    says "WARNING: feature nvarlandmarkdetection lists dependencies that are not present: nvarbodydetection (features/nvarlandmarkdetection/nvARLandmarkDetection_dependencies.txt)"

d=$(new_dir)
make_tree "$d/src"
expect_pass "--features listing every present feature" --src "$d/src" --dest "$d/out" --version 1.2.0.0 \
    --features "nvarlandmarkdetection,nvarfaceboxdetection" --state "$d/state"
check "both are packaged" state_is "$d/state" "$two" sm_120
check "nothing is left out" not says "left out"
expect_pass "--features all" --src "$d/src" --dest "$d/all" --version 1.2.0.0 --features all --state "$d/all.state"
check "all packages every present feature" state_is "$d/all.state" "$two" sm_120
expect_fail "--features of an absent feature fails, naming it" "not present in the SDK tree $d/src: nvarbodydetection" \
    --src "$d/src" --dest "$d/out2" --version 1.2.0.0 --features "nvarlandmarkdetection nvarbodydetection"
check "the message names the NGC tag" says "nvidia/maxine/nvarbodydetection:1.2.0.0_lib_linux"
check "nothing was copied for the failed selection" test ! -e "$d/out2"
expect_fail "'all' with a feature fails" "'all' must be the only --features entry" \
    --src "$d/src" --dest "$d/out3" --version 1.2.0.0 --features "all nvarlandmarkdetection"
expect_fail "an empty --features fails" "--features is empty" \
    --src "$d/src" --dest "$d/out3" --version 1.2.0.0 --features " , "
# shellcheck disable=SC2016 # a literal $ in a feature name
expect_fail "an invalid feature name fails" "invalid feature name 'nvar\$x'" \
    --src "$d/src" --dest "$d/out3" --version 1.2.0.0 --features 'nvar$x'
expect_fail "an unknown option is a usage error" "usage:" \
    --src "$d/src" --dest "$d/out3" --version 1.2.0.0 --bogus nvarlandmarkdetection

d=$(new_dir)
make_tree "$d/src"
fake "$d/src/features/nvarlipsync/lib/libnvARLipSync.so"
before=$(listing "$d/src")
expect_pass "--features selecting one of three in a tree" --src "$d/src" --dest "$d/out" --version 1.2.0.0 \
    --features nvarlandmarkdetection --state "$d/state"
check "only it is in the state" state_is "$d/state" nvarlandmarkdetection sm_120
check "the features left out are removed from the copy" \
    test ! -e "$d/out/features/nvarfaceboxdetection" -a ! -e "$d/out/features/nvarlipsync"
check "the selected feature is copied" test -f "$d/out/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so"
check "the non-feature files of features/ stay" test -d "$d/out/features"
check "the summary lists them as present, not selected" \
    says "left out  nvarfaceboxdetection nvarlipsync (present, not selected)"
check "a note says the tree's models are kept" says "lib/models keeps those of the features left out"
check "the source tree is untouched by the selection" test "$before" = "$(listing "$d/src")"
printf 'nvarfaceboxdetection nvarbodydetection\n' >"$d/src/features/nvarlandmarkdetection/nvARLandmarkDetection_dependencies.txt"
expect_pass "a dependency left out of the selection" --src "$d/src" --dest "$d/dep" --version 1.2.0.0 \
    --features nvarlandmarkdetection
check "it warns that the dependency is present but not selected" \
    says "lists dependencies that are present but not selected: nvarfaceboxdetection"
check "and that the other one is not present" says "lists dependencies that are not present: nvarbodydetection"

d=$(new_dir)
core_files "$d/src" 1.2.0.0
fake "$d/src/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
expect_fail "a tree without any feature fails" "no feature in the assembled tree" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src" 1.2.0.0
expect_fail "a version mismatch fails, naming both versions" "the SDK is 1.2.0.0 (share/arsdk_version.h), --version is 1.4.0.0" \
    --src "$d/src" --dest "$d/out" --version 1.4.0.0

d=$(new_dir)
make_tree "$d/src"
fake "$d/out/leftover"
expect_fail "a non-empty dest fails" "--dest must not exist or be empty" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
mkdir "$d/empty"
expect_pass "an existing empty dest is accepted" --src "$d/src" --dest "$d/empty" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src"
expect_fail "a bad architecture value fails" "invalid architecture '8.9'" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs 8.9
expect_fail "a one-digit architecture fails" "invalid architecture 'sm_7'" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs "120 sm_7"
expect_fail "an empty --archs fails" "--archs is empty" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs " , "
expect_fail "a malformed --version fails" "--version must look like 1.2.0.0" \
    --src "$d/src" --dest "$d/out" --version 1.2

d=$(new_dir)
mkdir -p "$d/src"
fake "$d/src/unrelated.txt"
expect_fail "an empty source names what was looked for" "ARSDK_linux_1.2.0.0.tgz" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
expect_fail "an empty source points to docs/download.md" "docs/download.md" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src"
expect_fail "a dest inside the source tree fails" "--dest must not be inside the SDK tree" \
    --src "$d/src" --dest "$d/src/out" --version 1.2.0.0
check "the failed run created nothing in the source tree" test ! -e "$d/src/out"

# A trailing newline: $(realpath ...) would drop it and name $d/src.
d=$(new_dir)
make_tree "$d/src"
mkdir "$d/src"$'\n'
expect_fail "a source path with a newline fails" "contains a newline, which is not supported" \
    --src "$d/src"$'\n' --dest "$d/out" --version 1.2.0.0
check "it created no dest" test ! -e "$d/out"

echo "== download mode"
d=$(new_dir)
make_download "$d/src" subdir
before=$(listing "$d/src")
expect_pass "core tgz in ar_sdk_core_v1.2.0.0_linux/" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "the core and both features are assembled" has_core "$d/out"
check "the sm_120 models are copied" test "$(models "$d/out")" = "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg "
check "the state lists the features and sm_120" state_is "$d/state" "$two" sm_120
check "the summary gives the sm_120 model count and size" \
    grep -qE '^  models    sm_120  1 files, [0-9.]+[KMG]?$' <<<"$out"
check "the download is untouched" test "$before" = "$(listing "$d/src")"
check "no work directory is left beside dest" \
    test -z "$(find "$d" -maxdepth 1 -name '.assemble.*' -print -quit)"

d=$(new_dir)
make_download "$d/src" bare
expect_pass "a dest inside the download directory (makepkg's src/) works" \
    --src "$d/src" --dest "$d/src/src/arsdk" --version 1.2.0.0
check "the nested dest is assembled" has_core "$d/src/src/arsdk"

d=$(new_dir)
make_download "$d/src" bare
expect_pass "bare core tgz, --archs \"sm120 89\"" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs "sm120 89"
check "both architectures' models are copied" test "$(models "$d/out")" = \
    "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg "

d=$(new_dir)
make_download "$d/src" bare
add_feature "$d/src" nvarlipsync libnvARLipSync.so
add_models "$d/src" nvarlipsync 1.2.0.0 120 lipsync_fp16_120.engine.trtpkg
expect_pass "a third feature in the download" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "its library is assembled" test -f "$d/out/features/nvarlipsync/lib/libnvARLipSync.so"
check "it is packaged without being named" state_is "$d/state" "$two,nvarlipsync" sm_120
check "its models are copied" test "$(models "$d/out")" = "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg lipsync_fp16_120.engine.trtpkg "
check "the summary counts both features' models for sm_120" \
    grep -qE '^  models    sm_120  2 files, ' <<<"$out"

d=$(new_dir)
make_download "$d/src" bare
add_feature "$d/src" nvarlipsync libnvARLipSync.so
add_models "$d/src" nvarlipsync 1.2.0.0 89 lipsync_fp16_89.engine.trtpkg
expect_fail "a feature with sm_89 models but none for sm_120 fails" \
    "feature nvarlipsync has no models for sm_120: no nvarlipsync_v1.2.*_models_linux_sm120/" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs sm_120
check "the message names the NGC tag" says "nvidia/maxine/nvarlipsync:1.2.0.0_models_linux_sm120"
expect_pass "--archs all copies every models directory" --src "$d/src" --dest "$d/all" --version 1.2.0.0 \
    --archs all --state "$d/state"
check "all copies both features' models of every architecture" test "$(models "$d/all")" = \
    "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg lipsync_fp16_89.engine.trtpkg "
check "all lists the architectures found" state_is "$d/state" "$two,nvarlipsync" sm_89,sm_120

d=$(new_dir)
make_core "$d/src" bare
add_feature "$d/src" nvarfaceboxdetection libnvARFaceBoxDetection.so
expect_pass "a download without models passes" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "it warns that there are no models" says "WARNING: no models in the source"
check "the state lists the feature and no architecture" state_is "$d/state" nvarfaceboxdetection ""
check "the summary says no models" says "archs     none (no models)"
expect_fail "--features of an absent feature fails in download mode" "feature(s) not present in $d/src: nvarlandmarkdetection" \
    --src "$d/src" --dest "$d/out2" --version 1.2.0.0 --features nvarlandmarkdetection
check "the message gives the ngc command" \
    says "ngc registry model download-version \"nvidia/maxine/nvarlandmarkdetection:1.2.0.0_lib_linux\" --dest \"$d/src\""
check "nothing was assembled for the failed selection" test ! -e "$d/out2"

d=$(new_dir)
make_download "$d/src" bare
add_feature "$d/src" nvarlipsync libnvARLipSync.so
add_models "$d/src" nvarlipsync 1.2.0.0 86 lipsync_fp16_86.engine.trtpkg
expect_pass "--features selecting two of three in a download" --src "$d/src" --dest "$d/out" --version 1.2.0.0 \
    --features "nvarfaceboxdetection nvarlandmarkdetection" --state "$d/state"
check "the feature left out is not unpacked" test ! -e "$d/out/features/nvarlipsync"
check "its models are not copied" test "$(models "$d/out")" = "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg "
check "the state lists the selected features" state_is "$d/state" "$two" sm_120
check "the summary lists it as present, not selected" says "left out  nvarlipsync (present, not selected)"
expect_pass "--archs all counts the selected features' models only" --src "$d/src" --dest "$d/all" \
    --version 1.2.0.0 --archs all --features nvarlandmarkdetection --state "$d/all.state"
check "all gives the selected feature's architectures" state_is "$d/all.state" nvarlandmarkdetection sm_89,sm_120
expect_fail "a selected feature without models for the architecture still fails" \
    "feature nvarlipsync has no models for sm_120" \
    --src "$d/src" --dest "$d/vsr" --version 1.2.0.0 --features nvarlipsync

d=$(new_dir)
make_core "$d/src" subdir
expect_fail "a download without any feature fails" "no feature found in $d/src" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" bare 1.2.2.0
expect_pass "a feature of the same MAJOR.MINOR (1.2.2.0) is accepted" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" subdir 1.1.0.0
expect_fail "a feature MAJOR.MINOR mismatch fails" "does not match SDK version 1.2" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" subdir
add_feature "$d/src" nvarbodydetection libnvARBodyDetection.so 1.4.0.0
expect_fail "an extra feature of another MAJOR.MINOR fails, naming its directory" \
    "nvarbodydetection_v1.4.0.0_lib_linux does not match SDK version 1.2" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" subdir
rm -rf "$d/src/nvarlandmarkdetection_v1.2.0.0_lib_linux"
expect_fail "models without their feature's library fail" "nvarlandmarkdetection_v1.2.0.0_models_linux_sm120 has no library download" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" subdir
expect_fail "a missing model download fails, naming the tag" "nvidia/maxine/nvarlandmarkdetection:1.2.0.0_models_linux_sm86" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs 86

echo "== AR SDK specifics"
# The core tarball as NVIDIA ships it: lib/models holds the face model and
# the model list, none carrying an architecture; the Triton client tarball
# and its README sit next to it in the NGC resource directory.
d=$(new_dir)
stage=$(mktemp -d "$tmp/stage.XXXXXX")
core_files "$stage/ARSDK" 1.2.0.0
fake "$stage/ARSDK/lib/models/face_model3.nvf" "$stage/ARSDK/lib/models/models.json"
mkdir -p "$d/src/ar_sdk_core_v1.2.0.0_linux"
tar -czf "$d/src/ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz" -C "$stage" ARSDK
fake "$d/src/ar_sdk_core_v1.2.0.0_linux/ARSDK_triton_1.2.0.0.tgz" \
    "$d/src/ar_sdk_core_v1.2.0.0_linux/README_AR_SDK_Triton.md"
add_feature "$d/src" nvarlandmarkdetection libnvARLandmarkDetection.so
add_models "$d/src" nvarlandmarkdetection 1.2.0.0 120 faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg
expect_pass "the core's own lib/models files" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --state "$d/state"
check "they are kept next to the feature's models" test "$(models "$d/out")" = \
    "face_model3.nvf faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg models.json "
check "the summary counts the sm_120 models of the feature only" \
    grep -qE '^  models    sm_120  1 files, ' <<<"$out"
check "the summary counts every file in lib/models" says "models    total   3 files"
check "the Triton client tarball is not unpacked" \
    test -z "$(find "$d/out" -iname '*triton*' -print -quit)"

# NVIDIA's dependency files: library names, semicolon-separated, no newline.
d=$(new_dir)
make_tree "$d/src"
printf 'nvARFaceBoxDetection;nvARBodyDetection;' \
    >"$d/src/features/nvarlandmarkdetection/nvARLandmarkDetection_dependencies.txt"
expect_pass "a dependencies.txt in NVIDIA's format" --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "a present dependency gives no warning" not says "not present: nvarfaceboxdetection"
check "an absent one is named by its feature name" \
    says "WARNING: feature nvarlandmarkdetection lists dependencies that are not present: nvarbodydetection"
expect_pass "a dependency in NVIDIA's format left out" --src "$d/src" --dest "$d/one" --version 1.2.0.0 \
    --features nvarlandmarkdetection
check "it warns that it is present but not selected" \
    says "lists dependencies that are present but not selected: nvarfaceboxdetection"

echo "== symbolic links"
# Dangling links shaped like the Video Effects SDK's: cuDNN headers into Debian's
# /etc/alternatives (names that exist on no machine), and one relative.
alt=/etc/alternatives/omarchy-nvidia-sdks-test-libcudnn
add_sdk_links() { # add_sdk_links <root>
    local i
    mkdir -p "$1/external/cuda/include"
    for i in 1 2 3 4 5 6 7; do ln -s "$alt$i" "$1/external/cuda/include/cudnn$i.h"; done
    ln -s libcudnn9.so.9 "$1/external/cuda/lib/libcudnn.so"
    ln -s libcudart.so.12 "$1/external/cuda/lib/libcudart.so"
}
d=$(new_dir)
make_tree "$d/src"
add_sdk_links "$d/src"
expect_pass "dangling links as the SDK ships them are accepted" --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "the summary notes them in one line" \
    says "links     8 dangling symbolic links kept as shipped by NVIDIA (7 into /etc/alternatives)"
check "they are kept as links, unchanged" \
    test "$(readlink "$d/out/external/cuda/include/cudnn1.h")" = "${alt}1" -a \
    "$(readlink "$d/out/external/cuda/lib/libcudnn.so")" = libcudnn9.so.9
check "a link to a file inside the tree is kept" test "$(readlink "$d/out/external/cuda/lib/libcudart.so")" = libcudart.so.12
d=$(new_dir)
make_tree "$d/src"
expect_pass "a tree without links" --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "it prints no links line" not says "links  "

d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/home/models/cache"
fake "$d/home/models/cache/user-engine.bin" "$d/home/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
rm -rf "$d/src/lib/models"
ln -s "$d/home/models" "$d/src/lib/models"
expect_fail "a symlinked lib/models directory is refused" "lib/models in $d/src is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "the user's cache behind the link is untouched" test -f "$d/home/models/cache/user-engine.bin"
check "nothing was copied" test ! -e "$d/out"

d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/elsewhere"
ln -s "$d/elsewhere" "$d/src/features/nvarlandmarkdetection/data"
expect_fail "a symlinked directory anywhere in the tree is refused" "features/nvarlandmarkdetection/data in $d/src is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src"
fake "$d/home/secret.txt"
ln -s "$d/home/secret.txt" "$d/src/share/notes.txt"
expect_fail "a link to an existing file outside the tree is refused" "share/notes.txt in $d/src is a symbolic link to $d/home/secret.txt, outside the tree" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src"
ln -s ../../../nowhere "$d/src/share/up"
expect_fail "a dangling relative link leaving the tree is refused" "share/up in $d/src is a dangling symbolic link leaving the tree" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/src/lib/models/cache.real"
rm -rf "$d/src/lib/models/cache"
ln -s cache.real "$d/src/lib/models/cache"
expect_fail "a symlinked cache directory inside the tree is refused too" "lib/models/cache in $d/src is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
stage=$(mktemp -d "$tmp/stage.XXXXXX")
core_files "$stage/ARSDK" 1.2.0.0
add_sdk_links "$stage/ARSDK"
mkdir -p "$d/src"
tar -czf "$d/src/ARSDK_linux_1.2.0.0.tgz" -C "$stage" ARSDK
add_feature "$d/src" nvarfaceboxdetection libnvARFaceBoxDetection.so
expect_pass "download mode keeps the core's dangling links" --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "download mode notes them" \
    says "links     8 dangling symbolic links kept as shipped by NVIDIA (7 into /etc/alternatives)"
check "download mode keeps them as links" test -L "$d/out/external/cuda/include/cudnn7.h"

d=$(new_dir)
stage=$(mktemp -d "$tmp/stage.XXXXXX")
core_files "$stage/ARSDK" 1.2.0.0
ln -s /tmp "$stage/ARSDK/share/tmp"
mkdir -p "$d/src"
tar -czf "$d/src/ARSDK_linux_1.2.0.0.tgz" -C "$stage" ARSDK
add_feature "$d/src" nvarfaceboxdetection libnvARFaceBoxDetection.so
expect_fail "download mode refuses a directory link from a tarball" "share/tmp in $d/out is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

echo "== source layout and models directories"
d=$(new_dir)
make_tree "$d/src/ARSDK"
make_download "$d/src" subdir
expect_fail "a tree next to NGC downloads is refused" "holds both an SDK tree ($d/src/ARSDK) and NGC downloads" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "the message says what to do" says "Move one of them away, or point MAXINE_AR_SRC (--src) at the one you mean"
d=$(new_dir)
make_tree "$d/src/ARSDK"
make_core "$d/src" bare
expect_fail "a tree next to a bare core tarball is refused" "NGC downloads (ARSDK_linux_1.2.0.0.tgz)" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" bare
rm "$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120"/*
expect_fail "an empty models directory is refused" "models directory nvarlandmarkdetection_v1.2.0.0_models_linux_sm120 is empty" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "it names the NGC tag" says "nvidia/maxine/nvarlandmarkdetection:1.2.0.0_models_linux_sm120"
expect_pass "an empty models directory of an unselected architecture is not used" \
    --src "$d/src" --dest "$d/out89" --version 1.2.0.0 --archs sm_89

d=$(new_dir)
make_download "$d/src" bare
mkdir "$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120/sub"
mv "$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120"/*.trtpkg "$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120/sub/"
expect_fail "models in a subdirectory are refused, saying so" \
    "models directory nvarlandmarkdetection_v1.2.0.0_models_linux_sm120 contains subdirectories; expected the model files directly inside" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "the message does not contradict itself" not says "no models for sm_120"

d=$(new_dir)
make_download "$d/src" bare
ln -s faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg "$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120/link.trtpkg"
expect_fail "a link in a models directory is refused" "holds link.trtpkg, which is not a regular file" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" bare
add_feature "$d/src" nvarlipsync libnvARLipSync.so
add_models "$d/src" nvarlipsync 1.2.0.0 120 faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg
expect_pass "an identical model file in two models directories is accepted" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0
check "it is copied once" test "$(models "$d/out")" = "faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg "
printf 'different\n' >"$d/src/nvarlipsync_v1.2.0.0_models_linux_sm120/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
expect_fail "a same-name model file with other contents is refused" \
    "model file faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg is in both $d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120 and $d/src/nvarlipsync_v1.2.0.0_models_linux_sm120 with different contents" \
    --src "$d/src" --dest "$d/out2" --version 1.2.0.0

d=$(new_dir)
make_download "$d/src" bare
add_models "$d/src" nvarlandmarkdetection 1.2.0.0 86 faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg
printf 'other arch\n' >"$d/src/nvarlandmarkdetection_v1.2.0.0_models_linux_sm86/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg"
expect_fail "a collision across architectures is refused" "with different contents" \
    --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs "120 86"

d=$(new_dir)
make_tree "$d/src"
expect_fail "a four-digit architecture fails" "invalid architecture 'sm_1200'" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs sm_1200
expect_fail "a leading zero fails" "invalid architecture '089'" --src "$d/src" --dest "$d/out" --version 1.2.0.0 --archs 089

echo "== --scan"
# scan <description> <assemble args...>: stdout only in $out, stderr in $err.
err=''
scan() {
    local desc=$1
    shift
    if out=$("$assemble" --scan "$@" 2>"$tmp/err"); then ok "$desc"; else fail "$desc: $(cat "$tmp/err")"; fi
    err=$(cat "$tmp/err")
}
only_machine_lines() { ! grep -vqE '^(layout|version|source|feature|archs|models_unknown)=' <<<"$out"; }

d=$(new_dir)
make_tree "$d/src/ARSDK"
fake "$d/src/ARSDK/lib/models/custom_models_README.md" "$d/src/ARSDK/features/README.md"
mkdir -p "$d/src/ARSDK/features/nvarbroken/include"
before=$(listing "$d/src")
scan "--scan of a tree" --src "$d/src" --version 1.2.0.0
want="layout=tree
version=1.2.0.0
source=$d/src/ARSDK
feature=nvarfaceboxdetection archs=?
feature=nvarlandmarkdetection archs=?
archs=sm_89,sm_120
models_unknown=1"
check "it prints exactly the machine-readable lines" test "$out" = "$want"
check "the source is untouched and nothing is written" test "$before" = "$(listing "$d/src")" -a \
    -z "$(find "$d" -mindepth 1 -maxdepth 1 ! -name src -print -quit)"
expect_fail "--scan with --dest is a usage error" "usage:" --scan --src "$d/src" --dest "$d/out" --version 1.2.0.0
expect_fail "--scan with --state is a usage error" "usage:" --scan --src "$d/src" --state "$d/st" --version 1.2.0.0
expect_fail "--scan without --version is a usage error" "usage:" --scan --src "$d/src"
expect_fail "--scan of a tree of another version fails" "the SDK is 1.2.0.0 (share/arsdk_version.h), --version is 1.4.0.0" \
    --scan --src "$d/src" --version 1.4.0.0

d=$(new_dir)
make_download "$d/src" subdir
add_feature "$d/src" nvarlipsync libnvARLipSync.so
add_models "$d/src" nvarlipsync 1.2.0.0 86 lipsync_fp16_86.engine.trtpkg
before=$(listing "$d/src")
scan "--scan of a download" --src "$d/src" --version 1.2.0.0
want="layout=download
version=1.2.0.0
source=$d/src/ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz
feature=nvarfaceboxdetection archs=-
feature=nvarlandmarkdetection archs=sm_89,sm_120
feature=nvarlipsync archs=sm_86
archs=sm_86,sm_89,sm_120
models_unknown=0"
check "it prints each feature with its architectures" test "$out" = "$want"
check "nothing is extracted or written" test "$before" = "$(listing "$d/src")" -a \
    -z "$(find "$d" -mindepth 1 -maxdepth 1 ! -name src -print -quit)"
rm "$d/src/nvarlipsync_v1.2.0.0_models_linux_sm86"/*
scan "--scan with an empty models directory" --src "$d/src" --version 1.2.0.0
check "it warns on stderr" grep -qF "models directory nvarlipsync_v1.2.0.0_models_linux_sm86 holds no model file" <<<"$err"
check "stdout keeps only machine-readable lines" only_machine_lines

d=$(new_dir)
make_core "$d/src" subdir
scan "--scan of a core without features" --src "$d/src" --version 1.2.0.0
check "it lists no feature and no architecture" test "$out" = "layout=download
version=1.2.0.0
source=$d/src/ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz
archs=-
models_unknown=0"

d=$(new_dir)
make_tree "$d/src/ARSDK"
make_core "$d/src" bare
expect_fail "--scan refuses a tree next to downloads" "holds both an SDK tree" --scan --src "$d/src" --version 1.2.0.0
d=$(new_dir)
make_download "$d/src" bare 1.1.0.0
expect_fail "--scan refuses a feature MAJOR.MINOR mismatch" "does not match SDK version 1.2" --scan --src "$d/src" --version 1.2.0.0
d=$(new_dir)
mkdir -p "$d/src"
expect_fail "--scan of a directory without an SDK fails" "no Maxine AR SDK found in $d/src" --scan --src "$d/src" --version 1.2.0.0
d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/elsewhere"
ln -s "$d/elsewhere" "$d/src/share/linked"
expect_fail "--scan refuses a directory link in a tree" "share/linked in $d/src is a symbolic link to a directory" \
    --scan --src "$d/src" --version 1.2.0.0

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
