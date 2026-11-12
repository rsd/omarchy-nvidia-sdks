#!/usr/bin/env bash
# Tests for scripts/check-no-nvidia.sh and the hooks in .githooks/. Each case
# runs in a throwaway git repository under mktemp (its own index and
# history, never this repository's), with fake files generated here: nothing
# from NVIDIA is involved. The hook cases set core.hooksPath of the
# throwaway repository to this repository's .githooks/ and run real git
# commit, merge and push commands there (the push goes to a bare repository
# under mktemp).
# Usage: scripts/tests/check-no-nvidia-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
guard=$here/../check-no-nvidia.sh
hooks=$(cd "$here/../../.githooks" && pwd)

# Isolate from the caller's git: a hook exports GIT_INDEX_FILE and friends,
# and a global excludes file would change what --all sees.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The default core.excludesFile is $XDG_CONFIG_HOME/git/ignore, even without
# a global configuration.
export XDG_CONFIG_HOME=$tmp/xdg

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }

# Creates a fresh repository with no commits and prints its path. (It runs
# in a command substitution, so the name comes from mktemp, not a counter.)
new_repo() {
    local repo
    repo=$(mktemp -d "$tmp/repo.XXXXXX")
    git init -q -b main "$repo"
    printf 'recipes only\n' >"$repo/README.md"
    printf '%s\n' "$repo"
}

# A repository using this repository's hooks, with README.md committed
# through them.
hooked_repo() {
    local repo
    repo=$(new_repo)
    git -C "$repo" config core.hooksPath "$hooks"
    git -C "$repo" add README.md
    git -C "$repo" commit -q -m init >/dev/null 2>&1
    printf '%s\n' "$repo"
}

