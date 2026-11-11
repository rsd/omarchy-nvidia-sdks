#!/usr/bin/env bash
# Tests for maxine-afx/configure.sh and maxine-afx/selection.sh. The fixtures
# are FAKE: tiny text files with the SDK's file names, all under mktemp. The
# scripts run from a copy of maxine-afx/ under mktemp, so selection.conf is
# never written into the working tree. nvidia-smi, ngc, sudo and
# download_features.sh are stubs first on PATH that record every call: the
# real nvidia-smi is never run, and only --detect-gpu may call the stub.
# Usage: maxine-afx/tests/configure-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
recipe=$(cd "$here/.." && pwd)

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
version_header() { # version_header <file>: 3.0.0.12
    mkdir -p "$(dirname "$1")"
    printf '#define NVAUDIOEFFECTS_%s_VERSION %s\n' MAJOR 3 MINOR 0 PATCH 0 BUILD 12 >"$1"
}
listing() { (cd "$1" && find . -printf '%p %s %T@\n' | sort); }

# The scripts, copied: selection.conf goes next to them.
mafx=$tmp/maxine-afx
mkdir -p "$mafx"
cp "$recipe/configure.sh" "$recipe/selection.sh" "$recipe/assemble.sh" "$recipe/PKGBUILD" "$mafx/"
cfg=$mafx/configure.sh
conf=$mafx/selection.conf

# Stubs that record their calls. nvidia-smi answers like the real one.
stubs=$tmp/stubs calls=$tmp/calls
mkdir -p "$stubs"
: >"$calls"
for tool in ngc sudo download_features.sh; do
    printf '#!/bin/sh\necho "%s $*" >>%q\nexit 99\n' "$tool" "$calls" >"$stubs/$tool"
