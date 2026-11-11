#!/usr/bin/env bash
# Tests for maxine-afx/download.sh against a FAKE ngc. Everything happens
# under mktemp: the script runs from a copy of itself (next to a stub
# configure.sh), with a fake HOME and a PATH that holds only the stubs and
# links to the basic tools it needs, so the real ngc, nvidia-smi, sudo,
# pacman and makepkg can never run. Every run is under setsid, without a
# terminal, so a test can never wait for an answer.
#
# The fake ngc answers from a catalogue file (kind, ref, bytes, files):
# `registry {model|resource} info REF --format_type json` with JSON (or the
# 403 text, or the unconfigured {"error": ...} JSON, exit 1), and
# `registry {model|resource} download-version REF --dest D` by creating
# D/<name>_v<tag>/ with that many files and bytes. A faults file
# (REF MODE COUNT) makes the first COUNT downloads of REF fail (fail),
# leave a partial directory and fail (partial), or succeed with one byte too
# many (wrong). An info-faults file (REF MESSAGE...) makes `info REF` print
# MESSAGE on stderr and exit 1 (a 503, a timeout, a 403...), and
# FAKE_NGC_BANNER=1 makes every `info` print an "update available" line first.
# Usage: maxine-afx/tests/download-test.sh. Exits non-zero on any failure.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
recipe=$(cd "$here/.." && pwd)

tmp=$(mktemp -d)
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

