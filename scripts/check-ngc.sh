#!/usr/bin/env bash
# Read-only check of your NGC credentials. It changes nothing, downloads no
# SDK file and never reads ~/.ngc itself.
#
# Without options it checks the NGC CLI: that `ngc` is installed, that the
# key configured in it (`ngc config set`) is accepted by NGC (`ngc user who`,
# NGC's own validation) and that it can see the Video Effects SDK core
# (`ngc registry resource info`, the item maxine-vfx/download.sh probes
# first), which needs Maxine access. Then it checks that the account is
# entitled to the Audio Effects SDK's Early Access models (their names and
# the SDK version are read from maxine-afx/download.sh as text, never run)
# and to each model named with --model: a valid key on an account that is
# not entitled gets HTTP 402 (Early Access or an enterprise entitlement).
# The probe is `ngc registry model info REF --files`, read-only: the NGC CLI
# has no dry run for download-version, and info can succeed for a model
# whose files are gated, so an OK there does not rule out a 402 at download
# time.
#
# With --key, or when NGC_API_KEY is set, it also checks a key given to it,
# with curl, and only the HTTP status is kept. A personal key (nvapi-...) is
# sent as a Bearer token to NGC's API, as NVIDIA's download_features.sh sends
# it, in a read-only request for the file list of a feature library that is
# not Early Access (the request that script makes first); any other key goes
# to NVIDIA's token service (authn.nvidia.com), which that script uses for
# them. The key is taken from NGC_API_KEY, or read
# from stdin (without echo on a terminal; a pipe works too, for example from
# a password manager). It never appears on a command line: curl reads it from
# a config on stdin, written by printf (a shell builtin). Whatever NGC
# returns goes to /dev/null. The key is never passed to `ngc`, never written
# to a file and never printed: every message from ngc or curl that is shown
# is masked first (see mask).
#
# Exit status: 0 every check passed, 1 a check failed, 2 usage error.
set -euo pipefail
# The key, first of all: taken into a shell variable that is not exported and
# removed from the environment before any external command runs, so that no
# child (ngc, curl, jq) ever receives it in its environment. xtrace is off
# while the key is read, so that a `bash -x` run does not print it, and a key
# check refuses to run under xtrace. `set -v` (verbose) prints the script's
# lines as read, never an expanded value, so it cannot show the key.
# allexport (`bash -a`, SHELLOPTS=allexport, a BASH_ENV that sets it) would
# export every variable assigned, the key too: it is turned off for good,
# nothing here needs it.
case $- in *x*) cn_xtrace=1 ;; *) cn_xtrace=0 ;; esac
set +x +a
declare +x key=${NGC_API_KEY-}
unset NGC_API_KEY
if [[ -n $key ]]; then env_key=1; else env_key=0; fi
if ((cn_xtrace && env_key)); then
    key=''
    printf 'check-ngc.sh: refusing to check a key under xtrace (bash -x): it would print the key\n' >&2
    exit 2
fi
((!cn_xtrace)) || set -x

prog=check-ngc.sh
repo=$(cd "$(dirname "$0")/.." && pwd)

usage_error() {
    key=''
    printf '%s: %s\n' "$prog" "$*" >&2
    printf 'Run %s --help for the options.\n' "$prog" >&2
    exit 2
}
say() { printf '%s\n' "$*"; }

