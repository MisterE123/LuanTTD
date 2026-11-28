#!/usr/bin/env python3
"""Differential for vanilla RC1 location, nearest-town admission and conflicts."""
from hashlib import sha256
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
import subprocess
import sys
from rc1_rail_foundation_shim import source_block

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
assert sha256((src/"industry_cmd.cpp").read_bytes()).hexdigest()=="1e6bc18f0c26e56f2c50bad4c9e1039174ad2da7b404750ce688dcea2b10c752"
assert sha256((src/"map.cpp").read_bytes()).hexdigest()=="1562ab2110a9611bcaaf20df6b771433c962fa5b3c75b9704263c021abe946ea"
cpp=r"""
#include <cassert>
#include <climits>
#include <algorithm>
#include <iostream>
#include <vector>
using uint=unsigned;using TileIndex=uint;using IndustryType=uint;using IndustryID=uint;
enum class LandscapeType {Temperate,Arctic,Tropic,Toyland};
enum class GameMode {Normal,Editor};
enum class TropicZone {Normal,Desert,Rainforest};
enum class DiagDirection {NE,NW,SW,SE};
enum class IndustryBehaviour {Town1200More,OnlyNearTown};
constexpr int STR_ERROR_FOREST_CAN_ONLY_BE_PLANTED=1,STR_ERROR_SITE_UNSUITABLE=2,
  STR_ERROR_CAN_ONLY_BE_BUILT_IN_DESERT=3,STR_ERROR_CAN_ONLY_BE_BUILT_IN_RAINFOREST=4,
  STR_ERROR_CAN_ONLY_BE_BUILT_IN_LOW_AREAS=5,STR_ERROR_CAN_ONLY_BE_POSITIONED=6,
  STR_ERROR_ONLY_ONE_ALLOWED_PER_TOWN=7,STR_ERROR_CAN_ONLY_BE_BUILT_IN_TOWNS_WITH_POPULATION_OF_1200=8,
  STR_ERROR_CAN_ONLY_BE_BUILT_NEAR_TOWN_CENTER=9,STR_ERROR_INDUSTRY_TOO_CLOSE=10;
struct CommandCost {int err=0;CommandCost()=default;CommandCost(int e):err(e){}bool Failed()const{return err!=0;}};
#define NOT_REACHED() __builtin_unreachable()
struct Map {
 static inline uint w,h;
 static uint SizeX(){return w;}static uint SizeY(){return h;}
 static uint MaxX(){return w-1;}static uint MaxY(){return h-1;}
};
struct {
 struct {bool freeform_edges;} construction;
 struct {LandscapeType landscape;uint oil_refinery_limit;} game_creation;
 struct {bool multiple_industry_per_town;} economy;
} _settings_game;
GameMode _game_mode;
bool _ignore_industry_restrictions;
uint TileX(TileIndex t){return t%Map::w;}
uint TileY(TileIndex t){return t/Map::w;}
TileIndex TileAddXY(TileIndex t,int x,int z){return (t+z*Map::w+x)%(Map::w*Map::h);}
int base,north,snow,zone;
int GetTileZ(TileIndex){return base;}
int TileHeight(TileIndex){return north;}
uint HighestSnowLine(){return snow;}
TropicZone GetTropicZone(TileIndex){return TropicZone(zone);}
uint DistanceMax(TileIndex a,TileIndex b){return std::max(std::abs(int(TileX(a))-int(TileX(b))),std::abs(int(TileY(a))-int(TileY(b))));}
struct Town {TileIndex xy;struct{uint population;}cache;};
Town t1,t2;
Town *ClosestTownFromTile(TileIndex,uint){return &t1;}
struct Flags {uint v;bool Test(IndustryBehaviour b)const{return v&(1u<<uint(b));}};
constexpr int IT_INVALID=255;
struct IndustrySpec {std::vector<IndustryType> conflicting;Flags behaviour;};
IndustrySpec spec;
const IndustrySpec* GetIndustrySpec(IndustryType){return &spec;}
struct Industry {
 Town *town;struct{TileIndex tile;}location;
 static inline std::vector<IndustryID> industries[4]={};
 static const Industry* Get(IndustryID);
};
Industry neighbor;
const Industry* Industry::Get(IndustryID){return &neighbor;}
"""
cpp+=source_block(src,"map.cpp",r"^uint DistanceFromEdgeDir\(")
names=("None","Forest","OilRefinery","Farm","Plantation","Water","Lumbermill","BubbleGen","OilRig")
for n in names[:2]+("ScaledDistanceFromEdge",)+names[2:]:
    pat=r"^static bool CheckScaledDistanceFromEdge\(" if n=="ScaledDistanceFromEdge" else rf"^static CommandCost CheckNewIndustry_{n}\("
    cpp+=source_block(src,"industry_cmd.cpp",pat)+"\n"
for n in ("FindTownForIndustry","CheckIfIndustryIsAllowed","CheckIfFarEnoughFromConflictingIndustry"):
    cpp+=source_block(src,"industry_cmd.cpp",rf"^static CommandCost {n}\(")+"\n"
