# shellcheck shell=bash
# The selection file nvidia-optical-flow/selection.conf, written by
# configure.sh and read by the PKGBUILD's prepare(). Sourced by both; it only
# defines functions. The selection file itself is PARSED, never sourced or
# evaluated: it holds a local path, and a line such as
#   NVIDIA_OF_SRC=$(some command)
# must not run anything.
#
# Format: blank lines, comment lines (the first non-blank character is #),
# and at most one line for each of exactly these keys:
#   NVIDIA_OF_SRC=<absolute path: the SDK zip, a directory holding it, or an
#                 extracted SDK tree>
#   SHA256=<64 hexadecimal digits: the SHA-256 of the zip NVIDIA_OF_SRC names>
# A value is the rest of the line after the first =, taken literally. It
# must not be empty, must not start or end with white space, and must not
# contain $, a backtick, a quote or a control character (a tab, a carriage
# return, an escape); ~ is not expanded. An unknown key, any other line, or
# a duplicate key is an error that names the line number.
#
# Precedence (nvidia_of_resolve): NVIDIA_OF_SRC from the environment (when
# set and not empty) over the file, the file over the default. The checksum
# belongs to the source it was recorded for: NVIDIA_OF_SHA256 from the
# environment wins; else the file's SHA256 applies when the source is the
# file's NVIDIA_OF_SRC (from the file, or the same path from the
# environment); else there is none. A NVIDIA_OF_SRC from the environment
# must be an absolute path too.

# nvidia_of_read_selection <file>: sets nvidia_of_file_src and
# nvidia_of_file_sha256 (empty when the key is absent, both empty when the
# file does not exist). Returns 1 with a message on stderr when the file is
# not valid.
nvidia_of_read_selection() {
    local file=$1 line key value lineno=0
    nvidia_of_file_src='' nvidia_of_file_sha256=''
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
            NVIDIA_OF_SRC | SHA256) ;;
            *)
                printf '%s:%d: unknown key %s (allowed: NVIDIA_OF_SRC, SHA256)\n' \
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
            NVIDIA_OF_SRC)
                if [[ -n $nvidia_of_file_src ]]; then
                    printf '%s:%d: NVIDIA_OF_SRC is set twice\n' "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value == '~'* ]]; then
                    printf '%s:%d: NVIDIA_OF_SRC: ~ is not expanded; write the absolute path\n' \
                        "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value != /* ]]; then
                    printf '%s:%d: NVIDIA_OF_SRC must be an absolute path\n' "$file" "$lineno" >&2
                    return 1
                fi
                nvidia_of_file_src=$value
                ;;
            SHA256)
                if [[ -n $nvidia_of_file_sha256 ]]; then
                    printf '%s:%d: SHA256 is set twice\n' "$file" "$lineno" >&2
                    return 1
                fi
                if [[ ! $value =~ ^[0-9a-fA-F]{64}$ ]]; then
                    printf '%s:%d: SHA256 must be 64 hexadecimal digits\n' "$file" "$lineno" >&2
                    return 1
                fi
                nvidia_of_file_sha256=${value,,}
                ;;
        esac
    done <"$file"
    if [[ -n $nvidia_of_file_sha256 && -z $nvidia_of_file_src ]]; then
        printf '%s: SHA256 is set without NVIDIA_OF_SRC\n' "$file" >&2
        return 1
    fi
}

# nvidia_of_resolve <file> <default src>: sets nvidia_of_src and
# nvidia_of_sha256 (empty: none), and nvidia_of_src_from and
# nvidia_of_sha256_from (environment, the file's name, default or none).
# Returns 1 when the file is not valid, when NVIDIA_OF_SRC from the
# environment is not an absolute path (a relative one would be resolved
# against makepkg's $srcdir), or when NVIDIA_OF_SHA256 from the environment
# is not 64 hexadecimal digits.
nvidia_of_resolve() {
    local file=$1 name=${1##*/}
    nvidia_of_read_selection "$file" || return 1
    if [[ -n ${NVIDIA_OF_SRC:-} && $NVIDIA_OF_SRC != /* ]]; then
        printf 'environment: NVIDIA_OF_SRC must be an absolute path (got %s)\n' "$NVIDIA_OF_SRC" >&2
        return 1
    fi
    if [[ -n ${NVIDIA_OF_SHA256:-} && ! $NVIDIA_OF_SHA256 =~ ^[0-9a-fA-F]{64}$ ]]; then
        printf 'environment: NVIDIA_OF_SHA256 must be 64 hexadecimal digits (got %s)\n' \
            "$NVIDIA_OF_SHA256" >&2
        return 1
    fi
    if [[ -n ${NVIDIA_OF_SRC:-} ]]; then
        nvidia_of_src=$NVIDIA_OF_SRC nvidia_of_src_from=environment
    elif [[ -n $nvidia_of_file_src ]]; then
        nvidia_of_src=$nvidia_of_file_src nvidia_of_src_from=$name
    else
        nvidia_of_src=$2 nvidia_of_src_from=default
    fi
    if [[ -n ${NVIDIA_OF_SHA256:-} ]]; then
        nvidia_of_sha256=${NVIDIA_OF_SHA256,,} nvidia_of_sha256_from=environment
    elif [[ -n $nvidia_of_file_sha256 && $nvidia_of_src == "$nvidia_of_file_src" ]]; then
        nvidia_of_sha256=$nvidia_of_file_sha256 nvidia_of_sha256_from=$name
    else
        nvidia_of_sha256='' nvidia_of_sha256_from=none
    fi
}

# nvidia_of_print_resolved: one line per value, with where it came from.
nvidia_of_print_resolved() {
    printf '  NVIDIA_OF_SRC=%s (from %s)\n' "$nvidia_of_src" "$nvidia_of_src_from"
    if [[ -n $nvidia_of_sha256 ]]; then
        printf '  SHA256=%s (from %s)\n' "$nvidia_of_sha256" "$nvidia_of_sha256_from"
    else
        printf '  SHA256=none (no checksum recorded for this source)\n'
    fi
}
