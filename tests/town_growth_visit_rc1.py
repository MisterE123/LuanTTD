#!/usr/bin/env python3
"""Compare compiled RC1 growth decisions on identical, controlled town boards.

The town functions are unmodified. The host commands are deterministic
adapters: house/road bits persist between attempts, while terrain quote
outcomes are controlled by the fixture. This is not a whole-game replay.
"""
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
import os
import subprocess
import sys

from rc1_rail_foundation_shim import source_block

root=Path(sys.argv[1])
assert subprocess.check_output(["git","-C",root,"rev-parse","HEAD"],text=True).strip()=="07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src=root/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"

cpp=r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
using TownExpandModes=bool;
#define NOT_REACHED() std::abort()
template<class E> constexpr int to_underlying(E a){return int(a);}
enum class DiagDirection {NE,SE,SW,NW,End};
enum class DiagDirDiff {Right90=1,Left90=3};
enum class Direction {N,E,S,W};
enum class TileType {Clear,Road,House,Void,Water,Railway,TunnelBridge,Industry,Object,Station};
enum class RoadTramType{Road};
enum class GameMode{Normal,Editor};
constexpr GameMode _game_mode=GameMode::Normal;
constexpr int OWNER_TOWN=1,OWNER_NONE=0;
enum class TransportType {Road,Rail};
enum class TownLayout{Original,BetterRoads,Grid2x2,Grid3x3};
enum class TownGrowthResult {Continue,SearchStopped,Succeed};
constexpr int center=32+32*64;
struct Map {static int Size(){return 4096;}};
struct Town {
 int xy=center;TownLayout layout;
 int index=1;
 struct{uint num_houses=0;}cache;
 static Town *GetByTile(int){return nullptr;}
};
struct TileIndexDiffC {int x,y;};
TileIndexDiffC TileIndexToTileIndexDiffC(int a,int b){return {a%64-b%64,a/64-b/64};}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((int(d)+2)%4);}
DiagDirection ChangeDiagDir(DiagDirection d,DiagDirDiff diff){return DiagDirection((int(d)+int(diff))%4);}
int TileAddByDiagDir(int tile,DiagDirection d){return tile+std::array<int,4>{-1,64,1,-64}[int(d)];}
int TileAddByDir(int tile,Direction d){return tile+std::array<int,4>{-65,63,65,-63}[int(d)];}
auto EnumRange(DiagDirection){return std::array{DiagDirection::NE,DiagDirection::SE,DiagDirection::SW,DiagDirection::NW};}
enum class RoadBit {NW,SW,SE,NE};
struct RoadBits {
    uint bits=0;
    constexpr RoadBits()=default;
    constexpr RoadBits(uint n):bits(n){}
    constexpr RoadBits(RoadBit b):bits(1u<<int(b)){}
    constexpr RoadBits(std::initializer_list<RoadBit> b){for(auto v:b)bits|=1u<<int(v);}
    constexpr uint base()const{return bits;}
    bool None()const{return !bits;}
    bool Any()const{return bits!=0;}
    bool Any(RoadBits b)const{return bits&b.bits;}
    void Set(RoadBits b){bits|=b.bits;}
    RoadBits& Reset(RoadBits b){bits&=~b.bits;return *this;}
    bool operator==(RoadBits b)const{return bits==b.bits;}
};
RoadBits operator&(RoadBits a,RoadBits b){return a.bits&b.bits;}
RoadBits operator|(RoadBits a,RoadBits b){return a.bits|b.bits;}
RoadBits operator|(RoadBits a,RoadBit b){return a|RoadBits{b};}
RoadBits DiagDirToRoadBits(DiagDirection d){return 8u>>int(d);}
constexpr RoadBits ROAD_X=10,ROAD_Y=5,ROAD_N=9,ROAD_E=12,ROAD_S=6,ROAD_W=3,ROAD_ALL=15;
struct Row{int k=0,slope=0,house=0,road=0,allow=0,house_type=1,rb=0;};
std::array<Row,4096> cells;
auto &cell(int i){assert(i>=0 && i<Map::Size());return cells[i];}
auto GetTileType(int i){return TileType(cell(i).k);}
bool IsTileType(int i,TileType t){return GetTileType(i)==t;}
bool IsValidTile(int i){return i>=0 && i<Map::Size() && GetTileType(i)!=TileType::Void;}
bool HasTileWaterGround(int i){return GetTileType(i)==TileType::Water;}
int GetTileSlope(int i){return cell(i).slope;}
struct Settings{struct{bool allow_town_level_crossings;} economy;struct{bool build_on_slopes;} construction;} _settings_game;
uint32_t word,draws;
uint32_t Random(){draws++;assert(draws<10000);return word=word*1664525u+1013904223u;}
DiagDirection RandomRange(DiagDirection d){assert(d==DiagDirection::End);return DiagDirection(Random()>>30);}
bool Chance16(int a,int b){return (((Random()&0xffff)*b+b/2)>>16)<uint(a);}
bool TownAllowedToBuildRoads(TownExpandModes b){return b;}
bool TownCanGrowRoad(int){return true;}
bool RoadTypesAllowHouseHere(int i){return cell(i).house_type!=0;}
bool IsRoadAllowedHere(Town*,int i,DiagDirection){return cell(i).allow;}
int DistanceFromEdge(int i){return i%64==0 || i/64==0 || i%64==63 || i/64==63 ? 0 : 1;}
TransportType GetTunnelBridgeTransportType(int){return TransportType::Road;}
int GetOtherTunnelBridgeEnd(int i){return i+2;}
int TileOffsByDiagDir(DiagDirection d){return TileAddByDiagDir(0,d);}
bool IsValidDiagDirection(DiagDirection d){return d!=DiagDirection::End;}
DiagDirection GetTunnelBridgeDirection(int){return DiagDirection::SW;}
bool IsDriveThroughStopTile(int){return false;}
bool IsRoadDepot(int){return false;}
bool HasTileRoadType(int,RoadTramType){return true;}
bool IsRoadOwner(int,RoadTramType,int){return false;}
void SetRoadOwner(int,RoadTramType,int){assert(false);}
void SetTownIndex(int,int){assert(false);}
RoadBits GetTownRoadBits(int i){return {uint(cell(i).rb)};}
bool TryBuildTownHouse(Town*t,int i,TownExpandModes){
 std::cout<<" "<<(i-center)<<" ";
 if(cell(i).house){
   std::cout<<"1";cell(i).house=0;cell(i).k=int(TileType::House);t->cache.num_houses++;
   return true;
 }
 std::cout<<"0";return false;
}
void LevelTownLand(int i){std::cout<<" "<<(i-center)<<" 2";}
RoadBits CleanUpRoadBits(int,RoadBits b){return b;}
bool GrowTownWithBridge(Town*,int,DiagDirection){return false;}
bool GrowTownWithTunnel(Town*,int,DiagDirection){return false;}
bool GrowTownWithRoad(Town*,int i,RoadBits b){
 if(IsTileType(i,TileType::TunnelBridge))return false;
 std::cout<<" "<<(i-center)<<" "<<(b.bits+3);
 auto &c=cell(i);
 if(!c.road)return false;
 c.rb|=b.bits;c.k=int(TileType::Road);return true;
}
"""
cpp+=source_block(src,"slope_type.h",r"^enum class Corner :")
cpp+=source_block(src,"slope_type.h",r"^enum Slope :")
for f,t in [("GetTownRoadGridElement","RoadBits"),("GrowTownWithExtraHouse","bool"),("GrowTownInTile","TownGrowthResult"),("CanFollowRoad","bool"),("GrowTownAtRoad","bool")]:
    cpp+=source_block(src,"town_cmd.cpp",rf"^static {t} {f}\([^;\n]*\)\n")
cpp+=r"""
int main(){
 int dx,dz,layout,roads,incoming,mask,grade,cross,count,x,z;
 while(std::cin>>dx>>dz>>layout>>roads>>incoming>>mask>>grade>>cross>>word>>count){
   cells.fill(Row{});
   _settings_game.economy.allow_town_level_crossings=cross;
   _settings_game.construction.build_on_slopes=grade;
   for(int i=0;i<count;i++){
     std::cin>>x>>z;auto &r=cell(center+x+64*z);
     std::cin>>r.k>>r.slope>>r.house>>r.road>>r.allow>>r.house_type>>r.rb;
   }
   Town t{center,TownLayout(layout)};
   TileIndex tile=center+dx+64*dz;
   draws=0;
   if(incoming==5){
     for(int n=0;n<12;n++){
       auto result=GrowTownAtRoad(&t,tile,roads);
       std::cout<<" 900 "<<result<<" "<<draws<<" "<<t.cache.num_houses;
     }
     std::cout<<" 901";
     for(int z=-5;z<=5;z++)for(int x=-5;x<=5;x++){
       auto &q=cell(center+x+64*z);std::cout<<" "<<q.k*16+q.rb;
     }
     std::cout<<"\n";
   }else{
     auto result=GrowTownInTile(&tile,mask,DiagDirection(incoming),&t,roads);
     std::cout<<" "<<int(result)<<" "<<draws<<" "<<tile-center<<"\n";
   }
 }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local B=dofile(p.."town_growth_build.lua")(G,{})
local kinds={[0]="clear","road","house","void","water","rail","bridge"}
local code={}
for i,k in pairs(kinds) do code[k]=i end
for line in io.lines() do
 local a={}
 for w in line:gmatch("%S+") do a[#a+1]=tonumber(w) end
 local dx,dz,layout,roads,heading,mask,grade,cross,word=unpack(a)
 local cells,trace={},{}
 for i=11,#a,9 do
   local x,z,k,slope,house,road,allow,ht,rb=unpack(a,i,i+8)
   cells[x+64*z]={kind=kinds[k],slope=slope,house=house==1,road=road==1,allow=allow==1,house_type=ht==1,road_bits=rb,
                   inside=k==6 and 2 or nil,other_x=x+2,other_z=z}
 end
 local function tile(x,z) return cells[x+64*z] or {kind="clear",slope=0,house_type=true} end
 local function event(i,v) trace[#trace+1]=i;trace[#trace+1]=v end
 local board={tile=tile,clean_road_bits=function(_,_,_,b) return b end,
   level_land=function(x,z) event(x+64*z,2) end,
   road_allowed=function(_,x,z) return tile(x,z).allow end,
   house_roadtypes=function(x,z) return tile(x,z).house_type end,
   distance_to_edge=function() return 1 end,
   road_quote=function(_,x,z,b) event(x+64*z,b+3);if tile(x,z).road then return true end end}
 B.house=function(_,_,x,z)
   local good=tile(x,z).house
   event(x+64*z,good and 1 or 0)
   if good then return {kind="house",x=x,z=z} end
 end
 local t=G.new(1,0,0,{layout=({"original","better","grid2","grid3"})[layout+1]})
 local function apply(plan)
   if not plan then return false end
   local q=tile(plan.x,plan.z)
   if plan.kind=="house" then q.kind,q.house="house",false; t.num_houses=t.num_houses+1
   elseif plan.kind=="road" then
     local old=q.road_bits or 0
     for _,bit in ipairs{1,2,4,8} do
       if math.floor(plan.bits/bit)%2==1 and math.floor(old/bit)%2==0 then old=old+bit end
     end
     q.road_bits,q.kind=old,"road"
   end
   return true
 end
 local draws=0
 local function random() word=(word*1664525+1013904223)%4294967296;draws=draws+1;return word end
 local opts={allow_roads=roads==1,build_on_slopes=grade==1,allow_level_crossings=cross==1,extra_house=apply}
 if heading==5 then
   for _=1,12 do
     local plan,extra=B.walk(t,board,dx,dz,opts.allow_roads,random,function(t,b,x,z,q,rb,from,rand)
       return B.visit(t,b,x,z,q,rb,from,opts,rand)
     end)
     local result=apply(plan) or extra
     trace[#trace+1]=900;trace[#trace+1]=result and 1 or 0
     trace[#trace+1]=draws;trace[#trace+1]=t.num_houses
   end
   trace[#trace+1]=901
   for z=-5,5 do for x=-5,5 do
     local q=tile(x,z)
     trace[#trace+1]=16*code[q.kind]+q.road_bits
   end end
 else
   local plan,stop,extra,u,v=B.visit(t,board,dx,dz,tile(dx,dz),mask,heading<4 and heading or nil,opts,random)
   trace[#trace+1]=(plan or extra) and 2 or stop and 1 or 0
   trace[#trace+1]=draws
   trace[#trace+1]=u and u+v*64 or dx+64*dz
 end
 print(table.concat(trace," "))
end
"""
rng=Random(16005)
cases=[]
for i in range(6000):
    kind=rng.choice([0,1,1,1,1,5,6])
    dx,dz=rng.randrange(-1,2),rng.randrange(-1,2)
    bits=rng.randrange(1,16) if kind==1 else 10 if kind==6 else 0
    heading=rng.randrange(5 if bits else 4)
    cells=[]
    for x in range(-4,5):
        for z in range(-4,5):
            k=kind if (x,z)==(dx,dz) else rng.choice([0,0,0,0,1,2,2,3,4])
            cells.extend([x,z,k,rng.choice([0,1,2,3,4,5,6,7,8,9,11,12,13,14,23,27,29,30]),
                int(k==0 and rng.randrange(2)==0),int(k in (0,1,5) and rng.randrange(2)==0),
                int(k in (0,1,5) and rng.randrange(3)!=0),int(k in (0,1,2,5,6) or rng.randrange(2)==0),0])
    cases.append([dx,dz,rng.randrange(4),rng.randrange(2),heading,bits,rng.randrange(2),rng.randrange(2),
                  rng.getrandbits(32),len(cells)//9,*cells])
for i in range(800):
    cells=[]
    for z in range(-5,6):
        for x in range(-5,6):
            road=z==0 and -3<=x<=3 or x==0 and -3<=z<=3
            k=1 if road else 3 if abs(x)==5 or abs(z)==5 else rng.choice([0,0,0,0,2,4])
            bits=(10 if z==0 else 0)+(5 if x==0 else 0) if road else 0
            cells.extend([x,z,k,0,int(k==0 and rng.randrange(2)==0),int(k in (0,1)),
                         int(k in (0,1)),1,bits])
    cases.append([0,0,i%4,int(i%3!=0),5,15,1,1,rng.getrandbits(32),len(cells)//9,*cells])
data="".join(" ".join(map(str,r))+"\n" for r in cases)
with TemporaryDirectory(prefix="town-growth-visit-rc1-") as d:
    d=Path(d)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    a,b=[subprocess.check_output(cmd,input=data,text=True).splitlines() for cmd in ([d/"ref"],[lua,d/"test.lua"])]
    assert len(a)==len(b)==len(cases)
    errors=[(i,cases[i][:10],x,y) for i,(x,y) in enumerate(zip(a,b)) if x.split()!=y.split()]
    assert not errors,(len(errors),errors[:8])
print("PASS 6000 RC1 town visits and 800 twelve-attempt consecutive town-growth traces")
