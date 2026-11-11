#!/usr/bin/env bash
# Builds a Maxine AR SDK tree from the user's own NVIDIA download, for
# the maxine-ar PKGBUILD (prepare()). Nothing is downloaded and the
# source is never modified.
#
#   assemble.sh --src DIR --dest DIR --version 1.2.0.0 \
#       [--archs "sm_120 sm_89" | --archs all] [--features all | "f1 f2"] [--state FILE]
#   assemble.sh --scan --src DIR --version 1.2.0.0
#
# Two source layouts are accepted (docs/download.md):
#   tree mode      DIR or DIR/ARSDK is an assembled SDK tree (it holds
#                  lib/libnvARPose.so), e.g. a previous user-prefix install.
#                  It is copied (reflinks where the filesystem allows), and
#                  lib/models/ is pruned to the selected GPU architectures.
#   download mode  the directories as `ngc ... download-version` creates them:
#                  ARSDK_linux_<ver>.tgz (bare, or in ar_sdk_core_v<ver>_linux/),
#                  <feature>_v<ver>_lib_linux/*.tar.gz and
#                  <feature>_v<ver>_models_linux_sm<N>/*.
#
# The SDK tree is written directly into DEST (DEST/lib, DEST/features, ...),
# which must not exist or be empty. A source holding both an SDK tree and
# NGC downloads is refused: which one is meant is not guessed.
#
# Symbolic links: a link to a directory, or to an existing file outside the
# tree, is refused (it would package a link into the builder's home, and an
# engine cache removed through it would be the user's own). Dangling links
# are kept as shipped (the AR SDK 1.2.0.0 core has none; the VFX SDK's cuDNN
# headers point into Debian's /etc/alternatives) and counted in the summary.
#
# Features: the features present in the source are, in tree mode, every
# features/<f>/ with lib/*.so, in download mode every
# nvar*_v<MAJOR.MINOR>.*_lib_linux/*.tar.gz. --features all (the default)
# assembles every one of them; a list (spaces or commas) assembles exactly
# those, each of which must be present, and leaves the others out (the
# summary lists them as "present, not selected"). In tree mode a feature left
# out is removed from features/ of the copy; its model files cannot be told
# apart from the others' and stay in lib/models (a note says so). At least
# one feature is needed.
#
# Architectures: --archs takes sm_120, sm120 or 120 (the compute capability
# without the dot), spaces or commas between entries (default sm_120), or
# `all` alone, which keeps every architecture found. In tree mode a model
# file belongs to an architecture when an underscore-delimited field of its
# name is a known SM number (face_detection_multiprofile_120.engine.trtpkg is
# sm_120);
# files whose name carries none are kept and listed in a note. In download
# mode a model file belongs to the architecture of its models_linux_sm<N>
# directory; each models directory used must hold at least one regular file
# and nothing else (no subdirectories), and two files of the same name from
# different directories must be identical. Only the models of the selected
# features count.
#
# --state FILE receives two KEY=value lines on success, the packaged
# features and architectures as comma-separated lists, e.g.
#   MAXINE_AR_FEATURES=nvarfaceboxdetection,nvarlandmarkdetection
#   MAXINE_AR_ARCHS=sm_120
#
# The result is verified: version header, core libraries, one library per
# feature, models for every selected architecture. The summary on stdout
# lists the features, the architectures and the model count and size per
# architecture; warnings and notes go to stderr.
#
# --scan writes nothing and assembles nothing: it runs the layout detection
# and its refusals (both layouts, unrecognised or mismatching download
# directories, links in a tree) and prints only these lines on stdout,
# for maxine-ar/configure.sh:
#   layout=tree|download
#   version=<the SDK version: the tree's share/arsdk_version.h, or the
#            core tarball's name>
#   source=<the SDK tree, or the core tarball>
#   feature=<name> archs=<comma-separated sm_N list, or - for none>
#            one line per feature present, sorted by name; in tree mode
#            archs=? (model files are not tied to a feature in a tree)
#   archs=<comma-separated sm_N list of every model present, or ->
#   models_unknown=<model files whose name carries no architecture>
# No feature present is not an error for --scan (no feature= line).
set -euo pipefail

