#!/usr/bin/env python3
"""Extract an OpenTTD 14.1 map snapshot, not a playable world.

A separate JSON file contains the north-corner lattice and road topology.
The original .sav is only read. Existing files are never overwritten.
"""
# SPDX-License-Identifier: GPL-2.0-only
# Save fields translated from OpenTTD 14.1 src/saveload/map_sl.cpp,
# src/tile_{type,map}.h, src/{road,station}_map.h and src/road_type.h.
# Copyright OpenTTD contributors; see COPYING.OpenTTD.md.
from collections import Counter
from hashlib import sha256
from pathlib import Path
import argparse
import json
import lzma
import struct
import zlib

from openttd_save_inspect import LIMIT, SaveError, chunks, unpack_payload

SCHEMA = "luanttd-openttd-map/1"
MAPS_HEADER = b"\x06\x05dim_x\x06\x05dim_y\x00"
MAP_PLANES = (b"MAPT", b"MAPH", b"MAPO", b"MAP2", b"M3LO", b"M3HI",
              b"MAP5", b"MAPE", b"MAP7", b"MAP8")
MAP_TYPE = ("clear", "rail", "road", "house", "trees", "station",
            "water", "void", "industry", "tunnelbridge", "object")
STATION_TYPE = ("rail", "airport", "truck", "bus", "oilrig", "dock",
                "buoy", "waypoint")
# North-west, south-west, south-east and north-east stock directions.
# In LuanTTD, these are -Z, +X, +Z and -X in the same bit order.
AXIS_BITS = (0xA, 0x5)
INVALID_ROAD_TYPE = 63
MAX_ROAD_RECORDS = 250_000  # guard Python/JSON memory on dense huge maps


def decode_map(blob):
    if len(blob) > LIMIT:
        raise SaveError("Input exceeds the snapshot budget")
    version, compression, body = unpack_payload(blob)
    dims, planes, index = None, {}, {}
    for tag, kind, schema, data in chunks(body):
        if tag == b"MAPS":
            count, row = data if kind == 3 else (0, None)
            if schema != MAPS_HEADER or count != 1 or len(row) != 8:
                raise SaveError("Unsupported MAPS schema")
            dims = struct.unpack(">II", row)
            if any(n < 64 or n > 4096 or n & (n - 1) for n in dims):
                raise SaveError("Invalid or unsupported map dimensions")
        if tag in MAP_PLANES:
            if kind != 0:
                raise SaveError(f"Incorrect map plane encoding: {tag!r}")
            planes[tag] = data
        index[tag.decode()] = len(data) if kind == 0 else data[0]
    if dims is None:
        raise SaveError("Missing MAPS")
    w, h = dims
    for tag in MAP_PLANES:
        unit = 2 if tag in (b"MAP2", b"MAP8") else 1
        if len(planes.get(tag, ())) != w * h * unit:
            raise SaveError(f"Missing or inconsistent map plane: {tag.decode()}")
    return version, compression, w, h, planes, index


def decode_road(tile, m1, m2, m3, m4, m5, m6, m7, m8):
    # TileId, StationId, DepotId and TownId are stored values, not SlRef.
    # A pool id of 0 is legitimate; never subtract one from these fields.
    if tile == 2:
        subtype = m5 >> 6
        if subtype == 3:
            raise SaveError("Invalid OpenTTD road tile subtype")
        kind = ("road", "crossing", "depot")[subtype]
        station = None
    elif tile == 5:
        station = STATION_TYPE[(m6 >> 3) & 7]
        if station not in ("truck", "bus"):
            return None
        kind = "drive_stop" if m5 >= 4 else "bay_stop"
        if m5 > 5:
            raise SaveError("Invalid stock road stop graphics direction")
    else:
        return None

    road_type, tram_type = m4 & 63, (m8 >> 6) & 63
    road_owner = (m1 if kind == "road" else m7) & 31
    tram_owner = m3 >> 4
    if tram_owner == 15:  # OWNER_TOWN remapped to OWNER_NONE on tram tiles.
        tram_owner = 16
    extra = {}
    unsupported = []
    if kind == "road":
        road_bits, tram_bits = m5 & 15, m3 & 15
        extra.update(disallowed=(m5 >> 4) & 3, town_or_meta_id=m2)
        if extra["disallowed"]:
            unsupported.append("one_way_road")
    elif kind == "crossing":
        axis = m5 & 1
        road_bits = tram_bits = AXIS_BITS[axis]
        extra.update(axis=axis, rail_axis=1-axis, rail_owner=m1 & 31,
                     reserved=bool(m5 & 16), barred=bool(m5 & 32),
                     town_or_meta_id=m2)
        unsupported.append("rail_crossing")
    elif kind == "drive_stop":
        extra.update(axis=m5-4)
        road_bits = tram_bits = AXIS_BITS[extra["axis"]]
    else:  # road depot or bay stop, each has one open approach.
        extra.update(direction=m5 & 3)
        road_bits = tram_bits = 1 << (3-extra["direction"])
        if kind == "depot":
            extra.update(depot_id=m2, depot_owner=m1 & 31)

    if station is not None:
        extra.update(station_id=m2, station_owner=m1 & 31, stop_type=station,
                     custom_stop_spec=m8 & 63)
        if extra["custom_stop_spec"]:
            unsupported.append("custom_stop")
    if road_type not in (0, INVALID_ROAD_TYPE):
        unsupported.append("nonstandard_roadtype")
    if tram_type != INVALID_ROAD_TYPE:
        unsupported.append("tram")
    rec = {"kind": kind, "unsupported_for_initial_bus_world": unsupported, **extra}
    if road_type != INVALID_ROAD_TYPE:
        rec.update(road_bits=road_bits, road_type=road_type, road_owner=road_owner)
    if tram_type != INVALID_ROAD_TYPE:
        rec.update(tram_bits=tram_bits, tram_type=tram_type, tram_owner=tram_owner)
    return rec


