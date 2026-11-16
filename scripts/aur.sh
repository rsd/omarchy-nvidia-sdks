#!/usr/bin/env bash
# Makes the AUR copy of a recipe: a PKGBUILD that builds without this
# working tree. The recipe's PKGBUILD reads its helpers (selection.sh,
# assemble.sh, source.sh, the os-release shim's source, the documents it
# installs) from the directory above it; an AUR clone holds only its own
# files. The AUR copy fetches them instead, from this repository at one
# pinned commit:
#
#   source+=("omarchy-nvidia-sdks::git+https://github.com/rsd/omarchy-nvidia-sdks.git#commit=<sha>")
#
# with the SHA-256 makepkg computes for it (of `git archive` of that commit),
# and reads them from $srcdir/omarchy-nvidia-sdks. Nothing else changes.
# Nothing from NVIDIA is in the copy or in the pinned commit: the SDK still
# comes from each user's own download.
#
#   scripts/aur.sh --recipe DIR              # prints the AUR PKGBUILD
#   scripts/aur.sh --recipe DIR --srcinfo    # prints its .SRCINFO
#   scripts/aur.sh --recipe DIR --aur AURDIR # writes PKGBUILD, .SRCINFO and
#                                            # LICENSE (0BSD) into AURDIR, the
#                                            # top of a git clone of the AUR
#                                            # repository; commits nothing
#   scripts/aur.sh --recipe DIR --check AURDIR
#                                            # fails, with a diff, when
#                                            # AURDIR's files are not those
#                                            # --aur would write
#
# DIR is a recipe directory: maxine-vfx, maxine-ar, maxine-afx,
# nvidia-optical-flow or nvidia-tensorrt.
#
# The pinned commit is HEAD, and the PKGBUILD transformed is HEAD's, not the
# working tree's. The script refuses when HEAD is not contained in
# origin/main (as last fetched: this script never fetches), when the recipe
# directory or a file the PKGBUILD reads through $_repo differs from HEAD in
# the working tree or the index, or when a line it replaces is missing.
#
# The .SRCINFO is `LC_ALL=C makepkg --printsrcinfo` of the generated
# PKGBUILD alone in an empty directory, with an empty environment apart from
# PATH and an empty HOME: no MAXINE_*/NVIDIA_* variable, no selection.conf
# and no ~/Downloads copy can change it.
#
# For tests only: --from-git REPO takes the PKGBUILD and the pinned commit
# from REPO's HEAD instead, fetched as git+file://REPO, without the origin
# check.
#
# Exit status: 0 done (or up to date), 1 refused or stale, 2 usage or tool
# error.
set -euo pipefail

prog=${0##*/}
top=$(cd "$(dirname "$0")/.." && pwd)

name=omarchy-nvidia-sdks
public_url=https://github.com/rsd/omarchy-nvidia-sdks
recipes=(maxine-vfx maxine-ar maxine-afx nvidia-optical-flow nvidia-tensorrt)

usage() {
    echo "usage: $prog --recipe DIR [--srcinfo | --aur AURDIR | --check AURDIR] [--from-git REPO]" >&2
    echo "       DIR: ${recipes[*]}" >&2
    exit 2
}
die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}

recipe='' mode=print aur='' from_git=''
while (($#)); do
    case $1 in
        --recipe | --aur | --check | --from-git)
            (($# >= 2)) || usage
            case $1 in
                --recipe) [[ -z $recipe ]] || usage; recipe=${2%/} ;;
                --aur | --check) [[ $mode == print ]] || usage; mode=${1#--} aur=$2 ;;
                --from-git) [[ -z $from_git ]] || usage; from_git=$2 ;;
            esac
            shift 2
            ;;
        --srcinfo)
            [[ $mode == print ]] || usage
            mode=srcinfo
            shift
            ;;
        *) usage ;;
    esac
done
[[ -n $recipe ]] || usage
known=0
for r in "${recipes[@]}"; do [[ $recipe == "$r" ]] && known=1; done
((known)) || usage

for tool in git makepkg sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$prog: $tool not found" >&2; exit 2; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The repository the PKGBUILD and the commit come from, and the URL makepkg
# fetches the helpers from.
if [[ -n $from_git ]]; then
    repo=$(cd -- "$from_git" 2>/dev/null && pwd -P) || die "$from_git: no such directory"
    url=git+file://$repo
else
    repo=$top
    url=git+$public_url.git
fi
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git repository"
commit=$(git -C "$repo" rev-parse --verify "HEAD^{commit}") || die "$repo has no HEAD commit"
git -C "$repo" cat-file -e "$commit:$recipe/PKGBUILD" 2>/dev/null ||
    die "$recipe/PKGBUILD is not in commit $commit"
