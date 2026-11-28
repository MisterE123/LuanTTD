#!/usr/bin/env python3
"""Compare the served-station count around the actual RC1 deletion tick."""
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

src = Path(sys.argv[1]) / "src"
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
root = Path(__file__).resolve().parents[1]


def body(text, declaration):
    start = text.index("{", text.index(declaration))
    depth = 0
    for end in range(start, len(text)):
        depth += (text[end] == "{") - (text[end] == "}")
        if depth == 0:
            return text[start:end+1]
    raise AssertionError(declaration)


town = (src / "town_cmd.cpp").read_text()
station = (src / "station_cmd.cpp").read_text()
period = int(re.search(r"STATION_ACCEPTANCE_TICKS\s*=\s*(\d+)",
                       (src / "timer/timer_game_tick.h").read_text())[1])
retire = body(station, "if (!st->IsInUse()) {\n\t\tif (++st->delete_ctr")
closest = body(station, "static Station *GetClosestDeletedStation(TileIndex tile)")
near = body(town, "static void ForAllStationsNearTown(Town *t, Func func)")
count = body(town, "static int CountActiveStations(Town *t)")
cpp = r'''
#include <array>
#include <cstdlib>
#include <iostream>
#include <vector>
using uint = unsigned;
using TileIndex = unsigned;
enum class HouseZone { TownEdge };
static uint to_underlying(HouseZone h) { return uint(h); }
struct Town { TileIndex xy; struct { std::array<uint, 1> squared_town_zone_radius; } cache; };
static constexpr uint _current_company = 17;
struct Station {
  uint index, xy, time_since_load, time_since_unload, mode, delete_ctr = 0, owner = _current_company;
  bool IsInUse() const { return false; }
};
static std::vector<Station *> records;
static uint DistanceSquare(TileIndex a,TileIndex b) {
  int x=int(a%64)-int(b%64), y=int(a/64)-int(b/64);return x*x+y*y;
}
template <class F> static void ForAllStationsRadius(TileIndex xy,uint r,F visit) {
  for (auto *st:records) {
    if (std::abs(int(st->xy%64)-int(xy%64))<=int(r) &&
        std::abs(int(st->xy/64)-int(xy/64))<=int(r)) visit(st);
  }
}
static uint DistanceManhattan(TileIndex a, TileIndex b) {
  return std::abs(int(a%64)-int(b%64))+std::abs(int(a/64)-int(b/64));
}
static Station *GetClosestDeletedStation(TileIndex tile)
''' + closest + r'''
static void retired_bigtick(Station *st)
''' + retire.replace("return false;", "return;") + r'''
template <class Func> static void ForAllStationsNearTown(Town *t,Func func)
''' + near + r'''
static int CountActiveStations(Town *t)
''' + count + r'''
int main() {
  uint tile, radius, now, phase, n;
  while (std::cin>>tile>>radius>>now>>phase>>n) {
    Town t{tile,{{radius}}};
    for (uint i=0;i<n;++i) {
      uint mode,id,xy,removed,load,unload;
      std::cin>>mode>>id>>xy>>removed>>load>>unload;
      auto *st=new Station{id,xy,load,unload,mode};
      for (uint tick=removed+1;tick<=now-phase && st;++tick) {
        if ((tick+id)%PERIOD!=0) continue;
        bool last=st->delete_ctr==7;
        retired_bigtick(st);
        if (last) st=nullptr;
      }
      if (st) records.push_back(st);
    }
    std::cout<<CountActiveStations(&t);
    auto active=records;
    for (uint mode=0;mode<4;++mode) {
      records.clear();
      for (auto *st:active) if (st->mode==mode) records.push_back(st);
      auto *best=GetClosestDeletedStation(tile);
      std::cout<<' '<<(best?int(best->index):-1)<<' '<<(best?int(best->delete_ctr):-1);
    }
    records=active;
    std::cout<<'\n';
    for (auto *st:records) delete st;
    records.clear();
  }
}
'''.replace("PERIOD", str(period))
adapter = r'''
local mod="mods/luanttd_core/"
local Sim={xy=function(id) return id%64,math.floor(id/64) end,
  distance=function(a,b)return math.abs(a%64-b%64)+math.abs(math.floor(a/64)-math.floor(b/64)) end,
  id=function(x,z) if x>=0 and x<64 and z>=0 and z<64 then return x+z*64 end end}
local retire=dofile(mod.."openttd/road_station_retirement.lua")(Sim)
Sim.road_station_retirement=function()return retire end
local Services=dofile(mod.."town_station_services.lua")(Sim)
local G=dofile(mod.."openttd/town_growth.lua")
while true do
  local tile,radius,now,phase,n=io.read("*n","*n","*n","*n","*n")
  if not tile then break end
  local s={stock_pool_authority=true,passenger_house_clock={counter=0}}
  for _=1,n do
    local mode,id,xy,removed,load,unload=io.read("*n","*n","*n","*n","*n","*n")
    s.passenger_house_clock.counter=removed
    retire.retire(s,({"station","dock","rail","airport"})[mode+1],
      {id=1024-id,stock_station_id=id,owner="Company",tile=xy,time_since_load=load,time_since_unload=unload})
  end
  s.passenger_house_clock.counter=now
  local x,z=Sim.xy(tile)
  local t={x=x,z=z,radii={radius}}
  local result={G.active_stations(t,Services.view(s,true,now-phase))}
  s.passenger_house_clock.counter=now-phase
  for _,mode in ipairs({"station","dock","rail","airport"}) do
    local best=retire.closest(s,mode,"Company",tile)
    local _,count
    if best then _,count=retire.take(s,mode,best.id) end
    result[#result+1]=best and best.stock_station_id or -1
    result[#result+1]=count or -1
  end
  print(table.concat(result," "))
end
'''
rng = random.Random(0x16C1)
cases = []
for _ in range(1000):
    x, z = rng.randrange(12, 52), rng.randrange(12, 52)
    now = rng.randrange(2600, 70000)
    n = rng.randrange(1, 12)
    row = [x+64*z, rng.choice([4, 25, 49, 81, 121, 149, 200]), now, rng.randrange(2), n]
    for id in rng.sample(range(1024), n):
        xy = x+rng.randrange(-12,12)+64*(z+rng.randrange(-12,12))
        row.extend([rng.randrange(4),id,xy,now-rng.randrange(2450),
                    rng.choice([0,20,21,255]),rng.choice([0,20,21,255])])
    cases.append(row)
