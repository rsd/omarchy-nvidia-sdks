#!/usr/bin/env bash
# Tests for scripts/check-ngc.sh. No network and no real NGC CLI: the script
# runs with PATH set to stubs of `ngc` and `curl` and links to the few basic
# tools it needs, all under mktemp. HOME is a temporary directory too, so
# nothing of the real ~/.ngc or ~/.curlrc can be read.
# The stub ngc answers per $NGC_WHO and $NGC_PROBE, and `registry model info`
# per $NGC_EA (the speaker_focus models) and $NGC_MODEL (any other); 402 is
# HTTP 402 Payment Required, with a sentinel key echoed back. The stub curl answers per
# $CURL_MODE with the HTTP status on stdout (as -w '\n%{http_code}' does). Both
# log their arguments, and log "keyenv <name>" when NGC_API_KEY, or any
# variable holding a sentinel, is in their environment, which must never
# happen; curl also saves its stdin, where the key must be (and must not be
# in its arguments). Some modes echo the key or
# token-like strings back on stderr, to check that check-ngc.sh masks them.
# The test keys are sentinels, never real keys.
# Usage: scripts/tests/check-ngc-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
script=$top/scripts/check-ngc.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { # check <description> <command...>
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}
says() { grep -qF -- "$1" <<<"$out"; } # says <fragment>: the output has it
not() { ! "$@"; }
logged() { grep -qF -- "$1" "$tmp/calls"; } # logged <fragment>: a stub logged it

# The sentinels: one with the nvapi- prefix, one short and plain with a quote
# and a backslash (only the exact-key replacement of mask can hide it, and it
# exercises curl's config escaping).
key1='nvapi-SENTINELabc123def456ghi789jkl012mno345'
key2='Sx"q\7Kz'
# shellcheck disable=SC2016 # a literal $oauthtoken, as curl's config holds it
key2_conf='user = "$oauthtoken:Sx\"q\\7Kz"'
leaks() { # leaks: the output holds a sentinel or a part of one
    grep -qE 'SENTINEL|Sx"q|7Kz' <<<"$out"
}

# Basic tools, linked; jq when present (the org names need it).
base=$tmp/base
mkdir -p "$base"
for t in bash cat sed grep head env dirname jq; do
    p=$(command -v "$t" || true)
    [[ -n $p ]] && ln -s "$p" "$base/$t"
done

stubs=$tmp/stubs
mkdir -p "$stubs"
cat >"$stubs/ngc" <<'STUB'
#!/usr/bin/env bash
log=$STUB_DIR/calls
echo "ngc $*" >>"$log"
[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv ngc" >>"$log"
! env | grep -qE 'SENTINEL|7Kz' || echo "keyenv-value ngc" >>"$log"
case "$1 $2" in
    "user who")
        case ${NGC_WHO:-ok} in
            ok)
                echo '{"user": {"name": "Jane Private", "email": "jane@example.invalid", "roles": [{"org": {"name": "0123abcd", "displayName": "Jane"}, "team": {"name": "no-team"}}]}}'
                ;;
            unauth)
                echo 'Error: Invalid apikey nvapi-SENTINELechoedBack0000 Bearer abc.def.ghi' >&2
                exit 1
                ;;
            expired)
                echo '{"error": "401 Unauthorized: the API key has expired"}'
                exit 1
                ;;
            missing)
                echo 'Error: Missing API key and missing Email Authentication. Run ngc config set.' >&2
                exit 1
                ;;
            down)
                echo 'Error: Connection timed out (token: "abcdefghijklmnopqrstuvwxyz0123456789ABCD")' >&2
                exit 1
                ;;
        esac
        ;;
    "registry resource")
        case ${NGC_PROBE:-ok} in
            ok) echo '{"name": "vfx_sdk_core", "totalFileCount": 10, "totalSizeInBytes": 12345}' ;;
            denied)
                echo 'Error: 403 Response: Access Denied' >&2
                exit 1
                ;;
            notfound)
                echo "Error: Target 'nvidia/maxine/vfx_sdk_core:1.3.0.0_linux' could not be found." >&2
                exit 1
                ;;
            fail)
                echo 'Error: 503 Service Unavailable' >&2
                exit 1
                ;;
        esac
        ;;
    "registry model")
        mode=${NGC_MODEL:-ok}
        [[ $4 != *speaker_focus* ]] || mode=${NGC_EA:-ok}
        case $mode in
            ok) echo '{"modelVersion": {"totalFileCount": 1, "totalSizeInBytes": 4020}, "files": [{"path": "lib.so"}]}' ;;
            402)
                echo "Error: 402 Response: Payment Required (apikey nvapi-SENTINELechoedBack0000)" >&2
                exit 1
                ;;
            denied)
                echo 'Error: 403 Response: Access Denied' >&2
                exit 1
                ;;
            fail)
                echo 'Error: 503 Service Unavailable' >&2
                exit 1
                ;;
        esac
        ;;
