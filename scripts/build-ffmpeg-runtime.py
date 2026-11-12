#!/usr/bin/env python3
"""Build a static FFmpeg + x264 for the current Mac without installing system files."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


def run(command, cwd=None, env=None):
    print("RUN:", " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--resume", action="store_true", help="Reuse the previous build's source and object files")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    root = Path(__file__).resolve().parent.parent
    vendor = root / "Vendor/FFmpeg"
    manifest = json.loads((vendor / "sources.json").read_text())
    architecture = platform.machine()
    if architecture not in ("arm64", "x86_64"):
        raise RuntimeError(f"Unsupported build architecture: {architecture}")
    target = manifest["deploymentTarget"]
    work = root / ".build" / f"ffmpeg-runtime-{architecture}"
    if work.exists() and not args.resume:
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    prefix = work / "prefix"
    env = dict(os.environ, PATH=f"{prefix / 'bin'}:/usr/bin:/bin:/usr/sbin:/sbin",
               MACOSX_DEPLOYMENT_TARGET=target,
               CC="/usr/bin/clang", CFLAGS=f"-O2 -mmacosx-version-min={target}",
               LDFLAGS=f"-mmacosx-version-min={target}",
               PKG_CONFIG_LIBDIR=str(prefix / "lib/pkgconfig"), PKG_CONFIG_PATH="")
    for key in list(env):
        if key.startswith("DYLD_") or key in {"CPPFLAGS", "CXXFLAGS", "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH",
                                               "OBJC_INCLUDE_PATH", "LIBRARY_PATH", "PKG_CONFIG_SYSROOT_DIR",
                                               "PKG_CONFIG_SYSTEM_INCLUDE_PATH", "PKG_CONFIG_SYSTEM_LIBRARY_PATH"}:
            env.pop(key)
    source_info = manifest["sources"]
    for name, record in source_info.items():
        archive = vendor / "Sources" / record["archive"]
        if hashlib.sha256(archive.read_bytes()).hexdigest() != record["sha256"]:
            raise RuntimeError(f"Source checksum mismatch: {archive}")
        directory = work / name
        if not directory.exists():
            directory.mkdir()
            run(["/usr/bin/tar", "-xf", archive, "--strip-components", "1", "-C", directory])

    # GitHub release archives have no VERSION file. Prevent FFmpeg's version
    # script from accidentally reporting the containing player's Git revision.
    (work / "ffmpeg/VERSION").write_text(source_info["ffmpeg"]["version"] + "\n")

    jobs = f"-j{args.jobs}"
    package_tool = prefix / "bin/pkgconf"
    if not args.resume or not package_tool.exists():
        run(["./configure", f"--prefix={prefix}", "--disable-shared", "--enable-static"], work / "pkgconf", env)
        run(["/usr/bin/make", jobs], work / "pkgconf", env)
        run(["/usr/bin/make", "install"], work / "pkgconf", env)
    x264_flags = [f"--prefix={prefix}", "--enable-static", "--enable-pic", "--disable-cli",
                  "--disable-opencl", "--disable-swscale", "--disable-lavf", "--disable-ffms",
                  "--disable-gpac", "--disable-lsmash", "--disable-avs", "--bit-depth=8", "--chroma-format=420"]
    if architecture == "x86_64" and not shutil.which("nasm", path=env["PATH"]):
        x264_flags.append("--disable-asm")
    if not args.resume or not (prefix / "lib/libx264.a").exists():
        run(["./configure", *x264_flags], work / "x264", env)
        run(["/usr/bin/make", jobs], work / "x264", env)
        run(["/usr/bin/make", "install-lib-static"], work / "x264", env)
    ffmpeg_flags = ["--prefix=/usr/local", "--extra-version=MacVideoPlayer", "--cc=/usr/bin/clang",
                    f"--pkg-config={package_tool}", "--pkg-config-flags=--static --keep-system-cflags --keep-system-libs", "--disable-autodetect",
                    "--disable-debug", "--disable-doc", "--disable-network", "--disable-shared", "--enable-static",
                    "--disable-ffplay", "--disable-ffprobe", "--disable-indevs", "--disable-outdevs",
                    "--enable-gpl", "--enable-libx264", "--enable-zlib", "--enable-bzlib", "--enable-iconv",
                    "--extra-libs=-liconv"]
    if architecture == "x86_64" and not shutil.which("nasm", path=env["PATH"]):
        ffmpeg_flags.append("--disable-x86asm")
    config_record = work / "ffmpeg/runtime-config.json"
    configuration = {"flags": ffmpeg_flags, "deploymentTarget": target}
    if not args.resume or not config_record.exists() or json.loads(config_record.read_text()) != configuration:
        run(["./configure", *ffmpeg_flags], work / "ffmpeg", env)
        config_record.write_text(json.dumps(configuration, indent=2) + "\n")
    run(["/bin/sh", "ffbuild/version.sh", ".", "libavutil/ffversion.h", "MacVideoPlayer"], work / "ffmpeg", env)
    run(["/usr/bin/make", jobs, "ffmpeg"], work / "ffmpeg", env)

    binary = vendor / "bin/ffmpeg"
    binary.parent.mkdir(exist_ok=True)
    shutil.copy2(work / "ffmpeg/ffmpeg", binary)
    binary.chmod(0o755)
    run(["/usr/bin/codesign", "--force", "--sign", "-", binary])
    specification = importlib.util.spec_from_file_location("ffmpeg_runtime_check", root / "scripts/check-ffmpeg-runtime.py")
    checker = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(checker)
    checker.verify(binary, [architecture], target)
    licenses = vendor / "Licenses"
    licenses.mkdir(exist_ok=True)
    for source, name in [("ffmpeg/COPYING.GPLv2", "FFmpeg-GPL-2.0.txt"),
                         ("ffmpeg/COPYING.GPLv3", "FFmpeg-GPL-3.0.txt"),
                         ("ffmpeg/LICENSE.md", "FFmpeg-LICENSE.md"), ("x264/COPYING", "x264-GPL-2.0.txt"),
                         ("pkgconf/COPYING", "pkgconf-ISC.txt")]:
        shutil.copy2(work / source, licenses / name)
    info = {"architectures": [architecture], "deploymentTarget": target, "sources": source_info,
            "ffmpegConfigure": ffmpeg_flags, "x264Configure": x264_flags,
            "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    (vendor / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
    print(f"Built {binary} ({binary.stat().st_size / 1024 / 1024:.1f} MiB)", flush=True)


if __name__ == "__main__":
    main()
