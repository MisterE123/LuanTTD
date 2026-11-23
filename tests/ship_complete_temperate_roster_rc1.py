#!/usr/bin/env python3
"""Direct RC1 comparisons for all seven originally Temperate mounted ships."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re
import subprocess
p=ArgumentParser(description=__doc__);p.add_argument('engines',type=Path);p.add_argument('--lua',default='lua5.1')
a=p.parse_args()
raw=a.engines.read_bytes()
assert sha256(raw).hexdigest()=='d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74'
s=raw.decode()
rows={204:'MPS Oil Tanker',205:'CS-Inc. Oil Tanker',206:'MPS Passenger Ferry',207:'FFP Passenger Ferry',
      208:'Bakewell 300 Hovercraft',211:'Yate Cargo ship',212:'Bakewell Cargo ship'}
modules=[('F','ship_roster'),('O','oil_ship_roster'),('P','passenger_ship_roster')]
tests=[f'local {k}=dofile("mods/luanttd_core/openttd/{filename}.lua")' for k,filename in modules]
for uid,name in rows.items():
    pattern=re.escape(name)
    kind='CT_OIL' if uid<=205 else 'CT_PASSENGERS' if uid<=208 else 'CT_GOODS'
    line=re.search(rf'^\s*MS\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*{kind}\s*,\s*LandscapeTypes\(\{{T,A,S\s*\}}\)\), //\s*{uid} {pattern}$',s,re.M)
    marine=re.search(rf'^\s*SVI\(([^\n]+)\), //\s*{uid-204} {pattern}$',s,re.M)[1].split(',')
    expected=dict(zip(('intro_after_1920','decay_speed','life','base_life'),map(int,line.groups())))
    expected.update(zip(('image','purchase_factor','acceleration','max_speed','capacity','running_factor'),
                        map(int,marine[:6])))
    assert int(marine[7])==(uid>=211)
    table='O' if uid<=205 else 'P' if uid<=208 else 'F'
    tests += [f'local row=assert({table}.model({uid}))']
    tests += [f'assert(row.{key}=={value},{uid})' for key,value in expected.items()]
subprocess.run([a.lua,'-'],input='\n'.join(tests),text=True,cwd=Path(__file__).resolve().parents[1],check=True)
print("PASS all seven exact RC1 Temperate ship model/physical/market rows")
