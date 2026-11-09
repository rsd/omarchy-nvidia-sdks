#!/usr/bin/env bash
# Tests for maxine-vfx/download.sh against a FAKE ngc. Everything happens
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
# Usage: maxine-vfx/tests/download-test.sh. Exits non-zero on any failure.
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
mvfx=$tmp/maxine-vfx
mkdir -p "$mvfx"
cp "$recipe/download.sh" "$mvfx/"
dl=$mvfx/download.sh
calls=$tmp/calls
: >"$calls"
cat >"$mvfx/configure.sh" <<EOF
#!/usr/bin/env bash
echo "configure.sh \$*" >>$(printf %q "$calls")
EOF
chmod +x "$mvfx/configure.sh"

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

# The catalogues: tiny sizes for downloads, NGC's real sizes for the table.
v=1.3.0.0
mx=nvidia/maxine
catalogue=$tmp/catalogue
cat >"$catalogue" <<EOF
resource $mx/vfx_sdk_core:${v}_linux 300 3
model $mx/nvvfxgreenscreen:${v}_lib_linux 10 1
model $mx/nvvfxgreenscreen:${v}_models_linux_sm120 80 8
model $mx/nvvfxgreenscreen:${v}_models_linux_sm89 70 8
model $mx/nvvfxgreenscreen:${v}_models_linux_sm86 60 8
model $mx/nvvfxgreenscreen:${v}_models_linux_sm75 50 8
model $mx/nvvfxbackgroundblur:${v}_lib_linux 5 1
model $mx/nvvfxdenoising:${v}_lib_linux 7 1
model $mx/nvvfxdenoising:${v}_models_linux_sm120 20 2
model $mx/nvvfxdenoising:${v}_models_linux_sm86 18 2
model $mx/nvvfxrelighting:${v}_lib_linux 9 1
model $mx/nvvfxrelighting:${v}_models_linux_sm120 30 2
model $mx/nvvfxvideosuperres:${v}_lib_linux 40 1
model $mx/nvvfxupscale:${v}_lib_linux 6 1
model $mx/nvvfxtruehdr:${v}_lib_linux 8 1
model $mx/nvvfxvideoframegeneration:${v}_lib_linux 50 1
EOF
real_catalogue=$tmp/real-catalogue
cat >"$real_catalogue" <<EOF
resource $mx/vfx_sdk_core:${v}_linux 2821858131 3
model $mx/nvvfxgreenscreen:${v}_lib_linux 2692828 1
model $mx/nvvfxgreenscreen:${v}_models_linux_sm120 118636240 8
model $mx/nvvfxbackgroundblur:${v}_lib_linux 391520 1
model $mx/nvvfxdenoising:${v}_lib_linux 2300900 1
model $mx/nvvfxdenoising:${v}_models_linux_sm120 3901624 2
model $mx/nvvfxrelighting:${v}_lib_linux 2565338 1
model $mx/nvvfxrelighting:${v}_models_linux_sm120 83319624 2
model $mx/nvvfxvideosuperres:${v}_lib_linux 49110043 1
model $mx/nvvfxupscale:${v}_lib_linux 1604252 1
model $mx/nvvfxtruehdr:${v}_lib_linux 2332065 1
model $mx/nvvfxvideoframegeneration:${v}_lib_linux 187991091 1
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
    rm -rf -- "$dest"
    : >"$calls"
    rm -f "$faults" "$info_faults" "$state"/*
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

broadcast_dirs=("vfx_sdk_core_v${v}_linux" "nvvfxgreenscreen_v${v}_lib_linux"
    "nvvfxgreenscreen_v${v}_models_linux_sm120" "nvvfxbackgroundblur_v${v}_lib_linux"
    "nvvfxdenoising_v${v}_lib_linux" "nvvfxdenoising_v${v}_models_linux_sm120")

echo "== options"
fresh opts
run --bogus
check "an unknown option is a usage error (2)" fails_with 2 "unknown argument: --bogus"
run --preset all --features nvvfxgreenscreen
check "--preset with --features is a usage error" fails_with 2 "give --preset or --features, not both"
run --preset bogus
check "an unknown preset is a usage error" fails_with 2 "unknown preset 'bogus'"
run --archs "all sm_120"
check "'all' with another architecture is a usage error" fails_with 2 "must be the only --archs entry"
run --archs 8.9
check "an architecture with a dot is a usage error" fails_with 2 "invalid architecture '8.9'"
run --retries x
check "a non-numeric --retries is a usage error" fails_with 2 "invalid --retries 'x'"
run --version 1.3
check "a short version is a usage error" fails_with 2 "invalid version '1.3'"
run --list --yes
check "--list with a download option is a usage error" fails_with 2 "--list takes only"
# shellcheck disable=SC2016 # a literal $(id), never run
run --features 'nvvfx$(id)'
check "an invalid feature name is a usage error" fails_with 2 "invalid feature name"
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
check "auto: the sm_120 models are probed" called "info $mx/nvvfxgreenscreen:${v}_models_linux_sm120 --format_type json"
fresh arch
run_with "$stubs" FAKE_SMI_OUT='12.0\n8.9\n12.0' -- --dry-run --dest "$dest"
check "several GPUs: the unique architectures in GPU order" says "GPU architecture (from nvidia-smi): sm_120 sm_89"
check "several GPUs: each architecture is probed once" \
    test "$(ncalls "nvvfxgreenscreen:${v}_models_linux_sm120 --format")" = 1
check "several GPUs: the next step names both" says "--archs \"sm_120 sm_89\""
fresh arch
run_with "$stubs" FAKE_SMI_OUT=' 8.6' -- --dry-run --dest "$dest"
check "8.6 is sm_86" says "GPU architecture (from nvidia-smi): sm_86"
check "sm_86 models are probed" called "nvvfxdenoising:${v}_models_linux_sm86 --format_type json"
fresh arch
run_with "$stubs" FAKE_SMI_OUT=10.0 -- --dry-run --dest "$dest"
check "10.0 is sm_100" says "GPU architecture (from nvidia-smi): sm_100"
fresh arch
run_with "$stubs" FAKE_SMI_OUT=6.1 -- --dry-run --dest "$dest"
check "a GPU below 7.5 is refused" fails_with 1 "sm_61 is not supported: the SDK needs Turing (sm_75) or newer"
check "it probes nothing" not called "ngc "
fresh arch
run_with "$stubs_nosmi" -- --dry-run --dest "$dest"
check "no nvidia-smi: it stops" fails_with 1 "nvidia-smi not found"
check "no nvidia-smi: it says to pass --archs" says "pass --archs sm_120"
fresh arch
run_with "$stubs" FAKE_SMI_RC=9 FAKE_SMI_OUT='NVIDIA-SMI has failed' -- --dry-run --dest "$dest"
check "a failing nvidia-smi: it stops and says to pass --archs" fails_with 1 "nvidia-smi failed (NVIDIA-SMI has failed): pass --archs sm_120"
fresh arch
run_with "$stubs" FAKE_SMI_OUT='[N/A]' -- --dry-run --dest "$dest"
check "an unparseable answer: it stops and says to pass --archs" fails_with 1 "'[N/A]', which is not understood: pass --archs sm_120"
fresh arch
run_with "$stubs" FAKE_SMI_OUT='' -- --dry-run --dest "$dest"
check "no GPU listed: it stops and says to pass --archs" fails_with 1 "nvidia-smi reported no GPU: pass --archs"
fresh arch
run --dry-run --dest "$dest" --archs "sm120,120 89"
check "--archs: a dry run succeeds" passes
check "--archs skips nvidia-smi entirely" not called nvidia-smi
check "--archs: sm120, 120 and 89 normalise and deduplicate" \
    test "$(ncalls "nvvfxgreenscreen:${v}_models_linux_sm120 --format")" = 1
check "--archs: sm_89 is probed" called "nvvfxgreenscreen:${v}_models_linux_sm89 --format_type json"
fresh arch
run --dry-run --dest "$dest" --archs all
check "--archs all probes sm_75 to sm_120" \
    test "$(grep -c "nvvfxgreenscreen:${v}_models_linux_sm" "$calls")" = 7
fresh arch
run --dry-run --dest "$dest" --archs sm_87
check "an architecture outside the model list is a warning" passes
check "it says so" says "sm_87 is not an architecture with ${v} Linux model packages"
check "its models show as no model package" table_row "nvvfxgreenscreen:${v}_models_linux_sm87" "no model package for sm_87"
run --dry-run --dest "$dest" --archs sm_61
check "--archs below 75 is refused" fails_with 1 "sm_61 is not supported"

echo "== presets and --features"
fresh preset
run --dry-run --dest "$dest" --archs sm_120
check "default preset: green screen, background blur, denoising" \
    test "$(grep -c '_lib_linux --format' "$calls")" = 3
check "default preset: relighting is not probed" not called nvvfxrelighting
check "the core is probed as a resource" called "ngc registry resource info $mx/vfx_sdk_core:${v}_linux --format_type json"
fresh preset
run --dry-run --dest "$dest" --archs sm_120 --preset all
check "--preset all probes the eight libraries" test "$(grep -c '_lib_linux --format' "$calls")" = 8
check "--preset all: video frame generation is one of them" called "nvvfxvideoframegeneration:${v}_lib_linux"
check "--preset all does not probe artifact reduction" not called nvvfxartifactreduction
fresh preset
run --dry-run --dest "$dest" --archs sm_120 --features nvvfxrelighting,nvvfxrelighting
check "--features replaces the preset" not called nvvfxgreenscreen
check "--features: each name once" test "$(ncalls "nvvfxrelighting:${v}_lib_linux --format")" = 1
check "--features: the core is still fetched" called "vfx_sdk_core:${v}_linux"

echo "== dry run"
fresh dry
run --dry-run --dest "$dest" --archs sm_120
check "a dry run succeeds" passes
check "it probes" called "info $mx/nvvfxgreenscreen:${v}_lib_linux"
check "it downloads nothing" no_downloads
check "it creates no destination" test ! -e "$dest"
check "stdout holds the six download commands" test "$(wc -l <<<"$out")" = 6
check "stdout holds only download commands into the staging directory" \
    not grep -qvE "^ngc registry (model|resource) download-version $mx/[a-z_]+:${v}_[a-z0-9_]+ --dest $dest/\.partial\$" <<<"$out"
check "the core is a resource download" grep -qxF "ngc registry resource download-version $mx/vfx_sdk_core:${v}_linux --dest $dest/.partial" <<<"$out"
check "the table is on stderr" says_err "^item +size +files +status"
check "the next steps are on stderr" says_err "Next steps, once the download is complete"
check "it says nothing was downloaded" says "nothing was downloaded or created"
fresh dry
run_with "$stubs" FAKE_NGC_CATALOGUE="$real_catalogue" -- --dry-run --dest "$dest" --archs sm_120
check "sizes: the core in GiB" table_row "vfx_sdk_core:${v}_linux +2.63 GiB +3" "missing"
check "sizes: the green screen models in MiB" table_row "nvvfxgreenscreen:${v}_models_linux_sm120 +113.1 MiB +8" "missing"
check "sizes: the broadcast total for sm_120" says "To download: 6 item(s), 2.75 GiB (2949781243 bytes)"
run_with "$stubs" FAKE_NGC_CATALOGUE="$real_catalogue" -- --dry-run --dest "$dest" --archs sm_120 --preset all
check "sizes: the all total for sm_120" says "To download: 12 item(s), 3.05 GiB (3276703656 bytes)"
fresh dry
mkdir -p "$home/Downloads"
run --dry-run --archs sm_120
check "the default destination is ~/Downloads/maxine" \
    grep -qxF "ngc registry resource download-version $mx/vfx_sdk_core:${v}_linux --dest $home/Downloads/maxine/.partial" <<<"$out"
check "it is not created" test ! -e "$home/Downloads/maxine"
run --dry-run --archs sm_120 --build
check "--build --dry-run calls neither configure.sh nor makepkg" not grep -qE '^(configure.sh|makepkg)' "$calls"

echo "== status of each item"
fresh status
item "vfx_sdk_core:${v}_linux" "$dest"
item "nvvfxgreenscreen:${v}_lib_linux" "$dest"
item "nvvfxgreenscreen:${v}_models_linux_sm120" "$dest"
truncate -s 2 "$dest/nvvfxgreenscreen_v${v}_models_linux_sm120/file1.bin" # 81 bytes, not 80
item "nvvfxdenoising:${v}_lib_linux" "$dest"
item "nvvfxdenoising:${v}_models_linux_sm120" "$dest"
rm "$dest/nvvfxdenoising_v${v}_models_linux_sm120/file1.bin"
truncate -s 20 "$dest/nvvfxdenoising_v${v}_models_linux_sm120/file2.bin" # 20 bytes, 1 file, not 2
before=$(cd "$dest" && find . -printf '%p %s\n' | sort)
run --dry-run --dest "$dest" --archs sm_120
check "the core is present" table_row "vfx_sdk_core:${v}_linux" "present$"
check "a complete library is present" table_row "nvvfxgreenscreen:${v}_lib_linux" "present$"
check "a byte mismatch is incomplete" table_row "nvvfxgreenscreen:${v}_models_linux_sm120" "incomplete \(will download again\)"
check "a file-count mismatch is incomplete" table_row "nvvfxdenoising:${v}_models_linux_sm120" "incomplete"
check "an absent item is missing" table_row "nvvfxbackgroundblur:${v}_lib_linux" "missing \(will download\)"
check "only the three to do are printed" test "$(wc -l <<<"$out")" = 3
check "a present item is not downloaded again" not grep -q vfx_sdk_core <<<"$out"
check "the dry run left the destination alone" test "$before" = "$(cd "$dest" && find . -printf '%p %s\n' | sort)"

echo "== no model package, unavailable"
fresh avail
run --dry-run --dest "$dest" --archs sm_120 --features nvvfxbackgroundblur,nvvfxbogus
check "a missing model package is reported" table_row "nvvfxbackgroundblur:${v}_models_linux_sm120" "no model package for sm_120"
check "an unknown feature is unavailable" table_row "nvvfxbogus:${v}_lib_linux" "unavailable \(unknown name or no access\)"
check "it warns about it" says "feature nvvfxbogus is unavailable"
check "the unavailable feature's models are not probed" not called "nvvfxbogus:${v}_models"
check "an unavailable feature fails the run (1)" test "$status" = 1
check "no model package is not an error" not says "nvvfxbackgroundblur is unavailable"
run --yes --dest "$dest" --archs sm_120 --features nvvfxbackgroundblur,nvvfxbogus
check "the rest is still downloaded" complete "$dest/nvvfxbackgroundblur_v${v}_lib_linux" 1 5
check "and the run still fails (1)" test "$status" = 1
check "the next step names the present feature only" says "--features nvvfxbackgroundblur --write"

echo "== NGC CLI setup"
fresh setup
run_with "$stubs" FAKE_NGC_MODE=unconfigured -- --dry-run --dest "$dest" --archs sm_120
check "an unconfigured CLI: the core probe fails (1)" fails_with 1 "the NGC CLI cannot see the SDK core"
check "it gives ngc's message" says "ngc said: Error: Target '$mx/vfx_sdk_core:${v}_linux' could not be found."
check "it names ngc config set" says "run \`ngc config set\` yourself"
check "it names the other causes" says "the API key is invalid or expired"
check "it points to the troubleshooting section" says "docs/download.md#troubleshooting"
check "it stops after the core" test "$(wc -l <"$calls")" = 1
fresh setup
grep -v vfx_sdk_core "$catalogue" >"$tmp/no-core"
run_with "$stubs" FAKE_NGC_CATALOGUE="$tmp/no-core" -- --dry-run --dest "$dest" --archs sm_120
check "no access to the core: the same message" fails_with 1 "ngc said: Client Error: 403 Response: Access Denied"
fresh setup
run_with "$stubs_nongc" -- --dry-run --dest "$dest" --archs sm_120
check "ngc not on PATH: it stops" fails_with 1 "the NGC CLI ('ngc') is not on PATH"
check "it names the install section" says "docs/download.md#3-install-the-ngc-cli"
run_with "$stubs_nongc" -- --list --dry-run --archs sm_120
check "--list --dry-run needs no ngc" passes

echo "== confirmation"
fresh confirm
run --dest "$dest" --archs sm_120
check "without a terminal --yes is required" fails_with 1 "pass --yes"
check "nothing was downloaded" no_downloads
check "the destination was not created" test ! -e "$dest"

echo "== download"
fresh dl
run --yes --dest "$dest" --archs sm_120
check "a download succeeds" passes
check "it downloads into the staging directory" called "download-version $mx/nvvfxgreenscreen:${v}_lib_linux --dest $dest/.partial"
check "it downloads the core as a resource" called "ngc registry resource download-version $mx/vfx_sdk_core:${v}_linux --dest $dest/.partial"
check "six downloads" test "$(ncalls download-version)" = 6
check "the core is complete" complete "$dest/vfx_sdk_core_v${v}_linux" 3 300
check "the green screen models are complete" complete "$dest/nvvfxgreenscreen_v${v}_models_linux_sm120" 8 80
present_all=1
for d in "${broadcast_dirs[@]}"; do [[ -d $dest/$d ]] || present_all=0; done
check "all six directories are in the destination" test "$present_all" = 1
check ".partial is removed" test ! -e "$dest/.partial"
check "stdout carries no ngc output" not grep -q "Download completed" <<<"$out"
cfg_line="$mvfx/configure.sh --src $dest --archs \"sm_120\" --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising --write"
check "next step: configure.sh with absolute paths" grep -qxF "  $cfg_line" <<<"$out"
check "next step: makepkg in this maxine-vfx/" grep -qxF "  cd $mvfx && makepkg -f" <<<"$out"
check "next step: pacman -U is printed, for any PKGEXT" grep -qxF "  sudo pacman -U $mvfx/maxine-vfx-sdk-local-*.pkg.tar*" <<<"$out"
check "a complete run: the plain next-steps heading" grep -qxF "Next steps:" <<<"$out"
check "nothing ran sudo, pacman, makepkg or configure.sh" not grep -qE '^(sudo|pacman|makepkg|configure.sh)' "$calls"
: >"$calls"
run --dest "$dest" --archs sm_120
check "run again without --yes: nothing to do needs no confirmation" passes
check "it says everything is present" says "everything is present in $dest"
check "it downloads nothing" no_downloads

echo "== retries and verification"
fresh retry
echo "$mx/nvvfxgreenscreen:${v}_lib_linux partial 1" >"$faults"
run --yes --dest "$dest" --archs sm_120
check "a retry after one failure succeeds" passes
check "it took two attempts" test "$(ncalls "nvvfxgreenscreen:${v}_lib_linux --dest")" = 2
check "the second attempt found the staging copy in place" called "nvvfxgreenscreen:${v}_lib_linux --dest $dest/.partial [existing]"
check "the item is complete" complete "$dest/nvvfxgreenscreen_v${v}_lib_linux" 1 10
check "it said it tried again" says "trying again"

fresh retry
echo "$mx/nvvfxgreenscreen:${v}_models_linux_sm120 wrong 1" >"$faults"
run --yes --dest "$dest" --archs sm_120
check "a wrong byte count is retried" passes
check "it said why" says "got 8 file(s), 81 bytes; NGC reported 8, 80"
check "the item is complete" complete "$dest/nvvfxgreenscreen_v${v}_models_linux_sm120" 8 80

fresh retry
echo "$mx/nvvfxbackgroundblur:${v}_lib_linux partial 99" >"$faults"
run --yes --dest "$dest" --archs sm_120 --retries 1
check "retries exhausted: the run fails (1)" test "$status" = 1
check "retries exhausted: 1 + --retries attempts" test "$(ncalls "nvvfxbackgroundblur:${v}_lib_linux --dest")" = 2
check "the partial copy is removed" test ! -e "$dest/.partial"
check "nothing of it reaches the destination" test ! -e "$dest/nvvfxbackgroundblur_v${v}_lib_linux"
check "the other items continue" complete "$dest/nvvfxdenoising_v${v}_models_linux_sm120" 2 20
check "the failure is reported" says "$mx/nvvfxbackgroundblur:${v}_lib_linux: ngc exited with status 1"
check "the next steps leave the failed feature out" says "--features nvvfxgreenscreen,nvvfxdenoising --write"
fresh retry
echo "$mx/nvvfxbackgroundblur:${v}_lib_linux fail 99" >"$faults"
run --yes --dest "$dest" --archs sm_120
check "the default is 2 retries (3 attempts)" test "$(ncalls "nvvfxbackgroundblur:${v}_lib_linux --dest")" = 3
run --yes --dest "$dest" --archs sm_120 --retries 0
check "--retries 0: one attempt" test "$(ncalls "nvvfxbackgroundblur:${v}_lib_linux --dest")" = 4

fresh replace
mkdir -p "$dest/nvvfxgreenscreen_v${v}_lib_linux"
echo old >"$dest/nvvfxgreenscreen_v${v}_lib_linux/old.bin"
echo "$mx/nvvfxgreenscreen:${v}_lib_linux wrong 99" >"$faults"
run --yes --dest "$dest" --archs sm_120 --retries 0
check "an incomplete item that fails to verify: the run fails" test "$status" = 1
check "the old incomplete copy is kept" test -f "$dest/nvvfxgreenscreen_v${v}_lib_linux/old.bin"
rm -f "$faults"
run --yes --dest "$dest" --archs sm_120
check "verified: the run succeeds" passes
check "the old copy was replaced" not test -e "$dest/nvvfxgreenscreen_v${v}_lib_linux/old.bin"
check "by the verified one" complete "$dest/nvvfxgreenscreen_v${v}_lib_linux" 1 10

fresh stray
mkdir -p "$dest/.partial/stray"
echo x >"$dest/.partial/stray/x"
run --yes --dest "$dest" --archs sm_120
check "a stray file in .partial does not fail the run" passes
check "it is kept and reported" says "$dest/.partial is not empty"
check "the stray file is untouched" test -f "$dest/.partial/stray/x"

echo "== failed probes"
fresh probe
echo "$mx/nvvfxgreenscreen:${v}_models_linux_sm120 Client Error: 503 Response: Service Unavailable - Request Id: fake-1" >"$info_faults"
run --dry-run --dest "$dest" --archs sm_120
check "a 503 on a models probe fails the run (1)" test "$status" = 1
check "it is shown as a failed probe" table_row "nvvfxgreenscreen:${v}_models_linux_sm120" "probe failed: Client Error: 503"
check "it is not shown as no model package" not table_row "nvvfxgreenscreen:${v}_models_linux_sm120" "no model package"
check "it is not among the download commands" not grep -q "nvvfxgreenscreen:${v}_models" <<<"$out"
check "it warns with ngc's message" says "probing $mx/nvvfxgreenscreen:${v}_models_linux_sm120 failed (Client Error: 503 Response: Service Unavailable"
check "the next steps come after the failures" says "Next steps, once the failures above are fixed"
check "the next steps leave green screen out" says "--features nvvfxbackgroundblur,nvvfxdenoising --write"
run --yes --build --dest "$dest" --archs sm_120
check "a real run with a 503: it fails (1)" test "$status" = 1
check "the other items are downloaded" complete "$dest/nvvfxdenoising_v${v}_models_linux_sm120" 2 20
check "the item whose probe failed is not downloaded" not called "download-version $mx/nvvfxgreenscreen:${v}_models"
check "--build does not run after a failed probe" not grep -qE '^(configure.sh|makepkg)' "$calls"
check "--build says why" says "--build skipped"
check "the failed probe is in the failure list" says "$mx/nvvfxgreenscreen:${v}_models_linux_sm120: probe failed: Client Error: 503"
fresh probe
echo "$mx/nvvfxbackgroundblur:${v}_lib_linux Error: Request timed out after 30 seconds" >"$info_faults"
run --dry-run --dest "$dest" --archs sm_120
check "a timeout on a library probe fails the run (1)" test "$status" = 1
check "it is a failed probe" table_row "nvvfxbackgroundblur:${v}_lib_linux" "probe failed: Error: Request timed out"
check "it is not unavailable" not says "feature nvvfxbackgroundblur is unavailable"
check "its models are not probed" not called "nvvfxbackgroundblur:${v}_models"
fresh probe
echo "$mx/nvvfxgreenscreen:${v}_models_linux_sm120 {\"error\": \"Error: Target '$mx/nvvfxgreenscreen:${v}_models_linux_sm120' could not be found.\"}" >"$info_faults"
run --dry-run --dest "$dest" --archs sm_120
check "could not be found on a models probe: no model package" table_row "nvvfxgreenscreen:${v}_models_linux_sm120" "no model package for sm_120"
check "and the run succeeds" passes
fresh probe
run_with "$stubs" FAKE_NGC_MODE=unconfigured FAKE_NGC_BANNER=1 -- --dry-run --dest "$dest" --archs sm_120
check "a banner first: ngc said gives the error line" says "ngc said: Error: Target '$mx/vfx_sdk_core:${v}_linux' could not be found."
check "a banner first: not the banner" not says "ngc said: A newer version"
fresh probe
run_with "$stubs" FAKE_NGC_BANNER=1 -- --dry-run --dest "$dest" --archs sm_120
check "a banner on a successful probe changes nothing" passes

echo "== next steps after a failure"
fresh steps
echo "$mx/nvvfxdenoising:${v}_models_linux_sm120 fail 99" >"$faults"
run --yes --build --dest "$dest" --archs sm_120 --retries 0
check "a failed models download: the run fails (1)" test "$status" = 1
check "the feature's library is present" complete "$dest/nvvfxdenoising_v${v}_lib_linux" 1 7
check "the next steps leave out the feature whose models failed" \
    grep -qxF "  $mvfx/configure.sh --src $dest --archs \"sm_120\" --features nvvfxgreenscreen,nvvfxbackgroundblur --write" <<<"$out"
check "under the heading for after the failures" \
    grep -qxF "Next steps, once the failures above are fixed (the --features below leave out every feature with a failure):" <<<"$out"
check "--build does not run" not grep -qE '^(configure.sh|makepkg)' "$calls"

echo "== the destination"
fresh others
mkdir -p "$dest/extract/sub"
echo keep >"$dest/extract/sub/file"
echo log >"$dest/download.log"
others() { (cd "$dest" && find extract download.log -printf '%p %y %s %T@\n' | sort); }
others_before=$(others)
run --yes --dest "$dest" --archs sm_120
check "with unrelated entries in DEST: the run succeeds" passes
check "the unrelated entries are untouched" test "$others_before" = "$(others)"
fresh link
mkdir -p "$dest" "$tmp/elsewhere/gs-lib"
echo old >"$tmp/elsewhere/gs-lib/old.bin"
ln -s "$tmp/elsewhere/gs-lib" "$dest/nvvfxgreenscreen_v${v}_lib_linux"
ln -s "$tmp/nowhere" "$dest/nvvfxbackgroundblur_v${v}_lib_linux"
run --dry-run --dest "$dest" --archs sm_120
check "a link to an incomplete copy is incomplete" table_row "nvvfxgreenscreen:${v}_lib_linux" "incomplete"
check "a dangling link is incomplete" table_row "nvvfxbackgroundblur:${v}_lib_linux" "incomplete"
run --yes --dest "$dest" --archs sm_120
check "with links in DEST: the run succeeds" passes
check "the link is replaced by a real directory" not test -L "$dest/nvvfxgreenscreen_v${v}_lib_linux"
check "which is the verified download" complete "$dest/nvvfxgreenscreen_v${v}_lib_linux" 1 10
check "the dangling link is replaced too" complete "$dest/nvvfxbackgroundblur_v${v}_lib_linux" 1 5
check "the link's target is untouched" test "$(cd "$tmp/elsewhere/gs-lib" && find . -mindepth 1 -printf '%P %s\n')" = "old.bin 4"
fresh link
mkdir -p "$dest"
item "nvvfxgreenscreen:${v}_lib_linux" "$tmp/elsewhere2"
ln -s "$tmp/elsewhere2/nvvfxgreenscreen_v${v}_lib_linux" "$dest/nvvfxgreenscreen_v${v}_lib_linux"
run --yes --dest "$dest" --archs sm_120
check "a link to a complete copy is present" table_row "nvvfxgreenscreen:${v}_lib_linux" "present$"
check "it is not downloaded" not called "download-version $mx/nvvfxgreenscreen:${v}_lib_linux"
check "the link is kept" test -L "$dest/nvvfxgreenscreen_v${v}_lib_linux"
check "its target is untouched" complete "$tmp/elsewhere2/nvvfxgreenscreen_v${v}_lib_linux" 1 10
fresh "with space"
run --yes --build --dest "$dest" --archs sm_120
check "a DEST with a space: the run succeeds" passes
check "it downloads into DEST/.partial" called "download-version $mx/vfx_sdk_core:${v}_linux --dest $dest/.partial"
check "the items are complete" complete "$dest/nvvfxdenoising_v${v}_models_linux_sm120" 2 20
check ".partial is removed" test ! -e "$dest/.partial"
check "the next step quotes the path" says "--src $(printf %q "$dest") --archs"
check "--build passes the path as one word" grep -qxF "configure.sh --src $dest --archs sm_120 --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising --write" "$calls"
fresh partial-link
mkdir -p "$dest" "$tmp/partial-target"
ln -s "$tmp/partial-target" "$dest/.partial"
run --yes --dest "$dest" --archs sm_120
check "a DEST/.partial that is a link is refused (1)" fails_with 1 "$dest/.partial is a symbolic link"
check "it probes and downloads nothing" not called "ngc "
check "the link is kept" test -L "$dest/.partial"
check "its target is untouched" test -z "$(find "$tmp/partial-target" -mindepth 1 -print -quit)"
fresh partial-file
mkdir -p "$dest"
echo x >"$dest/.partial"
run --yes --dest "$dest" --archs sm_120
check "a DEST/.partial that is a file is refused (1)" fails_with 1 "$dest/.partial exists and is not a directory"
check "the file is kept" test -f "$dest/.partial"

echo "== --build"
fresh build
run --yes --build --dest "$dest" --archs sm_120
check "--build succeeds" passes
check "--build runs configure.sh --write" \
    grep -qxF "configure.sh --src $dest --archs sm_120 --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising --write" "$calls"
check "--build runs makepkg -f in this maxine-vfx/" grep -qxF "makepkg -f in $mvfx" "$calls"
check "configure.sh comes first" test "$(grep -nE '^(configure.sh|makepkg)' "$calls" | cut -d: -f1 | head -n 1)" = \
    "$(grep -n '^configure.sh' "$calls" | cut -d: -f1)"
check "--build never runs sudo or pacman" not grep -qE '^(sudo|pacman)' "$calls"
check "--build never installs: its one makepkg call is exactly -f" test "$(grep '^makepkg ' "$calls")" = "makepkg -f in $mvfx"
fresh build
echo "$mx/nvvfxbackgroundblur:${v}_lib_linux fail 99" >"$faults"
run --yes --build --dest "$dest" --archs sm_120 --retries 0
check "--build after a failure: the run fails" test "$status" = 1
check "--build after a failure builds nothing" not grep -qE '^(configure.sh|makepkg)' "$calls"
check "it says why" says "--build skipped"

echo "== --list"
fresh list
grep -v nvvfxtruehdr "$real_catalogue" >"$tmp/no-truehdr"
run_with "$stubs" FAKE_NGC_CATALOGUE="$tmp/no-truehdr" -- --list --archs sm_120
check "--list succeeds" passes
check "it explains NOT_LISTED" says "(Access Type: NOT_LISTED), so this probes the known names with \`ngc registry model info\`."
# shellcheck disable=SC2016 # literal backticks in the expected text
check "it names the hidden wildcard" says 'NGC hides the Maxine items from `ngc registry model list "nvidia/maxine/nvvfx*"`'
check "it gives the per-feature version list" says 'ngc registry model list "nvidia/maxine/<feature>:*"'
check "it lists library and model sizes" grep -qE '^nvvfxrelighting +2\.4 MiB +79\.5 MiB *$' <<<"$out"
check "a feature without models says none" grep -qE '^nvvfxbackgroundblur +0\.4 MiB +none *$' <<<"$out"
check "a feature NGC denies is not available" grep -qE '^nvvfxtruehdr +not available *$' <<<"$out"
check "it gives the Broadcast names" says "Background Removal, Background Replacement"
check "it says Eye Contact is the AR SDK" says "Eye Contact and Auto Frame (NVIDIA Broadcast) belong to the Maxine AR SDK"
check "it probes the eight libraries" test "$(grep -c '_lib_linux --format' "$calls")" = 8
check "it never downloads" no_downloads
check "it does not probe artifact reduction" not called nvvfxartifactreduction
fresh list
run --list --dry-run --archs sm_120,sm_89
check "--list --dry-run prints the info commands" grep -qxF "ngc registry model info $mx/nvvfxdenoising:${v}_models_linux_sm89 --format_type json" <<<"$out"
check "--list --dry-run: 1 + 8 x 3 commands" test "$(wc -l <<<"$out")" = 25
check "--list --dry-run runs no ngc" not called "ngc "
fresh list
echo "$mx/nvvfxrelighting:${v}_models_linux_sm120 Too many requests, slow down" >"$info_faults"
echo "$mx/nvvfxupscale:${v}_lib_linux Client Error: 429 Response: Too Many Requests" >>"$info_faults"
run_with "$stubs" FAKE_NGC_CATALOGUE="$real_catalogue" -- --list --archs sm_120
check "--list: a failed probe fails the run (1)" test "$status" = 1
check "--list: a failed models probe says probe failed" grep -qE '^nvvfxrelighting +2\.4 MiB +probe failed *$' <<<"$out"
check "--list: a failed library probe says probe failed" grep -qE '^nvvfxupscale +probe failed *$' <<<"$out"
check "--list: a 403 is still none" grep -qE '^nvvfxbackgroundblur +0\.4 MiB +none *$' <<<"$out"
check "--list: it gives ngc's error line" says "probe failed, so the table is incomplete: $mx/nvvfxupscale:${v}_lib_linux: Client Error: 429"
check "--list: without an error line, the first line" says "$mx/nvvfxrelighting:${v}_models_linux_sm120: Too many requests, slow down"

echo "== ~/.ngc"
# Runtime checks: with an unreadable ~/.ngc/config that holds a sentinel key,
# a download and --list still succeed, print no key and no "Permission
# denied", and leave ~/.ngc as it was. They cannot prove that the script never
# opens the file (a read with its error discarded would pass them); the
# static grep of the script's code at the end is the real guard.
fresh ngcdir
mkdir -p "$home/.ngc"
printf '[CURRENT]\napikey = SENTINEL-KEY-0f3a9\n' >"$home/.ngc/config"
cp "$home/.ngc/config" "$tmp/config.saved"
chmod 000 "$home/.ngc/config"
ngc_entries() { find "$home/.ngc" -printf '%M %s %P\n' | sort; }
ngc_listing=$(ngc_entries)
run --yes --dest "$dest" --archs sm_120
check "a download with an unreadable ~/.ngc/config succeeds" passes
check "no output names the key" not says SENTINEL-KEY-0f3a9
check "no output says Permission denied" not says "Permission denied"
run --list --archs sm_120
check "--list with an unreadable ~/.ngc/config succeeds" passes
check "no --list output names the key" not says SENTINEL-KEY-0f3a9
check "HOME/.ngc holds the same entries, modes and sizes" test "$ngc_listing" = "$(ngc_entries)"
chmod 600 "$home/.ngc/config"
check "HOME/.ngc/config is unchanged" cmp -s "$home/.ngc/config" "$tmp/config.saved"
code=$(grep -vE '^[[:space:]]*#' "$recipe/download.sh")
check "the script's code never names ~/.ngc or an API key" \
    not grep -qiE '\.ngc|api_?key|NGC_CLI_API' <<<"$code"

if ((fails > 0)); then
    echo "$fails of $count check(s) failed"
    exit 1
fi
echo "all $count checks passed"
