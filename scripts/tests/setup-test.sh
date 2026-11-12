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
# arguments to one file (makepkg also logs the <PREFIX>_SRC it receives);
# sudo runs only `cp` (to copy the fake features). One section replaces the
# Optical Flow and TensorRT stubs with their real configure.sh, run against
# fake inputs packed with bsdtar (skipped without bsdtar).
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
# The Optical Flow SDK: a stub package directory (not the real recipe), whose
# configure.sh and selection.sh honour the contract of scripts/setup.d/README:
# configure.sh --src accepts the zip, or a directory holding exactly one, of
# version 5.0.7, and prints its machine-readable lines; --write records SRC
# and SHA256; every call is logged.
of_dir=$repo/nvidia-optical-flow
mkdir -p "$of_dir"
cat >"$of_dir/PKGBUILD" <<'EOF'
pkgname=nvidia-optical-flow-sdk-local
pkgver=5.0.7
pkgrel=1
arch=('x86_64')
url='https://developer.nvidia.com/opticalflow/download'
EOF
cat >"$of_dir/configure.sh" <<'EOF'
#!/usr/bin/env bash
[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv configure.sh" >>"$FAKE_CALLS"
echo "configure.sh $*" >>"$FAKE_CALLS"
here=$(cd "$(dirname "$0")" && pwd)
src='' write=0
while (($#)); do
    case $1 in
        --src) src=$2 && shift 2 ;;
        --write) write=1 && shift ;;
        --show) cat "$here/selection.conf" && exit 0 ;;
        *) echo "configure.sh: unknown option $1" >&2 && exit 2 ;;
    esac
