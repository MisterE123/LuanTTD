#!/usr/bin/env python3
"""Reference check for the actual Temperate monorail and maglev stock tables."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import re
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1]).read_text()
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
ids=set([54,55,84,85,86,87]+list(range(57,68))+list(range(89,100)))
labels={"CT_NONE":"-","CT_PASSENGERS":"passenger","CT_MAIL":"mail","CT_COAL":"coal","CT_OIL":"oil",
  "CT_LIVESTOCK":"livestock","CT_GOODS":"goods","MCT_GRAIN_WHEAT_MAIZE":"grain","CT_WOOD":"wood",
  "CT_IRON_ORE":"iron_ore","CT_STEEL":"steel","MCT_VALUABLES_GOLD_DIAMONDS":"valuables"}
dates={}
for match in re.finditer(r"M([TW])\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\w+)\s*,\s*LandscapeTypes\(\{([^}]*)\}\)\),\s*//\s*(\d+) (.*)",src):
    kind,intro,decay,life,modellife,cargo,climate,id,name=match.groups()
    if int(id) in ids:
        flags=sum(1<<i for i,t in enumerate("TASY") if t in climate)
        dates[int(id)]=[intro,decay,life,modellife,labels[cargo],str(flags),name.replace(" (Electric)","")]
expected={}
for row,index in re.findall(r"RVI\(([^)]*)\),\s*//\s*(\d+) ",src):
    id=int(index)
    if id not in ids: continue
    image,kind,buy,speed,power,tare,run,_,capacity,gauge,_=map(str.strip,row.split(","))
    expected[id]=[str(id),"2" if gauge=="O" else "3",image,buy,speed,power,tare,run,capacity,
      "1" if kind=="M" else "0",*dates[id]]
cmd=r'''
local A=dofile("mods/luanttd_core/openttd/advanced_rail_roster.lua")
for _,r in ipairs(A.catalog()) do
  print(table.concat({r.stock_id,r.railtype,r.image_index,r.cost_factor,r.speed,r.power,r.tare,
    r.running_factor,r.capacity,r.multiheaded and 1 or 0,r.base_intro,r.decay_speed,r.vehicle_life,
    r.model_life or r.source_model_life,r.cargo or "-",r.climates,r.name},"\t"))
end
'''
actual=subprocess.check_output([lua,"-e",cmd],cwd=root,text=True).splitlines()
assert len(actual)==len(ids)==len(expected)
for row in actual:
    fields=row.split("\t")
    assert fields==expected[int(fields[0])],(fields,expected[int(fields[0])])
print("PASS pinned RC1 monorail/maglev: 28 exact Temperate locomotive and freight/passenger trailer records")
