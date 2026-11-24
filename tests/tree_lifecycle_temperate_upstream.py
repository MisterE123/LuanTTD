#!/usr/bin/env python3
"""Compare the native Temperate tree tile transition to compiled 16.0-RC1."""
import argparse
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
source = (a.source / "src/tree_cmd.cpp").read_text()
start = source.index("static void TileLoop_Trees(TileIndex tile)")
body_start = source.index("\t/* TimerGameTick::counter", start)
body_end = source.index("\n}\n", body_start)
body = source[body_start:body_end]
assert "ETP_NO_GROWTH_NO_SPREAD" in body and "CanPlantTreesOnTile(tile, false)" in body
shim = r"""
#include <algorithm>
#include <cstdint>
#include <iostream>
using TileIndex=int;
using TreeType=int;
using uint=unsigned;
enum class TreeGround { Grass, Rough, SnowOrDesert, Shore, RoughSnow };
enum class TreeGrowthStage { Growing1,Growing2,Growing3,Grown,Dying1,Dying2,Dead };
enum class LandscapeType { Temperate,Tropic,Arctic };
enum class TropicZone { Desert };
enum class TileType { Clear,Water };
enum class ClearGround { Grass,Rough,Rocks,Fields,Snow,Desert };
enum class Direction { End=8 };
struct TimerGameTick {static uint32_t counter;};
uint32_t TimerGameTick::counter;
struct { struct {int extra_tree_placement;} construction;
  struct {LandscapeType landscape=LandscapeType::Temperate;} game_creation; } _settings_game;
constexpr int ETP_SPREAD_ALL=2, ETP_NO_GROWTH_NO_SPREAD=3, TREE_CACTUS=-1;
struct Tree { int count,stage,density,ground; };
Tree t;
int target,choice,direction,draws,action,desc;
static uint TileX(TileIndex){return 3;}
static uint TileY(TileIndex){return 4;}
static auto GetTreeGround(TileIndex){return TreeGround(t.ground);}
static uint GetTreeDensity(TileIndex){return t.density;}
static void SetTreeGroundDensity(TileIndex,TreeGround g,uint d){t.ground=int(g);t.density=d;}
static void MarkTileDirtyByTile(TileIndex){}
static auto GetTreeGrowth(TileIndex){return TreeGrowthStage(t.stage);}
static int GetTreeType(TileIndex){return 7;}
static auto GetTropicZone(TileIndex){return TropicZone::Desert;}
static uint32_t Random(){++draws;return choice;}
static uint GB(uint32_t r,int pos,int n){return (r>>pos)&((1u<<n)-1);}
static void AddTreeGrowth(TileIndex,int n){t.stage+=n;}
static void AddTreeCount(TileIndex,int n){t.count+=n;}
static void SetTreeGrowth(TileIndex,TreeGrowthStage g){t.stage=int(g);}
static uint GetTreeCount(TileIndex){return t.count;}
static bool TreesOnTileCanSpread(TileIndex){return _settings_game.construction.extra_tree_placement==ETP_SPREAD_ALL;}
static Direction RandomRange(Direction){++draws;return Direction(direction);}
static int TileOffsByDir(Direction d){return int(d)+1;}
static bool CanPlantTreesOnTile(TileIndex,bool){return target<=2;}
static bool IsTileType(TileIndex,TileType ty){return target==2?ty==TileType::Water:ty==TileType::Clear;}
static auto GetClearGround(TileIndex){return target==1?ClearGround::Rough:ClearGround::Grass;}
static bool IsSnowTile(TileIndex){return false;}
static int GetClearDensity(TileIndex){return target==0?2:3;}
static void PlantTreesOnTile(TileIndex id,int,int,TreeGrowthStage){
  action=1;desc=id-1;
}
static void MakeShore(TileIndex){action=2;desc=3;}
static void MakeClear(TileIndex,ClearGround g,int d){action=2;desc=int(g);if(g==ClearGround::Grass)t.density=d;}
static void MakeSnow(TileIndex,int){}
"""
main = r"""
static void rule(TileIndex tile) {
""" + body + r"""
}
int main(){
  for(int setting=0;setting<4;setting++) for(int growth=0;growth<7;growth++)
    for(int count=1;count<=4;count++) for(int ground: {0,1,3}) for(int density=0;density<4;density++)
    for(int cycle: {0,7,11,15}) for(choice=0;choice<8;choice++) for(target=0;target<4;target++) {
      t={count,growth,density,ground}; _settings_game.construction.extra_tree_placement=setting;
      TimerGameTick::counter=(cycle+16-(3*11+4*9)%16)*256;
      direction=(cycle+target+count)%8; draws=action=desc=0;
      rule(0);
      for(int v: {action,desc,draws,action==2?0:t.count,action==2?0:t.stage,t.density}) std::cout.put(char(v));
    }
}
"""
lua = r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."tree_worldgen.lua")
local T=dofile(p.."tree_lifecycle_temperate.lua")(G)
local targets={[0]={class=0,density=2,ground=0},{class=0,density=3,ground=1},
  {class=6,coast=true,slope=3,density=3},{class=6,coast=true,slope=3,rocky=true,density=3}}
local tree={type=7,class=4}
local out={}
for setting=0,3 do for growth=0,6 do for count=1,4 do for _,ground in ipairs({0,1,3}) do
  for density=0,3 do for _,cycle in ipairs({0,7,11,15}) do for choice=0,7 do for target=0,3 do
    tree.growth,tree.count,tree.ground,tree.density=growth,count,ground,density
    local direction=(cycle+target+count)%8
    local draws=0
    local next,event=T.visit(tree,3,4,(cycle+16-(3*11+4*9)%16)*256,setting,function()
      draws=draws+1
      return draws==1 and choice or direction*536870912
    end,function(d) assert(d==direction);return targets[target] end)
    local action=event and (event.kind=="plant" and 1 or 2) or 0
    local desc=event and (event.kind=="plant" and event.direction or event.ground) or 0
    out[#out+1]=string.char(action,desc,draws,next and next.count or 0,next and next.growth or 0,
      next and next.density or event.density)
  end end end end
end end end end
io.write(table.concat(out))
"""
with tempfile.TemporaryDirectory() as td:
    cpp = Path(td) / "tree.cpp"
    exe = Path(td) / "tree"
    cpp.write_text(shim + main)
    subprocess.run(["g++", "-std=c++20", "-O2", str(cpp), "-o", str(exe)], check=True)
    expected = subprocess.check_output([exe])
answer = subprocess.run([a.lua, "-"], input=lua.encode(), stdout=subprocess.PIPE, check=True).stdout
assert len(answer) == len(expected)
if answer != expected:
    error_index = next(i for i,(x,y) in enumerate(zip(answer,expected)) if x!=y) // 6 * 6
    raise AssertionError((error_index//6, list(answer[error_index:error_index+6]), list(expected[error_index:error_index+6])))
print(f"PASS {len(answer)//6:,} compiled RC1 tree cases: life stages, tile cadence, spread and RNG draw count")
