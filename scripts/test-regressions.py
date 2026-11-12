#!/usr/bin/env python3
"""Run core regressions without XCTest, opening a window, or decoding media."""
import argparse
import contextlib
import importlib.util
import io
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


def check_ffmpeg_portability(root, scratch):
    specification = importlib.util.spec_from_file_location("ffmpeg_check", root / "scripts/check-ffmpeg-runtime.py")
    checker = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(checker)
    architecture = platform.machine()
    source = scratch / "portable-runtime.c"
    source.write_text("int main(void) { return 0; }\n")
    portable = scratch / "portable-runtime"
    too_new = scratch / "newer-runtime"
    run(["clang", "-mmacosx-version-min=13.0", str(source), "-o", str(portable)])
    run(["clang", "-mmacosx-version-min=15.0", str(source), "-o", str(too_new)])
    library_source = scratch / "external-runtime.c"
    library_source.write_text("int external_runtime(void) { return 0; }\n")
    library = scratch / "libexternal-runtime.dylib"
    run(["clang", "-mmacosx-version-min=13.0", "-dynamiclib", str(library_source),
         "-install_name", "/opt/homebrew/lib/libexternal-runtime.dylib", "-o", str(library)])
    source.write_text("extern int external_runtime(void); int main(void) { return external_runtime(); }\n")
    external = scratch / "externally-linked-runtime"
    run(["clang", "-mmacosx-version-min=13.0", str(source), str(library), "-o", str(external)])
    with contextlib.redirect_stdout(io.StringIO()):
        checker.verify(portable, [architecture], execute=False)
    for binary, arches, expected in [
        (external, [architecture], "external library"),
        (too_new, [architecture], "above the app's"),
        (portable, ["x86_64" if architecture == "arm64" else "arm64"], "architectures"),
    ]:
        try:
            checker.verify(binary, arches, execute=False)
        except RuntimeError as error:
            assert expected in str(error), error
        else:
            raise AssertionError(f"Non-portable clip runtime was accepted: {binary}")
    print("PASS: FFmpeg packaging rejects external libraries, newer macOS requirements, and mismatched architectures", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-cache", type=Path, help="Reuse an existing Swift module cache")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="myplayer-regressions-") as temporary:
        scratch = Path(temporary).resolve()
        fixtures = scratch / "fixtures"
        fixtures.mkdir()
        clip_encoder = fixtures / "fake-ffmpeg"
        shutil.copy2(root / "Tests/Fixtures/fake-ffmpeg.py", clip_encoder)
        clip_encoder.chmod(0o755)
        check_packaging(root, scratch)
        check_ffmpeg_portability(root, scratch)
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
