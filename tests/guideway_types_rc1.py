#!/usr/bin/env python3
"""Differential source-table check of native Maglev and Monorail rules."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import re
import subprocess
import sys

repo = Path(sys.argv[1]).resolve()
commit = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
assert commit == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837", commit
source = (repo / "src/table/railtypes.h").read_text()
types = {"RAIL": 1, "ELECTRIC": 2, "MONO": 4, "MAGLEV": 8}
names = ("compatible", "powered", "bridge", "fallback", "curves", "cost", "maintenance",
         "acceleration", "max_speed", "sort", "introduces")
rows = {}
for gauge, title, acceleration in ((2, "Monorail", 1), (3, "Maglev", 2)):
    part = source.split(f"/** {title} */", 1)[1]
    def field(name):
        m = re.search(r"/\* " + re.escape(name) + r" \*/\s*([^,\n]+),", part)
        assert m, name
        return m.group(1).strip()
    def mask(name):
        return sum(types[k] for k in re.findall(r"RAILTYPE_(\w+)", field(name)))
    assert field("acceleration type") == "VehicleAccelerationModel::" + title
    assert field("introduction date") == "CalendarTime::INVALID_DATE"
    assert field("flags") == "{}"
    m = re.fullmatch(r"(\d+) << (\d+) \| (\d+)", field("sort order"))
    a,b,c = map(int,m.groups())
    rows[gauge] = (
        mask("Compatible Railtypes"),mask("Powered railtypes"),int(field("bridge offset")),
        int(field("fallback_railtype")),int(field("curve speed advantage (multiplier)")),
        int(field("cost multiplier")),int(field("maintenance cost multiplier")),
        acceleration,int(field("max speed")),(a<<b)|c,mask("introduction rail types"),
    )
script = '''
local r=dofile("mods/luanttd_core/openttd/rail_types.lua")
for i=2,3 do
  local q=r.entry(i)
  assert(not q.no_crossings)
  io.write(i)
  for _,k in ipairs({%s}) do io.write(" ", tostring(q[k])) end
  io.write("\\n")
end
''' % ",".join('"' + n + '"' for n in names)
actual = subprocess.check_output(["lua5.1", "-"], input=script, text=True).splitlines()
assert [tuple(map(int,row.split())) for row in actual] == [(i,*rows[i]) for i in (2,3)], actual
print("GUIDEWAY_TYPES_RC1_PASS matching masks, costs, speed, curve/acceleration model and static introduction for both stock gauges")
