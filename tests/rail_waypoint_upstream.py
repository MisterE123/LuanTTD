#!/usr/bin/env python3
"""Compare the original 1x1 waypoint axis/eligibility/price branches."""
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "waypoint_cmd.cpp":"d9dda3d6b0bb6a2b1bf8b604e6faac62029d08f7d0bd39f7c8a971bba65c6403",
    "table/pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
})
SHIM = r"""
#include <iostream>
using TileIndex=int; using Axis=int; using Owner=int; using StationID=int; using Slope=int;
constexpr int AXIS_X=0,AXIS_Y=1,INVALID_AXIS=-1,INVALID_STATION=-1;
constexpr int MP_RAILWAY=0,MP_STATION=1,RAIL_TILE_NORMAL=0,TRACK_BIT_X=1,TRACK_BIT_Y=2,SLOPE_FLAT=0,DC_AUTO=0;
enum { STR_ERROR_NO_SUITABLE_RAILROAD_TRACK=1, OWNER_DENIED, VEHICLE_IN_WAY, STR_ERROR_FLAT_LAND_REQUIRED,
 STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST, STR_ERROR_WAYPOINT_ADJOINS_MORE_THAN_ONE_EXISTING, STATION_IN_WAY };
struct CommandCost {
  int error=0,cost=0;
  static CommandCost Err(int x) { return {x,0}; }
  bool Succeeded()const{return error==0;}
  bool Failed()const{return error!=0;}
  void AddCost(int c){cost+=c;}
};
#define return_cmd_error(e) return CommandCost::Err(e)
struct { int kind,track,axis,shape,owner,occupied,overhead; } tile;
struct { struct { bool build_on_slopes; } construction; } _settings_game;
bool IsRailWaypointTile(TileIndex){return tile.kind==4;}
bool IsRailWaypoint(TileIndex t){return IsRailWaypointTile(t);}
bool IsTileType(TileIndex,int k){return k==MP_RAILWAY?tile.kind<=2:tile.kind==3||tile.kind==4;}
int GetRailTileType(TileIndex){return tile.kind;}
int GetRailStationAxis(TileIndex){return tile.axis;}
int GetTrackBits(TileIndex){return tile.track;}
int GetStationIndex(TileIndex){return 9;}
int GetTileOwner(TileIndex){return tile.owner;}
CommandCost CheckOwnership(int o){return o==1?CommandCost{}:CommandCost::Err(OWNER_DENIED);}
CommandCost EnsureNoVehicleOnGround(TileIndex){return tile.occupied?CommandCost::Err(VEHICLE_IN_WAY):CommandCost{};}
CommandCost ClearTile_Station(TileIndex,int){return CommandCost::Err(STATION_IN_WAY);}
int GetTileSlope(TileIndex){return tile.shape;}
bool IsSteepSlope(int a){return (a&16)!=0;}
bool IsBridgeAbove(TileIndex){return tile.overhead;}
enum {PR_BUILD_WAYPOINT_RAIL, PR_CLEAR_WAYPOINT_RAIL, PR_CLEAR_RAIL};
"""
MAIN = r"""
int main() {
  int axis,build_on_slopes;
  while(std::cin>>tile.kind>>tile.track>>tile.axis>>tile.shape>>tile.owner>>tile.occupied>>tile.overhead>>axis>>build_on_slopes){
    _settings_game.construction.build_on_slopes=build_on_slopes;
    StationID station=INVALID_STATION;
    const TileIndex cur_tile=0;
    CommandCost cost{};
    BUILD_COST
    auto legal=IsValidTileForWaypoint(cur_tile,axis,&station);
    CommandCost total_cost{};
    KEEP_RAIL_COST
    total_cost.AddCost(_price[PR_CLEAR_WAYPOINT_RAIL]);
    std::cout<<GetAxisForNewWaypoint(cur_tile)<<" "<<legal.error<<" "<<(legal.Failed()?0:cost.cost)<<" "<<
      total_cost.cost<<"\n";
  }
}
"""
LUA=r"""
local W=dofile("mods/bayline/openttd/rail_waypoint.lua")
local kinds={[0]="rail","signals","depot","station","waypoint","clear"}
local errors={NO_SUITABLE_RAILROAD_TRACK=1,OWNED_BY_ANOTHER=2,VEHICLE_IN_THE_WAY=3,
  FLAT_LAND_REQUIRED=4,MUST_DEMOLISH_BRIDGE_FIRST=5,STATION_IN_WAY=7}
for line in io.lines() do
  local a={}
  for v in line:gmatch("%d+") do a[#a+1]=tonumber(v) end
  local t={kind=kinds[a[1]],trackbits=a[2],axis=a[3],slope=a[4],owner=a[5],occupied=a[6]==1,
    overhead=a[7]==1}
  local ok,why=W.build(t,a[8],{owner=1,build_on_slopes=a[9]==1})
  local keep=assert(W.remove({kind="waypoint",axis=0,owner=1},{owner=1}))
  if t.kind=="station" then why="STATION_IN_WAY" end -- opaque upstream station clear error
  print(("%d %d %d %d"):format(W.axis(t) or -1,ok and 0 or assert(errors[why]),ok and ok.price or 0,keep.price))
end
"""


def main():
    source=Path(sys.argv[1])
    commands=src(source,"waypoint_cmd.cpp")
    station=src(source,"station_cmd.cpp")
    prices=src(source,"table/pricebase.h")
    values=[int(re.search(fr"{{\s*(-?\d+),.*///< {key}\b",prices)[1]) for key in
            ("PR_BUILD_WAYPOINT_RAIL","PR_CLEAR_WAYPOINT_RAIL","PR_CLEAR_RAIL")]
    cost=re.search(r"if \(!IsRailWaypointTile\(cur_tile\)\) cost.AddCost\(_price\[PR_BUILD_WAYPOINT_RAIL\]\);",commands)[0]
    keep=re.search(r"total_cost.AddCost\(-_price\[PR_CLEAR_RAIL\]\);",station)[0]
    cpp=SHIM+"\nint _price[]={"+",".join(map(str,values))+"};\n"
    cpp+=block(commands,r"^Axis GetAxisForNewWaypoint\(")+block(commands,r"^static CommandCost IsValidTileForWaypoint\(")
    cpp+=MAIN.replace("BUILD_COST",cost).replace("KEEP_RAIL_COST",keep)
    cases=list(product(range(6),(0,1,2,3,4,8,16,32,48,63),range(2),[*range(15),23,27,29,30],(1,2),range(2),range(2),range(2),range(2)))
    data="\n".join(" ".join(map(str,c)) for c in cases)+"\n"
    with tempfile.TemporaryDirectory() as temp:
        c,l,exe=(Path(temp)/p for p in ("oracle.cpp","adapter.lua","oracle"))
        c.write_text(cpp);l.write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",str(c),"-o",str(exe)],check=True)
        ref=subprocess.check_output([str(exe)],input=data,text=True).splitlines()
        got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(l)],cwd=ROOT,input=data,text=True).splitlines()
    assert len(ref)==len(cases)==len(got)
    for cfg,a,b in zip(cases,ref,got):
        assert a==b,(cfg,a,b)
    print(f"PASS {len(ref):,} source waypoint cases: axis, slopes, ownership, occupancy, overhead, original build and keep-track price")


if __name__=="__main__":
    main()