def snapshot(blob):
    version, compression, w, h, p, index = decode_map(blob)
    types = p[b"MAPT"]
    heights = p[b"MAPH"]
    # The far row/column are excluded from playable space, not from the
    # source corner lattice. Retain their actual MAPH values; in edge maps,
    # the first row/column can be void too, but still have their own heights.
    if (any(t >> 4 != 7 for t in types[(h-1)*w:])
            or any(types[z*w + w-1] >> 4 != 7 for z in range(h))):
        raise SaveError("Expected OpenTTD void tiles at far map edges")
    near_border = [types[x] >> 4 == 7 for x in range(w-1)]
    near_border.extend(types[z*w] >> 4 == 7 for z in range(1, h-1))
    if any(near_border) and not all(near_border):
        raise SaveError("Inconsistent OpenTTD near-edge void border")
    freeform_edges = all(near_border)
    road_tiles, unsupported, tile_counts = {}, Counter(), Counter()
    for n, code in enumerate(types):
        tile = code >> 4
        if tile >= len(MAP_TYPE):
            raise SaveError(f"Unknown stock tile class {tile} at tile {n}")
        tile_counts[MAP_TYPE[tile]] += 1
        if tile not in (2, 5):
            if tile in (1, 3, 8, 9, 10):
                unsupported["tile:" + MAP_TYPE[tile]] += 1
            continue
        rec = decode_road(tile, p[b"MAPO"][n],
                          struct.unpack_from(">H", p[b"MAP2"], n*2)[0],
                          p[b"M3LO"][n], p[b"M3HI"][n], p[b"MAP5"][n],
                          p[b"MAPE"][n], p[b"MAP7"][n],
                          struct.unpack_from(">H", p[b"MAP8"], n*2)[0])
        if rec is None:
            unsupported["station:" + STATION_TYPE[(p[b"MAPE"][n] >> 3) & 7]] += 1
        else:
            unsupported.update(rec["unsupported_for_initial_bus_world"])
            if len(road_tiles) >= MAX_ROAD_RECORDS:
                raise SaveError("Road-record count exceeds the current snapshot budget")
            road_tiles[str(n)] = rec
    if index.get("NGRF", 0):
        unsupported["newgrf"] = index["NGRF"]

    return {
        "schema": SCHEMA, "can_resume_in_luanti": False,
        "reason": "Map snapshot only. Stations, companies, vehicles, orders and cargo are not restored.",
        "source": {"save_version": version, "compression": compression, "sha256": sha256(blob).hexdigest()},
        "width": w, "height": h, "tile_columns": w-1, "tile_rows": h-1,
        "freeform_edges": freeform_edges,
        "coordinate_mapping": "source tile index=z*width+x; Luanti tile=x+1,z+1; far void border is corner-only",
        "corner_rows_hex": [heights[z*w:(z+1)*w].hex() for z in range(h)],
        "tile_type_rows_hex": [bytes(t >> 4 for t in types[z*w:(z+1)*w]).hex() for z in range(h)],
        "road_tiles": road_tiles, "tile_counts": dict(tile_counts),
        "unsupported_counts": dict(unsupported),
        "undecoded_pool_counts": {t:index[t] for t in
                                  ("CITY","INDY","PLYR","STNN","ROAD","DEPT","VEHS","ORDR","CAPA")
                                  if t in index},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path)
    parser.add_argument("--output", type=Path, help="create a new snapshot file; never overwrite")
    args = parser.parse_args()
    try:
        with args.save.open("rb") as stream:
            blob = stream.read(LIMIT+1)
        result = snapshot(blob)
        if args.output:
            with args.output.open("x", encoding="utf-8") as out:
                json.dump(result, out, sort_keys=True, separators=(",", ":"))
                print(file=out)
        else:
            print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    except (SaveError, OSError, lzma.LZMAError, zlib.error) as exc:
        parser.exit(1, f"Map not extracted: {exc}\n")


if __name__ == "__main__":
    main()