fails=0 count=0
ok() { count=$((count + 1)); echo "ok   $1"; }
fail() { count=$((count + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { # check <description> <command...>
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else fail "$desc"; fi
}
says() { grep -qF -- "$1" <<<"$all"; }        # says <fragment>: stdout or stderr has it
says_err() { grep -qE -- "$1" <<<"$err"; }    # says_err <regex>: stderr has it
not() { ! "$@"; }

setsid_bin=$(command -v setsid) || {
    echo "setsid (util-linux) is needed to run without a terminal" >&2
    exit 2
}

# The script, copied, next to a stub configure.sh that records its call.
mafx=$tmp/maxine-afx
mkdir -p "$mafx"
cp "$recipe/download.sh" "$mafx/"
dl=$mafx/download.sh
calls=$tmp/calls
: >"$calls"
cat >"$mafx/configure.sh" <<EOF
#!/usr/bin/env bash
echo "configure.sh \$*" >>$(printf %q "$calls")
EOF
chmod +x "$mafx/configure.sh"

# The basic tools, linked one by one: nothing else of the system is on PATH.
sysbin=$tmp/sysbin
mkdir -p "$sysbin"
for tool in bash env cat grep sed awk find mkdir rm mv rmdir head tail realpath dirname truncate wc tr; do
    ln -s "$(command -v "$tool")" "$sysbin/$tool"
done

# The stubs. ngc and nvidia-smi are fakes; sudo, pacman and makepkg record.
stub_dir() { # stub_dir <name> <tool...>: a directory with those stubs
    local d=$tmp/stubs-$1 tool
    shift
    mkdir -p "$d"
    for tool in "$@"; do cp "$tmp/stubs-src/$tool" "$d/"; done
    echo "$d"
}
mkdir -p "$tmp/stubs-src"
cat >"$tmp/stubs-src/ngc" <<'EOF'
#!/usr/bin/env bash
# A fake NGC CLI: see the header of download-test.sh.
set -euo pipefail
[[ ${1:-} == registry && $# -ge 4 ]] || {
    echo "ngc $* (unsupported)" >>"$FAKE_CALLS"
    exit 64
}
kind=$2 verb=$3 ref=$4
shift 4
line=$(awk -v k="$kind" -v r="$ref" '$1 == k && $2 == r { print; exit }' "$FAKE_NGC_CATALOGUE")
name=${ref%%:*} tag=${ref#*:}
name=${name##*/}
denied() {
    echo "Client Error: 403 Response: Access Denied - Request Id: fake-0000" >&2
    exit 1
}
case $verb in
    info)
        echo "ngc registry $kind info $ref $*" >>"$FAKE_CALLS"
        [[ "$*" == "--format_type json" ]] || exit 64
        [[ -z ${FAKE_NGC_BANNER:-} ]] ||
            echo "A newer version of the NGC CLI (9.9.9) is available. Current version: 4.36.6." >&2
        if [[ -f $FAKE_NGC_INFO_FAULTS ]]; then
            msg=$(awk -v r="$ref" '$1 == r { $1 = ""; sub(/^ /, ""); print; exit }' "$FAKE_NGC_INFO_FAULTS")
            if [[ -n $msg ]]; then
                echo "$msg" >&2
                exit 1
            fi
        fi
        if [[ ${FAKE_NGC_MODE:-} == unconfigured ]]; then
            echo "{\"error\": \"Error: Target '$ref' could not be found.\"}"
            exit 1
        fi
        [[ -n $line ]] || denied
        read -r _ _ bytes files <<<"$line"
        cat <<JSON
{
    "$kind": {
        "name": "$name",
        "latestVersionIdStr": "9.9.9.9_other",
        "latestVersionSizeInBytes": 123456789
    },
    "${kind}Version": {
        "status": "UPLOAD_COMPLETE",
        "totalFileCount": $files,
        "totalSizeInBytes": $bytes,
        "versionId": "$tag"
    }
}
JSON
        ;;
    download-version)
        [[ $# == 2 && $1 == --dest ]] || exit 64
        dir=$2/${name}_v$tag
        existing=''
        [[ -d $dir ]] && existing=' [existing]'
        echo "ngc registry $kind download-version $ref --dest $2$existing" >>"$FAKE_CALLS"
        [[ -n $line ]] || denied
        read -r _ _ bytes files <<<"$line"
        mode='' limit=0
        if [[ -f $FAKE_NGC_FAULTS ]]; then
            read -r _ mode limit < <(awk -v r="$ref" '$1 == r { print; exit }' "$FAKE_NGC_FAULTS") || true
        fi
        state=$FAKE_NGC_STATE/${ref//[^A-Za-z0-9._-]/_}
        used=0
        [[ -f $state ]] && used=$(<"$state")
        if [[ -n $mode ]] && ((used < limit)); then
            echo $((used + 1)) >"$state"
        else
            mode=good
        fi
        echo "Downloading $ref ($mode)"
        mkdir -p "$dir"
        case $mode in
            fail)
                echo "fake ngc: connection reset" >&2
                exit 1
                ;;
            partial)
                truncate -s 0 "$dir/file1.bin"
                echo "fake ngc: interrupted" >&2
                exit 1
                ;;
        esac
        for ((i = 1; i <= files; i++)); do
            size=1
            ((i < files)) || size=$((bytes - files + 1))
            [[ $mode == wrong && $i == 1 ]] && size=$((size + 1))
            truncate -s "$size" "$dir/file$i.bin"
        done
        echo "Download completed."
        ;;
    *) exit 64 ;;
esac
EOF
cat >"$tmp/stubs-src/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "nvidia-smi $*" >>"$FAKE_CALLS"
[[ "$*" == "--query-gpu=compute_cap --format=csv,noheader" ]] || exit 64
printf '%b\n' "$FAKE_SMI_OUT"
exit "${FAKE_SMI_RC:-0}"
EOF
# shellcheck disable=SC2016 # the stubs expand their own $* and $PWD
for tool in sudo pacman; do
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$FAKE_CALLS"\nexit 99\n' "$tool" >"$tmp/stubs-src/$tool"
done
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "makepkg $* in $PWD" >>"$FAKE_CALLS"\n' >"$tmp/stubs-src/makepkg"
chmod +x "$tmp/stubs-src"/*
stubs=$(stub_dir all ngc nvidia-smi sudo pacman makepkg)
stubs_nongc=$(stub_dir nongc nvidia-smi sudo pacman makepkg)
stubs_nosmi=$(stub_dir nosmi ngc sudo pacman makepkg)

# The catalogues: tiny sizes for downloads, the sizes of a real 3.0.0
# download for the table.
v=3.0.0
mx=nvidia/maxine
catalogue=$tmp/catalogue
cat >"$catalogue" <<EOF
resource $mx/maxine_linux_audio_effects_sdk:$v 300 3
model $mx/afx_denoiser:$v-lib 10 1
model $mx/afx_denoiser:$v-48k-sm120 80 4
model $mx/afx_denoiser:$v-48k-sm89 70 4
model $mx/afx_denoiser:$v-16k-sm120 60 4
model $mx/afx_dereverb:$v-lib 9 1
model $mx/afx_dereverb:$v-48k-sm120 30 2
model $mx/afx_dereverb_denoiser:$v-lib 8 1
model $mx/afx_dereverb_denoiser:$v-48k-sm120 20 2
model $mx/afx_studio_voice:$v-lib 12 1
model $mx/afx_studio_voice:$v-48k-sm120 90 6
model $mx/afx_superres:$v-lib 7 1
model $mx/afx_superres:$v-16k_to_48k-sm120 40 2
EOF
real_catalogue=$tmp/real-catalogue
cat >"$real_catalogue" <<EOF
resource $mx/maxine_linux_audio_effects_sdk:$v 1501636190 1
model $mx/afx_denoiser:$v-lib 1707630 1
model $mx/afx_denoiser:$v-48k-sm120 185854784 4
model $mx/afx_dereverb:$v-lib 1553866 1
model $mx/afx_dereverb:$v-48k-sm120 57478800 2
model $mx/afx_dereverb_denoiser:$v-lib 1707986 1
model $mx/afx_dereverb_denoiser:$v-48k-sm120 51375536 2
model $mx/afx_studio_voice:$v-lib 2503444 1
model $mx/afx_studio_voice:$v-48k-sm120 1281441760 6
EOF
faults=$tmp/faults
info_faults=$tmp/info-faults
state=$tmp/state
home=$tmp/home
mkdir -p "$state" "$home"

# run_with <stubdir> [VAR=value...] -- <args...>: download.sh in a clean
# environment, without a terminal. stdout in $out, stderr in $err, both in
# $all, the status in $status.
out='' err='' all='' status=0
run_with() {
    local sd=$1
    shift
    local -a vars=()
    while [[ $1 != -- ]]; do vars+=("$1") && shift; done
    shift
    status=0
    out=$(env -i HOME="$home" PATH="$sd:$sysbin" FAKE_CALLS="$calls" \
        FAKE_NGC_CATALOGUE="$catalogue" FAKE_NGC_FAULTS="$faults" FAKE_NGC_STATE="$state" \
        FAKE_NGC_INFO_FAULTS="$info_faults" \
        FAKE_SMI_OUT=12.0 "${vars[@]}" "$setsid_bin" -w "$dl" "$@" 2>"$tmp/err") || status=$?
    err=$(<"$tmp/err")
    all=$out$'\n'$err
}
run() { run_with "$stubs" -- "$@"; }
# fresh <name>: a new, absent destination in $dest; calls, faults and the
# fault counters cleared.
fresh() {
    dest=$tmp/dest/$1
    rm -rf -- "${dest:?}"
    : >"$calls"
    rm -f -- "${faults:?}" "${info_faults:?}"
    find "${state:?}" -mindepth 1 -delete
}
passes() { ((status == 0)) || { echo "status $status: $all"; return 1; }; }
fails_with() { # fails_with <status> <fragment>
    ((status == $1)) || { echo "status $status, not $1: $all"; return 1; }
    says "$2" || { echo "$all"; return 1; }
}
called() { grep -qF -- "$1" "$calls"; }        # called <fragment>
ncalls() { grep -cF -- "$1" "$calls" || true; } # ncalls <fragment>: how many calls have it
no_downloads() { not called download-version; }
# item <ref-tail> <dir>: a complete item in <dir> as the fake ngc makes it.
item() {
    local name=$1 dir=$2 line bytes files i size
    line=$(grep -F " $mx/$name " "$catalogue")
    read -r _ _ bytes files <<<"$line"
    local d=$dir/${name%%:*}_v${name#*:}
    mkdir -p "$d"
    for ((i = 1; i <= files; i++)); do
        size=1
        ((i < files)) || size=$((bytes - files + 1))
        truncate -s "$size" "$d/file$i.bin"
    done
}
complete() { # complete <dir> <files> <bytes>: the dir holds exactly that
    [[ -d $1 && $(find "$1" -type f | wc -l) == "$2" && $(find "$1" -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}') == "$3" ]]
}
table_row() { says_err "^$1.*  $2"; } # table_row <ref-tail regex> <status regex>

broadcast_dirs=("maxine_linux_audio_effects_sdk_v$v" "afx_denoiser_v$v-lib" "afx_denoiser_v$v-48k-sm120"
    "afx_dereverb_v$v-lib" "afx_dereverb_v$v-48k-sm120" "afx_dereverb_denoiser_v$v-lib"
    "afx_dereverb_denoiser_v$v-48k-sm120" "afx_studio_voice_v$v-lib" "afx_studio_voice_v$v-48k-sm120")
broadcast_features=denoiser,dereverb,dereverb_denoiser,studio_voice

echo "== options"
fresh opts
run --bogus
check "an unknown option is a usage error (2)" fails_with 2 "unknown argument: --bogus"
run --preset all --features denoiser-48k
check "--preset with --features is a usage error" fails_with 2 "give --preset or --features, not both"
run --preset bogus
check "an unknown preset is a usage error" fails_with 2 "unknown preset 'bogus'"
run --features denoiser
check "an effect without a rate is a usage error" fails_with 2 "invalid effect 'denoiser' (expected <feature>-<rate>"
# shellcheck disable=SC2016 # a literal $(id), never run
run --features 'de$(id)-48k'
check "an invalid effect is a usage error" fails_with 2 "invalid effect"
run --archs "all sm_120"
check "'all' with another architecture is a usage error" fails_with 2 "must be the only --archs entry"
run --archs 8.9
check "an architecture with a dot is a usage error" fails_with 2 "invalid architecture '8.9'"
run --version 3.0.0.12
check "a four-part version is a usage error" fails_with 2 "invalid version '3.0.0.12'"
run --retries x
check "a non-numeric --retries is a usage error" fails_with 2 "invalid --retries 'x'"
run --list --yes
check "--list with a download option is a usage error" fails_with 2 "--list takes only"
run --help
check "--help succeeds" passes
check "--help names the presets" says "--preset NAME    broadcast (default"
check "the options ran no ngc and no nvidia-smi" test ! -s "$calls"

echo "== architectures"
fresh arch
run --dry-run --dest "$dest"
check "auto: a dry run succeeds" passes
check "auto: nvidia-smi was asked the documented query" \
    called "nvidia-smi --query-gpu=compute_cap --format=csv,noheader"
check "auto: 12.0 is sm_120" says "GPU architecture (from nvidia-smi): sm_120"
check "auto: the sm_120 models are probed" called "info $mx/afx_denoiser:$v-48k-sm120 --format_type json"
fresh arch
run_with "$stubs" FAKE_SMI_OUT='12.0\n8.9\n12.0' -- --dry-run --dest "$dest"
check "several GPUs: the unique architectures in GPU order" says "GPU architecture (from nvidia-smi): sm_120 sm_89"
check "several GPUs: each architecture is probed once" test "$(ncalls "afx_denoiser:$v-48k-sm120 --format")" = 1
fresh arch
run_with "$stubs" FAKE_SMI_OUT=6.1 -- --dry-run --dest "$dest"
check "a GPU below 7.5 is refused" fails_with 1 "sm_61 is not supported: the SDK needs Turing (sm_75) or newer"
check "it probes nothing" not called "ngc "
fresh arch
run_with "$stubs_nosmi" -- --dry-run --dest "$dest"
check "no nvidia-smi: it stops and says to pass --archs" fails_with 1 "nvidia-smi not found"
fresh arch
run --dry-run --dest "$dest" --archs "sm120,120 89"
check "--archs skips nvidia-smi" not called nvidia-smi
check "--archs normalises and deduplicates" test "$(ncalls "afx_denoiser:$v-48k-sm120 --format")" = 1
check "--archs: sm_89 is probed" called "afx_denoiser:$v-48k-sm89 --format_type json"
fresh arch
run --dry-run --dest "$dest" --archs all
check "--archs all probes sm_75 to sm_120" test "$(grep -c "afx_denoiser:$v-48k-sm" "$calls")" = 7
fresh arch
run --dry-run --dest "$dest" --archs sm_87
check "an architecture outside the list is a warning" says "sm_87 is not an architecture NVIDIA's download script lists"
check "its models show as no model package" table_row "afx_denoiser:$v-48k-sm87" "no model package for 48k-sm87"

echo "== presets and --features"
fresh preset
run --dry-run --dest "$dest" --archs sm_120
check "default preset: the four 48k effects" test "$(grep -c -- '-lib --format' "$calls")" = 4
check "default preset: no 16k model is probed" not called "16k-sm120"
check "the core is probed as a resource" \
    called "ngc registry resource info $mx/maxine_linux_audio_effects_sdk:$v --format_type json"
fresh preset
run --dry-run --dest "$dest" --archs sm_120 --preset all
check "--preset all probes five libraries, once each" test "$(grep -c -- '-lib --format' "$calls")" = 5
check "--preset all probes superres 8k_to_16k" called "afx_superres:$v-8k_to_16k-sm120"
check "--preset all probes superres 16k_to_48k" called "afx_superres:$v-16k_to_48k-sm120"
check "--preset all probes the 16k studio voice" called "afx_studio_voice:$v-16k-sm120"
check "--preset all leaves the Early Access effect out" not called speaker_focus
fresh preset
run --dry-run --dest "$dest" --archs sm_120 --features denoiser-16k,denoiser-48k,denoiser-16k
check "--features replaces the preset" not called afx_studio_voice
check "--features: one library for two rates" test "$(ncalls "afx_denoiser:$v-lib --format")" = 1
check "--features: each effect once" test "$(ncalls "afx_denoiser:$v-16k-sm120 --format")" = 1
check "--features: the core is still fetched" called "maxine_linux_audio_effects_sdk:$v"

echo "== dry run"
fresh dry
run --dry-run --dest "$dest" --archs sm_120
check "a dry run succeeds" passes
check "it downloads nothing" no_downloads
check "it creates no destination" test ! -e "$dest"
check "stdout holds the nine download commands" test "$(wc -l <<<"$out")" = 9
check "stdout holds only download commands into the staging directory" \
    not grep -qvE "^ngc registry (model|resource) download-version $mx/[a-z_]+:$v(-[a-z0-9_]+)* --dest $dest/\.partial\$" <<<"$out"
check "the core is a resource download" \
    grep -qxF "ngc registry resource download-version $mx/maxine_linux_audio_effects_sdk:$v --dest $dest/.partial" <<<"$out"
check "the table is on stderr" says_err "^item +size +files +status"
check "the next steps are on stderr" says_err "Next steps, once the download is complete"
fresh dry
run_with "$stubs" FAKE_NGC_CATALOGUE="$real_catalogue" -- --dry-run --dest "$dest" --archs sm_120
check "sizes: the core in GiB" table_row "maxine_linux_audio_effects_sdk:$v +1.40 GiB +1" "missing"
check "sizes: the studio voice models in GiB" table_row "afx_studio_voice:$v-48k-sm120 +1.19 GiB +6" "missing"
check "sizes: the broadcast total for sm_120" says "To download: 9 item(s), 2.87 GiB (3085259996 bytes)"
fresh dry
run --dry-run --archs sm_120
check "the default destination is ~/Downloads/maxine/afx-sdk" \
    grep -qxF "ngc registry resource download-version $mx/maxine_linux_audio_effects_sdk:$v --dest $home/Downloads/maxine/afx-sdk/.partial" <<<"$out"
check "it is not created" test ! -e "$home/Downloads/maxine"

echo "== status of each item"
fresh status
item "maxine_linux_audio_effects_sdk:$v" "$dest"
item "afx_denoiser:$v-lib" "$dest"
item "afx_denoiser:$v-48k-sm120" "$dest"
truncate -s 2 "$dest/afx_denoiser_v$v-48k-sm120/file1.bin"
before=$(cd "$dest" && find . -printf '%p %s\n' | sort)
run --dry-run --dest "$dest" --archs sm_120
check "the core is present" table_row "maxine_linux_audio_effects_sdk:$v" "present$"
check "a complete library is present" table_row "afx_denoiser:$v-lib" "present$"
check "a byte mismatch is incomplete" table_row "afx_denoiser:$v-48k-sm120" "incomplete \(will download again\)"
check "an absent item is missing" table_row "afx_dereverb:$v-lib" "missing \(will download\)"
check "only the seven to do are printed" test "$(wc -l <<<"$out")" = 7
check "the dry run left the destination alone" test "$before" = "$(cd "$dest" && find . -printf '%p %s\n' | sort)"

echo "== no model package, unavailable"
fresh avail
run --dry-run --dest "$dest" --archs sm_120 --features dereverb-16k,bogus-48k
check "a missing model package is reported" table_row "afx_dereverb:$v-16k-sm120" "no model package for 16k-sm120"
check "an unknown feature is unavailable" table_row "afx_bogus:$v-lib" "unavailable \(unknown name or no access\)"
check "it warns about it" says "feature bogus is unavailable"
check "the unavailable feature's models are not probed" not called "afx_bogus:$v-48k"
check "an unavailable feature fails the run (1)" test "$status" = 1
run --yes --dest "$dest" --archs sm_120 --features dereverb-16k,bogus-48k
check "the rest is still downloaded" complete "$dest/afx_dereverb_v$v-lib" 1 9
check "the next step names the present feature only" says "--features dereverb --write"

echo "== NGC CLI setup"
fresh setup
run_with "$stubs" FAKE_NGC_MODE=unconfigured -- --dry-run --dest "$dest" --archs sm_120
check "an unconfigured CLI: the core probe fails (1)" fails_with 1 "the NGC CLI cannot see the SDK core"
check "it gives ngc's message" says "ngc said: Error: Target '$mx/maxine_linux_audio_effects_sdk:$v' could not be found."
check "it names ngc config set" says "run \`ngc config set\` yourself"
check "it stops after the core" test "$(wc -l <"$calls")" = 1
fresh setup
run_with "$stubs_nongc" -- --dry-run --dest "$dest" --archs sm_120
check "ngc not on PATH: it stops" fails_with 1 "the NGC CLI ('ngc') is not on PATH"
run_with "$stubs_nongc" -- --list --dry-run --archs sm_120
check "--list --dry-run needs no ngc" passes

echo "== confirmation and download"
fresh confirm
run --dest "$dest" --archs sm_120
check "without a terminal --yes is required" fails_with 1 "pass --yes"
check "nothing was downloaded" no_downloads
fresh dl
run --yes --dest "$dest" --archs sm_120
check "a download succeeds" passes
check "it downloads into the staging directory" called "download-version $mx/afx_denoiser:$v-lib --dest $dest/.partial"
check "nine downloads" test "$(ncalls download-version)" = 9
check "the core is complete" complete "$dest/maxine_linux_audio_effects_sdk_v$v" 3 300
check "the studio voice models are complete" complete "$dest/afx_studio_voice_v$v-48k-sm120" 6 90
present_all=1
for d in "${broadcast_dirs[@]}"; do [[ -d $dest/$d ]] || present_all=0; done
check "all nine directories are in the destination, named as assemble.sh expects" test "$present_all" = 1
check ".partial is removed" test ! -e "$dest/.partial"
cfg_line="$mafx/configure.sh --src $dest --archs \"sm_120\" --features $broadcast_features --write"
check "next step: configure.sh with the feature names" grep -qxF "  $cfg_line" <<<"$out"
check "next step: pacman -U is printed" grep -qxF "  sudo pacman -U $mafx/maxine-afx-sdk-local-*.pkg.tar*" <<<"$out"
check "nothing ran sudo, pacman, makepkg or configure.sh" not grep -qE '^(sudo|pacman|makepkg|configure.sh)' "$calls"
: >"$calls"
run --dest "$dest" --archs sm_120
check "run again: nothing to do needs no confirmation" passes
check "it says everything is present" says "everything is present in $dest"
check "it downloads nothing" no_downloads

echo "== retries and verification"
fresh retry
echo "$mx/afx_denoiser:$v-lib partial 1" >"$faults"
run --yes --dest "$dest" --archs sm_120
check "a retry after one failure succeeds" passes
check "it took two attempts" test "$(ncalls "afx_denoiser:$v-lib --dest")" = 2
check "the second attempt found the staging copy in place" called "afx_denoiser:$v-lib --dest $dest/.partial [existing]"
fresh retry
echo "$mx/afx_denoiser:$v-48k-sm120 wrong 1" >"$faults"
run --yes --dest "$dest" --archs sm_120
check "a wrong byte count is retried" passes
check "it said why" says "got 4 file(s), 81 bytes; NGC reported 4, 80"
fresh retry
echo "$mx/afx_dereverb:$v-lib partial 99" >"$faults"
run --yes --dest "$dest" --archs sm_120 --retries 1
check "retries exhausted: the run fails (1)" test "$status" = 1
check "retries exhausted: 1 + --retries attempts" test "$(ncalls "afx_dereverb:$v-lib --dest")" = 2
check "nothing of it reaches the destination" test ! -e "$dest/afx_dereverb_v$v-lib"
check "the other items continue" complete "$dest/afx_studio_voice_v$v-48k-sm120" 6 90
check "the next steps leave the failed feature out" says "--features denoiser,dereverb_denoiser,studio_voice --write"

echo "== failed probes"
fresh probe
echo "$mx/afx_denoiser:$v-48k-sm120 Client Error: 503 Response: Service Unavailable - Request Id: fake-1" >"$info_faults"
run --dry-run --dest "$dest" --archs sm_120
check "a 503 on a models probe fails the run (1)" test "$status" = 1
check "it is shown as a failed probe" table_row "afx_denoiser:$v-48k-sm120" "probe failed: Client Error: 503"
check "the next steps leave denoiser out" says "--features dereverb,dereverb_denoiser,studio_voice --write"
run --yes --build --dest "$dest" --archs sm_120
check "--build does not run after a failed probe" not grep -qE '^(configure.sh|makepkg)' "$calls"
check "--build says why" says "--build skipped"

echo "== the destination"
fresh partial-link
mkdir -p "$dest" "$tmp/partial-target"
ln -s "$tmp/partial-target" "$dest/.partial"
run --yes --dest "$dest" --archs sm_120
check "a DEST/.partial that is a link is refused (1)" fails_with 1 "$dest/.partial is a symbolic link"
check "it probes and downloads nothing" not called "ngc "
fresh "with space"
run --yes --build --dest "$dest" --archs sm_120
check "a DEST with a space: the run succeeds" passes
check "the next step quotes the path" says "--src $(printf %q "$dest") --archs"
check "--build runs configure.sh --write with the path as one word" \
    grep -qxF "configure.sh --src $dest --archs sm_120 --features $broadcast_features --write" "$calls"
check "--build runs makepkg -f in this maxine-afx/" grep -qxF "makepkg -f in $mafx" "$calls"
check "--build never runs sudo or pacman" not grep -qE '^(sudo|pacman)' "$calls"

echo "== --list"
fresh list
run_with "$stubs" FAKE_NGC_CATALOGUE="$real_catalogue" -- --list --archs sm_120
check "--list succeeds" passes
check "it lists library and model sizes" grep -qE '^denoiser-48k +1\.6 MiB +177\.2 MiB *$' <<<"$out"
check "an effect without models says none" grep -qE '^denoiser-16k +1\.6 MiB +none *$' <<<"$out"
check "a feature NGC denies is not available" grep -qE '^superres-8k_to_16k +not available *$' <<<"$out"
check "the library of a feature is probed once" test "$(ncalls "afx_denoiser:$v-lib --format")" = 1
check "it lists the Early Access effects" grep -qE '^speaker_focus-48k ' <<<"$out"
check "it gives the Broadcast names" says "-> Room Echo Removal"
check "it never downloads" no_downloads
fresh list
run --list --dry-run --archs sm_120,sm_89
check "--list --dry-run prints the info commands" \
    grep -qxF "ngc registry model info $mx/afx_studio_voice:$v-16k-sm89 --format_type json" <<<"$out"
check "--list --dry-run: 1 + 6 libraries + 12 effects x 2" test "$(wc -l <<<"$out")" = 31
check "--list --dry-run runs no ngc" not called "ngc "

echo "== ~/.ngc"
fresh ngcdir
mkdir -p "$home/.ngc"
printf '[CURRENT]\napikey = SENTINEL-KEY-0f3a9\n' >"$home/.ngc/config"
chmod 000 "$home/.ngc/config"
run --yes --dest "$dest" --archs sm_120
check "a download with an unreadable ~/.ngc/config succeeds" passes
check "no output names the key" not says SENTINEL-KEY-0f3a9
check "no output says Permission denied" not says "Permission denied"
chmod 600 "$home/.ngc/config"
code=$(grep -vE '^[[:space:]]*#' "$recipe/download.sh")
check "the script's code never names ~/.ngc or an API key" \
    not grep -qiE '\.ngc|api_?key|NGC_CLI_API' <<<"$code"
check "the script's code never runs NVIDIA's download script" \
    not grep -qE '(^|[[:space:]/])(\./)?download_features\.sh[[:space:]]*($|[;&|])' <<<"$code"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