done
zip=''
if [[ -f $src && ${src##*/} == optical_flow_sdk_*.zip ]]; then
    zip=$src
elif [[ -d $src ]]; then
    shopt -s nullglob
    z=("$src"/optical_flow_sdk_*.zip)
    ((${#z[@]} < 2)) || { echo "configure.sh: more than one optical_flow_sdk_*.zip in $src" >&2 && exit 1; }
    zip=${z[0]:-}
fi
[[ -n $zip ]] || { echo "configure.sh: no Optical Flow SDK in $src" >&2 && exit 1; }
v=${zip##*optical_flow_sdk_} v=${v%.zip}
[[ $v == 5.0.7 ]] || { echo "configure.sh: $zip is version $v; this recipe builds 5.0.7" >&2 && exit 1; }
sum=$(sha256sum <"$zip") sum=${sum%% *}
printf 'version %s\nsource %s\nlayout zip\nsha256 %s\nfeatures api fruc\n\n' "$v" "$zip" "$sum"
echo "The Optical Flow SDK $v, in $zip."
((write)) && printf 'NVIDIA_OF_SRC=%s\nNVIDIA_OF_SHA256=%s\n' "$zip" "$sum" >"$here/selection.conf"
exit 0
EOF
cat >"$of_dir/selection.sh" <<'EOF'
# shellcheck shell=bash
nvidia_of_read_selection() {
    local line
    nvidia_of_file_src=''
    [[ -e $1 ]] || return 0
    while IFS= read -r line; do
        [[ $line == NVIDIA_OF_SRC=* ]] && nvidia_of_file_src=${line#*=}
    done <"$1"
    return 0
}
EOF
chmod +x "$of_dir/configure.sh"
# TensorRT: a stub package directory too. configure.sh --src accepts the
# archive, or a directory holding exactly one, of version 11.4.0.106 (the
# version is the one in the file name), prints its machine-readable lines;
# --write records SRC; every call is logged.
trt_dir=$repo/nvidia-tensorrt
trt_file=TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
mkdir -p "$trt_dir"
cat >"$trt_dir/PKGBUILD" <<'EOF'
pkgname=nvidia-tensorrt-sdk-local
pkgver=11.4.0.106
pkgrel=1
arch=('x86_64')
url='https://developer.nvidia.com/tensorrt/download'
EOF
cat >"$trt_dir/configure.sh" <<'EOF'
#!/usr/bin/env bash
[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv configure.sh" >>"$FAKE_CALLS"
echo "configure.sh $*" >>"$FAKE_CALLS"
here=$(cd "$(dirname "$0")" && pwd)
src='' write=0
while (($#)); do
    case $1 in
        --src) src=$2 && shift 2 ;;
        --write) write=1 && shift ;;
        --show) cat "$here/selection.conf" && exit 0 ;;
        *) echo "configure.sh: unknown option $1" >&2 && exit 2 ;;
    esac
done
a=''
if [[ -f $src && ${src##*/} == TensorRT-*.tar.* ]]; then
    a=$src
elif [[ -d $src ]]; then
    shopt -s nullglob
    z=("$src"/TensorRT-*.tar.*)
    ((${#z[@]} < 2)) || { echo "configure.sh: more than one TensorRT-*.tar.* in $src" >&2 && exit 1; }
    a=${z[0]:-}
fi
[[ -n $a ]] || { echo "configure.sh: no TensorRT download in $src" >&2 && exit 1; }
[[ $a == *-11.4.0.106-* ]] || { echo "configure.sh: $a is not version 11.4.0.106" >&2 && exit 1; }
printf 'version 11.4.0.106\nsource %s\nlayout archive\nsha256 none\nfeatures headers libs\n\n' "$a"
((write)) && printf 'NVIDIA_TRT_SRC=%s\n' "$a" >"$here/selection.conf"
exit 0
EOF
cat >"$trt_dir/selection.sh" <<'EOF'
# shellcheck shell=bash
nvidia_trt_read_selection() {
    local line
    nvidia_trt_file_src=''
    [[ -e $1 ]] || return 0
    while IFS= read -r line; do
        [[ $line == NVIDIA_TRT_SRC=* ]] && nvidia_trt_file_src=${line#*=}
    done <"$1"
    return 0
}
EOF
chmod +x "$trt_dir/configure.sh"
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
# The download locations it receives (what the PKGBUILD would build).
for v in $(compgen -e); do [[ $v != *_SRC ]] || echo "makepkg-env $v=${!v}" >>"$FAKE_CALLS"; done
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
check "it prints the build command, with the source in MAXINE_AFX_SRC" \
    says "(cd $repo/maxine-afx && PKGEXT=.pkg.tar MAXINE_AFX_SRC=$afx_dl makepkg -f)"
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

echo "== the Optical Flow SDK (a browser download)"
not_installed
of_name=nvidia-optical-flow-sdk-local
of_pkg=$of_dir/$of_name-5.0.7-1-x86_64.pkg.tar
of_url=https://developer.nvidia.com/opticalflow/download
of_zip=$home/Downloads/optical_flow_sdk_5.0.7.zip
of_root=$root/opt/nvidia/optical-flow
no_ngc() { not grep -qi ngc <<<"$out"; } # the output never mentions NGC
run -- --help
check "--help lists it as a browser download, with its file" \
    says "of   Optical Flow SDK 5.0.7: in a browser, optical_flow_sdk_5.0.7.zip from"
check "--help documents --src-KEY" says "--src-KEY PATH"
check "--help names NVIDIA_OF_SRC" says NVIDIA_OF_SRC
check "--help offers no --features-of" not says "--features-of"
before=$(listing)
run -- --sdk of --dry-run
check "a dry run of it passes" passes
check "it looks in ~/Downloads" says "-- 2. Download: $home/Downloads (from the default directory)"
check "a missing zip names the Developer Program" says "Join the NVIDIA Developer Program"
check "it names the download page" says "$of_url"
check "it names Accept & Download and the licence" says "NVIDIA DesignWorks SDK License and select \"Accept & Download\""
check "it names the file and the version" says "optical_flow_sdk_5.0.7.zip (version 5.0.7)"
check "it names where to save it, and --src-of" says "Save it in $home/Downloads"
check "and --src-of" says "--src-of PATH"
check "it points at the steps by hand" says "$repo/docs/optical-flow.md#download"
check "it never mentions NGC (no SDK in question uses it)" no_ngc
check "it never offers download.sh" not says "download.sh"
check "it prints the configure command, without --archs or --features" \
    says "$of_dir/configure.sh --src $home/Downloads --write"
check "it prints the build command" says "(cd $of_dir && PKGEXT=.pkg.tar NVIDIA_OF_SRC=$home/Downloads makepkg -f)"
check "it prints the install command" says "sudo pacman -U $of_pkg"
check "nothing that changes anything ran" nothing_changed
check "nothing was written" test "$before" == "$(listing)"
nosmi=$tmp/stubs-nosmi
mkdir -p "$nosmi"
cp "$stubs"/* "$nosmi/"
rm "$nosmi/nvidia-smi"
run PATH="$nosmi:$sysbin" -- --sdk of --dry-run
check "without nvidia-smi it passes" passes
check "no architecture is asked for" not says "configure.sh needs --archs"
check "the configure command is still printed" says "$of_dir/configure.sh --src $home/Downloads --write"
run PATH="$nosmi:$sysbin" -- --sdk vfx --dry-run
check "a Maxine SDK without nvidia-smi still needs --archs" says "configure.sh needs --archs sm_<N> from you"
answers='\ns\n'
run -- --sdk of
check "a skipped browser download is not a failure" passes
check "Enter re-checks" test "$(grep -c "No Optical Flow SDK 5.0.7 download in $home/Downloads" <<<"$out")" == 2
check "it says Enter re-checks and s skips" says "Then press Enter below to re-check, or s to skip."
check "s skipped it" says "Skipped the Optical Flow SDK"
check "interactively it never mentions NGC" no_ngc
check "it runs no download.sh and no ngc" not grep -qE '^(download\.sh|ngc) ' "$calls"
mkdir -p "$tmp/of-old"
fake "$tmp/of-old/optical_flow_sdk_5.0.6.zip"
run -- --dry-run --sdk of --src-of "$tmp/of-old"
check "--src-of is where it looks" says "-- 2. Download: $tmp/of-old (from --src-of)"
check "a zip of another version is not usable, with configure.sh's reason" \
    says "is not usable: configure.sh cannot use it: configure.sh: $tmp/of-old/optical_flow_sdk_5.0.6.zip is version 5.0.6"
check "and the browser steps are shown" says "optical_flow_sdk_5.0.7.zip (version 5.0.7)"
fake "$of_zip"
answers='y\ny\nn\n'
run -- --sdk of
check "a valid zip: selection yes, build yes, install no passes" passes
check "the zip is found in ~/Downloads" says "Found: $of_zip"
check "configure.sh wrote the selection of the zip" called "configure.sh --src $of_zip --write"
check "the selection.conf names the zip" grep -qx "NVIDIA_OF_SRC=$of_zip" "$of_dir/selection.conf"
check "makepkg -f ran in the recipe" called "makepkg -f (PKGEXT=.pkg.tar in $of_dir)"
check "the install command is printed" says "sudo pacman -U $of_pkg"
check "the declined install ran no sudo" not called sudo
run -- --dry-run --sdk of
check "a re-run takes the selection.conf" says "-- 2. Download: $of_zip (from $of_dir/selection.conf)"
check "and reuses the package" says "Already built: $of_pkg (it is current and reused)."
run NVIDIA_OF_SRC="$tmp/of-old" -- --dry-run --sdk of --src-of "$of_zip"
check "--src-of comes before NVIDIA_OF_SRC" says "-- 2. Download: $of_zip (from --src-of)"
rm -f "$of_dir/selection.conf" "$of_pkg" "$of_zip"
# An installed tree under the fake root.
fake "$of_root/include/nvOpticalFlowCuda.h" "$of_root/include/nvOpticalFlowCommon.h" \
    "$of_root/fruc/lib/libNvOFFRUC.so" "$root/usr/lib/libnvidia-opticalflow.so.1"
mkdir -p "$root/usr/share/nvidia-optical-flow"
cat >"$root/usr/share/nvidia-optical-flow/nvidia-optical-flow.env" <<EOF
NVIDIA_OF_ROOT=$of_root
NVIDIA_OF_INCLUDE_DIR=$of_root/include
NVIDIA_OF_LIBRARY_PATH=
NVIDIA_OF_FEATURES=api fruc
EOF
printf '%s\n' "$afx_name $afx_version" "$of_name 5.0.7-1" >"$state/installed"
run -- --sdk of
check "installed: it passes" passes
check "installed: download, build and install are skipped" says "Download, build and install skipped"
check "installed: nothing changed" nothing_changed
check "the check passes; an empty library path without a core library is '-'" \
    grep -qE "^  of +$of_name 5\.0\.7-1 +ok +- +ok +ok$" <<<"$out"
check "the FRUC library is ldd'd" called "ldd $of_root/fruc/lib/libNvOFFRUC.so"
check "the undo names the package" grep -qE "^    \\$ sudo pacman -R .*$of_name" <<<"$out"
check "it points at its check by hand" says "$repo/docs/optical-flow.md#check-the-installation"
of_env=$root/usr/share/nvidia-optical-flow/nvidia-optical-flow.env
cp "$of_env" "$tmp/of.env.orig"
grep -v '^NVIDIA_OF_LIBRARY_PATH=' "$tmp/of.env.orig" >"$of_env"
run -- --sdk of
check "without NVIDIA_OF_LIBRARY_PATH (no core library) it passes" passes
check "and the library path is '-' (nothing to check)" \
    grep -qE "^  of +$of_name 5\.0\.7-1 +ok +- +ok +ok$" <<<"$out"
check "with no note about it" not says "no NVIDIA_OF_LIBRARY_PATH"
mv "$tmp/of.env.orig" "$of_env"
rm "$of_root/include/nvOpticalFlowCommon.h"
run -- --sdk of
check "a missing header fails the check" test "$status" -ne 0
check "it names the header" says "of: $of_root/include/nvOpticalFlowCommon.h does not exist"
fake "$of_root/include/nvOpticalFlowCommon.h"
rm "$root/usr/lib/libnvidia-opticalflow.so.1"
run -- --sdk of
check "a missing driver library fails the check" test "$status" -ne 0
check "it names the library" says "the system library libnvidia-opticalflow.so.1 is not found"
fake "$root/usr/lib/libnvidia-opticalflow.so.1"
not_installed
run -- --dry-run --sdk all
check "--sdk all passes" passes
check "--sdk all sets up five SDKs" test "$(grep -cE '^== .*: [a-z-]+-local ' <<<"$out")" == 5
check "--sdk all skips the placeholder with one line" \
    test "$(grep -c '^Skipped Maxine Early Access: access required' <<<"$out")" == 1
check "the fourth is the Optical Flow SDK" says "== Optical Flow SDK: $of_name 5.0.7-1"
check "with a Maxine SDK the NGC CLI is reported" says "NGC CLI: $stubs/ngc"
check "the Maxine SDKs still get the NGC steps" says "Run \`ngc config set\` yourself"
installed

echo "== the source makepkg builds (a selection.conf, --src-KEY and <PREFIX>_SRC)"
not_installed
of_old=$tmp/of-src-old/optical_flow_sdk_5.0.7.zip
of_new=$tmp/of-src-new/optical_flow_sdk_5.0.7.zip
fake "$of_old" "$of_new"
echo "the new one" >>"$of_new"
rm -f "$of_dir/selection.conf" "$of_pkg"
answers='y\nn\n'
run -- --sdk of --src-of "$tmp/of-src-old"
check "the selection.conf records the old zip" grep -qx "NVIDIA_OF_SRC=$of_old" "$of_dir/selection.conf"
answers='n\ny\nn\n'
run -- --sdk of --src-of "$of_new"
check "keeping the selection.conf passes" passes
check "it says the kept selection.conf's source is built, not --src-of" \
    says "The selection.conf records $of_old, not $of_new: the build uses $of_old unless you replace the selection.conf."
check "the recorded source is validated" called "configure.sh --src $of_old"
check "and said valid" says "$of_old is valid (configure.sh accepts it)."
check "makepkg gets the recorded source in NVIDIA_OF_SRC" called "makepkg-env NVIDIA_OF_SRC=$of_old"
check "not the --src-of one" not called "makepkg-env NVIDIA_OF_SRC=$of_new"
check "the selection.conf is unchanged" grep -qx "NVIDIA_OF_SRC=$of_old" "$of_dir/selection.conf"
rm -f "$of_pkg"
answers='n\ny\nn\n'
run NVIDIA_OF_SRC="$tmp/of-src-new" -- --sdk of
check "keeping it with NVIDIA_OF_SRC set elsewhere passes" passes
check "the build uses the recorded source" says "the build uses $of_old"
check "makepkg gets the recorded source, not the inherited NVIDIA_OF_SRC" called "makepkg-env NVIDIA_OF_SRC=$of_old"
check "the inherited value does not reach makepkg" not called "makepkg-env NVIDIA_OF_SRC=$tmp/of-src-new"
# A package current against the recorded source, a newer file at --src-of.
touch -d '-3 hours' "$of_old"
touch -d '-2 hours' "$of_dir/selection.conf"
touch -d '-1 hour' "$of_pkg"
touch "$of_new"
run -- --dry-run --sdk of --src-of "$of_new"
check "staleness is judged on the recorded source" says "Already built: $of_pkg (it is current and reused)."
check "not on the --src-of one" not says "has newer files"
check "the build command names the recorded source" \
    says "(cd $of_dir && PKGEXT=.pkg.tar NVIDIA_OF_SRC=$of_old makepkg -f)"
answers='y\ny\nn\n'
run -- --sdk of --src-of "$of_new"
check "replacing the selection.conf passes" passes
check "the selection.conf names the new zip" grep -qx "NVIDIA_OF_SRC=$of_new" "$of_dir/selection.conf"
check "makepkg gets the new zip" called "makepkg-env NVIDIA_OF_SRC=$of_new"
check "no mismatch is reported" not says "The selection.conf records"
rm -f "$of_pkg" "$of_new"
answers='n\n'
run -- --sdk of --src-of "$of_old"
check "a kept selection.conf whose source is gone passes" passes
check "it says its source is not usable" says "$of_new is not usable: $of_new does not exist"
check "it stops before the build" says "of: stopped (the selection.conf's source is not usable)"
check "makepkg did not run" not called makepkg
rm -f "$of_dir/selection.conf"
answers='y\ny\nn\n'
run NVIDIA_OF_SRC="$tmp/of-src-new" -- --sdk of --src-of "$of_old"
check "a new selection with another NVIDIA_OF_SRC inherited passes" passes
check "makepkg gets the validated source, not the inherited one" called "makepkg-env NVIDIA_OF_SRC=$of_old"
check "only that one" test "$(grep -c '^makepkg-env NVIDIA_OF_SRC=' "$calls")" == 1
rm -rf "$of_dir/selection.conf" "$of_pkg" "$tmp/of-src-old" "$tmp/of-src-new"

echo "== a configure.sh refusal in a directory without the download file"
mv "$of_dir/configure.sh" "$tmp/of-configure.orig"
cat >"$of_dir/configure.sh" <<'EOF'
#!/usr/bin/env bash
echo "configure.sh $*" >>"$FAKE_CALLS"
echo "a report line on stdout"
echo "configure.sh: cannot read $2: Permission denied" >&2
echo "a second error line" >&2
exit 1
EOF
chmod +x "$of_dir/configure.sh"
mkdir -p "$tmp/of-empty"
run -- --dry-run --sdk of --src-of "$tmp/of-empty"
check "it passes" passes
check "it is reported as a missing download" says "No Optical Flow SDK 5.0.7 download in $tmp/of-empty."
check "with configure.sh's first error line" \
    says "configure.sh says: configure.sh: cannot read $tmp/of-empty: Permission denied"
check "only the first one" not says "a second error line"
before_steps() { # the reason comes before the browser steps
    local a b
    a=$(grep -n -m 1 -F "configure.sh says:" <<<"$out" | cut -d: -f1)
    b=$(grep -n -m 1 -F "Join the NVIDIA Developer Program" <<<"$out" | cut -d: -f1)
    [[ -n $a && -n $b ]] && ((a < b))
}
check "before the browser steps" before_steps
mv "$tmp/of-configure.orig" "$of_dir/configure.sh"
rmdir "$tmp/of-empty"

echo "== TensorRT (a browser download)"
not_installed
trt_name=nvidia-tensorrt-sdk-local
trt_pkg=$trt_dir/$trt_name-11.4.0.106-1-x86_64.pkg.tar
trt_arc=$home/Downloads/$trt_file
trt_root=$root/opt/nvidia/tensorrt
run -- --help
check "--help lists it as a browser download with its file" \
    says "trt  TensorRT 11.4.0.106: in a browser, $trt_file from"
run -- --sdk trt --dry-run
check "a dry run passes" passes
check "it names the archive and the version" says "$trt_file (version 11.4.0.106)"
check "it names the licence" says "NVIDIA TensorRT Software License Agreement"
check "it names the download page" says "https://developer.nvidia.com/tensorrt/download"
check "it points at its steps by hand" says "$repo/docs/tensorrt.md#download"
check "it never mentions NGC" no_ngc
check "it prints the configure command, without --archs" \
    says "$trt_dir/configure.sh --src $home/Downloads --write"
check "nothing that changes anything ran" nothing_changed
fake "$trt_arc"
answers='y\ny\nn\n'
run -- --sdk trt
check "a valid archive: selection yes, build yes, install no passes" passes
check "the archive is found" says "Found: $trt_arc"
check "configure.sh wrote the selection" called "configure.sh --src $trt_arc --write"
check "makepkg ran in the recipe" called "makepkg -f (PKGEXT=.pkg.tar in $trt_dir)"
check "the install command is printed" says "sudo pacman -U $trt_pkg"
check "the declined install ran no sudo" not called sudo
rm -f "$trt_dir/selection.conf"
rm -f "$trt_pkg"
rm -f "$trt_arc"
fake "$trt_root/include/NvInfer.h" "$trt_root/include/NvInferVersion.h" \
    "$trt_root/lib/pkgconfig/nvidia-tensorrt.pc" "$trt_root/lib/libnvinfer.so"
mkdir -p "$root/usr/share/nvidia-tensorrt"
cat >"$root/usr/share/nvidia-tensorrt/nvidia-tensorrt.env" <<EOF
NVIDIA_TRT_ROOT=$trt_root
NVIDIA_TRT_LIBRARY_PATH=$trt_root/lib
NVIDIA_TRT_FEATURES=headers libs
EOF
printf '%s\n' "$afx_name $afx_version" "$trt_name 11.4.0.106-1" >"$state/installed"
run -- --sdk trt
check "installed: it passes" passes
check "the check passes" grep -qE "^  trt +$trt_name 11\.4\.0\.106-1 +ok +ok +ok +ok$" <<<"$out"
check "libnvinfer is ldd'd" called "ldd $trt_root/lib/libnvinfer.so"
check "it points at its check by hand" says "$repo/docs/tensorrt.md#check-the-installation"
rm "$trt_root/include/NvInferVersion.h"
run -- --sdk trt
check "a missing check file fails" test "$status" -ne 0
check "it names the file" says "trt: $trt_root/include/NvInferVersion.h does not exist"
fake "$trt_root/include/NvInferVersion.h"
trt_env=$root/usr/share/nvidia-tensorrt/nvidia-tensorrt.env
cp "$trt_env" "$tmp/trt.env.orig"
grep -v '^NVIDIA_TRT_LIBRARY_PATH=' "$tmp/trt.env.orig" >"$trt_env"
run -- --sdk trt
check "with a core library, no NVIDIA_TRT_LIBRARY_PATH fails the check" test "$status" -ne 0
check "the library path is MISSING" grep -qE "^  trt +$trt_name 11\.4\.0\.106-1 +ok +MISSING " <<<"$out"
check "it says why" says "trt: no NVIDIA_TRT_LIBRARY_PATH in $trt_env"
mv "$tmp/trt.env.orig" "$trt_env"
installed

echo "== the placeholder (Maxine Early Access)"
not_installed
before=$(listing)
run -- --help
check "--help lists it as access required" says "Maxine Early Access: access required, not installable yet"
check "--help names its request page" says "request: https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/collections/maxine_linux_ar_sdk_collection_ea"
check "--help lists it among the --sdk keys" says "maxineea"
run -- --sdk maxineea
check "choosing it passes" passes
check "it prints the request steps" says "How to request access:"
check "it names the collection" says "nvidia/maxine/maxine_linux_ar_sdk_collection_ea"
check "it names the licence" says "NVIDIA Software Evaluation License Agreement"
check "it names the request page" says "Request page: https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/collections/maxine_linux_ar_sdk_collection_ea"
check "it names the AI for Media Early Access Program" says "https://developer.nvidia.com/maxine-early-access"
check "it says it becomes active once the item names are supplied" says "becomes active once the item names are supplied"
check "it runs no tool at all" test ! -s "$calls"
check "it has no preflight" not says "== 1. Preflight"
check "it wrote nothing" test "$before" == "$(listing)"
run -- --sdk maxineea --src-maxineea /tmp
check "it takes no --src-KEY" test "$status" == 2
check "--src-maxineea is refused as an unknown option" says "unknown option --src-maxineea (no SDK 'maxineea')"
check "and nothing ran" test ! -s "$calls"
run -- --sdk maxineea --features-maxineea all
check "it takes no --features-KEY" test "$status" == 2
check "--features-maxineea is refused as an unknown option" says "unknown option --features-maxineea (no SDK 'maxineea')"
check "and nothing ran for it" test ! -s "$calls"
run -- --dry-run --sdk all
check "--sdk all skips it with a line" says "Skipped Maxine Early Access: access required, not installable yet"
check "and prints no request steps" not says "How to request access:"
answers='n\nn\nn\nn\nn\ny\n'
run --
check "interactively it is asked, with the SDKs" says "Show how to request access to Maxine Early Access (access required, not installable yet)?"
check "yes prints the steps" says "How to request access:"
check "and nothing was run" nothing_changed
ph_conf=$repo/scripts/setup.d/60-maxine-ea.conf
mv "$ph_conf" "$tmp/60-ea.orig"
sed '/^request_steps=/d' "$tmp/60-ea.orig" >"$ph_conf"
run -- --help
check "a placeholder without request_steps is refused" says "60-maxine-ea.conf: a placeholder needs request_steps="
sed '/^request_url=/d' "$tmp/60-ea.orig" >"$ph_conf"
run -- --help
check "a placeholder without request_url is refused" says "60-maxine-ea.conf: a placeholder needs request_url="
{ cat "$tmp/60-ea.orig" && echo "package=nvidia-zzz"; } >"$ph_conf"
run -- --help
check "a placeholder with an installable key is refused" says "60-maxine-ea.conf: a placeholder has no package="
mv "$tmp/60-ea.orig" "$ph_conf"
installed
mv "$repo/scripts/setup.d/40-of.conf" "$tmp/40-of.conf.orig"
sed '/^download_file=/d' "$tmp/40-of.conf.orig" >"$repo/scripts/setup.d/40-of.conf"
run -- --help
check "obtain=browser without download_file is refused" says "40-of.conf: obtain=browser needs download_file="
{ cat "$tmp/40-of.conf.orig" && echo "catalogue=download.sh"; } >"$repo/scripts/setup.d/40-of.conf"
run -- --help
check "a catalogue without NGC is refused" says "40-of.conf: catalogue needs obtain=ngc"
sed 's/^configure_select=.*/configure_select=archs bogus/' "$tmp/40-of.conf.orig" >"$repo/scripts/setup.d/40-of.conf"
run -- --help
check "an unknown configure_select is refused" says "40-of.conf: configure_select must be archs, features, both, or none"
sed 's/^configure_select=.*/configure_select=both/' "$tmp/40-of.conf.orig" >"$repo/scripts/setup.d/40-of.conf"
run -- --dry-run --sdk of
check "configure_select=both is accepted" passes
check "both means --archs and --features" \
    says "$of_dir/configure.sh --src $home/Downloads --archs sm_120 --features all --write"
mv "$tmp/40-of.conf.orig" "$repo/scripts/setup.d/40-of.conf"

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

echo "== the real configure.sh of the Optical Flow SDK and of TensorRT, on fake downloads"
# The recipes' own configure.sh (with their helper scripts and PKGBUILD,
# copied into the temporary repository in place of the stubs) against tiny
# fake inputs packed with bsdtar: setup.sh must read their "source" lines
# and record the file they found. The fake TensorRT archive's SHA-256 is
# pinned in the copied PKGBUILD, as nvidia-tensorrt/tests/configure-test.sh
# does. The layout line is read too, but only matters with optional
# downloads, which neither SDK has.
if ! real_bsdtar=$(command -v bsdtar); then
    echo "skipped: bsdtar not found (the end-to-end cases of the real configure.sh need it)"
else
    not_installed
    e2e_bin=$tmp/stubs-e2e
    mkdir -p "$e2e_bin"
    cp "$stubs"/* "$e2e_bin/"
    for tool in cut readlink; do
        # shellcheck disable=SC2016 # the wrapper's own text, expanded when it runs
        printf '#!%s\n[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv %s" >>"${FAKE_CALLS:-/dev/null}"\nexec %q "$@"\n' \
            "$bash_bin" "$tool" "$(command -v "$tool")" >"$e2e_bin/$tool"
    done
    # shellcheck disable=SC2016 # the wrapper's own text, expanded when it runs
    printf '#!%s\n[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv bsdtar" >>"${FAKE_CALLS:-/dev/null}"\nexec %q "$@"\n' \
        "$bash_bin" "$real_bsdtar" >"$e2e_bin/bsdtar"
    chmod +x "$e2e_bin"/*
    mv "$of_dir" "$tmp/of-stub-recipe"
    mv "$trt_dir" "$tmp/trt-stub-recipe"
    mkdir -p "$of_dir" "$trt_dir"
    cp "$top/nvidia-optical-flow/configure.sh" "$top/nvidia-optical-flow/selection.sh" \
        "$top/nvidia-optical-flow/assemble.sh" "$top/nvidia-optical-flow/PKGBUILD" "$of_dir/"
    cp "$top/nvidia-tensorrt/configure.sh" "$top/nvidia-tensorrt/selection.sh" \
        "$top/nvidia-tensorrt/source.sh" "$top/nvidia-tensorrt/PKGBUILD" "$trt_dir/"
    e2e=$tmp/e2e
    # The Optical Flow SDK: its documented top-level names, zipped.
    d=$e2e/of-stage/Optical_Flow_SDK_5.0.7
    fake "$d/NvOFInterface/nvOpticalFlowCommon.h" "$d/NvOFInterface/nvOpticalFlowCuda.h" \
        "$d/NvOFBasicSamples/AppOFCuda/AppOFCuda.cpp" "$d/NvOFTracker/inc/NvOFTracker.h" \
        "$d/NvOFFRUC/Interface/NvFRUC.h" "$d/NvOFFRUC/NvOFFRUCSample/bin/ubuntu/libNvFRUC.so"
    mkdir -p "$e2e/of-dl" "$e2e/of-old"
    (cd "$e2e/of-stage" && "$real_bsdtar" -a -cf "$e2e/of-dl/optical_flow_sdk_5.0.7.zip" -- *)
    e2e_zip=$(realpath "$e2e/of-dl/optical_flow_sdk_5.0.7.zip")
    e2e_zip_sum=$(sha256sum <"$e2e_zip") e2e_zip_sum=${e2e_zip_sum%% *}
    run PATH="$e2e_bin:$sysbin" -- --dry-run --sdk of --src-of "$e2e/of-dl"
    check "of: the real configure.sh accepts the fake zip" passes
    check "of: setup.sh reads its source line" says "Found: $e2e_zip"
    check "of: the configure command names the zip" says "$of_dir/configure.sh --src $e2e_zip --write"
    answers='y\nn\n'
    run PATH="$e2e_bin:$sysbin" -- --sdk of --src-of "$e2e/of-dl"
    check "of: writing the selection passes" passes
    check "of: the selection.conf records the zip" grep -qx "NVIDIA_OF_SRC=$e2e_zip" "$of_dir/selection.conf"
    check "of: and its SHA-256" grep -qx "SHA256=$e2e_zip_sum" "$of_dir/selection.conf"
    rm -f "$of_dir/selection.conf"
    cp "$e2e_zip" "$e2e/of-old/optical_flow_sdk_5.0.6.zip"
    run PATH="$e2e_bin:$sysbin" -- --dry-run --sdk of --src-of "$e2e/of-old"
    check "of: a zip of another version is not usable" says "The download in $e2e/of-old is not usable: configure.sh cannot use it:"
    # TensorRT: a fake tree with its version header, packed as the archive.
    d=$e2e/trt-stage/TensorRT-11.4.0.106
    mkdir -p "$d/include"
    {
        printf '#define TRT_%s_ENTERPRISE %s\n' MAJOR 11 MINOR 4 PATCH 0 BUILD 106
        printf '#define NV_TENSORRT_%s TRT_%s_ENTERPRISE\n' MAJOR MAJOR MINOR MINOR PATCH PATCH BUILD BUILD
    } >"$d/include/NvInferVersion.h"
    fake "$d/include/NvInfer.h" "$d/include/NvOnnxParser.h" "$d/lib/libnvinfer.so.11.4.0" \
        "$d/lib/libnvinfer_plugin.so.11.4.0" "$d/lib/libnvonnxparser.so.11.4.0"
    ln -s libnvinfer.so.11.4.0 "$d/lib/libnvinfer.so"
    mkdir -p "$e2e/trt-dl"
    "$real_bsdtar" --zstd -cf "$e2e/trt-dl/$trt_file" -C "$e2e/trt-stage" TensorRT-11.4.0.106
    e2e_arc=$(realpath "$e2e/trt-dl/$trt_file")
    e2e_arc_sum=$(sha256sum <"$e2e_arc") e2e_arc_sum=${e2e_arc_sum%% *}
    sed -i "s/^_trt_sha256=.*/_trt_sha256=$e2e_arc_sum/" "$trt_dir/PKGBUILD"
    run PATH="$e2e_bin:$sysbin" -- --dry-run --sdk trt --src-trt "$e2e/trt-dl"
    check "trt: the real configure.sh accepts the fake archive" passes
    check "trt: setup.sh reads its source line" says "Found: $e2e_arc"
    check "trt: the configure command names the archive" says "$trt_dir/configure.sh --src $e2e_arc --write"
    answers='y\nn\n'
    run PATH="$e2e_bin:$sysbin" -- --sdk trt --src-trt "$e2e/trt-dl"
    check "trt: writing the selection passes" passes
    check "trt: the selection.conf records the archive" grep -qx "NVIDIA_TRT_SRC=$e2e_arc" "$trt_dir/selection.conf"
    check "trt: and its SHA-256" grep -qx "NVIDIA_TRT_SHA256=$e2e_arc_sum" "$trt_dir/selection.conf"
    check "no program got a key" keyenv_none
    rm -rf "$of_dir" "$trt_dir" "$e2e"
    mv "$tmp/of-stub-recipe" "$of_dir"
    mv "$tmp/trt-stub-recipe" "$trt_dir"
    installed
fi

echo "== a descriptor with post_script but no feature_lib"
sed '/^feature_lib=/d' "$repo/scripts/setup.d/30-afx.conf" >"$tmp/30-afx.conf"
mv "$repo/scripts/setup.d/30-afx.conf" "$tmp/30-afx.conf.orig"
cp "$tmp/30-afx.conf" "$repo/scripts/setup.d/30-afx.conf"
run -- --help
check "it is refused when read" test "$status" -ne 0
check "with a clear message" says "30-afx.conf: post_script needs feature_lib="
mv "$tmp/30-afx.conf.orig" "$repo/scripts/setup.d/30-afx.conf"

echo "== a further SDK, from its descriptor alone"
cat >"$repo/scripts/setup.d/40-zzz.conf" <<'EOF'
# a fake further SDK
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
