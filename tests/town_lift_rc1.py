"""Compile OpenTTD 16.0-RC1 AnimateTile_Town and compare exact lift steps."""
from pathlib import Path
import subprocess as sp
from tempfile import TemporaryDirectory
import sys
from rc1_rail_foundation_shim import source_block

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
src = source / "src"
table = (src / "table/town_land.h").read_text()
animated = [row.split("// ", 1)[1][:2] for row in table[table.index("_original_house_specs[]"):].split("MS(")
            if "BuildingFlag::IsAnimated" in row and "// " in row]
assert animated == ["04", "05"], animated
cpp = r"""
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
struct TimerGameTick{static uint counter;};
uint TimerGameTick::counter;
constexpr int NEW_HOUSE_OFFSET=110;
enum class BuildingFlag{IsAnimated};
int type,pos,dest,erased,changed;
uint draws;
uint32_t word;
int GetHouseType(int){return type;}
void AnimateNewHouseTile(int){std::abort();}
struct HouseSpec {
  struct {bool Test(BuildingFlag)const{return type==4||type==5;}} building_flags;
  static const HouseSpec *Get(int){static HouseSpec h;return &h;}
};
void DeleteAnimatedTile(int){erased=1;}
bool LiftHasDestination(int){return dest>=0;}
int GetLiftPosition(int){return pos;}
int GetLiftDestination(int){return dest;}
void SetLiftDestination(int,int d){dest=d;}
void SetLiftPosition(int,int p){pos=p;}
void HaltLift(int){dest=-1;}
void MarkTileDirtyByTile(int){++changed;}
uint RandomRange(uint limit){
  ++draws;
  word=word*1664525u+1013904223u;
  return (uint64_t(word)*limit)>>32;
}
"""
cpp += source_block(src, "town_cmd.cpp", r"^static void AnimateTile_Town")
cpp += r"""
int main(){
 for(int id:{3,4,5})for(int p=0;p<=36;++p)for(int d:{-1,0,2,3,4,5,6})
   for(uint tick=0;tick<8;++tick)for(uint32_t seed:{0u,18u,17000u,0xffffffffu}){
     if(d*6==p)continue;
     type=id;pos=p;dest=d;word=seed;
     draws=erased=changed=0;
     TimerGameTick::counter=tick;
     AnimateTile_Town(0);
     std::cout<<id<<' '<<p<<' '<<d<<' '<<tick<<' '<<seed<<' '<<pos<<' '
              <<dest<<' '<<erased<<' '<<changed<<' '<<draws<<'\n';
   }
}
"""
lua = r"""
local L=dofile("mods/luanttd_core/openttd/town_lift.lua")
local n=0
for row in io.lines() do
  local v={};for w in row:gmatch("%-?%d+") do v[#v+1]=tonumber(w) end
  local id,p,d,tick,word,pos,dest,erase,marked,draws=unpack(v)
  local a=L.new()
  local h={id=id,lift_position=p,lift_destination=d>=0 and d or nil,lift_has_destination=d>=0 or nil}
  L.add(a,1)
  local count,dirty=0,0
  L.step(a,tick,function()return h end,function()
    count=count+1;word=(word*1664525+1013904223)%4294967296;return word
  end,function()dirty=dirty+1 end)
  assert(h.lift_position==pos and (h.lift_destination or -1)==dest and
    (a.states[1]=="delete")==(erase==1) and count==draws and dirty==marked,row)
  n=n+1
end
assert(n>22000)
print(("PASS %d compiled RC1 lift step comparisons"):format(n))
"""
with TemporaryDirectory() as work:
    cc, exe, frame = (Path(work) / name for name in ("lift.cpp", "lift", "lift.lua"))
    cc.write_text(cpp)
    frame.write_text(lua)
    sp.run(["g++", "-O2", "-std=c++20", cc, "-o", exe], check=True)
    sp.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1", frame],
           input=sp.check_output([exe]), check=True)
