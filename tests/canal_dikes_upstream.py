#!/usr/bin/env python3
"""Compile the actual 16.0-RC1 water-edge functions and compare to Lua."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from rc1_rail_foundation_shim import source_block

p=argparse.ArgumentParser(description=__doc__)
p.add_argument("source",type=Path)
p.add_argument("--lua",default="lua5.1")
a=p.parse_args()

namespace=r"""
#include <array>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
using SpriteID=int;
enum class TileType { Clear, Water, Railway, Station, Industry, Object, TunnelBridge, Void };
enum class WaterTileType {Clear,Depot,ClearRocks,Lock,Coast,CoastRocks};
enum class Direction {N,NE,E,SE,S,SW,W,NW};
enum class TransportType {Road,Water};
enum class RailGroundType {Normal,HalfTileWater};
enum class CanalFeature {Dikes,RiverEdge};
#define NOT_REACHED() __builtin_unreachable()
#define assert(X) do { if (!(X)) std::abort(); } while (0)
enum {SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SPR_CANAL_DIKES_BASE=100};
struct Tile { int kind=0, slope=0, dir=0, wet=0, industry=0; };
std::array<Tile,49> map;
TileIndex TileAddXY(TileIndex tile,int x,int z){return tile+x+7*z;}
int TileOffsByDir(Direction d){
    // From N is (-1,-1), E=(-1,+1), S=(+1,+1), W=(+1,-1)
    constexpr int stock[]={-8,-1,6,7,8,1,-6,-7};
    return stock[int(d)];
}
TileType GetTileType(TileIndex t){
    constexpr TileType types[]={TileType::Clear,TileType::Water,TileType::Water,TileType::Water,
      TileType::Water,TileType::Water,TileType::Water,TileType::Railway,TileType::Station,TileType::Industry,
      TileType::Object,TileType::Station,TileType::Station,TileType::TunnelBridge,TileType::Void,
      TileType::Railway,TileType::Station,TileType::TunnelBridge};
    return types[map[t].kind];
}
bool IsTileType(TileIndex t,TileType k){return GetTileType(t)==k;}
WaterTileType GetWaterTileType(TileIndex t){return WaterTileType(map[t].kind-1);}
RailGroundType GetRailGroundType(TileIndex t){return map[t].kind==7 ? RailGroundType::HalfTileWater : RailGroundType::Normal;}
bool IsPlainRail(TileIndex){return true;}
int GetTileSlope(TileIndex t){return map[t].slope;}
bool IsTileFlat(TileIndex t){return map[t].slope==0;}
bool IsOilRig(TileIndex t){return map[t].kind==8;}
bool IsDock(TileIndex t){return map[t].kind==11;}
bool IsBuoy(TileIndex t){return map[t].kind==12;}
bool IsTileOnWater(TileIndex t){return map[t].wet;}
int GetIndustryIndex(TileIndex t){return map[t].industry;}
int GetLockDirection(TileIndex t){return map[t].dir;}
int GetTunnelBridgeDirection(TileIndex t){return map[t].dir;}
int ReverseDiagDir(int d){return (d+2)%4;}
int DirToDiagDir(Direction d){return int(d)/2;}
int DiagDirToAxis(int d){return d%2;}
TransportType GetTunnelBridgeTransportType(TileIndex t){return map[t].kind==13?TransportType::Water:TransportType::Road;}
int GetCanalSprite(CanalFeature,TileIndex){return 0;}
int mask=0;
void DrawWaterSprite(SpriteID,uint offset,CanalFeature,TileIndex){mask|=1<<offset;}
"""
witness=r"""
int main(){
  constexpr int positions[]={-1,7,1,-7,6,8,-6,-8};
  for(int wet=0;wet<256;wet++){
    for(int i=0;i<8;i++)map[24+positions[i]].kind=(wet>>i)&1;
    mask=0;
    DrawWaterEdges(true,0,24);
    std::cout<<"m "<<wet<<' '<<mask<<'\n';
  }
  for(int k=0;k<18;k++)for(int slope=0;slope<32;slope++)
  for(int dir=0;dir<4;dir++)for(int wet=0;wet<2;wet++)
  for(int source:{0,8,9})for(int same=0;same<2;same++)for(int from=0;from<8;from++){
    map[24]=Tile{k,slope,dir,wet,42};
    map[24+TileOffsByDir(Direction(from))]=Tile{source,0,0,0,same?42:24};
    std::cout<<"w "<<k<<' '<<slope<<' '<<dir<<' '<<wet<<' '<<source<<' '<<same<<' '<<from
      <<' '<<IsWateredTile(24,Direction(from))<<'\n';
  }
}
"""
lua=r"""
local D=dofile("mods/luanttd_core/openttd/canal_dikes.lua")
local kind={[0]="dry","clear_water","depot","water_rocks","lock","coast","coast_rocks","half_rail",
  "oilrig","industry","object","dock","buoy","aqueduct","void","dry","dry","dry"}
local n=0
for line in io.lines() do
  local row={}
  for v in line:gmatch("%d+") do row[#row+1]=tonumber(v) end
  if line:sub(1,1)=="m" then
    local cells={["-1,0"]=0,["0,1"]=1,["1,0"]=2,["0,-1"]=3,["-1,1"]=4,["1,1"]=5,["1,-1"]=6,["-1,-1"]=7}
    assert(D.edges(function(dx,dz) return math.floor(row[1]/2^cells[dx..","..dz])%2==1 end)==row[2],line)
  else
    local k,slope,dir,wet,src,same,from,expected=unpack(row)
    local got=D.watered({kind=kind[k],slope=slope,dir=dir,on_water=wet==1,industry=42},from,
      {kind=kind[src],industry=same==1 and 42 or 24})
    assert(got==(expected==1),line)
  end
  n=n+1
end
print(("PASS %d compiled RC1 water-edge masks and neighbor/source decisions"):format(n))
"""
with tempfile.TemporaryDirectory() as d:
    here=Path(d)
    cpp=here/"stock.cpp"
    cpp.write_text(namespace+source_block(a.source/"src","water_cmd.cpp","^bool IsWateredTile")
        +source_block(a.source/"src","water_cmd.cpp","^static void DrawWaterEdges")+witness)
    binary=here/"stock"
    subprocess.run(["c++","-O2","-std=c++17",cpp,"-o",binary],check=True)
    script=here/"compare.lua"
    script.write_text(lua)
    subprocess.run([a.lua,script],input=subprocess.check_output([binary]),check=True)
