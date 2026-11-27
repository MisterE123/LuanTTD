#!/usr/bin/env python3
"""Road-type eligibility for ordinary houses, against OpenTTD 16.0-RC1."""
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
from rc1_rail_foundation_shim import source_block
import os
import subprocess
import sys

root = Path(sys.argv[1])
assert subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
cpp = r"""
#include <array>
#include <iostream>
using TileIndex=int;
using RoadType=int;
enum class TileType { Road };
enum class RoadTypeFlag { NoHouses };
struct TileIndexDiffC { int x,y; };
constexpr RoadType INVALID_ROADTYPE=-1;
int ToTileIndexDiff(TileIndexDiffC a) { return a.x+a.y*5; }
std::array<int,25> board{};
bool IsValidTile(int i) { return board[i]!=-1; }
bool IsTileType(int i,TileType) {
  int k=board[i];return k==1||k==2||k==5||k==6||k==7||k==9||k==12;
}
bool IsAnyRoadStopTile(int i) { return board[i]==3||board[i]==4||board[i]==11; }
RoadType GetRoadTypeRoad(int i) {
  int k=board[i];return k==1||k==4||k==6||k==9||k==11||k==12?0:INVALID_ROADTYPE;
}
struct Flags{bool Test(RoadTypeFlag) const {return false;}};
struct RoadTypeInfo{Flags flags;};
const RoadTypeInfo *GetRoadTypeInfo(RoadType) { static RoadTypeInfo rt;return &rt; }
"""
cpp += source_block(root / "src", "town_cmd.cpp", r"^static inline bool RoadTypesAllowHouseHere\(")
cpp += r"""
int main() {
  int n;
  std::cin>>n;
  for(int i=0;i<n;i++) {
    for(auto &k:board)std::cin>>k;
    std::cout<<RoadTypesAllowHouseHere(12)<<"\n";
  }
}
"""
lua = r"""
local mod="mods/luanttd_core/"
local House=dofile(mod.."openttd/town_house_roadtypes.lua")
local kinds={[-1]={stock_void=true},[0]={},[1]={build="road",road_bits=5},
 [2]={tram={kind="road"}},[3]={tram={kind="drive_stop"}},[4]={build="road_station"},
 [5]={level_crossing={tramtype=1}},[6]={level_crossing={roadtype=0,road_bits=10}},
 [7]={tram={kind="depot"}},[8]={build="road",road_bits=5,road_bridge_id=1},
 [9]={build="road_depot"},[10]={build="road_station",road_waypoint_id=1},
 [11]={build="road_station",tram={kind="drive_stop"}},[12]={build="road",road_bits=5,tram={kind="road"}}}
local sim={id=function(x,z)return 1+x+z*5 end}
for _=1,io.read("*n") do
  local tiles={}
  for i=1,25 do tiles[i]=assert(kinds[io.read("*n")]) end
  local allows=House.on_board(sim,{tiles=tiles})
  print(allows(2,2) and 1 or 0)
end
"""
rng = Random(16011)
cases = []
for i in range(3**8 + 1024):
    case = [0] * 25
    for idx in (6, 7, 8, 11, 13, 16, 17, 18):
        if i < 3**8:
            case[idx] = i % 3
            i //= 3
        else:
            case[idx] = rng.randrange(-1, 13)
    cases.append(case)
data = str(len(cases)) + "\n" + "".join(" ".join(map(str, c)) + "\n" for c in cases)
with TemporaryDirectory() as temp:
    ref, prog, runner = (Path(temp) / name for name in ("ref.cpp", "ref", "runner.lua"))
    ref.write_text(cpp)
    runner.write_text(lua)
    subprocess.run([os.environ.get("CXX", "c++"), "-std=c++20", "-O2", ref, "-o", prog], check=True)
    a = subprocess.check_output([prog], text=True, input=data).splitlines()
    b = subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1", runner], text=True, input=data).splitlines()
    assert len(a) == len(b) == len(cases)
    for x, y, case in zip(a, b, cases):
        assert x == y, (x, y, case)
print(f"PASS {len(cases)} RC1 house road-type decisions with native tile projection")