esac
exit 0
STUB
cat >"$stubs/curl" <<'STUB'
#!/usr/bin/env bash
log=$STUB_DIR/calls
printf '%s\n' "$@" >"$STUB_DIR/curl.argv"
echo "curl $*" >>"$log"
[[ -z ${NGC_API_KEY+set} ]] || echo "keyenv curl" >>"$log"
! env | grep -qE 'SENTINEL|7Kz' || echo "keyenv-value curl" >>"$log"
[[ -z ${SSLKEYLOGFILE+set} ]] || echo "sslkeylog curl" >>"$log"
cat >"$STUB_DIR/curl.stdin"
case ${CURL_MODE:-200} in
    200) printf '\n200' ;;
    401) printf '\n401' ;;
    400) printf '\n400' ;;
    402) printf '\n402' ;;
    403) printf '\n403' ;;
    500) printf '\n500' ;;
    unreachable)
        echo 'curl: (6) Could not resolve host: authn.nvidia.com' >&2
        printf '\n000'
        exit 6
        ;;
    echo)
        # Echo the whole config (with the key) back on stderr.
        printf 'curl: (7) Failed: %s\n' "$(cat "$STUB_DIR/curl.stdin")" >&2
        printf '\n000'
        exit 7
        ;;
esac
STUB
chmod +x "$stubs/ngc" "$stubs/curl"
nongc=$tmp/nongc nocurl=$tmp/nocurl
mkdir -p "$nongc" "$nocurl"
ln -s "$stubs/curl" "$nongc/curl"
ln -s "$stubs/ngc" "$nocurl/ngc"

home=$tmp/home
mkdir -p "$home"

out='' rc=0
# cn <path dirs> <VAR=value...> -- <args...>: runs check-ngc.sh with stdin
# from $cn_in (default: empty), stdout and stderr in $out, status in $rc.
cn_in=''
cn() {
    local dirs=$1
    shift
    local -a vars=()
    while [[ $1 != -- ]]; do
        vars+=("$1")
        shift
    done
    shift
    : >"$tmp/calls"
    rm -f "$tmp/curl.argv" "$tmp/curl.stdin"
    rc=0
    out=$(printf '%s' "$cn_in" | env -i HOME="$home" PATH="$dirs:$base" STUB_DIR="$tmp" \
        SSLKEYLOGFILE="$tmp/sslkeys" "${vars[@]}" "$base/bash" "$script" "$@" 2>&1) || rc=$?
}
no_keyenv() { not logged keyenv; }

# --help
cn "$stubs" -- --help
check "--help exits 0" test "$rc" -eq 0
check "--help names --key and --no-cli" says "--no-cli"
cn "$stubs" -- --bogus
check "an unknown option is a usage error (2)" test "$rc" -eq 2
check "an unknown option is not shown" not says "--bogus"
cn "$stubs" -- --key "$key1"
check "a key given as an argument: usage error (2)" test "$rc" -eq 2
check "a key given as an argument: not shown" not leaks
check "a key given as an argument: says it is not shown" says "unknown argument (not shown"
check "a key given as an argument: nothing ran" not logged "curl "
cn "$stubs" -- --no-cli
check "--no-cli without a key is a usage error (2)" test "$rc" -eq 2