prog=${0##*/}
die() {
    printf '%s: %s\n' "$prog" "$*" >&2
    exit 1
}
warn() { printf '%s: WARNING: %s\n' "$prog" "$*" >&2; }
note() { printf '%s: note: %s\n' "$prog" "$*" >&2; }
usage() {
    echo "usage: $prog --src DIR --dest DIR --version X.Y.Z.W" \
        "[--archs \"sm_120 sm_89\" | all] [--features all | \"f1 f2\"] [--state FILE]" >&2
    echo "       $prog --scan --src DIR --version X.Y.Z.W" >&2
    exit 2
}

src='' dest='' version='' archs_arg=sm_120 features_arg=all state='' scan=0
while (($#)); do
    case $1 in
        --scan)
            scan=1
            shift
            ;;
        --src | --dest | --version | --archs | --features | --state)
            (($# >= 2)) || usage
            case $1 in
                --src) src=$2 ;;
                --dest) dest=$2 ;;
                --version) version=$2 ;;
                --archs) archs_arg=$2 ;;
                --features) features_arg=$2 ;;
                --state) state=$2 ;;
            esac
            shift 2
            ;;
        -h | --help) usage ;;
        *) usage ;;
    esac
done
if ((scan)); then
    [[ -n $src && -n $version && -z $dest && -z $state ]] || usage
else
    [[ -n $src && -n $dest && -n $version ]] || usage
fi

