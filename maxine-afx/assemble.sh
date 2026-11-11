#!/usr/bin/env bash
# Builds a Maxine Audio Effects SDK tree from the user's own NVIDIA download,
# for the maxine-afx PKGBUILD (prepare()). Nothing is downloaded, nothing
# from the download is executed, and the source is never modified.
#
#   assemble.sh --src DIR --dest DIR --version 3.0.0.12 \
#       [--archs "sm_120 sm_89" | --archs all] [--features all | "f1 f2"] [--state FILE]
#   assemble.sh --scan --src DIR --version 3.0.0.12
#
# The version is the SDK's full four-part version (version.h); NGC tags its
# downloads with the first three parts (v3.0.0). Two source layouts are
# accepted (README.md, "Source layouts"):
#   tree mode      DIR or DIR/Audio_Effects_SDK is an assembled SDK tree (it
#                  holds nvafx/lib/libnv_audiofx.so), e.g. a previous
#                  user-prefix install. It is copied (reflinks where the
#                  filesystem allows), and each features/<f>/models/ is
#                  pruned to the selected GPU architectures.
#   download mode  the directories as `ngc ... download-version` creates them:
#                  NVIDIA_AFX_SDK_Linux_<ver>.tar.gz (bare, or in
#                  maxine_linux_audio_effects_sdk_v<X.Y.Z>/),
#                  afx_<feature>_v<X.Y.Z>-lib/*.tar.gz and
#                  afx_<feature>_v<X.Y.Z>-<rate>-sm<N>/*.trtpkg (+ .trtpkg.md5),
#                  where <rate> is a sample rate such as 48k or 16k, or a
#                  conversion such as 16k_to_48k.
#
# The result is laid out as NVIDIA's features/download_features.sh lays it
# out: features/<f>/{include,lib,licenses}/ from the feature's tarball, and
# features/<f>/models/sm_<N>/<model>.trtpkg, the models of every sample rate
# of that architecture side by side. Like that script, each <model>.trtpkg
# whose name ends in _<digits> gets a relative link without that suffix
# (denoiser_48k_10752.trtpkg gets denoiser_48k.trtpkg ->
# denoiser_48k_10752.trtpkg) unless the name is taken, and the .md5 sidecars
# are checked and not kept. The SDK tree is written directly into DEST
# (DEST/nvafx, DEST/features, ...), which must not exist or be empty. A
# source holding both an SDK tree and NGC downloads is refused: which one is
# meant is not guessed.
#
# Archives: every member name is listed first (tar -t) and an absolute name
# or a .. component is refused before anything is extracted. Symbolic links:
# a link to a directory, or to an existing file outside the tree, is refused
# (it would package a link into the builder's home); dangling links are kept
# as shipped and counted in the summary.
#
# Checksums: in download mode every <model>.trtpkg.md5 must sit next to its
# <model>.trtpkg and begin with 32 hexadecimal digits, the MD5 of the model;
# the copied model is hashed (md5sum, nothing is executed) and a mismatch
# stops the build. In tree mode the sidecars present are checked the same
# way. A model without a sidecar is counted in a note. Other files in a
# models directory are, in download mode, not copied, and in tree mode kept
# as the tree has them; a note names them in both modes.
#
# Features: the features present in the source are, in tree mode, every
# features/<f>/ with lib/*.so, in download mode every
# afx_<f>_v<MAJOR.MINOR>.*-lib/*.tar.gz. --features all (the default)
# assembles every one of them; a list (spaces or commas) assembles exactly
# those, each of which must be present, and leaves the others out (the
# summary lists them as "present, not selected"). At least one feature is
# needed. Feature names are those of features/<f>/: denoiser, dereverb,
# dereverb_denoiser, studio_voice, ...
#
# Architectures: --archs takes sm_120, sm120 or 120 (the compute capability
# without the dot), spaces or commas between entries (default sm_120), or
# `all` alone, which keeps every architecture found. A model belongs to the
# architecture of its directory (download: -sm<N>; tree: models/sm_<N>/).
# Without `all`, every selected feature that has models has them for every
# selected architecture, and in download mode for every sample rate it has
# models for (any architecture): a missing one stops the build, naming the
# NGC tag. Each models directory used must hold at least one .trtpkg and
# only regular files; two files of the same name for one feature and
# architecture must be identical.
#
# Sample rates are not selected: every rate present for the selected
# features and architectures is packaged and reported. A rate is read from
# the download directory's name, or in tree mode from the model's name (an
# underscore-delimited 48k, 16k or 16k_to_48k).
#
# --state FILE receives three KEY=value lines on success, comma-separated:
#   MAXINE_AFX_FEATURES=denoiser,studio_voice
#   MAXINE_AFX_ARCHS=sm_120
#   MAXINE_AFX_RATES=48k
#
# The result is verified: version header, core library and header, one
# library per feature, models for every selected architecture. The summary
# on stdout lists the features, architectures, rates, the model count and
# size per architecture, and the checksums verified; warnings and notes go
# to stderr.
#
# --scan writes nothing and assembles nothing: it runs the layout detection
# and its refusals and prints only these lines on stdout, for configure.sh:
#   layout=tree|download
#   version=<the SDK version: the tree's version.h, or --version for a
#            download (the core tarball's name carries it)>
#   source=<the SDK tree, or the core tarball>
#   feature=<name> archs=<sm_N,...|-> rates=<rate,...|->
#            one line per feature present, sorted by name
#   archs=<every architecture with models, or ->
#   rates=<every sample rate with models, or ->
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
        *) usage ;;
    esac
