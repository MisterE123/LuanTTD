#!/usr/bin/env python3
"""Generate the native Helidepot and Helistation data from OpenTTD 16.0-RC1."""
import argparse
from hashlib import sha1
from pathlib import Path
import re
from build_city_airport_tables import read

KINDS = ("helidepot", "helistation")
DIRS = dict(zip(("N", "NE", "E", "SE", "S", "SW", "W", "NW"), range(8)))
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "mods/luanttd_core/openttd/airport_rotary_ground_profiles.lua"


def generate(source):
    movement = read(source, "airport_movement.h")
    defaults = read(source, "airport_defaults.h")
    head = read(source.parent, "airport.h")
    spec = (source.parent / "airport.cpp").read_bytes()
    assert sha1(spec).hexdigest() == "d8e7b8ddac74dba106ae99ba805404a793bd057d"
    spec = spec.decode()

    def enum(label):
        return re.search(label + r"[^{}]*{([^}]+)}", head)[1]

    flag_values = {n.strip(): 1 << i for i, n in enumerate(enum("enum class AirportMovingDataFlag").split(",")) if n.strip()}
    flags = {"NOSPDCLAMP": "NoSpeedClamp", "TAKEOFF": "Takeoff", "SLOWTURN": "SlowTurn",
             "LAND": "Land", "EXACTPOS": "ExactPosition", "BRAKE": "Brake",
             "HELI_RAISE": "HeliRaise", "HELI_LOWER": "HeliLower", "HOLD": "Hold"}
    block_values = {n: 1 << int(i) for n, i in re.findall(r"(\w+)\s*=\s*(\d+)", enum("enum class AirportBlock"))}
    states = {n: int(i) for n, i in re.findall(r"(\w+)\s*=\s*(\d+)", enum("enum AirportMovementStates"))}
    states["ALL"] = states.pop("TO_ALL")
    states.pop("MAX_HEADINGS")

    def table(source_text, label, suffix=r"\[\d*\]"):
        return re.search(r"\b" + label + suffix + r"\s*=\s*\{(.*?)\};", source_text, re.S)[1]

    def array(xs):
        return "{" + ",".join(map(str, xs)) + "}"

    def mapping(xs):
        return "{" + ",".join(f"{k}={v}" for k, v in xs.items()) + "}"

    text = [
        "-- SPDX-License-Identifier: GPL-2.0-only",
        "-- OpenTTD contributors. Generated from OpenTTD 16.0-RC1 airport tables.",
        'local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"',
        'local FTA=dofile(mod.."/openttd/airport_fta.lua")',
        "local P={}",
        f"local S={mapping(states)}",
        f"local F={mapping({k:flag_values[v] for k,v in flags.items()})}",
    ]
    for kind in KINDS:
        w, h, intro, radius, noise = map(int, re.search(
            r"\bAS\(" + kind + r",\s*(\d+),\s*(\d+),\s*(\d+),\s*CalendarTime::MAX_YEAR,\s*(\d+),\s*(\d+),", defaults).groups())
        pads, zoff = map(int, re.search(r"\bHELIPORT\(" + kind + r",\s*(\d+),\s*(\d+)\)", spec).groups())
        waypoints = []
        for x, z, mask, d in re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*\{([^}]*)\},\s*Direction::(\w+)\s*\}",
                                        table(movement, "_airport_moving_data_" + kind)):
            bits = sum(flag_values[n] for n in re.findall(r"AirportMovingDataFlag::(\w+)", mask))
            waypoints.append((int(x), int(z), bits, DIRS[d]))
        layout, used = {}, {"Nothing"}
        for point, event, block, target in re.findall(r"\{\s*(\d+),\s*(\w+),\s*(\{[^}]*\}|AirportBlock::\w+),\s*(\d+)\s*\}",
                                                        table(movement, "_airport_fta_" + kind)):
            names = re.findall(r"AirportBlock::(\w+)", block)
            used.update(names)
            layout.setdefault(int(point), []).append((states["ALL" if event == "TO_ALL" else event],
                                                      sum(block_values[n] for n in names), int(target)))
        assert set(layout) == set(range(len(waypoints)))
        assert all(0 <= target < len(waypoints) for links in layout.values() for _, _, target in links)
        entries = [int(n) for n in re.findall(r"\d+", table(movement, "_airport_entries_" + kind))]
        assert len(entries) == 4 and all(i in layout for i in entries)
        x, z, direction, no = re.search(r"\{\s*\{(\d+),\s*(\d+)\},\s*Direction::(\w+),\s*(\d+)\s*\}",
                                        table(movement, "_airport_depots_" + kind)).groups()
        tiles = sorted((int(tx), int(tz), tile) for tx, tz, tile in re.findall(r"\{\{(\d+),\s*(\d+)\},\s*(APT_\w+)\}",
                       table(defaults, "_tile_table_" + kind + "_0", "")))
        assert {(tx, tz) for tx, tz, _ in tiles} == {(dx, dz) for dx in range(w) for dz in range(h)}
        terminal_bits = [block_values[f"Helipad{i}"] for i in range(1, pads+1)]
        terminal_states = [states[f"HELIPAD{i}"] for i in range(1, pads+1)]
        used_values = sorted({block_values[k] for k in used} | set(terminal_bits))
        text += [
            f"P.{kind}=FTA({{airport_type=\"{kind}\",W={w},H={h},TILE=16,intro_year={intro},catchment_radius={radius},noise={noise},",
            f"  helicopters=true,airplanes=false,num_helipads={pads},delta_z={zoff},state=S,flag=F,block={{NOTHING={block_values['Nothing']}}},",
            f"  terminal_bits={array(terminal_bits)},terminal_states={array(terminal_states)},block_bits={array(used_values)},",
            f"  hangar={{x={x},z={z},dir={DIRS[direction]},id={no}}},entries={{[0]={','.join(map(str,entries))}}},",
            "  tile_map={" + ",".join(f'{{{tx},{tz},"{tile}"}}' for tx,tz,tile in tiles) + "},",
            "  points={",
        ]
        text += ["    " + ("[0]=" if i == 0 else "") + array(v) + "," for i, v in enumerate(waypoints)]
        text += ["  },layout={"]
        text += ["    " + ("[0]=" if i == 0 else "") + array(array(r) for r in row) + "," for i, row in sorted(layout.items())]
        text += ["  },", "})"]
    return "\n".join(text + ["return P", ""])


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path, help="Pinned OpenTTD src/table directory")
    p.add_argument("--write", action="store_true")
    a = p.parse_args()
    generated = generate(a.source)
    if a.write:
        OUT.write_text(generated)
    else:
        assert OUT.read_text() == generated
        print("PASS exact RC1 Helidepot and Helistation layout, hangar, every waypoint and FTA transition")
