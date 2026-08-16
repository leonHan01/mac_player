#!/usr/bin/env python3
"""Create an ICNS file from a standard macOS PNG iconset.

This is a small fallback for environments where `iconutil` rejects otherwise
valid iconsets. Modern ICNS containers store PNG payloads directly.
"""

from pathlib import Path
from struct import pack
from sys import argv, exit


ICON_ENTRIES = (
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
)


def main() -> int:
    if len(argv) != 3:
        print("Usage: make-icns.py <iconset-dir> <output.icns>")
        return 2

    iconset = Path(argv[1])
    chunks = []
    for chunk_type, filename in ICON_ENTRIES:
        image = (iconset / filename).read_bytes()
        if not image.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"{filename} is not a PNG image")
        chunks.append(chunk_type.encode("ascii") + pack(">I", len(image) + 8) + image)

    payload = b"".join(chunks)
    Path(argv[2]).write_bytes(b"icns" + pack(">I", len(payload) + 8) + payload)
    return 0


if __name__ == "__main__":
    exit(main())
