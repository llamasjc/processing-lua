#!/usr/bin/env bash
# Builds the libprocessing runner (Bevy + wgpu) that LuaMode uses when the
# toolbar's renderer menu says libprocessing. The first build takes a while.
#
# Uses your own libprocessing checkout when there is one: LIBPROCESSING_DIR,
# then ~/lp-fork, then ~/sketchbook/libprocessing. Otherwise the libprocessing
# commit pinned in RustMode's Cargo.toml.
#
#   --upstream  build from the pinned commit even with a checkout, and copy
#               the runner to mode/runner/<platform>-libprocessing/, which is
#               what releases ship. Your fork build (target-libprocessing/)
#               is left alone, and the IDE keeps preferring it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
UPSTREAM=0
if [ "${1:-}" = "--upstream" ]; then UPSTREAM=1; shift; fi
FORK=${LIBPROCESSING_DIR:-}
if [ "$UPSTREAM" = 1 ]; then FORK=/nonexistent; unset LIBPROCESSING_DIR
elif [ -z "$FORK" ]; then
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
if [ "$UPSTREAM" = 1 ]; then
  # own target folder so it never overwrites your fork build; after the first
  # time only what changed recompiles
  cargo build --release --features libprocessing --target-dir target-libprocessing-upstream "$@"
  case "$(uname -s)" in Darwin) OS=macos;; MINGW*|MSYS*|CYGWIN*) OS=windows;; *) OS=linux;; esac
  case "$(uname -m)" in arm64|aarch64) ARCH=aarch64;; *) ARCH=x86_64;; esac
  EXE=luamode-runner; [ "$OS" = windows ] && EXE=luamode-runner.exe
  DEST="$HERE/../mode/runner/$OS-$ARCH-libprocessing"
  mkdir -p "$DEST"
  cp "target-libprocessing-upstream/release/$EXE" "$DEST/$EXE"
  # GLFW 3.4 goes along, so the runner works where it isn't installed
  case "$OS" in
    linux)
      L=$(pkg-config --variable=libdir glfw3 2>/dev/null)
      for d in "$L" /usr/local/lib /usr/lib /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu; do
        if [ -n "$d" ] && [ -e "$d/libglfw.so.3" ]; then cp -L "$d/libglfw.so.3" "$DEST/"; echo "GLFW: $d/libglfw.so.3"; break; fi
      done;;
    macos)
      f=$(ls target-libprocessing-upstream/release/build/glfw-sys-*/out/*/lib-*/libglfw.3.dylib 2>/dev/null | head -1)
      [ -z "$f" ] && f="$(brew --prefix glfw 2>/dev/null)/lib/libglfw.3.dylib"
      [ -e "$f" ] && cp -L "$f" "$DEST/libglfw.3.dylib";;
    windows)
      f=$(ls target-libprocessing-upstream/release/build/glfw-sys-*/out/*/lib-vc*/glfw3.dll 2>/dev/null | head -1)
      [ -e "$f" ] && cp "$f" "$DEST/";;
  esac
  echo "built: $DEST/$EXE (pinned libprocessing, goes in releases)"
else
  cargo build --release --features libprocessing --target-dir target-libprocessing ${ARGS[@]+"${ARGS[@]}"} "$@"
  echo "built: $HERE/target-libprocessing/release/luamode-runner"
fi
