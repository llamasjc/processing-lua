#!/usr/bin/env bash
# Runs every tests/*.lua through luamode-runner and checks what it does.
#
#   runner/tests/run.sh                 all tests
#   runner/tests/run.sh err_ fuzz       only tests whose name contains one of these
#   RUNNER=target-libprocessing/release/luamode-runner PROCESSING_RENDERER=libprocessing runner/tests/run.sh
#                                       the same tests on libprocessing
#
# Each test says what it expects in comments at the top of the file:
#   -- rc: 1                 exit status (default 0; 124 means "still running
#                            when the time is up", for sketches that stay open)
#   -- stdout: some text     must appear in stdout (repeatable)
#   -- stderr: some text     must appear in stderr (repeatable)
#   -- stderr-lines: 1       exact number of stderr lines
#   -- timeout: 5            seconds before the sketch is stopped (default 20)
#   -- env: NAME=value       extra environment (repeatable)
#
# Tests run in a scratch folder; LUAMODE_TESTS is this folder, for tests that
# need a file from tests/assets.
#
# Needs a display. Without one it re-runs itself under xvfb-run.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=${RUNNER:-$HERE/../target/release/luamode-runner}
[ -x "$RUNNER" ] || RUNNER=$RUNNER.exe
[ -x "$RUNNER" ] || { echo "no runner at $RUNNER (cargo build --release first)" >&2; exit 2; }
# tests run from a scratch folder, so a relative path has to become absolute
case $RUNNER in /*) ;; *) RUNNER=$(cd "$(dirname "$RUNNER")" && pwd)/$(basename "$RUNNER") ;; esac

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(uname -s)" = Linux ]; then
  command -v xvfb-run >/dev/null || { echo "no display and no xvfb-run" >&2; exit 2; }
  exec xvfb-run -a "$0" "$@"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0; failed=()

directive() { sed -n "s/^-- $2: *//p" "$1"; }

for t in "$HERE"/*.lua; do
  name=$(basename "$t" .lua)
  if [ $# -gt 0 ]; then
    hit=0; for f in "$@"; do case $name in *"$f"*) hit=1 ;; esac; done
    [ $hit = 1 ] || continue
  fi

  want_rc=$(directive "$t" rc | head -1);        want_rc=${want_rc:-0}
  secs=$(directive "$t" timeout | head -1);      secs=${secs:-20}
  want_lines=$(directive "$t" stderr-lines | head -1)

  dir=$WORK/$name; mkdir -p "$dir"
  envs=()
  while IFS= read -r e; do [ -n "$e" ] && envs+=("$e"); done < <(directive "$t" env)

  ( cd "$dir" && env LUAMODE_TESTS="$HERE" ${envs[@]+"${envs[@]}"} timeout -k 5 "$secs" "$RUNNER" "$t" >out.txt 2>err.txt )
  rc=$?
  # The next test starts only once this runner is really gone: one still
  # tearing down its window and GPU (the libprocessing runner takes a while
  # on a slow machine) slows the next sketch down, sometimes past its time.
  for _ in $(seq 50); do pgrep -f -- "$RUNNER" >/dev/null || break; sleep 0.2; done

  why=""
  [ "$rc" = "$want_rc" ] || why="exit status $rc, expected $want_rc"
  while IFS= read -r s; do
    [ -z "$s" ] || grep -qF -- "$s" "$dir/out.txt" || why="${why:+$why; }stdout lacks '$s'"
  done < <(directive "$t" stdout)
  while IFS= read -r s; do
    [ -z "$s" ] || grep -qF -- "$s" "$dir/err.txt" || why="${why:+$why; }stderr lacks '$s'"
  done < <(directive "$t" stderr)
  if [ -n "$want_lines" ]; then
    n=$(grep -c '' "$dir/err.txt")
    [ "$n" = "$want_lines" ] || why="${why:+$why; }$n stderr lines, expected $want_lines"
  fi

  if [ -z "$why" ]; then
    pass=$((pass + 1)); echo "ok    $name"
  else
    fail=$((fail + 1)); failed+=("$name"); echo "FAIL  $name: $why"
    sed 's/^/        out| /' "$dir/out.txt" | head -15
    sed 's/^/        err| /' "$dir/err.txt" | head -15
  fi
done

echo
echo "$pass passed, $fail failed"
[ $fail = 0 ] || { printf '  %s\n' "${failed[@]}"; exit 1; }