# (a) ngc missing
cn "$nongc" --
check "ngc missing: exit 1" test "$rc" -eq 1
check "ngc missing: says NGC CLI not found" says "FAIL NGC CLI not found"
check "ngc missing: hint names the install section" says "docs/download.md#3-install-the-ngc-cli"
check "ngc missing: the other CLI checks are skipped" says "SKIP Maxine access"

# (b) the CLI's key
cn "$stubs" NGC_WHO=ok NGC_PROBE=ok --
check "CLI ok: exit 0" test "$rc" -eq 0
check "CLI ok: key accepted" says "OK   the NGC CLI's key is accepted"
check "CLI ok: Maxine access" says "OK   Maxine access: the NGC CLI can see nvidia/maxine/vfx_sdk_core:"
check "CLI ok: the core ref is download.sh's" says "vfx_sdk_core:$(sed -nE 's/^version=([0-9.]+)$/\1/p' "$top/maxine-vfx/download.sh")_linux"
check "CLI ok: no name or e-mail printed" not grep -qiE 'Jane|example\.invalid' <<<"$out"
if [[ -e $base/jq ]]; then
    check "CLI ok: org printed (jq present)" says "org/team: 0123abcd, no-team"
fi
check "CLI ok: ngc user who ran with JSON output" logged "ngc user who --format_type json"
check "CLI ok: ngc never ran with --debug" not logged "--debug"
check "CLI ok: the key check did not run (no key)" not logged "curl "

cn "$stubs" NGC_WHO=unauth --
check "CLI unauthorized: exit 1" test "$rc" -eq 1
check "CLI unauthorized: invalid or expired" says "FAIL the NGC CLI's key is invalid or expired"
check "CLI unauthorized: hint to make a new key" says "org.ngc.nvidia.com/setup/personal-keys"
check "CLI unauthorized: ngc config set yourself" says "run \`ngc config set\` yourself"
check "CLI unauthorized: Maxine probe skipped" says "SKIP Maxine access"
check "CLI unauthorized: echoed key and bearer masked" not grep -qE 'SENTINEL|abc\.def\.ghi' <<<"$out"
check "CLI unauthorized: ngc's message shown, masked" says "Invalid apikey ****"

cn "$stubs" NGC_WHO=expired --
check "CLI expired: invalid or expired" says "FAIL the NGC CLI's key is invalid or expired"
check "CLI expired: the JSON error is shown" says "the API key has expired"

cn "$stubs" NGC_WHO=missing --
check "CLI not configured: exit 1" test "$rc" -eq 1
check "CLI not configured: says no key configured" says "FAIL the NGC CLI has no key configured"
check "CLI not configured: hint ngc config set" says "run \`ngc config set\` yourself"

cn "$stubs" NGC_WHO=down --
check "CLI other error: could not check" says "FAIL could not check the NGC CLI's key"
check "CLI other error: token value masked" not says "abcdefghijklmnopqrstuvwxyz0123456789ABCD"

cn "$stubs" NGC_WHO=ok NGC_PROBE=denied --
check "Maxine denied: exit 1" test "$rc" -eq 1
check "Maxine denied: no access to nvidia/maxine" says "FAIL no access to the Maxine org/team (nvidia/maxine)"
check "Maxine denied: hint Get Access" says "Get Access"
check "Maxine denied: the probe was read-only info" logged "ngc registry resource info nvidia/maxine/vfx_sdk_core:"
cn "$stubs" NGC_WHO=ok NGC_PROBE=notfound --
check "Maxine not found: no access" says "FAIL no access to the Maxine org/team"
cn "$stubs" NGC_WHO=ok NGC_PROBE=fail --
check "Maxine probe failure: could not check" says "FAIL could not check Maxine access"

