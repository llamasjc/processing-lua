#!/usr/bin/env bash
# Runs every sketch under examples/ for a few seconds. Each one has to keep
# running (or finish on its own) without printing an error.
#
#   runner/tests/examples.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RUNNER=${RUNNER:-$HERE/../target/release/luamode-runner}
[ -x "$RUNNER" ] || { echo "no runner at $RUNNER" >&2; exit 2; }
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(uname -s)" = Linux ]; then
  command -v xvfb-run >/dev/null || { echo "no display and no xvfb-run" >&2; exit 2; }
  exec xvfb-run -a "$0" "$@"
fi

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT
fail=0; n=0
while IFS= read -r -d '' sketch; do
  name=${sketch#"$ROOT/examples/"}
  # written for Roblox Studio; there is no `game` object anywhere else
  if grep -q 'game\.ReplicatedStorage' "$sketch"; then echo "skip  $name (Roblox only)"; continue; fi
  n=$((n + 1))
  ( cd "$(dirname "$sketch")" && timeout 3 "$RUNNER" "$sketch" >/dev/null 2>"$ERR" )
  rc=$?
  if { [ $rc = 124 ] || [ $rc = 0 ]; } && [ ! -s "$ERR" ]; then
    echo "ok    $name"
  else
    fail=$((fail + 1)); echo "FAIL  $name (exit status $rc)"; sed 's/^/        err| /' "$ERR" | head -10
  fi
done < <(find "$ROOT/examples" -name '*.lua' -print0 | sort -z)

echo
echo "$n examples, $fail failed"
[ $fail = 0 ]
