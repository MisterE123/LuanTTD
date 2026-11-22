#!/usr/bin/env python3
"""Check the stock truck/cargo data and coal callback order against OpenTTD 14.1."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
DIGEST={
    "engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "cargo_const.h":"3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "timer_game_tick.h":"be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
    "openttd.cpp":"1dacf8eaa085bde8d4db8993a582652da653915073611e6b029a77c4c474245d",
    "landscape.cpp":"0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97",
    "economy.cpp":"073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
}
def file(root,name):
    for sub in [Path("."),Path("src"),Path("src/table"),Path("src/timer")]:
        p=root/sub/name
        if p.exists():
            raw=p.read_bytes()
            assert hashlib.sha256(raw).hexdigest()==DIGEST[name],f"Wrong upstream version for {name}"
            return raw.decode()
    raise FileNotFoundError(name)
def fields(line):
    return [v.strip() for v in line.split(",")]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    eng,cargo,timer,main_cpp,landscape,eco=(file(a.source,n) for n in DIGEST)
    capacity=fields(re.search(r"ROV\((.*)\), //\s+7 Balogh Coal Truck",eng)[1])
    data=fields(re.search(r"MR\((.*)\), //\s+123 Balogh Coal Truck",eng)[1])
    props=fields(re.search(r"#define MR\(.*\) \{(.*)\}",eng)[1])
    coal=fields(re.search(r"MK\((.*CT_COAL.*)\),",cargo)[1])
    assert data[4]=="CT_COAL"
    assert re.search(r"RunTileLoop\(\);\s*CallVehicleTicks\(\);\s*CallLandscapeTick\(\);",main_cpp)
    assert re.search(r"OnTick_Station\(\);\s*OnTick_Industry\(\);",landscape)
    delays=fields(re.search(r"gradual_loading_wait_time\[\] = \{ (.*) \};",eco)[1])
    aging=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",timer)[1]
    expected=f"123,{capacity[5]},{capacity[4]},{props[4]},{aging},{delays[1]},{coal[0]},{coal[5]},{coal[6]},{coal[7]}"
    fixture=r"""
local r="mods/bayline/"
local c=dofile(r.."openttd/coal_industry.lua")()
local t=dofile(r.."openttd/loading_timing.lua")
local a=dofile(r.."road_coal_service.lua")(nil,c)
local e=a.truck
local k=a.cargo
io.write(table.concat({e.id,e.capacity,e.speed,e.load_amount,e.cargo_age_ticks,t.road_gradual_wait,
  k.id,k.payment,k.days1,k.days2},","))
"""
    got=subprocess.check_output([a.lua,"-e",fixture],cwd=ROOT,text=True)
    assert got==expected,(got,expected)
    print("PASS: pinned coal truck, cargo and raw loop/load/industry callback order")

if __name__=="__main__":
    main()
