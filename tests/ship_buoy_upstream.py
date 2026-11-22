#!/usr/bin/env python3
"""Compile and compare the OpenTTD 14.1 CmdBuildBuoy query against Lua."""
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "waypoint_cmd.cpp": "d9dda3d6b0bb6a2b1bf8b604e6faac62029d08f7d0bd39f7c8a971bba65c6403",
    "table/pricebase.h": "17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
})

SHIM = r"""
#include <cassert>
#include <iostream>
using TileIndex=int;
using DoCommandFlag=int;
constexpr int DC_AUTO=1,DC_EXEC=2,CMD_LANDSCAPE_CLEAR=3,EXPENSES_CONSTRUCTION=0,
  STR_ERROR_SITE_UNSUITABLE=1,STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST=2,
  STR_ERROR_TOO_MANY_STATIONS_LOADING=3,STR_SV_STNAME_BUOY=4,OWNER_NONE=5,
  WC_WAYPOINT_VIEW=6,FACIL_DOCK=8;
enum {PR_BUILD_WAYPOINT_BUOY,PR_CLEAR_WAYPOINT_BUOY};
struct CommandCost {
  int error=0,cost=0;
  CommandCost()=default;
  CommandCost(int,int cost):cost(cost){}
  static CommandCost Err(int e){CommandCost c;c.error=e;return c;}
  bool Failed()const{return error!=0;}
  void AddCost(const CommandCost& c){cost+=c.cost;}
};
#define return_cmd_error(e) return CommandCost::Err(e)
struct {int wet,flat,bridge,reusable,slot,water,auto_price,klass,called;} terrain;
struct StationRect {
  static const int ADD_TRY=0;
  void BeforeAddTile(TileIndex,int){}
};
struct Waypoint {
  explicit Waypoint(TileIndex){}
  int xy=0,index=0,string_id=0,facilities=0,owner=0,build_date=0;
  void *town=nullptr;
  void UpdateVirtCoord(){}
  StationRect rect;
  static bool CanAllocateItem(){return terrain.slot;}
};
struct TimerGameCalendar {static const int date=0;};
template<int> struct Command {
  static CommandCost Do(int flags,TileIndex){
    assert(flags==DC_AUTO);
    ++terrain.called;
    if(terrain.auto_price<0)return CommandCost::Err(4);
    return CommandCost(EXPENSES_CONSTRUCTION,terrain.auto_price);
  }
};
bool HasTileWaterGround(TileIndex){return terrain.wet;}
bool IsBridgeAbove(TileIndex){return terrain.bridge;}
bool IsTileFlat(TileIndex){return terrain.flat;}
bool IsWaterTile(TileIndex){return terrain.water;}
Waypoint *FindDeletedWaypointCloseTo(TileIndex,int,int){
  static Waypoint p(0);
  return terrain.reusable?&p:nullptr;
}
int GetWaterClass(TileIndex){return terrain.klass;}
void MakeBuoy(TileIndex,int,int){}
void MakeDefaultName(Waypoint*){}
void CheckForDockingTile(TileIndex){}
void MarkTileDirtyByTile(TileIndex){}
void InvalidateWindowData(int,int){}
"""
MAIN = r"""
int main(){
  int cell;
  while(std::cin>>cell>>terrain.wet>>terrain.flat>>terrain.bridge>>terrain.reusable>>terrain.slot>>
        terrain.water>>terrain.auto_price>>terrain.klass){
    terrain.called=0;
    const auto q=CmdBuildBuoy(0,cell);
    std::cout<<q.error<<" "<<q.cost<<" "<<terrain.called<<" "<<_price[PR_CLEAR_WAYPOINT_BUOY]<<"\n";
  }
}
"""
LUA = r"""
local src="mods/bayline/openttd/"
local T=dofile(src.."rail_track.lua")
local W=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,W)
local e={BUOY_NEEDS_OPEN_WATER=1,BRIDGE_ABOVE=2,STATION_LIMIT=3,PROTECTED_TILE=4}
local classes={"sea","river","canal"}
for line in io.lines() do
  local a={}
  for n in line:gmatch("%-?%d+") do a[#a+1]=tonumber(n) end
  local t={kind="surface",owner=9,water_class=classes[a[9]],water_ground=a[2]==1,
      slope=a[3]==1 and 0 or 9,overhead=a[4]==1,is_water_tile=a[7]==1}
  local calls=0
  local out,why=D.buoy({tile=function(i) assert(i==a[1]);return t end}, a[1],{
    waypoint_slot=function()return a[5]==1 or a[6]==1 end,
    clear=function(i,v,auto)
      assert(i==a[1] and v==t and auto)
      calls=calls+1
      if a[8]<0 then return nil,"PROTECTED_TILE" end
      return a[8]
    end})
  if out then assert(out.water_class==classes[a[9]] and out.water_owner==9) end
  print(("%d %d %d %d"):format(out and 0 or assert(e[why]),out and out.cost or 0,calls,D.BUOY_CLEAR_COST))
end
"""


def main():
    source = Path(sys.argv[1])
    prices = src(source, "table/pricebase.h")
    cost, clear = (
        int(re.search(fr"{{\s*(-?\d+),.*///< {key}\b", prices)[1])
        for key in ("PR_BUILD_WAYPOINT_BUOY", "PR_CLEAR_WAYPOINT_BUOY")
    )
    original = block(src(source, "waypoint_cmd.cpp"), r"^CommandCost CmdBuildBuoy\(")
    cases = list(product((0,42), *(range(2) for _ in range(6)), (-1,0,85,400), range(1,4)))
    data = "\n".join(" ".join(map(str, row)) for row in cases) + "\n"
    with tempfile.TemporaryDirectory() as tmp:
        cpp, lua, exe = (Path(tmp) / s for s in ("stock.cpp", "port.lua", "stock"))
        cpp.write_text(SHIM + f"\nint _price[]={{{cost},{clear}}};\n" + original + MAIN)
        lua.write_text(LUA)
        subprocess.run(["c++", "-std=c++17", "-O2", str(cpp), "-o", str(exe)], check=True)
        expected = subprocess.check_output([str(exe)], input=data, text=True).splitlines()
        actual = subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1", str(lua)],
                                         cwd=ROOT, input=data, text=True).splitlines()
    assert len(cases) == len(actual) == len(expected)
    for row, a, b in zip(cases, expected, actual):
        assert a == b, (row, a, b)
    print(f"PASS {len(cases):,} pinned stock buoy quotes: flatness, water, overhead, station pool, auto-clear, original prices")


if __name__ == "__main__":
    main()
