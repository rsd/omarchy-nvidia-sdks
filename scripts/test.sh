#!/usr/bin/env bash
# Runs every check of this repository that needs no GPU, no network and no
# NVIDIA download: shellcheck, the PKGBUILD's syntax and metadata, the shim
# test, the fixture tests (assemble.sh, configure.sh and the selection.conf
# parser, download.sh against a fake ngc, env.sh, the licence guard and its hooks, makepkg builds of the
# PKGBUILD against a fake SDK tree) and the
# licence guard over the whole tree. Build output goes to mktemp, never into
# the working tree.
#
#   scripts/test.sh                      # shellcheck from PATH
#   SHELLCHECK=/path/to/shellcheck scripts/test.sh
#
# Exits non-zero when any check fails.
set -uo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
cd "$top" || exit 2

shellcheck=${SHELLCHECK:-$(command -v shellcheck || true)}
if [[ -z $shellcheck || ! -x $shellcheck ]]; then
    echo "shellcheck not found: install it or set SHELLCHECK=/path/to/shellcheck" >&2
    exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failed=()
run() { # run <name> <command...>
    local name=$1
    shift
    echo "== $name"
    if "$@"; then
        echo "-- ok: $name"
    else
        echo "-- FAIL: $name"
        failed+=("$name")
    fi
}

scripts=(
    .githooks/pre-commit
    .githooks/pre-merge-commit
    .githooks/pre-push
    scripts/check-no-nvidia.sh
    scripts/test.sh
    scripts/tests/check-no-nvidia-test.sh
    scripts/tests/env-sh-test.sh
    scripts/tests/pkgbuild-fixture-test.sh
    maxine-vfx/assemble.sh
    maxine-vfx/configure.sh
    maxine-vfx/selection.sh
    maxine-vfx/tests/assemble-test.sh
    maxine-vfx/tests/configure-test.sh
    maxine-vfx/tests/download-test.sh
    tools/os-release-shim/test.sh
    tools/maxine-probe/env.sh
)
[[ -f maxine-vfx/download.sh ]] && scripts+=(maxine-vfx/download.sh)

# -x follows the sourced maxine-vfx/selection.sh (source-path=SCRIPTDIR).
run "shellcheck (scripts)" "$shellcheck" -x "${scripts[@]}"
# makepkg defines the PKGBUILD's variables (SC2034: assigned but unused,
# SC2154: referenced but unassigned, e.g. $srcdir) and runs each function in
# a fresh directory (SC2164: cd without a fallback).
run "shellcheck (PKGBUILD)" "$shellcheck" -x -s bash -e SC2034,SC2154,SC2164 maxine-vfx/PKGBUILD
run "bash -n PKGBUILD" bash -n maxine-vfx/PKGBUILD
if command -v makepkg >/dev/null 2>&1; then
    run "makepkg --printsrcinfo" sh -c 'cd maxine-vfx && makepkg --printsrcinfo >/dev/null'
else
    echo "== makepkg --printsrcinfo: skipped (makepkg not found)"
fi
run "os-release shim test" env -u LD_PRELOAD -u MAXINE_OS_RELEASE -u MAXINE_OS_RELEASE_DEBUG \
    -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
    make -s -C tools/os-release-shim OUT="$tmp/shim" test
run "assemble.sh fixture tests" maxine-vfx/tests/assemble-test.sh
run "configure.sh and selection.conf tests" maxine-vfx/tests/configure-test.sh
run "download.sh tests (fake ngc)" maxine-vfx/tests/download-test.sh
run "env.sh tests" scripts/tests/env-sh-test.sh
run "licence guard and hook tests" scripts/tests/check-no-nvidia-test.sh
# Exit 77: a tool it needs (makepkg, fakeroot, bsdtar) is missing.
pkgbuild_test() {
    local status=0
    scripts/tests/pkgbuild-fixture-test.sh || status=$?
    ((status == 0 || status == 77))
}
run "PKGBUILD fixture build" pkgbuild_test
run "licence guard (--all)" scripts/check-no-nvidia.sh --all

if ((${#failed[@]} > 0)); then
    printf 'FAILED: %s\n' "${failed[@]}"
    exit 1
fi
echo "all checks passed"
