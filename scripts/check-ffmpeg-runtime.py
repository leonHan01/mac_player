#!/usr/bin/env python3
"""Verify that the bundled FFmpeg runs without third-party dynamic libraries."""
import argparse
import os
from pathlib import Path
import re
import subprocess


def run(arguments, env=None):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=30, env=env)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def verify(binary, architectures, deployment_target="13.0", execute=True):
    binary = Path(binary).resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError(f"Missing executable FFmpeg: {binary}")
    actual_architectures = run(["/usr/bin/lipo", "-archs", str(binary)]).split()
    if not set(architectures) <= set(actual_architectures):
        raise RuntimeError(f"FFmpeg architectures {actual_architectures} do not cover {architectures}")
    for arch in architectures:
        dependencies = run(["/usr/bin/otool", "-arch", arch, "-L", str(binary)])
        for line in dependencies.splitlines():
            if " (compatibility version " not in line:
                continue
            path = line.strip().split(" (compatibility version ")[0]
            if not path.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError(f"FFmpeg depends on an external library: {path}")
        commands = run(["/usr/bin/otool", "-arch", arch, "-l", str(binary)])
        match = re.search(r"\bminos\s+(\d+(?:\.\d+)*)", commands)
        if not match:
            match = re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+(?:\.\d+)*)", commands)
        if not match:
            raise RuntimeError(f"FFmpeg has no macOS deployment target for {arch}")
        version = lambda text: tuple((list(map(int, text.split('.'))) + [0, 0])[:3])
        if version(match[1]) > version(deployment_target):
            raise RuntimeError(f"FFmpeg requires macOS {match[1]}, above the app's {deployment_target} target")
    if execute:
        # Exclude developer package managers and dyld overrides from validation.
        env = {key: value for key, value in os.environ.items() if not key.startswith("DYLD_")}
        env["PATH"] = "/usr/bin:/bin"
        output = run([str(binary), "-hide_banner", "-version"], env)
        encoders = run([str(binary), "-hide_banner", "-encoders"], env)
        if not re.search(r"^ V\S*\s+libx264\s", encoders, re.MULTILINE):
            raise RuntimeError("Bundled FFmpeg has no libx264 encoder")
        if not re.search(r"^ A\S*\s+aac\s", encoders, re.MULTILINE):
            raise RuntimeError("Bundled FFmpeg has no AAC encoder")
        print(output.splitlines()[0], flush=True)
    print(f"PASS: standalone FFmpeg, {', '.join(architectures)}, macOS {deployment_target} or earlier", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--arch", action="append", required=True)
    parser.add_argument("--deployment-target", default="13.0")
    parser.add_argument("--skip-execution", action="store_true")
    args = parser.parse_args()
    verify(args.binary, args.arch, args.deployment_target, not args.skip_execution)


if __name__ == "__main__":
    main()
