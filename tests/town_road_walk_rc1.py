#!/usr/bin/env python3
"""Differential for exact RC1 town road traversal with controlled tile visits."""
from hashlib import sha256
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
import os
import subprocess
import sys

from rc1_rail_foundation_shim import source_block

src = Path(sys.argv[1]) / "src"
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert sha256((src / "town_cmd.cpp").read_bytes()).hexdigest() == (
    "9483d2c1b188f62241de9a4aef682db940592eb7bf0b40086c4af7b7da77a7e0"
)
cpp = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <vector>
using uint=unsigned;
using TileIndex=int;
using TownExpandModes=bool;
enum class DiagDirection {NE,SE,SW,NW,End};
bool IsValidDiagDirection(DiagDirection d){return d!=DiagDirection::End;}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((int(d)+2)%4);}
int TileOffsByDiagDir(DiagDirection d){return std::array{-1,64,1,-64}[int(d)];}
int TileAddByDiagDir(TileIndex t,DiagDirection d){return t+TileOffsByDiagDir(d);}
struct RoadBits{
 int n;
 bool Any()const{return n!=0;}
 bool None()const{return n==0;}
 bool Any(RoadBits v)const{return n&v.n;}
 RoadBits& Reset(RoadBits v){n&=~v.n;return *this;}
};
RoadBits DiagDirToRoadBits(DiagDirection d){return {8>>int(d)};}
enum class TileType{Void,Road,Station,TunnelBridge,House,Industry,Object,Clear,Trees,Railway,Water};
enum class TransportType{Road,Rail};
enum class RoadTramType{Road};
enum class TownLayout{Original,BetterRoads,Grid2x2,Grid3x3};
enum class GameMode{Normal,Editor};
enum class TownGrowthResult{Succeed,SearchStopped,Continue};
constexpr GameMode _game_mode=GameMode::Normal;
constexpr int OWNER_TOWN=1,OWNER_NONE=0;
struct Town{
 TownLayout layout;
 int index=1;
 struct{uint num_houses=0;}cache;
 static Town *GetByTile(TileIndex);
};
struct tile{
 int k=0,bits=0,foreign=0,inside=0,other_x=0,other_y=0;
};
struct Map{static int Size(){return 4096;}};
std::array<tile,4096> cells;
constexpr int center=32+32*64;
Town self,foreign;
auto &at(int i){assert(i>=0 && i<Map::Size());return cells[i];}
Town *Town::GetByTile(TileIndex i){return at(i).foreign ? &foreign : &self;}
TileType GetTileType(int i){
 return std::array{TileType::Void,TileType::Road,TileType::Clear,TileType::Water,TileType::House,
      TileType::Industry,TileType::Object,TileType::Station,TileType::Station,TileType::Road,
      TileType::TunnelBridge,TileType::TunnelBridge,TileType::Railway,TileType::Trees,
      TileType::TunnelBridge}[at(i).k];
}
bool IsTileType(int i,TileType t){return GetTileType(i)==t;}
bool IsValidTile(int i){return i>=0 && i<Map::Size() && at(i).k!=0;}
bool HasTileWaterGround(int i){return at(i).k==3;}
RoadBits GetTownRoadBits(int i){return {at(i).bits};}
bool IsDriveThroughStopTile(int i){return at(i).k==7;}
TransportType GetTunnelBridgeTransportType(int i){return at(i).k==14?TransportType::Rail:TransportType::Road;}
DiagDirection GetTunnelBridgeDirection(int i){return DiagDirection(at(i).inside);}
bool IsRoadDepot(int i){return at(i).k==9;}
bool HasTileRoadType(int i,RoadTramType){return at(i).bits!=0 || at(i).k==9;}
bool IsRoadOwner(int i,RoadTramType,int own){return (at(i).foreign ? OWNER_TOWN : OWNER_NONE)==own;}
void SetRoadOwner(int,RoadTramType,int){assert(false);}
void SetTownIndex(int,int){assert(false);}
bool TownAllowedToBuildRoads(TownExpandModes modes){return modes;}
uint32_t word,draws;
int stop_at,success_at,visits;
DiagDirection RandomRange(DiagDirection max){
 assert(max==DiagDirection::End && draws<100000);draws++;
 word=word*1664525u+1013904223u;
 return DiagDirection(word>>30);
}
TownGrowthResult GrowTownInTile(TileIndex *i,RoadBits,DiagDirection d,Town*,TownExpandModes){
 visits++;
 std::cout<<" "<<*i-center<<" "<<int(d);
 auto &q=at(*i);
 if(visits==success_at)return TownGrowthResult::Succeed;
 if(visits==stop_at)return TownGrowthResult::SearchStopped;
 if(q.k==10 || q.k==11)*i=center+q.other_x+64*q.other_y;
 return TownGrowthResult::Continue;
}
"""
for f in ("CanFollowRoad", "GrowTownAtRoad"):
    cpp += source_block(src, "town_cmd.cpp", rf"^static bool {f}\(")
cpp += r"""
int main(){
 int layout,roads,count,x,z;
 while(std::cin>>layout>>roads>>self.cache.num_houses>>word>>stop_at>>success_at>>count){
    cells.fill({});
    self.layout=TownLayout(layout);
    for(int k=0;k<count;k++){
        std::cin>>x>>z;auto &q=at(center+x+64*z);
        std::cin>>q.k>>q.bits>>q.foreign>>q.inside>>q.other_x>>q.other_y;
    }
    draws=visits=0;
    auto result=GrowTownAtRoad(&self,center,roads);
    std::cout<<" "<<result<<" "<<draws<<"\n";
 }
}
"""
program = r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local B=dofile(p.."town_growth_build.lua")(G,{})
local kind={[0]="void","road","clear","water","house","industry","object",
 "drive_stop","bay_stop","depot","bridge","tunnel","rail","trees","rail_portal"}
for line in io.lines() do
  local a={}
  for v in line:gmatch("%S+") do a[#a+1]=tonumber(v) end
  local layout,roads,n,word,stop_at,success_at=unpack(a)
  local cells={}
  for i=8,#a,8 do
    local x,z,k,bits,foreign,inside,u,v=unpack(a,i,i+7)
    cells[x+64*z]={kind=kind[k],road_bits=bits,road_town=foreign==1 and 2 or nil,
      inside=(k==10 or k==11) and inside or nil,other_x=u,other_z=v}
  end
  local t=G.new(1,0,0,{num_houses=n,layout=({"original","better","grid2","grid3"})[layout+1]})
  local trace,draws,visits={},0,0
  local tile=function(x,z) return cells[x+64*z] or {kind="void"} end
  local plan=B.walk(t,{tile=tile},0,0,roads==1,function()
    word=(word*1664525+1013904223)%4294967296
    draws=draws+1
    assert(draws<100000)
    return word
  end,function(_,_,x,z,q,_,d)
    visits=visits+1
    trace[#trace+1]=x+64*z;trace[#trace+1]=d or 4
    if visits==success_at then return true end
    if visits==stop_at then return nil,true end
    if q.inside~=nil then return nil,false,false,q.other_x,q.other_z end
  end)
  trace[#trace+1]=plan and 1 or 0
  trace[#trace+1]=draws
  print(table.concat(trace," "))
end
"""
rand=Random(16004)
inputs=[]
for i in range(3200):
    cells={}
    for z in range(-4,5):
        for x in range(-4,5):
            k=rand.choice([1]*9+[0,2,3,4,5,6,7,8,9,12,13,14])
            bits=rand.randrange(16) if k==1 else rand.choice([5,10]) if k==7 else 0
            cells[x,z]=[k,bits,int(k==1 and rand.random()<.12),0,0,0]
    cells[0,0]=[1,rand.randrange(1,16),int(i%4==0),0,0,0]
    if i%4==1:
        # Portals at either end; also test a portal as the starting tile.
        cells[0,0]=[10,10,0,2,2,0]
        cells[2,0]=[11,10,0,0,0,0]
        cells[3,0]=[1,10,int(i%3==0),0,0,0]
    elif i%4==2:
        for x,z,rb in ((0,0,6),(1,0,12),(1,1,9),(0,1,3)):
            cells[x,z]=[1,rb,0,0,0,0]
    inputs.append([i%4,(i//4)%2,rand.randrange(64),rand.getrandbits(32),
        rand.choice([0,0,0,1,3]),rand.choice([0,0,0,2,5]),len(cells),
        *(v for (x,z),cell in cells.items() for v in (x,z,*cell))])
data="".join(" ".join(map(str,row))+"\n" for row in inputs)
with TemporaryDirectory(prefix="town-road-walk-") as d:
    d=Path(d)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    a,b=[subprocess.check_output(cmd,input=data,text=True).splitlines() for cmd in ([d/"ref"],[lua,d/"test.lua"])]
    assert len(a)==len(b)==len(inputs)
    differences=[(i,x,y) for i,(x,y) in enumerate(zip(a,b)) if x.split()!=y.split()]
    assert not differences,(len(differences),differences[:12])
print(f"PASS {len(inputs)} RC1 town road traces (ordered visited tiles, headings, result and RNG draws)")
