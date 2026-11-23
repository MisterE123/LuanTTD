#!/usr/bin/env python3
"""Verify modeled RC1 City Airport jet metadata against the pinned source."""
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
for id_,name in ((217,"FFP Dart"),(220,"Bakewell Luckett LB-8"),(225,"Yate Aerospace YAC 1-11"),(226,"Darwin 100"),(228,"Darwin 300")):
    ma=re.search(rf"^\s*MA\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+).+//\s*{id_} {name}\s*$",text,re.M)
    raw=re.search(rf"^\s*AVI\(([^\n]+)\), //\s*{id_-215} {name}\s*$",text,re.M)[1]
    fields=dict(zip(("intro_after_1920","decay_speed","life","model_life"),map(int,ma.groups())))
    assert fields.pop("decay_speed")==20
    row=list(map(str.strip,raw.split(",")))
    assert row[3]=="J"
    keys=("image","buy_factor","running_factor","acceleration","source_speed","mail","passengers")
    fields.update(zip(keys,(int(row[i]) for i in (0,1,2,5,6,7,8))))
    lua += [f'local r=assert(A.entry({id_}));assert(r.name=="{name}" and r.jet and not r.small)']
    lua += [f'assert(r.{k}=={v},{id_})' for k,v in fields.items()]
subprocess.run([a.lua,"-"],cwd=Path(__file__).resolve().parents[1],input="\n".join(lua),text=True,check=True)
print("PASS: five exact RC1 fast aircraft rows and native City Airport requirements")