done
if ((scan)); then
    [[ -n $src && -n $version && -z $dest && -z $state ]] || usage
else
    [[ -n $src && -n $dest && -n $version ]] || usage
fi

[[ $version =~ ^(([0-9]+)\.([0-9]+)\.[0-9]+)\.[0-9]+$ ]] ||
    die "--version must look like 3.0.0.12, got '$version'"
ngc_ver=${BASH_REMATCH[1]}
major_minor=${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
see="See maxine-afx/README.md."

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
sort_rates() { (($# == 0)) || printf '%s\n' "$@" | sort -V -u; }
in_list() { # in_list <word> <list...>
    local word=$1 item
    shift
    for item in "$@"; do [[ $item == "$word" ]] && return 0; done
    return 1
}
# comma_archs <n>...: sm_N,sm_M sorted by number, or - for none.
comma_archs() {
    local n out=''
    while IFS= read -r n; do out+=${out:+,}sm_$n; done < <(sort_numbers "$@")
    echo "${out:--}"
}
# comma_rates <rate>...: sorted (8k_to_16k,16k,16k_to_48k,48k), or - for none.
comma_rates() {
    local r out=''
    while IFS= read -r r; do out+=${out:+,}$r; done < <(sort_rates "$@")
    echo "${out:--}"
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

# rate_of <model file name>: the sample rate an underscore-delimited field of
# the name carries (48k, 16k_to_48k), or nothing.
rate_of() {
    if [[ $1 =~ (^|_)([0-9]+k(_to_[0-9]+k)?)(_|\.trtpkg$) ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    fi
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
core_name=NVIDIA_AFX_SDK_Linux_$version.tar.gz
core_dir=maxine_linux_audio_effects_sdk_v$ngc_ver
tree='' core_tgz=''
for candidate in "$src" "$src/Audio_Effects_SDK"; do
    if [[ -f $candidate/nvafx/lib/libnv_audiofx.so ]]; then
        tree=$(realpath -- "$candidate")
        break
    fi
done
if [[ -n $tree ]]; then
    # A tree next to NGC downloads: which one is meant is not guessed.
    shopt -s nullglob
    downloads=("$src"/maxine_linux_audio_effects_sdk_v* "$src"/NVIDIA_AFX_SDK_Linux_*.tar.gz "$src"/afx_*_v*)
    shopt -u nullglob
    if ((${#downloads[@]} > 0)); then
        die "$src holds both an SDK tree ($tree) and NGC downloads (${downloads[*]##*/})." \
            "Move one of them away, or point MAXINE_AFX_SRC (--src) at the one you mean."
    fi
else
    for candidate in "$src/$core_name" "$src/$core_dir/$core_name"; do
        if [[ -f $candidate ]]; then
            core_tgz=$candidate
            break
        fi
    done
fi
if [[ -z $tree && -z $core_tgz ]]; then
    die "no Maxine AFX SDK found in $src. Looked for an SDK tree" \
        "($src/nvafx/lib/libnv_audiofx.so or $src/Audio_Effects_SDK/nvafx/lib/libnv_audiofx.so)" \
        "and for the core download ($src/$core_name or $src/$core_dir/$core_name). $see"
fi

# check_links <root>: refuses a symbolic link to a directory, to an existing
# file outside <root>, or a dangling relative link that leaves <root>; counts
# the dangling links, which are kept as shipped. <root> is a canonical path.
dangling_links=0
check_links() {
    local root=$1 link rel target resolved
    while IFS= read -r -d '' link; do
        rel=${link#"$root"/}
        target=$(readlink -- "$link")
        if [[ -d $link ]]; then
            die "$rel in $root is a symbolic link to a directory ($target): refused, so that" \
                "nothing outside the tree is packaged or removed through it. Use a copy of the" \
                "directory, or point MAXINE_AFX_SRC (--src) at a tree without directory links."
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
        fi
    done < <(find "$root" -type l -print0)
}

# check_members <tarball>: refuses an absolute member name or one with a ..
# component, before anything is extracted.
check_members() {
    local tarball=$1 member members
    members=$(tar -tzf "$tarball") || die "${tarball##*/} cannot be read as a .tar.gz archive"
    while IFS= read -r member; do
        case /$member/ in
            //*) die "${tarball##*/} holds the absolute name $member: refused" ;;
            */../*) die "${tarball##*/} holds $member, which leaves the directory: refused" ;;
        esac
    done <<<"$members"
}

# header_version <file>: prints the SDK version a version.h defines.
header_version() {
    local header=$1 part value
    local -a parts=()
    [[ -f $header ]] || die "missing version.h in ${header%/version.h}"
    for part in MAJOR MINOR PATCH BUILD; do
        value=$(awk -v key="NVAUDIOEFFECTS_${part}_VERSION" \
            '$1 == "#define" && $2 == key { print $3; exit }' "$header")
        [[ $value =~ ^[0-9]+$ ]] || die "version.h does not define NVAUDIOEFFECTS_${part}_VERSION"
        parts+=("$value")
    done
    (IFS=.; echo "${parts[*]}")
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
                "nvidia/maxine/afx_${missing[0]}:${ngc_ver}-lib). $see"
        fi
        local fetch=''
        for f in "${missing[@]}"; do
            fetch+=" ngc registry model download-version \"nvidia/maxine/afx_$f:${ngc_ver}-lib\" --dest \"$src\";"
        done
        die "feature(s) not present in $src: ${missing[*]} (present: ${present[*]:-none})." \
            "Fetch with your own NGC CLI:${fetch} plus its models for each sample rate and" \
            "architecture, nvidia/maxine/afx_<feature>:${ngc_ver}-<rate>-sm<N>. $see"
    fi
    mapfile -t selected < <(sort_names "${wanted[@]}")
    for f in "${present[@]}"; do
        in_list "$f" "${selected[@]}" || left_out+=("$f")
    done
}

# check_md5 <model copy> <sidecar> <where>: the copy's MD5 against the first
# 32 characters of the sidecar.
md5_verified=0
check_md5() {
    local file=$1 sidecar=$2 where=$3 want got
    want=$(head -c 32 -- "$sidecar")
    [[ $want =~ ^[0-9a-fA-F]{32}$ ]] ||
        die "${sidecar##*/} in $where does not begin with an MD5 checksum (32 hexadecimal digits)"
    got=$(md5sum <"$file")
    got=${got%% *}
    [[ ${got,,} == "${want,,}" ]] ||
        die "${file##*/} from $where does not match ${sidecar##*/} (MD5 $got, expected ${want,,}):" \
            "the download is corrupted or incomplete; download it again. $see"
    md5_verified=$((md5_verified + 1))
}

# add_aliases <models dir>: NVIDIA's download script links <stem>.trtpkg to
# each <stem>_<digits>.trtpkg; the same is done here, never over a name that
# is taken (the first model in name order wins).
aliases=0 alias_skipped=()
add_aliases() {
    local dir=$1 file name alias
    while IFS= read -r -d '' file; do
        name=${file##*/}
        [[ $name =~ ^(.+)_[0-9]+\.trtpkg$ ]] || continue
        alias=${BASH_REMATCH[1]}.trtpkg
        if [[ -e $dir/$alias || -L $dir/$alias ]]; then
            [[ -L $dir/$alias && $(readlink -- "$dir/$alias") == "$name" ]] ||
                alias_skipped+=("${dir#"$dest"/}/$name")
            continue
        fi
        ln -s -- "$name" "$dir/$alias"
        aliases=$((aliases + 1))
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print0 | LC_ALL=C sort -z)
}

# Per architecture: the packaged model files ("<feature>/<name>" lines); the
# rates packaged; models without a sidecar; files not copied (download
# mode) or kept (tree mode) that are not models.
declare -A arch_files=()
source_sms=() packaged_rates=() no_sidecar=0 skipped_files=() kept_files=() present=()

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
    shopt -s nullglob
    for dir in "$tree"/features/*/; do
        dir=${dir%/}
        libs=("$dir"/lib/*.so)
        ((${#libs[@]} == 0)) || present+=("${dir##*/}")
    done
    mapfile -t present < <(sort_names "${present[@]}")
    # feature_sms[f]: the architectures of its models/sm_<N>/ directories.
    declare -A feature_sms=() feature_rates=()
    for f in "${present[@]}"; do
        for dir in "$tree/features/$f"/models/sm_*/; do
            dir=${dir%/}
            [[ ${dir##*/} =~ ^sm_([1-9][0-9]{1,2})$ ]] || continue
            n=${BASH_REMATCH[1]}
            feature_sms[$f]+="$n "
            while IFS= read -r -d '' file; do
                r=$(rate_of "${file##*/}")
                [[ -z $r || " ${feature_rates[$f]:-} " == *" $r "* ]] || feature_rates[$f]+="$r "
            done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print0)
        done
    done
    shopt -u nullglob
    got=$(header_version "$tree/version.h")
    [[ $got == "$version" ]] ||
        die "version mismatch: the SDK is $got (version.h), --version is $version"
    if ((scan)); then
        scan_sms=() scan_rates=()
        printf 'layout=tree\nversion=%s\nsource=%s\n' "$got" "$tree"
        for f in "${present[@]}"; do
            read -r -a fs <<<"${feature_sms[$f]:-}"
            read -r -a fr <<<"${feature_rates[$f]:-}"
            for n in "${fs[@]}"; do in_list "$n" "${scan_sms[@]}" || scan_sms+=("$n"); done
            for r in "${fr[@]}"; do in_list "$r" "${scan_rates[@]}" || scan_rates+=("$r"); done
            printf 'feature=%s archs=%s rates=%s\n' "$f" "$(comma_archs "${fs[@]}")" "$(comma_rates "${fr[@]}")"
        done
        printf 'archs=%s\nrates=%s\n' "$(comma_archs "${scan_sms[@]}")" "$(comma_rates "${scan_rates[@]}")"
        exit 0
    fi
    select_features
    for f in "${selected[@]}"; do
        read -r -a fs <<<"${feature_sms[$f]:-}"
        for n in "${fs[@]}"; do in_list "$n" "${source_sms[@]}" || source_sms+=("$n"); done
        ((${#fs[@]} > 0 && !all)) || continue
        for n in "${sms[@]}"; do
            if ! in_list "$n" "${fs[@]}"; then
                read -r -a fr <<<"${feature_rates[$f]:-}"
                die "feature $f has no models for sm_$n in the SDK tree $tree (no" \
                    "features/$f/models/sm_$n/; it has $(comma_archs "${fs[@]}")). NGC:" \
                    "nvidia/maxine/afx_$f:${ngc_ver}-<rate>-sm$n for each rate" \
                    "(${fr[*]:-48k or 16k}); an SDK tree is used as it is. $see"
            fi
        done
    done
    mkdir -p -- "$dest"
    cp -a --reflink=auto -- "$tree/." "$dest/"
    ((all)) && mapfile -t sms < <(sort_numbers "${source_sms[@]}")
    for f in "${selected[@]}"; do
        mdir=$dest/features/$f/models
        [[ -d $mdir ]] || continue
        [[ ! -L $mdir ]] || die "features/$f/models in the copy is a symbolic link"
        while IFS= read -r -d '' entry; do
            name=${entry##*/}
            if [[ ! -d $entry || ! $name =~ ^sm_([1-9][0-9]{1,2})$ ]]; then
                note "kept features/$f/models/$name: not an sm_<N> directory"
                continue
            fi
            n=${BASH_REMATCH[1]}
            if ! in_list "$n" "${sms[@]}"; then
                rm -rf -- "${entry:?}"
                continue
            fi
            [[ -z $(find "$entry" -mindepth 1 -maxdepth 1 -type d -print -quit) ]] ||
                die "features/$f/models/$name contains subdirectories; expected the model files directly inside"
            [[ -n $(find "$entry" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print -quit) ]] ||
                die "features/$f/models/$name holds no .trtpkg model file"
            while IFS= read -r -d '' sidecar; do
                model=${sidecar%.md5}
                [[ -f $model && ! -L $model ]] ||
                    die "features/$f/models/$name/${sidecar##*/} has no model file next to it"
                check_md5 "$model" "$sidecar" "features/$f/models/$name"
                rm -f -- "$sidecar"
            done < <(find "$entry" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg.md5' -print0 | LC_ALL=C sort -z)
            while IFS= read -r -d '' file; do
                arch_files[$n]+="$f/${file##*/}"$'\n'
                r=$(rate_of "${file##*/}")
                [[ -z $r ]] || in_list "$r" "${packaged_rates[@]}" || packaged_rates+=("$r")
            done < <(find "$entry" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print0 | LC_ALL=C sort -z)
            # What is left besides the models (the sidecars are gone) stays
            # in the copy, as in the tree; the note names it.
            while IFS= read -r -d '' file; do
                kept_files+=("features/$f/models/$name/${file##*/}")
            done < <(find "$entry" -mindepth 1 -maxdepth 1 ! -name '*.trtpkg' -print0 | LC_ALL=C sort -z)
            add_aliases "$entry"
        done < <(find "$mdir" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
    done
else
    mode=download
    # Every feature library download and every models download; a MAJOR.MINOR
    # other than the SDK's is an error, and so is any other afx_*_v* entry.
    feature_re='^afx_([[:alnum:]_]+)_v(([0-9]+)\.([0-9]+)(\.[0-9]+)*)-'
    declare -A lib_dir=() feat_ver=() model_dir=() feat_rates=() feat_sms=()
    shopt -s nullglob
    for dir in "$src"/afx_*_v*; do
        base=${dir##*/}
        [[ -d $dir && ! -L $dir ]] ||
            die "$base in $src is not a directory: expected the directories ngc download-version creates"
        if [[ $base =~ ${feature_re}lib$ ]]; then
            f=${BASH_REMATCH[1]} fver=${BASH_REMATCH[2]} fmm=${BASH_REMATCH[3]}.${BASH_REMATCH[4]}
            [[ $fmm == "$major_minor" ]] ||
                die "$base does not match SDK version $major_minor (feature MAJOR.MINOR must equal the SDK's)"
            [[ -z ${lib_dir[$f]:-} ]] ||
                die "more than one download of $f (-lib) in $src: ${lib_dir[$f]##*/} $base"
            tarballs=("$dir"/*.tar.gz)
            ((${#tarballs[@]} > 0)) || die "no .tar.gz in $dir"
            lib_dir[$f]=$dir
            feat_ver[$f]=$fver
        elif [[ ! $base =~ ${feature_re}([0-9]+k(_to_[0-9]+k)?)-sm([0-9]+)$ ]]; then
            die "unrecognised download directory $base (expected afx_<feature>_v<version>-lib" \
                "or afx_<feature>_v<version>-<rate>-sm<N>)"
        fi
    done
    for dir in "$src"/afx_*_v*; do
        base=${dir##*/}
        [[ $base =~ ${feature_re}([0-9]+k(_to_[0-9]+k)?)-sm([0-9]+)$ ]] || continue
        f=${BASH_REMATCH[1]} fmm=${BASH_REMATCH[3]}.${BASH_REMATCH[4]} r=${BASH_REMATCH[6]} n=${BASH_REMATCH[8]}
        [[ $fmm == "$major_minor" ]] ||
            die "$base does not match SDK version $major_minor (feature MAJOR.MINOR must equal the SDK's)"
        [[ -n ${lib_dir[$f]:-} ]] ||
            die "$base has no library download: no afx_${f}_v${major_minor}.*-lib/ in $src" \
                "(NGC: nvidia/maxine/afx_$f:${ngc_ver}-lib). $see"
        [[ -z ${model_dir[$f:$r:$n]:-} ]] ||
            die "more than one download of $f ($r-sm$n) in $src: ${model_dir[$f:$r:$n]##*/} $base"
        model_dir[$f:$r:$n]=$dir
        [[ " ${feat_rates[$f]:-} " == *" $r "* ]] || feat_rates[$f]+="$r "
        [[ " ${feat_sms[$f]:-} " == *" $n "* ]] || feat_sms[$f]+="$n "
    done
    shopt -u nullglob
    mapfile -t present < <(sort_names "${!lib_dir[@]}")
    if ((scan)); then
        printf 'layout=download\nversion=%s\nsource=%s\n' "$version" "$core_tgz"
        scan_sms=() scan_rates=()
        for f in "${present[@]}"; do
            read -r -a fs <<<"${feat_sms[$f]:-}"
            read -r -a fr <<<"${feat_rates[$f]:-}"
            for n in "${fs[@]}"; do in_list "$n" "${scan_sms[@]}" || scan_sms+=("$n"); done
            for r in "${fr[@]}"; do in_list "$r" "${scan_rates[@]}" || scan_rates+=("$r"); done
            printf 'feature=%s archs=%s rates=%s\n' "$f" "$(comma_archs "${fs[@]}")" "$(comma_rates "${fr[@]}")"
        done
        for key in "${!model_dir[@]}"; do
            dir=${model_dir[$key]}
            [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print -quit) ]] ||
                warn "models directory ${dir##*/} holds no .trtpkg model file directly inside:" \
                    "the build refuses it when sm_${key##*:} is selected. $see"
        done
        printf 'archs=%s\nrates=%s\n' "$(comma_archs "${scan_sms[@]}")" "$(comma_rates "${scan_rates[@]}")"
        exit 0
    fi
    ((${#present[@]} > 0)) ||
        die "no feature found in $src: no afx_<feature>_v${major_minor}.*-lib/ directory" \
            "(e.g. NGC: nvidia/maxine/afx_denoiser:${ngc_ver}-lib). $see"
    select_features
    for f in "${selected[@]}"; do
        read -r -a fs <<<"${feat_sms[$f]:-}"
        for n in "${fs[@]}"; do in_list "$n" "${source_sms[@]}" || source_sms+=("$n"); done
    done
    if ((all)); then
        mapfile -t sms < <(sort_numbers "${source_sms[@]}")
    else
        # Every feature that has models has them for every selected
        # architecture, at every sample rate it has models for.
        for f in "${selected[@]}"; do
            read -r -a fr <<<"${feat_rates[$f]:-}"
            for r in "${fr[@]}"; do
                for n in "${sms[@]}"; do
                    [[ -n ${model_dir[$f:$r:$n]:-} ]] ||
                        die "feature $f has no $r models for sm_$n: no afx_${f}_v${major_minor}.*-$r-sm$n/" \
                            "in $src (NGC: nvidia/maxine/afx_$f:${feat_ver[$f]}-$r-sm$n). $see"
                done
            done
        done
    fi

    # The models directories used: only regular files, at least one .trtpkg,
    # each sidecar next to its model; a name shared by two directories of one
    # feature and architecture must have one content.
    declare -A model_origin=()
    for f in "${selected[@]}"; do
        read -r -a fr <<<"${feat_rates[$f]:-}"
        for n in "${sms[@]}"; do
            for r in "${fr[@]}"; do
                dir=${model_dir[$f:$r:$n]:-}
                [[ -n $dir ]] || continue
                tag="nvidia/maxine/afx_$f:${feat_ver[$f]}-$r-sm$n"
                [[ -z $(find "$dir" -mindepth 1 -maxdepth 1 -type d -print -quit) ]] ||
                    die "models directory ${dir##*/} contains subdirectories; expected the model files" \
                        "directly inside (as ngc download-version creates it). $see"
                other=$(find "$dir" -mindepth 1 -maxdepth 1 ! -type f -printf '%f\n' -quit)
                [[ -z $other ]] ||
                    die "models directory ${dir##*/} holds $other, which is not a regular file;" \
                        "expected only the model files"
                [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.trtpkg' -print -quit) ]] ||
                    die "models directory ${dir##*/} holds no .trtpkg model file: download it again" \
                        "(NGC: $tag). $see"
                while IFS= read -r -d '' file; do
                    name=${file##*/}
                    case $name in
                        *.trtpkg.md5)
                            [[ -f ${file%.md5} ]] ||
                                die "models directory ${dir##*/} holds $name without ${name%.md5}:" \
                                    "download it again (NGC: $tag)"
                            ;;
                        *.trtpkg)
                            key=$f:$n:$name
                            first=${model_origin[$key]:-}
                            if [[ -z $first ]]; then
                                model_origin[$key]=$file
                            elif ! cmp -s -- "$first" "$file"; then
                                die "model file $name is in both ${first%/*} and ${file%/*}" \
                                    "with different contents; refusing to let one overwrite the other" \
                                    "in features/$f/models/sm_$n"
                            fi
                            ;;
                    esac
                done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
            done
        done
    done

    # Extract next to DEST, then move the tarball's Audio_Effects_SDK/ into
    # place.
    check_members "$core_tgz"
    mkdir -p -- "$(dirname "$dest")"
    work=$(mktemp -d "$(dirname "$dest")/.assemble.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    tar -xzf "$core_tgz" -C "$work" --no-same-owner
    [[ -d $work/Audio_Effects_SDK && ! -L $work/Audio_Effects_SDK &&
        -f $work/Audio_Effects_SDK/nvafx/lib/libnv_audiofx.so ]] ||
        die "${core_tgz##*/} does not contain Audio_Effects_SDK/nvafx/lib/libnv_audiofx.so"
    [[ ! -d $dest ]] || rmdir -- "$dest"
    mv -- "$work/Audio_Effects_SDK" "$dest"
    [[ ! -L $dest/features ]] || die "features in ${core_tgz##*/} is a symbolic link"
    mkdir -p "$dest/features"
    # The core's links, before a feature tarball is unpacked next to them.
    check_links "$dest"

    for f in "${selected[@]}"; do
        fdir=$dest/features/$f
        [[ ! -e $fdir && ! -L $fdir ]] ||
            die "${core_tgz##*/} already holds features/$f; refusing to unpack the feature over it"
        mkdir -p -- "$fdir"
        for t in "${lib_dir[$f]}"/*.tar.gz; do
            check_members "$t"
            tar -xzf "$t" -C "$fdir" --no-same-owner
            # Before the next tarball: it must not write through a link this
            # one made. (The dangling links are counted once, below.)
            check_links "$dest"
        done
        [[ -d $fdir/lib && ! -L $fdir/lib ]] ||
            die "${lib_dir[$f]##*/}: its tarball does not unpack to lib/ (features/$f/lib)"
    done
    dangling_links=0
    check_links "$dest"
    for f in "${selected[@]}"; do
        read -r -a fr <<<"${feat_rates[$f]:-}"
        for n in "${sms[@]}"; do
            mdir=$dest/features/$f/models/sm_$n
            used=0
            for r in "${fr[@]}"; do
                dir=${model_dir[$f:$r:$n]:-}
                [[ -n $dir ]] || continue
                used=1
                in_list "$r" "${packaged_rates[@]}" || packaged_rates+=("$r")
                [[ ! -L $dest/features/$f/models ]] || die "features/$f/models in the copy is a symbolic link"
                mkdir -p -- "$mdir"
                while IFS= read -r -d '' file; do
                    name=${file##*/}
                    case $name in
                        *.trtpkg) ;;
                        *.trtpkg.md5) continue ;;
                        *)
                            skipped_files+=("${dir##*/}/$name")
                            continue
                            ;;
                    esac
                    # Identical duplicates (checked above) are copied once.
                    if [[ ! -e $mdir/$name ]]; then
                        cp -a --reflink=auto -- "$file" "$mdir/"
                        arch_files[$n]+="$f/$name"$'\n'
                    fi
                    if [[ -f $file.md5 ]]; then
                        check_md5 "$mdir/$name" "$file.md5" "${dir##*/}"
                    else
                        no_sidecar=$((no_sidecar + 1))
                    fi
                done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
            done
            ((used)) && add_aliases "$mdir"
        done
    done
fi

# Verification (both modes).
got=$(header_version "$dest/version.h")
[[ $got == "$version" ]] ||
    die "version mismatch: the SDK is $got (version.h), --version is $version"

for need in nvafx/lib/libnv_audiofx.so nvafx/include/nvAudioEffects.h; do
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
        "(e.g. NGC: nvidia/maxine/afx_denoiser:${ngc_ver}-lib). $see"
for f in "${wanted[@]}"; do
    in_list "$f" "${features[@]}" ||
        die "selected feature $f is not in the assembled tree (no features/$f/lib/*.so; NGC:" \
            "nvidia/maxine/afx_$f:${ngc_ver}-lib). $see"
done

# The models: every selected architecture has some, unless the source has
# none for any architecture.
if ((${#source_sms[@]} == 0)); then
    warn "no models in the source: no effect can run without its model. $see"
else
    have=''
    while IFS= read -r n; do have+="sm_$n "; done < <(sort_numbers "${source_sms[@]}")
    for n in "${sms[@]}"; do
        [[ -n ${arch_files[$n]:-} ]] ||
            die "no models for sm_$n; the source has models for ${have}(NGC:" \
                "nvidia/maxine/afx_<feature>:${ngc_ver}-<rate>-sm$n for every feature)." \
                "$see"
    done
fi
((no_sidecar == 0)) || note "$no_sidecar model file(s) had no .md5 sidecar and were not verified"
((${#skipped_files[@]} == 0)) ||
    note "not copied (not a model or checksum file): ${skipped_files[*]}"
((${#kept_files[@]} == 0)) ||
    note "kept as in the SDK tree (not a model or checksum file): ${kept_files[*]}"
((${#alias_skipped[@]} == 0)) ||
    note "no short-name link for ${alias_skipped[*]}: the name is taken"

packaged_archs=()
while IFS= read -r n; do
    if [[ -n ${arch_files[$n]:-} ]]; then packaged_archs+=("sm_$n"); fi
done < <(sort_numbers "${sms[@]}")
mapfile -t packaged_rates < <(sort_rates "${packaged_rates[@]}")

if [[ -n $state ]]; then
    {
        printf 'MAXINE_AFX_FEATURES=%s\n' "$(IFS=,; echo "${features[*]}")"
        printf 'MAXINE_AFX_ARCHS=%s\n' "$(IFS=,; echo "${packaged_archs[*]}")"
        printf 'MAXINE_AFX_RATES=%s\n' "$(IFS=,; echo "${packaged_rates[*]}")"
    } >"$state"
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
printf '  rates     %s\n' "${packaged_rates[*]:-none}"
for arch in "${packaged_archs[@]}"; do
    mapfile -t names < <(printf '%s' "${arch_files[${arch#sm_}]}" | LC_ALL=C sort -u)
    paths=()
    for name in "${names[@]}"; do paths+=("${name%%/*}/models/$arch/${name#*/}"); done
    size=$(cd "$dest/features" && du -ch -- "${paths[@]}" | tail -n 1 | cut -f 1)
    printf '  models    %-7s %d files, %s\n' "$arch" "${#names[@]}" "$size"
done
printf '  checksums %d model file(s) verified against their .md5\n' "$md5_verified"
((aliases == 0)) || printf '  links     %d short-name model link(s), as NVIDIA'\''s download script makes them\n' "$aliases"
if ((dangling_links > 0)); then
    printf '  dangling  %d dangling symbolic links kept as shipped by NVIDIA\n' "$dangling_links"
fi
