#!/usr/bin/env bash
# Tests for scripts/setup.sh. Everything happens under mktemp: the script
# runs from a copy of the repository's scripts (setup.sh, its descriptors in
# setup.d, and each recipe's configure.sh, selection.sh, assemble.sh and
# PKGBUILD; download.sh is a stub that logs its arguments and exits, followed
# by the real script's text, so that setup.sh reads the real feature tables
# from it), so the real selection.conf files and built packages of the working
# tree are never read or written. HOME is a temporary directory,
# MAXINE_SETUP_ROOT points /opt and /usr/share at a fake installed tree, and
# PATH holds only stubs and links to the basic tools, so the real pacman,
# sudo, makepkg, ngc, nvidia-smi and ldd can never run. The stubs log their
# arguments to one file; sudo runs only `cp` (to copy the fake features).
# The fake NVIDIA download_features.sh writes "key ok" or "key missing" in
# that log, comparing the key it receives with a SHA-256 sum: the test key
# itself is never written to any file. Every other program setup.sh can
# start (each stub, the stub download.sh, and a wrapper around each basic
# tool) logs "keyenv <name>" when NGC_API_KEY is in its environment, which
# must never happen. Every run is under setsid, without a terminal, with
# answers on stdin.
# Usage: scripts/tests/setup-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)

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
says() { grep -qF -- "$1" <<<"$out"; }   # says <fragment>: the output has it
called() { grep -qF -- "$1" "$calls"; } # called <fragment>: a stub logged it
not() { ! "$@"; }

setsid_bin=$(command -v setsid) || {
    echo "setsid (util-linux) is needed to run without a terminal" >&2
    exit 2
}

# The repository, copied.
repo=$tmp/repo
mkdir -p "$repo/scripts/setup.d"
cp "$top/scripts/setup.sh" "$repo/scripts/"
cp "$top"/scripts/setup.d/*.conf "$repo/scripts/setup.d/"
for key in vfx ar afx; do
    mkdir -p "$repo/maxine-$key"
    cp "$top/maxine-$key/configure.sh" "$top/maxine-$key/selection.sh" \
        "$top/maxine-$key/assemble.sh" "$top/maxine-$key/PKGBUILD" "$repo/maxine-$key/"
    {
        cat <<'STUB'
#!/usr/bin/env bash
[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv download.sh" >>"$FAKE_CALLS"
echo "download.sh $*" >>"$FAKE_CALLS"
exit 0
STUB
        cat "$top/maxine-$key/download.sh"
    } >"$repo/maxine-$key/download.sh"
    chmod +x "$repo/maxine-$key/download.sh"
done
setup=$repo/scripts/setup.sh
pkgbuild_value() { sed -n "s/^$2=//p" "$repo/maxine-$1/PKGBUILD" | head -n 1 | tr -d "'\"()"; }
afx_name=$(pkgbuild_value afx pkgname)
afx_version=$(pkgbuild_value afx pkgver)-$(pkgbuild_value afx pkgrel)
afx_pkg=$repo/maxine-afx/$afx_name-$afx_version-x86_64.pkg.tar
afx_out=$tmp/home/Downloads/maxine/afx-features
vfx_url=$(pkgbuild_value vfx url)

calls=$tmp/calls state=$tmp/state home=$tmp/home root=$tmp/root
mkdir -p "$state" "$home" "$tmp/tmpdir"
: >"$calls"

# The basic tools, one by one: nothing else of the system is on PATH. bash
# and env are links (setup.sh itself runs on them); every other one is a
# wrapper that logs whether NGC_API_KEY reached it, then runs the tool.
sysbin=$tmp/sysbin
mkdir -p "$sysbin"
bash_bin=$(command -v bash)
for tool in bash env; do ln -s "$(command -v "$tool")" "$sysbin/$tool"; done
for tool in cat grep sed awk find mkdir rm mv rmdir head tail realpath dirname \
    basename df md5sum sha256sum sort tr wc ls cp chmod uname mktemp paste; do
    # shellcheck disable=SC2016 # the wrapper's own text, expanded when it runs
    printf '#!%s\n[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv %s" >>"${FAKE_CALLS:-/dev/null}"\nexec %q "$@"\n' \
        "$bash_bin" "$tool" "$(command -v "$tool")" >"$sysbin/$tool"
    chmod +x "$sysbin/$tool"
done
# keyenv_none: no program but download_features.sh got the key.
keyenv_none() { not grep -q '^keyenv' "$calls" || { grep '^keyenv' "$calls"; return 1; }; }

# The stubs.
stubs=$tmp/stubs
mkdir -p "$stubs"
cat >"$stubs/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >>"$FAKE_CALLS"
if [[ ${1:-} == -Qo && $# == 2 ]]; then
    grep -qxF -- "$2" "$FAKE_STATE/owned" 2>/dev/null && { echo "$2 is owned by fake 1-1"; exit 0; }
    echo "error: No package owns $2" >&2
    exit 1
fi
if [[ ${1:-} == -Q && $# == 2 ]]; then
    [[ $2 == base-devel ]] && { echo "base-devel 1-2"; exit 0; }
    line=$(grep -m 1 "^$2 " "$FAKE_STATE/installed" 2>/dev/null) && { echo "$line"; exit 0; }
    echo "error: package '$2' was not found" >&2
    exit 1
fi
exit 0
EOF
cat >"$stubs/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"$FAKE_CALLS"
[[ ${1:-} == cp ]] && exec "$@"
exit 0
EOF
cat >"$stubs/makepkg" <<'EOF'
#!/usr/bin/env bash
echo "makepkg $* (PKGEXT=${PKGEXT:-} in $PWD)" >>"$FAKE_CALLS"
v() { sed -n "s/^$1=//p" PKGBUILD | head -n 1 | tr -d "'\"()"; }
echo "fake package" >"$(v pkgname)-$(v pkgver)-$(v pkgrel)-x86_64.pkg.tar"
EOF
cat >"$stubs/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "nvidia-smi $*" >>"$FAKE_CALLS"
echo "NVIDIA GeForce RTX 5090, 615.78, 12.0"
EOF
cat >"$stubs/ldd" <<'EOF'
#!/usr/bin/env bash
echo "ldd $*" >>"$FAKE_CALLS"
printf '\tlibc.so.6 => /usr/lib/libc.so.6 (0x0)\n'
EOF
for tool in ngc fakeroot; do
    cat >"$stubs/$tool" <<EOF
#!/usr/bin/env bash
echo "$tool \$*" >>"\$FAKE_CALLS"
exit 99
EOF
done
# bsdtar -tf lists the package as $FAKE_STATE/pkglist says (nothing without it).
cat >"$stubs/bsdtar" <<'EOF'
#!/usr/bin/env bash
echo "bsdtar $*" >>"$FAKE_CALLS"
[[ ${1:-} == -tf && $# == 2 ]] || exit 99
cat "$FAKE_STATE/pkglist" 2>/dev/null
exit 0
EOF
for f in "$stubs"/*; do
    # shellcheck disable=SC2016 # the stub's own text, expanded when it runs
    sed -i '1a [[ -z ${NGC_API_KEY+set} ]] || echo "keyenv '"${f##*/}"'" >>"${FAKE_CALLS:-/dev/null}"' "$f"