# expect <pass|fail> <description> <repo> <guard args...> [-- <expected path>]
# The guard must exit 0 (pass) or 1 (fail); for a failure, the expected path
# must be named in its output (a path with control characters as %q shows it).
expect() {
    local want=$1 desc=$2 repo=$3 out status
    shift 3
    local -a args=()
    while (($#)) && [[ $1 != -- ]]; do args+=("$1"); shift; done
    local path=
    if (($#)); then path=$2; fi
    [[ $path != *[[:cntrl:]]* ]] || printf -v path '%q' "$path"
    status=0
    out=$(cd "$repo" && "$guard" "${args[@]}" 2>&1) || status=$?
    if [[ $want == pass ]]; then
        if ((status == 0)); then ok "$desc"; else fail "$desc (exit $status): $out"; fi
    elif ((status != 1)); then
        fail "$desc (exit $status, want 1): $out"
    elif [[ -n $path ]] && ! grep -qF -- "$path:" <<<"$out"; then
        fail "$desc (path $path not reported): $out"
    else
        ok "$desc"
    fi
}

# stage_case <pass|fail> <description> <path> <generator command...>: writes
# the file with the generator (stdout to the file), stages it, runs --staged.
stage_case() {
    local want=$1 desc=$2 path=$3 repo
    shift 3
    repo=$(new_repo)
    mkdir -p "$(dirname "$repo/$path")"
    "$@" >"$repo/$path"
    git -C "$repo" add -f -- "$path" README.md
    expect "$want" "$desc" "$repo" --staged -- "$path"
}

# link_case <pass|fail> <description> <link path> <target>: a staged symlink.
link_case() {
    local want=$1 desc=$2 path=$3 target=$4 repo
    repo=$(new_repo)
    mkdir -p "$(dirname "$repo/$path")"
    ln -s -- "$target" "$repo/$path"
    git -C "$repo" add -f -- "$path"
    expect "$want" "$desc" "$repo" --staged -- "$path"
}

elf() { printf '\177ELF\002\001\001\000'; }
# The marker texts are put together at run time, so this file carries none.
corp() { printf '%s %s' NVIDIA CORPORATION; }

# refused <description> <repo> <git args...>: the git command must fail and
# HEAD must not move.
refused() {
    local desc=$1 repo=$2 before out status=0
    shift 2
    before=$(git -C "$repo" rev-parse -q --verify HEAD || true)
    out=$(git -C "$repo" "$@" 2>&1) || status=$?
    if ((status == 0)); then
        fail "$desc: git $* succeeded"
    elif [[ $(git -C "$repo" rev-parse -q --verify HEAD || true) != "$before" ]]; then
        fail "$desc: HEAD moved"
    elif ! grep -qF 'NVIDIA files must never be committed' <<<"$out"; then
        fail "$desc: git failed, but not through the guard: $out"
    else
        ok "$desc"
    fi
}

# accepted <description> <repo> <git args...>: the git command must succeed.
accepted() {
    local desc=$1 repo=$2 out
    shift 2
    if out=$(git -C "$repo" "$@" 2>&1); then ok "$desc"; else fail "$desc: $out"; fi
}

echo "== staged (the default), in a repository with no commits"
repo=$(new_repo)
mkdir -p "$repo/maxine-vfx"
printf '#!/bin/sh\necho hello\n' >"$repo/maxine-vfx/build.sh"
git -C "$repo" add README.md maxine-vfx/build.sh
expect pass "clean text files pass" "$repo"
expect pass "clean text files pass (--staged)" "$repo" --staged
expect pass "nothing staged passes" "$(new_repo)"

echo "== paths"
stage_case fail "a .so library fails" x.so printf 'not really a library\n'
stage_case fail "a versioned library fails" lib/libnvthing.so.1.2 printf 'x\n'
stage_case fail "a static library fails" lib/libthing.a printf 'x\n'
stage_case fail "a TensorRT model fails" m.engine.trtpkg printf 'fake model\n'
stage_case fail "a path under VideoFX/ fails" VideoFX/lib/a.txt printf 'text\n'
stage_case fail "a .pdf fails" licence.pdf printf 'not really a pdf\n'
stage_case fail "an SDK header fails" include/nvVideoEffects.h printf '/* fake */\n'
stage_case fail "an NGC download directory fails" nvvfxgreenscreen_v1.3.0.0_lib_linux/readme printf 'x\n'
stage_case fail "a nested NGC download directory fails" dl/vfx_sdk_core_v1.3.0.0_linux/readme printf 'x\n'
stage_case fail "the NGC configuration fails" home/.ngc/config printf '[CURRENT]\n'
stage_case pass "docs/libnvidia-notes.md is not a library" docs/libnvidia-notes.md printf '# notes\n'
stage_case pass "docs/nvvfx_vs_afx.md is not an NGC directory" docs/nvvfx_vs_afx.md printf '# notes\n'
stage_case pass "a file named like an NGC directory is not one" docs/nvvfxgreenscreen_v1.3.0.0_lib_linux.md printf '# notes\n'
stage_case pass "a path with a space passes" "my notes/a b.md" printf 'text\n'
stage_case fail "a .ngc under a directory with a space fails" "a b/.ngc/config" printf 'x\n'
stage_case fail "a .ngc under a directory with a newline fails" $'a\nb/.ngc/config' printf 'x\n'
stage_case fail "a VideoFX under a directory with a newline fails" $'a\nb/VideoFX/lib/x' printf 'x\n'
stage_case pass "a clean path with a newline passes" $'a\nb/notes.md' printf 'text\n'

echo "== paths: AR and Audio Effects SDKs"
for pkg in maxine-ar maxine-afx; do
    stage_case fail "$pkg/src/ (makepkg work directory) fails" "$pkg/src/notes.txt" printf 'x\n'
    stage_case fail "$pkg/pkg/ (makepkg work directory) fails" "$pkg/pkg/usr/share/x.txt" printf 'x\n'
    for f in PKGBUILD assemble.sh README.md tests/assemble-test.sh; do
        stage_case pass "the recipe $pkg/$f passes" "$pkg/$f" printf '# recipe\n'
    done
done
echo "== paths: an SDK unpacked straight into a recipe directory"
# The SDKs' top-level names (VideoFX/, ARSDK/, Audio_Effects_SDK/), e.g.
# maxine-afx/features/README.md, maxine-ar/lib/models/models.json. Text files
# with clean content, so only the path can refuse them.
for pkg in maxine-vfx maxine-ar maxine-afx; do
    for f in features/README.md samples/README.md samples/download_samples.sh \
        external/ThirdPartyLicenses.txt lib/models/models.json lib/models/add_custom_models.sh \
        include/notes.txt share/build_triton_client_lib.sh licenses/terms.txt nvafx/include/x.txt \
        bin/run.sh docs/index.html version.h Changelog.txt; do
        stage_case fail "an SDK file $pkg/$f fails" "$pkg/$f" printf 'plain text\n'
    done
    for f in PKGBUILD README.md assemble.sh configure.sh download.sh selection.sh \
        tests/assemble-test.sh tests/pkgbuild-test.sh; do
        stage_case pass "the recipe file $pkg/$f passes" "$pkg/$f" printf '# recipe\n'
    done
    stage_case fail "an SDK README.md as $pkg/README.md fails by its content" "$pkg/README.md" \
        printf 'NVIDIA %s\n====\n' "$(case $pkg in maxine-vfx) echo 'Video Effects SDK' ;;
            maxine-ar) echo 'Augmented Reality SDK' ;; *) echo 'AudioEffects SDK' ;; esac)"
done
stage_case pass "a top-level name elsewhere is not an SDK tree" docs/features/README.md printf '# notes\n'
stage_case pass "a top-level name under a recipe's tests/ is not an SDK tree" \
    maxine-afx/tests/lib/helper.sh printf '# recipe\n'
stage_case pass "a recipe file named like an SDK directory is not one" maxine-ar/libraries.md printf '# notes\n'

stage_case fail "a path under ARSDK/ fails" ARSDK/features/README.md printf 'text\n'
stage_case fail "a nested path under Audio_Effects_SDK/ fails" maxine-afx/Audio_Effects_SDK/version.txt printf 'text\n'
stage_case fail "an AR SDK header fails" include/nvAR.h printf '/* fake */\n'
stage_case fail "an AR SDK definitions header fails" include/nvAR_defs.h printf '/* fake */\n'
stage_case fail "a TensorRT model's .md5 sidecar fails" models/denoiser_48k.trtpkg.md5 printf '0123  x\n'
stage_case fail "the AR core download directory fails" dl/ar_sdk_core_v1.2.0.0_linux/readme printf 'x\n'
stage_case fail "an AR feature download directory fails" nvarfaceboxdetection_v1.2.0.0_lib_linux/readme printf 'x\n'
stage_case fail "the Audio Effects core download directory fails" \
    maxine_linux_audio_effects_sdk_v3.0.0/readme printf 'x\n'
stage_case fail "an Audio Effects library download directory fails" afx_denoiser_v3.0.0-lib/readme printf 'x\n'
stage_case fail "an Audio Effects model download directory fails" \
    dl/afx_studio_voice_v3.0.0-48k-sm120/readme printf 'x\n'
stage_case pass "maxine-afx/ is not an NGC directory" maxine-afx/tests/download-test.sh printf '# recipe\n'
stage_case pass "afx without _v<digit> is not an NGC directory" afx_notes/vendor.md printf '# notes\n'
stage_case pass "nvar without _v<digit> is not an NGC directory" nvarchive/notes.md printf '# notes\n'
stage_case pass "a file named like an AR download directory is not one" \
    docs/ar_sdk_core_v1.2.0.0_linux.md printf '# notes\n'

echo "== paths: the Optical Flow SDK"
of=nvidia-optical-flow
stage_case fail "$of/src/ (makepkg work directory) fails" "$of/src/of/include/x.txt" printf 'x\n'
stage_case fail "$of/pkg/ (makepkg work directory) fails" "$of/pkg/usr/share/x.txt" printf 'x\n'
for f in PKGBUILD README.md assemble.sh configure.sh selection.sh tests/configure-test.sh \
    tests/pkgbuild-test.sh; do
    stage_case pass "the recipe file $of/$f passes" "$of/$f" printf '# recipe\n'
done
# The SDK's top-level names and the installed tree's, as plain text files.
for f in NvOFInterface/notes.txt NvOFBasicSamples/README.md NvOFTracker/CMakeLists.txt \
    NvOFFRUC/notes.txt Common/External/FreeImage/licence-fi.txt include/notes.txt \
    fruc/include/notes.txt samples/README.md tracker/README.md licenses/terms.txt; do
    stage_case fail "an SDK file $of/$f fails" "$of/$f" printf 'plain text\n'
done
stage_case pass "a top-level name under the recipe's tests/ is not an SDK tree" \
    "$of/tests/include/helper.sh" printf '# recipe\n'
for d in Optical_Flow_SDK_5.0.7 optical_flow_sdk_5.0.7 OPTICAL_FLOW_SDK_5.0; do
    stage_case fail "an unpacked $d/ at the top fails" "$d/Read_Me.txt" printf 'plain text\n'
    stage_case fail "an unpacked $d/ in a recipe directory fails" "$of/$d/NvOFInterface/x.txt" \
        printf 'plain text\n'
    stage_case fail "an unpacked $d/ elsewhere fails" "docs/dl/$d/notes.txt" printf 'plain text\n'
done
stage_case pass "a file named like the SDK's directory is not one" docs/optical_flow_sdk_notes.md \
    printf '# notes\n'
stage_case fail "the Optical Flow SDK zip fails" "$of/optical_flow_sdk_5.0.7.zip" printf 'x\n'
for f in nvOpticalFlowCommon.h nvOpticalFlowCuda.h nvOpticalFlowD3D11.h NvFRUC.h NvOFTracker.h; do
    stage_case fail "the Optical Flow SDK header $f fails" "src/$f" printf '/* fake */\n'
done
stage_case fail "the FRUC library fails" lib/NvFRUC.so printf 'x\n'
stage_case fail "FRUC's bundled CUDA runtime fails" lib/libcudart.so.11.6.55 printf 'x\n'

echo "== paths: TensorRT"
trt=nvidia-tensorrt
stage_case fail "$trt/src/ (makepkg work directory) fails" "$trt/src/x/y.txt" printf 'x\n'
stage_case fail "$trt/pkg/ (makepkg work directory) fails" "$trt/pkg/usr/x.txt" printf 'x\n'
for f in PKGBUILD README.md configure.sh selection.sh source.sh tests/configure-test.sh \
    tests/pkgbuild-test.sh; do
    stage_case pass "the recipe file $trt/$f passes" "$trt/$f" printf '# recipe\n'
done
for d in include lib bin python samples data doc targets; do
    stage_case fail "a TensorRT file $trt/$d/notes.txt fails" "$trt/$d/notes.txt" printf 'plain text\n'
done
stage_case fail "the TensorRT tarball's targets/x86_64-linux-gnu/ fails" \
    "$trt/targets/x86_64-linux-gnu/include/notes.txt" printf 'plain text\n'
stage_case pass "a top-level name under the recipe's tests/ (targets/) is not an SDK tree" \
    "$trt/tests/targets/helper.sh" printf '# recipe\n'
stage_case pass "a top-level name under the recipe's tests/ is not an SDK tree" \
    "$trt/tests/data/helper.sh" printf '# recipe\n'
for f in NvInfer.h NvInferRuntime.h NvOnnxParser.h NvOnnxParserRuntime.h NvOnnxConfig.h; do
    stage_case fail "the TensorRT header $f fails" "src/$f" printf '/* fake */\n'
done
stage_case fail "an unpacked TensorRT-10.4.0.26/ at the top fails" TensorRT-10.4.0.26/notes.txt \
    printf 'plain text\n'
stage_case fail "an unpacked TensorRT-*/ in a recipe directory fails" \
    "$trt/TensorRT-10.4.0.26/notes.txt" printf 'plain text\n'
stage_case fail "an unpacked TensorRT-*/ elsewhere fails" docs/dl/TensorRT-10.4/a/notes.txt \
    printf 'plain text\n'
stage_case pass "a file named like the TensorRT directory is not one" docs/TensorRT-notes.md \
    printf '# notes\n'

echo "== content"
stage_case fail "ELF magic under an innocent name fails" tool.txt elf
stage_case fail "gzip data named notes.txt fails" notes.txt sh -c 'printf "hello\n" | gzip -c'
stage_case fail "an ar archive under an innocent name fails" data.txt printf '!<arch>\nmember/         0           0     0     644     2         `\nx\n'
mkdir -p "$tmp/tarsrc"
printf 'text\n' >"$tmp/tarsrc/member.txt"
stage_case fail "a POSIX tar under an innocent name fails" bundle.dat tar --format=ustar -cf - -C "$tmp/tarsrc" member.txt
stage_case fail "a NUL byte in the first 8 KiB fails" data.bin printf 'abc\000def\n'
stage_case fail "a text file over 1 MiB fails" big.txt sh -c 'head -c 1048577 /dev/zero | tr "\0" "a"'
copyright_header() { printf '/*\n * Copyright (c) 2020 %s.  All rights reserved.\n */\nint x;\n' "$(corp)"; }
stage_case fail "an NVIDIA copyright line under an innocent name fails" include/effects.h copyright_header
stage_case fail "a mixed-case NVIDIA copyright line fails" src/proxy.cpp \
    printf '# Copyright 2020 NVIDIA %s\n' Corporation
stage_case fail "the licence agreement's title on its own line fails" terms.txt \
    printf 'NVIDIA %s\n\n1. Definitions\n' 'SOFTWARE LICENSE AGREEMENT'
stage_case pass "prose naming the licence agreement passes" docs/rules.md \
    printf 'The NVIDIA %s (8.5) forbids redistribution.\n' 'Software License Agreement'
stage_case fail "the SDK Changelog's first line fails" notes.txt \
    printf '%s (v1.3.0.0)\n----\n- new\n' Changelog
stage_case fail "install_feature.sh's header fails" fetch.sh \
    printf '#!/bin/bash\n# Feature %s for VFX SDK\n' 'Installation Script'
stage_case fail "the AR SDK's install_feature.sh header fails" fetch.sh \
    printf '#!/bin/bash\n\n# Feature %s for ARSDK\n' 'Installation Script'
stage_case fail "the Audio Effects SDK's download_features.sh header fails" fetch.sh \
    printf '#!/bin/bash\n\n# Set NGC %s if needed\n' 'org/team below'
stage_case fail "the AR SDK README's title fails" notes.md \
    printf 'NVIDIA %s\n====\n' 'Augmented Reality SDK'
stage_case fail "the Audio Effects SDK README's title fails" notes.md \
    printf 'See the guide.\n\nNVIDIA %s\n====\n' 'AudioEffects SDK'
stage_case pass "prose naming the AR SDK passes" docs/ar.md \
    printf 'The NVIDIA %s is packaged by maxine-ar.\n' 'Augmented Reality SDK'

repo=$(new_repo)
head -c 1048576 /dev/zero | tr '\0' 'a' >"$repo/exact.txt"
git -C "$repo" add exact.txt
expect pass "a text file of exactly 1 MiB passes" "$repo" --staged

repo=$(new_repo)
printf 'staged content\n' >"$repo/notes.txt"
git -C "$repo" add notes.txt
elf >"$repo/notes.txt"
expect pass "--staged checks the staged content, not the work tree" "$repo" --staged

echo "== symbolic links, submodules, type changes, renames"
link_case pass "a symlink inside the repository passes" docs/readme README.md
link_case pass "a symlink up to the repository root passes" docs/a/readme ../../README.md
link_case fail "a symlink to an absolute path fails" docs/passwd /etc/passwd
link_case fail "a symlink leaving the repository fails" docs/up ../../outside
link_case fail "a symlink leaving through a newline directory fails" $'a\nb/up' ../../x

repo=$(new_repo)
other=$(hooked_repo)
git -C "$repo" update-index --add --cacheinfo "160000,$(git -C "$other" rev-parse HEAD),sub"
expect fail "a submodule (gitlink) fails" "$repo" --staged -- sub

repo=$(new_repo)
ln -s README.md "$repo/tool"
git -C "$repo" add README.md tool
git -C "$repo" commit -q -m init
rm "$repo/tool"
elf >"$repo/tool"
git -C "$repo" add tool
check_status=$(git -C "$repo" diff --cached --name-status)
[[ $check_status == T* ]] || fail "fixture: the change is not a type change: $check_status"
expect fail "a symlink replaced by an ELF (type change T) fails" "$repo" --staged -- tool

repo=$(new_repo)
elf >"$repo/notes.txt"
git -C "$repo" add README.md notes.txt
git -C "$repo" commit -q -m init
git -C "$repo" mv notes.txt renamed.txt
expect fail "a renamed offending file fails" "$repo" --staged -- renamed.txt
repo=$(new_repo)
printf 'x\n' >"$repo/x.txt"
git -C "$repo" add README.md x.txt
git -C "$repo" commit -q -m init
mkdir "$repo/lib"
git -C "$repo" mv x.txt lib/libx.so
expect fail "a rename to a library name fails" "$repo" --staged -- lib/libx.so
git -C "$repo" rm -q --cached lib/libx.so
expect pass "a deletion passes" "$repo" --staged

echo "== --all"
repo=$(new_repo)
printf 'ignored.bin\n' >"$repo/.gitignore"
git -C "$repo" add README.md .gitignore
expect pass "--all passes a clean tree" "$repo" --all
elf >"$repo/ignored.bin"
expect pass "--all does not report ignored files" "$repo" --all
printf 'fake\n' >"$repo/untracked.so"
expect fail "--all catches an untracked, not ignored file" "$repo" --all -- untracked.so
expect pass "--staged ignores the untracked file" "$repo" --staged
repo=$(new_repo)
ln -s /etc/os-release "$repo/os-release"
expect fail "--all catches an absolute symlink" "$repo" --all -- os-release
repo=$(new_repo)
git init -q "$repo/nested"
printf 'x\n' >"$repo/nested/file"
expect fail "--all catches a nested repository" "$repo" --all -- nested
repo=$(new_repo)
printf '#define X 1\n// Copyright 2021 %s\n' "$(corp)" >"$repo/fx.h"
expect fail "--all checks the content" "$repo" --all -- fx.h

echo "== --range"
repo=$(new_repo)
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
elf >"$repo/tool.txt"
git -C "$repo" add tool.txt
git -C "$repo" commit -q -m bad
git -C "$repo" rm -q tool.txt
git -C "$repo" commit -q -m removed >/dev/null 2>&1
expect pass "--range of the first commit passes" "$repo" --range HEAD~2
expect fail "--range sees a file a later commit deleted" "$repo" --range HEAD~2..HEAD -- tool.txt
expect fail "--range with --not --remotes and no remote checks every commit" "$repo" \
    --range main --not --remotes=origin -- tool.txt
expect pass "--range of the deletion alone passes" "$repo" --range HEAD~1..HEAD
status=0
(cd "$repo" && "$guard" --range no-such-rev >/dev/null 2>&1) || status=$?
if ((status == 2)); then ok "--range of an unknown revision exits 2"; else fail "--range of an unknown revision exits $status, want 2"; fi

echo "== hooks: git commit"
repo=$(hooked_repo)
ok "a clean first commit goes through the hook"
printf 'more\n' >>"$repo/README.md"
git -C "$repo" add README.md
accepted "a clean commit goes through the hook" "$repo" commit -q -m clean
elf >"$repo/tool.txt"
git -C "$repo" add tool.txt
refused "git commit of a staged ELF is refused" "$repo" commit -q -m bad
git -C "$repo" rm -q --cached tool.txt
rm "$repo/tool.txt"

printf 'notes\n' >"$repo/notes.txt"
git -C "$repo" add notes.txt
accepted "a clean notes.txt is committed" "$repo" commit -q -m notes
elf >"$repo/notes.txt"
refused "git commit -a of a modified file turned ELF is refused" "$repo" commit -q -a -m bad
refused "git commit <path> of an unstaged ELF is refused" "$repo" commit -q -m bad notes.txt
printf 'notes, edited\n' >"$repo/notes.txt"
git -C "$repo" add notes.txt
printf '%s\n' "/* Copyright 2020 $(corp) */" >"$repo/notes.txt"
refused "git commit <path> checks the work tree file, not the clean staged one" "$repo" \
    commit -q -m bad notes.txt
printf 'notes, edited again\n' >"$repo/notes.txt"
accepted "a clean git commit -a passes" "$repo" commit -q -a -m edit
git -C "$repo" update-index --add --cacheinfo "160000,$(git -C "$repo" rev-parse HEAD),sub"
refused "git commit of a submodule is refused" "$repo" commit -q -m sub
git -C "$repo" rm -q --cached sub

echo "== hooks: git merge (pre-merge-commit)"
repo=$(hooked_repo)
git -C "$repo" worktree add -q -b side "$tmp/side.wt" >/dev/null 2>&1
elf >"$tmp/side.wt/tool.txt"
git -C "$tmp/side.wt" add tool.txt
accepted "the side branch commits with --no-verify" "$tmp/side.wt" commit -q --no-verify -m side
printf 'main\n' >"$repo/main.txt"
git -C "$repo" add main.txt
accepted "main moves on through the hook" "$repo" commit -q -m main
refused "a merge bringing the side branch's ELF is refused" "$repo" merge -q --no-ff -m merge side
git -C "$repo" merge --abort >/dev/null 2>&1 || true
git -C "$tmp/side.wt" rm -q tool.txt
printf 'side\n' >"$tmp/side.wt/side.txt"
git -C "$tmp/side.wt" add side.txt
git -C "$tmp/side.wt" commit -q -m clean >/dev/null 2>&1
accepted "a merge of a cleaned side branch passes" "$repo" merge -q --no-ff -m merge side

echo "== hooks: git push (pre-push)"
remote=$tmp/remote.git
git init -q --bare "$remote"
repo=$(hooked_repo)
git -C "$repo" remote add origin "$remote"
elf >"$repo/tool.txt"
git -C "$repo" add tool.txt
git -C "$repo" commit -q --no-verify -m bad
git -C "$repo" rm -q tool.txt
git -C "$repo" commit -q -m removed >/dev/null 2>&1
refused "pushing a new branch whose history holds an ELF is refused" "$repo" push -q origin main
if git -C "$remote" rev-parse -q --verify refs/heads/main >/dev/null; then
    fail "the refused push created main on the remote"
else
    ok "the refused push left the remote empty"
fi
expect fail "--range main --not --remotes=origin finds it with no remote-tracking ref" "$repo" \
    --range main --not --remotes=origin -- tool.txt

repo=$(hooked_repo)
git -C "$repo" remote add origin "$remote"
accepted "pushing a clean new branch passes" "$repo" push -q origin main
printf 'more\n' >>"$repo/README.md"
git -C "$repo" commit -q -a -m more >/dev/null 2>&1
accepted "pushing a clean update passes" "$repo" push -q origin main
pushed=$(git -C "$repo" rev-parse HEAD)
printf 'x\n' >"$repo/libx.so"
git -C "$repo" add -f libx.so
git -C "$repo" commit -q --no-verify -m bad
refused "pushing an update that adds a library is refused" "$repo" push -q origin main
if [[ $(git -C "$remote" rev-parse refs/heads/main) == "$pushed" ]]; then
    ok "the remote keeps the last clean commit"
else
    fail "the refused push moved the remote"
fi

echo "== usage"
status=0
(cd "$(new_repo)" && "$guard" --bogus >/dev/null 2>&1) || status=$?
if ((status == 2)); then ok "an unknown option exits 2"; else fail "an unknown option exits $status, want 2"; fi
status=0
(cd "$(new_repo)" && "$guard" --range >/dev/null 2>&1) || status=$?
if ((status == 2)); then ok "--range without a revision exits 2"; else fail "--range without a revision exits $status, want 2"; fi

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
