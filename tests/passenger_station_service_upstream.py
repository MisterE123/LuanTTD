#!/usr/bin/env python3
"""Verify stock passenger ferry/carriage specs and compare their loading clocks."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
PIN={
    "economy.cpp":"073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "timer_game_tick.h":"be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
}
CPP=r"""
#include <algorithm>
#include <iostream>
const int VEH_TRAIN=0,VEH_ROAD=1,VEH_SHIP=2,TILE_SIZE=16;
struct Station {
  int length;
  int GetPlatformLength(int) const {return length;}
};
struct Vehicle {
  int type,tile=0,load_unload_ticks=0;
  struct {int cached_total_length;} cache;
  auto GetGroundVehicleCache(){return &cache;}
};
struct {struct {bool station_length_loading_penalty;} order;} _settings_game;

STOCK_WAIT

int main(){
  int mode,loaded,unloaded,retry,gradual,train_length,platform,penalty;
  while(std::cin>>mode>>loaded>>unloaded>>retry>>gradual>>train_length>>platform>>penalty){
    Vehicle vehicle; Station st{platform}; Vehicle* front=&vehicle;
    front->type=mode==0?VEH_TRAIN:VEH_SHIP;
    front->cache.cached_total_length=train_length;
    _settings_game.order.station_length_loading_penalty=penalty;
    int new_load_unload_ticks=loaded+unloaded;
    if(loaded>0 || unloaded>0 || retry) {
      if (gradual) {
          STOCK_GRADUAL
      }
      UpdateLoadUnloadTicks(front,&st,new_load_unload_ticks);
    } else {
      STOCK_IDLE
    }
    std::cout<<front->load_unload_ticks<<"\n";
  }
}
"""
LUA=r"""
local S=dofile('mods/luanttd_core/passenger_station_service.lua')(
  {},{},{},{},{},function()return {} end,dofile('mods/luanttd_core/openttd/loading_timing.lua'))
for _,mode in ipairs({"rail","ship"}) do
  local d=S.stock[mode]
  print(string.format("%d %d %d %d",d.engine,d.cap,d.slice,d.aging))
end
for line in io.lines() do
  local n={}
  for s in line:gmatch("%S+") do n[#n+1]=tonumber(s) end
  print(S.loading_delay(n[1]==0 and "rail" or "ship",
    {loaded=n[2],unloaded=n[3],retry_unload=n[4]>0,gradual=n[5]>0},n[6],n[7],n[8]>0))
end
"""

def read(path,name):
    for f in (path/name,path/"src"/name,path/"src"/"table"/name,path/"src"/"timer"/name):
        if f.exists():
            b=f.read_bytes()
            assert sha256(b).hexdigest()==PIN[name],f"Expected OpenTTD 14.1 {name}"
            return b.decode()
    raise FileNotFoundError(name)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    p.add_argument("--cxx",default="g++")
    a=p.parse_args()
    eco,eng,timer=(read(a.source,name) for name in PIN)
    start=eco.index("static void UpdateLoadUnloadTicks")
    wait=eco[start:eco.index("\n}",start)+2]
    gradual=re.search(r"const uint gradual_loading_wait_time\[\].*?new_load_unload_ticks = gradual_loading_wait_time\[front->type\];",eco,re.S).group()
    idle=re.search(r"UpdateLoadUnloadTicks\(front, st, \d+\); // We need the ticks for link refreshing.",eco).group()
    idle=idle.replace("front, st","front, &st") # standalone fixture's stack station
    cpp=CPP.replace("STOCK_WAIT",wait).replace("STOCK_GRADUAL",gradual).replace("STOCK_IDLE",idle)
    cpp="#include <cstdint>\nusing uint=unsigned int;\n"+cpp
    ages=int(re.search(r"CARGO_AGING_TICKS = (\d+)",timer).group(1))
    spec=[]
    for record,idx,cap_macro,rider in [("MW",27,"RVI","Passenger Carriage"),
                                          ("MS",206,"SVI","MPS Passenger Ferry")]:
        def_record=re.search(r"#define "+record+r"\([^)]*\) \{(.*)\}",eng).group(1)
        slice_count=int(def_record.split(",")[4].strip())
        assert "Ticks::CARGO_AGING_TICKS" in def_record
        assert re.search(r"\b"+record+r"\(.*CT_PASSENGERS.*\), //\s+"+str(idx)+r" "+rider,eng)
        vehicle_idx=idx if record=="MW" else 2
        vi=re.search(r"\b"+cap_macro+r"\(([^)]*)\), //\s+"+str(vehicle_idx)+" "+rider,eng)
        capacity=int(vi.group(1).split(",")[8 if record=="MW" else 4])
        spec.append(f"{idx} {capacity} {slice_count} {ages}")
    rand=random.Random(141)
    cases=[]
    for i in range(10000):
        case=[i%2,rand.choice([0,0,5,10]),rand.choice([0,0,5,10]),rand.randrange(2),
            rand.randrange(2),rand.randrange(8,144),rand.randrange(1,12),rand.randrange(2)]
        cases.append(" ".join(map(str,case)))
    data="\n".join(cases)+"\n"
    with tempfile.TemporaryDirectory() as temp:
        tmp=Path(temp); (tmp/"ref.cpp").write_text(cpp); (tmp/"probe.lua").write_text(LUA)
        subprocess.run([a.cxx,"-std=c++17","-O2",tmp/"ref.cpp","-o",tmp/"ref"],check=True)
        expected=subprocess.check_output([tmp/"ref"],input=data,text=True).splitlines()
        got=subprocess.check_output([a.lua,tmp/"probe.lua"],cwd=ROOT,input=data,text=True).splitlines()
    assert got[:2]==spec,(got[:2],spec)
    got=got[2:]
    assert len(expected)==len(got)==len(cases)
    for c,left,right in zip(cases,expected,got):
        assert left==right,(c,left,right)
    print(f"PASS: stock capacities/slices/aging and {len(cases)} rail/ship load or retry delays")

if __name__=="__main__":
    main()