done
chmod +x "$stubs"/*
nopacman=$tmp/stubs-nopacman
mkdir -p "$nopacman"
cp "$stubs"/* "$nopacman/"
rm "$nopacman/pacman"

fake() { # fake <file>...: tiny placeholder files
    local f
    for f in "$@"; do
        mkdir -p "$(dirname "$f")"
        printf 'fake %s\n' "${f##*/}" >"$f"
    done
}
md5_of() { local s; s=$(md5sum <"$1"); echo "${s%% *}"; }

# An installed Audio Effects tree under the fake root, with its env file and
# a fake NVIDIA download_features.sh.
afx_root=$root/opt/nvidia/maxine/afx
fake "$afx_root/nvafx/lib/libnv_audiofx.so" \
    "$afx_root/features/denoiser/lib/libnv_audiofx_denoiser.so" \
    "$afx_root/features/denoiser/models/sm_120/denoiser_48k_10752.trtpkg" \
    "$afx_root/external/cuda/lib/libcudart.so.12"
mkdir -p "$root/usr/share/maxine-afx"
cat >"$root/usr/share/maxine-afx/maxine-afx.env" <<EOF
# a fake environment file
MAXINE_AFX_ROOT=$afx_root
MAXINE_AFX_FEATURES_DIR=$afx_root/features
MAXINE_AFX_LIBRARY_PATH=$afx_root/nvafx/lib:$afx_root/features/denoiser/lib:$afx_root/features/speaker_focus/lib:$afx_root/features/superres/lib:$afx_root/external/cuda/lib
LD_LIBRARY_PATH=$afx_root/nvafx/lib
MAXINE_AFX_FEATURES=denoiser
MAXINE_AFX_ARCHS=sm_120
MAXINE_AFX_RATES=48k
EOF
# It takes the key out of its environment first, so that the programs it
# runs do not log it (keyenv). FAKE_DF_SKIP names a feature it leaves out.
cat >"$afx_root/features/download_features.sh" <<'EOF'
#!/usr/bin/env bash
k=${NGC_API_KEY-}
unset NGC_API_KEY
echo "download_features.sh $* (in $PWD)" >>"$FAKE_CALLS"
if [[ -n $k && $(printf '%s' "$k" | sha256sum) == "$FAKE_KEY_SUM" ]]; then
    echo "key ok" >>"$FAKE_CALLS"
else
    echo "key missing" >>"$FAKE_CALLS"
fi
effects='' out=''
while (($#)); do
    case $1 in
        -e) effects=$2 && shift 2 ;;
        -o) out=$2 && shift 2 ;;
        *) echo "unexpected argument $1" >>"$FAKE_CALLS" && exit 1 ;;
    esac
