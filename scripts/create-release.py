#!/usr/bin/env python3
"""
Makes LuaMode-<version>.zip next to the LuaMode folder, ready to upload as a
release. Nothing is pushed and nothing in the repo changes. The version is
prettyVersion in mode.properties.

It zips what's in your folder, like CppMode's script:

1. The CPU runner: gradle builds it (seconds when nothing changed).
2. The libprocessing runner from mode/runner/<platform>-libprocessing/, the
   one built from the pinned commit. If it's missing or older than the
   runner sources, it says so and gives the command; --build-runner builds
   it first. Your fork build (runner/target-libprocessing/) never goes in.
3. gradle dist, then the zip is renamed with the version.

    --build-runner   build the pinned libprocessing runner first if it's stale
"""
import platform, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def plat():
    s = platform.system().lower()
    os_ = "macos" if s == "darwin" else "windows" if s.startswith(("win", "msys", "cygwin", "mingw")) else "linux"
    arch = "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
    return f"{os_}-{arch}"


def version():
    for line in (ROOT / "mode.properties").read_text().splitlines():
        if line.startswith("prettyVersion="):
            return line.split("=", 1)[1].strip()
    return ""


def newest_source():
    files = [ROOT / "runner" / "Cargo.toml", ROOT / "runner" / "Cargo.lock"]
    files += [f for f in (ROOT / "runner" / "src").rglob("*") if f.is_file()]
    return max(f.stat().st_mtime for f in files if f.exists())


def lp_runner():
    exe = "luamode-runner.exe" if plat().startswith("windows") else "luamode-runner"
    return ROOT / "mode" / "runner" / f"{plat()}-libprocessing" / exe


def check_lp(build):
    r = lp_runner()
    ok = r.is_file() and r.stat().st_mtime >= newest_source()
    print(f"{plat()} libprocessing runner: {'ok, goes in' if ok else 'stale or missing'}")
    if ok:
        return
    if not build:
        print("  build it with: runner/build-libprocessing.sh --upstream  (or rerun with --build-runner)")
        print("  zipping without it: libprocessing won't work from this release")
        return
    if subprocess.run(["bash", str(ROOT / "runner" / "build-libprocessing.sh"), "--upstream"]).returncode:
        sys.exit("the libprocessing runner build failed")


if __name__ == "__main__":
    v = version()
    print(f"LuaMode {v}")
    check_lp("--build-runner" in sys.argv)
    gradle = shutil.which("gradle") or str(ROOT / "gradlew")
    if subprocess.run([gradle, "dist", "-q"], cwd=ROOT).returncode:
        sys.exit("gradle dist failed")
    src = ROOT / "build" / "distributions" / "LuaMode.zip"
    out = ROOT.parent / "LuaMode.zip"
    shutil.copy(src, out)
    print(f"\n{out}  ({out.stat().st_size // (1024 * 1024)} MB)")
