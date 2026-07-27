#!/usr/bin/env bash
# OpenHyprWhisper test suite.
#
# Three tiers, heaviest last:
#   unit         - pure text/audio processing, no daemons, no audio hardware
#   integration  - real pipeline on this machine (pipewire + whisper daemon)
#   ui           - the Quickshell overlay on a live Hyprland session
#
# Tests that need something the machine doesn't have are SKIPPED, not failed,
# so the suite is safe to run anywhere (including CI without audio).
#
# Usage: tests/run-tests.sh [unit|integration|ui|all]   (default: all)
set -u

OHW_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
OHW="$OHW_ROOT/bin/ohw"
TIER="${1:-all}"

PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); printf '\033[32mok\033[0m     %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '\033[31mFAIL\033[0m   %s%s\n' "$1" "${2:+ - $2}"; }
skip() { SKIP=$((SKIP+1)); printf '\033[33mskip\033[0m   %s (%s)\n' "$1" "$2"; }

# assert <name> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
assert_contains() {
    case "$3" in *"$2"*) pass "$1" ;; *) fail "$1" "[$3] does not contain [$2]" ;; esac
}

# Isolated environment: never touch the user's real config/history.
# XDG_RUNTIME_DIR itself must stay untouched - the wayland and pipewire
# sockets live there - so ohw gets its own OHW_RUNTIME_DIR test hook.
TESTTMP=$(mktemp -d)
export XDG_CONFIG_HOME="$TESTTMP/config"
export XDG_DATA_HOME="$TESTTMP/data"
export OHW_RUNTIME_DIR="$TESTTMP/runtime"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$OHW_RUNTIME_DIR"
export OHW_OVERLAY=false   # UI tier launches the overlay explicitly

SINK=""
cleanup() {
    "$OHW" cancel >/dev/null 2>&1
    [ -n "$SINK" ] && pactl unload-module "$SINK" >/dev/null 2>&1
    pkill -f "qs -p $OHW_ROOT/quickshell/overlay.qml" 2>/dev/null
    rm -rf "$TESTTMP"
}
trap cleanup EXIT

# The real model lives in the user's data dir; tests reuse it read-only.
REAL_MODELS="${XDG_DATA_HOME_REAL:-$HOME/.local/share}/openhyprwhisper/models"
mkdir -p "$XDG_DATA_HOME/openhyprwhisper"
[ -d "$REAL_MODELS" ] && ln -s "$REAL_MODELS" "$XDG_DATA_HOME/openhyprwhisper/models"

JFK="$OHW_ROOT/vendor/whisper.cpp/samples/jfk.wav"

# Load ohw's functions (read_state, clean_text, ...) into the harness once,
# for every tier. ohw sets -euo pipefail; undo it so failing asserts don't
# kill the suite.
# shellcheck disable=SC1090
if OHW_LIB_ONLY=1 . "$OHW" 2>/dev/null; then LIB_OK=1; else LIB_OK=0; fi
set +e +o pipefail; set -u

