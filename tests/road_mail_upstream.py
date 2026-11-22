#!/usr/bin/env python3
"""Check the mail adapter's data against the OpenTTD 14.1 declarations."""
import argparse
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LUA = r"""
local base="mods/luanttd_core/"
local H=dofile(base.."openttd/town_passengers.lua")
local mail=dofile(base.."road_mail_runtime.lua")({},H)
local c,e=mail.cargo,mail.engine
local function row(...) print(table.concat({...},",")) end
row(c.id,c.bitnum,c.label,c.weight_sixteenths,c.capacity_multiplier,
    c.base_payment,c.transit_period_1,c.transit_period_2)
row(e.id,e.road_model,e.capacity,e.max_speed,e.load_amount,e.cargo_aging_ticks,e.intro_days_after_1920,
    e.cost_factor,e.running_cost_factor,e.weight_quarters,e.power_tens_hp)
row(mail.catchment)
for i=0,109 do row(i,mail.house_acceptance(i)) end
"""

FILES = {
    "cargo_const.h": "src/table/cargo_const.h",
    "engines.h": "src/table/engines.h",
    "town_land.h": "src/table/town_land.h",
    "timer_game_tick.h": "src/timer/timer_game_tick.h",
    "station_type.h": "src/station_type.h",
}
DIGESTS = {
    "cargo_const.h": "3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "engines.h": "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "town_land.h": "a6925280753e551f4426a92d76a8c57f49171a519c860d855b3cd29946c817d7",
}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path,help="OpenTTD 14.1 checkout or flat staged source")
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()

    def read(name):
        f=a.source/name
        if not f.exists():
            f=a.source/FILES[name]
        data=f.read_bytes()
        if name in DIGESTS:
            assert sha256(data).hexdigest()==DIGESTS[name], f"Need pinned OpenTTD 14.1 {name}"
        return data.decode()

    cargo_src=read("cargo_const.h")
    cargo=re.search(r"\bMK\(\s*(\d+),\s*CT_MAIL,\s*\d+,\s*(\d+),\s*(0x[0-9A-F]+),"
                    r"\s*(\d+),\s*(\d+),\s*(\d+),\s*false,\s*TAE_MAIL",cargo_src)
    bit,weight,mult,payment,delay1,delay2=cargo.groups()
    climate=re.search(r"_default_climate_cargo[^\n]+\n\s*\{([^}]+)\}",cargo_src)[1]
    cid=[x.strip() for x in climate.split(",")].index("CT_MAIL")

    engines=read("engines.h")
    engine=re.search(r"\bMR\(\s*(\d+),[^\n]+CT_MAIL[^\n]+\),\s*//\s*(\d+) MPS Mail Truck",engines)
    intro,eid=engine.groups()
    road=re.search(r"ROV\(\s*\d+,\s*(\d+),\s*(\d+),\s*\w+,\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)"
                   r",\s*//\s*(\d+) MPS Mail Truck",engines)
    cost,running,speed,capacity,weightq,power,rid=road.groups()
    engine_macro=re.search(r"#define MR\([^\n]+",engines)[0]
    assert ", e, 0, 8, 0, 0, 0, STR_EMPTY, Ticks::CARGO_AGING_TICKS" in engine_macro
    age=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",read("timer_game_tick.h"))[1]

    expected=[f"{cid},{bit},MAIL,{weight},{int(mult,16)},{payment},{delay1},{delay2}",
              f"{eid},{rid},{capacity},{speed},8,{age},{intro},{cost},{running},{weightq},{power}"]
    expected.append(re.search(r"CA_TRUCK\s*=\s*(\d+)",read("station_type.h"))[1])
    for args,ident in re.findall(r"MS\(([^)]*)\), // ([0-9A-F]{2})",read("town_land.h"),re.S):
        fields=[x.strip() for x in args.split(",")]
        assert fields[13]=="CT_MAIL"
        expected.append(f"{int(ident,16)},{fields[8]}")
    assert len(expected)==113

    with tempfile.TemporaryDirectory() as tmp:
        lua=Path(tmp)/"run.lua"
        lua.write_text(LUA)
        got=subprocess.check_output([a.lua,str(lua)],cwd=ROOT,text=True).splitlines()
    assert got==expected
    print("PASS: stock temperate MAIL CargoSpec, complete first truck identity/specs and all 110 vanilla mail acceptance entries")

if __name__=="__main__":
    main()