done
for e in ${effects//,/ }; do
    f=${e%%-*}
    [[ $f == "${FAKE_DF_SKIP:-}" ]] && continue
    mkdir -p "$out/$f/lib" "$out/$f/models/sm_120"
    echo "fake lib" >"$out/$f/lib/libnv_audiofx_$f.so"
    echo "fake model" >"$out/$f/models/sm_120/${f}_${e#*-}_1.trtpkg"
done
EOF
chmod +x "$afx_root/features/download_features.sh"

secret=nvapi-SETUPTESTSECRET
secret_sum=$(printf '%s' "$secret" | sha256sum)

# A valid Audio Effects download in the default directory, with a checksum.
afx_dl=$home/Downloads/maxine/afx-sdk
fake "$afx_dl/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" \
    "$afx_dl/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" \
    "$afx_dl/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg"
model=$afx_dl/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg
echo "$(md5_of "$model")  ${model##*/}" >"$model.md5"

# run [VAR=value...] -- <args...>: setup.sh with the answers in $answers on
# stdin (none: /dev/null); output in $out, status in $status. The calls log
# is emptied first.
out='' status=0 answers=''
run() {
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    : >"$calls"
    status=0
    if [[ -n $answers ]]; then
        out=$(printf '%b' "$answers" | env -i HOME="$home" PATH="$stubs:$sysbin" TMPDIR="$tmp/tmpdir" \
            FAKE_CALLS="$calls" FAKE_STATE="$state" FAKE_KEY_SUM="$secret_sum" \
            MAXINE_SETUP_ROOT="$root" "${vars[@]}" "$setsid_bin" -w "$setup" "$@" 2>&1) || status=$?
    else
        out=$(env -i HOME="$home" PATH="$stubs:$sysbin" TMPDIR="$tmp/tmpdir" \
            FAKE_CALLS="$calls" FAKE_STATE="$state" FAKE_KEY_SUM="$secret_sum" \
            MAXINE_SETUP_ROOT="$root" "${vars[@]}" "$setsid_bin" -w "$setup" "$@" </dev/null 2>&1) || status=$?
    fi
    answers=''
}
passes() { ((status == 0)) || { echo "status $status: $out"; return 1; }; }
nothing_changed() { # no stub that changes anything was called
    not grep -qE '^(sudo|makepkg|download\.sh|download_features\.sh|ngc) |^pacman -[URS]' "$calls"
}
listing() { (cd "$tmp" && find . -path ./calls -prune -o -printf '%p %s %T@\n' | LC_ALL=C sort); }
secret_nowhere() { # the key is in no output, no log and no file under the temp dir
    not grep -qF -- "$secret" <<<"$out" || { echo "the key is in the output"; return 1; }
    not grep -rqF -- "$secret" "$tmp" || { grep -rlF -- "$secret" "$tmp"; return 1; }
}
installed() { echo "$afx_name $afx_version" >"$state/installed"; }
not_installed() { rm -f "$state/installed"; }

echo "== --help"
run -- --help
check "--help passes" passes
check "--help names the key handling and NVIDIA's command line" says "curl or wget on their"
check "--help names MAXINE_SETUP_ROOT" says MAXINE_SETUP_ROOT
check "--help runs nothing" test ! -s "$calls"
run NGC_API_KEY="$secret" -- --help
check "--help with a key passes" passes
check "no program started for --help gets the key" keyenv_none

echo "== a hard blocker"
out=$(env -i HOME="$home" PATH="$nopacman:$sysbin" FAKE_CALLS="$calls" \
    "$setsid_bin" -w "$setup" --sdk afx </dev/null 2>&1) && status=0 || status=$?
check "no pacman exits non-zero" test "$status" -ne 0
check "it says why" says "pacman not found"

echo "== --dry-run"
not_installed
before=$(listing)
run NGC_API_KEY="$secret" -- --dry-run
check "a dry run passes" passes
check "it asks nothing" not says "[y/N]"
check "it offers no re-check" not says "Press Enter"
check "nothing that changes anything ran" nothing_changed
check "it ran the read-only checks" called "nvidia-smi --query-gpu=name,driver_version,compute_cap"
check "nothing was written under the temp dir" test "$before" == "$(listing)"
check "no selection.conf was written" test ! -e "$repo/maxine-afx/selection.conf"
check "it detects the GPU" says "compute capability 12.0 -> sm_120"
check "it prints the configure command" \
    says "$repo/maxine-afx/configure.sh --src $afx_dl --archs sm_120 --features all --write"
check "it prints the build command" says "(cd $repo/maxine-afx && PKGEXT=.pkg.tar makepkg -f)"
check "it prints the install command" says "sudo pacman -U $afx_pkg"
check "it takes the default selection" says "Selected: denoiser-48k, dereverb-48k, dereverb_denoiser-48k, studio_voice-48k"
check "it prints download.sh for the selected effects not in the download" \
    says "$repo/maxine-afx/download.sh --dest $afx_dl --features dereverb-48k,dereverb_denoiser-48k,studio_voice-48k"
check "it prints a new download directory for the features" \
    says "mkdir -p $afx_out && dir=\$(mktemp -d $afx_out/run.XXXXXX)"
check "it prints the features command with a placeholder key" \
    says "(cd $afx_root/features && NGC_API_KEY=<your key> ./download_features.sh -e dereverb-48k,dereverb_denoiser-48k,studio_voice-48k -o \"\$dir\")"
check "it prints the copy of exactly the feature directories, root-owned" \
    says "sudo cp -R --no-preserve=ownership -- \"\$dir\"/dereverb \"\$dir\"/dereverb_denoiser \"\$dir\"/studio_voice $afx_root/features/"
check "no program but download_features.sh gets the key" keyenv_none
check "it prints the download command of a missing SDK, with the default features" \
    says "$repo/maxine-vfx/download.sh --dest $home/Downloads/maxine --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising"
check "it shows no selection prompt" not says "Optional downloads (numbers"
check "a dry run never shows the key" secret_nowhere

echo "== a missing download"
answers='\ny\nn\ns\n'
run -- --sdk vfx
check "a skipped SDK is not a failure" passes
check "it names the catalogue page" says "$vfx_url"
check "it names the personal key page" says "https://org.ngc.nvidia.com/setup/personal-keys"
check "it points at the NGC CLI install" says "docs/download.md#3-install-the-ngc-cli"
check "it says to run ngc config set yourself" says "Run \`ngc config set\` yourself"
check "it names the expected version" says "Video Effects SDK 1.3.0.0"
check "it prints the download command" says "$repo/maxine-vfx/download.sh --dest $home/Downloads/maxine"
check "Enter took the default selection" says "Selected: nvvfxgreenscreen, nvvfxbackgroundblur, nvvfxdenoising"
check "y ran download.sh with --dest and the default features" \
    called "download.sh --dest $home/Downloads/maxine --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising"
check "s skipped it" says "Skipped the Video Effects SDK"
check "nothing was built" not called makepkg
check "ngc config was never run" not called "ngc config"
run -- --sdk vfx
check "without answers (end of input) it skips and ends" passes
check "and builds nothing" not called makepkg

echo "== a bad checksum"
bad=$tmp/bad
fake "$bad/maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz" \
    "$bad/afx_denoiser_v3.0.0-lib/feature_libs.tar.gz" \
    "$bad/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg"
echo "0123456789abcdef0123456789abcdef  denoiser_48k_10752.trtpkg" \
    >"$bad/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg.md5"
answers='\nn\ns\n'
run MAXINE_AFX_SRC="$bad" -- --sdk afx
check "a bad download is skipped" passes
check "the bad file is named" says "$bad/afx_denoiser_v3.0.0-48k-sm120/denoiser_48k_10752.trtpkg does not match"
check "it says to delete it and download again" says "Delete each file named above and run download.sh again"
check "makepkg was not called" not called makepkg

echo "== declining"
answers='n\n'
run -- --sdk afx --features-afx denoiser-48k
check "declining the selection passes" passes
check "the configure command is printed" says "$repo/maxine-afx/configure.sh --src $afx_dl --archs sm_120 --features all --write"
check "no selection.conf was written" test ! -e "$repo/maxine-afx/selection.conf"
check "nothing changed" nothing_changed
answers='y\ny\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "selection yes, build yes, install no passes" passes
check "configure.sh wrote selection.conf" grep -qx "MAXINE_AFX_SRC=$afx_dl" "$repo/maxine-afx/selection.conf"
check "makepkg -f ran with PKGEXT=.pkg.tar in the recipe" called "makepkg -f (PKGEXT=.pkg.tar in $repo/maxine-afx)"
check "makepkg was never asked to install" not grep -qE '^makepkg .*(-i|-s|--install|--syncdeps)' "$calls"
check "sudo was never invoked" not called sudo
check "the install command is printed" says "sudo pacman -U $afx_pkg"
check "the features are skipped without the package" says "skipped ($afx_name is not installed)"
answers='n\nn\ny\n'
run -- --sdk afx --features-afx denoiser-48k
check "keep, reuse, install passes" passes
check "the selection.conf is shown and kept" says "MAXINE_AFX_SRC=$afx_dl"
check "the package is reused" says "Already built: $afx_pkg"
check "makepkg was not called" not called makepkg
check "sudo ran pacman -U with the absolute path" called "sudo pacman -U $afx_pkg"

echo "== a built package out of date"
conf=$repo/maxine-afx/selection.conf
current() { # the package newer than the selection.conf and the download
    find "$afx_dl" -exec touch -d '-3 hours' {} +
    touch -d '-2 hours' "$conf"
    touch -d '-1 hour' "$afx_pkg"
}
current
answers='n\nn\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "a current package passes" passes
check "a current package is offered for reuse" says "Already built: $afx_pkg (it is current and reused)."
answers='y\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "rewriting the selection passes" passes
check "a selection written by this run rebuilds" \
    says "Out of date: $afx_pkg (this run changed the download or the selection); it is rebuilt."
check "it asks to build, not to reuse" says "Build the package now"
check "the stale package is not reused" not says "Already built"
check "and not installed" not called "pacman -U"
answers='n\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "a selection.conf newer than the package rebuilds" \
    says "Out of date: $afx_pkg ($conf is newer); it is rebuilt."
current
touch "$model"
answers='n\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "a download file newer than the package rebuilds" \
    says "Out of date: $afx_pkg (the download in $afx_dl has newer files); it is rebuilt."
check "nothing was built without a yes" not called makepkg
current

echo "== the optional features, key from the environment"
installed
answers='y\nn\n'
run NGC_API_KEY="$secret" -- --sdk afx --features-afx speaker_focus-48k,superres-16k_to_48k
check "it passes" passes
check "the installed version skips build and install" says "Download, build and install skipped"
check "an installed package is not rebuilt for the selection" not called "download.sh "
check "download_features.sh ran in the features directory, into a new directory, without --gpu or -v" \
    grep -qE "^download_features.sh -e superres-16k_to_48k,speaker_focus-48k -o $afx_out/run\.[A-Za-z0-9]{6} \(in $afx_root/features\)$" "$calls"
check "it received the key" called "key ok"
check "no other program got the key" keyenv_none
check "declining the copy runs no sudo" not called sudo
run_dir=$(sed -n "s|^download_features.sh .* -o \($afx_out/run\.[A-Za-z0-9]*\) .*|\1|p" "$calls")
check "the copy command of that directory is printed" \
    says "sudo cp -R --no-preserve=ownership -- $run_dir/superres $run_dir/speaker_focus $afx_root/features/"
check "a declined copy keeps the download" test -d "$run_dir/superres/lib"
check "the key is nowhere" secret_nowhere

echo "== the optional features, a feature left out"
fake "$afx_out/superres/lib/libnv_audiofx_superres.so"
answers='y\n'
run NGC_API_KEY="$secret" FAKE_DF_SKIP=superres -- --sdk afx --features-afx superres-16k_to_48k
check "a feature the script left out fails, despite a leftover of an earlier run" test "$status" -ne 0
check "it names the missing feature directory" says "download_features.sh left no $afx_out/run."
check "nothing was copied" not called sudo
rm -rf "$afx_out/superres"

echo "== the optional features, key from the prompt"
# Leftovers in the persistent download directory, from earlier runs.
fake "$afx_out/leftover/lib/libnv_audiofx_leftover.so" "$afx_out/denoiser/lib/stale.so"
answers="y\n$secret\ny\n"
run -- --sdk afx --features-afx speaker_focus-48k,superres-16k_to_48k
check "it passes" passes
check "it received the key" called "key ok"
run_dir=$(sed -n "s|^download_features.sh .* -o \($afx_out/run\.[A-Za-z0-9]*\) .*|\1|p" "$calls")
check "the copy ran with sudo, of the two feature directories only, without keeping the owner" \
    called "sudo cp -R --no-preserve=ownership -- $run_dir/superres $run_dir/speaker_focus $afx_root/features/"
check "the leftover of an earlier run was not copied" test ! -e "$afx_root/features/leftover"
check "the leftover in a packaged feature did not reach the package's directory" \
    test ! -e "$afx_root/features/denoiser/lib/stale.so"
check "the copied download directory is removed" test ! -e "$run_dir"
check "no other program got the key" keyenv_none
check "cp -a is never used" not grep -qE '^sudo cp .*-a' "$calls"
check "the features are in the tree" test -d "$afx_root/features/speaker_focus/lib" -a -d "$afx_root/features/superres/lib"
check "the undo removes exactly the copied features" \
    says "sudo rm -r -- $afx_root/features/superres $afx_root/features/speaker_focus"
check "the undo removes the package" says "sudo pacman -R $afx_name"
check "pacman -R was not run" not called "pacman -R"
check "the key is nowhere" secret_nowhere

echo "== an idempotent re-run"
run -- --sdk afx --features-afx speaker_focus-48k,superres-16k_to_48k
check "it passes" passes
check "it says the features are there" says "already present under $afx_root/features: nothing to do"
check "nothing changed" nothing_changed
check "the check reports the package" grep -qE "^  afx +$afx_name $afx_version +ok +ok +ok +ok$" <<<"$out"

echo "== a new sample rate of a packaged effect"
run -- --sdk afx --features-afx denoiser-16k
check "it passes" passes
check "it is not 'nothing to do'" not says "nothing to do"
check "it names the effect at its rate" says "In the package, but not at this sample rate: denoiser-16k"
check "it routes it to download.sh before the build" \
    says "$repo/maxine-afx/download.sh --dest $afx_dl --features denoiser-16k"
check "and to a rebuild" says "(cd $repo/maxine-afx && PKGEXT=.pkg.tar makepkg -f)"
check "download_features.sh is not offered for it" not says "./download_features.sh"
check "nothing changed" nothing_changed
run -- --sdk afx --features-afx denoiser-48k,speaker_focus-48k
check "the packaged rate and a copied effect are nothing to do" says "already present under $afx_root/features: nothing to do"
answers='y\n'
run NGC_API_KEY="$secret" -- --sdk afx --features-afx speaker_focus-16k
check "a new rate of a copied (unowned) effect goes to download_features.sh" \
    grep -qE "^download_features.sh -e speaker_focus-16k -o $afx_out/run\." "$calls"
check "no other program got the key" keyenv_none

echo "== the key step under xtrace"
answers='y\n'
run SHELLOPTS=xtrace NGC_API_KEY="$secret" -- --sdk afx --features-afx studio_voice-16k
check "it fails" test "$status" -ne 0
check "it says why" says "xtrace (bash -x or set -x) is on: it would print the key"
check "download_features.sh did not run" not called download_features.sh
check "the trace never shows the key" secret_nowhere
check "no program got the key" keyenv_none

echo "== feature directories copied in by hand, in a newer package"
not_installed
current
touch "$afx_pkg"
echo "$afx_root/features/denoiser" >"$state/owned"
printf '%s\n' .PKGINFO opt/nvidia/maxine/afx/features/ opt/nvidia/maxine/afx/features/download_features.sh \
    opt/nvidia/maxine/afx/features/denoiser/lib/libnv_audiofx_denoiser.so \
    opt/nvidia/maxine/afx/features/superres/lib/libnv_audiofx_superres.so \
    opt/nvidia/maxine/afx/features/dereverb/lib/libnv_audiofx_dereverb.so >"$state/pkglist"
run -- --dry-run --sdk afx --features-afx denoiser-48k
check "a dry run passes" passes
check "it prints the removal of the unowned directory the package holds" \
    says "sudo rm -r -- $afx_root/features/superres"
check "not of the owned one" not says "sudo rm -r -- $afx_root/features/denoiser"
check "it says why" says 'pacman -U would stop with "exists in filesystem"'
check "the check is read-only" called "pacman -Qo $afx_root/features/superres"
check "nothing changed" nothing_changed
answers='n\nn\nn\n'
run -- --sdk afx --features-afx denoiser-48k
check "declining the removal passes" passes
check "it does not install" not called "pacman -U"
check "it runs no sudo" not called sudo
check "it prints both commands" says "Not removed, so not installed"
answers='n\nn\ny\ny\n'
run -- --sdk afx --features-afx denoiser-48k
check "removal and install pass" passes
check "the removal ran first" grep -qxF "sudo rm -r -- $afx_root/features/superres" <(head -n 1 <(grep '^sudo' "$calls"))
check "then pacman -U" called "sudo pacman -U $afx_pkg"
rm -f "$state/pkglist" "$state/owned"
installed

echo "== the check"
printf '#!/usr/bin/env bash\nprintf "\\tlibcudart.so.12 => not found\\n"\n' >"$stubs/ldd"
run -- --sdk afx
check "a library not found fails the check" test "$status" -ne 0
check "it names the library" says "libcudart.so.12 => not found"

echo "== the optional downloads: every feature of each download.sh"
# names_of <download.sh> <array>: the words of an array literal, read here
# with awk, independently of setup.sh's own parser (the drift guard).
names_of() {
    awk -v a="$2" '
        !on && index($0, a "=(") == 1 { on = 1; $0 = substr($0, length(a) + 3) }
        on { if (index($0, ")")) { sub(/\).*/, ""); print; exit } print }' "$1" | tr -s ' \t' '\n' | grep -v '^$'
}
# section <sdk>: the numbered list of the SDK in --help
section() { awk -v s="  --features-$1 " 'index($0, s) == 1 { on = 1; next } on && /^$/ { exit } on' <<<"$out"; }
# listed <sdk> <name> [mark]: the name is a numbered line of the SDK's list
# (mark: [x] selected, [ ] not; either when empty)
listed() {
    local m='[x ]'
    [[ ${3:-} == '[x]' ]] && m=x
    [[ ${3:-} == '[ ]' ]] && m=' '
    grep -qE "^ +[0-9]+ \\[$m\\] $2( |\$)" <<<"$(section "$1")"
}
list_count() { # list_count <sdk>: the numbered lines of its list
    awk -v s="  --features-$1 " 'index($0, s) == 1 { on = 1; next } on && /^$/ { exit } on && $1 ~ /^[0-9]+$/ { c++ } END { print c + 0 }' <<<"$out"
}
run -- --help
for key in vfx ar afx; do
    arrays=known_features
    [[ $key == afx ]] && arrays="known_effects early_access"
    all_names=()
    for a in $arrays; do
        while IFS= read -r n; do all_names+=("$n"); done < <(names_of "$top/maxine-$key/download.sh" "$a")
    done
    check "$key: download.sh lists ${#all_names[@]} features, the list ${#all_names[@]} lines" \
        test "$(list_count "$key")" == "${#all_names[@]}"
    for n in "${all_names[@]}"; do
        check "$key: $n is offered" listed "$key" "$n"
    done
    while IFS= read -r n; do
        check "$key: $n is a default" listed "$key" "$n" '[x]'
    done < <(names_of "$top/maxine-$key/download.sh" preset_broadcast)
