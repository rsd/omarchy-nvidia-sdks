#!/usr/bin/env bash
# Tests for maxine-ar/configure.sh and maxine-ar/selection.sh. The fixtures
# are FAKE: tiny text files with the SDK's file names, all under mktemp. The
# scripts run from a copy of maxine-ar/ under mktemp, so selection.conf is
# never written into the working tree. nvidia-smi, ngc, sudo and
# install_feature.sh are stubs first on PATH that record every call: the
# real nvidia-smi is never run, and only --detect-gpu may call the stub.
# Usage: maxine-ar/tests/configure-test.sh. Exits non-zero on any failure.
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
version_header() { # version_header <file>: 1.2.0.0
    mkdir -p "$(dirname "$1")"
    printf '#define NVIDIA_AR_SDK_VERSION_%s %s\n' MAJOR 1 MINOR 2 RELEASE 0 BUILD 0 >"$1"
}
listing() { (cd "$1" && find . -printf '%p %s %T@\n' | sort); }

# The scripts, copied: selection.conf goes next to them.
mar=$tmp/maxine-ar
mkdir -p "$mar"
cp "$recipe/configure.sh" "$recipe/selection.sh" "$recipe/assemble.sh" "$recipe/PKGBUILD" "$mar/"
cfg=$mar/configure.sh
conf=$mar/selection.conf

# Stubs that record their calls. nvidia-smi answers like the real one.
stubs=$tmp/stubs calls=$tmp/calls
mkdir -p "$stubs"
: >"$calls"
for tool in ngc sudo install_feature.sh; do
    printf '#!/bin/sh\necho "%s $*" >>%q\nexit 99\n' "$tool" "$calls" >"$stubs/$tool"
