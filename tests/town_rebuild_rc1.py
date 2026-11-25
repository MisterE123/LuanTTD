"""Compile the original RC1 per-town rebuild countdown and compare Lua receipts."""
import subprocess as sp
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
from rc1_rail_foundation_shim import source_block

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
src = source / "src"
raw = (src / "town_cmd.cpp").read_text()
assert "t->time_until_rebuild = 10;" in raw
command = source_block(src, "town_cmd.cpp", r"^static void TileLoop_Town")
branch = command[command.index("if (hs->building_flags.Any(BUILDING_HAS_1_TILE)"):].rsplit("}", 1)[0]
cpp = r"""
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
struct TileIndex{int x,y;};
struct TileIndexDiffC{int x,y;};
using uint=unsigned;
constexpr int BUILDING_HAS_1_TILE=1,BUILDING_HAS_2_TILES=2;
enum class BuildingFlag{Size2x2,Size1x2,Size2x1,Size1x1};
enum class TownFlag{IsGrowing};
enum class TownExpandMode{Roads,Buildings};
struct TownExpandModes{
  TownExpandModes(TownExpandMode){}
  void Set(TownExpandMode){}
};
int width,depth,is_root,age,allow_remove;
int cleared,px,py;
struct HouseSpec{
 int minimum_life;
 struct {
  bool Any(int flags)const{return flags==BUILDING_HAS_1_TILE?is_root:width*depth>1;}
  bool Test(BuildingFlag f)const{
    return f==(width==2?(depth==2?BuildingFlag::Size2x2:BuildingFlag::Size2x1):
      (depth==2?BuildingFlag::Size1x2:BuildingFlag::Size1x1));
  }
 } building_flags;
};
struct Town{
 TileIndex xy;
 uint16_t time_until_rebuild;
 struct {bool normal;bool Test(TownFlag)const{return normal;}} flags;
};
struct {struct {bool allow_town_roads=true;} economy;} _settings_game;
int GetHouseAge(TileIndex){return age;}
bool CanDeleteHouse(TileIndex){return allow_remove;}
void ClearTownHouse(Town*,TileIndex){cleared=1;}
void TryBuildTownHouse(Town*,TileIndex pos,TownExpandModes){px=pos.x;py=pos.y;}
TileIndex TileAddXY(TileIndex p,int x,int y){return {p.x+x,p.y+y};}
TileIndexDiffC TileIndexToTileIndexDiffC(TileIndex a,TileIndex b){return {a.x-b.x,a.y-b.y};}
int Clamp(int x,int a,int b){return std::clamp(x,a,b);}
uint GB(uint v,int s,int n){return (v>>s)&((1u<<n)-1);}
void run(Town* t,const HouseSpec* hs,TileIndex tile,uint r){
""" + branch + r"""
}
int main(){
 for(width=1;width<=2;width++)for(depth=1;depth<=2;depth++)
 for(is_root=0;is_root<2;++is_root)for(int g=0;g<2;g++)
 for(allow_remove=0;allow_remove<2;allow_remove++)for(age=2;age<=4;age++)
 for(int cx:{4,5,6})for(int cy:{4,5,6})
 for(int count:{0,1,2,10,447})for(uint top:{0,11,12,255})for(uint low:{0,121,255}){
   Town t{{cx,cy},uint16_t(count),{g!=0}};HouseSpec hs{3};
   cleared=0;px=-1;py=-1;
   run(&t,&hs,{5,5},(top<<24)|(low<<16)|0xACED);
   std::cout<<width<<' '<<depth<<' '<<is_root<<' '<<g<<' '<<allow_remove<<' '<<age<<' '
     <<cx<<' '<<cy<<' '<<count<<' '<<top<<' '<<low<<' '<<int(t.time_until_rebuild)<<' '<<cleared<<' '<<px<<' '<<py<<'\n';
 }
}
"""
lua = r"""
local R=dofile("mods/luanttd_core/openttd/town_rebuild.lua")
local n=0
for row in io.lines() do
 local a={};for v in row:gmatch("%-?%d+") do a[#a+1]=tonumber(v) end
 local w,d,root,g,ok,age,x,z,before,hi,lo,after,clear,u,v=unpack(a)
 local town={x=x,z=z,growing=g==1,time_until_rebuild=before}
 local h={x=5,z=5,root=root==1,age=age,completed=true}
 local q=R.visit(town,h,{width=w,depth=d,minimum_life=3},ok==1,hi*2^24+lo*2^16+0xACED)
 assert(town.time_until_rebuild==after and (not not q)==(clear==1),row)
 local p=q and q.replace
 assert((p and p.x or -1)==u and (p and p.z or -1)==v,row)
 n=n+1
end
assert(n==51840)
print(("PASS %d exact compiled RC1 town rebuild decisions from TileLoop_Town"):format(n))
"""
with TemporaryDirectory() as tmp:
    cc, exe, driver = (Path(tmp) / k for k in ("rebuild.cpp", "rebuild", "rebuild.lua"))
    cc.write_text(cpp)
    driver.write_text(lua)
    sp.run(["g++", "-O2", "-std=c++20", cc, "-o", exe], check=True)
    sp.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1", driver], input=sp.check_output([exe]), check=True)
