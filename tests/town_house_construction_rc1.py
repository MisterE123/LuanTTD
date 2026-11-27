#!/usr/bin/env python3
"""Compare the real RC1 house-construction state machine and tile write order."""
from pathlib import Path
from tempfile import TemporaryDirectory
from rc1_rail_foundation_shim import source_block
import os
import subprocess
import sys

root = Path(sys.argv[1])
assert subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src = root / "src"
cpp = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

enum class TileType { House };
struct Parcel { uint8_t byte=0; bool complete=false; };
std::array<Parcel,4> parcels;
struct Tile {
 int index;
 uint8_t &m5() const { return parcels[index].byte; }
};
using TileIndex=Tile;
bool IsTileType(Tile,TileType){return true;}
int GB(int n,int start,int len){return (n>>start)&((1<<len)-1);}
void AB(uint8_t &n,int start,int len,int increment){
 const int mask=(1<<len)-1;
 n=(n&~(mask<<start))|(((GB(n,start,len)+increment)&mask)<<start);
}
bool IsHouseCompleted(Tile t){return parcels[t.index].complete;}
void SetHouseCompleted(Tile t,bool complete){parcels[t.index].complete=complete;}
constexpr int TOWN_HOUSE_COMPLETED=3;
constexpr int BUILDING_HAS_1_TILE=1,BUILDING_2_TILES_Y=2,BUILDING_2_TILES_X=4,BUILDING_HAS_4_TILES=8;
struct BuildingFlags {int n; bool Any(int bits)const{return n&bits;}};
struct HouseSpec {
 int population;
 BuildingFlags building_flags;
 static std::array<HouseSpec,4> data;
 static const HouseSpec *Get(int id){return &data[id];}
};
std::array<HouseSpec,4> HouseSpec::data{};
int GetHouseType(Tile t){return t.index;}
Tile TileAddXY(Tile t,int x,int y){return {t.index+x*2+y};}
struct Town { static int GetByTile(Tile t){return t.index;} };
std::vector<int> dirty,animations,populations;
void ChangePopulation(int tile,int population){populations.push_back(tile);populations.push_back(population);}
void TriggerHouseAnimation_ConstructionStageChanged(Tile t,bool initial){assert(!initial);animations.push_back(t.index);}
void MarkTileDirtyByTile(Tile t){dirty.push_back(t.index);}
"""
for fn in ("GetHouseConstructionTick", "GetHouseBuildingStage", "IncHouseConstructionTick", "ResetHouseAge"):
    cpp += source_block(src, "town_map.h", rf"^inline (?:uint8_t|void) {fn}\(")
for fn in ("AdvanceSingleHouseConstruction", "AdvanceHouseConstruction"):
    cpp += source_block(src, "town_cmd.cpp", rf"^static void {fn}\(")
cpp += r"""
int main(){
 int mask,stage,counter,phase;
 while(std::cin>>mask>>stage>>counter>>phase){
  HouseSpec::data={{{65,{mask}},{3,{0}},{7,{0}},{11,{0}}}};
  for(auto &t:parcels)t={uint8_t(stage<<3|counter),stage==3};
  if(stage==3)for(auto &t:parcels)t.byte=115;
  for(int tick=0;tick<29;tick++){
    dirty.clear();animations.clear();populations.clear();
    const int child=(phase+tick)%4;
    bool invoke_child=child!=0 && (mask&(1<<child))!=0 && !parcels[child].complete;
    if(invoke_child)AdvanceHouseConstruction(Tile{child});
    bool active=!parcels[0].complete;
    if(active)AdvanceHouseConstruction(Tile{0});
    assert(dirty==animations);
    std::cout<<active;
    for(int i=0;i<4;i++)if(mask&(1<<i)){
      Tile t{i};
      std::cout<<" "<<int(GetHouseBuildingStage(t))<<" "<<int(GetHouseConstructionTick(t))
        <<" "<<IsHouseCompleted(t)<<" "<<(IsHouseCompleted(t)?int(t.m5()):0);
    }
    std::cout<<" ;";
    for(int i:dirty)std::cout<<" "<<i;
    std::cout<<" ;";
    for(int i:populations)std::cout<<" "<<i;
    std::cout<<"\n";
  }
 }
}
"""
lua = r"""
local root="mods/luanttd_core/openttd/"
local B=dofile(root.."town_growth_build.lua")(dofile(root.."town_growth.lua"),{})
local specs={[0]={65},{3},{7},{11}}
for line in io.lines() do
  local mask,stage,counter,phase=line:match("(%d+) (%d+) (%d+) (%d+)")
  mask,stage,counter,phase=tonumber(mask),tonumber(stage),tonumber(counter),tonumber(phase)
  local parts,lookup={},{}
  for i=0,3 do if math.floor(mask/2^i)%2==1 then
    local p={id=i,stage=stage,counter=stage==3 and 0 or counter,completed=stage==3,age=stage==3 and 115 or nil,root=i==0}
    lookup[i]=p;parts[#parts+1]=p
  end end
  for tick=0,28 do
    local child=(phase+tick)%4
    if child~=0 and lookup[child] and not lookup[child].completed then
      assert(B.advance_house(lookup[child],parts,specs))
    end
    local before,dirty,popu={},{},{}
    for i,p in ipairs(parts) do before[i]=p.stage end
    local active=B.advance_house(lookup[0],parts,specs,function(p,pop)
      popu[#popu+1]=p.id;popu[#popu+1]=pop
    end)
    local row={active and 1 or 0}
    for i,p in ipairs(parts) do
      for _,a in ipairs{p.stage,p.counter,p.completed and 1 or 0,p.age or 0} do row[#row+1]=a end
      if p.stage~=before[i] then dirty[#dirty+1]=p.id end
    end
    print(table.concat(row," ").." ; "..table.concat(dirty," ").." ; "..table.concat(popu," "))
  end
end
"""
data = "".join(f"{mask} {stage} {counter} {phase}\n"
               for mask in (1,3,5,15) for stage in range(4)
               for counter in range(8) for phase in range(4))
with TemporaryDirectory() as d:
    cxx, exe, script = (Path(d) / name for name in ("ref.cpp", "ref", "lua"))
    cxx.write_text(cpp)
    script.write_text(lua)
    subprocess.run([os.environ.get("CXX", "c++"), "-std=c++20", "-O2", cxx, "-o", exe], check=True)
    a = subprocess.check_output([exe], text=True, input=data).splitlines()
    b = subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1", script], text=True, input=data).splitlines()
    assert len(a) == len(b) == 14848
    for i, (x, y) in enumerate(zip(a,b)):
        assert x.split() == y.split(), (i,x,y)
print(f"PASS {len(a)} RC1 house visits with identical physical stages, counters, completion population and dirty parts")
