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
# The nine dry choices are derived from the *active slots* and cargo
# classes, not the OpenTTD cargo-bit constant (which varies by climate).
src=a.engines.parent.parent
def pinned(path,digest):
    raw=(src/path).read_bytes()
    assert sha256(raw).hexdigest()==digest,path
    return raw.decode()
refits=pinned("newgrf.cpp","e6176f8d13d7f57139f134f69630327dd3300a6b3b7979bbb1d9e6294b2b344e")
cargos=pinned("table/cargo_const.h","cac711a29f0bcd906a8c202219ead4ba5cec90bfc5ea2e2fc03c990ab86f43d2")
engine=pinned("engine.cpp","d34c988d4903da1216befbdf004dd170e5b865e67eb0ccc913e373a842b60286")
command=pinned("vehicle_cmd.cpp","0eaa6d5fbd87591499717348b8a4dd9b81280e7b7f23f8cc7e1ab68c13f6cd67")
prices=pinned("table/pricebase.h","8e0d8a31a7b08aa75fbb63d6b583e9a3edf9bae3c49493c5819d1de579ab1ec1")
classes=lambda text:set(re.findall(r"CargoClass::(\w+)",text))
allowed,excluded=map(classes,re.search(
    r"/\* Cargo ships \*/\s*_gted\[engine\]\.cargo_allowed = (.*?);\s*"
    r"_gted\[engine\]\.cargo_disallowed = (.*?);",refits).groups())
by_cargo={}
for label,description in re.findall(r"^\s*MK\(\s*(?:\d+|0xFF),\s*CT_(\w+),[^\n]*?CargoClasses\(\{([^}]*)\}\)",cargos,re.M):
    by_cargo.setdefault(label,classes(description))
temperate=re.search(r"_default_climate_cargo[^=]*= \{\s*\{([^}]+)\}",cargos)[1]
slots=[(i,key.removeprefix("CT_")) for i,key in enumerate(map(str.strip,temperate.split(","))) if key.startswith("CT_")]
keys={i:(label.lower() if label!="PASSENGERS" else "passenger") for i,label in slots
      if by_cargo[label]&allowed and not by_cargo[label]&excluded}
assert "this->type != VehicleType::Ship && default_cargo != cargo_type" in engine
buy_shift=int(re.search(r"Money Engine::GetCost\(\).*?GetPrice\([^\n]*, -(\d+)\)",engine,re.S)[1])
refit_shift=int(re.search(r"static CommandCost GetRefitCost\(.*?GetPrice\([^\n]*, -(\d+)\)",command,re.S)[1])
refit_factor=int(re.search(r"#define MS[^\n]*CargoTypes\{\}, (\d+),",s)[1])
base=int(re.search(r"PriceBaseSpec\((\d+),[^\n]*Price::BuildVehicleShip",prices)[1])
tests += [
    f'assert(F.default_cargo=={next(i for i,label in slots if label=="GOODS")})',
    f'assert(#F.refit_catalog()=={len(keys)})',
]
for i,(slot,key) in enumerate(keys.items(),1):
    tests += [
        f'assert(F.refit_catalog()[{i}].id=={slot} and F.refit_catalog()[{i}].cargo=="{key}")',
        f'assert(F.cargo_id("{key}")=={slot} and F.cargo_key({slot})=="{key}")',
    ]
for uid in (211,212):
    vehicle_row=re.search(rf"^\s*SVI\(([^\n]+)\), //\s*{uid-204} ",s,re.M)[1].split(",")
    factor,capacity=int(vehicle_row[1]),int(vehicle_row[4])
    for dst in range(12):
        for old in keys:
            if dst not in keys:
                tests += [f'assert(not F.quote({dst},{base},{old},{uid}))']
                continue
            for price in (1,base,base+31111):
                purchase=price*factor>>buy_shift
                refit=0 if dst==old else price*refit_factor>>refit_shift
                tests += [
                    f'do local q=assert(F.quote({dst},{price},{old},{uid})); '
                    f'assert(q.capacity=={capacity} and q.purchase=={purchase} and q.refit=={refit}) end'
                ]
subprocess.run([a.lua,'-'],input='\n'.join(tests),text=True,cwd=Path(__file__).resolve().parents[1],check=True)
print("PASS all seven exact RC1 Temperate ship model/physical/market rows and the complete dry refit price/hold matrix")
