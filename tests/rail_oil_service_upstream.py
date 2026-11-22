#!/usr/bin/env python3
"""Verify stock #30 rail Oil Tanker, load wait and freight mass against 14.1."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from road_loading_upstream import extract
from timber_industry_upstream import ROOT, read, args_of

PIN = {
    "vehicle_type.h":"a941b74ff14f5b930a11430debd518370e0c338dbc49f3a7d7a51ad7f1da8c7c",
    "cargotype.cpp":"ab55f017e6dce9a87d48bab64a51d1b0365600bae719f5830785f3c16a555c51",
    "cargotype.h":"4b197ae98b933c63a147402b74a87a58b91b46d6685e960239f7683b01e3bef2",
    "engine.cpp":"b2bbfc2fb77e4b9695730b5e7623f0311e8f7d4d75dbc4fcd166d4ac08691db9",
}
CPP = r"""
#include <algorithm>
#include <cstdint>
#include <iostream>
constexpr int VEH_TRAIN=0,TILE_SIZE=16;
struct Setting {
 struct { bool station_length_loading_penalty; } order;
 struct { int freight_trains; } vehicle;
} _settings_game;
struct Vehicle {
 int type=VEH_TRAIN,tile=5,load_unload_ticks=0;
 struct { int cached_total_length; } cache;
 const decltype(cache)* GetGroundVehicleCache() const {return &cache;}
};
struct Station {int length;int GetPlatformLength(int tile) const {return tile==5?length:0;}};
struct CargoSpec {
 bool is_freight=true;
 uint16_t weight=16;
 INLINE_WEIGHT
 uint64_t WeightOfNUnitsInTrain(uint32_t n) const;
};
"""
DRIVER = r"""
int main() {
  int units,factor,length,platform_tiles,loaded,unloaded,gradual,retry,penalty;
  while(std::cin>>units>>factor>>length>>platform_tiles>>loaded>>unloaded>>gradual>>retry>>penalty) {
    const CargoSpec cargo;
    _settings_game.vehicle.freight_trains=factor;
    auto mass=cargo.WeightOfNUnitsInTrain(units);
    Vehicle v;
    v.cache.cached_total_length=length;
    Station s{platform_tiles};
    _settings_game.order.station_length_loading_penalty=penalty;
    int wait=loaded+unloaded;
    if(wait||retry) {if(gradual) wait=STOCK_GRADUAL;}
    else wait=STOCK_RETRY;
    UpdateLoadUnloadTicks(&v,&s,wait);
    std::cout<<mass+STOCK_TARE<<' '<<mass<<' '<<v.load_unload_ticks<<'\n';
  }
}
"""
LUA = r"""
local root="mods/bayline/"
local function m(n) return dofile(root..n..".lua") end
local O=m("openttd/oil_industry")(m("openttd/farm_factory_industry"))
local Roster,Timing=m("openttd/rail_roster"),m("openttd/loading_timing")
local Platform=m("rail_coal_service")(nil,m("openttd/coal_industry")(),nil,Roster,nil,nil,nil,nil,nil,Timing)
local R=m("rail_oil_service")(nil,O,nil,Roster,Platform,nil,nil,nil,nil,Timing)
local v=R.wagon
print(table.concat({v.stock_id,v.image_index,v.tare,v.capacity,v.cost_factor,v.length,v.load_amount,
  v.cargo_age_ticks,v.base_intro,v.decay_speed,v.vehicle_life,v.model_life,
  O.cargo.oil.id,O.cargo.oil.weight_16,O.cargo.oil.payment,O.cargo.oil.days1,O.cargo.oil.days2},","))
for line in io.lines() do
  local a={}
  for v in line:gmatch("%d+") do a[#a+1]=tonumber(v) end
  local weight,cargo=R.mass(a[1],a[2])
  local delay=R.loading_pulse({loaded=a[5],unloaded=a[6],gradual=a[7]==1,retry_unload=a[8]==1,
    reservations=0,full=false,cargo_not_full=true,elapsed=1,wait=0,lateness=0},
    a[3],a[4],a[9]==1)
  print(table.concat({weight,cargo,delay}," "))
end
"""


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    ns=p.parse_args()
    def pin(name):
        f=ns.source/name
        if not f.exists():
            f=ns.source/"src"/name
        b=f.read_bytes()
        assert hashlib.sha256(b).hexdigest()==PIN[name],f
        return b.decode()
    engines,eco,time,commodities=(read(ns.source,k) for k in ("engines.h","economy.cpp","timer_game_tick.h","cargo_const.h"))
    raw=args_of(re.search(r"RVI\((.*)\), //\s+30 Oil Tanker",engines)[1])
    mw=args_of(re.search(r"MW\((.*)\), //\s+30 Oil Tanker",engines)[1])
    macro=args_of(re.search(r"#define MW\(.*\) \{(.*)\}",engines)[1])
    oil=args_of(re.search(r"MK\((.*CT_OIL.*)\),",commodities)[1])
    assert mw[4]=="CT_OIL" and raw[1]=="W" and oil[8]=="true"
    n0=re.search(r"this->u\.rail\.railveh_type == RAILVEH_WAGON\) this->info\.base_life = (0x\w+)",pin("engine.cpp"))[1]
    old=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",time)[1]
    grad=args_of(re.search(r"gradual_loading_wait_time\[\] = \{(.*)\};",eco)[1])[0]
    retry=re.search(r"UpdateLoadUnloadTicks\(front, st, (\d+)\); // We need the ticks",eco)[1]
    # Vehicle length eight is the source's un-shortened stock ground
    # vehicle and one station tile has sixteen sub-tile units.
    spec=("30",raw[0],raw[5],raw[8],raw[2],re.search(r"VEHICLE_LENGTH\s*=\s*(\d+)",pin("vehicle_type.h"))[1],macro[4],old,mw[0],mw[1],mw[2],
          str(int(n0,16)),*[str(int(oil[i],0)) for i in (0,3,5,6,7)])
    inline=re.search(r"inline uint64_t WeightOfNUnits\(.*?^\s*}",pin("cargotype.h"),re.S|re.M)[0]
    stock=CPP.replace("INLINE_WEIGHT",inline)+extract(pin("cargotype.cpp"),"uint64_t CargoSpec::WeightOfNUnitsInTrain(")
    stock+=extract(eco,"static void UpdateLoadUnloadTicks(")
    stock+=DRIVER.replace("STOCK_GRADUAL",grad).replace("STOCK_RETRY",retry).replace("STOCK_TARE",raw[5])
    rng=random.Random(30)
    rows=[]
    for i in range(5000):
        m=i%4
        rows.append(" ".join(map(str,(rng.randrange(31),rng.randrange(1,11),rng.randrange(1,120),
          rng.randrange(1,12),rng.randrange(1,31) if m==0 else 0,rng.randrange(1,31) if m==1 else 0,
          rng.randrange(2),int(m==2),rng.randrange(2)))))
    data=("\n".join(rows)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(stock)
        (d/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        c=subprocess.check_output([str(d/"stock")],input=data).decode().splitlines()
        l=subprocess.check_output([ns.lua,str(d/"port.lua")],input=data,cwd=ROOT).decode().splitlines()
    assert l[0]==",".join(spec),(l[0],spec)
    for row,old,new in zip(rows,c,l[1:],strict=True):
        assert old==new,(row,old,new)
    print("PASS: pinned #30 Tanker and 5,000 compiled freight mass/source rail loading waits")

if __name__=="__main__":
    main()
