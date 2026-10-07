#!/usr/bin/env bash
# A sketch started by the IDE must close when the IDE dies without cleaning
# up. The IDE holds the sketch's stdin open; this plays the IDE with a
# process that gets killed the hard way.
#
#   runner/tests/ide_gone.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=${RUNNER:-$HERE/../target/release/luamode-runner}
[ -x "$RUNNER" ] || { echo "no runner at $RUNNER" >&2; exit 2; }
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(uname -s)" = Linux ]; then
  command -v xvfb-run >/dev/null || { echo "skipped: no display and no xvfb-run"; exit 0; }
  exec xvfb-run -a "$0" "$@"
fi

PIDFILE=$(mktemp)
trap 'rm -f "$PIDFILE"' EXIT
fail=0

# 1. the "IDE" (sleep) feeds stdin, then is killed with -9
( sleep 600 | { LUAMODE_WATCH_STDIN=1 "$RUNNER" "$HERE/empty_stays_open.lua" >/dev/null 2>&1 & echo $! >"$PIDFILE"; wait; } ) &
sleep 1.5
PID=$(cat "$PIDFILE")
if ! kill -0 "$PID" 2>/dev/null; then echo "FAIL  sketch did not stay open while the IDE was alive"; fail=1; fi
pkill -9 -P $! sleep 2>/dev/null || pkill -9 -f "sleep 600"
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.3; done
if kill -0 "$PID" 2>/dev/null; then echo "FAIL  sketch outlived the IDE"; kill -9 "$PID"; fail=1; else echo "ok    sketch closes when the IDE is killed"; fi

# 2. run by hand (no LUAMODE_WATCH_STDIN): closed stdin must not close the sketch
"$RUNNER" "$HERE/empty_stays_open.lua" </dev/null >/dev/null 2>&1 &
PID=$!
sleep 1.5
if kill -0 "$PID" 2>/dev/null; then echo "ok    run by hand, stdin closed: stays open"; kill "$PID"; else echo "FAIL  sketch run by hand closed on its own"; fail=1; fi

exit $fail
