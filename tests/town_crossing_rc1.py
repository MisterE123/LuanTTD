#!/usr/bin/env python3
"""Check the stock road-command branch that towns use to cross existing rail."""
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import re
import subprocess
import sys

from rc1_rail_foundation_shim import source_block

root = Path(sys.argv[1])
assert subprocess.check_output(["git","-C",root,"rev-parse","HEAD"],text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src = root / "src"
lua = sys.argv[2] if len(sys.argv)>2 else "lua5.1"
road_cmd=source_block(src,"road_cmd.cpp",r"^CommandCost CmdBuildRoad\(")
begin=road_cmd.index("case TileType::Railway:")
stop=road_cmd.index("case TileType::Station:",begin)
branch=road_cmd[begin:stop].strip()
cpp=r"""
#include <cassert>
#include <cstdint>
#include <iostream>
using TileIndex=int;
using uint=unsigned;
using RailType=int;
constexpr int OWNER_TOWN=-2,OWNER_DEITY=-3,town_id=7,rt=0,INVALID_ROADTYPE=-1;
constexpr int STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION=1,STR_ERROR_CROSSING_DISALLOWED_ROAD=2,
    STR_ERROR_CROSSING_DISALLOWED_RAIL=3,LEVELCROSSING_TRACKBIT_FACTOR=2;
enum class TileType{Railway,Station};
enum class RailTileType{Normal,Depot};
enum class Axis{X,Y};
enum class Track{X,Y};
enum class RoadTramType{Road,Tram};
enum class ExpensesType{Construction};
enum class DoCommandFlag{Execute};
struct RoadBits{
 unsigned b;
 bool Any(RoadBits rhs)const{return b&rhs.b;}
};
struct TrackBits{
 unsigned b;
 constexpr TrackBits(unsigned n):b(n){}
 constexpr TrackBits(Track t):b(1u<<int(t)){}
 constexpr unsigned base()const{return b;}
};
constexpr RoadBits ROAD_X{10},ROAD_Y{5};
struct CommandCost{
 int error=0,cost=0;
 CommandCost()=default;
 CommandCost(ExpensesType,int cost):cost(cost){}
 CommandCost(int error):error(error){}
 bool Failed()const{return error!=0;}
};
struct Flags{bool Test(DoCommandFlag)const{return true;}} flags;
struct RailRecord{
 int slope,mask,occupied,kind,deny,road_deny,hold,owner,competitor;
} q;
struct Crossing{int axis=-1,road_owner=-1,rail_owner=-1,town=-1,held=0;} made;
struct Settings{struct {bool crossing_with_competitor;} construction;} _settings_game;
struct Company{
 struct {int rail[4]{};} infrastructure;
 int index=0;
 static Company *GetIfValid(int);
} company_rail;
Company *Company::GetIfValid(int owner){return owner>=0?&company_rail:nullptr;}
bool IsSteepSlope(int s){return s&16;}
bool HasBit(uint v,int b){return v&(1u<<b);}
CommandCost CheckTileOwnership(int){return CommandCost{5};}
RailTileType GetRailTileType(int){return RailTileType(q.kind);}
bool RoadNoLevelCrossing(int){return q.road_deny;}
bool RailNoLevelCrossings(int){return q.deny;}
TrackBits GetTrackBits(int){return {unsigned(q.mask)};}
int GetRailType(int){return 0;}
int GetTileOwner(int){return q.owner;}
CommandCost EnsureNoVehicleOnGround(int){return q.occupied?CommandCost{4}:CommandCost{};}
Axis OtherAxis(Axis a){return Axis(1-int(a));}
Track AxisToTrack(Axis a){return Track(int(a));}
void YapfNotifyTrackLayoutChange(int,Track){}
void UpdateCompanyRoadInfrastructure(int,int owner,int count){assert(owner==OWNER_TOWN && count==2);}
void DirtyCompanyInfrastructureWindows(int){}
struct Reservation{bool Test(Track t)const{return q.hold&(1<<int(t));}};
Reservation GetRailReservationTrackBits(int){return {};}
void MakeRoadCrossing(int,int road,int tram,int rail,Axis axis,int railtype,int roadtype,int tramtype,int town){
  assert(road==tram && railtype==0 && roadtype==0 && tramtype==-1);
  made={int(axis),road,rail,town,0};
}
void SetCrossingReservation(int,bool reserved){made.held=reserved;}
void UpdateLevelCrossing(int,bool){}
Axis GetCrossingRoadAxis(int){return Axis(made.axis);}
void MarkDirtyAdjacentLevelCrossingTiles(int,Axis){}
void MarkTileDirtyByTile(int){}
"""
cpp += "template<class Enum> constexpr int to_underlying(Enum value){return int(value);}\n"
cpp += source_block(src,"slope_type.h",r"^enum class Corner :")
cpp += source_block(src,"slope_type.h",r"^enum Slope :")
raw=(src/"slope_type.h").read_text()
cpp+="#define M(a) (1U << (a))\n"+re.search(r"^static const uint32_t VALID_LEVEL_CROSSING_SLOPES.*",raw,re.M)[0]+"\n"
cpp+=r"""
CommandCost quote(RoadBits pieces){
 int tile=0,tileh=q.slope,company=OWNER_TOWN;
 auto rtt=RoadTramType::Road;
 auto RoadBuildCost=[](int){return 95;};
 switch(TileType::Railway){
"""+branch+r"""
 default: break;
 }
 do_clear:return CommandCost{6};
}
int main(){
 unsigned mask;
 while(std::cin>>q.slope>>q.mask>>mask>>q.occupied>>q.kind>>q.deny>>q.road_deny>>q.hold>>q.owner>>q.competitor){
   _settings_game.construction.crossing_with_competitor=q.competitor;
   made=Crossing{};
   auto r=quote({mask});
   std::cout<<r.error<<" "<<r.cost<<" "<<made.axis<<" "<<made.road_owner<<" "<<made.rail_owner<<" "<<made.town<<" "<<made.held<<"\n";
 }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local T=dofile(p.."rail_track.lua")
local C=dofile(p.."level_crossing.lua")(T)
local errors={LAND_SLOPED_IN_WRONG_DIRECTION=1,CROSSING_DISALLOWED_ROAD=2,CROSSING_DISALLOWED_RAIL=3,
  VEHICLE_IN_THE_WAY=4,OWNED_BY_ANOTHER=5,FALLBACK_CLEAR=6}
for line in io.lines() do
 local a={}
 for w in line:gmatch("%S+") do a[#a+1]=tonumber(w) end
 local slope,track,pieces,occ,kind,rdeny,d,hold,owner,competition=unpack(a)
 local q,e=C.quote({kind=kind==0 and "rail" or "rail_depot",slope=slope,trackbits=track,
   occupied=occ==1,reserved_bits=hold,owner=owner,railtype=0},
   {kind="road",owner="town",pieces=pieces,town=7},
   {crossing_with_competitor=competition==1,
    road_types={[0]={no_crossing=d==1}},rail_types={[0]={no_crossing=rdeny==1}}})
 if q then print(0,q.cost,q.road_axis,q.road_owner=="town" and -2 or -1,q.rail_owner,q.town,q.reserved and 1 or 0)
 else print(assert(errors[e],e),0,-1,-1,-1,-1,0) end
end
"""
cases=[]
for slope in (0,1,3,5,7,10,11,13,14,16,17):
    for track in (1,2,3,4,8,32):
        for bits in range(1,16):
            for flags in range(16):
                cases.append([slope,track,bits,flags&1,flags>>1&1,flags>>2&1,0,
                              track if flags>>3 else 0,9,0])
# Road types disallowed by the setting are also exercised, but a refusal
# must not be conflated with terrain, occupancy or the fallback-clear path.
cases.extend(([0,track,bits,0,0,0,1,track,9,0] for track in (1,2) for bits in (2,4,5,10)))
data="".join(" ".join(map(str,r))+"\n" for r in cases)
with TemporaryDirectory(prefix="town-crossing-rc1-") as d:
    d=Path(d)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    a,b=[subprocess.check_output(cmd,input=data,text=True).splitlines() for cmd in ([d/"ref"],[lua,d/"test.lua"])]
    assert len(a)==len(b)==len(cases)
    errors=[(i,cases[i],x,y) for i,(x,y) in enumerate(zip(a,b)) if x.split()!=y.split()]
    assert not errors,(len(errors),errors[:12])
print(f"PASS {len(cases)} RC1 municipal crossing command cases (axis, ownership, reservation, cost and rejection)")
