#!/usr/bin/env bash
# Tests for maxine-afx/assemble.sh. The fixtures are FAKE: tiny text files
# with the SDK's file names, tarballs and .md5 sidecars built from them here,
# all under mktemp. Nothing from NVIDIA is read or needed.
# Usage: maxine-afx/tests/assemble-test.sh. Exits non-zero on any failure.
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
        echo "#define NVAUDIOEFFECTS_MAJOR_VERSION ${v[0]}"
        echo "#define NVAUDIOEFFECTS_MINOR_VERSION ${v[1]}"
        echo "#define NVAUDIOEFFECTS_PATCH_VERSION ${v[2]}"
        echo "#define NVAUDIOEFFECTS_BUILD_VERSION ${v[3]}"
        echo "#define NVAUDIOEFFECTS_VERSION \"$2\""
    } >"$1"
}

so_links() { # so_links <dir> <stem>: <stem>.so -> .so.3 -> .so.3.0.0
    fake "$1/$2.so.3.0.0"
    ln -s "$2.so.3.0.0" "$1/$2.so.3"
    ln -s "$2.so.3" "$1/$2.so"
}

core_files() { # core_files <root> <version>: the SDK core without features or models
    so_links "$1/nvafx/lib" libnv_audiofx
    fake "$1/nvafx/include/nvAudioEffects.h" "$1/external/cuda/lib/libcudart.so.12.8.90" \
        "$1/licenses/NVIDIA Software License Agreement.pdf" "$1/external/ThirdPartyLicenses.txt" \
        "$1/features/README.md" "$1/samples/README.md"
    ln -s libcudart.so.12.8.90 "$1/external/cuda/lib/libcudart.so.12"
    version_header "$1/version.h" "$2"
}

feature_files() { # feature_files <dir> <feature>: include/, lib/, licenses/ of a feature
    fake "$1/include/$2.h" "$1/licenses/NVIDIA Models Community License.pdf"
    so_links "$1/lib" "libnv_audiofx_$2"
}

# add_feature <dir> <feature> [version]: a feature's -lib download
add_feature() {
    local dir=$1 f=$2 fver=${3:-3.0.0} stage
    stage=$(mktemp -d "$tmp/stage.XXXXXX")
    feature_files "$stage" "$f"
    mkdir -p "$dir/afx_${f}_v${fver}-lib"
    tar -czf "$dir/afx_${f}_v${fver}-lib/feature_libs.tar.gz" -C "$stage" include lib licenses
}

# add_models <dir> <feature> <version> <rate> <sm> <file>...: a models
# download, each model with its .md5 sidecar (32 digits, no newline).
add_models() {
    local dir=$1/afx_${2}_v${3}-${4}-sm$5 f
    shift 5
    for f in "$@"; do
        fake "$dir/$f"
        md5sum <"$dir/$f" | head -c 32 >"$dir/$f.md5"
    done
}

# make_core <dir> <bare|subdir>: the core download alone
make_core() {
    local dir=$1 where=$2 stage core=$1
    stage=$(mktemp -d "$tmp/stage.XXXXXX")
    core_files "$stage/Audio_Effects_SDK" 3.0.0.12
    [[ $where == subdir ]] && core=$dir/maxine_linux_audio_effects_sdk_v3.0.0
    mkdir -p "$core"
    tar -czf "$core/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" -C "$stage" ./Audio_Effects_SDK
}

dn120=denoiser_48k_10752.trtpkg
dn2_120=denoiser_v2_48k_4096.trtpkg
sv120=studio_voice_high_quality_48k_1.trtpkg
# make_download <dir> <bare|subdir> [feature version]: an NGC download of the
# core, denoiser (48k models for sm_120 and sm_89) and studio voice (48k
# models for sm_120).
make_download() {
    local dir=$1 where=$2 fver=${3:-3.0.0}
    make_core "$dir" "$where"
    add_feature "$dir" denoiser "$fver"
    add_feature "$dir" studio_voice "$fver"
    add_models "$dir" denoiser "$fver" 48k 120 "$dn120" "$dn2_120"
    add_models "$dir" denoiser "$fver" 48k 89 denoiser_48k_10752.trtpkg
    add_models "$dir" studio_voice "$fver" 48k 120 "$sv120"
}

