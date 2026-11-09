#!/bin/sh
# Tests for os-release-shim. Usage: test.sh <path to os-release-shim.so>
# (`make test` builds the shim and runs this). Needs a C compiler, and uses
# cat, grep and python3 when present. Exits non-zero on any failure.
# The sh -c scripts below are single-quoted on purpose: their arguments
# arrive as $1, $2 and are expanded by the inner shell, not this one.
# shellcheck disable=SC2016
set -u

here=$(cd "$(dirname "$0")" && pwd)
shim=${1:?usage: test.sh <path to os-release-shim.so>}
case $shim in /*) ;; *) shim=$(pwd)/$shim ;; esac
[ -f "$shim" ] || { echo "no such file: $shim" >&2; exit 2; }
out=${OUT:-$(dirname "$shim")}
cc=${CC:-cc}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake=$tmp/fake-os-release
printf 'NAME="Shim Test"\nID=oma-shim-test\nVERSION_ID="1"\n' >"$fake"

fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # check <description> <command...>: passes when the command succeeds
    desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}

# Runs a command with the shim preloaded and the replacement configured.
with_shim() { env LD_PRELOAD="$shim" OMA_BROADCAST_OS_RELEASE="$fake" "$@"; }

echo "== build the test program"
"$cc" -O2 -Wall -Wextra -Werror -std=gnu11 -o "$out/shim-test" "$here/shim-test.c" || exit 2

echo "== the test program without the shim (checks the test itself)"
check "shim-test passthrough, no preload" "$out/shim-test" passthrough "$tmp"

echo "== every entry point with the shim"
check "shim-test redirect" with_shim "$out/shim-test" redirect "$tmp"

echo "== unset, empty, relative or missing replacement: nothing is redirected"
check "OMA_BROADCAST_OS_RELEASE unset" \
    env -u OMA_BROADCAST_OS_RELEASE LD_PRELOAD="$shim" "$out/shim-test" passthrough "$tmp"
check "OMA_BROADCAST_OS_RELEASE empty" \
    env LD_PRELOAD="$shim" OMA_BROADCAST_OS_RELEASE= "$out/shim-test" passthrough "$tmp"
warn=$(cd "$tmp" && env LD_PRELOAD="$shim" OMA_BROADCAST_OS_RELEASE=fake-os-release \
    "$out/shim-test" passthrough "$tmp" 2>&1 >/dev/null)
check "OMA_BROADCAST_OS_RELEASE relative (even if it exists in the cwd)" \
    env -C "$tmp" LD_PRELOAD="$shim" OMA_BROADCAST_OS_RELEASE=fake-os-release "$out/shim-test" passthrough "$tmp"
check "a relative value prints a warning" \
    sh -c 'printf "%s" "$1" | grep -q "not an absolute path"' sh "$warn"
check "a missing replacement falls back to the real file" \
    env LD_PRELOAD="$shim" OMA_BROADCAST_OS_RELEASE="$tmp/missing" "$out/shim-test" passthrough "$tmp"

echo "== ordinary programs"
check "cat /etc/os-release shows the replacement" \
    sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" cat /etc/os-release)" = "$(cat "$2")" ]' sh "$shim" "$fake"
check "grep ^ID= /etc/os-release finds the replacement" \
    sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" grep ^ID= /etc/os-release)" = "ID=oma-shim-test" ]' sh "$shim" "$fake"
if [ -r /etc/hostname ]; then
    check "cat /etc/hostname is untouched" \
        sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" cat /etc/hostname)" = "$(cat /etc/hostname)" ]' sh "$shim" "$fake"
fi
if command -v python3 >/dev/null 2>&1; then
    check "python3 open() shows the replacement" \
        sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" python3 -I -c "print(open(\"/etc/os-release\").read(), end=\"\")")" = "$(cat "$2")" ]' sh "$shim" "$fake"
    check "python3 os.open(dir_fd=/etc, \"os-release\") reads the real file" \
        sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" python3 -I -c "
import os
d = os.open(\"/etc\", os.O_RDONLY | os.O_DIRECTORY)
f = os.open(\"os-release\", os.O_RDONLY, dir_fd=d)
print(os.read(f, 65536).decode(), end=\"\")
")" = "$(cat /etc/os-release)" ]' sh "$shim" "$fake"
    check "python3 creates a file with the requested mode" \
        sh -c 'env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" python3 -I -c "
import os, stat, sys
os.umask(0)
p = sys.argv[1] + \"/py-created\"
os.close(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640))
sys.exit(0 if stat.S_IMODE(os.stat(p).st_mode) == 0o640 else 1)
" "$3"' sh "$shim" "$fake" "$tmp"
else
    echo "skip python3 not found"
fi

echo "== children do not inherit the preload"
# The witness must not rely on getenv in a process that may have loaded the
# shim (the shim strips its own copy), so the child cat reads the environment
# it was started with from /proc/self/environ. The preloaded parent is sh
# (bash), which defines its own getenv/unsetenv.
check "LD_PRELOAD is empty in a child" \
    sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" sh -c "cat /proc/self/environ | tr \"\\\\0\" \"\\\\n\" | grep -c ^LD_PRELOAD=")" = "0" ]' sh "$shim" "$fake"
check "a child does not see the replacement" \
    sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" sh -c "cat /etc/os-release")" = "$(cat /etc/os-release)" ]' sh "$shim" "$fake"
check "OMA_BROADCAST_OS_RELEASE is kept" \
    sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" sh -c "printenv OMA_BROADCAST_OS_RELEASE")" = "$2" ]' sh "$shim" "$fake"

echo "== the process stays in the caller's namespaces"
for ns in user mnt; do
    check "same $ns namespace" \
        sh -c '[ "$(env LD_PRELOAD="$1" OMA_BROADCAST_OS_RELEASE="$2" readlink /proc/self/ns/$3)" = "$(readlink /proc/self/ns/$3)" ]' sh "$shim" "$fake" "$ns"
done

if [ "$fails" -eq 0 ]; then
    echo "PASS"
else
    echo "FAILED: $fails check(s)"
    exit 1
fi