# helper: generate a wav (silence or tone) - 16 kHz mono s16
gen_wav() { # gen_wav <path> <seconds> <amplitude 0..32767> [freq]
    python3 - "$@" <<'PY'
import math, sys, wave
path, secs, amp = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
freq = float(sys.argv[4]) if len(sys.argv) > 4 else 440.0
rate = 16000
with wave.open(path, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    frames = bytearray()
    for i in range(int(rate * secs)):
        v = int(amp * math.sin(2 * math.pi * freq * i / rate)) if amp else 0
        frames += v.to_bytes(2, "little", signed=True)
    w.writeframes(bytes(frames))
PY
}

# =========================================================================
# UNIT
# =========================================================================
run_unit() {
    echo "== unit =="

    # --- scripts parse
    local f ok=1
    for f in "$OHW" "$OHW_ROOT/install.sh" "$OHW_ROOT/tests/run-tests.sh"; do
        bash -n "$f" || ok=0
    done
    [ $ok = 1 ] && pass "bash syntax of all shell scripts" || fail "bash syntax of all shell scripts"
    for f in "$OHW_ROOT"/scripts/*.py; do
        python3 -m py_compile "$f" 2>/dev/null || ok=0
    done
    [ $ok = 1 ] && pass "python syntax of all scripts" || fail "python syntax of all scripts"

    if command -v shellcheck >/dev/null; then
        if shellcheck -S error "$OHW" "$OHW_ROOT/install.sh" >/dev/null 2>&1; then
            pass "shellcheck (error level)"
        else
            fail "shellcheck (error level)"
        fi
    else
        skip "shellcheck" "not installed"
    fi

    # --- ohw loaded as a library (done in setup, asserted here)
    if [ "$LIB_OK" = 1 ] && declare -f read_state >/dev/null; then
        pass "ohw loads as a library"
    else
        fail "ohw loads as a library"; return
    fi

    # --- clean_text: whisper artifacts
    assert_eq "clean_text strips [BLANK_AUDIO]" \
        "hello world" "$(printf ' [BLANK_AUDIO] hello   world\n' | clean_text)"
    assert_eq "clean_text strips *music* markers" \
        "hello" "$(printf '*soft music* hello\n' | clean_text)"
    assert_eq "clean_text drops noise-only (...) lines" \
        "" "$(printf '(wind blowing)\n' | clean_text)"
    assert_eq "clean_text keeps dictated parentheses" \
        "use printf (not echo) here" "$(printf 'use printf (not echo) here\n' | clean_text)"
    assert_eq "clean_text flattens newlines" \
        "one two" "$(printf 'one\ntwo\n' | clean_text)"

    # --- replacements
    mkdir -p "$CONFIG_DIR"
    printf '# comment\ncloud code = Claude Code\nhyper land = Hyprland\n' > "$CONFIG_DIR/replacements"
    assert_eq "replacements fix known mishearings" \
        "I use Claude Code on Hyprland" \
        "$(printf 'I use cloud code on hyper land' | apply_replacements)"
    assert_eq "replacements are case-insensitive" \
        "Claude Code" "$(printf 'CLOUD CODE' | apply_replacements)"
    assert_eq "replacements respect word boundaries" \
        "cloudy codebase" "$(printf 'cloudy codebase' | apply_replacements)"
    rm -f "$CONFIG_DIR/replacements"
    assert_eq "no replacements file = passthrough" \
        "text" "$(printf 'text' | apply_replacements)"

    # --- silence gate (wav-peak)
    gen_wav "$TESTTMP/silence.wav" 1 0
    gen_wav "$TESTTMP/tone.wav" 1 8000
    assert_eq "wav-peak: pure silence is 0" "0" "$(python3 "$OHW_ROOT/scripts/wav-peak.py" "$TESTTMP/silence.wav")"
    local tonepeak; tonepeak=$(python3 "$OHW_ROOT/scripts/wav-peak.py" "$TESTTMP/tone.wav")
    [ "$tonepeak" -gt 3000 ] && pass "wav-peak: tone is loud ($tonepeak)" || fail "wav-peak: tone is loud" "peak=$tonepeak"
    if [ -f "$JFK" ]; then
        local jfkpeak; jfkpeak=$(python3 "$OHW_ROOT/scripts/wav-peak.py" "$JFK")
        [ "$jfkpeak" -gt 1000 ] && pass "wav-peak: real speech passes the gate ($jfkpeak)" \
            || fail "wav-peak: real speech passes the gate" "peak=$jfkpeak"
    else
        skip "wav-peak on real speech" "jfk.wav not built"
    fi

    # --- mic meter: sample-aligned, bounded output
    local meter_out
    meter_out=$(gen_pcm_stream | python3 "$OHW_ROOT/scripts/mic-meter.py")
    local bad; bad=$(printf '%s\n' "$meter_out" | awk '$1 < 0 || $1 > 1' | wc -l)
    assert_eq "mic-meter values stay within [0,1]" "0" "$bad"
    local lines; lines=$(printf '%s\n' "$meter_out" | wc -l)
    [ "$lines" -ge 25 ] && [ "$lines" -le 35 ] && pass "mic-meter rate ~30 fps ($lines/s)" \
        || fail "mic-meter rate ~30 fps" "$lines lines for 1s of audio"

    # --- state machine
    write_state recording
    assert_eq "state roundtrip" "recording" "$(read_state)"
    write_state idle

    # --- usage text
    local usage; usage=$("$OHW" definitely-not-a-command 2>&1)
    assert_contains "usage lists every command" "history" "$usage"
    assert_contains "usage mentions mic picker" "ohw mic" "$usage"

    # --- service templating
    sed -e "s|@OHW_ROOT@|/some/where|" "$OHW_ROOT/assets/openhyprwhisper.service" > "$TESTTMP/svc"
    assert_contains "service ExecStart is templated" "/some/where/bin/ohw daemon run" "$(cat "$TESTTMP/svc")"
    if grep -q 'After=default.target' "$TESTTMP/svc"; then
        fail "service has no ordering cycle"
    else
        pass "service has no ordering cycle"
    fi
}

gen_pcm_stream() { # 1 second of 8 kHz s16 mono noise-ish PCM on stdout
    python3 - <<'PY'
import math, sys
rate = 8000
out = sys.stdout.buffer
for i in range(rate):
    v = int(6000 * math.sin(2 * math.pi * 300 * i / rate))
    out.write(v.to_bytes(2, "little", signed=True))
PY
}

# =========================================================================
# INTEGRATION
# =========================================================================
run_integration() {
    echo "== integration =="

    if ! command -v pw-record >/dev/null || ! pactl info >/dev/null 2>&1; then
        skip "all integration tests" "no pipewire"
        return
    fi
    if [ ! -f "$JFK" ]; then
        skip "all integration tests" "vendor/whisper.cpp not built"
        return
    fi

    # --- transcription backends
    if curl -sf -m 2 http://127.0.0.1:8595/health >/dev/null 2>&1; then
        local text
        text=$(curl -sf "http://127.0.0.1:8595/inference" -F "file=@$JFK" -F response_format=text -F language=auto)
        assert_contains "daemon transcribes real speech" "fellow Americans" "$text"
    else
        skip "daemon transcription" "whisper daemon not running"
    fi

    # --- fake mic for deterministic end-to-end runs
    SINK=$(pactl load-module module-null-sink sink_name=ohwtests 2>/dev/null) || {
        skip "e2e tests" "cannot create null sink"; return; }
    export OHW_AUDIO_SOURCE=ohwtests OHW_RECORD_ARGS="-P stream.capture.sink=true" OHW_INJECT=clipboard

    # --- e2e: speech in, text in clipboard out
    local saved_clip; saved_clip=$(wl-paste 2>/dev/null || true)
    wl-copy "sentinel-before-test" >/dev/null 2>&1
    "$OHW" start >/dev/null 2>&1
    sleep 0.4
    pw-play --target ohwtests "$JFK"
    local t0 t1; t0=$(date +%s%3N)
    "$OHW" stop >/dev/null 2>&1
    t1=$(date +%s%3N)
    assert_contains "e2e: spoken words land in the clipboard" \
        "ask not what your country" "$(wl-paste 2>/dev/null)"
    local ms=$((t1 - t0))
    [ "$ms" -lt 5000 ] && pass "e2e: stop-to-text under 5s (${ms}ms)" \
        || fail "e2e: stop-to-text under 5s" "${ms}ms"
    assert_contains "e2e: transcription saved to history" \
        "ask not what your country" "$(cat "$DATA_DIR/history.tsv" 2>/dev/null || true)"

    # --- e2e: pure silence types nothing
    wl-copy "sentinel-silence" >/dev/null 2>&1
    "$OHW" start >/dev/null 2>&1
    sleep 1.2
    "$OHW" stop >/dev/null 2>&1
    assert_eq "e2e: silence injects nothing" "sentinel-silence" "$(wl-paste 2>/dev/null)"
    assert_eq "e2e: silence ends in state empty" "empty" "$(read_state)"

    # --- cancel discards
    wl-copy "sentinel-cancel" >/dev/null 2>&1
    "$OHW" start >/dev/null 2>&1
    sleep 0.4
    "$OHW" cancel >/dev/null 2>&1
    sleep 0.3
    assert_eq "cancel: state is cancelled" "cancelled" "$(read_state)"
    assert_eq "cancel: nothing injected" "sentinel-cancel" "$(wl-paste 2>/dev/null)"
    pgrep -f "pw-record.*ohwtests.*audio.wav" >/dev/null \
        && fail "cancel: recorder is stopped" || pass "cancel: recorder is stopped"

    # --- double toggle: press starts, press stops (the original lock-leak bug
    # made the second press a silent no-op because children held the lock)
    "$OHW" toggle >/dev/null 2>&1
    sleep 0.4
    assert_eq "toggle #1 starts recording" "recording" "$(read_state)"
    "$OHW" toggle >/dev/null 2>&1
    sleep 1.5
    local st; st=$(read_state)
    [ "$st" != "recording" ] && pass "toggle #2 stops recording (state=$st)" \
        || fail "toggle #2 stops recording" "still recording - lock leaked?"
    # lock must be free for the next session
    "$OHW" start >/dev/null 2>&1
    sleep 0.4
    assert_eq "lock released for next session" "recording" "$(read_state)"
    "$OHW" cancel >/dev/null 2>&1

    # --- watchdog auto-stop
    OHW_MAX_RECORD_SECONDS=2 "$OHW" start >/dev/null 2>&1
    sleep 4.5
    st=$(read_state)
    [ "$st" != "recording" ] && pass "watchdog stops runaway recording (state=$st)" \
        || { fail "watchdog stops runaway recording"; "$OHW" cancel >/dev/null 2>&1; }

    # --- history can be disabled
    rm -f "$DATA_DIR/history.tsv"
    OHW_HISTORY=false "$OHW" start >/dev/null 2>&1
    sleep 0.4
    pw-play --target ohwtests "$JFK" >/dev/null 2>&1
    OHW_HISTORY=false "$OHW" stop >/dev/null 2>&1
    [ -f "$DATA_DIR/history.tsv" ] && fail "HISTORY=false keeps no records" \
        || pass "HISTORY=false keeps no records"

    # --- local polish daemon (optional)
    if curl -sf -m 2 http://127.0.0.1:8596/health >/dev/null 2>&1; then
        local polished
        polished=$(echo "i use cloud code every day" | OHW_POLISH_MODE=full "$OHW_ROOT/scripts/polish-local.py")
        [ -n "$polished" ] && pass "polish-local full returns text" || fail "polish-local full returns text"
        polished=$(echo "yeah i think elden ring is cool" | OHW_POLISH_MODE=light "$OHW_ROOT/scripts/polish-local.py")
        assert_contains "polish-local light keeps casual wording" "yeah" "$polished"
    else
        skip "polish-local daemon" "not running"
    fi

    # restore the user's clipboard
    printf '%s' "$saved_clip" | wl-copy >/dev/null 2>&1 || true

    pactl unload-module "$SINK" >/dev/null 2>&1; SINK=""
    unset OHW_AUDIO_SOURCE OHW_RECORD_ARGS OHW_INJECT
}

# =========================================================================
# UI (needs a live Hyprland + Quickshell session)
# =========================================================================
run_ui() {
    echo "== ui =="

    if ! command -v qs >/dev/null || [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        skip "all ui tests" "no Hyprland/Quickshell session"
        return
    fi

    local statef="$OHW_RUNTIME_DIR/state.json"

    # every state must render without QML errors
    local s
    for s in recording transcribing polishing done empty; do
        printf '{"state":"%s","startedAt":%s}\n' "$s" "$(date +%s%3N)" > "$statef"
        local errs
        errs=$(timeout 3 qs -p "$OHW_ROOT/quickshell/overlay.qml" 2>&1 \
               | grep -ciE 'error|cannot|unable|failed' || true)
        assert_eq "overlay state '$s' renders without errors" "0" "$errs"
    done

    # positions and theme fallback must load cleanly
    local mode
    for mode in top bottom window; do
        printf '{"state":"recording","startedAt":%s}\n' "$(date +%s%3N)" > "$statef"
        local env_extra=()
        [ "$mode" = "window" ] && env_extra=(OHW_ANCHOR="$(hyprctl monitors -j | python3 -c 'import json,sys; m=json.load(sys.stdin)[0]; print(m["name"], 500, 500)')")
        local errs
        errs=$(env OHW_OVERLAY_POSITION="$mode" "${env_extra[@]}" timeout 3 qs -p "$OHW_ROOT/quickshell/overlay.qml" 2>&1 \
               | grep -ciE 'error|cannot|unable|failed' || true)
        assert_eq "overlay position '$mode' renders without errors" "0" "$errs"
    done

    # without end-4 theme files (fresh machine) the fallback palette must work
    # silently - ohw passes empty OHW_THEME_* when the files don't exist
    printf '{"state":"recording","startedAt":%s}\n' "$(date +%s%3N)" > "$statef"
    local errs
    errs=$(env HOME="$TESTTMP" OHW_THEME_COLORS= OHW_THEME_CONFIG= \
           timeout 3 qs -p "$OHW_ROOT/quickshell/overlay.qml" 2>&1 \
           | grep -ciE 'error|cannot|unable|failed' || true)
    assert_eq "overlay works without end-4 theme (fallback palette)" "0" "$errs"

    # terminal states must auto-quit the overlay process
    printf '{"state":"recording","startedAt":%s}\n' "$(date +%s%3N)" > "$statef"
    qs -p "$OHW_ROOT/quickshell/overlay.qml" >/dev/null 2>&1 &
    local qpid=$!
    sleep 1.5
    printf '{"state":"done","startedAt":%s}\n' "$(date +%s%3N)" > "$statef"
    local waited=0 alive=1
    while [ $waited -lt 50 ]; do
        kill -0 "$qpid" 2>/dev/null || { alive=0; break; }
        sleep 0.1; waited=$((waited + 1))
    done
    [ $alive = 0 ] && pass "overlay auto-quits after 'done'" \
        || { fail "overlay auto-quits after 'done'"; kill "$qpid" 2>/dev/null; }
}

# =========================================================================
case "$TIER" in
    unit)        run_unit ;;
    integration) run_integration ;;
    ui)          run_ui ;;
    all)         run_unit; run_integration; run_ui ;;
    *)           echo "usage: $0 [unit|integration|ui|all]"; exit 2 ;;
esac

echo
printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed: %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
