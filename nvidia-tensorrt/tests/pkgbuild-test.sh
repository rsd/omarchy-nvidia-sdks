#!/usr/bin/env bash
# Builds nvidia-tensorrt/PKGBUILD end to end against a FAKE TensorRT archive
# (tiny text files with TensorRT's names and a version header in its
# format, packed here into a .tar.zst that carries the real archive's name)
# and checks the package with bsdtar: the tree under /opt/nvidia/tensorrt,
# the environment file, the pkg-config file, the licence links and that
# nothing lies outside /opt/nvidia/tensorrt and /usr/share. Builds: the
# archive from the environment, a tree from selection.conf, and failures
# for a checksum mismatch, another version and a hostile selection.conf
# (never executed, not even by `makepkg --printsrcinfo`), for an
# archive or tree with a symbolic link out of it or a special file, and for
# a tree changed after configure.sh --write; the archive unpinned (no
# published checksum: built, with its SHA-256 printed; a SHA-256 recorded by
# configure.sh still checked); the ARM (aarch64) build refused, by name and
# by contents; and the targets/x86_64-linux-gnu layout.
# The download mode (no NVIDIA_TRT_SRC, no selection.conf source, no archive
# in ~/Downloads) runs against a stub DLAGENT that records the URL and copies
# the fake archive: SRCDEST reuse, the exact URL, a wrong file refused by
# makepkg's checksum, and ~/Downloads taking precedence without a download.
# Every makepkg run here has that stub (failing unless a file is delivered),
# so nothing can reach the network.
# Everything happens under mktemp: the recipe files are copied there, the
# fake archive's SHA-256 is pinned in the copied PKGBUILD, and makepkg's
# BUILDDIR, PKGDEST, SRCDEST and LOGDEST point there, so this working tree
# gets no src/, pkg/ or package. Needs makepkg, fakeroot and bsdtar; no
# GPU, no network, no NVIDIA download.
# Usage: nvidia-tensorrt/tests/pkgbuild-test.sh. Exits non-zero on any
# failure, 77 when a needed tool is missing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)

for tool in makepkg fakeroot bsdtar sha256sum; do
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
    fake "$1/$2.so.11.4.0"
    ln -s "$2.so.11.4.0" "$1/$2.so.11"
    ln -s "$2.so.11" "$1/$2.so"
}
trt_tree() { # trt_tree <root> <major> <minor> <patch> <build>
    local root=$1 l
    mkdir -p "$root/include"
    {
        printf '#define TRT_%s_ENTERPRISE %s\n' MAJOR "$2" MINOR "$3" PATCH "$4" BUILD "$5"
        printf '#define NV_TENSORRT_%s TRT_%s_ENTERPRISE\n' MAJOR MAJOR MINOR MINOR PATCH PATCH BUILD BUILD
    } >"$root/include/NvInferVersion.h"
    fake "$root/include/NvInfer.h" "$root/include/NvOnnxParser.h" "$root/bin/trtexec" \
        "$root/python/tensorrt-11.4.0.106-cp313-none-linux_x86_64.whl" \
        "$root/samples/sampleOnnxMNIST/sampleOnnxMNIST.cpp" "$root/data/mnist/README.md" \
        "$root/doc/Acknowledgements.txt" "$root/doc/TensorRT-SLA.pdf" "$root/lib/libnvinfer_static.a"
    for l in libnvinfer libnvinfer_plugin libnvonnxparser; do so_links "$root/lib" "$l"; done
    fake "$root/lib/libnvinfer_builder_resource.so.11.4.0"
    chmod 755 "$root/bin/trtexec"
}

name=TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
stage=$tmp/stage
trt_tree "$stage/good/TensorRT-11.4.0.106" 11 4 0 106
dl=$tmp/dl
mkdir -p "$dl"
bsdtar --zstd -cf "$dl/$name" -C "$stage/good" TensorRT-11.4.0.106
sum=$(sha256sum "$dl/$name" | cut -d' ' -f1)

# The recipe, copied: what the PKGBUILD reads from the repository; the fake
# archive's SHA-256 pinned.
repo=$tmp/repo
recipe=$repo/nvidia-tensorrt
mkdir -p "$recipe"
cp "$top/nvidia-tensorrt/PKGBUILD" "$top/nvidia-tensorrt/selection.sh" "$top/nvidia-tensorrt/source.sh" \
    "$top/nvidia-tensorrt/configure.sh" "$top/nvidia-tensorrt/README.md" "$recipe/"
