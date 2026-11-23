#!/usr/bin/env python3
"""Check the exact OpenTTD 16.0-RC1 layout, industry table and oilrig movements."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
game = Path(__file__).resolve().parents[1]
data = (root / "src/table/build_industry.h").read_text()
moves = (root / "src/table/airport_movement.h").read_text()
defaults = (root / "src/table/airport_defaults.h").read_text()
types = (root / "src/industry_type.h").read_text()
airport = (root / "src/airport.cpp").read_text()
air_header = (root / "src/airport.h").read_text()

def cut(text, marker):
    return text.split(marker, 1)[1].split("};", 1)[0]

def tokens(*fields):
    return list(map(str, fields))

expected = [[x,z,gfx] for x,z,gfx in re.findall(
    r"\{\{(-?\d+), (-?\d+)\}, (\w+)\}", cut(data, "_tile_table_oil_rig_0 {"))]
assert len(expected) == 58
raw_meta = re.search(
    r"MI\(_tile_table_oil_rig,\s*\{\},\s*"
    r"(\d+),\s*(0x[0-9A-F]+),\s*(\d+, \d+, \d+, \d+),\s*(\d+, \d+, \d+, \d+),\s*(\d+),\s*"
    r"IT_OIL_REFINERY,\s*IT_INVALID,\s*IT_INVALID,\s*IndustryCheck::OilRig,\s*"
    r"CT_OIL,\s*(\d+),\s*CT_PASSENGERS,\s*(\d+),\s*(\d+),", data)
assert raw_meta
cost, procurement, appearance, generation, color, oil, passenger, minimum = raw_meta.groups()
assert re.search(r"GFX_OILRIG_1 = 24;", types)
expected.append(tokens("META", 5, cost, int(procurement, 16), color, minimum, oil,
                       passenger, appearance.replace(" ", ""), generation.replace(" ", "")))
flags = {
    "AirportMovingDataFlag::ExactPosition": "exact_position",
    "AirportMovingDataFlag::HeliRaise": "heli_raise",
    "AirportMovingDataFlag::HeliLower": "heli_lower",
    "AirportMovingDataFlag::NoSpeedClamp, AirportMovingDataFlag::SlowTurn": "unclamped_slow_turn",
    "": "ground",
}
pattern = r"\{\s*(-?\d+),\s*(-?\d+),\s*\{([^}]*)\},\s*Direction::(N|NE)\s*\}"
for n, (x,z,kind,bearing) in enumerate(re.findall(pattern, cut(moves, "_airport_moving_data_oilrig[9] = {"))):
    expected.append(tokens("MOVE", n, x, z, flags[kind], bearing))
assert len(expected) == 68
assert "#define _airport_entries_oilrig _airport_entries_heliport" in moves
assert "#define _airport_fta_oilrig _airport_fta_heliport" in moves
assert re.search(r"_airportfta_oilrig, \{\}, \{\}, 1, 1, 0, 4,", defaults)
delta = re.search(r"HELIPORT\(oilrig, 1, (\d+)\)", airport)[1]
entry = re.search(r"_airport_entries_heliport\[\] = \{ (.*?) \};", moves)[1].split(", ")
expected.append(tokens("HELIPORT", delta, 4, 1, 1, *entry))
blocks = {k: 1 << int(re.search(rf"\b{k}\s*=\s*(\d+),", air_header)[1])
    for k in ("Helipad1", "AirportBusy", "Nothing")}
heads = {"TO_ALL":0,"HELIPAD1":8,"HELITAKEOFF":13,"FLYING":14,"HELILANDING":17,
         "HELIENDLANDING":18,"TERMGROUP":255}
fta = cut(moves, "_airport_fta_heliport[] = {").split("{ MAX_ELEMENTS",1)[0]
for i,head,block,j in re.findall(r"\{ (\d+), (\w+), (AirportBlock::\w+|\{\}), (\d+) \}", fta):
    expected.append(tokens("FTA", i, heads[head], blocks.get(block.split("::")[-1],0), j))
assert len(expected) == 83
out = subprocess.check_output([lua, "tests/oil_rig_rules.lua", "dump"], cwd=game, text=True)
actual = [line.split() for line in out.splitlines()]
assert len(actual) == len(expected)
for model, upstream in zip(actual, expected):
    assert model == upstream, (model, upstream)
print("PASS exact RC1 Oil Rig #5 table: 6 occupied cells, 52 ordered water checks, 9 helicopter movement entries, exact block graph and heli deck datum")