done
check "vfx lists eight, ar seven, afx twelve" \
    test "$(list_count vfx) $(list_count ar) $(list_count afx)" == "8 7 12"
check "speaker_focus-16k is marked Early Access" grep -qE ' speaker_focus-16k .*\[Early Access\]$' <<<"$out"
check "speaker_focus-48k is marked Early Access" grep -qE ' speaker_focus-48k .*\[Early Access\]$' <<<"$out"
check "only the two speaker focus effects are Early Access" test "$(grep -c '\[Early Access\]' <<<"$out")" == 2
check "the non-default AR features are offered unselected" listed ar nvarlipsync '[ ]'

echo "== selecting optional downloads"
not_installed
answers='1 3\ny\ns\n'
run -- --sdk vfx
check "numbers pass" passes
check "the list is shown before the question" says "Optional downloads of the Video Effects SDK"
check "numbers reach download.sh --features" \
    called "download.sh --dest $home/Downloads/maxine --features nvvfxgreenscreen,nvvfxdenoising"
answers='all\ny\ns\n'
run -- --sdk vfx
check "all passes" passes
check "all reaches download.sh --features with the eight" \
    called "download.sh --dest $home/Downloads/maxine --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising,nvvfxrelighting,nvvfxvideosuperres,nvvfxupscale,nvvfxtruehdr,nvvfxvideoframegeneration"
