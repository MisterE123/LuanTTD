#!/usr/bin/env python3
"""Verify modeled RC1 City/Country jet metadata against the pinned source."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re
import subprocess

p=ArgumentParser(description=__doc__)
p.add_argument("engines",type=Path)
p.add_argument("--lua",default="lua5.1")
a=p.parse_args()
blob=a.engines.read_bytes()
assert sha256(blob).hexdigest()=="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
text=blob.decode()
lua=['local A=dofile("mods/luanttd_core/openttd/airport_roster.lua")']
for id_,name in ((217,"FFP Dart"),(220,"Bakewell Luckett LB-8"),
                 (221,"Bakewell Luckett LB-9"),(222,"Bakewell Luckett LB80"),
                 (223,"Bakewell Luckett LB-10"),(224,"Bakewell Luckett LB-11"),(225,"Yate Aerospace YAC 1-11"),(226,"Darwin 100"),(227,"Darwin 200"),(228,"Darwin 300"),
                 (229,"Darwin 400"),(230,"Darwin 500"),(231,"Darwin 600"),
                 (232,"Guru Galaxy"),(233,"Airtaxi A21"),(234,"Airtaxi A31"),(237,"Yate Aerospace YAe46"),
                 (238,"Dinger 100"),(235,"Airtaxi A32"),(236,"Airtaxi A33"),(254,"Guru X2 Helicopter"),(239,"AirTaxi A34-1000"),(247,"Dinger 1000")):
    ma=re.search(rf"^\s*MA\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+).+//\s*{id_} {name}\s*$",text,re.M)
    raw=re.search(rf"^\s*AVI\(([^\n]+)\), //\s*{id_-215} {name}\s*$",text,re.M)[1]
    fields=dict(zip(("intro_after_1920","decay_speed","life","model_life"),map(int,ma.groups())))
    assert fields.pop("decay_speed")==20
    row=list(map(str.strip,raw.split(",")))
    assert row[3]==("H" if id_==254 else "P" if id_ in (221,237,238,239) else "J") and "TAKEOFF_JET" in row[4]
    keys=("image","buy_factor","running_factor","acceleration","source_speed","mail","passengers")
    fields.update(zip(keys,(int(row[i]) for i in (0,1,2,5,6,7,8))))
    design = ("r.small and r.helicopter and r.dated and not r.jet" if id_==254 else
              "r.small and r.dated and not r.jet" if id_ in (221,237,238,239) else "r.jet and not r.small")
    lua += [f'local r=assert(A.entry({id_}));assert(r.name=="{name}" and {design})']
    lua += [f'assert(r.{k}=={v},{id_})' for k,v in fields.items()]
subprocess.run([a.lua,"-"],cwd=Path(__file__).resolve().parents[1],input="\n".join(lua),text=True,check=True)
print("PASS: 23 exact RC1 aircraft rows, including Country-capable jets and Guru X2 rotary")
