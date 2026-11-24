#!/usr/bin/env python3
"""Compare compiled 16.0-RC1 DoFloodTile/DoDryUp on Temperate trees."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
source = (a.source / "src/water_cmd.cpp").read_text()


def block(name):
    start = re.search(r"^static void " + name + r"\(TileIndex", source, re.M).start()
    end = source.index("\n}", start)
    return source[start:end + 2] + "\n"


shim = r"""
#include <cassert>
#include <cstdlib>
#include <iostream>
using TileIndex=int;
using Slope=int;
enum class TileType { Water, Clear, Railway, Trees };
enum class TreeGround { Grass=0, Rough=1, Shore=3 };
enum class Track { Upper,Lower,Left,Right };
enum class RailGroundType { HalfTileWater,FenceHoriz1,FenceHoriz2,FenceVert1,FenceVert2 };
enum class ClearGround { Rocks, Grass };
enum class Commands { LandscapeClear };
enum class DoCommandFlag { Execute };
struct AutoRestoreBackup {AutoRestoreBackup(int,int){}};
#define NOT_REACHED() std::abort()
constexpr int OWNER_WATER=0,SLOPE_FLAT=0;
int _current_company=0,shape,events,allow;
TileType type;
TreeGround ground;
int density=2;
bool IsTileType(TileIndex,TileType k){return type==k;}
TileType GetTileType(TileIndex){return type;}
bool IsClearGround(TileIndex,ClearGround){return false;}
ClearGround GetClearGround(TileIndex){return ClearGround::Grass;}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
Slope GetTileSlope(TileIndex){return shape;}
bool IsPlainRail(TileIndex){return true;}
bool FloodHalftile(TileIndex){return false;}
void FloodVehicles(TileIndex){}
void SetTreeGroundDensity(TileIndex,TreeGround g,int n){events=g==TreeGround::Shore?3:4;ground=g;density=n;}
void MarkTileDirtyByTile(TileIndex){}
void MakeShore(TileIndex,bool){events=2;type=TileType::Water;}
void MakeSea(TileIndex,bool){events=1;type=TileType::Water;}
void MakeClear(TileIndex,ClearGround,int){events=5;type=TileType::Clear;}
void MarkCanalsAndRiversAroundDirty(TileIndex){}
void UpdateSignalsInBuffer(){}
bool IsPossibleDockingTile(TileIndex){return false;}
void CheckForDockingTile(TileIndex){}
void InvalidateWaterRegion(TileIndex){}
bool IsCoast(TileIndex){return true;}
enum class WaterTileType { CoastRocks };
WaterTileType GetWaterTileType(TileIndex){return WaterTileType::CoastRocks;}
RailGroundType GetRailGroundType(TileIndex){return RailGroundType::HalfTileWater;}
Track GetTrackBits(TileIndex){return Track::Upper;}
Track TrackBitsToTrack(Track t){return t;}
void SetRailGroundType(TileIndex,RailGroundType){}
struct Result {bool Succeeded(){return allow!=0;}};
template<Commands C> struct Command{ static Result Do(DoCommandFlag, TileIndex){return {};}; };
"""
main = r"""
int main(){
  for(int s: {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30})
    for(int i=0;i<2;i++) for(int g=0;g<2;g++){
      shape=s; events=0; allow=i; type=TileType::Trees;
      ground=g?TreeGround::Rough:TreeGround::Grass; density=2;
      DoFloodTile(0);
      for(int v: {events,int(ground),density}) std::cout.put(char(v));
    }
  events=0; ground=TreeGround::Shore; type=TileType::Trees;
  DoDryUp(0);
  for(int v: {events,int(ground),density}) std::cout.put(char(v));
}
"""
# The actual adapter F.visit queries direction first. Force one
# permitted seaward neighbor for each eligible slope so the tree
# actions can be compared independently of this earlier direction gate.
lua = r"""
local F=dofile("mods/luanttd_core/openttd/water_flood.lua")
local s={kind="sea",base=0,slope=0}
local t={kind="trees",base=0,slope=0}
local codes={sea=1,coast=2,shore_trees=3,dry_trees=4}
local function find_change(allow)
  for d=0,7 do
    local dx,dz=F.offset(d)
    local B={tile=function(x,z)
      if x==0 and z==0 then return s end
      if x==dx and z==dz then return t end
    end,can_clear=function() return allow end}
    local q=F.visit(B,0,0)
    if q[1] then return q[1] end
  end
end
for _,shape in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
 for allow=0,1 do for original=0,1 do
  t.slope=shape
  -- 5 and 10 have no flood direction; use the same post-gate rules
  -- with a mocked foundation direction solely for this comparison.
  t.foundation_slope=(shape==5 or shape==10) and 0 or nil
  local q=find_change(allow==1)
  local event=q and codes[q.kind] or 0
  io.write(string.char(event,event==3 and 3 or original,event==3 and 3 or 2))
 end end
end
t.water_ground=true;t.slope=9;t.foundation_slope=nil
local dry=assert(F.visit({tile=function(x,z) if x==0 and z==0 then return t end end},0,0)[1])
io.write(string.char(assert(codes[dry.kind]),0,3))
"""
with tempfile.TemporaryDirectory() as td:
    src, exe = Path(td) / "water.cpp", Path(td) / "water"
    src.write_text(shim + block("DoFloodTile") + block("DoDryUp") + main)
    subprocess.run(["g++", "-O2", "-std=c++20", str(src), "-o", str(exe)], check=True)
    expected = subprocess.check_output([exe])
actual = subprocess.run([a.lua, "-"], input=lua.encode(), check=True, capture_output=True).stdout
assert len(actual) == len(expected)
if actual != expected:
    i = next(i for i, (x, y) in enumerate(zip(actual, expected)) if x != y) // 3 * 3
    raise AssertionError((i // 3, list(actual[i:i+3]), list(expected[i:i+3])))
print(f"PASS {len(actual)//3} compiled RC1 woodland shoreline transitions")