answers='bogus\nnvvfxtruehdr,2\ny\ns\n'
run -- --sdk vfx
check "an unknown answer is rejected" says "unknown feature 'bogus' for the Video Effects SDK"
check "and asked again; names and numbers mix, in the list's order" \
    called "download.sh --dest $home/Downloads/maxine --features nvvfxbackgroundblur,nvvfxtruehdr"
answers='y\ns\n'
run -- --sdk ar --features-ar 5,nvarbodyposeestimation,7
check "--features-ar passes" passes
check "it asks no selection" not says "Optional downloads (numbers"
check "--features-ar reaches download.sh --features" \
    called "download.sh --dest $home/Downloads/maxine/ar-sdk --features nvarbodydetection,nvarbodyposeestimation,nvarlipsync"
answers='y\ns\n'
run MAXINE_AFX_SRC="$tmp/no-afx" -- --sdk afx --features-afx all
check "afx all reaches download.sh with the twelve, Early Access included" \
    called "download.sh --dest $tmp/no-afx --features denoiser-16k,denoiser-48k,dereverb-16k,dereverb-48k,dereverb_denoiser-16k,dereverb_denoiser-48k,superres-8k_to_16k,superres-16k_to_48k,studio_voice-16k,studio_voice-48k,speaker_focus-16k,speaker_focus-48k"
