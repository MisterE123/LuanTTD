#!/usr/bin/env python3
"""Generate the two-swatch selector colors using the standard library."""
from pathlib import Path
import struct
import zlib

out = Path(__file__).resolve().parents[1] / "mods" / "bayline" / "textures"
dark = bytes.fromhex("172733")
colors = {"inspect": "e2f3f8", "valid": "baf39b", "invalid": "ff947d", "anchor": "ffd579"}

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

for state, color in colors.items():
    row = b"\x00" + dark*8 + bytes.fromhex(color)*8
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 4, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(row*4))
    png += chunk(b"IEND", b"")
    (out / f"bl_selector_{state}.png").write_bytes(png)