# (b2) model access: the Early Access models of maxine-afx/download.sh, and
# --model.
afx_v=$(sed -nE 's/^version=([0-9.]+)$/\1/p' "$top/maxine-afx/download.sh")
sf_ref="nvidia/maxine/afx_speaker_focus:$afx_v-lib"
sf_url="https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_speaker_focus"
cn "$stubs" NGC_WHO=ok NGC_PROBE=ok --
check "models ok: the Early Access library is probed read-only, with its files" \
    logged "ngc registry model info $sf_ref --files --format_type json"
check "models ok: one probe for the two Early Access rates" test "$(grep -c 'registry model info' "$tmp/calls")" = 1
check "models ok: OK model" says "OK   model $sf_ref"
check "models ok: no download" not logged "download-version"

cn "$stubs" NGC_WHO=ok NGC_EA=402 NGC_API_KEY="$key1" -- --model nvidia/maxine/afx_denoiser:3.0.0-lib
check "402: exit 1" test "$rc" -eq 1
check "402: key valid, no access to the model" \
    says "FAIL key valid, no access to model $sf_ref (HTTP 402: Early Access or an entitlement)"
check "402: hint names its NGC page" says "hint: request access on its NGC page: $sf_url"
check "402: the --model one is OK" says "OK   model nvidia/maxine/afx_denoiser:3.0.0-lib"
check "402: --model probed" logged "ngc registry model info nvidia/maxine/afx_denoiser:3.0.0-lib --files --format_type json"
check "402: the key check still ran" says "OK   the key is accepted"
check "402: no leak" not leaks
check "402: ngc and curl never get NGC_API_KEY" no_keyenv

cn "$stubs" NGC_WHO=ok NGC_MODEL=402 -- --model acme/team1/thing:1.0 --model acme/team1/other:2.0
check "--model 402: exit 1" test "$rc" -eq 1
check "--model 402: both reported" says "no access to model acme/team1/other:2.0 (HTTP 402"
check "--model 402: the hint URL is the model's" says "https://catalog.ngc.nvidia.com/orgs/acme/teams/team1/models/thing"
check "--model 402: the Early Access model is still OK" says "OK   model $sf_ref"
check "--model 402: no leak" not leaks

cn "$stubs" NGC_WHO=ok NGC_EA=denied --
check "model 403: the existing no-access wording" says "FAIL no access to the Maxine org/team (nvidia/maxine): $sf_ref"
check "model 403: hint Get Access" says "Get Access"
cn "$stubs" NGC_WHO=ok NGC_MODEL=denied -- --model acme/team1/thing:1.0
check "model 403 elsewhere: names the org/team" says "FAIL no access to the acme/team1 org/team: acme/team1/thing:1.0"
cn "$stubs" NGC_WHO=ok NGC_EA=fail --
check "model probe failure: could not check" says "FAIL could not check model $sf_ref (ngc said: Error: 503"

cn "$stubs" NGC_WHO=ok NGC_PROBE=denied -- --model acme/team1/thing:1.0
check "no Maxine access: Early Access models skipped" says "SKIP Early Access models"
check "no Maxine access: --model still probed" says "OK   model acme/team1/thing:1.0"
cn "$stubs" NGC_WHO=unauth --
check "key not accepted: model access skipped" says "SKIP model access"
check "key not accepted: no model probed" not logged "registry model"

cn "$stubs" -- --model "$key1"
check "--model with an invalid value: usage error (2)" test "$rc" -eq 2
check "--model with an invalid value: the value is not printed" not leaks
cn "$stubs" -- --model
check "--model without a value: usage error (2)" test "$rc" -eq 2
cn "$stubs" NGC_API_KEY="$key1" -- --no-cli --model acme/team1/thing:1.0
check "--model with --no-cli: usage error (2)" test "$rc" -eq 2
check "--model with --no-cli: no leak" not leaks

# (c) a key of your own
cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=200 -- --key
check "env key OK (with CLI checks): exit 0" test "$rc" -eq 0
check "env key OK: accepted" says "OK   the key is accepted by NGC's API"
check "env key: ngc and curl never get NGC_API_KEY" no_keyenv
check "env key: the stub ngc ran (so keyenv is meaningful)" logged "ngc user who"
check "env key: key absent from curl's argv" not grep -qF "SENTINEL" "$tmp/curl.argv"
check "personal key: sent as a Bearer header in curl's stdin config" \
    grep -qxF "header = \"Authorization: Bearer $key1\"" "$tmp/curl.stdin"
