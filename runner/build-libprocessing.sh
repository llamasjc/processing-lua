#!/usr/bin/env bash
# Builds the libprocessing runner (Bevy + wgpu) that LuaMode uses when the
# toolbar's renderer menu says libprocessing. The first build takes a while.
#
# Uses your own libprocessing checkout when there is one: LIBPROCESSING_DIR,
# or ~/sketchbook/libprocessing next to the modes folder. Otherwise the
# libprocessing commit pinned in RustMode's Cargo.toml.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
FORK=${LIBPROCESSING_DIR:-$(cd "$HERE/../../.." && pwd)/libprocessing}
ARGS=()
if [ -f "$FORK/crates/processing_render/Cargo.toml" ]; then
  echo "libprocessing from $FORK"
  for c in processing_core processing_render processing_input processing_glfw; do
    ARGS+=(--config "patch.\"https://github.com/processing/libprocessing\".$c.path=\"$FORK/crates/$c\"")
  done
else
  echo "libprocessing: the pinned upstream commit (no checkout at $FORK)"
fi
cargo build --release --features libprocessing --target-dir target-libprocessing "${ARGS[@]}" "$@"
echo "built: $HERE/target-libprocessing/release/luamode-runner"
