#!/usr/bin/env python3
"""Extract a read-only OpenTTD 14.1 coast and water-kind sidecar for terrain preview."""
# SPDX-License-Identifier: GPL-2.0-only
# Field/classifier port from OpenTTD 14.1 src/water_map.h (GetWaterTileType,
# GetWaterClass, IsCoastTile). Copyright OpenTTD contributors.
from hashlib import sha256
from pathlib import Path
import argparse
import json
import lzma
import zlib

from openttd_save_inspect import LIMIT, SaveError
from openttd_save_map import decode_map

NORMAL, COAST, COAST_TREES, LOCK, DEPOT = range(1, 6)


def water_kind(tile_type, m1, m5):
    if tile_type == 4:  # MP_TREES
        return COAST_TREES if (m1 >> 5) & 3 != 3 else 0
    if tile_type != 6:  # MP_WATER
        return 0
    subtype = m5 >> 4
    if subtype == 0:
        return COAST if m5 & 1 else NORMAL
    if subtype == 1:
        return LOCK
    if subtype == 8:
        return DEPOT
    raise SaveError(f"Unknown OpenTTD 14.1 water subtype {subtype}")


def ground_sidecar(blob):
    version, _, w, h, planes, _ = decode_map(blob)
    roof = planes[b"MAPT"]
    owner, water = planes[b"MAPO"], planes[b"MAP5"]
    rows = []
    for off in range(0, w*h, w):
        end = off+w
        rows.append(bytes(water_kind(t >> 4, a, b)
                          for t,a,b in zip(roof[off:end], owner[off:end], water[off:end])).hex())
    return {"schema": "luanttd-openttd-ground/1",
            "save_version": version, "width": w, "height": h,
            "source_sha256": sha256(blob).hexdigest(), "water_rows_hex": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path)
    parser.add_argument("--output", type=Path, help="new sidecar path, never overwrite")
    args = parser.parse_args()
    try:
        with args.save.open("rb") as stream:
            data = ground_sidecar(stream.read(LIMIT+1))
        text = json.dumps(data, sort_keys=True, separators=(",", ":"))+"\n"
        if args.output:
            with args.output.open("x", encoding="utf-8") as out:
                out.write(text)
        else:
            print(text, end="")
    except (SaveError, OSError, lzma.LZMAError, zlib.error) as exc:
        parser.exit(1, f"Ground flags not extracted: {exc}\n")


if __name__ == "__main__":
    main()
