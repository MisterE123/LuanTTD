#!/usr/bin/env python3
"""Compare stock aircraft passenger specs, speed telemetry, and edge terrain."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
PINS={
    "aircraft.h":"dcddab039810812ae3a6221b263ebe3dd45284a10296bf7dd3a4e4f8c25fb4ef",
    "aircraft_cmd.cpp":"2cbab20d910072dfc2dd490de9032fd9873224c890b7e8160e6cfe1514f96056",
    "engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "economy.cpp":"073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "airport_defaults.h":"4dff1dd1863443da7b5a6ab3b438734ceb0012ba2a152f498dc4629d77047f67",
    "timer_game_tick.h":"be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
}
CPP=r"""
#include <algorithm>
#include <iostream>
using uint=unsigned;
constexpr int TILE_SIZE=16,TILE_HEIGHT=8,VEH_AIRCRAFT=3;
namespace Map { int MaxX(){return 47;} int MaxY(){return 35;} }
int Clamp(int i,int l,int r){return std::min(r,std::max(i,l));}
int TileVirtXY(int x,int y){return x/16+y/16*48;}
int TileHeight(int tile){return (tile%48)%2+(tile/48)%2;}
struct Vehicle {
  int x_pos,y_pos,type=VEH_AIRCRAFT;
  struct {int cached_max_speed;} vcache;
  SPEED
};
HEIGHT
int main(){
  Vehicle v{};
  int loaded,unloaded,retry,gradual;
  while(std::cin>>v.vcache.cached_max_speed>>v.x_pos>>v.y_pos>>loaded>>unloaded>>retry>>gradual) {
    Vehicle* front=&v;
    int new_load_unload_ticks=loaded+unloaded;
    int wait;
    if(loaded>0 || unloaded>0 || retry) {
      if(gradual) {
        GRADUAL
      }
      wait=std::max(1,new_load_unload_ticks);
    } else {
      wait=IDLE;
    }
    std::cout<<std::min(255,v.GetSpeedOldUnits())<<" "<<GetTileHeightBelowAircraft(&v)<<" "<<wait<<"\n";
  }
}
"""
LUA=r"""
local root="mods/bayline/"
local function mod(n) return dofile(root..n..".lua") end
local R=mod("openttd/station_rating")
local C=mod("openttd/station_catchment")(nil,R)
local S=mod("passenger_station_service")(nil,nil,nil,R,nil,function()return {} end,mod("openttd/loading_timing"))
local A=mod("airport_preview_run")({W=48,H=36},nil,nil,nil,mod("openttd/terrain"))
local stock=S.stock.air
io.write(table.concat({stock.engine,stock.cap,stock.slice,stock.aging,A.engine.mail,A.engine.max_speed,
        C.radius("airport")},","),"\n")
local terrain=mod("openttd/terrain")
local s={corner_grid=terrain.new(48,36,function(x,z)return (x-1)%2+(z-1)%2 end)}
for line in io.lines() do
  local n={}
  for item in line:gmatch("%S+") do n[#n+1]=tonumber(item) end
  local g=R.new()
  C.observe_loading(g,"air",n[1],1950,1940,25)
  local delay=S.loading_delay("air",{loaded=n[4],unloaded=n[5],retry_unload=n[6]==1,gradual=n[7]==1})
  io.write(g.last_speed," ",A.terrain_under(s,n[2]+16,n[3]+16)," ",delay,"\n")
end
"""

def read(base,name):
    for part in (".","src","src/table","src/timer"):
        f=base/part/name
        if f.is_file():
            body=f.read_bytes()
            assert sha256(body).hexdigest()==PINS[name],f"Expected OpenTTD 14.1 {name}"
            return body.decode()
    raise FileNotFoundError(name)

def main():
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument("source",type=Path)
    args.add_argument("--lua",default="lua5.1")
    args.add_argument("--cxx",default="g++")
    opt=args.parse_args()
    aircraft,cmd,eng,eco,airport,timer=(read(opt.source,n) for n in PINS)
    speed=re.search(r"int GetSpeedOldUnits\(\) const\s*\{[^}]+}",aircraft)[0]
    height=cmd[cmd.index("int GetTileHeightBelowAircraft("):].split("\n}",1)[0]+"\n}"
    delay=re.search(r"const uint gradual_loading_wait_time\[\].*?new_load_unload_ticks = gradual_loading_wait_time\[front->type\];",eco,re.S)[0]
    idle=re.search(r"UpdateLoadUnloadTicks\(front, st, (\d+)\); // We need the ticks for link refreshing",eco)[1]
    assert re.search(r"MA\(.*\), //\s*215 Sampson U52",eng)
    air_values=re.search(r"AVI\(([^)]*)\), //\s*0 Sampson U52",eng)[1].split(",")
    slice_count=int(re.search(r"#define MA\([^\n]+\{([^\n]+)\}",eng)[1].split(",")[4])
    aging=int(re.search(r"CARGO_AGING_TICKS = (\d+)",timer)[1])
    cap=int(air_values[8]);mail=int(air_values[7]);max_speed=int(air_values[6])*128//10
    catchment=int(re.search(r"AS\(country,\s*4,\s*3,\s*\d+,\s*\d+,\s*(\d+)",airport)[1])
    spec=",".join(map(str,[215,cap,slice_count,aging,mail,max_speed,catchment]))
    cpp=CPP.replace("SPEED",speed).replace("HEIGHT\n",height+"\n").replace("GRADUAL",delay).replace("IDLE",idle)
    r=random.Random(215)
    cases=[]
    for i in range(8000):
        vals=[473 if i==0 else r.randrange(4096),-47 if i==0 else r.randrange(-320,1200),
            136 if i==0 else r.randrange(-320,900),r.choice([0,0,5,20]),r.choice([0,0,5,20]),
            r.randrange(2),r.randrange(2)]
        cases.append(" ".join(map(str,vals)))
    data="\n".join(cases)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        f=Path(tmp)
        (f/"t.cpp").write_text(cpp);(f/"t.lua").write_text(LUA)
        subprocess.run([opt.cxx,"-std=c++17","-O2",f/"t.cpp","-o",f/"t"],check=True)
        expected=subprocess.check_output([f/"t"],input=data,text=True).splitlines()
        result=subprocess.check_output([opt.lua,f/"t.lua"],cwd=ROOT,input=data,text=True).splitlines()
    assert result[0]==spec,(result[0],spec)
    result=result[1:]
    assert len(result)==len(expected)==len(cases)
    for case,want,got in zip(cases,expected,result):
        assert got==want,(case,want,got)
    print(f"PASS: source Sampson, country catchment, and {len(cases)} loading/speed/edge-height comparisons")

if __name__=="__main__":
    main()
