#!/usr/bin/env bash
# Sends real mouse and keyboard events to a sketch (with xdotool) and checks
# that every callback fires with the right values. Linux/X11 only; skipped
# when xdotool or xvfb-run isn't installed.
#
#   runner/tests/input.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=${RUNNER:-$HERE/../target/release/luamode-runner}
command -v xdotool >/dev/null || { echo "skipped: xdotool not installed"; exit 0; }
[ -x "$RUNNER" ] || { echo "no runner at $RUNNER" >&2; exit 2; }
# Always under a private X server: these events must never land on a real desktop.
command -v xvfb-run >/dev/null || { echo "skipped: xvfb-run not installed"; exit 0; }
[ -n "${LUAMODE_INPUT_TEST_XVFB:-}" ] || exec env LUAMODE_INPUT_TEST_XVFB=1 xvfb-run -a "$0" "$@"

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
"$RUNNER" "$HERE/input/events.lua" >"$OUT" 2>&1 &
PID=$!
sleep 1.5
WIN=$(xdotool search --pid $PID | head -1)
[ -n "$WIN" ] || WIN=$(xdotool search --name "Lua sketch" | head -1)
[ -n "$WIN" ] || { echo "FAIL: sketch window not found"; kill $PID; exit 1; }
xdotool windowfocus "$WIN" 2>/dev/null
step() { "$@"; sleep 0.2; }
step xdotool mousemove --window "$WIN" 50 60
step xdotool mousemove --window "$WIN" 80 90
step xdotool mousedown 1
step xdotool mousemove --window "$WIN" 120 100
step xdotool mouseup 1
step xdotool click 4
step xdotool key a
step xdotool key shift+b
step xdotool key Up
step xdotool key Left
step xdotool key Return
step xdotool key space
step xdotool key Escape
sleep 0.5
if kill -0 $PID 2>/dev/null; then echo "FAIL: Escape did not close the sketch"; kill $PID; exit 1; fi
wait $PID; rc=$?

fail=0
[ $rc = 0 ] || { echo "FAIL: exit status $rc"; fail=1; }
TAB=$(printf '\t')
while IFS= read -r want; do
  grep -qF -- "$want" "$OUT" || { echo "FAIL: missing: $want"; fail=1; }
done <<EOF2
mouseMoved${TAB}80${TAB}90
mousePressed${TAB}80${TAB}90${TAB}37${TAB}true
mouseDragged${TAB}120${TAB}100${TAB}37
mouseReleased${TAB}120${TAB}100${TAB}37
mouseClicked
mouseWheel
keyPressed${TAB}[a]${TAB}65${TAB}true
keyTyped${TAB}[a]
keyReleased${TAB}[a]${TAB}65
keyPressed${TAB}CODED${TAB}16
keyTyped${TAB}[B]
keyPressed${TAB}CODED${TAB}38
keyReleased${TAB}CODED${TAB}38
keyPressed${TAB}CODED${TAB}37
keyTyped${TAB}[ ]
keyPressed${TAB}[$(printf '\033')]${TAB}27
EOF2
[ "$(grep -c '^keyPressed' "$OUT")" = 8 ] || { echo "FAIL: expected 8 keyPressed, got $(grep -c '^keyPressed' "$OUT")"; fail=1; }
[ "$(grep -c '^mousePressed' "$OUT")" = 1 ] || { echo "FAIL: expected 1 mousePressed"; fail=1; }
if [ $fail = 0 ]; then echo "ok    input events"; else sed 's/^/        | /' "$OUT"; exit 1; fi