# make_tree <root> [version]: an assembled tree with denoiser (models for
# sm_120 and sm_89) and dereverb (sm_120).
make_tree() {
    local root=$1 version=${2:-3.0.0.12}
    core_files "$root" "$version"
    feature_files "$root/features/denoiser" denoiser
    feature_files "$root/features/dereverb" dereverb
    fake "$root/features/denoiser/models/sm_120/$dn120" "$root/features/denoiser/models/sm_89/$dn120" \
        "$root/features/dereverb/models/sm_120/dereverb_48k_10752.trtpkg"
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

check() { # check <description> <command...>
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}
says() { grep -qF -- "$1" <<<"$out"; } # says <fragment>: the last output has it
not() { ! "$@"; }

models() { # models <tree> <feature> <sm_N>: the entries of models/sm_N, sorted
    (cd "$1/features/$2/models/$3" && find . -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')
}
has_core() {
    [[ -f $1/nvafx/lib/libnv_audiofx.so && -f $1/version.h && -f $1/nvafx/include/nvAudioEffects.h ]]
}
state_is() { # state_is <file> <features> <archs> <rates>
    [[ $(cat "$1") == "MAXINE_AFX_FEATURES=$2"$'\n'"MAXINE_AFX_ARCHS=$3"$'\n'"MAXINE_AFX_RATES=$4" ]]
}
ver=3.0.0.12
two=denoiser,studio_voice

echo "== download mode"
d=$(new_dir)
make_download "$d/src" subdir
before=$(listing "$d/src")
expect_pass "core tarball in maxine_linux_audio_effects_sdk_v3.0.0/" --src "$d/src" --dest "$d/out" \
    --version $ver --state "$d/state"
check "the core is assembled" has_core "$d/out"
check "the feature libraries unpack into features/<f>/lib" \
    test -f "$d/out/features/denoiser/lib/libnv_audiofx_denoiser.so.3.0.0" -a \
    -L "$d/out/features/studio_voice/lib/libnv_audiofx_studio_voice.so"
check "the feature headers and licences unpack beside them" \
    test -f "$d/out/features/denoiser/include/denoiser.h" -a \
    -f "$d/out/features/denoiser/licenses/NVIDIA Models Community License.pdf"
check "the sm_120 models are in features/<f>/models/sm_120, with short-name links, without .md5" \
    test "$(models "$d/out" denoiser sm_120)" = "denoiser_48k.trtpkg $dn120 denoiser_v2_48k.trtpkg $dn2_120 "
check "a short-name link points at its model, relatively" \
    test "$(readlink "$d/out/features/denoiser/models/sm_120/denoiser_48k.trtpkg")" = "$dn120"
check "studio voice's model has its link" \
    test "$(models "$d/out" studio_voice sm_120)" = "studio_voice_high_quality_48k.trtpkg $sv120 "
check "the sm_89 models are not copied by default" test ! -e "$d/out/features/denoiser/models/sm_89"
check "the state lists the features, sm_120 and 48k" state_is "$d/state" "$two" sm_120 48k
check "the summary gives the sm_120 model count and size" \
    grep -qE '^  models    sm_120  3 files, [0-9.]+[KMG]?$' <<<"$out"
check "the summary counts the verified checksums" says "checksums 3 model file(s) verified against their .md5"
check "the summary counts the links" says "links     3 short-name model link(s)"
check "the summary gives the rates" says "rates     48k"
check "the download is untouched" test "$before" = "$(listing "$d/src")"
check "no work directory is left beside dest" \
    test -z "$(find "$d" -maxdepth 1 -name '.assemble.*' -print -quit)"
check "the core's own links are kept" test "$(readlink "$d/out/nvafx/lib/libnv_audiofx.so")" = libnv_audiofx.so.3

d=$(new_dir)
make_download "$d/src" bare
expect_pass "a bare core tarball, dest inside the download (makepkg's src/)" \
    --src "$d/src" --dest "$d/src/src/afx" --version $ver
check "the nested dest is assembled" has_core "$d/src/src/afx"

d=$(new_dir)
make_download "$d/src" bare
expect_fail "an architecture one feature lacks fails, naming the tag" \
    "feature studio_voice has no 48k models for sm_89: no afx_studio_voice_v3.0.*-48k-sm89/" \
    --src "$d/src" --dest "$d/out" --version $ver --archs "sm120 89"
check "the message names the NGC tag" says "nvidia/maxine/afx_studio_voice:3.0.0-48k-sm89"
check "nothing was assembled" test ! -e "$d/out"
expect_pass "--archs \"120 89\" with denoiser only" --src "$d/src" --dest "$d/two" --version $ver \
    --archs "120 89" --features denoiser --state "$d/two.state"
check "both architectures are copied" test -d "$d/two/features/denoiser/models/sm_89" -a \
    -d "$d/two/features/denoiser/models/sm_120"
check "the state lists sm_89 and sm_120" state_is "$d/two.state" denoiser sm_89,sm_120 48k
check "studio voice is left out" says "left out  studio_voice (present, not selected)"
check "the feature left out is not unpacked" test ! -e "$d/two/features/studio_voice"
expect_pass "--archs all copies every models directory" --src "$d/src" --dest "$d/all" --version $ver \
    --archs all --state "$d/all.state"
check "all lists the architectures found" state_is "$d/all.state" "$two" sm_89,sm_120 48k
check "the summary says all found" says "archs     sm_89 sm_120 (all found)"

d=$(new_dir)
make_download "$d/src" bare
add_models "$d/src" denoiser 3.0.0 16k 120 denoiser_16k_10752.trtpkg
add_feature "$d/src" superres
add_models "$d/src" superres 3.0.0 16k_to_48k 120 superres_16k_to_48k_1.trtpkg
add_models "$d/src" superres 3.0.0 8k_to_16k 120 superres_8k_to_16k_1.trtpkg
expect_pass "several sample rates" --src "$d/src" --dest "$d/out" --version $ver --state "$d/state"
check "the rates of one architecture share its directory" \
    test "$(models "$d/out" denoiser sm_120)" = "denoiser_16k.trtpkg denoiser_16k_10752.trtpkg denoiser_48k.trtpkg $dn120 denoiser_v2_48k.trtpkg $dn2_120 "
check "conversion rates are read from the directory name" \
    test -f "$d/out/features/superres/models/sm_120/superres_16k_to_48k_1.trtpkg"
check "every rate is in the state, in order" \
    state_is "$d/state" "denoiser,studio_voice,superres" sm_120 8k_to_16k,16k,16k_to_48k,48k
expect_fail "a rate missing for a selected architecture fails" \
    "feature denoiser has no 16k models for sm_89" \
    --src "$d/src" --dest "$d/out89" --version $ver --archs 89 --features denoiser

echo "== checksums and models directories"
d=$(new_dir)
make_download "$d/src" bare
printf 'tampered\n' >>"$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120"
expect_fail "a model that does not match its .md5 fails" \
    "$dn120 from afx_denoiser_v3.0.0-48k-sm120 does not match $dn120.md5" \
    --src "$d/src" --dest "$d/out" --version $ver
check "it says to download again" says "the download is corrupted or incomplete; download it again"

d=$(new_dir)
make_download "$d/src" bare
printf 'not a checksum' >"$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120.md5"
expect_fail "a sidecar without a checksum fails" "$dn120.md5 in afx_denoiser_v3.0.0-48k-sm120 does not begin with an MD5 checksum" \
    --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_download "$d/src" bare
md5sum <"$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120" >"$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120.md5"
expect_pass "a sidecar in md5sum's own format (hash, two spaces, -, newline) is accepted" \
    --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_download "$d/src" bare
rm "$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120"
expect_fail "a sidecar without its model fails" "holds $dn120.md5 without $dn120" \
    --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_download "$d/src" bare
rm "$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120.md5"
fake "$d/src/afx_denoiser_v3.0.0-48k-sm120/README.txt"
expect_pass "a model without a sidecar and another file" --src "$d/src" --dest "$d/out" --version $ver
check "the unverified model is noted" says "1 model file(s) had no .md5 sidecar and were not verified"
check "the other file is noted" says "not copied (not a model or checksum file): afx_denoiser_v3.0.0-48k-sm120/README.txt"
check "the other file is not copied" test ! -e "$d/out/features/denoiser/models/sm_120/README.txt"
check "nothing is said to be kept from a download" not says "kept as in the SDK tree"

d=$(new_dir)
make_download "$d/src" bare
add_models "$d/src" denoiser 3.0.0 48k 120 denoiser_48k.trtpkg
expect_pass "a model already named like a short-name link" --src "$d/src" --dest "$d/out" --version $ver
check "it is kept as a file" test -f "$d/out/features/denoiser/models/sm_120/denoiser_48k.trtpkg" -a \
    ! -L "$d/out/features/denoiser/models/sm_120/denoiser_48k.trtpkg"
check "the link is skipped, with a note" says "no short-name link for features/denoiser/models/sm_120/$dn120: the name is taken"

d=$(new_dir)
make_download "$d/src" bare
add_models "$d/src" denoiser 3.0.0 16k 120 "$dn120"
cp "$d/src/afx_denoiser_v3.0.0-48k-sm120/$dn120" "$d/src/afx_denoiser_v3.0.0-16k-sm120/$dn120"
md5sum <"$d/src/afx_denoiser_v3.0.0-16k-sm120/$dn120" | head -c 32 >"$d/src/afx_denoiser_v3.0.0-16k-sm120/$dn120.md5"
expect_pass "an identical model in two rate directories is accepted (sm_120 only)" \
    --src "$d/src" --dest "$d/out" --version $ver --features denoiser
printf 'different\n' >"$d/src/afx_denoiser_v3.0.0-16k-sm120/$dn120"
expect_fail "a same-name model with other contents is refused" \
    "model file $dn120 is in both $d/src/afx_denoiser_v3.0.0-16k-sm120 and $d/src/afx_denoiser_v3.0.0-48k-sm120 with different contents" \
    --src "$d/src" --dest "$d/out2" --version $ver --features denoiser

d=$(new_dir)
make_download "$d/src" bare
mkdir "$d/src/afx_denoiser_v3.0.0-48k-sm120/sub"
expect_fail "a subdirectory in a models directory is refused" \
    "models directory afx_denoiser_v3.0.0-48k-sm120 contains subdirectories" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_download "$d/src" bare
ln -s "$dn120" "$d/src/afx_denoiser_v3.0.0-48k-sm120/link.trtpkg"
expect_fail "a link in a models directory is refused" "holds link.trtpkg, which is not a regular file" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_download "$d/src" bare
rm "$d/src/afx_studio_voice_v3.0.0-48k-sm120"/*
expect_fail "an empty models directory is refused" "models directory afx_studio_voice_v3.0.0-48k-sm120 holds no .trtpkg model file" \
    --src "$d/src" --dest "$d/out" --version $ver
check "it names the NGC tag" says "nvidia/maxine/afx_studio_voice:3.0.0-48k-sm120"

echo "== download directories and features"
d=$(new_dir)
make_download "$d/src" subdir
expect_pass "--features listing both" --src "$d/src" --dest "$d/out" --version $ver \
    --features "studio_voice,denoiser" --state "$d/state"
check "both are packaged" state_is "$d/state" "$two" sm_120 48k
expect_fail "--features of an absent feature fails, with the ngc command" "feature(s) not present in $d/src: dereverb" \
    --src "$d/src" --dest "$d/out2" --version $ver --features "denoiser dereverb"
check "the message gives the ngc command" \
    says "ngc registry model download-version \"nvidia/maxine/afx_dereverb:3.0.0-lib\" --dest \"$d/src\""
check "nothing was assembled for it" test ! -e "$d/out2"
expect_fail "'all' with a feature fails" "'all' must be the only --features entry" \
    --src "$d/src" --dest "$d/out3" --version $ver --features "all denoiser"
# shellcheck disable=SC2016 # a literal $ in a feature name
expect_fail "an invalid feature name fails" "invalid feature name 'de\$x'" \
    --src "$d/src" --dest "$d/out3" --version $ver --features 'de$x'

d=$(new_dir)
make_download "$d/src" bare 3.0.2
expect_pass "a feature of the same MAJOR.MINOR (3.0.2) is accepted" --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_download "$d/src" bare 2.1.0
expect_fail "a feature MAJOR.MINOR mismatch fails" "does not match SDK version 3.0" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_download "$d/src" bare
rm -rf "$d/src/afx_studio_voice_v3.0.0-lib"
expect_fail "models without their library fail" "afx_studio_voice_v3.0.0-48k-sm120 has no library download" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_download "$d/src" bare
mkdir "$d/src/afx_denoiser_v3.0.0-models"
expect_fail "an unrecognised afx_ directory fails" "unrecognised download directory afx_denoiser_v3.0.0-models" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_core "$d/src" subdir
expect_fail "a core without features fails" "no feature found in $d/src" --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_core "$d/src" bare
add_feature "$d/src" denoiser
expect_pass "a feature without models passes with a warning" --src "$d/src" --dest "$d/out" --version $ver --state "$d/state"
check "it warns" says "WARNING: no models in the source"
check "the state has no architecture and no rate" state_is "$d/state" denoiser "" ""

echo "== archives"
d=$(new_dir)
make_core "$d/src" bare
stage=$(mktemp -d "$tmp/stage.XXXXXX")
mkdir -p "$stage/x/lib" "$d/escape-target"
fake "$stage/evil"
mkdir -p "$d/src/afx_denoiser_v3.0.0-lib"
tar -czPf "$d/src/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" -C "$stage/x" lib ../evil
expect_fail "a member with a .. component is refused" "holds ../evil, which leaves the directory: refused" \
    --src "$d/src" --dest "$d/out" --version $ver
check "nothing escaped" test ! -e "$d/evil" -a ! -e "$d/out/features/evil"
tar -czPf "$d/src/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" "$stage/evil"
expect_fail "an absolute member is refused" "holds the absolute name $stage/evil" \
    --src "$d/src" --dest "$d/out2" --version $ver
printf 'not gzip\n' >"$d/src/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz"
expect_fail "a tarball that cannot be read is refused" "feature_libs.tar.gz cannot be read as a .tar.gz archive" \
    --src "$d/src" --dest "$d/out3" --version $ver

d=$(new_dir)
make_core "$d/src" bare
stage=$(mktemp -d "$tmp/stage.XXXXXX")
feature_files "$stage" denoiser
ln -s /tmp "$stage/lib/tmp"
mkdir -p "$d/src/afx_denoiser_v3.0.0-lib"
tar -czf "$d/src/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" -C "$stage" include lib licenses
expect_fail "a directory link from a feature tarball is refused" "features/denoiser/lib/tmp in $d/out is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_core "$d/src" bare
stage=$(mktemp -d "$tmp/stage.XXXXXX")
feature_files "$stage" denoiser
mkdir -p "$d/src/afx_denoiser_v3.0.0-lib"
tar -czf "$d/src/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" -C "$stage" include licenses
expect_fail "a feature tarball without lib/ fails" "its tarball does not unpack to lib/ (features/denoiser/lib)" \
    --src "$d/src" --dest "$d/out" --version $ver

# Two tarballs in one -lib directory: the first makes lib/up a link to a
# directory outside the tree, the second has lib/up/planted.txt. The link is
# refused before the second tarball is unpacked, so nothing is written
# through it (or replaces it unseen).
d=$(new_dir)
make_core "$d/src" bare
mkdir -p "$d/outside" "$d/src/afx_denoiser_v3.0.0-lib"
stage=$(mktemp -d "$tmp/stage.XXXXXX")
feature_files "$stage" denoiser
ln -s "$d/outside" "$stage/lib/up"
tar -czf "$d/src/afx_denoiser_v3.0.0-lib/a_libs.tar.gz" -C "$stage" include lib licenses
stage=$(mktemp -d "$tmp/stage.XXXXXX")
fake "$stage/lib/up/planted.txt"
tar -czf "$d/src/afx_denoiser_v3.0.0-lib/b_more.tar.gz" -C "$stage" lib
expect_fail "a link from the first of two feature tarballs is refused before the second" \
    "features/denoiser/lib/up in $d/out is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version $ver
check "the second tarball wrote nothing through the link" test ! -e "$d/outside/planted.txt"
check "the second tarball was not unpacked" test ! -e "$d/out/features/denoiser/lib/up/planted.txt"

d=$(new_dir)
make_core "$d/src" bare
add_feature "$d/src" denoiser
stage=$(mktemp -d "$tmp/stage.XXXXXX")
fake "$stage/lib/libnv_audiofx_denoiser_extra.so"
ln -s nowhere.so "$stage/lib/libgone_extra.so"
tar -czf "$d/src/afx_denoiser_v3.0.0-lib/more_libs.tar.gz" -C "$stage" lib
expect_pass "two clean tarballs in one -lib directory are both unpacked" --src "$d/src" --dest "$d/out" --version $ver
check "the second tarball's library is there" test -f "$d/out/features/denoiser/lib/libnv_audiofx_denoiser_extra.so"
check "a dangling link is counted once despite the repeated checks" \
    says "dangling  1 dangling symbolic links kept as shipped by NVIDIA"

d=$(new_dir)
stage=$(mktemp -d "$tmp/stage.XXXXXX")
core_files "$stage/Audio_Effects_SDK" $ver
ln -s nowhere.so "$stage/Audio_Effects_SDK/nvafx/lib/libgone.so"
mkdir -p "$d/src"
tar -czf "$d/src/NVIDIA_AFX_SDK_Linux_$ver.tar.gz" -C "$stage" Audio_Effects_SDK
add_feature "$d/src" denoiser
expect_pass "a dangling link inside the core is kept" --src "$d/src" --dest "$d/out" --version $ver
check "it is counted" says "dangling  1 dangling symbolic links kept as shipped by NVIDIA"
check "it is kept as shipped" test "$(readlink "$d/out/nvafx/lib/libgone.so")" = nowhere.so

echo "== tree mode"
d=$(new_dir)
make_tree "$d/src"
md5sum <"$d/src/features/denoiser/models/sm_120/$dn120" | head -c 32 >"$d/src/features/denoiser/models/sm_120/$dn120.md5"
before=$(listing "$d/src")
expect_pass "a tree at the source root" --src "$d/src" --dest "$d/out" --version $ver --state "$d/state"
check "the tree is copied" has_core "$d/out"
check "sm_89 is pruned" test ! -e "$d/out/features/denoiser/models/sm_89"
check "the sidecar is verified and dropped, the link added" \
    test "$(models "$d/out" denoiser sm_120)" = "denoiser_48k.trtpkg $dn120 "
check "it counts the checksum" says "checksums 1 model file(s) verified"
check "the state lists both features, sm_120 and the rate from the name" \
    state_is "$d/state" denoiser,dereverb sm_120 48k
check "the source tree is untouched" test "$before" = "$(listing "$d/src")"
check "no other file is noted in a clean tree" not says "kept as in the SDK tree"

d=$(new_dir)
make_tree "$d/src"
fake "$d/src/features/denoiser/models/sm_120/README.txt" "$d/src/features/denoiser/models/sm_89/notes.txt"
expect_pass "a tree whose models directory holds another file" --src "$d/src" --dest "$d/out" --version $ver
check "the other file is kept, as in the tree" test -f "$d/out/features/denoiser/models/sm_120/README.txt"
check "the note names it" \
    says "kept as in the SDK tree (not a model or checksum file): features/denoiser/models/sm_120/README.txt"
check "a file of a pruned architecture is not named" not says "sm_89/notes.txt"

d=$(new_dir)
make_tree "$d/src/Audio_Effects_SDK"
expect_pass "a tree at <src>/Audio_Effects_SDK, one feature, all architectures" --src "$d/src" --dest "$d/out" \
    --version $ver --features denoiser --archs all --state "$d/state"
check "the feature left out is removed" test ! -e "$d/out/features/dereverb"
check "both architectures are kept" test -d "$d/out/features/denoiser/models/sm_89"
check "the state" state_is "$d/state" denoiser sm_89,sm_120 48k
check "the non-feature files of features/ stay" test -f "$d/out/features/README.md"

d=$(new_dir)
make_tree "$d/src"
expect_fail "a tree feature without models for an architecture fails" \
    "feature dereverb has no models for sm_89 in the SDK tree $d/src" \
    --src "$d/src" --dest "$d/out" --version $ver --archs "120 89"
check "it names the NGC tag" says "nvidia/maxine/afx_dereverb:3.0.0-<rate>-sm89"
expect_fail "a tree feature that is absent fails" "feature(s) not present in the SDK tree $d/src: studio_voice" \
    --src "$d/src" --dest "$d/out" --version $ver --features studio_voice
printf 'deadbeefdeadbeefdeadbeefdeadbeef' >"$d/src/features/dereverb/models/sm_120/dereverb_48k_10752.trtpkg.md5"
expect_fail "a bad checksum in a tree fails" "dereverb_48k_10752.trtpkg from features/dereverb/models/sm_120 does not match" \
    --src "$d/src" --dest "$d/out2" --version $ver
rm "$d/src/features/dereverb/models/sm_120/dereverb_48k_10752.trtpkg.md5"
expect_fail "a version mismatch fails, naming both versions" "the SDK is 3.0.0.12 (version.h), --version is 3.0.0.13" \
    --src "$d/src" --dest "$d/out3" --version 3.0.0.13
expect_fail "a dest inside the tree fails" "--dest must not be inside the SDK tree" \
    --src "$d/src" --dest "$d/src/out" --version $ver
check "it created nothing in the tree" test ! -e "$d/src/out"

d=$(new_dir)
make_tree "$d/src"
mkdir -p "$d/elsewhere"
ln -s "$d/elsewhere" "$d/src/features/denoiser/models/sm_75"
expect_fail "a directory link in a tree is refused" "features/denoiser/models/sm_75 in $d/src is a symbolic link to a directory" \
    --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
make_tree "$d/src"
fake "$d/home/secret.txt"
ln -s "$d/home/secret.txt" "$d/src/licenses/notes.txt"
expect_fail "a link to a file outside the tree is refused" "licenses/notes.txt in $d/src is a symbolic link to $d/home/secret.txt, outside the tree" \
    --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_tree "$d/src/Audio_Effects_SDK"
make_download "$d/src" subdir
expect_fail "a tree next to NGC downloads is refused" "holds both an SDK tree ($d/src/Audio_Effects_SDK) and NGC downloads" \
    --src "$d/src" --dest "$d/out" --version $ver

echo "== options and sources"
d=$(new_dir)
make_tree "$d/src"
expect_fail "'all' with another architecture fails" "'all' must be the only --archs entry" \
    --src "$d/src" --dest "$d/out" --version $ver --archs "all sm_120"
expect_fail "a bad architecture fails" "invalid architecture '8.9'" --src "$d/src" --dest "$d/out" --version $ver --archs 8.9
expect_fail "an empty --archs fails" "--archs is empty" --src "$d/src" --dest "$d/out" --version $ver --archs " , "
expect_fail "a three-part --version fails" "--version must look like 3.0.0.12" --src "$d/src" --dest "$d/out" --version 3.0.0
expect_fail "an unknown option is a usage error" "usage:" --src "$d/src" --dest "$d/out" --version $ver --rates 48k
fake "$d/out/leftover"
expect_fail "a non-empty dest fails" "--dest must not exist or be empty" --src "$d/src" --dest "$d/out" --version $ver
d=$(new_dir)
mkdir -p "$d/src"
expect_fail "an empty source names what was looked for" "NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" \
    --src "$d/src" --dest "$d/out" --version $ver
check "and the core directory" says "maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz"
d=$(new_dir)
make_tree "$d/src"
mkdir "$d/src"$'\n'
expect_fail "a source path with a newline fails" "contains a newline, which is not supported" \
    --src "$d/src"$'\n' --dest "$d/out" --version $ver

echo "== --scan"
scan() { # scan <description> <args...>: stdout in $out, stderr in $err
    local desc=$1
    shift
    if out=$("$assemble" --scan "$@" 2>"$tmp/err"); then ok "$desc"; else fail "$desc: $(cat "$tmp/err")"; fi
    err=$(cat "$tmp/err")
}
err=''
d=$(new_dir)
make_download "$d/src" subdir
add_feature "$d/src" dereverb
add_models "$d/src" denoiser 3.0.0 16k 120 denoiser_16k_10752.trtpkg
before=$(listing "$d/src")
scan "--scan of a download" --src "$d/src" --version $ver
want="layout=download
version=$ver
source=$d/src/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_$ver.tar.gz
feature=denoiser archs=sm_89,sm_120 rates=16k,48k
feature=dereverb archs=- rates=-
feature=studio_voice archs=sm_120 rates=48k
archs=sm_89,sm_120
rates=16k,48k"
check "it prints each feature with its architectures and rates" test "$out" = "$want"
check "nothing is extracted or written" test "$before" = "$(listing "$d/src")" -a \
    -z "$(find "$d" -mindepth 1 -maxdepth 1 ! -name src -print -quit)"
rm "$d/src/afx_studio_voice_v3.0.0-48k-sm120"/*
scan "--scan with an empty models directory" --src "$d/src" --version $ver
check "it warns on stderr" grep -qF "models directory afx_studio_voice_v3.0.0-48k-sm120 holds no .trtpkg model file" <<<"$err"

d=$(new_dir)
make_tree "$d/src/Audio_Effects_SDK"
scan "--scan of a tree" --src "$d/src" --version $ver
want="layout=tree
version=$ver
source=$d/src/Audio_Effects_SDK
feature=denoiser archs=sm_89,sm_120 rates=48k
feature=dereverb archs=sm_120 rates=48k
archs=sm_89,sm_120
rates=48k"
check "it prints the tree's features with their architectures and rates" test "$out" = "$want"
expect_fail "--scan of another version fails" "the SDK is 3.0.0.12 (version.h), --version is 3.0.0.13" \
    --scan --src "$d/src" --version 3.0.0.13
expect_fail "--scan with --dest is a usage error" "usage:" --scan --src "$d/src" --dest "$d/out" --version $ver

d=$(new_dir)
make_core "$d/src" bare
scan "--scan of a core alone" --src "$d/src" --version $ver
check "it lists no feature" test "$out" = "layout=download
version=$ver
source=$d/src/NVIDIA_AFX_SDK_Linux_$ver.tar.gz
archs=-
rates=-"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
