#!/usr/bin/env bash
# Tests for nvidia-tensorrt/configure.sh, source.sh and selection.sh. The
# fixtures are FAKE: tiny text files with TensorRT's file names and a
# version header in its format, packed with bsdtar into .tar.zst archives,
# all under mktemp. The scripts run from a copy of nvidia-tensorrt/ under
# mktemp, so selection.conf is never written into the working tree. The
# copied PKGBUILD has the fake archive's SHA-256 pinned in place of the real
# one (configure.sh reads _trt_archive and _trt_sha256 from the PKGBUILD next
# to it); the fake archive carries the real archive's name.
# Usage: nvidia-tensorrt/tests/configure-test.sh. Exits non-zero on any
# failure, 77 when bsdtar is missing.
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
recipe=$(cd "$here/.." && pwd)

command -v bsdtar >/dev/null 2>&1 || { echo "skipped: bsdtar not found"; exit 77; }

# The real selection.conf (if any): its content must not change.
real_conf_state() { if [[ -e $recipe/selection.conf ]]; then sha256sum <"$recipe/selection.conf"; else echo absent; fi; }
real_conf_before=$(real_conf_state)

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
# version_header <file> <major> <minor> <patch> <build>: the 10.x/11.x style,
# NV_TENSORRT_* defined as TRT_*_ENTERPRISE.
version_header() {
    mkdir -p "$(dirname "$1")"
    {
        echo '#ifndef NV_INFER_VERSION_H'
        printf '#define TRT_%s_ENTERPRISE %s\n' MAJOR "$2" MINOR "$3" PATCH "$4" BUILD "$5"
        printf '#define NV_TENSORRT_%s TRT_%s_ENTERPRISE //!< TensorRT %s version.\n' \
            MAJOR MAJOR major MINOR MINOR minor PATCH PATCH patch BUILD BUILD build
        echo '#endif'
    } >"$1"
}
# trt_tree <root> [version...]: a fake TensorRT tree, 11.4.0.106 by default.
trt_tree() {
    local root=$1
    shift
    (($# == 4)) || set -- 11 4 0 106
    version_header "$root/include/NvInferVersion.h" "$@"
    fake "$root/include/NvInfer.h" "$root/include/NvOnnxParser.h" \
        "$root/lib/libnvinfer.so.11.4.0" "$root/lib/libnvinfer_plugin.so.11.4.0" \
        "$root/lib/libnvonnxparser.so.11.4.0" "$root/bin/trtexec" \
        "$root/python/tensorrt-11.4.0.106-cp313-none-linux_x86_64.whl" \
        "$root/samples/README.md" "$root/doc/Acknowledgements.txt"
    ln -s libnvinfer.so.11.4.0 "$root/lib/libnvinfer.so.11"
    ln -s libnvinfer.so.11 "$root/lib/libnvinfer.so"
}
pack() { # pack <archive> <dir> <top>: a .tar.zst of <dir>/<top>
    mkdir -p "$(dirname "$1")"
    bsdtar --zstd -cf "$1" -C "$2" "$3"
}
listing() { (cd "$1" && find . -printf '%p %s %T@\n' | sort); }

name=TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
stage=$tmp/stage
trt_tree "$stage/good/TensorRT-11.4.0.106"
dl=$tmp/dl
pack "$dl/$name" "$stage/good" TensorRT-11.4.0.106
archive=$dl/$name
sum=$(sha256sum "$archive" | cut -d' ' -f1)

# The scripts, copied: selection.conf goes next to them; the fake archive's
# SHA-256 is pinned in the copy.
trt=$tmp/nvidia-tensorrt
mkdir -p "$trt"
cp "$recipe/configure.sh" "$recipe/selection.sh" "$recipe/source.sh" "$recipe/PKGBUILD" "$trt/"
real_sum=$(sed -n 's/^_trt_sha256=//p' "$trt/PKGBUILD")
sed -i "s/^_trt_sha256=.*/_trt_sha256=$sum/" "$trt/PKGBUILD"
cfg=$trt/configure.sh
conf=$trt/selection.conf
# pin <archive>: pins that archive's SHA-256 in the copied PKGBUILD (for the
# fixtures that test what comes after the checksum); `pin "$archive"` restores.
pin() { sed -i "s/^_trt_sha256=.*/_trt_sha256=$(sha256sum "$1" | cut -d' ' -f1)/" "$trt/PKGBUILD"; }
check "the recipe pins the archive name the fixture uses" grep -qx "_trt_archive=$name" "$trt/PKGBUILD"
check "the recipe pins a 64-digit SHA-256" grep -qE '^[0-9a-f]{64}$' <<<"$real_sum"

# run [VAR=value...] -- <args...>: configure.sh with a fake HOME and no
# NVIDIA_TRT_SRC from the caller; output in $out, stdout alone in $stdout,
# status in $status.
out='' stdout='' status=0
run_env() {
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    stdout=$(env -u NVIDIA_TRT_SRC HOME="$tmp/home" "${vars[@]}" "$cfg" "$@" 2>"$tmp/stderr") || status=$?
    out=$stdout$'\n'$(cat "$tmp/stderr")
}
run() { run_env -- "$@"; }
passes() { ((status == 0)) || { echo "$out"; return 1; }; }
fails_with() { # fails_with <fragment>
    ((status != 0)) || { echo "unexpectedly succeeded: $out"; return 1; }
    says "$1" || { echo "$out"; return 1; }
}
head_is() { # head_is <expected first five lines of stdout>
    [[ $(head -n 5 <<<"$stdout") == "$1" ]] || { echo "got:"; head -n 5 <<<"$stdout"; return 1; }
}
features="features headers libs trtexec python samples"

echo "== a valid archive"
before=$(listing "$dl")
run --src "$archive"
check "the archive is valid" passes
check "the machine-readable lines come first" head_is "version 11.4.0.106
source $archive
layout archive
sha256 $sum
$features"
check "it says the checksum matches" says "checksum  SHA-256 matches the pinned $name"
check "it names the top directory" says "top directory: TensorRT-11.4.0.106"
check "it gives the save command" says "--src $archive --write"
check "nothing is written" test ! -e "$conf"
check "the download is untouched (nothing extracted)" test "$before" = "$(listing "$dl")"

echo "== a directory holding the archive"
run --src "$dl"
check "the directory is valid" passes
check "it resolves to the archive" head_is "version 11.4.0.106
source $archive
layout archive
sha256 $sum
$features"
mkdir -p "$tmp/home/Downloads"
cp "$archive" "$tmp/home/Downloads/"
run
check "the default source is ~/Downloads" passes
check "it says the default was used" says "from      the default (~/Downloads)"
check "it found the archive there" grep -qx "source $tmp/home/Downloads/$name" <<<"$stdout"
run_env NVIDIA_TRT_SRC="$archive" --
check "NVIDIA_TRT_SRC is a source" says "from      the environment (NVIDIA_TRT_SRC)"

echo "== a valid tree"
run --src "$stage/good/TensorRT-11.4.0.106"
check "the tree is valid" passes
check "a tree has no checksum" head_is "version 11.4.0.106
source $stage/good/TensorRT-11.4.0.106
layout tree
sha256 none
$features"
check "it says there is no checksum" says "an extracted tree: no checksum to verify"
run --src "$stage/good"
check "a directory holding one tree resolves to it" grep -qx "source $stage/good/TensorRT-11.4.0.106" <<<"$stdout"
minimal=$tmp/minimal
trt_tree "$minimal"
rm -rf "${minimal:?}/bin" "${minimal:?}/python" "${minimal:?}/samples"
run --src "$minimal"
check "a tree without the optional parts is valid" passes
check "it lists only headers and libs" grep -qx "features headers libs" <<<"$stdout"
check "it names the optional parts that are absent" says "absent    trtexec python samples (optional)"

echo "== errors"
two=$tmp/two
mkdir -p "$two"
cp "$archive" "$two/"
cp "$archive" "$two/TensorRT-11.4.0.106-other.tar.zst"
run --src "$two"
check "two archives are an error" fails_with "holds 2 TensorRT archives"
check "it lists both" says "$two/TensorRT-11.4.0.106-other.tar.zst"
check "no machine-readable line on an error" test -z "$stdout"

bad=$tmp/bad
mkdir -p "$bad"
cp "$archive" "$bad/$name"
printf 'x' >>"$bad/$name"
run --src "$bad/$name"
check "a checksum mismatch is an error" fails_with "SHA-256 mismatch: expected $sum, got $(sha256sum "$bad/$name" | cut -d' ' -f1)"
check "it says to download again" says "download it again from https://developer.nvidia.com/tensorrt/download"
other=$tmp/other
mkdir -p "$other"
pack "$other/TensorRT-renamed.tar.zst" "$tmp" minimal
run --src "$other/TensorRT-renamed.tar.zst"
check "another archive is not this recipe's" fails_with "is not the archive this recipe packages: expected $name"
cp "$archive" "$other/TensorRT-copy.tar.zst"
run --src "$other/TensorRT-copy.tar.zst"
check "a renamed archive with the pinned checksum is accepted" passes
check "it notes the other name" says "(the file is named TensorRT-copy.tar.zst)"

trt_tree "$stage/old/TensorRT-10.13.3.9" 10 13 3 9
run --src "$stage/old/TensorRT-10.13.3.9"
check "another version (tree) is an error" fails_with "holds TensorRT 10.13.3.9, but this recipe packages TensorRT 11.4.0.106"
pack "$tmp/oldar/TensorRT-10.13.3.9.Linux.x86_64-gnu.cuda-12.9.tar.zst" "$stage/old" TensorRT-10.13.3.9
run --src "$tmp/oldar"
check "another version (archive) is an error naming both" \
    fails_with "holds TensorRT 10.13.3.9, but this recipe packages TensorRT 11.4.0.106"

trt_tree "$stage/nohdr/TensorRT-11.4.0.106"
rm "$stage/nohdr/TensorRT-11.4.0.106/include/NvInfer.h" "$stage/nohdr/TensorRT-11.4.0.106/include/NvOnnxParser.h"
pack "$tmp/nohdr/$name" "$stage/nohdr" TensorRT-11.4.0.106
pin "$tmp/nohdr/$name"
run --src "$tmp/nohdr/$name"
check "missing headers are an error" fails_with "missing: include/NvInfer.h include/NvOnnxParser.h"
pin "$archive"
run --src "$stage/nohdr/TensorRT-11.4.0.106"
check "missing headers in a tree are an error" fails_with "missing: include/NvInfer.h include/NvOnnxParser.h"
trt_tree "$stage/nolib"
rm "$stage/nolib/lib/libnvonnxparser.so.11.4.0"
run --src "$stage/nolib"
check "a missing library is an error" fails_with "missing: lib/libnvonnxparser.so"
mkdir -p "$stage/nover/TensorRT-11.4.0.106/include"
fake "$stage/nover/TensorRT-11.4.0.106/include/NvInfer.h"
pack "$tmp/nover/$name" "$stage/nover" TensorRT-11.4.0.106
pin "$tmp/nover/$name"
run --src "$tmp/nover/$name"
check "an archive without NvInferVersion.h is not TensorRT" fails_with "no include/NvInferVersion.h in the archive"
pin "$archive"
mv "$tmp/nover/$name" "$tmp/nover/TensorRT-nover.tar.zst"
run --src "$tmp/nover/TensorRT-nover.tar.zst"
check "an unreadable other archive is reported as not this recipe's" \
    fails_with "is not the archive this recipe packages"
mkdir -p "$tmp/empty"
run --src "$tmp/empty"
check "an empty directory is an error" fails_with "holds no TensorRT archive"
run --src "$tmp/missing"
check "a missing source is an error" fails_with "$tmp/missing: not found"
fake "$tmp/notar.txt"
run --src "$tmp/notar.txt"
check "a file that is not a tar is an error" fails_with "not a tar archive"
run --bogus
check "an unknown option is a usage error" test "$status" = 2
run --show --write
check "--show with --write is a usage error" test "$status" = 2
check "no error wrote selection.conf" test ! -e "$conf"

echo "== links out of the tree and special files"
# hostile <dir> <target>: a tree whose lib/libnvinfer.so links to <target>.
hostile() {
    trt_tree "$1"
    rm "$1/lib/libnvinfer.so"
    ln -s "$2" "$1/lib/libnvinfer.so"
}
hostile "$stage/abs/TensorRT-11.4.0.106" /etc/shadow
pack "$tmp/abs/$name" "$stage/abs" TensorRT-11.4.0.106
pin "$tmp/abs/$name"
run --src "$tmp/abs/$name"
check "an archive with a link to an absolute path is refused" \
    fails_with "member TensorRT-11.4.0.106/lib/libnvinfer.so is a symbolic link to an absolute path (/etc/shadow); refusing the archive"
check "no machine-readable line for it" test -z "$stdout"
run --src "$stage/abs/TensorRT-11.4.0.106"
check "a tree with a link to an absolute path is refused" \
    fails_with "lib/libnvinfer.so: a symbolic link to an absolute path (/etc/shadow); refusing the tree"
hostile "$stage/up/TensorRT-11.4.0.106" ../../../../etc
pack "$tmp/up/$name" "$stage/up" TensorRT-11.4.0.106
pin "$tmp/up/$name"
run --src "$tmp/up/$name"
check "an archive with a link leading out of the tree is refused" \
    fails_with "member TensorRT-11.4.0.106/lib/libnvinfer.so is a symbolic link leading out of the TensorRT tree (../../../../etc)"
run --src "$stage/up/TensorRT-11.4.0.106"
check "a tree with a link leaving it is refused" \
    fails_with "lib/libnvinfer.so: a symbolic link leaving the TensorRT tree (../../../../etc); refusing the tree"
hostile "$stage/sib/TensorRT-11.4.0.106" ../../other/lib/libnvinfer.so.11.4.0
pack "$tmp/sib/$name" "$stage/sib" TensorRT-11.4.0.106
pin "$tmp/sib/$name"
run --src "$tmp/sib/$name"
check "an archive link out of the tree's top directory, though inside the archive, is refused" \
    fails_with "is a symbolic link leading out of the TensorRT tree (../../other/lib/libnvinfer.so.11.4.0)"
# Special files: a fifo in a tree; a device and a fifo in an archive, made
# from an mtree description (no root needed).
trt_tree "$stage/fifo/TensorRT-11.4.0.106"
mkfifo "$stage/fifo/TensorRT-11.4.0.106/lib/pipe"
run --src "$stage/fifo/TensorRT-11.4.0.106"
check "a tree with a fifo is refused" fails_with "lib/pipe is a special file (a device, fifo or socket); refusing the tree"
rm "$stage/fifo/TensorRT-11.4.0.106/lib/pipe"
for kind in char fifo; do
    (
        cd "$stage/fifo" && {
            echo '#mtree'
            find TensorRT-11.4.0.106 -type d -printf './%p type=dir mode=0755\n'
            find TensorRT-11.4.0.106 -type f -printf './%p type=file mode=0644\n'
            find TensorRT-11.4.0.106 -type l -printf './%p type=link link=%l\n'
            if [[ $kind == char ]]; then
                echo './TensorRT-11.4.0.106/lib/null type=char mode=0644 device=native,1,3'
            else
                echo './TensorRT-11.4.0.106/lib/pipe type=fifo mode=0644'
            fi
        } >"$tmp/$kind.mtree" && mkdir -p "$tmp/$kind" && bsdtar --zstd -cf "$tmp/$kind/$name" "@$tmp/$kind.mtree"
    )
    pin "$tmp/$kind/$name"
    run --src "$tmp/$kind/$name"
    check "an archive with a $kind member is refused" fails_with "is a special file ($kind: a device, fifo or socket); refusing the archive"
done
pin "$archive"

echo "== the targets/x86_64-linux-gnu layout"
tg=$stage/targets/TensorRT-11.4.0.106
trt_tree "$tg"
mkdir -p "$tg/targets/x86_64-linux-gnu"
mv "$tg/lib" "$tg/targets/x86_64-linux-gnu/lib"
ln -s targets/x86_64-linux-gnu/lib "$tg/lib"
run --src "$tg"
check "lib/ as a link to targets/x86_64-linux-gnu/lib is valid" passes
check "its libraries are found there" grep -qx "$features" <<<"$stdout"
pack "$tmp/targets/$name" "$stage/targets" TensorRT-11.4.0.106
pin "$tmp/targets/$name"
run --src "$tmp/targets/$name"
check "the same archive is valid" passes
pin "$archive"
rm "$tg/lib"
run --src "$tg"
check "targets/x86_64-linux-gnu/lib without lib/ is valid" passes

echo "== header styles"
# shellcheck source=source.sh
. "$recipe/source.sh"
check "numeric NV_TENSORRT_* defines" test "$(printf '#define NV_TENSORRT_MAJOR 11 //!< major\n#define NV_TENSORRT_MINOR 4\n#define NV_TENSORRT_PATCH 0\n#define NV_TENSORRT_BUILD 106\n' | trt_header_version)" = 11.4.0.106
check "TRT_*_ENTERPRISE defines alone" test "$(printf '#define TRT_%s_ENTERPRISE %s\n' MAJOR 11 MINOR 4 PATCH 0 BUILD 106 | trt_header_version)" = 11.4.0.106
check "no version defines give nothing" test -z "$(printf '#define FOO 1\n' | trt_header_version)"

echo "== --write and --show"
run --show
check "--show without a selection says so" says "no selection.conf ($conf)"
run --src "$dl" --write
check "--write saves an archive" passes
check "selection.conf holds the archive and its SHA-256" \
    test "$(grep -v '^#' "$conf")" = "NVIDIA_TRT_SRC=$archive"$'\n'"NVIDIA_TRT_SHA256=$sum"
check "--write still prints the machine-readable lines" grep -qx "sha256 $sum" <<<"$stdout"
check "no temporary file is left" test -z "$(find "$trt" -name '.selection.conf.*' -print -quit)"
run --show
check "--show prints the source" says "NVIDIA_TRT_SRC=$archive"
check "--show prints the SHA-256" says "NVIDIA_TRT_SHA256=$sum"
run
check "selection.conf is the source when --src is not given" says "from      $conf"
run --src "$stage/good" --write
check "--write saves a tree" passes
check "selection.conf holds the tree and no SHA-256" \
    test "$(grep -v '^#' "$conf")" = "NVIDIA_TRT_SRC=$stage/good/TensorRT-11.4.0.106"
run_env NVIDIA_TRT_SRC="$archive" -- --show
check "--show notes an environment override" says "note: NVIDIA_TRT_SRC is set in this environment"
cp "$conf" "$tmp/conf.saved"
run --src "$bad/$name" --write
check "a failed --write keeps the previous selection.conf" cmp -s "$conf" "$tmp/conf.saved"

echo "== selection.conf parsing"
pwned=$tmp/pwned
# shellcheck disable=SC2016 # the hostile line is literal
printf 'NVIDIA_TRT_SRC=$(touch %s)\n' "$pwned" >"$conf"
run --show
check "a hostile selection.conf is refused" says "the value of NVIDIA_TRT_SRC must not contain"
check "nothing in it was executed" test ! -e "$pwned"
printf 'NVIDIA_TRT_SRC=relative/path\n' >"$conf"
run
check "a relative path is refused" fails_with "selection.conf:1: NVIDIA_TRT_SRC must be an absolute path"
printf 'NVIDIA_TRT_SRC=%s\nNVIDIA_TRT_SHA256=XYZ\n' "$archive" >"$conf"
run --show
check "a malformed SHA-256 is refused" says "selection.conf:2: NVIDIA_TRT_SHA256 must be 64 lowercase hexadecimal digits"
printf 'NVIDIA_TRT_SRC=%s\nNVIDIA_TRT_SRC=%s\n' "$archive" "$archive" >"$conf"
run --show
check "a duplicate key is refused" says "selection.conf:2: NVIDIA_TRT_SRC is set twice"
printf 'MAXINE_AFX_SRC=%s\n' "$archive" >"$conf"
run --show
check "an unknown key is refused" says "unknown key MAXINE_AFX_SRC"
rm -f "$conf"
if (
    unset NVIDIA_TRT_SRC
    printf 'NVIDIA_TRT_SRC=/a\nNVIDIA_TRT_SHA256=%s\n' "$sum" >"$tmp/sel.conf"
    # shellcheck source=selection.sh
    . "$recipe/selection.sh"
    nvidia_trt_resolve "$tmp/sel.conf" /default
    [[ $nvidia_trt_src == /a && $nvidia_trt_src_from == sel.conf && $nvidia_trt_sha256 == "$sum" ]] || exit 1
    NVIDIA_TRT_SRC=/b nvidia_trt_resolve "$tmp/sel.conf" /default
    [[ $nvidia_trt_src == /b && $nvidia_trt_src_from == environment && -z $nvidia_trt_sha256 ]] || exit 1
    nvidia_trt_resolve "$tmp/none.conf" /default
    [[ $nvidia_trt_src == /default && $nvidia_trt_src_from == default ]]
); then
    ok "the precedence is environment > file > default, the file's SHA-256 only with its source"
else
    fail "the precedence is environment > file > default, the file's SHA-256 only with its source"
fi

check "the real recipe's selection.conf is untouched" test "$real_conf_before" = "$(real_conf_state)"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