check "the recipe pins the archive name the fixture uses" grep -qx "_trt_archive=$name" "$recipe/PKGBUILD"
# pin <archive>: pins its SHA-256 in the copied PKGBUILD; `pin "$dl/$name"` restores.
pin() { sed -i "s/^_trt_sha256=.*/_trt_sha256=$(sha256sum "$1" | cut -d' ' -f1)/" "$recipe/PKGBUILD"; }
pin "$dl/$name"

# build <name> [VAR=value...]: makepkg -f in the copied recipe directory,
# with a fake HOME and only the given NVIDIA_TRT_SRC; the log in $log, the
# status in $status, the package (when there is exactly one) in $pkg.
log='' status=0 pkg='' mkflags=() # mkflags: extra makepkg options
# A stub download agent: records the URL it is asked for in $stubdir/calls and
# copies the file named in $stubdir/deliver to the output, or fails when there
# is none. makepkg's --config sources the system one, then replaces DLAGENTS.
stubdir=$tmp/stub
mkdir -p "$stubdir"
cat >"$stubdir/dlstub" <<'STUB'
#!/usr/bin/env bash
d=$(dirname "$0")
printf '%s\n' "$1" >>"$d/calls"
[[ -f $d/deliver ]] || exit 1
cp -- "$(cat "$d/deliver")" "$2"
STUB
chmod 755 "$stubdir/dlstub"
printf '#!/bin/sh\nexit 1\n' >"$stubdir/dlfail"
chmod 755 "$stubdir/dlfail"
cat >"$stubdir/makepkg.conf" <<CONF
source /etc/makepkg.conf
DLAGENTS=('https::$stubdir/dlstub %u %o' 'http::$stubdir/dlfail %u %o' 'ftp::$stubdir/dlfail %u %o')
CONF
stub_reset() { rm -f "$stubdir/calls" "$stubdir/deliver"; } # no call recorded, nothing to deliver
build() {
    local name=$1
    shift
    mkdir -p "$tmp/$name/build" "$tmp/$name/pkgdest" "$tmp/srcdest" "$tmp/logdest" "$tmp/home"
    log=$tmp/$name/makepkg.log status=0 pkg=''
    (
        cd "$recipe" &&
            env -u NVIDIA_TRT_SRC HOME="$tmp/home" \
                BUILDDIR="$tmp/$name/build" PKGDEST="$tmp/$name/pkgdest" SRCDEST="$tmp/srcdest" \
                LOGDEST="$tmp/logdest" PKGEXT=.pkg.tar "$@" \
                makepkg -f -d --nosign --noconfirm "${mkflags[@]}" --config "$stubdir/makepkg.conf"
    ) >"$log" 2>&1 || status=$?
    local -a pkgs=("$tmp/$name"/pkgdest/nvidia-tensorrt-sdk-local-*.pkg.tar)
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
# srcinfo [VAR=value...]: the metadata, with a fake HOME and no NVIDIA_TRT_SRC unless given.
srcinfo() { (cd "$recipe" && env -u NVIDIA_TRT_SRC HOME="$tmp/home" "$@" makepkg --printsrcinfo); }
mkdir -p "$tmp/home"
srcinfo_before=$(srcinfo)
check "the metadata provides nvidia-tensorrt-sdk" grep -qxF $'\tprovides = nvidia-tensorrt-sdk=11.4.0.106' <<<"$srcinfo_before"
check "the metadata provides tensorrt" grep -qxF $'\tprovides = tensorrt=11.4.0.106' <<<"$srcinfo_before"
check "the metadata has pkgrel 3" grep -qxF $'\tpkgrel = 3' <<<"$srcinfo_before"
url=https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/11.4.0/tars/$name
check "the metadata has the exact download URL, named as the archive" \
    grep -qxF $'\tsource = '"$name::$url" <<<"$srcinfo_before"
check "the metadata has the pinned checksum" grep -qxF $'\tsha256sums = '"$sum" <<<"$srcinfo_before"
check "the metadata does not extract the download" grep -qxF $'\tnoextract = '"$name" <<<"$srcinfo_before"
check "the metadata depends on cuda 13.4 or newer 13, and nvidia-utils" \
    test "$(grep -E $'^\tdepends = ' <<<"$srcinfo_before")" = $'\tdepends = cuda>=13.4\n\tdepends = cuda<14\n\tdepends = nvidia-utils'
check "the metadata conflicts with tensorrt" grep -qxF $'\tconflicts = tensorrt' <<<"$srcinfo_before"
check "the metadata does not provide python-tensorrt" not grep -q 'python-tensorrt' <<<"$srcinfo_before"
check "the environment's NVIDIA_TRT_SRC leaves no source in the metadata" \
    test -z "$(srcinfo NVIDIA_TRT_SRC="$dl" | grep -E $'^\t(source|sha256sums|noextract) =' || true)"
mkdir -p "$tmp/home3/Downloads"
cp "$dl/$name" "$tmp/home3/Downloads/"
check "an archive in ~/Downloads leaves no source in the metadata" \
    test -z "$(srcinfo HOME="$tmp/home3" | grep -E $'^\t(source|sha256sums|noextract) =' || true)"
mkdir -p "$tmp/home4/Downloads"
cp "$dl/$name" "$tmp/home4/Downloads/TensorRT-other.tar.zst"
check "another archive in ~/Downloads does not change the metadata" test "$(srcinfo HOME="$tmp/home4")" = "$srcinfo_before"

R=/opt/nvidia/tensorrt
r=${R#/}
lic=usr/share/licenses/nvidia-tensorrt-sdk-local

echo "== the archive, by the environment"
build env NVIDIA_TRT_SRC="$dl"
built "makepkg -f -d builds the package from the archive"
check "prepare() prints where the source came from" logged "NVIDIA_TRT_SRC=$dl (from environment)"
check "prepare() verified the checksum" logged "SHA-256 $sum verified"
check "nothing was written into the copied recipe directory" \
    test -z "$(find "$recipe" -mindepth 1 -maxdepth 1 \( -name src -o -name pkg -o -name '*.pkg.tar*' -o -name selection.conf \) -print -quit)"
check "nothing was extracted next to the download" test "$(find "$dl" -mindepth 1 | wc -l)" = 1
listing=$(bsdtar -tf "$pkg" | grep -v '^\.' | sed 's|/$||')
has() { grep -qxF -- "$1" <<<"$listing"; }
for f in include/NvInfer.h include/NvInferVersion.h include/NvOnnxParser.h lib/libnvinfer.so.11.4.0 \
    lib/libnvinfer_static.a lib/libnvinfer_builder_resource.so.11.4.0 bin/trtexec \
    python/tensorrt-11.4.0.106-cp313-none-linux_x86_64.whl samples/sampleOnnxMNIST/sampleOnnxMNIST.cpp \
    data/mnist/README.md doc/Acknowledgements.txt; do
    check "$f is packaged" has "$r/$f"
done
check "the pkg-config file is packaged" has "$r/lib/pkgconfig/nvidia-tensorrt.pc"
check "the environment file is packaged" has usr/share/nvidia-tensorrt/nvidia-tensorrt.env
check "the README is packaged" has usr/share/doc/nvidia-tensorrt-sdk-local/README.md
ldconf=etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf
outside=$(grep -vE "^($r|usr/share)(/|$)" <<<"$listing" | grep -vxE 'opt|opt/nvidia|usr|etc|etc/ld.so.conf.d' | grep -vxF "$ldconf" || true)
check "nothing outside /opt/nvidia/tensorrt, /usr/share and the loader entry" test -z "$outside"
check "nothing under /usr/include or /usr/lib" test -z "$(grep -E '^usr/(include|lib)(/|$)' <<<"$listing" || true)"
check "nothing under /etc but the loader entry" test "$(grep -E '^etc(/|$)' <<<"$listing" | grep -vxE 'etc|etc/ld.so.conf.d')" = "$ldconf"
check "the loader entry is packaged" has "$ldconf"
verbose=$(bsdtar -tvf "$pkg")
check "the loader entry is a 644 file" grep -qE "^-rw-r--r-- .* $ldconf\$" <<<"$verbose"
check "the loader entry holds exactly the library directory" \
    test "$(bsdtar -xOf "$pkg" "$ldconf" | grep -v '^#')" = "$R/lib"
link_to() { grep -qF -- "$1 -> $2" <<<"$verbose"; } # link_to <path> <target>
check "the library links are kept" link_to "$r/lib/libnvinfer.so" libnvinfer.so.11
check "trtexec stays executable" grep -qE "^-rwxr-xr-x .* $r/bin/trtexec\$" <<<"$verbose"
check "the files are root-owned" not grep -qvE '^[^ ]+ +[0-9]+ root +root ' <<<"$(grep " $r/" <<<"$verbose")"
check "the acknowledgements are linked" link_to "$lic/Acknowledgements.txt" "$R/doc/Acknowledgements.txt"
check "the licence agreement is linked" link_to "$lic/TensorRT-SLA.pdf" "$R/doc/TensorRT-SLA.pdf"
check "the licence pointer is packaged" has "$lic/TERMS.txt"
terms=$(bsdtar -xOf "$pkg" "$lic/TERMS.txt")
check "it names the TensorRT SLA" grep -qF https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html <<<"$terms"
check "it says the package must not be redistributed" grep -qF 'must not be redistributed' <<<"$terms"
check "the licence pointer is a 644 file" grep -qE "^-rw-r--r-- .* $lic/TERMS.txt\$" <<<"$verbose"
want="NVIDIA_TRT_ROOT=$R
NVIDIA_TRT_INCLUDE_DIR=$R/include
NVIDIA_TRT_LIBRARY_PATH=$R/lib
LD_LIBRARY_PATH=$R/lib
NVIDIA_TRT_PKG_CONFIG_PATH=$R/lib/pkgconfig
TENSORRT_HOME=$R
NVIDIA_TRT_VERSION=11.4.0.106"
got=$(bsdtar -xOf "$pkg" usr/share/nvidia-tensorrt/nvidia-tensorrt.env | grep -v '^#')
if [[ $got == "$want" ]]; then
    ok "the environment file has exactly the expected keys and values"
else
    fail "the environment file differs:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
fi
pc=$(bsdtar -xOf "$pkg" "$r/lib/pkgconfig/nvidia-tensorrt.pc")
check "the .pc file names the prefix" grep -qx "prefix=$R" <<<"$pc"
check "the .pc file has the version" grep -qx 'Version: 11.4.0.106' <<<"$pc"
check "the .pc file has the include directory" grep -qxF "Cflags: -I\${includedir}" <<<"$pc"
check "the .pc file requires cudart, for the CUDA headers" grep -qx 'Requires: cudart' <<<"$pc"
check "the .pc file links the three libraries with an RPATH" \
    grep -qxF "Libs: -L\${libdir} -Wl,-rpath,\${libdir} -lnvinfer -lnvinfer_plugin -lnvonnxparser" <<<"$pc"
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists cudart; then
    mkdir -p "$tmp/pc"
    printf '%s\n' "$pc" >"$tmp/pc/nvidia-tensorrt.pc"
    flags=$(PKG_CONFIG_PATH="$tmp/pc" pkg-config --cflags --libs nvidia-tensorrt) || flags=''
    want_flags=("-I$R/include" "-L$R/lib" "-Wl,-rpath,$R/lib" -lnvinfer -lnvinfer_plugin -lnvonnxparser)
    for f in $(pkg-config --cflags --libs cudart); do want_flags+=("$f"); done
    missing=()
    for f in "${want_flags[@]}"; do [[ " $flags " == *" $f "* ]] || missing+=("$f"); done
    check "pkg-config resolves it, with cudart's flags" test -n "$flags" -a "${#missing[@]}" = 0
else
    echo "skip pkg-config resolution (no pkg-config, or no cudart.pc)"
fi

echo "== the download"
# Reuse: a file of the archive's name in SRCDEST is not downloaded again.
stub_reset
mkdir -p "$tmp/sd-reuse"
cp "$dl/$name" "$tmp/sd-reuse/$name"
build reuse SRCDEST="$tmp/sd-reuse"
built "makepkg -f -d builds from the archive already in SRCDEST"
check "prepare() says the source is the download" logged "(from download: fetched by makepkg from $url"
check "it verified the checksum" logged "SHA-256 $sum verified"
check "nothing was fetched" test ! -e "$stubdir/calls"
check "the package holds the library" grep -qxF "$r/lib/libnvinfer.so.11.4.0" <<<"$(bsdtar -tf "$pkg")"
# Fetch: the stub is asked for the exact URL and delivers the fake archive.
stub_reset
printf '%s\n' "$dl/$name" >"$stubdir/deliver"
mkdir -p "$tmp/sd-fetch"
build fetch SRCDEST="$tmp/sd-fetch"
built "makepkg -f -d downloads (stub) and builds"
check "the URL asked for is exactly NVIDIA's" test "$(cat "$stubdir/calls")" = "$url"
check "the download was saved under the archive's name" test -f "$tmp/sd-fetch/$name"
check "it verified the checksum" logged "SHA-256 $sum verified"
# A wrong file is refused by makepkg's own checksum validation.
stub_reset
cp "$dl/$name" "$tmp/wrong.tar.zst"
printf 'x' >>"$tmp/wrong.tar.zst"
printf '%s\n' "$tmp/wrong.tar.zst" >"$stubdir/deliver"
mkdir -p "$tmp/sd-wrong"
build wrong SRCDEST="$tmp/sd-wrong"
check "a wrong download stops the build" test "$status" -ne 0
check "makepkg reports the failed checksum" logged "FAILED"
check "no package was built from it" test -z "$pkg"
check "nothing was extracted" test -z "$(find "$tmp/wrong/build" -name NvInfer.h -print -quit)"
# Without makepkg's own check (--skipchecksums), prepare() still compares the
# pinned SHA-256 and calls a download incomplete or damaged, not another archive.
stub_reset
printf '%s\n' "$tmp/wrong.tar.zst" >"$stubdir/deliver"
mkdir -p "$tmp/sd-wrong2"
mkflags=(--skipchecksums)
build wrong2 SRCDEST="$tmp/sd-wrong2"
mkflags=()
check "a wrong download stops prepare() too" test "$status" -ne 0
check "it is called incomplete or damaged" logged "The download is incomplete or damaged: delete the copy of $name"
check "it is not called another archive" not logged "is not the archive this recipe packages"
# ~/Downloads: the exact file is used, with no download.
stub_reset
mkdir -p "$tmp/home2/Downloads"
cp "$dl/$name" "$tmp/home2/Downloads/$name"
cp "$dl/$name" "$tmp/home2/Downloads/TensorRT-other.tar.zst"
build dldir HOME="$tmp/home2"
built "makepkg -f -d uses the archive in ~/Downloads"
check "prepare() names that exact file" logged "NVIDIA_TRT_SRC=$tmp/home2/Downloads/$name (from default)"
check "it verified the checksum" logged "SHA-256 $sum verified"
check "nothing was fetched" test ! -e "$stubdir/calls"
# The environment wins over ~/Downloads, with no download either.
build envwins HOME="$tmp/home2" NVIDIA_TRT_SRC="$stage/good/TensorRT-11.4.0.106"
built "the environment's source wins over ~/Downloads"
check "it is the environment's" logged "(from environment)"
check "nothing was fetched" test ! -e "$stubdir/calls"
stub_reset

echo "== a tree, by selection.conf"
printf '# test selection\nNVIDIA_TRT_SRC=%s\n' "$stage/good/TensorRT-11.4.0.106" >"$recipe/selection.conf"
check "a selection.conf naming a source leaves no source in makepkg --printsrcinfo" \
    test -z "$(srcinfo | grep -E $'^\t(source|sha256sums|noextract) =' || true)"
build conf
built "makepkg -f -d builds from a tree in selection.conf"
check "the source came from selection.conf" logged "NVIDIA_TRT_SRC=$stage/good/TensorRT-11.4.0.106 (from selection.conf)"
check "it says a tree has no checksum" logged "an extracted tree: no checksum to verify"
check "the tree's library is packaged" grep -qxF "$r/lib/libnvinfer.so.11.4.0" <<<"$(bsdtar -tf "$pkg")"

echo "== failures"
printf 'NVIDIA_TRT_SRC=%s\nNVIDIA_TRT_SHA256=%064d\n' "$dl/$name" 0 >"$recipe/selection.conf"
build stale
check "a SHA-256 recorded by configure.sh that no longer matches stops the build" test "$status" -ne 0
check "it says to run configure.sh again" logged "changed since configure.sh --write"
rm -f "$recipe/selection.conf"

bad=$tmp/bad
mkdir -p "$bad"
cp "$dl/$name" "$bad/$name"
printf 'x' >>"$bad/$name"
build mismatch NVIDIA_TRT_SRC="$bad/$name"
check "a checksum mismatch stops the build" test "$status" -ne 0
check "it names both hashes" logged "SHA-256 mismatch: expected $sum, got $(sha256sum "$bad/$name" | cut -d' ' -f1)"
check "no package was built" test -z "$pkg"
check "nothing was extracted" test -z "$(find "$tmp/mismatch/build" -name NvInfer.h -print -quit)"

trt_tree "$stage/old/TensorRT-10.13.3.9" 10 13 3 9
build oldtree NVIDIA_TRT_SRC="$stage/old/TensorRT-10.13.3.9"
check "another version stops the build" test "$status" -ne 0
check "it names both versions" logged "holds TensorRT 10.13.3.9, but this recipe packages TensorRT 11.4.0.106"

echo "== no pinned SHA-256"
# unpin: empties _trt_sha256 in the copied PKGBUILD (no published checksum).
unpin() { sed -i "s/^_trt_sha256=.*/_trt_sha256=/" "$recipe/PKGBUILD"; }
unpin
not_pinned="(not pinned: NVIDIA publishes no checksum for this release; compare it with your download)"
build unpinned NVIDIA_TRT_SRC="$dl"
built "makepkg -f -d builds an unpinned archive"
check "prepare() prints its SHA-256 as not pinned" logged "SHA-256 $sum $not_pinned"
check "it does not claim the checksum was verified" not logged "verified"
printf 'NVIDIA_TRT_SRC=%s\nNVIDIA_TRT_SHA256=%s\n' "$dl/$name" "$sum" >"$recipe/selection.conf"
build unpinnedconf
built "makepkg -f -d builds an unpinned archive with the SHA-256 configure.sh recorded"
check "it says the SHA-256 is the recorded one, not pinned" \
    logged "SHA-256 $sum as configure.sh --write recorded it (not pinned: NVIDIA publishes no checksum for this release; compare it with your download)"
printf 'NVIDIA_TRT_SRC=%s\nNVIDIA_TRT_SHA256=%064d\n' "$dl/$name" 0 >"$recipe/selection.conf"
build unpinnedstale
check "unpinned, a recorded SHA-256 that no longer matches stops the build" test "$status" -ne 0
check "it says to run configure.sh again" logged "changed since configure.sh --write"
check "no package was built" test -z "$pkg"
rm -f "$recipe/selection.conf"
mkdir -p "$tmp/renamed"
cp "$dl/$name" "$tmp/renamed/TensorRT-copy.tar.zst"
build unpinnedrenamed NVIDIA_TRT_SRC="$tmp/renamed/TensorRT-copy.tar.zst"
check "unpinned, an archive under another name stops the build" test "$status" -ne 0
check "it names the expected archive" logged "is not the archive this recipe packages: expected $name, got TensorRT-copy.tar.zst"
# A SRCDEST symlink to a differently named file is still the download makepkg accepted.
mkdir -p "$tmp/sd-link"
ln -s "$tmp/renamed/TensorRT-copy.tar.zst" "$tmp/sd-link/$name"
build unpinnedlink SRCDEST="$tmp/sd-link"
built "makepkg -f -d builds an unpinned download that is a SRCDEST symlink to another name"

echo "== the ARM (aarch64) build"
pin "$dl/$name"
# NVIDIA publishes TensorRT 11.4.1.31 for ARM only: the fixture is that
# release, as the real ARM download is.
arm_name=TensorRT-Enterprise-11.4.1.31-Linux-aarch64-cuda-13.4-Release-external.tar.zst
arm_says=": this is the ARM (aarch64) build of TensorRT; download the Linux x86_64 one: $name from https://developer.nvidia.com/tensorrt/download"
arm_only="$arm_says (NVIDIA publishes TensorRT 11.4.1.31 for ARM only; the x86_64 one to download is 11.4.0.106)"
arm=$stage/arm/TensorRT-11.4.1.31
trt_tree "$arm" 11 4 1 31
rm "$arm/python/tensorrt-11.4.0.106-cp313-none-linux_x86_64.whl"
fake "$arm/python/tensorrt-11.4.1.31-cp313-none-linux_aarch64.whl"
mkdir -p "$tmp/armdl"
bsdtar --zstd -cf "$tmp/armdl/$arm_name" -C "$stage/arm" TensorRT-11.4.1.31
build armname NVIDIA_TRT_SRC="$tmp/armdl/$arm_name"
check "an archive named for aarch64 stops the build" test "$status" -ne 0
check "it says it is the ARM build, and which file to download" logged "$tmp/armdl/$arm_name$arm_only"
build armdir NVIDIA_TRT_SRC="$tmp/armdl"
check "a directory holding only it stops the build, naming it as the ARM build" logged "$tmp/armdl/$arm_name$arm_only"
mkdir -p "$tmp/armboth"
cp "$dl/$name" "$tmp/armdl/$arm_name" "$tmp/armboth/"
build armboth NVIDIA_TRT_SRC="$tmp/armboth"
built "a directory with one x86_64 and one ARM archive builds the x86_64 one"
check "prepare() names the ARM archive it set aside" logged "skipped $tmp/armboth/$arm_name (the ARM (aarch64) build)"
mkdir -p "$tmp/armren"
cp "$tmp/armdl/$arm_name" "$tmp/armren/$name"
build armrenamed NVIDIA_TRT_SRC="$tmp/armren/$name"
check "an aarch64 archive renamed to the x86_64 name stops the build" test "$status" -ne 0
check "it is named as the ARM build, by its contents" logged "$tmp/armren/$name$arm_says"
check "nothing was extracted from it" test -z "$(find "$tmp/armrenamed/build" -name NvInfer.h -print -quit)"
check "no package was built from it" test -z "$pkg"
ae=$stage/armelf/TensorRT-11.4.0.106
trt_tree "$ae" 11 4 0 106
rm -r "${ae:?}/python"
printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7\x00' >"$ae/lib/libnvinfer.so.11.4.0"
build armelf NVIDIA_TRT_SRC="$ae"
check "a tree whose libnvinfer is an aarch64 ELF stops the build" test "$status" -ne 0
check "it is named as the ARM build" logged "$ae$arm_says"
check "no package was built from the ARM tree" test -z "$pkg"

echo "== links out of the tree and special files"
hostile() { # hostile <root> <target>: a tree whose lib/libnvinfer.so links to <target>
    trt_tree "$1" 11 4 0 106
    rm "$1/lib/libnvinfer.so"
    ln -s "$2" "$1/lib/libnvinfer.so"
}
hostile "$stage/abs/TensorRT-11.4.0.106" /etc/shadow
mkdir -p "$tmp/absdl"
bsdtar --zstd -cf "$tmp/absdl/$name" -C "$stage/abs" TensorRT-11.4.0.106
pin "$tmp/absdl/$name"
build absar NVIDIA_TRT_SRC="$tmp/absdl/$name"
check "an archive with a link to /etc/shadow stops the build" test "$status" -ne 0
check "it names the link" logged "member TensorRT-11.4.0.106/lib/libnvinfer.so is a symbolic link to an absolute path (/etc/shadow)"
check "nothing was extracted from it" test -z "$(find "$tmp/absar/build" -name NvInfer.h -print -quit)"
check "no package was built from it" test -z "$pkg"
hostile "$stage/up/TensorRT-11.4.0.106" ../../../../etc
mkdir -p "$tmp/updl"
bsdtar --zstd -cf "$tmp/updl/$name" -C "$stage/up" TensorRT-11.4.0.106
pin "$tmp/updl/$name"
build upar NVIDIA_TRT_SRC="$tmp/updl/$name"
check "an archive with a link to ../../../../etc stops the build" test "$status" -ne 0
check "it says the link leads out of the tree" logged "is a symbolic link leading out of the TensorRT tree (../../../../etc)"
(
    cd "$stage/good" && {
        echo '#mtree'
        find TensorRT-11.4.0.106 -type d -printf './%p type=dir mode=0755\n'
        find TensorRT-11.4.0.106 -type f -printf './%p type=file mode=0644\n'
        find TensorRT-11.4.0.106 -type l -printf './%p type=link link=%l\n'
        echo './TensorRT-11.4.0.106/lib/pipe type=fifo mode=0644'
    } >"$tmp/fifo.mtree" && mkdir -p "$tmp/fifodl" && bsdtar --zstd -cf "$tmp/fifodl/$name" "@$tmp/fifo.mtree"
)
pin "$tmp/fifodl/$name"
build fifoar NVIDIA_TRT_SRC="$tmp/fifodl/$name"
check "an archive with a fifo stops the build" test "$status" -ne 0
check "it names the fifo" logged "member TensorRT-11.4.0.106/lib/pipe is a special file (fifo"
pin "$dl/$name"
build uptree NVIDIA_TRT_SRC="$stage/up/TensorRT-11.4.0.106"
check "a tree with a link to ../../../../etc stops the build" test "$status" -ne 0
check "it says the link leaves the tree" logged "lib/libnvinfer.so: a symbolic link leaving the TensorRT tree (../../../../etc)"
build abstree NVIDIA_TRT_SRC="$stage/abs/TensorRT-11.4.0.106"
check "a tree with a link to /etc/shadow stops the build" test "$status" -ne 0
check "it says the link is absolute" logged "lib/libnvinfer.so: a symbolic link to an absolute path (/etc/shadow)"
trt_tree "$stage/fifo/TensorRT-11.4.0.106" 11 4 0 106
mkfifo "$stage/fifo/TensorRT-11.4.0.106/lib/pipe"
build fifotree NVIDIA_TRT_SRC="$stage/fifo/TensorRT-11.4.0.106"
check "a tree with a fifo stops the build" test "$status" -ne 0
check "it names the fifo" logged "lib/pipe is a special file (a device, fifo or socket)"

echo "== a tree changed after configure.sh --write"
sw=$stage/swap/TensorRT-11.4.0.106
trt_tree "$sw" 11 4 0 106
(cd "$recipe" && env -u NVIDIA_TRT_SRC HOME="$tmp/home" ./configure.sh --src "$sw" --write >/dev/null)
check "configure.sh accepted the clean tree" grep -qx "NVIDIA_TRT_SRC=$sw" "$recipe/selection.conf"
rm "$sw/lib/libnvinfer.so.11.4.0"
ln -s /etc/shadow "$sw/lib/libnvinfer.so.11.4.0"
build swapped
check "a library swapped for a link to /etc/shadow after configure.sh stops the build" test "$status" -ne 0
check "it names the swapped library" logged "lib/libnvinfer.so.11.4.0: a symbolic link to an absolute path (/etc/shadow)"
check "no package was built from the swapped tree" test -z "$pkg"
rm -f "$recipe/selection.conf"

echo "== the targets/x86_64-linux-gnu layout"
tg=$stage/targets/TensorRT-11.4.0.106
trt_tree "$tg" 11 4 0 106
mkdir -p "$tg/targets/x86_64-linux-gnu"
mv "$tg/lib" "$tg/targets/x86_64-linux-gnu/lib"
ln -s targets/x86_64-linux-gnu/lib "$tg/lib"
build targets NVIDIA_TRT_SRC="$tg"
built "makepkg -f -d builds a tree whose lib/ links to targets/x86_64-linux-gnu/lib"
verbose=$(bsdtar -tvf "$pkg")
check "targets/ is packaged as shipped" grep -qE " $r/targets/x86_64-linux-gnu/lib/libnvinfer.so.11.4.0$" <<<"$verbose"
check "lib/ stays a link to it" link_to "$r/lib" targets/x86_64-linux-gnu/lib
check "the .pc file is in the linked directory" grep -qE " $r/targets/x86_64-linux-gnu/lib/pkgconfig/nvidia-tensorrt.pc$" <<<"$verbose"
check "the library path is lib/" grep -qx "LD_LIBRARY_PATH=$R/lib" <<<"$(bsdtar -xOf "$pkg" usr/share/nvidia-tensorrt/nvidia-tensorrt.env)"
check "the loader entry names lib/" test "$(bsdtar -xOf "$pkg" "$ldconf" | grep -v '^#')" = "$R/lib"
rm "$tg/lib"
build targetsonly NVIDIA_TRT_SRC="$tg"
built "makepkg -f -d builds a tree with targets/x86_64-linux-gnu/lib and no lib/"
envf=$(bsdtar -xOf "$pkg" usr/share/nvidia-tensorrt/nvidia-tensorrt.env)
check "the library path is then targets/x86_64-linux-gnu/lib" \
    grep -qx "LD_LIBRARY_PATH=$R/targets/x86_64-linux-gnu/lib" <<<"$envf"
check "the loader entry names it too" test "$(bsdtar -xOf "$pkg" "$ldconf" | grep -v '^#')" = "$R/targets/x86_64-linux-gnu/lib"
check "and the pkg-config path below it" \
    grep -qx "NVIDIA_TRT_PKG_CONFIG_PATH=$R/targets/x86_64-linux-gnu/lib/pkgconfig" <<<"$envf"
check "the .pc file's libdir is there" grep -qxF "libdir=\${prefix}/targets/x86_64-linux-gnu/lib" \
    <<<"$(bsdtar -xOf "$pkg" "$r/targets/x86_64-linux-gnu/lib/pkgconfig/nvidia-tensorrt.pc")"

pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile line is literal
printf 'NVIDIA_TRT_SRC=$(touch %s)\n' "$pwned" >"$recipe/selection.conf"
srcinfo >/dev/null 2>&1 || true
check "makepkg --printsrcinfo never executes a hostile selection.conf" test ! -e "$pwned"
build hostile
check "a hostile selection.conf stops the build" test "$status" -ne 0
check "it names the line" logged "selection.conf:1: the value of NVIDIA_TRT_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
rm -f "$recipe/selection.conf"

build relative NVIDIA_TRT_SRC=dl
check "a relative NVIDIA_TRT_SRC from the environment stops the build" test "$status" -ne 0
check "it says the path must be absolute" logged "environment: NVIDIA_TRT_SRC must be an absolute path"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
