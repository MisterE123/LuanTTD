#!/usr/bin/env python3
"""Compare all RC1 road turnaround movements in both driving sides."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import re
import subprocess
import sys

repo = Path(sys.argv[1]).resolve()
commit = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
assert commit == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837", commit
src = repo / "src"
driver = (src / "roadveh_cmd.cpp").read_text()
enum = (src / "track_type.h").read_text()
table = (src / "table" / "roadveh_movement.h").read_text()
turn = re.search(r"_road_reverse_table\{(.*?)\};", driver, re.S)
names = re.findall(r"Trackdir::RvRev_(\w+)", turn.group(1))
assert names == ["NE", "SE", "SW", "NW"]
rows = [int(re.search(rf"RvRev_{key} = (\d+)", enum).group(1)) for key in names]
expected = []
for side in range(2):
    for approach,td in enumerate(rows):
        found = re.search(rf"_roadveh_drive_data_{td + 16*side}\[\] = \{{(.*?)\}};", table, re.S)
        segment = found.group(1)
        for x,y in re.findall(r"\{(\d+),\s*(\d+)\}", segment):
            expected.append(f"{side} {approach} {td} position {x} {y}")
        end = re.search(r"RDE_TURNED \| to_underlying\(DiagDirection::(\w+)\)", segment)
        expected.append(f"{side} {approach} {td} turned {names.index(end.group(1))} -")
script = '''
local root="mods/luanttd_core/openttd/"
local m=dofile(root.."road_motion.lua")(dofile(root.."road_motion_data.lua"))
for side=0,1 do
  for d=0,3 do
    local td=assert(m.reversing_state(d))
    local frame=0
    while true do
      local k,x,y=m.sample(td,side,frame)
      print(("%d %d %d %s %d %s"):format(side,d,td,k,x,tostring(y or "-")))
      if k~="position" then break end
      frame=frame+1
    end
  end
end
'''
actual = subprocess.check_output(["lua5.1", "-"], input=script, text=True).splitlines()
assert actual == expected, (actual, expected)
print(f"PASS pinned 16.0-RC1: {len(expected)} exact positions and RDE_TURNED flags over all eight directional/side cases")