done
cat >"$stubs/nvidia-smi" <<EOF
#!/bin/sh
echo "nvidia-smi \$*" >>$(printf %q "$calls")
printf '%s\n' 'NVIDIA GeForce RTX 5090, 12.0' 'NVIDIA GeForce GTX 1080, 6.1' 'NVIDIA L4, 8.9'
EOF
chmod +x "$stubs"/*

# run <args...>: configure.sh with the stubs, a fake HOME and no MAXINE_AR_*
# variables from the caller; output in $out, status in $status.
out='' status=0
run_env() { # run_env [VAR=value...] -- <args...>
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    out=$(env -u MAXINE_AR_SRC -u MAXINE_AR_ARCHS -u MAXINE_AR_FEATURES \
        PATH="$stubs:$PATH" HOME="$tmp/home" "${vars[@]}" "$cfg" "$@" 2>&1) || status=$?
}
run() { run_env -- "$@"; }
passes() { ((status == 0)) || { echo "$out"; return 1; }; }
fails_with() { # fails_with <fragment>
    ((status != 0)) || { echo "unexpectedly succeeded: $out"; return 1; }
    says "$1" || { echo "$out"; return 1; }
}
conf_is() { # conf_is <src> <archs> <features>: the non-comment lines of selection.conf
    [[ $(grep -v '^#' "$conf") == "MAXINE_AR_SRC=$1"$'\n'"MAXINE_AR_ARCHS=$2"$'\n'"MAXINE_AR_FEATURES=$3" ]]
}
no_temp_left() { test -z "$(find "$mar" -name '.selection.conf.*' -print -quit)"; }

# A download: core, landmark detection (models sm_120, sm_89), face box
# detection (no models in this fixture).
dl=$tmp/dl
fake "$dl/ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz" \
    "$dl/nvarlandmarkdetection_v1.2.0.0_lib_linux/nvarlandmarkdetection_linux.tar.gz" \
    "$dl/nvarfaceboxdetection_v1.2.0.0_lib_linux/nvarfaceboxdetection_linux.tar.gz" \
    "$dl/nvarlandmarkdetection_v1.2.0.0_models_linux_sm120/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg" \
    "$dl/nvarlandmarkdetection_v1.2.0.0_models_linux_sm89/faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg"
# A tree: both features, models for sm_120 and sm_89, one without an SM.
tree=$tmp/tree
fake "$tree/ARSDK/lib/libnvARPose.so" \
    "$tree/ARSDK/features/nvarlandmarkdetection/lib/libnvARLandmarkDetection.so" \
    "$tree/ARSDK/features/nvarfaceboxdetection/lib/libnvARFaceBoxDetection.so" \
    "$tree/ARSDK/features/README.md" \
    "$tree/ARSDK/lib/models/faceland_fp16_multiprofile_68_mode0_120.engine.trtpkg" \
    "$tree/ARSDK/lib/models/faceland_fp16_multiprofile_68_mode0_89.engine.trtpkg" \
    "$tree/ARSDK/lib/models/custom_models_README.md"
version_header "$tree/ARSDK/share/arsdk_version.h"

echo "== the report"
before=$(listing "$dl")
run --src "$dl"
check "a download is reported" passes
check "it names the layout and the core" says "layout   download ($dl/ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz)"
check "it lists each feature with its architectures" \
    grep -qE '^   nvarlandmarkdetection +sm_89 sm_120$' <<<"$out"
check "a feature without models says so" grep -qE '^   nvarfaceboxdetection +no models$' <<<"$out"
check "the offered table marks the present features" \
    grep -qE '^   \[x\] nvarlandmarkdetection +Facial landmark detection and tracking \(68 or 126 points\)$' <<<"$out"
check "the offered table marks the absent ones" grep -qE '^   \[ \] nvarlipsync +Lip synchronisation to an audio track$' <<<"$out"
check "the offered table has the seven documented features" test "$(grep -cE '^   \[[ x]\] nvar' <<<"$out")" = 7
check "eye contact is offered" grep -qE '^   \[ \] nvargazeredirection +Eye contact \(gaze estimation and redirection\)$' <<<"$out"
check "body pose estimation is offered" grep -qE '^   \[ \] nvarbodyposeestimation +Body pose estimation' <<<"$out"
check "the offered table points to download.sh --list" says "the closest NVIDIA Broadcast name: $mar/download.sh --list"
check "the architecture list marks the present ones" \
    says "[ ] sm_75 [ ] sm_80 [ ] sm_86 [x] sm_89 [ ] sm_90 [ ] sm_100 [x] sm_120"
check "there is no selection yet" says "no selection.conf ($conf)"
check "it gives the save command" says "--src $dl --archs sm_120 --features all --write"
check "it gives the fetch commands" \
    says "ngc registry model download-version \"nvidia/maxine/<feature>:1.2.0.0_models_linux_sm<N>\" --dest $dl"
check "it gives the download.sh command with its flags" \
    says "    $mar/download.sh --dest $dl --features <feature>,... --archs sm_<N>,..."
check "it gives the download.sh preset" says "    $mar/download.sh --dest $dl --preset all"
check "nothing is written" test ! -e "$conf"
check "the download is untouched" test "$before" = "$(listing "$dl")"
# The save command names configure.sh as a shell word.
mkdir -p "$tmp/a dir"
cp -a "$mar" "$tmp/a dir/"
cfg="$tmp/a dir/maxine-ar/configure.sh"
run --src "$dl"
check "the save command quotes the script's path" says "    $(printf %q "$cfg") --src $dl --archs"
cfg=$mar/configure.sh

run --src "$tree"
check "a tree is reported" passes
check "it lists the tree's features" says "features  nvarfaceboxdetection nvarlandmarkdetection"
check "it lists the architectures per tree" says "models    sm_89 sm_120 (for the tree as a whole"
check "it counts the files without an architecture" says "1 file(s) whose name carries no architecture"
check "it says a tree is packaged as it is" says "An SDK tree is packaged as it is"

mkdir -p "$tmp/home/Downloads/maxine"
cp -a "$dl" "$tmp/home/Downloads/maxine/ar-sdk"
run
check "the default source is ~/Downloads/maxine/ar-sdk" says "Maxine AR SDK in $tmp/home/Downloads/maxine/ar-sdk"
check "it says the default was used" says "  from     the default (~/Downloads/maxine/ar-sdk)"
run_env MAXINE_AR_SRC="$tree" --
check "MAXINE_AR_SRC is the default when set" grep -qxF "Maxine AR SDK in $tree" <<<"$out"
check "the environment variable is noted as an override" says "note: MAXINE_AR_SRC is set in this environment"

run --src "$tmp/missing"
check "a missing source fails" fails_with "source directory not found: $tmp/missing"
# A trailing newline: $(realpath ...) would drop it and name $dl.
mkdir "$dl"$'\n'
run --src "$dl"$'\n'
check "a source path with a newline fails" fails_with "contains a newline, which is not supported"
rmdir "$dl"$'\n'
mkdir -p "$tmp/both/ARSDK"
cp -a "$tree/ARSDK/." "$tmp/both/ARSDK/"
cp -a "$dl/ar_sdk_core_v1.2.0.0_linux" "$tmp/both/"
run --src "$tmp/both"
check "assemble.sh's refusals apply (both layouts)" fails_with "holds both an SDK tree"

echo "== --write"
run --src "$dl" --archs "120,sm_89" --features "nvarlandmarkdetection nvarfaceboxdetection" --write
check "a valid selection is written" passes
check "selection.conf holds the normalised values" conf_is "$dl" sm_89,sm_120 nvarfaceboxdetection,nvarlandmarkdetection
check "it is mode 644" test "$(stat -c %a "$conf")" = 644
check "no temporary file is left" no_temp_left
check "the result is printed" says "MAXINE_AR_ARCHS=sm_89,sm_120"
check "the next command is printed" says "makepkg -f"
check "it starts with comments only" test "$(head -n 1 "$conf" | cut -c 1)" = "#"
cp "$conf" "$tmp/saved.conf"
inode=$(stat -c %i "$conf")

run --show
check "--show prints the selection" passes
check "--show gives each value" says "MAXINE_AR_FEATURES=nvarfaceboxdetection,nvarlandmarkdetection"

run --src "$dl" --archs sm_86 --write
check "an architecture without models fails" fails_with "feature nvarlandmarkdetection has no models for sm_86 in $dl"
check "it names the fetch command" \
    says "ngc registry model download-version \"nvidia/maxine/nvarlandmarkdetection:1.2.0.0_models_linux_sm86\" --dest $dl"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
run --src "$dl" --features "nvarlandmarkdetection,nvarbodydetection" --write
check "an absent feature fails" fails_with "feature nvarbodydetection is not present in $dl"
check "it names the fetch command" \
    says "ngc registry model download-version \"nvidia/maxine/nvarbodydetection:1.2.0.0_lib_linux\" --dest $dl"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
run --src "$dl" --archs "all sm_120" --write
check "'all' with another architecture fails" fails_with "'all' must be the only --archs entry"
run --src "$dl" --archs 8.9 --write
check "an invalid architecture fails" fails_with "invalid architecture '8.9'"
# shellcheck disable=SC2016 # a literal $(id), never run
run --src "$dl" --features 'nvar$(id)' --write
check "an invalid feature name fails" fails_with "invalid feature name"
check "the file is unchanged after the failures" cmp -s "$conf" "$tmp/saved.conf"
check "no temporary file is left after the failures" no_temp_left

run --src "$dl" --archs sm_120
check "--archs without --write validates" passes
check "it says nothing was saved" says "not saved; add --write"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"

run --src "$dl" --archs sm_120 --write
check "--write with --archs only" passes
check "it keeps the file's features" conf_is "$dl" sm_120 nvarfaceboxdetection,nvarlandmarkdetection
check "the file was replaced, not rewritten in place" test "$(stat -c %i "$conf")" != "$inode"
run --src "$dl" --features nvarfaceboxdetection --write
check "--write with --features only keeps the file's architectures" conf_is "$dl" sm_120 nvarfaceboxdetection
check "a selected feature without models needs no models" passes
run --src "$dl" --archs all --features all --write
check "all and all are written as such" conf_is "$dl" all all

run --src "$tree" --archs sm_86 --features all --write
check "a tree without models for an architecture fails" fails_with "the SDK tree has no models for sm_86 (it has sm_89 sm_120)"
run --src "$tree" --features nvarbodydetection --write
check "a tree without the feature fails" fails_with "feature nvarbodydetection is not present in the SDK tree $tree/ARSDK"
run --src "$tree" --archs "sm_120 89" --features nvarlandmarkdetection --write
check "a valid tree selection is written" conf_is "$tree" sm_89,sm_120 nvarlandmarkdetection
check "it notes that the tree's models stay" says "lib/models keeps those of the features left out"

# Without --src: the environment, else selection.conf's MAXINE_AR_SRC.
run --archs sm_120 --write
check "--write without --src keeps the file's source" conf_is "$tree" sm_120 nvarlandmarkdetection
check "it says the source came from selection.conf" says "Source: $tree (from $conf)"
run
check "the report without --src reads the file's source" grep -qxF "Maxine AR SDK in $tree" <<<"$out"
check "it says where the source came from" says "  from     $conf"
run_env MAXINE_AR_SRC="$dl" -- --archs sm_120 --features all
check "the environment is over the file's source" says "Source: $dl (from the environment (MAXINE_AR_SRC))"
run --src "$dl" --archs sm_120 --features all
check "--src is over the environment and the file" says "Source: $dl (from --src)"
check "validating left the file alone" conf_is "$tree" sm_120 nvarlandmarkdetection

# shellcheck disable=SC2016 # a literal $ in a directory name
weird=$tmp/'we$ird'
cp -a "$dl" "$weird"
cp "$conf" "$tmp/saved.conf"
run --src "$weird" --archs sm_120 --features all --write
check "a path that selection.conf cannot hold is refused" fails_with "cannot be stored in selection.conf"
check "the file is unchanged" cmp -s "$conf" "$tmp/saved.conf"
check "no temporary file is left" no_temp_left

nomodels=$tmp/nomodels
fake "$nomodels/ARSDK_linux_1.2.0.0.tgz" "$nomodels/nvarfaceboxdetection_v1.2.0.0_lib_linux/b.tar.gz"
run --src "$nomodels" --archs sm_120 --features all --write
check "a download without models may be selected" passes
check "it warns that the features need their models" says "holds no models: the packaged features will not run without their models"
core=$tmp/core
fake "$core/ARSDK_linux_1.2.0.0.tgz"
run --src "$core" --archs sm_120 --features all --write
check "a download without features cannot be selected" fails_with "no feature is present in $core"
run --src "$core"
check "the report of a core alone asks for a feature" says "no feature (no nvar*_v1.2.*_lib_linux/ directory)"

echo "== --show and option checks"
rm -f "$conf"
run --show
check "--show without a file" passes
check "it gives the defaults" says "MAXINE_AR_ARCHS=sm_120, MAXINE_AR_FEATURES=all"
run --show --write
check "--show with --write is a usage error" fails_with "usage:"
run --detect-gpu --src "$dl"
check "--detect-gpu with --src is a usage error" fails_with "usage:"
run --bogus
check "an unknown option is a usage error" fails_with "usage:"
check "nothing so far ran nvidia-smi, ngc, sudo or install_feature.sh" test ! -s "$calls"

echo "== --detect-gpu (stub)"
run --detect-gpu
check "--detect-gpu runs" passes
check "it ran the stub with the documented query" \
    test "$(cat "$calls")" = "nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader"
check "it warns that the query wakes the GPU" says "WARNING: running nvidia-smi: the query wakes a sleeping discrete GPU"
check "12.0 is sm_120" says "NVIDIA GeForce RTX 5090: compute capability 12.0 -> sm_120 (NVIDIA's feature installer fetches models for it)"
check "6.1 is not supported" says "NVIDIA GeForce GTX 1080: compute capability 6.1 -> sm_61, not supported"
check "it suggests the architectures with models" says "--archs \"sm_120 sm_89\" --write"
check "it writes nothing" test ! -e "$conf"

echo "== a malicious selection.conf"
evil() { # evil <line>: a selection.conf whose second line is <line>
    printf '# hostile\n%s\nMAXINE_AR_ARCHS=sm_120\n' "$1" >"$conf"
}
pwned=$tmp/pwned
for line in "MAXINE_AR_SRC=\$(touch $pwned)" "MAXINE_AR_SRC=\`touch $pwned\`" \
    "MAXINE_AR_SRC=/x\"; touch $pwned; \"" "MAXINE_AR_SRC=/x'\$(touch $pwned)'" \
    "MAXINE_AR_FEATURES=all;touch\${IFS}$pwned"; do
    evil "$line"
    run --show
    check "--show rejects: $line" fails_with "selection.conf:2:"
    run --src "$dl"
    check "the report shows it as not valid: $line" says "is not valid"
done
check "nothing was executed" test ! -e "$pwned"
evil "LD_PRELOAD=/tmp/evil.so"
run --show
check "an unknown key is rejected" fails_with "selection.conf:2: unknown key LD_PRELOAD"
evil "touch $pwned"
run --show
check "a line that is not KEY=value is rejected" fails_with "selection.conf:2: not a KEY=value line"
evil "MAXINE_AR_SRC=relative/dir"
run --show
check "a relative MAXINE_AR_SRC is rejected" fails_with "MAXINE_AR_SRC must be an absolute path"
evil $'MAXINE_AR_SRC=/x\t/y'
run --show
check "a control character is rejected" fails_with "a control character"
evil "MAXINE_AR_ARCHS=sm_89"
run --show
check "a duplicate key is rejected" fails_with "selection.conf:3: MAXINE_AR_ARCHS is set twice"
evil "MAXINE_AR_SRC="
run --show
check "an empty value is rejected" fails_with "MAXINE_AR_SRC has an empty value"
evil "MAXINE_AR_SRC= /x"
run --show
check "a leading space is rejected" fails_with "selection.conf:2: the value of MAXINE_AR_SRC must not start or end with white space"
evil "MAXINE_AR_FEATURES=all "
run --show
check "a trailing space is rejected" fails_with "selection.conf:2: the value of MAXINE_AR_FEATURES must not start or end with white space"
evil "MAXINE_AR_SRC=~/Downloads/maxine"
run --show
check "a ~ path is rejected, saying why" fails_with "selection.conf:2: MAXINE_AR_SRC: ~ is not expanded; write the absolute path"
run --archs sm_120 --features all --write
check "without --src a bad file cannot give the source" fails_with "is not valid (see above); give --src"
evil "MAXINE_AR_SRC=\$(touch $pwned)"
run --src "$dl" --archs sm_120 --write
check "--write needing the file's values refuses a bad file" fails_with "is not valid"
run --src "$dl" --archs sm_120 --features all --write
check "--write with both values replaces a bad file" conf_is "$dl" sm_120 all
check "still nothing was executed" test ! -e "$pwned"

echo "== selection.sh: parsing and precedence"
# resolve <env assignments...>: runs maxine_ar_resolve in a clean
# environment and prints value/origin pairs.
# shellcheck disable=SC2016 # the script for bash -c expands its own arguments
resolve() {
    env -u MAXINE_AR_SRC -u MAXINE_AR_ARCHS -u MAXINE_AR_FEATURES "$@" bash -c '
        . "$1/selection.sh"
        maxine_ar_resolve "$2" /default/src sm_120 all || exit 1
        echo "$maxine_ar_src:$maxine_ar_src_from $maxine_ar_archs:$maxine_ar_archs_from $maxine_ar_features:$maxine_ar_features_from"
    ' resolve "$mar" "$conf"
}
rm -f "$conf"
check "no file: the defaults" test "$(resolve)" = "/default/src:default sm_120:default all:default"
printf '# a comment\n\n   # indented comment\nMAXINE_AR_SRC=/data/my maxine\nMAXINE_AR_FEATURES=nvarlandmarkdetection' >"$conf"
check "the file over the defaults (a space in the path, no final newline)" \
    test "$(resolve)" = "/data/my maxine:selection.conf sm_120:default nvarlandmarkdetection:selection.conf"
check "the environment over the file" \
    test "$(resolve MAXINE_AR_SRC=/env MAXINE_AR_ARCHS=all)" = "/env:environment all:environment nvarlandmarkdetection:selection.conf"
check "an empty environment variable does not override" \
    test "$(resolve MAXINE_AR_FEATURES=)" = "/data/my maxine:selection.conf sm_120:default nvarlandmarkdetection:selection.conf"
check "a relative MAXINE_AR_SRC from the environment fails" not resolve MAXINE_AR_SRC=relative/dir 2>/dev/null
check "it says the path must be absolute" \
    grep -qF "environment: MAXINE_AR_SRC must be an absolute path" <<<"$(resolve MAXINE_AR_SRC=relative/dir 2>&1)"
evil "MAXINE_AR_SRC=\$(touch $pwned)"
check "a bad file fails the resolution" not resolve 2>/dev/null
check "the parser executed nothing" test ! -e "$pwned"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
