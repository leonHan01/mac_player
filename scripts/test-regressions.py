#!/usr/bin/env python3
"""Run core regressions without XCTest, opening a window, or decoding media."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, timeout=300, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def check_packaging(root, scratch):
    project = scratch / "clean-project"
    scripts = project / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy2(root / "scripts/build-dmg.sh", scripts / "build-dmg.sh")
    builder = scripts / "build-app.sh"
    builder.write_text('#!/bin/sh\nset -eu\nmkdir -p "$(dirname "$0")/../build/MacVideoPlayer.app"\n')
    builder.chmod(0o755)
    fakebin = scratch / "bin"
    fakebin.mkdir()
    disk_image = fakebin / "hdiutil"
    disk_image.write_text('#!/bin/sh\nfor destination do :; done\n: > "$destination"\n')
    disk_image.chmod(0o755)
    env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"], APP_VERSION="test")
    run(["bash", str(scripts / "build-dmg.sh")], env=env)
    assert (project / "build/MacVideoPlayer-test.dmg").exists(), "Clean packaging did not reach image creation"
    assert not list((project / "build").glob("dmg-staging.*")), "Packaging did not clean its staging directory"
    print("PASS: DMG staging on a clean checkout (build and image tools stubbed)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-cache", type=Path, help="Reuse an existing Swift module cache")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="myplayer-regressions-") as temporary:
        scratch = Path(temporary).resolve()
        check_packaging(root, scratch)
        cache = args.module_cache or scratch / "module-cache"
        common = ["-swift-version", "6", "-module-cache-path", str(cache),
                  "-target", f"{platform.machine()}-apple-macosx13.0"]
        sources = sorted(str(p) for p in (root / "Sources/MacVideoPlayer").glob("*.swift")
                         if p.name != "main.swift" and not p.name.startswith("._"))
        run(["swiftc", *common, "-parse-as-library", "-enable-testing", "-emit-library", "-emit-module",
             "-module-name", "MacVideoPlayer", "-emit-module-path", str(scratch / "MacVideoPlayer.swiftmodule"),
             *sources, "-o", str(scratch / "libMacVideoPlayer.dylib")])
        fake = scratch / "fake-mpv.dylib"
        run(["clang", "-dynamiclib", str(root / "Tests/Fixtures/fake-mpv.c"), "-o", str(fake)])
        runner = scratch / "regressions"
        checks = sorted(str(p) for p in (root / "Tests/RegressionChecks").glob("*.swift")
                        if not p.name.startswith("._"))
        run(["swiftc", *common, "-parse-as-library", "-I", str(scratch), "-L", str(scratch),
             "-lMacVideoPlayer", "-Xlinker", "-rpath", "-Xlinker", str(scratch),
             *checks, "-o", str(runner)])
        print(run([str(runner), str(fake), str(scratch / "fixtures")]), end="", flush=True)


if __name__ == "__main__":
    main()