check "personal key: no token exchange" not grep -qF "oauthtoken" "$tmp/curl.stdin"
check "env key: curl reads its config from stdin, no curlrc" grep -qxF -- "-q" "$tmp/curl.argv"
check "personal key: curl got the library's file list URL (read-only, as download_features.sh)" \
    grep -qxF "https://api.ngc.nvidia.com/v2/org/nvidia/team/maxine/models/afx_denoiser/$(sed -nE 's/^version=([0-9.]+)$/\1/p' "$top/maxine-afx/download.sh")-lib/files" "$tmp/curl.argv"
check "personal key: not the token URL" not grep -qF "authn.nvidia.com" "$tmp/curl.argv"
check "personal key: no redirect followed, no upload" not grep -qxE -- '-L|--location|-d|--data|-T|-X' "$tmp/curl.argv"
check "env key: body to /dev/null" grep -qxF "/dev/null" "$tmp/curl.argv"
check "env key: SSLKEYLOGFILE dropped for curl" not logged "sslkeylog curl"
check "env key OK: no leak" not leaks

cn "$stubs" NGC_API_KEY="$key1" -- --no-cli
check "NGC_API_KEY alone enables the key check" says "OK   the key is accepted"
check "--no-cli: ngc not run" not logged "ngc "

cn "$stubs" NGC_API_KEY="$key2" CURL_MODE=200 -- --key --no-cli
check "escaped key: curl's config escapes \\ and \"" grep -qxF "$key2_conf" "$tmp/curl.stdin"
check "escaped key: absent from argv" not grep -qE '7Kz' "$tmp/curl.argv"
check "legacy key: accepted by the token service" says "OK   the key is accepted by NGC's token service"
check "legacy key: curl got the token URL" grep -qF "https://authn.nvidia.com/token?service=ngc&scope=group/ngc:nvidia" "$tmp/curl.argv"
check "legacy key: no Bearer header" not grep -qF "Bearer" "$tmp/curl.stdin"

cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=401 -- --key --no-cli
check "env key 401: exit 1" test "$rc" -eq 1
check "env key 401: invalid or expired" says "FAIL the key is invalid or expired (NGC answered HTTP 401)"
check "env key 401: hint new key" says "org.ngc.nvidia.com/setup/personal-keys"
check "env key 401: no leak" not leaks

cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=403 -- --key --no-cli
check "personal key 403: invalid or expired" says "FAIL the key is invalid or expired (NGC answered HTTP 403"
check "personal key 403: hint names Maxine access" says "Get Access"
check "personal key 403: no leak" not leaks
cn "$stubs" NGC_API_KEY="$key2" CURL_MODE=403 -- --key --no-cli
check "legacy key 403: invalid or expired" says "FAIL the key is invalid or expired (NGC answered HTTP 403)"
cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=400 -- --key --no-cli
check "personal key 400 (NGC's answer to an unknown key): invalid or expired" \
    says "FAIL the key is invalid or expired, or has no permission for nvidia/maxine/afx_denoiser:"
check "personal key 400: hint new key" says "org.ngc.nvidia.com/setup/personal-keys"
check "personal key 400: no leak" not leaks
cn "$stubs" NGC_API_KEY="$key2" CURL_MODE=400 -- --key --no-cli
check "legacy key 400: could not check" says "FAIL could not check the key: NGC answered HTTP 400"
cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=402 -- --key --no-cli
check "personal key 402: exit 1" test "$rc" -eq 1
check "personal key 402: valid, not entitled" says "FAIL the key is valid, but the account is not entitled to nvidia/maxine/afx_denoiser:"
check "personal key 402: no leak" not leaks

cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=500 -- --key --no-cli
check "env key 500: could not check" says "FAIL could not check the key: NGC answered HTTP 500"

