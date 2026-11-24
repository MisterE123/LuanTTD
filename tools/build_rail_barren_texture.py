#!/usr/bin/env python3
"""Generate the original muted dirt tile beneath newly laid stock rail."""
import argparse
from collections import Counter
from pathlib import Path
from random import Random
import struct
import zlib

root = Path(__file__).resolve().parents[1]
texture = root / "mods/luanttd_core/textures/bl_rail_barren.png"
size = 32


def png():
    rng = Random(16021)
    field = [[rng.randrange(-11, 12) for _ in range(size)] for _ in range(size)]
    palette = [(151, 126, 91), (136, 109, 79), (161, 134, 97)]
    counts = Counter()
    rows = []
    for z in range(size):
        row = bytearray([0])
        for x in range(size):
            local = (field[z][x] * 4 + field[z][(x-1)%size] + field[(z-1)%size][x]) // 6
            p = palette[1 if field[z][x] < -9 else 2 if field[z][x] > 8 else 0]
            shade = tuple(n + local for n in p)
            row.extend(shade)
            counts[shade] += 1
        rows.append(bytes(row))
    assert len(counts) > 24

    def chunk(name, content):
        return struct.pack(">I", len(content)) + name + content + struct.pack(">I", zlib.crc32(name + content))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">2I5B", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
            + chunk(b"IEND", b""))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    if parser.parse_args().check:
        assert texture.read_bytes() == png()
    else:
        texture.write_bytes(png())
