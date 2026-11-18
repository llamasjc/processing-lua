#!/usr/bin/env bash
# Starts a few of the examples with the runner for a few seconds each and
# fails if one exits early or prints an error. Works on Linux (under
# xvfb-run), macOS and Windows (Git Bash), so CI checks what users get.
#
#   RUNNER=path/to/luamode-runner runner/tests/smoke.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RUNNER=${RUNNER:?set RUNNER to the runner binary}
SECS=${SECS:-4}
fail=0
for ex in "Topics/Motion/Bounce" "Basics/Image/LoadDisplayImage" "Topics/Simulate/Flocking" \
          "Basics/Typography/Words" "Basics/Lights/Directional"; do
  dir="$ROOT/examples/$ex"
  name=$(basename "$ex")
  [ -f "$dir/$name.lua" ] || { echo "skip $ex (not there)"; continue; }
  err=$(mktemp)
  ( cd "$dir" && exec "$RUNNER" "$name.lua" ) >/dev/null 2>"$err" &
  pid=$!
  for _ in $(seq 1 $((SECS * 10))); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
  if kill -0 $pid 2>/dev/null; then
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    if grep -qiE "error|panic|attempt to" "$err"; then echo "FAIL  $ex"; cat "$err"; fail=1
    else echo "ok    $ex"; fi
  else
    wait $pid; rc=$?
    echo "FAIL  $ex (exited with $rc)"; cat "$err"; fail=1
  fi
  rm -f "$err"
done
exit $fail