cn "$stubs" NGC_API_KEY="$key1" CURL_MODE=unreachable -- --key --no-cli
check "unreachable: exit 1" test "$rc" -eq 1
check "unreachable: could not reach NGC" says "FAIL could not reach NGC's API (curl exit 6: curl: (6) Could not resolve host"
check "unreachable: hint network" says "check the network"

for k in "$key1" "$key2"; do
    cn "$stubs" NGC_API_KEY="$k" CURL_MODE=echo -- --key --no-cli
    check "curl echoing the key back: masked (${#k} chars)" not leaks
    check "curl echoing the key back: still reported" says "FAIL could not reach NGC's"
done

cn "$nocurl" NGC_API_KEY="$key1" -- --key --no-cli
check "curl missing: exit 1" test "$rc" -eq 1
check "curl missing: says so" says "FAIL curl not found"
check "curl missing: no leak" not leaks

# The key from stdin (a pipe here).
cn_in="$key2"$'\n'
cn "$stubs" CURL_MODE=200 -- --key --no-cli
cn_in=''
check "stdin key: accepted" says "OK   the key is accepted"
check "stdin key: reached curl's config" grep -qxF "$key2_conf" "$tmp/curl.stdin"
check "stdin key: no leak" not leaks
cn "$stubs" -- --key --no-cli
check "--key with no key at all: usage error (2)" test "$rc" -eq 2

# allexport (bash -a, SHELLOPTS=allexport): no child gets the key in its
# environment, whether from NGC_API_KEY or from stdin.
for k in "$key1" "$key2"; do
    rc=0
    : >"$tmp/calls"
    out=$(printf '' | env -i HOME="$home" PATH="$stubs:$base" STUB_DIR="$tmp" NGC_API_KEY="$k" \
        "$base/bash" -a "$script" --key 2>&1) || rc=$?
    check "bash -a, env key (${#k} chars): the stubs ran" logged "curl "
    check "bash -a, env key (${#k} chars): no child has it in its environment" no_keyenv
    check "bash -a, env key (${#k} chars): no leak" not leaks
    rc=0
    : >"$tmp/calls"
    out=$(printf '%s\n' "$k" | env -i HOME="$home" PATH="$stubs:$base" STUB_DIR="$tmp" SHELLOPTS=allexport \
        "$base/bash" "$script" --key 2>&1) || rc=$?
    check "SHELLOPTS=allexport, stdin key (${#k} chars): accepted" says "OK   the key is accepted"
    check "SHELLOPTS=allexport, stdin key (${#k} chars): no child has it in its environment" no_keyenv
    check "SHELLOPTS=allexport, stdin key (${#k} chars): no leak" not leaks
done

# xtrace
rc=0
out=$(printf '' | env -i HOME="$home" PATH="$stubs:$base" STUB_DIR="$tmp" NGC_API_KEY="$key1" \
    "$base/bash" -x "$script" --key --no-cli 2>&1) || rc=$?
check "bash -x with NGC_API_KEY: refuses (2)" test "$rc" -eq 2
check "bash -x with NGC_API_KEY: says xtrace" says "xtrace"
check "bash -x with NGC_API_KEY: no leak" not leaks
rc=0
: >"$tmp/calls"
out=$(printf '%s\n' "$key2" | env -i HOME="$home" PATH="$stubs:$base" STUB_DIR="$tmp" \
    "$base/bash" -x "$script" --key --no-cli 2>&1) || rc=$?
check "bash -x --key (stdin): refuses (2)" test "$rc" -eq 2
check "bash -x --key (stdin): curl never ran" not logged "curl "
check "bash -x --key (stdin): no leak" not leaks

# The key never reaches stdout or stderr in any run above (checked per
# case); and the script never names ~/.ngc as a path it reads.
no_ngc_path() { grep -vE '^[[:space:]]*#' "$script" | grep -qE '(~|HOME}?|^|[[:space:]"])/?\.ngc(/|[[:space:]"]|$)'; }
check "check-ngc.sh names no ~/.ngc path outside comments" not no_ngc_path

echo "$((count - fails))/$count passed"
((fails == 0))
