# shellcheck shell=bash
# The selection file nvidia-tensorrt/selection.conf, written by
# configure.sh --write and read by the PKGBUILD's prepare(). Sourced by
# both; it only defines functions. The selection file itself is PARSED,
# never sourced or evaluated: it holds a local path, and a line such as
#   NVIDIA_TRT_SRC=$(some command)
# must not run anything.
#
# Format: blank lines, comment lines (the first non-blank character is #),
# and at most one line for each of exactly these keys:
#   NVIDIA_TRT_SRC=<absolute path>     the archive, a directory holding it,
#                                      or an extracted tree
#   NVIDIA_TRT_SHA256=<64 hex digits>  the archive's SHA-256 as configure.sh
#                                      computed it (absent for a tree)
# A value is the rest of the line after the first =, taken literally. It
# must not be empty, must not start or end with white space, and must not
# contain $, a backtick, a quote or a control character; ~ is not expanded.
# An unknown key, any other line, or a duplicate key is an error that names
# the line number.
#
# Precedence (nvidia_trt_resolve): NVIDIA_TRT_SRC from the environment (when
# set and not empty) over the file, the file over the default. The
# NVIDIA_TRT_SHA256 of the file applies only to the NVIDIA_TRT_SRC of the
# same file: with NVIDIA_TRT_SRC from the environment it is ignored.

# nvidia_trt_read_selection <file>: sets nvidia_trt_file_src and
# nvidia_trt_file_sha256 (empty when the key is absent, both empty when the
# file does not exist). Returns 1 with a message on stderr when the file is
# not valid.
nvidia_trt_read_selection() {
    local file=$1 line key value lineno=0
    nvidia_trt_file_src='' nvidia_trt_file_sha256=''
    if [[ ! -e $file && ! -L $file ]]; then
        return 0
    fi
    if [[ ! -f $file || ! -r $file ]]; then
        printf '%s: not a readable regular file\n' "$file" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n $line ]]; do
        lineno=$((lineno + 1))
        [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue
        if [[ $line == *[[:cntrl:]]* ]]; then
            printf '%s:%d: a control character (tab, carriage return, escape) is not allowed\n' \
                "$file" "$lineno" >&2
            return 1
        fi
        if [[ ! $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            printf '%s:%d: not a KEY=value line\n' "$file" "$lineno" >&2
            return 1
        fi
        key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        case $key in
            NVIDIA_TRT_SRC | NVIDIA_TRT_SHA256) ;;
            *)
                printf '%s:%d: unknown key %s (allowed: NVIDIA_TRT_SRC, NVIDIA_TRT_SHA256)\n' \
                    "$file" "$lineno" "$key" >&2
                return 1
                ;;
        esac
        case $value in
            *'$'* | *'`'* | *"'"* | *'"'*)
                printf '%s:%d: the value of %s must not contain $, a backtick or a quote\n' \
                    "$file" "$lineno" "$key" >&2
                return 1
                ;;
        esac
        if [[ -z $value ]]; then
            printf '%s:%d: %s has an empty value\n' "$file" "$lineno" "$key" >&2
            return 1
        fi
        if [[ $value =~ ^[[:space:]] || $value =~ [[:space:]]$ ]]; then
            printf '%s:%d: the value of %s must not start or end with white space\n' \
                "$file" "$lineno" "$key" >&2
            return 1
        fi
        case $key in
            NVIDIA_TRT_SRC)
                if [[ -n $nvidia_trt_file_src ]]; then
                    printf '%s:%d: NVIDIA_TRT_SRC is set twice\n' "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value == '~'* ]]; then
                    printf '%s:%d: NVIDIA_TRT_SRC: ~ is not expanded; write the absolute path\n' \
                        "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value != /* ]]; then
                    printf '%s:%d: NVIDIA_TRT_SRC must be an absolute path\n' "$file" "$lineno" >&2
                    return 1
                fi
                nvidia_trt_file_src=$value
                ;;
            NVIDIA_TRT_SHA256)
                if [[ -n $nvidia_trt_file_sha256 ]]; then
                    printf '%s:%d: NVIDIA_TRT_SHA256 is set twice\n' "$file" "$lineno" >&2
                    return 1
                fi
                if [[ ! $value =~ ^[0-9a-f]{64}$ ]]; then
                    printf '%s:%d: NVIDIA_TRT_SHA256 must be 64 lowercase hexadecimal digits\n' \
                        "$file" "$lineno" >&2
                    return 1
                fi
                nvidia_trt_file_sha256=$value
                ;;
        esac
    done <"$file"
}

# nvidia_trt_resolve <file> <default src>: sets nvidia_trt_src,
# nvidia_trt_src_from (environment, the file's name, or default) and
# nvidia_trt_sha256 (the file's NVIDIA_TRT_SHA256 when the source came from
# the file, else empty). Returns 1 when the file is not valid, or when
# NVIDIA_TRT_SRC from the environment is not an absolute path (a relative
# one would be resolved against makepkg's $srcdir).
nvidia_trt_resolve() {
    local file=$1 name=${1##*/}
    nvidia_trt_read_selection "$file" || return 1
    nvidia_trt_sha256=''
    if [[ -n ${NVIDIA_TRT_SRC:-} && $NVIDIA_TRT_SRC != /* ]]; then
        printf 'environment: NVIDIA_TRT_SRC must be an absolute path (got %s)\n' "$NVIDIA_TRT_SRC" >&2
        return 1
    fi
    if [[ -n ${NVIDIA_TRT_SRC:-} ]]; then
        nvidia_trt_src=$NVIDIA_TRT_SRC nvidia_trt_src_from=environment
    elif [[ -n $nvidia_trt_file_src ]]; then
        nvidia_trt_src=$nvidia_trt_file_src nvidia_trt_src_from=$name
        nvidia_trt_sha256=$nvidia_trt_file_sha256
    else
        nvidia_trt_src=$2 nvidia_trt_src_from=default
    fi
}

# nvidia_trt_print_resolved: one line per value, with where it came from.
nvidia_trt_print_resolved() {
    printf '  NVIDIA_TRT_SRC=%s (from %s)\n' "$nvidia_trt_src" "$nvidia_trt_src_from"
    if [[ -n $nvidia_trt_sha256 ]]; then
        printf '  NVIDIA_TRT_SHA256=%s (from %s)\n' "$nvidia_trt_sha256" "$nvidia_trt_src_from"
    fi
}
