#!/usr/bin/env python3
"""Measure production scanning/tag code without launching the player or decoding media."""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-cache", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="myplayer-benchmarks-") as temporary:
        scratch = Path(temporary)
        source = root / "Sources/MacVideoPlayer"
        binary = scratch / "benchmarks"
        subprocess.run([
            "swiftc", "-O", "-swift-version", "6", "-parse-as-library",
            "-module-cache-path", str(args.module_cache or scratch / "module-cache"),
            "-target", f"{platform.machine()}-apple-macosx13.0",
            *(str(source / name) for name in [
                "AppLanguage.swift", "Models.swift", "VideoFileScanner.swift", "TagStore.swift"
            ]),
            str(root / "Tests/PerformanceBenchmarks/main.swift"), "-o", str(binary)
        ], check=True, timeout=300)
        subprocess.run([str(binary), str(scratch / "fixtures")], check=True, timeout=120)


if __name__ == "__main__":
    main()