run -- --sdk vfx --features-vfx nvvfxgreenscreen,nvvfxbogus
check "an unknown --features-vfx name is a usage error" test "$status" == 2
check "it names it" says "unknown feature 'nvvfxbogus' for the Video Effects SDK"
check "nothing ran" not called "download.sh"
run -- --features-afx denoiser-44k
check "an unknown effect rate is a usage error" test "$status" == 2
run -- --features-afx 13
check "a number past the list is a usage error" test "$status" == 2
run -- --features-nosuch all
check "--features for an unknown SDK is a usage error" test "$status" == 2

echo "== the Audio Effects packaged route"
answers='y\nn\nn\nn\n'
run NGC_API_KEY="$secret" -- --sdk afx --features-afx denoiser-48k,speaker_focus-48k
check "it passes" passes
check "download.sh did not get the key" keyenv_none
check "the effect missing from the download goes to download.sh before the build" \
    called "download.sh --dest $afx_dl --features speaker_focus-48k"
check "the present one is not fetched again" not grep -q 'features denoiser' "$calls"
check "it says download.sh left it out and goes on" says "download.sh did not fetch them"
check "download_features.sh did not run" not called "download_features.sh"

echo "== a Video Effects SDK tree"
vtree=$tmp/vtree/VideoFX
fake "$vtree/lib/libVideoFX.so" "$vtree/lib/libNVCVImage.so" "$vtree/include/nvVideoEffects.h" \
    "$vtree/features/nvvfxgreenscreen/lib/libnvVFXGreenScreen.so" \
    "$vtree/features/nvvfxbackgroundblur/lib/libnvVFXBackgroundBlur.so" \
    "$vtree/lib/models/AIGS_288x512_120_m0.engine.trtpkg"