usage() {
    cat <<USAGE
Usage: scripts/check-ngc.sh [--key] [--no-cli] [--model ORG/TEAM/NAME:VERSION]...

Checks your NGC credentials, read-only. One line per check (OK, FAIL or
SKIP), with a hint after each FAIL.

  (no option)  check the NGC CLI: that \`ngc\` is installed, that the key
               configured in it is accepted (\`ngc user who\`) and that it
               can see the Maxine SDK core (\`ngc registry resource info\`),
               and the account's access to the Audio Effects SDK's Early
               Access models (\`ngc registry model info --files\`)
  --model REF  also check access to this model, ORG/TEAM/NAME:VERSION
               (repeatable). HTTP 402 means the key is valid but the account
               is not entitled to it. info can succeed for a model whose
               files are gated: an OK does not rule out a 402 at download
               time
  --key        also check a key of your own: NGC_API_KEY when it is set,
               else read from stdin (no echo on a terminal; a pipe works
               too). A personal key (nvapi-...) is checked with a read-only
               NGC API request, as NVIDIA's download_features.sh uses it;
               any other key against NGC's token service. Setting
               NGC_API_KEY alone enables this check
  --no-cli     skip the NGC CLI checks (only the --key check)
  -h, --help   show this help

The key is never printed, never written to a file and never put on a
command line, so it is never an argument either: an unknown argument is
not shown. --key refuses to run under \`bash -x\`.

Exit status: 0 every check passed, 1 a check failed, 2 usage error.
USAGE
}

want_key=$env_key want_cli=1
models=()
model_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$'
while (($# > 0)); do
    case $1 in
        --key) want_key=1 ;;
        --no-cli) want_cli=0 ;;
        --model)
            (($# >= 2)) || usage_error "--model needs a value (ORG/TEAM/NAME:VERSION)"
            [[ $2 =~ $model_re ]] ||
                usage_error "invalid --model value (expected ORG/TEAM/NAME:VERSION, such as nvidia/maxine/afx_speaker_focus:3.0.0-lib)"
            models+=("$2")
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        # Never shown: \`--key nvapi-...\` is an easy mistake.
        *) usage_error "unknown argument (not shown: it may be a key; --key takes the key from NGC_API_KEY or stdin, never from an argument)" ;;
    esac
    shift
done
((want_cli || want_key)) || usage_error "--no-cli leaves nothing to check: add --key or set NGC_API_KEY"
((want_cli || ${#models[@]} == 0)) || usage_error "--model needs the NGC CLI checks: drop --no-cli"
if ((want_key)); then
    case $- in *x*) usage_error "refusing to check a key under xtrace (bash -x): it would print the key" ;; esac
fi

# mask: stdin to stdout, with the key (when known) and anything that looks
# like a key or a token replaced by ****. Every text from ngc or curl goes
# through it before it is printed. The key (and key_esc, its form in curl's
# config) is replaced by the shell, never passed to sed as an argument.
key_esc=''
mask() {
    local text
    text=$(cat)
    [[ -z $key_esc ]] || text=${text//"$key_esc"/****}
    [[ -z $key ]] || text=${text//"$key"/****}
    printf '%s\n' "$text" | sed -E \
        -e 's/nvapi-[A-Za-z0-9_-]+/****/g' \
        -e 's/(Bearer|Basic)[[:space:]]+[^[:space:]"]+/\1 ****/gI' \
        -e 's/"(token|access_token|apiKey|api_key|key)"[[:space:]]*:[[:space:]]*"[^"]*"/"\1": "****"/gI' \
        -e 's/oauthtoken:[^[:space:]"]*/oauthtoken:****/g' \
        -e 's#[A-Za-z0-9+/=_-]{32,}#****#g'
}
# first_error <text>: ngc's message, masked: the first line that names an
# error (an "update available" banner can come first), else the first line;
# the "error" field of a JSON answer; at most 300 characters.
first_error() {
    local line
    line=$(grep -m 1 -iE 'error|denied|not found|could not|invalid|unauthori|expired|missing|40[123]' <<<"$1" || true)
    [[ -n $line ]] || line=$(grep -m 1 -v '^[[:space:]]*$' <<<"$1" || true)
    if [[ $line =~ \"error\"[[:space:]]*:[[:space:]]*\"(.*)\" ]]; then
        line=${BASH_REMATCH[1]}
    fi
    line=$(printf '%s\n' "${line:0:300}" | mask)
    printf '%s\n' "$line"
}

failed=0
ok() { say "OK   $1"; }
skip() { say "SKIP $1"; }
fail() { # fail <message> <hint line...>
    local hint
    say "FAIL $1"
    shift
    for hint in "$@"; do say "     hint: $hint"; done
    failed=1
}

key_hint="create a new key at https://org.ngc.nvidia.com/setup/personal-keys (with the NGC Catalog service) and run \`ngc config set\` yourself"
access_hint="get Maxine access: log in at https://catalog.ngc.nvidia.com/orgs/nvidia/maxine/resources/vfx_sdk_core, select Get Access under NVIDIA Developer Program and accept the terms, with the account that owns the key; \`ngc config set\` must name the organisation that holds the access (docs/download.md, Prerequisites)"

# The SDK core of maxine-vfx/download.sh, read from it as text (never run);
# it always exists, so only access decides whether the CLI can see it.
vfx_version=$(sed -nE 's/^version=([0-9][0-9.]*)$/\1/p' "$repo/maxine-vfx/download.sh" 2>/dev/null | head -n 1 || true)
[[ -n $vfx_version ]] || vfx_version=1.3.0.0
core_ref="nvidia/maxine/vfx_sdk_core:${vfx_version}_linux"

# The Early Access effects of maxine-afx/download.sh and its library ref
# scheme, read from it as text (never run): one library per feature.
afx_dl=$repo/maxine-afx/download.sh
afx_version=$(sed -nE 's/^version=([0-9][0-9.]*)$/\1/p' "$afx_dl" 2>/dev/null | head -n 1 || true)
[[ -n $afx_version ]] || afx_version=3.0.0
afx_ea=$(sed -nE 's/^early_access=\(([a-z0-9_ -]*)\)$/\1/p' "$afx_dl" 2>/dev/null | head -n 1 || true)
[[ -n $afx_ea ]] || afx_ea='speaker_focus-16k speaker_focus-48k'
# lib_ref() { echo "nvidia/maxine/afx_$1:${version}-lib"; }: prefix, suffix.
# shellcheck disable=SC2016 # a literal $1 and ${version}, matched in the text
afx_lib=$(sed -nE 's/^lib_ref\(\) \{ echo "([a-z0-9_/]+)\$1:\$\{version\}([a-z0-9_.-]*)"; \}$/\1 \2/p' "$afx_dl" 2>/dev/null | head -n 1 || true)
[[ -n $afx_lib ]] || afx_lib='nvidia/maxine/afx_ -lib'
ea_refs=()
for e in $afx_ea; do
    ref="${afx_lib% *}${e%%-*}:$afx_version${afx_lib#* }"
    [[ $ref =~ $model_re ]] || continue
    case " ${ea_refs[*]} " in *" $ref "*) ;; *) ea_refs+=("$ref") ;; esac
done

# json_number <key> <text>: the first integer value of "key" in the text.
json_number() {
    { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" <<<"$2" || true; } |
        head -n 1 | sed 's/.*:[[:space:]]*//'
}
# orgs_of <json>: the org and team names in `ngc user who`'s answer, when jq
# is installed (nothing else of it, no name or e-mail, is ever printed).
orgs_of() {
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '[.. | objects | to_entries[]
            | select(.key | test("^(org|team)(name)?$"; "i")) | .value
            | if type == "object" then (.name // empty) elif type == "string" then . else empty end
            | select(test("^[A-Za-z0-9_.-]{1,64}$"))] | unique | join(", ")' <<<"$1" 2>/dev/null |
        mask || true
}

check_cli() {
    local ngc out rc=0 orgs msg
    if ! ngc=$(command -v ngc); then
        fail "NGC CLI not found (\`ngc\` is not on PATH)" \
            "install it into ~/.local/bin as in docs/download.md, \"3. Install the NGC CLI\" (docs/download.md#3-install-the-ngc-cli; download from https://api.ngc.nvidia.com/v2/resources/nvidia/ngc-apps/ngc_cli/versions/<version>/files/ngccli_linux.zip), and make sure ~/.local/bin is on PATH"
        skip "NGC CLI key (no NGC CLI)"
        skip "Maxine access (no NGC CLI)"
        skip "model access (no NGC CLI)"
        return 0
    fi
    ok "NGC CLI found: $ngc"

    # Never --debug: it can print request headers.
    out=$(ngc user who --format_type json 2>&1) || rc=$?
    if ((rc == 0)) && ! grep -qiE '"error"|unauthori|invalid api ?key|invalid apikey' <<<"$out"; then
        orgs=$(orgs_of "$out")
        if [[ -n $orgs ]]; then
            ok "the NGC CLI's key is accepted (org/team: $orgs)"
        else
            ok "the NGC CLI's key is accepted"
        fi
    else
        msg=$(first_error "$out")
        [[ -n $msg ]] || msg="ngc exited with status $rc"
        if grep -qiE 'missing api ?key|no api ?key|api ?key (is )?(required|not set|missing)|not configured|config(uration)? (file )?not found' <<<"$out"; then
            fail "the NGC CLI has no key configured (ngc said: $msg)" \
                "run \`ngc config set\` yourself and enter your key (docs/download.md, step 4)"
        elif grep -qiE '401|unauthori|invalid api ?key|invalid apikey|invalid key|expired|authenticat|ngc config set' <<<"$out"; then
            fail "the NGC CLI's key is invalid or expired (ngc said: $msg)" "$key_hint"
        else
            fail "could not check the NGC CLI's key (ngc said: $msg)" \
                "check the network and try again; see docs/download.md, Troubleshooting"
        fi
        skip "Maxine access (the NGC CLI's key is not accepted)"
        skip "model access (the NGC CLI's key is not accepted)"
        return 0
    fi

    rc=0
    out=$(ngc registry resource info "$core_ref" --format_type json 2>&1) || rc=$?
    if ((rc == 0)) && [[ -n $(json_number totalSizeInBytes "$out") ]]; then
        ok "Maxine access: the NGC CLI can see $core_ref"
        check_models "${ea_refs[@]}" "${models[@]}"
        return 0
    fi
    msg=$(first_error "$out")
    [[ -n $msg ]] || msg="ngc exited with status $rc"
    if grep -qiE 'Error: 403|403 Response|Access Denied|could not be found|not found|forbidden' <<<"$out"; then
        fail "no access to the Maxine org/team (nvidia/maxine): $core_ref (ngc said: $msg)" "$access_hint"
    else
        fail "could not check Maxine access (ngc said: $msg)" \
            "check the network and try again; see docs/download.md, Troubleshooting"
    fi
    # The Early Access models need Maxine access first; --model ones may not.
    ((${#ea_refs[@]} == 0)) || skip "Early Access models (${ea_refs[*]}): no Maxine access"
    check_models "${models[@]}"
}

# http402: an answer of HTTP 402 Payment Required in ngc's output (grep -iE):
# the key is valid, but the account is not entitled to the model.
http402='payment required|(error|status|response|http|code)[^0-9]{0,20}402([^0-9]|$)|(^|[^0-9.])402[[:space:]]+(payment|response|client)'
# check_models <ref...>: one line per model, read-only. `info --files` lists
# the version's files; the NGC CLI has no dry run for download-version, so
# this is the closest probe to the download, and a gated download can still
# answer 402 where this says OK.
check_models() {
    local ref out rc msg org team name
    for ref in "$@"; do
        rc=0
        out=$(ngc registry model info "$ref" --files --format_type json 2>&1) || rc=$?
        if ((rc == 0)) && ! grep -qiE '"error"' <<<"$out"; then
            ok "model $ref"
            continue
        fi
        if grep -qiE "$http402" <<<"$out"; then
            org=${ref%%/*} name=${ref#*/}
            team=${name%%/*} name=${name#*/}
            name=${name%%:*}
            fail "key valid, no access to model $ref (HTTP 402: Early Access or an entitlement)" \
                "request access on its NGC page: https://catalog.ngc.nvidia.com/orgs/$org/teams/$team/models/$name"
            continue
        fi
        msg=$(first_error "$out")
        [[ -n $msg ]] || msg="ngc exited with status $rc"
        if grep -qiE 'Error: 403|403 Response|Access Denied|could not be found|not found|forbidden' <<<"$out"; then
            org=${ref%%/*} team=${ref#*/}
            team=${team%%/*}
            if [[ $org/$team == nvidia/maxine ]]; then
                fail "no access to the Maxine org/team (nvidia/maxine): $ref (ngc said: $msg)" "$access_hint"
            else
                fail "no access to the $org/$team org/team: $ref (ngc said: $msg)" \
                    "check the name, and that \`ngc config set\` names an organisation with access to $org/$team"
            fi
        else
            fail "could not check model $ref (ngc said: $msg)" \
                "check the network and try again; see docs/download.md, Troubleshooting"
        fi
    done
}

token_url='https://authn.nvidia.com/token?service=ngc&scope=group/ngc:nvidia'
# A personal key: the file list of a feature library that is not Early
# Access, the same GET download_features.sh makes first with such a key
# (a JSON answer, no file is downloaded).
api_ref="nvidia/maxine/afx_denoiser:$afx_version${afx_lib#* }"
api_url="https://api.ngc.nvidia.com/v2/org/nvidia/team/maxine/models/afx_denoiser/$afx_version${afx_lib#* }/files"
check_key() {
    local out rc=0 code errs conf what url
    if [[ -z $key ]]; then
        [[ ! -t 0 ]] || printf 'NGC API key (not echoed): ' >&2
        IFS= read -rs key || true
        [[ ! -t 0 ]] || printf '\n' >&2
    fi
    if [[ -z $key ]]; then
        key=''
        usage_error "--key: no key given (set NGC_API_KEY or type it on stdin)"
    fi
    if [[ $key == *[[:cntrl:]]* ]]; then
        key=''
        fail "the key contains a control character" "copy the key again ($key_hint)"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        key=''
        fail "curl not found: the key check needs it" "install curl (pacman -S --needed curl)"
        return 0
    fi
    # curl's config syntax: a double-quoted value, with \ and " escaped.
    key_esc=${key//\\/\\\\}
    key_esc=${key_esc//\"/\\\"}
    # A personal key needs no token: download_features.sh sends it as the
    # Bearer token itself. Any other key is exchanged at the token service.
    if [[ $key == nvapi-* ]]; then
        what="NGC's API"
        conf="header = \"Authorization: Bearer $key_esc\""
        url=$api_url
    else
        what="NGC's token service"
        conf="user = \"\$oauthtoken:$key_esc\""
        url=$token_url
    fi
    # -q first: no ~/.curlrc (it could add --verbose or --trace and print
    # the Authorization header). SSLKEYLOGFILE is dropped for the same
    # reason. The config with the key reaches curl on stdin from printf, a
    # builtin: it is on no command line and in no file. No redirect is
    # followed.
    out=$(printf '%s\n' "$conf" |
        env -u SSLKEYLOGFILE curl -q -K - -sS -o /dev/null -w '\n%{http_code}' \
            --max-time 20 "$url" 2>&1) || rc=$?
    conf=''
    code=${out##*$'\n'}
    # A pipe, not a here-string: a large here-string can go to a temp file.
    errs=$(printf '%s\n' "${out%"$code"}" | mask | grep -v '^[[:space:]]*$' | head -n 1 || true)
    errs=${errs:0:300}
    key='' key_esc=''
    case $code in
        200) ok "the key is accepted by $what" ;;
        401) fail "the key is invalid or expired (NGC answered HTTP $code)" "$key_hint" ;;
        403)
            if [[ $what == "NGC's API" ]]; then
                fail "the key is invalid or expired (NGC answered HTTP $code for $api_ref)" "$key_hint" \
                    "if the key is new, the account may have no Maxine access: $access_hint"
            else
                fail "the key is invalid or expired (NGC answered HTTP $code)" "$key_hint"
            fi
            ;;
        400)
            # NGC's API answers an unknown or unauthorised personal key with
            # 400 INVALID_REQUEST ("API Key does not have correct permissions
            # (or subscriptions)"), not 401.
            if [[ $what == "NGC's API" ]]; then
                fail "the key is invalid or expired, or has no permission for $api_ref (NGC answered HTTP 400)" "$key_hint" \
                    "if the key is new, the account may have no Maxine access: $access_hint"
            else
                fail "could not check the key: NGC answered HTTP $code" "try again later"
            fi
            ;;
        402)
            fail "the key is valid, but the account is not entitled to $api_ref (HTTP 402: Early Access or an entitlement)" \
                "request access on its NGC page: https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_denoiser"
            ;;
        *)
            if [[ $code =~ ^[0-9]{3}$ && $code != 000 ]]; then
                fail "could not check the key: NGC answered HTTP $code" "try again later"
            else
                fail "could not reach $what (curl exit $rc${errs:+: $errs})" \
                    "check the network (and any proxy) and try again"
            fi
            ;;
    esac
}

((!want_cli)) || check_cli
((!want_key)) || check_key
key=''
exit "$failed"
