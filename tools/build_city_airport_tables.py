#!/usr/bin/env python3
"""Reproduce native City Airport data from two pinned OpenTTD 16.0-RC1 files."""
from hashlib import sha1
from pathlib import Path
import argparse
import re
import sys

PINS = {"airport_movement.h": "6988c499c81a88cd5f2dc7348f74263e5ceacdac",
        "airport.h": "11e2c34be36eabcd8434f64c0dbcf411dae428cd",
        "airport_defaults.h": "65dcba0808b1dabce5bc89c4351d32a16f0315e4"}
root = Path(__file__).resolve().parents[1]
def read(source, name):
    raw = (source / name).read_bytes()
    assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()==PINS[name], name
    return re.sub(r"//[^\n]*|/\*.*?\*/","",raw.decode(),flags=re.S)

def generate(source):
    head=read(source,"airport.h")
    data=read(source,"airport_movement.h")
    specs=read(source,"airport_defaults.h")
    def enum(label):
        return re.search(label+r"[^{}]*{([^}]+)}",head)[1]
    flags={name.strip():1<<i for i,name in enumerate(enum("enum class AirportMovingDataFlag").split(",")) if name.strip()}
    masks={name:1<<int(ix) for name,ix in re.findall(r"(\w+)\s*=\s*(\d+)",enum("enum class AirportBlock"))}
    states={name:int(ix) for name,ix in re.findall(r"(\w+)\s*=\s*(\d+)",enum("enum AirportMovementStates"))}
    dirs=dict(zip(("N","NE","E","SE","S","SW","W","NW"),range(8)))
    def table(name): return re.search(r"\b"+name+r"\[\d*\]\s*=\s*\{(.*?)\};",data,re.S)[1]
    waypoints=[]
    layout={}
    for x,z,mask,d in re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*\{([^}]+)?\},\s*Direction::(\w+)\s*\}",table("_airport_moving_data_city")):
        waypoints.append([int(x),int(z),sum(flags[n] for n in re.findall(r"AirportMovingDataFlag::(\w+)",mask or "")),dirs[d]])
    for i,h,b,j in re.findall(r"\{\s*(\d+),\s*(\w+),\s*(\{[^}]*\}|AirportBlock::\w+),\s*(\d+)\s*\}",table("_airport_fta_city")):
        layout.setdefault(int(i),[]).append([states[h],sum(masks[n] for n in re.findall(r"AirportBlock::(\w+)",b)),int(j)])
    assert set(layout)==set(range(len(waypoints))) and len(waypoints)==30
    entries=re.findall(r"\d+",table("_airport_entries_city"))
    x,z,d,id_=re.search(r"\{\s*\{(\d+),\s*(\d+)\},\s*Direction::(\w+),\s*(\d+)\s*\}",table("_airport_depots_city")).groups()
    groups,count=map(int,re.findall(r"\d+",table("_airport_terminal_city")))
    assert groups==1 and count==3
    w,h,year,reach=map(int,re.search(r"\bAS\(city,\s*(\d+),\s*(\d+),\s*(\d+),\s*CalendarTime::MAX_YEAR,\s*(\d+),",specs).groups())
    def array(items): return "{"+",".join(map(str,items))+"}"
    text=f"""-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Generated from the pinned 16.0-RC1 movement table.
local A={{W={w},H={h},TILE=16,intro_year={year},catchment_radius={reach},
  hangar={{x={x},z={z},dir={dirs[d]},id={id_}}},entries={{[0]={','.join(entries)}}}}}
local S={{ALL=0,HANGAR=1,TERM1=2,TERM2=3,TERM3=4,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}}
local B={{TERM1=1,TERM2=2,TERM3=4,RUNWAY=256,TAXIWAY=1024,OUT=2048,IN=4096,NOTHING=2^30}}
local F={{NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}}
A.state,A.block,A.flag=S,B,F
A.terminal_bits,A.terminal_states={{B.TERM1,B.TERM2,B.TERM3}},{{S.TERM1,S.TERM2,S.TERM3}}
A.block_bits={{B.TERM1,B.TERM2,B.TERM3,B.RUNWAY,B.TAXIWAY,B.OUT,B.IN,B.NOTHING}}
A.points={{
"""
    for i,cell in enumerate(waypoints):
        text+="  "+("[0]=" if i==0 else "")+array(cell)+",\n"
    text+="}\nA.layout={\n"
    for i,row in sorted(layout.items()):
        text+="  "+("[0]=" if i==0 else "")+array(array(p) for p in row)+",\n"
    return text+''' }
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
return dofile(mod.."/openttd/airport_fta.lua")(A)
'''.replace(" }\n","}\n",1)

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--write",action="store_true")
    args=parser.parse_args()
    target=root/"mods/luanttd_core/openttd/airport_city.lua"
    text=generate(args.source)
    if args.write: target.write_text(text)
    else:
        assert target.read_text()==text, "City Airport movement table is not pinned source"
        print("PASS exact City Airport 16.0-RC1 points, transitions, facility, and date")
