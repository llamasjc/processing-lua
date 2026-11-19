#!/usr/bin/env python3
"""processing-lua-standalone.zip: Lua sketches without the Processing IDE,
like C++ Mode's plug-and-play package. Every platform's runner (both
renderers), the examples, and run scripts that pick the right runner:

    ./run.sh sketch.lua          (Linux, macOS)
    run.bat sketch.lua           (Windows)
    ./run.sh --libprocessing sketch.lua

Made from a LuaMode.zip, which already has every runner:

    scripts/generate_standalone.py LuaMode.zip [--out FOLDER]
"""
import argparse, shutil, stat, zipfile
from pathlib import Path

HELLO = '''-- A Processing sketch in Lua. setup() runs once, draw() every frame.
local x = 0

function setup()
  size(640, 360)
end

function draw()
  background(30)
  x = (x + 2) % width
  fill(255, 120, 0)
  ellipse(x, height / 2, 60, 60)
  fill(255)
  text("Hello from processing-lua", 20, 30)
end
'''

RUN_SH = '''#!/bin/sh
# Runs a Lua sketch: ./run.sh [--libprocessing] sketch.lua
HERE=$(cd "$(dirname "$0")" && pwd -P)
SUFFIX=""
if [ "$1" = "--libprocessing" ]; then SUFFIX="-libprocessing"; export PROCESSING_RENDERER=libprocessing; shift; fi
SKETCH=${1:-"$HERE/hello.lua"}
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  P=linux-x86_64 ;;
  Linux-aarch64) P=linux-aarch64 ;;
  Darwin-arm64)  P=macos-aarch64 ;;
  Darwin-x86_64) P=macos-x86_64 ;;
  *) echo "no runner for $(uname -s) $(uname -m)"; exit 1 ;;
esac
R="$HERE/runner/$P$SUFFIX"
[ -x "$R/luamode-runner" ] || chmod +x "$R/luamode-runner" 2>/dev/null
# macOS marks downloaded files as quarantined; the runner is ours
[ "$(uname -s)" = Darwin ] && xattr -dr com.apple.quarantine "$R" 2>/dev/null
export LD_LIBRARY_PATH="$R${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DYLD_LIBRARY_PATH="$R${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
# relative paths (loadImage, data/) are next to the sketch, as in Processing
cd "$(dirname "$SKETCH")" || exit 1
exec "$R/luamode-runner" "$(basename "$SKETCH")"
'''

RUN_BAT = '''@echo off
rem Runs a Lua sketch: run.bat [--libprocessing] sketch.lua
set HERE=%~dp0
set R=%HERE%runner\\windows-x86_64
if "%~1"=="--libprocessing" (
  set R=%HERE%runner\\windows-x86_64-libprocessing
  set PROCESSING_RENDERER=libprocessing
  shift
)
set SKETCH=%~1
if "%SKETCH%"=="" set SKETCH=%HERE%hello.lua
set PATH=%R%;%PATH%
for %%F in ("%SKETCH%") do (cd /d "%%~dpF" & "%R%\\luamode-runner.exe" "%%~nxF")
'''

README = '''# processing-lua standalone

Processing sketches in Lua, without the Processing IDE. Nothing to install:
the runners for Linux (x86_64, ARM), macOS (Intel, Apple Silicon) and
Windows are in `runner/`.

    ./run.sh hello.lua                    Linux, macOS
    run.bat hello.lua                     Windows
    ./run.sh --libprocessing hello.lua    the libprocessing renderer (graphics card)

`examples/` has all of Processing's Basics and Topics examples in Lua. Files
a sketch loads go in a `data/` folder next to it.
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("luamode_zip", type=Path)
    ap.add_argument("--out", type=Path, default=Path("dist"))
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    out = a.out / "processing-lua-standalone.zip"
    if out.exists():
        out.unlink()
    base = "processing-lua-standalone/"
    runners = 0
    with zipfile.ZipFile(a.luamode_zip) as src, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for info in src.infolist():
            name = info.filename
            parts = name.split("/")
            if len(parts) < 3 or info.is_dir():
                continue
            if parts[1] == "mode" and len(parts) > 3 and parts[2] == "runner":
                rel = "runner/" + "/".join(parts[3:])
                runners += rel.endswith(("luamode-runner", "luamode-runner.exe"))
            elif parts[1] == "examples":
                rel = "/".join(parts[1:])
            else:
                continue
            zi = zipfile.ZipInfo(base + rel, info.date_time)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if rel.endswith("luamode-runner") else 0o644) << 16
            z.writestr(zi, src.read(info))
        for rel, text, mode in [("hello.lua", HELLO, 0o644), ("run.sh", RUN_SH, 0o755),
                                ("run.bat", RUN_BAT.replace("\n", "\r\n"), 0o644), ("README.md", README, 0o644)]:
            zi = zipfile.ZipInfo(base + rel, (2026, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = mode << 16
            z.writestr(zi, text)
    print(f"Wrote {out} ({out.stat().st_size // (1024 * 1024)} MB, {runners} runners)")


if __name__ == "__main__":
    main()
