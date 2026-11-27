#!/usr/bin/env python3
"""OpenTTD 16.0-RC1 initial town count, city allocation and site admission."""
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
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
#include <ranges>
#include <set>
#include <string>
#include <vector>
using uint=unsigned;
using TileIndex=int;
enum class TownLayout{Original,Grid2,Grid3};
enum class TownSize{Random};
enum class GenWorldProgress{Towns};
enum class WarningLevel{Critical};
enum class GameMode{Normal,Editor};
constexpr GameMode _game_mode=GameMode::Normal;
constexpr uint CUSTOM_TOWN_NUMBER_DIFFICULTY=4;
constexpr uint STR_ERROR_COULD_NOT_CREATE_TOWN=10,STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP=1,
    STR_ERROR_TOO_CLOSE_TO_ANOTHER_TOWN=2,STR_ERROR_SITE_UNSUITABLE=3;
struct TownPool{static constexpr uint MAX_SIZE=64000;};
struct Town{
  int x,z;bool city;
  std::string GetCachedName()const{return "T";}
  static const std::vector<Town*>& Iterate(){static std::vector<Town*> empty;return empty;}
  static int GetNumItems(){return 0;}
};
using TownNames=std::set<std::string>;
struct Settings{
 struct{uint number_towns;}difficulty;
 struct{int larger_towns,town_min_distance;}economy;
 struct{uint custom_town_number;}game_creation;
 struct{bool freeform_edges;}construction;
} _settings_game,_settings_newgame;
int mode;
uint word,draws,serial,water_count;
uint Random(){draws++;return word=word*1664525u+1013904223u;}
int _random;
uint CeilDiv(uint a,uint b){return (a+b-1)/b;}
template<class T> T Clamp(T n,T lo,T hi){return std::clamp(n,lo,hi);}
struct Map{
 inline static uint w,h,size,initial_land_count;
 static uint SizeX(){return w;}
 static uint SizeY(){return h;}
 static uint MaxX(){return w-1;}
 static uint MaxY(){return h-1;}
 static uint LogX(){return __builtin_ctz(w);}
 static uint LogY(){return __builtin_ctz(h);}
 static auto Iterate(){return std::views::iota(0,int(size));}
 static void CountLandTiles();
"""
for f in ("ScaleBySize","ScaleByLandProportion"):
    cpp+=source_block(src,"map_func.h",rf"^\s*static inline uint {f}\(")
cpp+=r"""
};
bool IsWaterTile(int tile){return uint(tile)<water_count;}
int X(int i){return i%Map::w;}
int Z(int i){return i/Map::w;}
int at(int x,int z){return x+Map::w*z;}
int DistanceFromEdge(int i){return std::min({X(i),Z(i),int(Map::w)-1-X(i),int(Map::h)-1-Z(i)});}
std::vector<Town> cities;
int test_x,test_z,nearx,nearz;
bool IsCloseToTown(int tile,int d){
  if(mode!=0 && std::abs(nearx-X(tile))+std::abs(nearz-Z(tile))<d)return true;
  for(auto &t:cities)if(std::abs(t.x-X(tile))+std::abs(t.z-Z(tile))<d)return true;
  return false;
}
enum class TileType{Clear,Trees,Water,Object,Void};
enum class ClearGround{Grass,Rough};
enum class TreeGround{Grass,Rough};
enum class ExpensesType{Other};
struct CommandCost{
 uint error;
 CommandCost(uint e):error(e){}
 CommandCost(ExpensesType):error(0){}
 bool Failed()const{return error!=0;}
};
struct Tile{int type=0,rough=0,base=0,slope=0;};
std::array<Tile,25> around;
std::vector<Tile> coast_board;
Tile read(int i){
 if(mode==0)return {};
 if(mode==2)return coast_board[i];
 int x=X(i)-test_x,z=Z(i)-test_z;
 return std::abs(x)<=2 && std::abs(z)<=2?around[(z+2)*5+x+2]:Tile{};
}
TileType kind(int i){return TileType(read(i).type);}
TileType GetTileType(int i){return kind(i);}
bool IsTileType(int i,TileType expected){return kind(i)==expected;}
bool IsTileFlat(int i){return read(i).slope==0;}
ClearGround GetClearGround(int i){return ClearGround(read(i).rough);}
TreeGround GetTreeGround(int i){return TreeGround(read(i).rough);}
int GetTileZ(int i){return read(i).base;}
int GetTileMaxZ(int i){auto t=read(i);return t.base+(t.slope>=16?2:t.slope>0);}
enum class Direction{W};
enum class DiagDirection{Begin,End=4,Invalid=255};
DiagDirection &operator++(DiagDirection &d){return d=DiagDirection(int(d)+1);}
template<class T> struct DiagDirectionIndexArray:std::array<T,4>{
 T operator[](DiagDirection d)const{return std::array<T,4>::operator[](int(d));}
};
struct Diff{int x,y;};
Diff TileIndexDiffCByDir(Direction){return {1,-1};}
Diff TileIndexDiffCByDiagDir(DiagDirection d){
 constexpr Diff delta[]={{-1,0},{0,1},{1,0},{0,-1}};
 return delta[int(d)];
}
int TileX(int i){return X(i);}
int TileY(int i){return Z(i);}
int TileXY(int x,int z){return at(x,z);}
template<class T> auto EnumRange(T d){return std::views::iota(0,int(d))|std::views::transform([](int n){return T(n);});}
bool IsInsideMM(int n,uint lo,uint hi){return uint(n)>=lo && uint(n)<hi;}
bool HasTileWaterGround(int i){auto t=read(i);return t.type==2 && !t.rough;}
bool IsTileAlignedToGrid(int i,TownLayout layout){
 const int n=int(layout)+2;
 return layout==TownLayout::Original || (X(i)%n==0 && Z(i)%n==0);
}
constexpr int INVALID_TILE=-1;
void SetGeneratingWorldProgress(GenWorldProgress,uint n){std::cout<<" "<<n;}
void IncreaseGeneratingWorldProgress(GenWorldProgress){}
void RebuildTownKdtree(){}
bool GenerateTownName(int,uint32_t *p,TownNames* names=nullptr){
 *p=Random();
 serial++;
 // The controlled name source deliberately fails on some slots.
 if(serial%5==3)return false;
 if(names)names->insert(std::to_string(serial));
 return true;
}
int GetEncodedString(int n){return n;}
void ShowErrorMessage(int,std::initializer_list<int>,WarningLevel){}
"""
for c in ("SpiralTileIterator","SpiralTileSequence"):
    cpp+=source_block(src,"tilearea_spiral.h",rf"^class {c} \{{")
for method in (r"SpiralTileIterator\(TileIndex center, uint diameter\)",r"SkipOutsideMap\(",r"InitPosition\(",r"Increment\("):
    cpp+=source_block(src,"tilearea_spiral.cpp",r"^(?:void )?SpiralTileIterator::"+method)
cpp+=source_block(src,"map.cpp",r"^uint GetClosestWaterDistance\(")
cpp+=source_block(src,"map.cpp",r"^/\* static \*/ void Map::CountLandTiles\(")
cpp+=source_block(src,"town_cmd.cpp",r"^static CommandCost TownCanBePlacedHere\([^;]*\)\n")
cpp+=source_block(src,"town_cmd.cpp",r"^static TileIndex FindNearestGoodCoastalTownSpot\(")
cpp+=r"""
Town *CreateRandomTown(uint attempts,uint32_t,TownSize,bool city,TownLayout){
 while(attempts--){
   int p=Random()%Map::size;
   if(TownCanBePlacedHere(p,true).Failed())continue;
   // Simulate a few viable lots whose first buildings did not grow.
   if((X(p)+Z(p))%7==0)continue;
   cities.push_back({X(p),Z(p),city});
   std::cout<<" "<<X(p)<<" "<<Z(p)<<" "<<city;
   return &cities.back();
 }
 return nullptr;
}
"""
for f,t in (("GetDefaultTownsForMapSize","uint"),("GenerateTowns","bool")):
    cpp+=source_block(src,"town_cmd.cpp",rf"^{t} {f}\(")
cpp+=r"""
int main(){
 while(std::cin>>mode>>Map::w>>Map::h){
   Map::size=Map::w*Map::h;
   cities.clear();
   if(mode==0){
     uint explicit_;
     std::cin>>water_count>>_settings_game.difficulty.number_towns>>_settings_newgame.game_creation.custom_town_number
         >>_settings_game.economy.larger_towns>>_settings_game.economy.town_min_distance>>word>>explicit_;
     Map::CountLandTiles();serial=draws=0;
     std::cout<<Map::initial_land_count;
     bool ok=GenerateTowns(TownLayout::Original,explicit_?std::optional<uint>{explicit_}:std::nullopt);
     std::cout<<" "<<ok<<" "<<draws<<" "<<word<<"\n";
   }else if(mode==2){
     int layout,freeform;
     std::cin>>test_x>>test_z>>nearx>>nearz>>_settings_game.economy.town_min_distance>>layout>>freeform;
     _settings_game.construction.freeform_edges=freeform;
     coast_board.resize(Map::size);
     for(auto &t:coast_board)std::cin>>t.type>>t.rough>>t.base>>t.slope;
     int p=FindNearestGoodCoastalTownSpot(at(test_x,test_z),TownLayout(layout));
     if(p==INVALID_TILE)std::cout<<"-1 -1 0\n";
     else std::cout<<X(p)<<" "<<Z(p)<<" "<<GetClosestWaterDistance(p,true)<<"\n";
   }else{
     int surrounding;
     std::cin>>test_x>>test_z>>nearx>>nearz>>_settings_game.economy.town_min_distance>>surrounding;
     for(auto &t:around)std::cin>>t.type>>t.rough>>t.base>>t.slope;
     std::cout<<TownCanBePlacedHere(at(test_x,test_z),surrounding).error<<"\n";
   }
 }
}
"""
program=r"""
local G=dofile("mods/luanttd_core/openttd/town_growth.lua")
local W=dofile("mods/luanttd_core/openttd/town_worldgen.lua")(G)
local kinds={[0]="clear","trees","water","object","void"}
local reasons={TOO_CLOSE_TO_EDGE=1,TOO_CLOSE_TO_ANOTHER_TOWN=2,SITE_UNSUITABLE=3}
for line in io.lines() do
 local a={}
 for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
 local kind,w,h=unpack(a,1,3)
 local board={width=w,height=h,tile=function() return {kind="clear",slope=0} end}
 if kind==0 then
   local water,diff,count,large,dist,word,explicit=unpack(a,4)
   local draws,serial=0,0
   local function random()draws=draws+1;word=(word*1664525+1013904223)%4294967296;return word end
   local function name(_,rnd)
     local value=rnd()
     serial=serial+1
     if serial%5~=3 then return value,tostring(serial) end
   end
   board.initial_land_count=W.land_for_density(w*h,w*h-water)
   local out=W.generate(board,{difficulty=diff,custom_count=count,larger_towns=large,
     separation=dist,number=explicit>0 and explicit or nil,random=random,name=name,create=function(c)
       return {x=c.x,z=c.z,city=c.city,population=(c.x+c.z)%7==0 and 0 or 1}
     end})
   local result={board.initial_land_count,out.target}
   for _,t in ipairs(out.towns) do for _,x in ipairs{t.x,t.z,t.city and 1 or 0} do result[#result+1]=x end end
   result[#result+1]=out.success and 1 or 0;result[#result+1]=draws;result[#result+1]=word
   print(table.concat(result," "))
 elseif kind==2 then
   local x,z,nx,nz,dist,layout,freeform=unpack(a,4,10)
   board.freeform=freeform==1
   board.tile=function(u,v)
     local i=11+4*(v*w+u)
     return {kind=kinds[a[i]],rough=a[i+1]==1,water_ground=a[i]==2 and a[i+1]==0,base=a[i+2],slope=a[i+3]}
   end
   local bx,bz,d=W.coast(board,x,z,({"original","grid2","grid3"})[layout+1],{{x=nx,z=nz}},dist)
   print(bx or -1,bz or -1,d or 0)
 else
   local x,z,nx,nz,dist,near=unpack(a,4)
   board.tile=function(u,v)
     local i=10+4*((v-z+2)*5+u-x+2)
     return {kind=kinds[a[i]],rough=a[i+1]==1,base=a[i+2],slope=a[i+3]}
   end
   local ok,why=W.can_place(board,{{x=nx,z=nz}},x,z,near==1,dist)
   print(ok and 0 or assert(reasons[why],why))
 end
end
"""
rng=Random(16006)
cases=[]
for i in range(256):
    w,h=rng.choice([64,128,256,512]),rng.choice([64,128,256,512])
    cases.append([0,w,h,rng.randrange(w*h+1),i%5,rng.randrange(1,30),rng.choice([0,1,2,4,17,255]),
                  rng.randrange(10,44),rng.getrandbits(32),i%3 and 0 or rng.randrange(1,40)])
for _ in range(6000):
    x,z=rng.randrange(8,52),rng.randrange(8,52)
    y=rng.randrange(8)
    data=[]
    for i in range(25):
        data.extend([rng.choice([0,0,0,1,2,3]),rng.randrange(2),
            rng.choice([y,y,y,y+1,y+2,max(0,y-1)]),rng.choice([0,0,0,1,3,23])])
        if i==12 and rng.randrange(4)!=0:
            data[-4:]=[0,0,y,0]
    cases.append([1,64,64,x,z,rng.randrange(64),rng.randrange(64),rng.randrange(10,35),rng.randrange(2),*data])
for i in range(120):
    w,h=(64,64) if i%3 else (64,32)
    shore=rng.randrange(10,50)
    line=[2,w,h,max(0,shore-rng.randrange(1,18)),rng.randrange(h),
          rng.randrange(w),rng.randrange(h),rng.randrange(10,24),i%3,i%2]
    for z in range(h):
        for x in range(w):
            shore_x=shore+(z//5)%3
            if x==w-1 or z==h-1 or (i%2 and (x==0 or z==0)):
                tile=[4,0,0,0]
            elif x<shore_x:
                tile=[2,int(x==shore_x-1),0,int(x==shore_x-1)]
            else:
                lot=rng.randrange(16)
                tile=[1 if lot==8 else 3 if lot==9 else 0,int(lot==12),
                      2 if x>shore+8 and lot<4 else 1,int(lot==7)]
            line.extend(tile)
    cases.append(line)
data="".join(" ".join(map(str,row))+"\n" for row in cases)
with TemporaryDirectory(prefix="town-placement-rc1-") as d:
    d=Path(d)
    (d/"ref.cpp").write_text(cpp)
    (d/"check.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    a,b=[subprocess.check_output(c,input=data,text=True).splitlines() for c in ([d/"ref"],[lua,d/"check.lua"])]
    assert len(a)==len(b)==len(cases)
    errors=[(i,cases[i][:13],x,y) for i,(x,y) in enumerate(zip(a,b)) if x.split()!=y.split()]
    assert not errors,(len(errors),errors[:8])
print("PASS 256 RC1 town/city generation streams, 6000 founding-site eligibility cases and 120 coastal searches")
