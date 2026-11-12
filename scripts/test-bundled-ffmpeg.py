#!/usr/bin/env python3
"""Export synthetic clips from a relocated app with no package-manager PATH; no player UI."""
import argparse
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile


def run(command, env=None, timeout=180):
    result = subprocess.run(list(map(str, command)), text=True, capture_output=True, timeout=timeout, env=env)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=root / "build/MacVideoPlayer.app")
    args = parser.parse_args()
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", args.app])
    env = {key: value for key, value in os.environ.items() if not key.startswith("DYLD_")}
    env["PATH"] = "/usr/bin:/bin"
    with tempfile.TemporaryDirectory(prefix="myplayer-bundled-export-") as temporary:
        scratch = Path(temporary)
        app = scratch / "another computer's folder" / "Renamed Player.app"
        shutil.copytree(args.app, app, symlinks=True)
        ffmpeg = app / "Contents/MacOS/ffmpeg"
        print(run([ffmpeg, "-hide_banner", "-version"], env).stdout.splitlines()[0], flush=True)
        video = scratch / "frames.yuv"
        audio = scratch / "audio.pcm"
        video.write_bytes(b"".join(bytes([16 + index * 8]) * (64 * 48) + bytes([128]) * (64 * 48 // 2) for index in range(20)))
        audio.write_bytes(b"".join(struct.pack("<h", round(3000 * math.sin(index * 440 * 2 * math.pi / 48000))) for index in range(96000)))
        run([ffmpeg, "-v", "error", "-f", "rawvideo", "-pixel_format", "yuv420p", "-video_size", "64x48", "-framerate", "10",
             "-i", video, "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", audio, "-t", "2",
             "-c:v", "libx264", "-threads", "2", "-c:a", "aac", scratch / "source.mkv"], env)
        run([ffmpeg, "-v", "error", "-i", scratch / "source.mkv", "-c", "copy", scratch / "source.mp4"], env)
        run([ffmpeg, "-v", "error", "-i", scratch / "source.mp4", "-c:v", "copy", "-an", scratch / "silent.mp4"], env)

        # Replace only the disposable copy's main executable with a CLI probe
        # using the production exporter. The actual player is never launched.
        probe = scratch / "ExportProbe.swift"
        probe.write_text('''import Foundation
@main @MainActor struct ExportProbe {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let expected = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("ffmpeg")
        let located = try VideoClipExporter.findFFmpeg()
        precondition(located?.standardizedFileURL == expected.standardizedFileURL, "Must use relocated bundled FFmpeg")
        for name in ["source.mp4", "source.mkv", "silent.mp4"] {
            var selection = try ClipTrimSelection(source: directory.appendingPathComponent(name), duration: 2)
            selection.drag(.start, to: 0.25)
            selection.drag(.end, to: 1.25)
            try await VideoClipExporter().export(source: selection.source, range: selection.exportRange(),
                                                destination: directory.appendingPathComponent("clip-\\(name).mp4"))
        }
        print("PASS: production exporter uses relocated bundled FFmpeg with no Homebrew PATH")
    }
}
''')
        executable = app / "Contents/MacOS/MacVideoPlayer"
        files = [root / "Sources/MacVideoPlayer" / name for name in ["Models.swift", "AppLanguage.swift", "VideoClipExporter.swift", "ClipTrimSelection.swift"]]
        run(["/usr/bin/swiftc", "-swift-version", "6", "-module-cache-path", root / ".build/module-cache", "-parse-as-library",
             *files, probe, "-o", executable])
        run(["/usr/bin/codesign", "--force", "--sign", "-", executable])
        print(run([executable, scratch], env, timeout=60).stdout, end="", flush=True)
        for source in ["source.mp4", "source.mkv", "silent.mp4"]:
            output = scratch / f"clip-{source}.mp4"
            decoded = run([ffmpeg, "-hide_banner", "-i", output, "-map", "0:v:0", "-map", "0:a:0?", "-f", "null", "-"], env)
            info = decoded.stderr
            duration = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", info)
            assert duration is not None, info
            seconds = int(duration[1]) * 3600 + int(duration[2]) * 60 + float(duration[3])
            assert abs(seconds - 1) <= 0.11, info
            assert "Video: h264" in info, info
            assert ("Audio: aac" in info) == (source != "silent.mp4"), info
            pixel = subprocess.run([str(ffmpeg), "-v", "error", "-i", str(output), "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"],
                                   capture_output=True, check=True, timeout=30, env=env).stdout
            assert pixel and pixel[0] >= 10, "Clip must begin at the selected position rather than the original first frame"
            print(f"PASS: bundled {source} → MP4, {seconds:.2f}s, selected first frame, correct audio presence", flush=True)


if __name__ == "__main__":
    main()
