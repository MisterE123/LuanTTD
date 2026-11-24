#!/usr/bin/env python3
"""Match the full one-tile Heliport profile to pinned upstream data."""
from argparse import ArgumentParser
from pathlib import Path
import re
import subprocess

p = ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
root = a.source / "src"
movement = (root / "table/airport_movement.h").read_text()
defaults = (root / "table/airport_defaults.h").read_text()
airport = (root / "airport.cpp").read_text()
intro = re.search(r"AS_ND\(heliport,\s*1,\s*1,\s*(\d+), CalendarTime::MAX_YEAR,\s*4,\s*1,\s*(\d+),", defaults)
assert re.search(r"_tile_table_heliport_0\s*=\s*\{\s*\{\{0, 0\}, APT_HELIPORT\},\s*\};", defaults)
delta = int(re.search(r"HELIPORT\(heliport, 1, (\d+)\)", airport)[1])
entries = tuple(map(int, re.search(r"_airport_entries_heliport\[\]\s*=\s*\{([^}]+)\}", movement)[1].split(",")))
flags = {"ExactPosition": 16, "HeliRaise": 64, "HeliLower": 128, "NoSpeedClamp": 1, "SlowTurn": 4}
points = re.search(r"_airport_moving_data_heliport\[9\]\s*=\s*\{(.*?)\n\};", movement, re.S)[1]
rows = re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*\{([^}]*)\},\s*Direction::(N|NE)\s*\}", points)
assert len(rows) == 9
series = [(int(x), int(z), sum(flags[key] for key in re.findall(r"AirportMovingDataFlag::(\w+)", opts)), int(d == "NE")) for x, z, opts, d in rows]
fta = re.search(r"_airport_fta_heliport\[\]\s*=\s*\{(.*?)\n\};", movement, re.S)[1]
states = {"TO_ALL": 0, "HELIPAD1": 8, "HELITAKEOFF": 13, "FLYING": 14, "HELILANDING": 17, "HELIENDLANDING": 18, "TERMGROUP": 255}
blocks = {"{}": 0, "Helipad1": 64, "AirportBusy": 256, "Nothing": 2**30}
links = [(int(i), states[state], blocks[block], int(next_)) for i, state, block, next_ in
         re.findall(r"\{\s*(\d+),\s*(\w+),\s*(?:AirportBlock::)?(\w+|\{\}),\s*(\d+)\s*\}", fta)]
assert len(links) == 14
result = subprocess.run([a.lua, "-"], input="""
local A=dofile("mods/luanttd_core/openttd/airport_heliport.lua")
assert(A.W==1 and A.H==1 and A.num_helipads==1 and A.helicopters and not A.airplanes and not A.hangar)
print(A.intro_year,A.catchment_radius,A.delta_z)
print(A.entries[0],A.entries[1],A.entries[2],A.entries[3])
for i=0,8 do print(A.point(i)) end
for i=0,8 do for _,t in ipairs(A.layout[i]) do print(i,unpack(t)) end end
""", text=True, check=True, capture_output=True)
actual = [tuple(map(int,line.split())) for line in result.stdout.splitlines()]
assert actual == [(int(intro[1]), int(intro[2]), delta), entries, *series, *links]
print("PASS RC1 Heliport: source dimensions, date, catchment, roof offset, all 9 movement points and 14 FTA transitions")
