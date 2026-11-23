#!/usr/bin/env python3
"""Check MPS/CS-Inc. stock tanker data against the pinned OpenTTD 16.0-RC1 table."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re
import subprocess

p=ArgumentParser(description=__doc__);p.add_argument('engines',type=Path);p.add_argument('--lua',default='lua5.1')
a=p.parse_args()
blob=a.engines.read_bytes()
assert sha256(blob).hexdigest()=='d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74'
text=blob.decode()
meta=re.search(r'^#define MS\([^\n]*\{ ([^\n]+) \}',text,re.M)[1].split(', ')
assert meta[4]=='10' and meta[-2]=='Ticks::CARGO_AGING_TICKS'
svi=re.search(r'^#define SVI\([^\n]*\{ ([^\n]+) \}',text,re.M)[1].split(', ')
assert svi[-2:]==['0','0']
lua=['local S=dofile("mods/luanttd_core/openttd/oil_ship_roster.lua")']
for id_,name in [(204,'MPS Oil Tanker'),(205,'CS-Inc. Oil Tanker')]:
    ma=re.search(rf'^\s*MS\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*CT_OIL\s*,\s*LandscapeTypes\(\{{T,A,S\s*\}}\)\), //\s*{id_} {re.escape(name)}\s*$',text,re.M)
    rv=re.search(rf'^\s*SVI\(([^\n]+)\), //\s*{id_-204} {re.escape(name)}\s*$',text,re.M)[1].split(',')
    fields=dict(zip(('intro_after_1920','decay_speed','life','base_life'),map(int,ma.groups())))
    fields.update(zip(('image','purchase_factor','acceleration','max_speed','capacity','running_factor'),map(int,rv[:6])))
    assert int(rv[7])==0
    fields.update(load_amount=10,cargo_age_ticks=185,default_cargo=3,local_id=id_-204)
    lua += [f'local r=assert(S.quote({id_}));assert(r.name=="{name}" and r.refittable==false and r.stock_id=={id_})']
    lua += [f'assert(r.{k}=={v},{id_})' for k,v in fields.items()]
    lua += [f'assert(r.price=={65000*fields["purchase_factor"]//256})']
    for ticks in (0,1,74,999):
        lua += [f'assert(S.running_fixed({id_},{ticks})=={5600*fields["running_factor"]*ticks//(365*74)})']
subprocess.run([a.lua,'-'],cwd=Path(__file__).resolve().parents[1],input='\n'.join(lua),text=True,check=True)
print('PASS: exact RC1 stock oil ship engines, purchase, running costs and unrefittable cargo')
