#!/usr/bin/env python3
"""Validate and bundle the standalone clip encoder and its corresponding sources."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--app-binary", type=Path, required=True)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    runtime = args.runtime.resolve()
    manifest = json.loads((runtime / "sources.json").read_text())
    info = json.loads((runtime / "build-info.json").read_text())
    if info["sources"] != manifest["sources"] or info["deploymentTarget"] != manifest["deploymentTarget"]:
        raise RuntimeError("FFmpeg build metadata does not match the supplied source manifest; rebuild the runtime")
    binary = runtime / "bin/ffmpeg"
    if hashlib.sha256(binary.read_bytes()).hexdigest() != info["binarySHA256"]:
        raise RuntimeError("FFmpeg binary checksum mismatch; rebuild the runtime")
    for record in manifest["sources"].values():
        archive = runtime / "Sources" / record["archive"]
        if hashlib.sha256(archive.read_bytes()).hexdigest() != record["sha256"]:
            raise RuntimeError(f"FFmpeg corresponding source checksum mismatch: {archive}")
    for name in ["FFmpeg-GPL-2.0.txt", "FFmpeg-GPL-3.0.txt", "FFmpeg-LICENSE.md", "x264-GPL-2.0.txt", "pkgconf-ISC.txt"]:
        if not (runtime / "Licenses" / name).is_file():
            raise RuntimeError(f"Missing FFmpeg license: {name}")
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(args.app_binary)], text=True).split()
    specification = importlib.util.spec_from_file_location("ffmpeg_runtime_check", root / "scripts/check-ffmpeg-runtime.py")
    checker = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(checker)
    checker.verify(binary, architectures, "13.0")
    if not args.app:
        return
    contents = args.app / "Contents"
    executable = contents / "MacOS/ffmpeg"
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, executable)
    resources = contents / "Resources/FFmpeg"
    resources.mkdir(parents=True, exist_ok=True)
    for name in ["Sources", "Licenses"]:
        shutil.copytree(runtime / name, resources / name, dirs_exist_ok=True)
    for name in ["sources.json", "build-info.json", "README.md"]:
        shutil.copy2(runtime / name, resources / name)
    recipes = resources / "Build"
    recipes.mkdir(exist_ok=True)
    for name in ["build-ffmpeg-runtime.py", "check-ffmpeg-runtime.py", "package-ffmpeg-runtime.py"]:
        shutil.copy2(root / "scripts" / name, recipes / name)
    print(f"Bundled FFmpeg, licenses, sources, and build recipes in {args.app}", flush=True)


if __name__ == "__main__":
    main()