[[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
    die "--version must look like 1.2.0.0, got '$version'"
major_minor=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}

# Lists split on spaces or commas; duplicates are dropped, order is kept.
split_list() {
    local word
    local -A seen=()
    local -a words
    read -r -a words <<<"${1//,/ }"
    for word in "${words[@]}"; do
        [[ -n ${seen[$word]:-} ]] && continue
        seen[$word]=1
        printf '%s\n' "$word"
    done
}
# Sorted, one per line; nothing for no arguments.
sort_numbers() { (($# == 0)) || printf '%s\n' "$@" | sort -n -u; }
sort_names() { (($# == 0)) || printf '%s\n' "$@" | LC_ALL=C sort -u; }
in_list() { # in_list <word> <list...>
    local word=$1 item
    shift
    for item in "$@"; do [[ $item == "$word" ]] && return 0; done
    return 1
}

# The GPU architectures: numbers (120), or every one found (all=1).
mapfile -t arch_words < <(split_list "$archs_arg")
((${#arch_words[@]} > 0)) || die "--archs is empty"
all=0 sms=()
for word in "${arch_words[@]}"; do
    if [[ $word == all ]]; then
        ((${#arch_words[@]} == 1)) ||
            die "'all' must be the only --archs entry, got '$archs_arg'"
        all=1
    elif [[ $word =~ ^(sm_?)?([1-9][0-9]{1,2})$ ]]; then
        n=${BASH_REMATCH[2]}
        in_list "$n" "${sms[@]}" || sms+=("$n")
    else
        die "invalid architecture '$word': use sm_120, sm120 or 120 (the compute" \
            "capability without the dot), or all"
    fi
done

# The features: every one present (all=1), or the listed ones.
mapfile -t feature_words < <(split_list "$features_arg")
((${#feature_words[@]} > 0)) || die "--features is empty"
all_features=0 wanted=()
for f in "${feature_words[@]}"; do
    if [[ $f == all ]]; then
        ((${#feature_words[@]} == 1)) ||
            die "'all' must be the only --features entry, got '$features_arg'"
        all_features=1
    elif [[ $f =~ ^[A-Za-z0-9_-]+$ ]]; then
        wanted+=("$f")
    else
        die "invalid feature name '$f'"
    fi
done

# SM numbers recognised in model file names, plus any selected one (a GPU
# newer than this list).
declare -A known_sm=()
for n in 50 52 53 60 61 62 70 72 75 80 86 87 89 90 100 101 103 110 120 121 "${sms[@]}"; do
    known_sm[$n]=1
done
# Sets file_sms to the SM numbers among the underscore-delimited fields of
# a file name (a last field such as 120.engine.trtpkg counts as 120).
file_sms=()
name_sms() {
    local field
    local -a fields
    file_sms=()
    IFS=_ read -r -a fields <<<"$1"
    for field in "${fields[@]}"; do
        field=${field%%.*}
        if [[ -n ${known_sm[$field]:-} ]] && ! in_list "$field" "${file_sms[@]}"; then
            file_sms+=("$field")
        fi
    done
}

# $(realpath ...) would drop a trailing newline and name another directory.
[[ $src != *$'\n'* ]] ||
    die "the source path $(printf '%q' "$src") contains a newline, which is not supported: rename the directory"
[[ -d $src ]] || die "source directory not found: $src"
src=$(realpath -- "$src")
if ((!scan)); then
    if [[ -e $dest ]]; then
        [[ -d $dest ]] || die "--dest exists and is not a directory: $dest"
        [[ -z $(find "$dest" -mindepth 1 -maxdepth 1 -print -quit) ]] ||
            die "--dest must not exist or be empty: $dest"
    fi
    dest=$(realpath -m -- "$dest")
fi

# Layout detection.
tree='' core_tgz=''
for candidate in "$src" "$src/ARSDK"; do
    if [[ -f $candidate/lib/libnvARPose.so ]]; then
        tree=$(realpath -- "$candidate")
        break
    fi
done
if [[ -n $tree ]]; then
    # A tree next to NGC downloads: which one is meant is not guessed.
    shopt -s nullglob
    downloads=("$src"/ar_sdk_core_v* "$src"/ARSDK_linux_*.tgz "$src"/nvar*_lib_linux)
    shopt -u nullglob
    if ((${#downloads[@]} > 0)); then
        die "$src holds both an SDK tree ($tree) and NGC downloads (${downloads[*]##*/})." \
            "Move one of them away, or point MAXINE_AR_SRC (--src) at the one you mean."
    fi
else
    for candidate in "$src/ARSDK_linux_$version.tgz" \
        "$src/ar_sdk_core_v${version}_linux/ARSDK_linux_$version.tgz"; do
        if [[ -f $candidate ]]; then
            core_tgz=$candidate
            break
        fi
    done
fi
if [[ -z $tree && -z $core_tgz ]]; then
    die "no Maxine AR SDK found in $src. Looked for an SDK tree" \
        "($src/lib/libnvARPose.so or $src/ARSDK/lib/libnvARPose.so) and for the" \
        "core download ($src/ARSDK_linux_$version.tgz or" \
        "$src/ar_sdk_core_v${version}_linux/ARSDK_linux_$version.tgz)." \
        "See docs/download.md."
fi

# check_links <root>: refuses a symbolic link to a directory, to an existing
# file outside <root>, or a dangling relative link that leaves <root>; counts
# the dangling links, which are kept as shipped. <root> is a canonical path.
dangling_links=0 dangling_alternatives=0
check_links() {
    local root=$1 link rel target resolved
    while IFS= read -r -d '' link; do
        rel=${link#"$root"/}
        target=$(readlink -- "$link")
        if [[ -d $link ]]; then
            die "$rel in $root is a symbolic link to a directory ($target): refused, so that" \
                "nothing outside the tree is packaged or removed through it. Use a copy of the" \
                "directory, or point MAXINE_AR_SRC (--src) at a tree without directory links."
        elif [[ -e $link ]]; then
            resolved=$(realpath -e -- "$link")
            case $resolved in
                "$root"/*) ;;
                *) die "$rel in $root is a symbolic link to $resolved, outside the tree: refused." \
                    "Replace it with the file itself." ;;
            esac
        else
            if [[ $target != /* ]]; then
                resolved=$(realpath -m -- "$link")
                case $resolved in
                    "$root"/*) ;;
                    *) die "$rel in $root is a dangling symbolic link leaving the tree ($target): refused." ;;
                esac
            fi
            dangling_links=$((dangling_links + 1))
            [[ $target != /etc/alternatives/* ]] || dangling_alternatives=$((dangling_alternatives + 1))
        fi
    done < <(find "$root" -type l -print0)
}

# header_version <file>: prints the SDK version a arsdk_version.h defines.
header_version() {
    local header=$1 part value
    local -a parts=()
    [[ -f $header ]] || die "missing share/arsdk_version.h in ${header%/share/*}"
    for part in MAJOR MINOR RELEASE BUILD; do
        value=$(awk -v key="NVIDIA_AR_SDK_VERSION_$part" \
            '$1 == "#define" && $2 == key { print $3; exit }' "$header")
        [[ $value =~ ^[0-9]+$ ]] || die "share/arsdk_version.h does not define NVIDIA_AR_SDK_VERSION_$part"
        parts+=("$value")
    done
    (IFS=.; echo "${parts[*]}")
}

# comma_archs <n>...: sm_N,sm_M sorted by number, or - for none.
comma_archs() {
    local n out=''
    while IFS= read -r n; do out+=${out:+,}sm_$n; done < <(sort_numbers "$@")
    echo "${out:--}"
}

# select_features: from the features present (sorted), the selected ones
# (all, or exactly the listed ones, each of which must be present) and the
# ones left out.
selected=() left_out=()
select_features() {
    local f
    local -a missing=()
    selected=() left_out=()
    if ((all_features)); then
        selected=("${present[@]}")
        return 0
    fi
    for f in "${wanted[@]}"; do
        in_list "$f" "${present[@]}" || missing+=("$f")
    done
    if ((${#missing[@]} > 0)); then
        if [[ $mode == tree ]]; then
            die "feature(s) not present in the SDK tree $tree: ${missing[*]} (no" \
                "features/<feature>/lib/*.so; present: ${present[*]:-none}). An SDK tree is used" \
                "as it is: to add a feature, build from an NGC download instead (NGC:" \
                "nvidia/maxine/${missing[0]}:${version}_lib_linux). See docs/download.md."
        fi
        local fetch=''
        for f in "${missing[@]}"; do
            fetch+=" ngc registry model download-version \"nvidia/maxine/$f:${version}_lib_linux\" --dest \"$src\";"
        done
        die "feature(s) not present in $src: ${missing[*]} (present: ${present[*]:-none})." \
            "Fetch with your own NGC CLI:${fetch} plus its models for each architecture," \
            "nvidia/maxine/<feature>:${version}_models_linux_sm<N>, if it has any. See docs/download.md."
    fi
    mapfile -t selected < <(sort_names "${wanted[@]}")
    for f in "${present[@]}"; do
        in_list "$f" "${selected[@]}" || left_out+=("$f")
    done
}

# The assembled model files per architecture (newline-separated names under
# lib/models), the files without an SM number (tree mode), and the
# architectures the source has models for (of the selected features, in
# download mode).
declare -A arch_files=()
unknown_models=() source_sms=() source_models=0 present=()

if [[ -n $tree ]]; then
    mode=tree
    if ((!scan)); then
        # A copy into itself would recurse. (DEST inside a download directory
        # is fine: makepkg's src/ sits next to a download beside the PKGBUILD.)
        case $dest/ in
            "$tree"/*) die "--dest must not be inside the SDK tree $tree" ;;
        esac
    fi
    check_links "$tree"
    # The features present: every features/<f>/ with lib/*.so.
    shopt -s nullglob
    for dir in "$tree"/features/*/; do
        dir=${dir%/}
        libs=("$dir"/lib/*.so)
        ((${#libs[@]} == 0)) || present+=("${dir##*/}")
    done
    shopt -u nullglob
    mapfile -t present < <(sort_names "${present[@]}")
    if ((scan)); then
        got=$(header_version "$tree/share/arsdk_version.h")
        [[ $got == "$version" ]] ||
            die "version mismatch: the SDK is $got (share/arsdk_version.h), --version is $version"
        unknown=0 scan_sms=()
        if [[ -d $tree/lib/models ]]; then
            while IFS= read -r -d '' file; do
                name_sms "${file##*/}"
                ((${#file_sms[@]} > 0)) || unknown=$((unknown + 1))
                for n in "${file_sms[@]}"; do
                    in_list "$n" "${scan_sms[@]}" || scan_sms+=("$n")
                done
            done < <(find "$tree/lib/models" -mindepth 1 -maxdepth 1 -type f -print0)
        fi
        printf 'layout=tree\nversion=%s\nsource=%s\n' "$got" "$tree"
        for f in "${present[@]}"; do printf 'feature=%s archs=?\n' "$f"; done
        printf 'archs=%s\nmodels_unknown=%d\n' "$(comma_archs "${scan_sms[@]}")" "$unknown"
        exit 0
    fi
    select_features
    mkdir -p -- "$dest"
    cp -a --reflink=auto -- "$tree/." "$dest/"
    # A user's engine cache is not part of the SDK. Never removed through a
    # link (check_links refused directory links; this is a second guard).
    [[ ! -L $dest/lib && ! -L $dest/lib/models ]] ||
        die "lib or lib/models in the copy is a symbolic link"
    if [[ -L $dest/lib/models/cache ]]; then
        rm -f -- "$dest/lib/models/cache"
    elif [[ -d $dest/lib/models/cache ]]; then
        rm -rf -- "$dest/lib/models/cache"
    fi
    if [[ -d $dest/lib/models ]]; then
        while IFS= read -r -d '' file; do
            name=${file##*/}
            source_models=$((source_models + 1))
            name_sms "$name"
            if ((${#file_sms[@]} == 0)); then
                unknown_models+=("$name")
                continue
            fi
            keep=0
            for n in "${file_sms[@]}"; do
                in_list "$n" "${source_sms[@]}" || source_sms+=("$n")
                if ((all)) || in_list "$n" "${sms[@]}"; then
                    keep=1
                    arch_files[$n]+=$name$'\n'
                fi
            done
            ((keep)) || rm -f -- "$file"
        done < <(find "$dest/lib/models" -mindepth 1 -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
    fi
else
    mode=download
    # Every feature library download and every models download; a MAJOR.MINOR
    # other than the SDK's is an error.
    feature_re='^(nvar[[:alnum:]-]*)_v(([0-9]+)\.([0-9]+)(\.[0-9]+)*)_'
    declare -A lib_dir=() feat_ver=() model_dir=() feat_has_models=()
    shopt -s nullglob
    for dir in "$src"/nvar*_v*_lib_linux/; do
        dir=${dir%/}
        base=${dir##*/}
        [[ $base =~ ${feature_re}lib_linux$ ]] ||
            die "unrecognised feature download directory $base (expected <feature>_v<version>_lib_linux)"
        f=${BASH_REMATCH[1]} fver=${BASH_REMATCH[2]} fmm=${BASH_REMATCH[3]}.${BASH_REMATCH[4]}
        [[ $fmm == "$major_minor" ]] ||
            die "$base does not match SDK version $major_minor (feature MAJOR.MINOR must equal the SDK's)"
        [[ -z ${lib_dir[$f]:-} ]] ||
            die "more than one download of $f (lib_linux) in $src: ${lib_dir[$f]##*/} $base"
        tarballs=("$dir"/*.tar.gz)
        ((${#tarballs[@]} > 0)) || die "no .tar.gz in $dir"
        lib_dir[$f]=$dir
        feat_ver[$f]=$fver
    done
    for dir in "$src"/nvar*_v*_models_linux_sm*/; do
        dir=${dir%/}
        base=${dir##*/}
        [[ $base =~ ${feature_re}models_linux_sm([0-9]+)$ ]] ||
            die "unrecognised models download directory $base (expected <feature>_v<version>_models_linux_sm<N>)"
        f=${BASH_REMATCH[1]} fmm=${BASH_REMATCH[3]}.${BASH_REMATCH[4]} n=${BASH_REMATCH[6]}
        [[ $fmm == "$major_minor" ]] ||
            die "$base does not match SDK version $major_minor (feature MAJOR.MINOR must equal the SDK's)"
        [[ -n ${lib_dir[$f]:-} ]] ||
            die "$base has no library download: no ${f}_v${major_minor}.*_lib_linux/ in $src" \
                "(NGC: nvidia/maxine/$f:${version}_lib_linux). See docs/download.md."
        [[ -z ${model_dir[$f:$n]:-} ]] ||
            die "more than one download of $f (models_linux_sm$n) in $src: ${model_dir[$f:$n]##*/} $base"
        model_dir[$f:$n]=$dir
        feat_has_models[$f]=1
    done
    shopt -u nullglob
    mapfile -t present < <(sort_names "${!lib_dir[@]}")
    if ((scan)); then
        printf 'layout=download\nversion=%s\nsource=%s\n' "$version" "$core_tgz"
        scan_sms=()
        for f in "${present[@]}"; do
            feature_sms=()
            for key in "${!model_dir[@]}"; do
                [[ ${key%:*} == "$f" ]] || continue
                n=${key##*:}
                feature_sms+=("$n")
                in_list "$n" "${scan_sms[@]}" || scan_sms+=("$n")
                dir=${model_dir[$key]}
                [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 -type f -print -quit) ]] ||
                    warn "models directory ${dir##*/} holds no model file directly inside:" \
                        "the build refuses it when sm_$n is selected. See docs/download.md."
            done
            printf 'feature=%s archs=%s\n' "$f" "$(comma_archs "${feature_sms[@]}")"
        done
        printf 'archs=%s\nmodels_unknown=0\n' "$(comma_archs "${scan_sms[@]}")"
        exit 0
    fi
    ((${#present[@]} > 0)) ||
        die "no feature found in $src: no nvar*_v${major_minor}.*_lib_linux/ directory" \
            "(e.g. NGC: nvidia/maxine/nvarfaceboxdetection:${version}_lib_linux). See docs/download.md."
    select_features
    lib_features=("${selected[@]}")
    # The architectures with models, among the selected features.
    for key in "${!model_dir[@]}"; do
        in_list "${key%:*}" "${lib_features[@]}" || continue
        in_list "${key##*:}" "${source_sms[@]}" || source_sms+=("${key##*:}")
    done
    if ((all)); then
        # Every models directory.
        mapfile -t sms < <(sort_numbers "${source_sms[@]}")
    else
        # Every feature that has models has them for every selected
        # architecture.
        for f in "${lib_features[@]}"; do
            [[ -n ${feat_has_models[$f]:-} ]] || continue
            for n in "${sms[@]}"; do
                [[ -n ${model_dir[$f:$n]:-} ]] ||
                    die "feature $f has no models for sm_$n: no ${f}_v${major_minor}.*_models_linux_sm$n/" \
                        "in $src (NGC: nvidia/maxine/$f:${feat_ver[$f]}_models_linux_sm$n). See docs/download.md."
            done
        done
    fi

    # The models directories used: regular files directly inside, at least
    # one; a file name shared by two directories must have one content.
    declare -A model_origin=()
    for f in "${lib_features[@]}"; do
        for n in "${sms[@]}"; do
            dir=${model_dir[$f:$n]:-}
            [[ -n $dir ]] || continue
            [[ -z $(find "$dir" -mindepth 1 -maxdepth 1 -type d -print -quit) ]] ||
                die "models directory ${dir##*/} contains subdirectories; expected the model files" \
                    "directly inside (as ngc download-version creates it). See docs/download.md."
            other=$(find "$dir" -mindepth 1 -maxdepth 1 ! -type f -printf '%f\n' -quit)
            [[ -z $other ]] ||
                die "models directory ${dir##*/} holds $other, which is not a regular file;" \
                    "expected only the model files"
            [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 -type f -print -quit) ]] ||
                die "models directory ${dir##*/} is empty: download it again" \
                    "(NGC: nvidia/maxine/$f:${feat_ver[$f]}_models_linux_sm$n). See docs/download.md."
            while IFS= read -r -d '' file; do
                name=${file##*/}
                first=${model_origin[$name]:-}
                if [[ -z $first ]]; then
                    model_origin[$name]=$file
                elif ! cmp -s -- "$first" "$file"; then
                    die "model file $name is in both ${first%/*} and ${file%/*}" \
                        "with different contents; refusing to let one overwrite the other in lib/models"
                fi
            done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
        done
    done

    # Extract next to DEST, then move the tarball's ARSDK/ into place.
    mkdir -p -- "$(dirname "$dest")"
    work=$(mktemp -d "$(dirname "$dest")/.assemble.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    tar -xzf "$core_tgz" -C "$work"
    [[ -f $work/ARSDK/lib/libnvARPose.so ]] ||
        die "${core_tgz##*/} does not contain ARSDK/lib/libnvARPose.so"
    [[ ! -d $dest ]] || rmdir -- "$dest"
    mv -- "$work/ARSDK" "$dest"
    mkdir -p "$dest/features" "$dest/lib/models"

    for f in "${lib_features[@]}"; do
        for t in "${lib_dir[$f]}"/*.tar.gz; do
            tar -xzf "$t" -C "$dest/features"
        done
        [[ -d $dest/features/$f/lib ]] ||
            die "${lib_dir[$f]##*/}: its tarball does not unpack to features/$f/lib"
    done
    check_links "$dest"
    for f in "${lib_features[@]}"; do
        for n in "${sms[@]}"; do
            dir=${model_dir[$f:$n]:-}
            [[ -n $dir ]] || continue
            while IFS= read -r -d '' file; do
                source_models=$((source_models + 1))
                arch_files[$n]+=${file##*/}$'\n'
                # Identical duplicates (checked above) are copied once.
                [[ -e $dest/lib/models/${file##*/} ]] ||
                    cp -a --reflink=auto -- "$file" "$dest/lib/models/"
            done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
        done
    done
fi

# Verification (both modes).
[[ -f $dest/share/arsdk_version.h ]] || die "missing share/arsdk_version.h in the assembled tree"
got=$(header_version "$dest/share/arsdk_version.h")
[[ $got == "$version" ]] ||
    die "version mismatch: the SDK is $got (share/arsdk_version.h), --version is $version"

for need in lib/libnvARPose.so lib/libNVCVImage.so include/nvAR.h; do
    [[ -e $dest/$need ]] || die "missing $need in the assembled tree"
done

# The features: every features/<f>/ with lib/*.so, sorted by name.
found=()
shopt -s nullglob
for dir in "$dest"/features/*/; do
    dir=${dir%/}
    f=${dir##*/}
    libs=("$dir"/lib/*.so)
    if ((${#libs[@]} > 0)); then
        found+=("$f")
    else
        note "features/$f has no lib/*.so: it is copied, but not packaged as a feature"
    fi
done
shopt -u nullglob
mapfile -t found < <(sort_names "${found[@]}")
# A feature that is not selected is removed from the copy (never through a
# link: check_links refused directory links; this is a second guard).
features=()
for f in "${found[@]}"; do
    if ((all_features)) || in_list "$f" "${wanted[@]}"; then
        features+=("$f")
        continue
    fi
    [[ ! -L $dest/features/$f ]] || die "features/$f in the copy is a symbolic link"
    rm -rf -- "${dest:?}/features/$f"
    in_list "$f" "${left_out[@]}" || left_out+=("$f")
done
mapfile -t left_out < <(sort_names "${left_out[@]}")
((${#features[@]} > 0)) ||
    die "no feature in the assembled tree (no features/<feature>/lib/*.so): download at least one" \
        "(e.g. NGC: nvidia/maxine/nvarfaceboxdetection:${version}_lib_linux). See docs/download.md."
for f in "${wanted[@]}"; do
    in_list "$f" "${features[@]}" ||
        die "selected feature $f is not in the assembled tree (no features/$f/lib/*.so; NGC:" \
            "nvidia/maxine/$f:${version}_lib_linux). See docs/download.md."
done

# A feature's <Name>_dependencies.txt may name other features it needs. Its
# format is not documented; the 1.2.0.0 files hold library names separated by
# semicolons (nvARFaceBoxDetection;nvARLandmarkDetection;). Words are split on
# semicolons, commas and white space and lowercased, and every word that
# starts with nvar counts (nvARFaceBoxDetection is the feature
# nvarfaceboxdetection).
shopt -s nullglob
for f in "${features[@]}"; do
    for deps in "$dest/features/$f"/*_dependencies.txt; do
        [[ -s $deps ]] || continue
        missing=() unselected=()
        while IFS= read -r word; do
            [[ $word == nvar* ]] || continue
            in_list "$word" "${features[@]}" "${missing[@]}" "${unselected[@]}" && continue
            if in_list "$word" "${present[@]}" "${left_out[@]}"; then
                unselected+=("$word")
            else
                missing+=("$word")
            fi
        done < <(tr -s ';,[:space:]' '\n' <"$deps" | tr '[:upper:]' '[:lower:]')
        ((${#missing[@]} == 0)) ||
            warn "feature $f lists dependencies that are not present: ${missing[*]}" \
                "(features/$f/${deps##*/}). See docs/download.md."
        ((${#unselected[@]} == 0)) ||
            warn "feature $f lists dependencies that are present but not selected: ${unselected[*]}" \
                "(features/$f/${deps##*/}); add them to MAXINE_AR_FEATURES (--features)."
    done
done
shopt -u nullglob

# The models: every selected architecture has some, unless the source has
# none for any architecture (a download without models only warns: every
# AR SDK 1.2.0.0 feature needs its models at run time, but a tree without
# them is still a valid SDK tree).
if ((all)); then
    mapfile -t sms < <(sort_numbers "${source_sms[@]}")
fi
if ((${#source_sms[@]} == 0)); then
    if ((source_models == 0)); then
        warn "no models in the source: the packaged features will not run without" \
            "their models. See docs/download.md."
    else
        warn "no model file name carries a GPU architecture: nothing was pruned"
    fi
else
    have=''
    while IFS= read -r n; do have+="sm_$n "; done < <(sort_numbers "${source_sms[@]}")
    for n in "${sms[@]}"; do
        [[ -n ${arch_files[$n]:-} ]] ||
            die "no models for sm_$n in lib/models; the source has models for ${have}(NGC:" \
                "nvidia/maxine/<feature>:${version}_models_linux_sm$n for every feature with" \
                "models). See docs/download.md."
    done
fi
if ((${#unknown_models[@]} > 0)); then
    note "kept ${#unknown_models[@]} model file(s) whose name carries no GPU architecture:" \
        "${unknown_models[*]}"
fi
if [[ $mode == tree ]] && ((${#left_out[@]} > 0 && source_models > 0)); then
    note "in an SDK tree the model files are not tied to a feature: lib/models keeps those of" \
        "the features left out (${left_out[*]}) for the selected architectures"
fi

packaged_archs=()
while IFS= read -r n; do
    if [[ -n ${arch_files[$n]:-} ]]; then packaged_archs+=("sm_$n"); fi
done < <(sort_numbers "${sms[@]}")

if [[ -n $state ]]; then
    {
        printf 'MAXINE_AR_FEATURES=%s\n' "$(IFS=,; echo "${features[*]}")"
        printf 'MAXINE_AR_ARCHS=%s\n' "$(IFS=,; echo "${packaged_archs[*]}")"
    } >"$state"
fi

model_total=0
if [[ -d $dest/lib/models ]]; then
    model_total=$(find "$dest/lib/models" -mindepth 1 -maxdepth 1 -type f | wc -l)
fi
printf '%s: assembled %s\n' "$prog" "$dest"
printf '  mode      %s (%s)\n' "$mode" "${tree:-$core_tgz}"
printf '  version   %s\n' "$version"
printf '  features  %s\n' "${features[*]}"
if ((${#left_out[@]} > 0)); then
    printf '  left out  %s (present, not selected)\n' "${left_out[*]}"
fi
if ((all)); then
    printf '  archs     %s (all found)\n' "${packaged_archs[*]:-none}"
else
    printf '  archs     %s\n' "${packaged_archs[*]:-none (no models)}"
fi
for arch in "${packaged_archs[@]}"; do
    mapfile -t names < <(printf '%s' "${arch_files[${arch#sm_}]}" | LC_ALL=C sort -u)
    size=$(cd "$dest/lib/models" && du -ch -- "${names[@]}" | tail -n 1 | cut -f 1)
    printf '  models    %-7s %d files, %s\n' "$arch" "${#names[@]}" "$size"
done
printf '  models    total   %d files\n' "$model_total"
if ((dangling_links > 0)); then
    if ((dangling_alternatives > 0)); then
        printf '  links     %d dangling symbolic links kept as shipped by NVIDIA (%d into /etc/alternatives)\n' \
            "$dangling_links" "$dangling_alternatives"
    else
        printf '  links     %d dangling symbolic links kept as shipped by NVIDIA\n' "$dangling_links"
    fi
fi