cpp+=r"""
int main(){
  using H=CommandCost(*)(TileIndex);
  H fn[]={CheckNewIndustry_None,CheckNewIndustry_Forest,CheckNewIndustry_OilRefinery,CheckNewIndustry_Farm,
    CheckNewIndustry_Plantation,CheckNewIndustry_Water,CheckNewIndustry_Lumbermill,CheckNewIndustry_BubbleGen,CheckNewIndustry_OilRig};
  uint kind,c,e,i,f,x,z,dx,dz,k,near,same,multiple,pop,lim,flags;
  while(std::cin>>kind>>c>>e>>i>>f>>Map::w>>Map::h>>x>>z>>base>>north>>zone>>snow>>lim
        >>pop>>dx>>dz>>k>>near>>same>>multiple>>flags){
    _settings_game.game_creation={LandscapeType(c),lim};
    _settings_game.construction.freeform_edges=f;
    _settings_game.economy.multiple_industry_per_town=multiple;
    _game_mode=e?GameMode::Editor:GameMode::Normal;
    _ignore_industry_restrictions=i;
    t1={TileAddXY(0,dx,dz),{pop}};
    for(auto &v:Industry::industries)v.clear();
    spec={{2,IT_INVALID},{flags}};
    neighbor={same?&t1:&t2,{near?TileAddXY(0,dx,dz):TileAddXY(0,dx,z)}};
    Industry::industries[k].push_back(0);
    auto tile=TileAddXY(0,x,z);
    Town *host;
    auto town=FindTownForIndustry(tile,1,&host);
    if(!town.Failed())town=CheckIfIndustryIsAllowed(tile,1,host);
    std::cout<<fn[kind](tile).err<<' '<<town.err<<' '<<CheckIfFarEnoughFromConflictingIndustry(tile,1).err<<'\n';
  }
}
"""
lua=r"""
local A=dofile("mods/luanttd_core/openttd/industry_admission_rc1.lua")
local names={"None","Forest","Refinery","Farm","Plantation","Water","Lumbermill","BubbleGen","OilRig"}
local reasons={FOREST_CAN_ONLY_BE_PLANTED=1,SITE_UNSUITABLE=2,CAN_ONLY_BE_BUILT_IN_DESERT=3,
 CAN_ONLY_BE_BUILT_IN_RAINFOREST=4,CAN_ONLY_BE_BUILT_IN_LOW_AREAS=5,CAN_ONLY_BE_POSITIONED=6,
 ONLY_ONE_ALLOWED_PER_TOWN=7,CAN_ONLY_BE_BUILT_IN_TOWNS_WITH_POPULATION_OF_1200=8,
 CAN_ONLY_BE_BUILT_NEAR_TOWN_CENTER=9,INDUSTRY_TOO_CLOSE=10}
local function code(ok,why) if ok then return 0 end;return assert(reasons[why]) end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local kind,c,e,i,f,w,h,x,z,base,north,zone,snow,lim,pop,u,v,k,near,same,multiple,flags=unpack(a)
  local opts={landscape=({"temperate","arctic","tropic","toyland"})[c+1],
    width=w,height=h,editor=e==1,ignore=i==1,freeform=f==1,oil_refinery_limit=lim,highest_snowline=snow}
  local spec={id=1,conflicts={2},behavior={Town1200More=flags%2==1,OnlyNearTown=flags>=2}}
  local other={{type=k,x=u,z=near==1 and v or z,town=same==1 and 1 or 2}}
  print(code(A.anchor(names[kind+1],x,z,{base=base,north=north,zone=zone},opts)),
    code(A.town(spec,x,z,{id=1,x=u,z=v,population=pop},other,multiple==1)),code(A.conflicts(spec,x,z,other)))
end
"""
rand=Random(16013)
rows=[]
for kind in range(9):
    for _ in range(1200):
        w,h=(rand.choice((64,128,256,512,1024,2048,4096)) for _ in range(2))
        x,z=rand.randrange(w),rand.randrange(h)
        u,v=max(0,min(w-1,x+rand.randrange(-18,19))),max(0,min(h-1,z+rand.randrange(-18,19)))
        rows.append((kind,rand.randrange(4),rand.randrange(2),rand.randrange(2),rand.randrange(2),w,h,x,z,
                     rand.randrange(32),rand.randrange(4),rand.randrange(3),rand.randrange(32),rand.randrange(65),
                     rand.choice((1199,1200,1201,430,3000)),u,v,rand.choice((1,2)),rand.randrange(2),rand.randrange(2),
                     rand.randrange(2),rand.randrange(4)))
inp="\n".join(" ".join(map(str,r)) for r in rows)+"\n"
with TemporaryDirectory(prefix="industry-admission-rc1-") as d:
    p=Path(d)
    (p/"compiled.cc").write_text(cpp)
    (p/"test.lua").write_text(lua)
    subprocess.run(["c++","-std=c++20","-O2",p/"compiled.cc","-o",p/"compiled"],check=True)
    ref=subprocess.check_output([p/"compiled"],text=True,input=inp).splitlines()
    got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"test.lua"],cwd=root,text=True,input=inp).splitlines()
assert len(got)==len(ref)==len(rows)
for r,a,b in zip(rows,ref,got):
    assert a.split()==b.split(),(r,a,b)
print(f"PASS {len(rows)} exact RC1 industry geography, town and separation cases")
