#!/usr/bin/env python3
"""Compare stock normal-game temperate forest placements and RNG.

Usage: python3 tests/tree_worldgen_upstream.py /path/to/OpenTTD-16.0-RC1 [lua5.1]
"""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("source",type=Path)
parser.add_argument("lua",nargs="?",default="lua5.1")
args=parser.parse_args()


assert subprocess.check_output(["git","-C",args.source,"rev-parse","HEAD"],text=True).strip()==(
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837")

def pinned(name):
    return (args.source/"src"/name).read_text()


def block(source,pattern):
    p=re.search(pattern,source,re.M).start()
    start=source.index("{",p)
    n,i=1,start
    while n:
        i+=1
        n+=(source[i]=="{")-(source[i]=="}")
    return source[p:i+1]


tree=pinned("tree_cmd.cpp")
tree_map=pinned("tree_map.h")
tile_map=pinned("tile_map.cpp")
tile_map_h=pinned("tile_map.h")
maps=pinned("map_func.h")
map_cpp=pinned("map.cpp")
random=pinned("core/random_func.cpp")
gen=pinned("genworld.cpp")
settings=pinned("table/settings/world_settings.ini")
settings_type=pinned("settings_type.h")
placer=settings.split("var      = game_creation.tree_placer",1)[1].split("[SDT_",1)[0]
assert re.search(r"^def\s*=\s*2$",placer,re.M)
gen=gen[gen.index("if (!GenerateTowns("):]
for left,right in zip(("GenerateTowns(", "GenerateIndustries();", "GenerateObjects();"),
                      ("GenerateIndustries();", "GenerateObjects();", "GenerateTrees();")):
    assert gen.index(left)<gen.index(right)

cpp=r"""
#include <algorithm>
#include <bit>
#include <cassert>
#include <array>
#include <cmath>
#include <numeric>
#include <span>
#include <type_traits>
#include <tuple>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
using uint=unsigned;using byte=uint8_t;using TileIndex=uint32_t;
constexpr TileIndex INVALID_TILE=0xffffffff;
enum class LandscapeType {Temperate,Arctic,Tropic,Toyland};
enum class GameMode {Normal,Editor};
enum class GenWorldProgress {Trees};
enum class TileType : byte {Clear=0,Trees=4,Water=6,Void=7};
enum class ClearGround : byte {Grass,Rough,Rocks,Fields,Snow,Desert};
enum class WaterClass : byte {Sea=0,Invalid=1};
enum class WaterTileType {Clear,Coast,CoastRocks};
enum class TropicZone {Normal,Desert,Rainforest};
enum {OWNER_NONE};
enum class TreePlacer:uint8_t;
constexpr uint MAP_HEIGHT_LIMIT_ORIGINAL=15;
template<class T> constexpr auto to_underlying(T e){return static_cast<std::underlying_type_t<T>>(e);}
struct Point {int x,y;};
enum Slope{SLOPE_FLAT=0,SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_STEEP=16};
constexpr Slope& operator|=(Slope& a,Slope b){ a=static_cast<Slope>(int(a)|int(b));return a; }
#define NOT_REACHED() std::abort()
constexpr auto _game_mode=GameMode::Normal;
struct Settings{
 struct{LandscapeType landscape=LandscapeType::Temperate;TreePlacer tree_placer;} game_creation;
 struct{bool freeform_edges;uint8_t map_height_limit;} construction;
} _settings_game;
uint RandomDraws;
template<class T=uint32_t> T GB(uint32_t r,int s,int n){return (r>>s)&((1u<<n)-1);}
template<class T> void SB(T& v,int s,int n,uint set){auto m=((1u<<n)-1)<<s;v=(v&~m)|(set<<s);}
template<class T> T CeilDiv(T n,int d){return (n+d-1)/d;}
int Delta(int a,int b){return std::abs(a-b);}
struct Randomizer{uint32_t state[2];uint32_t Next();} _random;
uint32_t Random(){RandomDraws++;return _random.Next();}
struct Map{
  static inline uint w,h,lx,lz;
  static uint LogX(){return lx;} static uint LogY(){return lz;}
  static uint MaxX(){return w-1;} static uint MaxY(){return h-1;}
  static TileIndex WrapToMap(uint32_t r){return r&(w*h-1);}
""" + block(maps,r"^\s*static inline uint ScaleBySize\(uint n\)") + r"""
};
struct Cell{
 byte type,ground,raw,density,coast,bridge,height;
 byte m3=0,m4=0,m5=0,m6=0,m7=0,owner=0,water=0;
 uint16_t m2=0,m8=0;
};
std::vector<Cell> cells;
std::vector<TileIndex> order;
struct Tile {
 TileIndex i;
 Tile(TileIndex i):i(i){}
 byte& m3(){return cells.at(i).m3;} byte& m4(){return cells.at(i).m4;}
 byte& m5(){return cells.at(i).m5;} byte& m6(){return cells.at(i).m6;}
 byte& m7(){return cells.at(i).m7;} uint16_t& m2(){return cells.at(i).m2;} uint16_t& m8(){return cells.at(i).m8;}
};
uint TileX(TileIndex i){return i%Map::w;}
uint TileY(TileIndex i){return i/Map::w;}
TileIndex TileXY(uint x,uint y){return x+y*Map::w;}
uint TileHeight(TileIndex i){return cells.at(i).height;}
bool IsBridgeAbove(TileIndex i){return cells.at(i).bridge;}
WaterTileType GetWaterTileType(TileIndex i){return static_cast<WaterTileType>(cells.at(i).coast);}
bool IsSnowTile(TileIndex i){return cells.at(i).ground==4;}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
TileType GetTileType(TileIndex i){return static_cast<TileType>(cells.at(i).type);}
bool IsTileType(Tile t,TileType kind){return GetTileType(t.i)==kind;}
ClearGround GetClearGround(TileIndex i){return static_cast<ClearGround>(IsSnowTile(i)? cells.at(i).raw: cells.at(i).ground);}
bool IsClearGround(TileIndex i,ClearGround kind){return GetClearGround(i)==kind;}
uint GetClearDensity(TileIndex i){return cells.at(i).density;}
TropicZone GetTropicZone(TileIndex){return TropicZone::Normal;}
int GetSnowLine(){return 0;}
void SetTileType(Tile t,TileType kind){
 assert(!IsTileType(t,TileType::Trees) && kind==TileType::Trees);
 cells.at(t.i).type=to_underlying(kind);order.push_back(t.i);
}
void SetTileOwner(Tile t,int owner){cells.at(t.i).owner=owner;}
void SetWaterClass(Tile t,WaterClass kind){cells.at(t.i).water=to_underlying(kind);}
void SetGeneratingWorldProgress(GenWorldProgress,uint){}
void IncreaseGeneratingWorldProgress(GenWorldProgress){}
void MarkTileDirtyByTile(TileIndex){}
void ClearNeighbourNonFloodingStates(TileIndex){}

"""
cpp+="\n"+block(random,r"^uint32_t Randomizer::Next\(\)")+"\n"
cpp+="\n".join(block(source,pat) for source,pat in (
    (map_cpp,r"^TileIndex TileAddWrap"), (maps,r"^inline TileIndex RandomTileSeed"),
    (tile_map,r"^static std::tuple<Slope, int> GetTileSlopeGivenHeight"),
    (tile_map,r"^std::tuple<Slope, int> GetTileSlopeZ\("), (tile_map_h,r"^inline Slope GetTileSlope\("),
    (tile_map,r"^int GetTileZ\(")))+"\n#define RandomTile() RandomTileSeed(Random())\n"
cpp+=block(settings_type,r"^enum class TreePlacer")+";\n"
for name in ("DEFAULT_TREE_STEPS","DEFAULT_RAINFOREST_TREE_STEPS","EDITOR_TREE_DIV"):
    cpp+=re.search(r"^static const uint16_t "+name+r" .*?;",tree,re.M)[0]+"\n"
for pattern in (r"^enum TreeType",r"^enum class TreeGround",r"^enum class TreeGrowthStage"):
    cpp+=block(tree_map,pattern)+";\n"
cpp+="\n".join(re.findall(r"^static const uint TREE_COUNT_.*?;",tree_map,re.M))+"\n"
for source,pat in (
    (tree_map,r"^inline TreeGround GetTreeGround"),(tree_map,r"^inline void SetTreeGroundDensity"),
    (tree_map,r"^inline void MakeTree"),(tree_map,r"^inline TreeType GetTreeType"),
    (tree_map,r"^inline uint GetTreeCount"),(tree_map,r"^inline TreeGrowthStage GetTreeGrowth"),
    (tree_map,r"^inline uint GetTreeDensity"),(tree,r"^static bool CanPlantTreesOnTile"),
    (tree,r"^static TreeGround TreeGroundFromClearGround"),(tree,r"^static void PlantTreesOnTile"),
    (tree,r"^static TreeType GetRandomTreeType"),(tree,r"^void PlaceTree\("),
    (tree,r"^struct BlobHarmonic"),(tree,r"^static void CreateStarShapedPolygon"),
    (tree,r"^static void CreateRandomStarShapedPolygon"),(tree,r"^static bool IsPointInTriangle"),
    (tree,r"^static bool IsPointInStarShapedPolygon"),(tree,r"^static void PlaceTreeGroups"),
    (tree,r"^static void PlaceTreeAtSameHeight"),(tree,r"^void PlaceTreesRandomly"),
    (tree,r"^void GenerateTrees")):
    definition=block(source,pat)
    if pat==r"^void PlaceTree\(":
        cpp+="void PlaceTree(TileIndex tile,uint32_t r,bool keep_density=false);\n"
    cpp+=definition+(";" if pat==r"^struct BlobHarmonic" else "")+"\n"
cpp+=r"""
int main(){
 int mode,freeform,height_limit;
 while(std::cin>>Map::w>>Map::h>>mode>>freeform>>height_limit>>_random.state[0]>>_random.state[1]){
   assert(std::cin.get()=='\n');
   Map::lx=std::countr_zero(Map::w);Map::lz=std::countr_zero(Map::h);
   _settings_game.construction.freeform_edges=freeform;
   _settings_game.construction.map_height_limit=height_limit;
   _settings_game.game_creation.tree_placer=static_cast<TreePlacer>(mode);
   RandomDraws=0;order.clear();cells.assign(Map::w*Map::h,{});
   for(auto& c:cells){
     c.type=std::cin.get();c.ground=std::cin.get();c.raw=std::cin.get();
     c.density=std::cin.get();c.coast=std::cin.get();c.bridge=std::cin.get();
     c.height=std::cin.get(); assert(std::cin);
   }
   GenerateTrees();
   std::cout<<_random.state[0]<<" "<<_random.state[1]<<" "<<RandomDraws<<" "<<order.size()<<"\n";
   for(auto i:order){
     std::cout.put(i&255);std::cout.put((i>>8)&255);std::cout.put((i>>16)&255);
     std::cout.put(GetTreeType(i));std::cout.put(GetTreeCount(i));std::cout.put(to_underlying(GetTreeGrowth(i)));
     std::cout.put(to_underlying(GetTreeGround(i)));std::cout.put(GetTreeDensity(i));std::cout.put(cells.at(i).water);
   }
 }
}
"""
lua=r"""
local p="mods/luanttd_core/openttd/"
local Slope=dofile(p.."slope.lua")
local TGP=dofile(p.."terragenesis.lua")(Slope)
local Clear=dofile(p.."terragenesis_clear.lua")
local Forest=dofile(p.."tree_worldgen.lua")
local f=assert(io.open(arg[1],"wb"))
local expected=assert(io.open(arg[2],"wb"))
local fixtures=0
local function run(w,h,mode,freeform,seed,test,opts)
  local opts=opts or {}
  local tgp=TGP.generate({width=w,depth=h,seed=seed,rng_state=TGP.startup_rng(seed),
    terrain_type=opts.terrain_type or 3,quantity_sea_lakes=opts.water or 0,
    water_borders=opts.borders or 15,tgen_smoothness=opts.smooth or 1,
    freeform_edges=freeform,variety=opts.variety or 0})
  local base=Clear.generate(tgp,TGP.next_random)
  local function corner(x,z)
    x,z=math.min(x,w),math.min(z,h)
    if test=="exhausted" then return 5 end
    return base.corner(x,z)
  end
  local function tile(x,z)
    local class,water,ground,rocks=Clear.describe(base.tile(x,z))
    local mask,height=Slope.classify(corner(x,z),corner(x+1,z),corner(x,z+1),corner(x+1,z+1))
    local t={class=class,ground=ground,raw_ground=ground,density=3,coast=class==6 and water==2,
      bridge_above=false,slope=mask,height=height,rocky=rocks}
    if t.class==7 then return t end
    if test=="blocked" then
      -- Distinct towns, rails and industry preempt stock forest candidates.
      -- Pinned predicates also distinguish a bridge above an otherwise
      -- plantable slope; no candidate sees the adapter as empty by default.
      if x>=23 and x<=34 and z>=31 and z<=36 then t.class=3
      elseif (x+z)%19==0 then t.class=2
      elseif (x+z)%23==0 then t.class=8
      elseif (3*x+z)%11==0 then t.bridge_above=true
      elseif t.class==0 and (2*x+z)%13==0 then t.ground,t.raw_ground=3,3
      elseif t.class==0 and (2*x+z)%17==0 then t.ground,t.raw_ground=2,2
      elseif t.class==0 and (x+z)%29==0 then t.ground,t.raw_ground,t.density=4,1,2
      elseif t.class==0 and (x+z)%37==0 then t.ground,t.raw_ground,t.density=5,5,1 end
    elseif test=="exhausted" then
      t.class,t.ground,t.raw_ground,t.bridge_above=0,2,2,false
      if x==22 and z==34 then t.ground,t.raw_ground=0,0 end
    end
    return t
  end
  -- Seeded exhausted board: the single clear tile is missed by both
  -- groups but hit by a base trial at level 5. All ten nearby searches fail.
  local start=test=="exhausted" and {3351320900,3998776463} or base.rng_after
  local height_limit=opts.height_limit or math.max(30,base.estimated_max_height+15)
  f:write(("%d %d %d %d %d %.0f %.0f\n"):format(w,h,mode,freeform and 1 or 0,height_limit,start[1],start[2]))
  for z=1,h do for x=1,w do
    local t=tile(x,z)
    f:write(string.char(t.class,t.ground,t.raw_ground,t.density,
      t.coast and (t.rocky and 2 or 1) or 0,t.bridge_above and 1 or 0,corner(x,z)))
  end end
  local initial_a,initial_b=start[1],start[2]
  local result=Forest.generate({width=w,depth=h,freeform=freeform,tile=tile},start,TGP.next_random,{tree_placer=mode,map_height_limit=height_limit})
  assert(initial_a==start[1] and initial_b==start[2])
  expected:write(("%.0f %.0f %d %d\n"):format(result.rng_after[1],result.rng_after[2],
    result.stats.random_draws,result.stats.tiles))
  local seen,count={},0
  result.each(function(x,z,t)
    local i=(z-1)*w+x-1
    assert(not seen[i],"Duplicate forest placements")
    seen[i],count=true,count+1
    local pre=tile(x,z)
    assert(Forest.can_plant(pre,true))
    assert(Forest.decode(result.encoded(x,z)).type==t.type)
    expected:write(string.char(i%256,math.floor(i/256)%256,math.floor(i/65536),
      t.type,t.count,t.growth,t.ground,t.density,t.water_class=="sea" and 0 or 1))
  end)
  assert(count==result.stats.tiles)
  if mode==0 then assert(count==0 and result.stats.random_draws==0) end
  fixtures=fixtures+1
end
for _,seed in ipairs{0,1751,2^32-2} do
  for mode=0,2 do
    for _,freeform in ipairs{true,false} do
      run(64,64,mode,freeform,seed,"blocked",{borders=16,water=1,smooth=3,variety=2})
    end
  end
end
run(64,64,1,true,1751,"regular")
run(64,64,2,true,1751,"regular")
run(128,64,2,true,99,"blocked",{borders=5,water=3,terrain_type=4})
run(64,128,1,false,100,"blocked",{borders=0,water=2,terrain_type=5})
run(256,128,2,true,214783648,"regular",{borders=13,terrain_type=4,smooth=3})
run(64,64,2,true,1751,"exhausted",{height_limit=15})
run(512,128,2,false,67955,"blocked",{terrain_type=5,height_limit=55})
run(128,256,2,true,71933,"blocked",{terrain_type=4,height_limit=255})
f:close();expected:close()
print(fixtures)
"""
with tempfile.TemporaryDirectory(prefix="bayline-tree-worldgen-") as d:
    wd=Path(d)
    cp,lp,exe,board,gold=[wd/n for n in ("oracle.cpp","run.lua","oracle","input","expected")]
    cp.write_text(cpp)
    lp.write_text(lua)
    subprocess.run(["g++","-std=c++20","-O2","-fwrapv",cp,"-o",exe],check=True)
    fixtures=int(subprocess.check_output([args.lua,lp,board,gold],cwd=ROOT).strip())
    with board.open("rb") as f:
        result=subprocess.check_output([exe],stdin=f)
    expected=gold.read_bytes()
    if result!=expected:
        n=next((i for i,(a,b) in enumerate(zip(result,expected)) if a!=b),min(len(result),len(expected)))
        raise AssertionError(f"first differing forest byte {n}: {result[n:n+28]} != {expected[n:n+28]}")
i=placements=draws=0
for _ in range(fixtures):
    p=result.index(b"\n",i)
    stats=list(map(int,result[i:p].split()))
    draws+=stats[2]
    placements+=stats[3]
    i=p+1+9*stats[3]
assert i==len(result)
print(f"PASS {fixtures} complete pinned OpenTTD 16.0-RC1 temperate forest runs, {placements:,} packed placements and {draws:,} RNG draws")