mkdir -p "$vtree/share"
printf '#define NVIDIA_VIDEOEFFECTS_SDK_VERSION_%s\n' 'MAJOR 1' 'MINOR 3' 'RELEASE 0' 'BUILD 0' \
    >"$vtree/share/videofx_version.h"
run MAXINE_VFX_SRC="$vtree" -- --dry-run --sdk vfx --features-vfx nvvfxgreenscreen,nvvfxbackgroundblur
check "a tree passes" passes
check "the features of a tree are found in it" not says "Selected but not in the download"
run MAXINE_VFX_SRC="$vtree" -- --dry-run --sdk vfx --features-vfx nvvfxgreenscreen,nvvfxdenoising
check "only the feature the tree lacks is missing" says "Selected but not in the download: nvvfxdenoising"
check "it says a tree is packaged as it is" says "$vtree is an SDK tree, which is packaged as it is"
check "it offers no download into the tree" not says "download.sh --dest $vtree"
check "it names a download directory of its own" \
    says "$repo/maxine-vfx/download.sh --dest $home/Downloads/maxine --features nvvfxgreenscreen,nvvfxdenoising"
answers='n\n'
run MAXINE_VFX_SRC="$vtree" -- --sdk vfx --features-vfx nvvfxgreenscreen,nvvfxdenoising
check "an interactive run does not offer download.sh for a tree" not says "Run download.sh now"
check "and runs none" not called download.sh
rm -f "$repo/maxine-vfx/selection.conf"