for id in range(period):
    removed = 4321
    cutoff = removed + (period-(removed+id)%period) + 7*period
    for when in [-1,0,1]:
        for phase in [0,1]:
            for age in [20,21]:
                for radius in [24,25]:
                    cases.append([2048,radius,cutoff+when,phase,1,id%4,id,2053,removed,age,255])
# Physical IDs intentionally sort opposite to the Lua adapter's local IDs.
# The nearest equal-distance sign must still be the smaller physical ID.
cases.append([2068,100,6440,0,4,0,612,2066,6000,20,255,0,91,2070,6000,0,255,
              1,312,2071,5900,0,255,1,81,2073,5900,20,255])
data = "".join(" ".join(map(str,r))+"\n" for r in cases)
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder)
    (path/"source.cpp").write_text(cpp)
    (path/"adapter.lua").write_text(adapter)
    subprocess.run(["g++","-O2",str(path/"source.cpp"),"-o",str(path/"source")],check=True)
    expected = subprocess.check_output([path/"source"],input=data,text=True).splitlines()
    observed = subprocess.check_output([lua,path/"adapter.lua"],input=data,text=True,cwd=root).splitlines()
assert len(expected)==len(observed)==len(cases)
for row,a,b in zip(cases,expected,observed):
    assert a==b,(row,a,b)
print(f"PASS {len(cases):,} compiled RC1 retired-station cases: town radius, ages, expiry, closest physical ID and reopen phase")