git -C "$repo" show "$commit:$recipe/PKGBUILD" >"$tmp/PKGBUILD.in"

if [[ -z $from_git ]]; then
    # Published: the AUR fetches the commit from GitHub, so it must be there.
    git -C "$repo" rev-parse --verify -q origin/main >/dev/null ||
        die "no origin/main: the pinned commit must be on GitHub's main"
    git -C "$repo" merge-base --is-ancestor "$commit" origin/main ||
        die "HEAD ($commit) is not in origin/main: push it first (this script does not fetch)"
fi

# The files the PKGBUILD reads through $_repo ("$_repo/<path>"), and the
# recipe directory: they must be HEAD's, so that what the AUR builds is what
# was tested here.
# shellcheck disable=SC2016 # $_repo is the PKGBUILD's text, not ours
mapfile -t helpers < <(grep -o '"\$_repo/[^"]*"' "$tmp/PKGBUILD.in" | sed 's|^"\$_repo/||; s|"$||' | sort -u)
((${#helpers[@]} > 0)) || die "$recipe/PKGBUILD reads nothing through \$_repo: nothing to pin"
for h in "${helpers[@]}"; do
    git -C "$repo" cat-file -e "$commit:$h" 2>/dev/null || die "$recipe/PKGBUILD reads $h, which is not in commit $commit"
done
if [[ -z $from_git ]]; then
    if ! git -C "$repo" diff --quiet HEAD -- "$recipe" "${helpers[@]}" ||
        ! git -C "$repo" diff --cached --quiet HEAD -- "$recipe" "${helpers[@]}"; then
        git -C "$repo" status --short -- "$recipe" "${helpers[@]}" >&2
        die "the files above differ from HEAD: commit them (and push) first"
    fi
fi

# The checksum makepkg computes for a git source pinned by commit: the
# SHA-256 of `git archive --format tar <commit>` (makepkg's calc_checksum_git).
sum=$(git -c core.abbrev=no -C "$repo" archive --format tar "$commit" | sha256sum)
sum=${sum%% *}
[[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "$prog: cannot compute the checksum of $commit" >&2; exit 2; }

# replace <old> <new>: replaces the one occurrence of the exact text <old>
# in the PKGBUILD being generated; refuses when there is none or several.
pkgbuild=$(<"$tmp/PKGBUILD.in")
replace() {
    local old=$1 new=$2 rest
    rest=${pkgbuild/"$old"/}
    if [[ $rest == "$pkgbuild" ]]; then
        die "$recipe/PKGBUILD has no text to replace:"$'\n'"$old"
    fi
    if [[ ${rest/"$old"/} != "$rest" ]]; then
        die "$recipe/PKGBUILD has the text to replace more than once:"$'\n'"$old"
    fi
    pkgbuild=${pkgbuild/"$old"/"$new"}
}
# replace_all <old> <new>: replaces every occurrence, of which there must be
# at least one.
replace_all() {
    [[ $pkgbuild == *"$1"* ]] || die "$recipe/PKGBUILD has no text to replace:"$'\n'"$1"
    pkgbuild=${pkgbuild//"$1"/"$2"}
}

# The TensorRT recipe downloads its archive itself (in the download case):
# makepkg -o would fetch it too.
fetch_note=''
[[ $recipe != nvidia-tensorrt ]] ||
    fetch_note="
# With no manual source set, \`makepkg -o\` also downloads the TensorRT
# archive; \`NVIDIA_TRT_SRC=<your copy> makepkg -o --noprepare\` does not."

replace "# The package is built from this working tree (the directory above), not
# from a git clone, so nothing has to be committed to build it." \
"# This copy is generated for the AUR by scripts/aur.sh of
# $public_url (documentation:
# $public_url/blob/$commit/README.md).
# The recipe's helpers (selection.sh, assemble.sh, configure.sh, the
# os-release shim's source, ...) come from that repository at the commit
# pinned in source=(); makepkg checks it out into src/$name.
# \"This directory\" below is the directory of this PKGBUILD: selection.conf
# is read there. configure.sh is
# src/$name/$recipe/configure.sh, which
# \`makepkg -o --noprepare\` fetches; run it from this directory with
# --conf selection.conf, as below, so that it writes the selection.conf
# this PKGBUILD reads. The environment variables work without it.$fetch_note"

replace "# The recipe's helpers (its scripts, the shim's source, the documents it
# installs): this repository's working tree, resolved at build time.
_repo=\$(realpath -- \"\$startdir/..\")" \
"# The recipe's helpers (its scripts, the shim's source, the documents it
# installs): $public_url at the commit
# below, fetched by makepkg (source=). Relative to \$srcdir, where makepkg
# runs every function: \$srcdir is not set yet when makepkg reads this file.
_repo=$name
_commit=$commit"

# The build examples: run in the AUR clone, with the fetched configure.sh.
replace "# Build (from $recipe/), e.g.:" "# Build (in the directory of this PKGBUILD), e.g.:"
replace_all "#   ./configure.sh " "#   src/$name/$recipe/configure.sh --conf selection.conf "

# The source entry, after every other assignment of source= (the TensorRT
# recipe sets it conditionally): just before the install root, which every
# recipe sets after them.
root_line=$(grep -m1 '^_root=/opt/' <<<"$pkgbuild") || die "$recipe/PKGBUILD has no _root=/opt/... line"
replace "$root_line" \
"# The helpers, pinned: makepkg verifies the checksum of \`git archive\` of the
# commit.
source+=(\"$name::$url#commit=\$_commit\")
sha256sums+=('$sum')
makedepends+=('git')

$root_line"

printf '%s\n' "$pkgbuild" >"$tmp/PKGBUILD"
# shellcheck disable=SC2016 # $startdir is the PKGBUILD's text
if grep -n 'startdir/\.\.\|realpath -- "\$startdir' "$tmp/PKGBUILD" >&2; then
    die "the generated PKGBUILD still reads the working tree (lines above)"
fi

# srcinfo <dir>: the .SRCINFO of <dir>/PKGBUILD, alone in an empty
# directory, in an empty environment.
srcinfo() {
    local work
    work=$(mktemp -d "$tmp/srcinfo.XXXXXX")
    mkdir "$work/recipe" "$work/home"
    cp -- "$1/PKGBUILD" "$work/recipe/PKGBUILD"
    (cd "$work/recipe" && env -i PATH="$PATH" HOME="$work/home" LC_ALL=C makepkg --printsrcinfo) ||
        { echo "$prog: makepkg --printsrcinfo failed" >&2; exit 2; }
}
srcinfo "$tmp" >"$tmp/.SRCINFO"

cat >"$tmp/LICENSE" <<'EOF'
Copyright (c) 2026 Raul Dias <raul@dias.com.br>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
EOF

files=(PKGBUILD .SRCINFO LICENSE)

# aur_dir: the absolute path of $aur, which must be the top of a git work
# tree (a clone of the AUR repository), not a directory inside one.
aur_dir() {
    local dir git_top
    if ! dir=$(cd -- "$aur" 2>/dev/null && pwd -P) ||
        ! git_top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) ||
        [[ $(cd -- "$git_top" && pwd -P) != "$dir" ]]; then
        die "$aur is not the top of a git clone (git clone ssh://aur@aur.archlinux.org/<pkgbase>.git)"
    fi
    printf '%s\n' "$dir"
}
# extra <dir>: fails when <dir> holds anything but .git and the files: an
# AUR repository holds exactly what is pushed.
extra() {
    local f found=0
    while IFS= read -r -d '' f; do
        f=${f##*/}
        case $f in .git | PKGBUILD | .SRCINFO | LICENSE) continue ;; esac
        echo "$prog: $1/$f is not part of the AUR package" >&2
        found=1
    done < <(find "$1" -mindepth 1 -maxdepth 1 -print0)
    ((!found)) || die "remove the files above from $1 first"
}

case $mode in
    print) cat "$tmp/PKGBUILD" ;;
    srcinfo) cat "$tmp/.SRCINFO" ;;
    aur)
        dir=$(aur_dir)
        extra "$dir"
        for f in "${files[@]}"; do
            cp -- "$tmp/$f" "$dir/.$f.tmp"
            mv -f -- "$dir/.$f.tmp" "$dir/$f"
        done
        # The .SRCINFO written is that of the PKGBUILD written.
        srcinfo "$dir" >"$tmp/again"
        cmp -s "$tmp/again" "$dir/.SRCINFO" || die "$dir/.SRCINFO is not that of $dir/PKGBUILD"
        echo "wrote ${files[*]} into $dir (commit $commit); review, commit and push there"
        ;;
    check)
        dir=$(aur_dir)
        stale=0
        for f in "${files[@]}"; do
            if [[ ! -f $dir/$f ]]; then
                echo "$prog: $dir/$f does not exist" >&2
                stale=1
            elif ! diff -u --label "$dir/$f" --label "generated" "$dir/$f" "$tmp/$f"; then
                stale=1
            fi
        done
        extra "$dir"
        ((!stale)) || die "$dir is stale: run $prog --recipe $recipe --aur $aur"
        echo "$dir is up to date (commit $commit)"
        ;;
esac