echo "== a descriptor with post_script but no feature_lib"
sed '/^feature_lib=/d' "$repo/scripts/setup.d/30-afx.conf" >"$tmp/30-afx.conf"
mv "$repo/scripts/setup.d/30-afx.conf" "$tmp/30-afx.conf.orig"
cp "$tmp/30-afx.conf" "$repo/scripts/setup.d/30-afx.conf"
run -- --help
check "it is refused when read" test "$status" -ne 0
check "with a clear message" says "30-afx.conf: post_script needs feature_lib="
mv "$tmp/30-afx.conf.orig" "$repo/scripts/setup.d/30-afx.conf"

echo "== a fourth SDK, from its descriptor alone"
cat >"$repo/scripts/setup.d/40-zzz.conf" <<'EOF'
# a fake fourth SDK
key=zzz
title=Zzz SDK
package=maxine-zzz
default_src=~/Downloads/maxine/zzz-sdk
configure=configure.sh
checksum_glob=*.trtpkg.md5
byhand_doc=docs/download.md#zzz
check_doc=docs/usage.md#zzz
root=/opt/nvidia/maxine/zzz
env_file=/usr/share/maxine-zzz/maxine-zzz.env
env_prefix=MAXINE_ZZZ
core_lib=lib/libzzz.so
model_dir=lib/models
model_glob=*.trtpkg
catalogue=download.sh
catalogue_features=zzz_features
catalogue_early_access=zzz_ea
catalogue_what=zzz_what
catalogue_default=zzz_default
EOF
mkdir -p "$repo/maxine-zzz"
cat >"$repo/maxine-zzz/PKGBUILD" <<'EOF'
pkgname=maxine-zzz-local
pkgver=0.1
pkgrel=1
arch=('x86_64')
url='https://example.invalid/zzz'
EOF
cat >"$repo/maxine-zzz/configure.sh" <<'EOF'
#!/usr/bin/env bash
echo "no Maxine Zzz SDK found in $2" >&2
exit 1
EOF
printf 'maxine_zzz_read_selection() { maxine_zzz_file_src=""; }\n' >"$repo/maxine-zzz/selection.sh"
cat >"$repo/maxine-zzz/download.sh" <<'EOF'
#!/usr/bin/env bash
echo "download.sh $*" >>"$FAKE_CALLS"
exit 0
zzz_features=(zalpha zbeta
    zgamma)
zzz_ea=(zgamma)
declare -A zzz_what=(
    [zalpha]="The first fake feature"
    [zbeta]="The second fake feature"
    [zgamma]="The third fake feature"
)
zzz_default=(zalpha)
EOF
chmod +x "$repo/maxine-zzz/configure.sh" "$repo/maxine-zzz/download.sh"
run -- --help
check "--help offers --features-zzz" says "--features-zzz (Zzz SDK, from maxine-zzz/download.sh)"
check "its list has three, the default marked" listed zzz zalpha '[x]'
check "its Early Access one is marked" grep -qE ' zgamma .*The third fake feature \[Early Access\]$' <<<"$out"
run -- --dry-run --sdk zzz
check "a dry run of it passes" passes
check "it names its catalogue page" says "https://example.invalid/zzz"
check "it prints its download command with the default" \
    says "$repo/maxine-zzz/download.sh --dest $home/Downloads/maxine/zzz-sdk --features zalpha"
answers='2,3\ny\ns\n'
run -- --sdk zzz
check "an interactive run of it passes" passes
check "its selection reaches its download.sh" \
    called "download.sh --dest $home/Downloads/maxine/zzz-sdk --features zbeta,zgamma"
check "it is skipped without a download" says "Skipped the Zzz SDK"
run -- --sdk zzz --features-zzz zdelta
check "an unknown name of it is rejected" test "$status" == 2
cat >>"$repo/scripts/setup.d/40-zzz.conf" <<'EOF'
title=again
EOF
run -- --help
check "a duplicate descriptor key is an error" test "$status" -ne 0
check "it names the line" says "40-zzz.conf:21: duplicate key title"
cat >"$repo/scripts/setup.d/40-zzz.conf" <<EOF
key=zzz
title=\$(touch $tmp/pwned)
EOF
run -- --help
check "a \$ in a descriptor value is refused" says 'a $, backtick, quote, backslash or control character is not allowed'
check "and never run" test ! -e "$tmp/pwned"
rm "$repo/scripts/setup.d/40-zzz.conf"

echo
if ((fails > 0)); then
    echo "$fails of $count checks FAILED"
    exit 1
fi
echo "all $count checks passed"
