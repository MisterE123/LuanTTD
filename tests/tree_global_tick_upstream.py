#!/usr/bin/env python3
"""Differential test: compile the original RC1 global Temperate planting tick."""
import argparse
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = (a.source / "src/tree_cmd.cpp").read_text()
mp = (a.source / "src/map_func.h").read_text()
clock = src[src.index("bool DecrementTreeCounter()"):src.index("void InitializeTrees()")]
species = src[src.index("static TreeType GetRandomTreeType("):src.index("/**\n * Make a random tree tile")]
scale = mp[mp.index("static inline uint ScaleBySize(uint n)"):mp.index("\n\t/**", mp.index("static inline uint ScaleBySize(uint n)"))]
seed = mp[mp.index("inline TileIndex RandomTileSeed("):mp.index("\n/**", mp.index("inline TileIndex RandomTileSeed("))]
shim = r"""
#include <cstdint>
#include <iostream>
#include <algorithm>
#include <cstdlib>
#include <limits>
using uint=unsigned;
using TileIndex=uint32_t;
using TreeType=int;
constexpr int TREE_TEMPERATE=0,TREE_COUNT_TEMPERATE=12,TREE_SUB_ARCTIC=0,
 TREE_COUNT_SUB_ARCTIC=0,TREE_COUNT_SUB_TROPICAL=0,TREE_SUB_TROPICAL=0,
 TREE_INVALID=-1,TREE_CACTUS=0,TREE_COUNT_RAINFOREST=0,TREE_RAINFOREST=0,
 TREE_COUNT_TOYLAND=0,TREE_TOYLAND=0,MAX_MAP_SIZE_BITS=12,MIN_MAP_SIZE_BITS=6,
 ETP_NO_SPREAD=0,ETP_SPREAD_RAINFOREST=1,ETP_NO_GROWTH_NO_SPREAD=3;
enum class LandscapeType {Temperate,Arctic,Tropic};
enum class TropicZone {Normal,Desert,Rainforest};
enum class TreeGrowthStage {Growing1};
uint8_t _trees_tick_ctr;
uint area,logx,logy,replay,draws,placed,kind,surface;
static uint CeilDiv(uint a,uint b){return (a+b-1)/b;}
struct Map {
  static uint LogX(){return logx;}
  static uint LogY(){return logy;}
  static TileIndex WrapToMap(TileIndex i){return i&(area-1);}
  SCALE_BODY
};
struct TimerGameTick {static uint counter;};
uint TimerGameTick::counter;
struct {struct {int extra_tree_placement;} construction;
  struct {LandscapeType landscape=LandscapeType::Temperate;} game_creation; } _settings_game;
static uint Random(){++draws;return replay;}
static uint GB(uint r,int p,int n){return (r>>p)&((1u<<n)-1);}
static auto GetTropicZone(TileIndex){return TropicZone::Normal;}
static bool CanPlantTreesOnTile(TileIndex,bool){return surface<=5;}
static void PlantTreesOnTile(TileIndex i,TreeType t,uint n,TreeGrowthStage g){
  if(n!=0 || g!=TreeGrowthStage::Growing1) std::abort();
  placed=i+1;kind=t+1;
}
"""
main = r"""
static void emit(uint n){for(int i=0;i<4;i++){std::cout.put(char(n&255));n>>=8;}}
int main(){
  for(logx=6;logx<=12;logx++) for(logy=6;logy<=12;logy++)
    for(int setting=0;setting<4;setting++) for(int ctr: {0,1,2,3,15,16,63,64,127,128,254,255})
    for(uint tick: {0,1,2,3,7,8,15,16,255,256,257}) for(surface=0;surface<11;surface++){
      area=1u<<(logx+logy);
      _settings_game.construction.extra_tree_placement=setting;
      _trees_tick_ctr=ctr; TimerGameTick::counter=tick;
      replay=0x9e3779b9u*(surface+tick*7+ctr*11+logx*31+logy+setting);
      draws=placed=kind=0;
      OnTick_Trees();
      emit(uint(_trees_tick_ctr)|(draws<<8)|(kind<<16));emit(placed);
    }
}
"""
lua = r"""
local m="mods/luanttd_core/openttd/"
local T=dofile(m.."tree_lifecycle_temperate.lua")(dofile(m.."tree_worldgen.lua"))
local surfaces={[0]={class=0,ground=0,density=0},{class=0,ground=0,density=1},
  {class=0,ground=0,density=2},{class=0,ground=0,density=3},{class=0,ground=1,density=3},
  {class=6,coast=true,slope=3},{class=6,coast=true,slope=3,rocky=true},
  {class=0,ground=3,density=3},{class=0,ground=2,density=3},{class=0,bridge_above=true,density=3},
  {class=6,coast=true,slope=1}}
local out={}
local function put(a,b)
  local function le(n) return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256) end
  out[#out+1]=le(a)..le(b)
  if #out==4096 then io.write(table.concat(out));out={} end
end
-- 16-bit limbs avoid floating-point rounding above 2^53.
local function roll(n) return (31161*n+40503*n*65536)%4294967296 end
for x=6,12 do for y=6,12 do for setting=0,3 do
 for _,ctr in ipairs({0,1,2,3,15,16,63,64,127,128,254,255}) do
 for _,tick in ipairs({0,1,2,3,7,8,15,16,255,256,257}) do for surface=0,10 do
    local r=roll(surface+tick*7+ctr*11+x*31+y+setting)
    local draws=0
    local next,i,tree=T.global_tick(ctr,2^(x+y),tick,setting,function() draws=draws+1;return r end,
      function(i) assert(i==r%2^(x+y));return surfaces[surface] end)
    if tree then
      local g=surface==5 and 3 or surface==4 and 1 or 0
      assert(tree.ground==g and tree.growth==0 and tree.count==1 and tree.density==(surface<4 and surface or 3))
    end
    put(next+256*draws+65536*(tree and tree.type+1 or 0),i and i+1 or 0)
 end end end
end end end
io.write(table.concat(out))
"""
with tempfile.TemporaryDirectory() as td:
    cpp = Path(td) / "clock.cpp"
    exe = Path(td) / "clock"
    cpp.write_text(shim.replace("SCALE_BODY", scale) + seed + species + clock + main)
    subprocess.run(["g++", "-std=c++20", "-O2", str(cpp), "-o", str(exe)], check=True)
    expected = subprocess.check_output([exe])
    answer = subprocess.run([a.lua, "-"], input=lua.encode(), capture_output=True, check=True).stdout
assert len(answer) == len(expected)
if answer != expected:
    i = next(i for i, (a, b) in enumerate(zip(answer, expected)) if a != b) // 8 * 8
    raise AssertionError((i//8, list(answer[i:i+8]), list(expected[i:i+8])))
print(f"PASS {len(answer)//8:,} compiled RC1 global tree cases: cadence, full-area wrap, species, acceptance and RNG draws")
