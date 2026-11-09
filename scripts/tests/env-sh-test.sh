#!/usr/bin/env bash
# Tests for tools/maxine-probe/env.sh with a fake SDK tree and a fake
# environment file under mktemp (MAXINE_VFX_ENV_FILE): the installed package,
# if any, is never read.
# Usage: scripts/tests/env-sh-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
envsh=$here/../../tools/maxine-probe/env.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }

# path_with <env file> [MAXINE_VFX_ROOT]: LD_LIBRARY_PATH after sourcing env.sh
# in a clean shell, then the names it leaves behind (none expected).
path_with() {
    # The inner script is single-quoted on purpose: the inner shell expands it.
    # shellcheck disable=SC2016
    env -i PATH="$PATH" MAXINE_VFX_ENV_FILE="$1" ${2:+MAXINE_VFX_ROOT="$2"} \
        bash -c 'set -u; source "$1"; printf "%s\n" "$LD_LIBRARY_PATH"; declare -F _maxine_vfx_env || true' _ "$envsh"
}
expect() { # expect <description> <want> <got>
    if [[ $3 == "$2" ]]; then ok "$1"; else fail "$1: got '$3', want '$2'"; fi
}

root=$tmp/sdk
mkdir -p "$root/lib" "$root/features/nvvfxzeta/lib" "$root/features/nvvfxalpha/lib" \
    "$root/features/nvvfxnolib/include"
built=$root/lib:$root/features/nvvfxalpha/lib:$root/features/nvvfxzeta/lib:$root/external/cuda/lib:$root/external/tensorrt/lib

expect "a tree without the package: every features/*/lib, sorted" "$built" \
    "$(path_with "$tmp/none.env" "$root")"

R=/opt/nvidia/maxine/videofx
printf '# comment\nMAXINE_VFX_ROOT=%s\nMAXINE_VFX_LIBRARY_PATH=%s/lib:%s/features/nvvfxgreenscreen/lib\nLD_LIBRARY_PATH=x\n' \
    "$R" "$R" "$R" >"$tmp/pkg.env"
expect "with the package and MAXINE_VFX_ROOT unset, the package's path" \
    "$R/lib:$R/features/nvvfxgreenscreen/lib" "$(path_with "$tmp/pkg.env")"
expect "with the package and MAXINE_VFX_ROOT equal to its root, the package's path" \
    "$R/lib:$R/features/nvvfxgreenscreen/lib" "$(path_with "$tmp/pkg.env" "$R")"
expect "with the package and another MAXINE_VFX_ROOT, the tree's path" "$built" \
    "$(path_with "$tmp/pkg.env" "$root")"

status=0
bash "$envsh" >/dev/null 2>&1 || status=$?
expect "running it instead of sourcing it exits 2" 2 "$status"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