done
cat >"$stubs/nvidia-smi" <<EOF
#!/bin/sh
echo "nvidia-smi \$*" >>$(printf %q "$calls")
printf '%s\n' 'NVIDIA GeForce RTX 5090, 12.0' 'NVIDIA GeForce GTX 1080, 6.1' 'NVIDIA L4, 8.9'
EOF
chmod +x "$stubs"/*

# run <args...>: configure.sh with the stubs, a fake HOME and no MAXINE_AFX_*
# variables from the caller; output in $out, status in $status.
out='' status=0
run_env() { # run_env [VAR=value...] -- <args...>
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    out=$(env -u MAXINE_AFX_SRC -u MAXINE_AFX_ARCHS -u MAXINE_AFX_FEATURES \
        PATH="$stubs:$PATH" HOME="$tmp/home" "${vars[@]}" "$cfg" "$@" 2>&1) || status=$?
}
run() { run_env -- "$@"; }
passes() { ((status == 0)) || { echo "$out"; return 1; }; }
fails_with() { # fails_with <fragment>
    ((status != 0)) || { echo "unexpectedly succeeded: $out"; return 1; }
    says "$1" || { echo "$out"; return 1; }
}
conf_is() { # conf_is <src> <archs> <features>: the non-comment lines of selection.conf
    [[ $(grep -v '^#' "$conf") == "MAXINE_AFX_SRC=$1"$'\n'"MAXINE_AFX_ARCHS=$2"$'\n'"MAXINE_AFX_FEATURES=$3" ]]
}
no_temp_left() { test -z "$(find "$mafx" -name '.selection.conf.*' -print -quit)"; }

# A download: core, denoiser (48k sm_120 and sm_89, 16k sm_120 and sm_89),
# studio voice (48k sm_120), dereverb (no models).
dl=$tmp/dl
fake "$dl/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" \
    "$dl/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" \
    "$dl/afx_studio_voice_v3.0.0-lib/feature_libs.tar.gz" \
    "$dl/afx_dereverb_v3.0.0-lib/feature_libs.tar.gz" \
    "$dl/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg" \
    "$dl/afx_denoiser_v3.0.0-48k-sm89/denoiser_48k_10752.trtpkg" \
    "$dl/afx_denoiser_v3.0.0-16k-sm120/denoiser_16k_10752.trtpkg" \
    "$dl/afx_denoiser_v3.0.0-16k-sm89/denoiser_16k_10752.trtpkg" \
    "$dl/afx_studio_voice_v3.0.0-48k-sm120/studio_voice_high_quality_48k_1.trtpkg"
# A tree: denoiser (sm_120, sm_89) and dereverb (sm_120).
tree=$tmp/tree
fake "$tree/Audio_Effects_SDK/nvafx/lib/libnv_audiofx.so" \
    "$tree/Audio_Effects_SDK/features/denoiser/lib/libnv_audiofx_denoiser.so" \
    "$tree/Audio_Effects_SDK/features/dereverb/lib/libnv_audiofx_dereverb.so" \
    "$tree/Audio_Effects_SDK/features/README.md" \
    "$tree/Audio_Effects_SDK/features/denoiser/models/sm_120/denoiser_48k_10752.trtpkg" \
    "$tree/Audio_Effects_SDK/features/denoiser/models/sm_89/denoiser_48k_10752.trtpkg" \
    "$tree/Audio_Effects_SDK/features/dereverb/models/sm_120/dereverb_48k_10752.trtpkg"
version_header "$tree/Audio_Effects_SDK/version.h"

echo "== the report"
before=$(listing "$dl")
run --src "$dl"
check "a download is reported" passes
check "it names the layout and the core" \
    says "layout   download ($dl/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz)"
check "it lists each feature with its architectures and rates" \
    grep -qE '^   denoiser +sm_89 sm_120 +16k 48k$' <<<"$out"
check "studio voice has sm_120 at 48k" grep -qE '^   studio_voice +sm_120 +48k$' <<<"$out"
check "a feature without models says so" grep -qE '^   dereverb +no models$' <<<"$out"
check "the offered table marks the present features, with NGC's rates" \
    grep -qE '^   \[x\] denoiser +16k 48k +Noise removal$' <<<"$out"
check "the offered table marks the absent ones" \
    grep -qE '^   \[ \] superres +8k_to_16k 16k_to_48k +Audio super resolution' <<<"$out"
check "speaker focus is offered as Early Access" grep -qE '^   \[ \] speaker_focus .*Early Access' <<<"$out"
check "the offered table has the six effects" test "$(grep -cE '^   \[[ x]\] [a-z_]+ ' <<<"$out")" = 6
check "the architecture list marks the present ones" \
    says "[ ] sm_75 [ ] sm_80 [ ] sm_86 [x] sm_89 [ ] sm_90 [ ] sm_100 [x] sm_120"
check "it says every rate is packaged" says "Sample rates are not selected: every rate present (16k 48k) is packaged."
check "there is no selection yet" says "no selection.conf ($conf)"
check "it gives the save command" says "--src $dl --archs sm_120 --features all --write"
check "it gives the fetch commands" \
    says "ngc registry model download-version \"nvidia/maxine/afx_<feature>:3.0.0-<rate>-sm<N>\" --dest $dl"
check "it gives the download.sh command" says "$mafx/download.sh --dest $dl --features <feature>-<rate>,... --archs sm_<N>,..."
check "nothing is written" test ! -e "$conf"
check "the download is untouched" test "$before" = "$(listing "$dl")"

run --src "$tree"
check "a tree is reported" passes
check "it lists the tree's features with architectures and rates" grep -qE '^   denoiser +sm_89 sm_120 +48k$' <<<"$out"
check "it says a tree is packaged as it is" says "An SDK tree is packaged as it is"

mkdir -p "$tmp/home/Downloads/maxine"
cp -a "$dl" "$tmp/home/Downloads/maxine/afx-sdk"
run
check "the default source is ~/Downloads/maxine/afx-sdk" says "Maxine Audio Effects SDK in $tmp/home/Downloads/maxine/afx-sdk"
check "it says the default was used" says "  from     the default (~/Downloads/maxine/afx-sdk)"
run_env MAXINE_AFX_SRC="$tree" -- --show
check "an environment variable is noted as an override" says "note: MAXINE_AFX_SRC is set in this environment"

run --src "$tmp/missing"
check "a missing source fails" fails_with "source directory not found: $tmp/missing"
mkdir "$dl"$'\n'
run --src "$dl"$'\n'
check "a source path with a newline fails" fails_with "contains a newline, which is not supported"
rmdir "$dl"$'\n'
mkdir -p "$tmp/both/Audio_Effects_SDK"
cp -a "$tree/Audio_Effects_SDK/." "$tmp/both/Audio_Effects_SDK/"
cp -a "$dl/maxine_linux_audio_effects_sdk_v3.0.0" "$tmp/both/"
run --src "$tmp/both"
check "assemble.sh's refusals apply (both layouts)" fails_with "holds both an SDK tree"

echo "== --write"
run --src "$dl" --archs "120,sm_89" --features "denoiser dereverb" --write
check "a valid selection is written" passes
check "selection.conf holds the normalised values" conf_is "$dl" sm_89,sm_120 denoiser,dereverb
check "it is mode 644" test "$(stat -c %a "$conf")" = 644
check "no temporary file is left" no_temp_left
check "it says every rate is packaged" says "sample rates: every rate present is packaged (16k 48k)"
check "the next command is printed" says "makepkg -f"
cp "$conf" "$tmp/saved.conf"
inode=$(stat -c %i "$conf")

run --src "$dl" --archs sm_89 --features all --write
check "a feature without models for the architecture fails" \
    fails_with "feature studio_voice has no 48k models for sm_89 in $dl"
check "it names the fetch command" \
    says "ngc registry model download-version \"nvidia/maxine/afx_studio_voice:3.0.0-48k-sm89\" --dest $dl"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
run --src "$dl" --archs sm_86 --features denoiser --write
check "every rate of the feature is named" says "feature denoiser has no 16k models for sm_86"
check "both rates" says "feature denoiser has no 48k models for sm_86"
run --src "$dl" --features "denoiser,superres" --write
check "an absent feature fails" fails_with "feature superres is not present in $dl"
check "it names the fetch command" \
    says "ngc registry model download-version \"nvidia/maxine/afx_superres:3.0.0-lib\" --dest $dl"
run --src "$dl" --archs "all sm_120" --write
check "'all' with another architecture fails" fails_with "'all' must be the only --archs entry"
# shellcheck disable=SC2016 # a literal $(id), never run
run --src "$dl" --features 'de$(id)' --write
check "an invalid feature name fails" fails_with "invalid feature name"
check "the file is unchanged after the failures" cmp -s "$conf" "$tmp/saved.conf"
check "no temporary file is left after the failures" no_temp_left

run --src "$dl" --archs sm_120
check "--archs without --write validates" passes
check "it says nothing was saved" says "not saved; add --write"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
run --src "$dl" --archs sm_120 --write
check "--write with --archs only keeps the file's features" conf_is "$dl" sm_120 denoiser,dereverb
check "the file was replaced, not rewritten in place" test "$(stat -c %i "$conf")" != "$inode"
run --src "$dl" --archs all --features all --write
check "all and all are written as such" conf_is "$dl" all all

run --src "$tree" --archs "sm_120 89" --features all --write
check "a tree feature without an architecture fails" fails_with "feature dereverb has no models for sm_89 in the SDK tree (it has sm_120)"
run --src "$tree" --archs "sm_120 89" --features denoiser --write
check "a valid tree selection is written" conf_is "$tree" sm_89,sm_120 denoiser
run --archs sm_120 --write
check "--write without --src keeps the file's source" conf_is "$tree" sm_120 denoiser
check "it says the source came from selection.conf" says "Source: $tree (from $conf)"
run_env MAXINE_AFX_SRC="$dl" -- --archs sm_120 --features all
check "the environment is over the file's source" says "Source: $dl (from the environment (MAXINE_AFX_SRC))"

# shellcheck disable=SC2016 # a literal $ in a directory name
weird=$tmp/'we$ird'
cp -a "$dl" "$weird"
cp "$conf" "$tmp/saved.conf"
run --src "$weird" --archs sm_120 --features all --write
check "a path that selection.conf cannot hold is refused" fails_with "cannot be stored in selection.conf"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
core=$tmp/core
fake "$core/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz"
run --src "$core" --archs sm_120 --features all --write
check "a download without features cannot be selected" fails_with "no feature is present in $core"
run --src "$core"
check "the report of a core alone asks for a feature" says "no feature (no afx_<feature>_v3.0.*-lib/ directory)"

echo "== --show, --detect-gpu and option checks"
rm -f "$conf"
run --show
check "--show without a file gives the defaults" says "MAXINE_AFX_ARCHS=sm_120, MAXINE_AFX_FEATURES=all"
run --show --write
check "--show with --write is a usage error" fails_with "usage:"
run --bogus
check "an unknown option is a usage error" fails_with "usage:"
check "nothing so far ran nvidia-smi, ngc, sudo or download_features.sh" test ! -s "$calls"
run --detect-gpu
check "--detect-gpu runs" passes
check "it ran the stub with the documented query" \
    test "$(cat "$calls")" = "nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader"
check "12.0 is sm_120" says "NVIDIA GeForce RTX 5090: compute capability 12.0 -> sm_120"
check "6.1 is not supported" says "compute capability 6.1 -> sm_61, not supported"
check "it suggests the architectures" says "--archs \"sm_120 sm_89\" --write"

echo "== a malicious selection.conf"
evil() { printf '# hostile\n%s\nMAXINE_AFX_ARCHS=sm_120\n' "$1" >"$conf"; }
pwned=$tmp/pwned
for line in "MAXINE_AFX_SRC=\$(touch $pwned)" "MAXINE_AFX_SRC=\`touch $pwned\`" \
    "MAXINE_AFX_SRC=/x\"; touch $pwned; \"" "MAXINE_AFX_FEATURES=all;touch\${IFS}$pwned"; do
    evil "$line"
    run --show
    check "--show rejects: $line" fails_with "selection.conf:2:"
done
check "nothing was executed" test ! -e "$pwned"
evil "MAXINE_AFX_RATES=48k"
run --show
check "a rate key is unknown" fails_with "selection.conf:2: unknown key MAXINE_AFX_RATES"
evil "MAXINE_AFX_SRC=relative/dir"
run --show
check "a relative MAXINE_AFX_SRC is rejected" fails_with "MAXINE_AFX_SRC must be an absolute path"
evil "MAXINE_AFX_ARCHS=sm_89"
run --show
check "a duplicate key is rejected" fails_with "selection.conf:3: MAXINE_AFX_ARCHS is set twice"
evil "MAXINE_AFX_SRC=~/Downloads/maxine"
run --show
check "a ~ path is rejected" fails_with "~ is not expanded"

echo "== selection.sh: precedence"
# shellcheck disable=SC2016 # the script for bash -c expands its own arguments
resolve() {
    env -u MAXINE_AFX_SRC -u MAXINE_AFX_ARCHS -u MAXINE_AFX_FEATURES "$@" bash -c '
        . "$1/selection.sh"
        maxine_afx_resolve "$2" /default/src sm_120 all || exit 1
        echo "$maxine_afx_src:$maxine_afx_src_from $maxine_afx_archs:$maxine_afx_archs_from $maxine_afx_features:$maxine_afx_features_from"
    ' resolve "$mafx" "$conf"
}
rm -f "$conf"
check "no file: the defaults" test "$(resolve)" = "/default/src:default sm_120:default all:default"
printf '# c\nMAXINE_AFX_SRC=/data/my afx\nMAXINE_AFX_FEATURES=denoiser' >"$conf"
check "the file over the defaults" test "$(resolve)" = "/data/my afx:selection.conf sm_120:default denoiser:selection.conf"
check "the environment over the file" \
    test "$(resolve MAXINE_AFX_SRC=/env MAXINE_AFX_ARCHS=all)" = "/env:environment all:environment denoiser:selection.conf"
check "a relative MAXINE_AFX_SRC from the environment fails" not resolve MAXINE_AFX_SRC=relative 2>/dev/null

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
