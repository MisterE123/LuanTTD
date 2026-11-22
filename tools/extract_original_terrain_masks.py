#!/usr/bin/env python3
"""Decode the Original generator's MAPGEN height masks from local OpenGFX 7.1.

Usage: python3 tools/extract_original_terrain_masks.py /path/to/ogfxi_logos.grf LOCAL_OUTPUT.bin
Only accepts the pinned, GPL-2.0 OpenGFX input. Keep its output local. This
tool handles the exact container layout/format of those 37 indexed sprites,
not arbitrary GRF data. No palette remapping or rendered art is included.
"""
from hashlib import sha256
from pathlib import Path
from struct import unpack_from
import argparse

GRF_SHA = "20644db32d97b2e1d7d7d9b73b0484b904a86f9e91752d9fc5f86bebb7706e5a"
# Global SPR_MAPGEN_BEGIN = 4845; the logos range starts at 4793. The
# input data section thus references these as its own real sprite IDs 53..89.
FIRST, COUNT = 52, 37


def u32(data, pos):
    return unpack_from("<I", data, pos)[0]


def decompress(payload, size):
    """Normal 8bpp sprites use the GRF literals/back-reference stream."""
    pos = 0
    result = bytearray()
    while pos < len(payload):
        code = payload[pos]
        pos += 1
        if code < 128:
            count = code or 128
            assert pos + count <= len(payload), "short literal"
            result += payload[pos:pos + count]
            pos += count
        else:
            count = -((code - 256) >> 3)
            distance = (code & 7) * 256 + payload[pos]
            pos += 1
            assert 1 <= distance <= len(result), "bad copy distance"
            for _ in range(count):
                result.append(result[-distance])
        assert len(result) <= size, "sprite exceeded width*height"
    assert len(result) == size, "short sprite"
    return bytes(result)


def extract(data):
    assert sha256(data).hexdigest() == GRF_SHA, "not the pinned OpenGFX 7.1 ogfxi_logos.grf"
    assert data[:10] == b"\x00\x00GRF\x82\r\n\x1a\n" and data[14] == 0
    real_section = u32(data, 10) + 14
    refs = []
    pos = 15
    while (length := u32(data, pos)):
        kind = data[pos + 4]
        refs.append(u32(data, pos + 5) if kind == 0xFD and length == 4 else None)
        pos += 5 + length
    assert pos + 4 == real_section
    selected = refs[FIRST:FIRST + COUNT]
    assert selected == list(range(53, 90))

    pos = real_section
    records = {}
    while (sprite := u32(data, pos)):
        size, kind, zoom, height, width, off_x, off_y = unpack_from("<IBBHHhh", data, pos + 4)
        next_pos = pos + 8 + size
        if sprite in selected:
            assert kind == 4 and zoom == 0 and off_x == off_y == 0 and sprite not in records
            raw = decompress(data[pos + 18:next_pos], width * height)
            assert any(raw) and max(raw) <= 15, "unrecognized MAPGEN pixel indices"
            records[sprite] = bytes((width, height)) + raw
        pos = next_pos
    return b"OTMAPGEN" + b"".join(records[sprite] for sprite in selected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("grf", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = extract(args.grf.read_bytes())
    # Never overwrite an existing local file, especially the source GRF.
    with args.output.open("xb") as out:
        out.write(data)
    print(f"{sha256(data).hexdigest()}  {args.output}")
