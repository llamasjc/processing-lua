#!/usr/bin/env bash
# Builds the libprocessing runner (Bevy + wgpu) that LuaMode uses when the
# toolbar's renderer menu says libprocessing. The first build takes a while.
#
# Uses your own libprocessing checkout when there is one: LIBPROCESSING_DIR,
# then ~/lp-fork, then ~/sketchbook/libprocessing. Otherwise the libprocessing
# commit pinned in RustMode's Cargo.toml.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
FORK=${LIBPROCESSING_DIR:-}
if [ -z "$FORK" ]; then
  if [ -f "$HOME/lp-fork/crates/processing_render/Cargo.toml" ]; then FORK="$HOME/lp-fork"
  else FORK=$(cd "$HERE/../../.." && pwd)/libprocessing; fi
fi
ARGS=()
if [ -f "$FORK/crates/processing_render/Cargo.toml" ]; then
  echo "libprocessing from $FORK"
  # RustMode's build.rs checks this same checkout for what it supports
  export LIBPROCESSING_DIR="$FORK"
  for c in processing_core processing_render processing_input processing_glfw; do
    ARGS+=(--config "patch.\"https://github.com/processing/libprocessing\".$c.path=\"$FORK/crates/$c\"")
  done
else
  echo "libprocessing: the pinned upstream commit (no checkout at $FORK)"
fi
cargo build --release --features libprocessing --target-dir target-libprocessing "${ARGS[@]}" "$@"
echo "built: $HERE/target-libprocessing/release/luamode-runner"
