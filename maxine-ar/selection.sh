# shellcheck shell=bash
# The selection file maxine-ar/selection.conf, written by configure.sh and
# read by the PKGBUILD's prepare(). Sourced by both; it only defines
# functions. The selection file itself is PARSED, never sourced or
# evaluated: it holds a local path, and a line such as
#   MAXINE_AR_SRC=$(some command)
# must not run anything.
#
# Format: blank lines, comment lines (the first non-blank character is #),
# and at most one line for each of exactly these keys:
#   MAXINE_AR_SRC=<absolute path>
#   MAXINE_AR_ARCHS=<comma-separated list, e.g. sm_120,sm_89, or all>
#   MAXINE_AR_FEATURES=<comma-separated list, or all>
# A value is the rest of the line after the first =, taken literally. It
# must not be empty, must not start or end with white space, and must not
# contain $, a backtick, a quote or a control character (a tab, a carriage
# return, an escape); ~ is not expanded. A list holds only
# letters, digits, _ and - between the commas. An unknown key, any other
# line, or a duplicate key is an error that names the line number.
#
# Precedence (maxine_ar_resolve): an environment variable of the same name
# (when set and not empty) over the file, the file over the default. A
# MAXINE_AR_SRC from the environment must be an absolute path too.

# maxine_ar_read_selection <file>: sets maxine_ar_file_src,
# maxine_ar_file_archs and maxine_ar_file_features (empty when the key is
# absent, all empty when the file does not exist). Returns 1 with a message
# on stderr when the file is not valid.
maxine_ar_read_selection() {
    local file=$1 line key value lineno=0
    maxine_ar_file_src='' maxine_ar_file_archs='' maxine_ar_file_features=''
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
            MAXINE_AR_SRC | MAXINE_AR_ARCHS | MAXINE_AR_FEATURES) ;;
            *)
                printf '%s:%d: unknown key %s (allowed: MAXINE_AR_SRC, MAXINE_AR_ARCHS, MAXINE_AR_FEATURES)\n' \
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
            MAXINE_AR_SRC)
                if [[ -n $maxine_ar_file_src ]]; then
                    printf '%s:%d: MAXINE_AR_SRC is set twice\n' "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value == '~'* ]]; then
                    printf '%s:%d: MAXINE_AR_SRC: ~ is not expanded; write the absolute path\n' \
                        "$file" "$lineno" >&2
                    return 1
                fi
                if [[ $value != /* ]]; then
                    printf '%s:%d: MAXINE_AR_SRC must be an absolute path\n' "$file" "$lineno" >&2
                    return 1
                fi
                maxine_ar_file_src=$value
                ;;
            *)
                if [[ ! $value =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]]; then
                    printf '%s:%d: %s must be a comma-separated list (letters, digits, _ and -) or all\n' \
                        "$file" "$lineno" "$key" >&2
                    return 1
                fi
                if [[ $key == MAXINE_AR_ARCHS ]]; then
                    if [[ -n $maxine_ar_file_archs ]]; then
                        printf '%s:%d: MAXINE_AR_ARCHS is set twice\n' "$file" "$lineno" >&2
                        return 1
                    fi
                    maxine_ar_file_archs=$value
                else
                    if [[ -n $maxine_ar_file_features ]]; then
                        printf '%s:%d: MAXINE_AR_FEATURES is set twice\n' "$file" "$lineno" >&2
                        return 1
                    fi
                    maxine_ar_file_features=$value
                fi
                ;;
        esac
    done <"$file"
}

# maxine_ar_resolve <file> <default src> <default archs> <default features>:
# sets maxine_ar_src, maxine_ar_archs and maxine_ar_features, and
# maxine_ar_src_from, maxine_ar_archs_from and maxine_ar_features_from
# (environment, the file's name, or default). Returns 1 when the file is not
# valid, or when MAXINE_AR_SRC from the environment is not an absolute path
# (a relative one would be resolved against makepkg's $srcdir).
maxine_ar_resolve() {
    local file=$1 name=${1##*/}
    maxine_ar_read_selection "$file" || return 1
    if [[ -n ${MAXINE_AR_SRC:-} && $MAXINE_AR_SRC != /* ]]; then
        printf 'environment: MAXINE_AR_SRC must be an absolute path (got %s)\n' "$MAXINE_AR_SRC" >&2
        return 1
    fi
    if [[ -n ${MAXINE_AR_SRC:-} ]]; then
        maxine_ar_src=$MAXINE_AR_SRC maxine_ar_src_from=environment
    elif [[ -n $maxine_ar_file_src ]]; then
        maxine_ar_src=$maxine_ar_file_src maxine_ar_src_from=$name
    else
        maxine_ar_src=$2 maxine_ar_src_from=default
    fi
    if [[ -n ${MAXINE_AR_ARCHS:-} ]]; then
        maxine_ar_archs=$MAXINE_AR_ARCHS maxine_ar_archs_from=environment
    elif [[ -n $maxine_ar_file_archs ]]; then
        maxine_ar_archs=$maxine_ar_file_archs maxine_ar_archs_from=$name
    else
        maxine_ar_archs=$3 maxine_ar_archs_from=default
    fi
    if [[ -n ${MAXINE_AR_FEATURES:-} ]]; then
        maxine_ar_features=$MAXINE_AR_FEATURES maxine_ar_features_from=environment
    elif [[ -n $maxine_ar_file_features ]]; then
        maxine_ar_features=$maxine_ar_file_features maxine_ar_features_from=$name
    else
        maxine_ar_features=$4 maxine_ar_features_from=default
    fi
}

# maxine_ar_print_resolved: one line per value, with where it came from.
maxine_ar_print_resolved() {
    printf '  MAXINE_AR_SRC=%s (from %s)\n' "$maxine_ar_src" "$maxine_ar_src_from"
    printf '  MAXINE_AR_ARCHS=%s (from %s)\n' "$maxine_ar_archs" "$maxine_ar_archs_from"
    printf '  MAXINE_AR_FEATURES=%s (from %s)\n' "$maxine_ar_features" "$maxine_ar_features_from"
}
