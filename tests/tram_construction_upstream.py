"""Compare tram geometry and drive-through quote against compiled OpenTTD 14.1."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "depot_func.h":"65f213680946622fb9f6c02e0e44d7f1047872affd2e5e5f44989450d28bae5c",
    "road_map.cpp":"dc6f929c776003c357dec11cd6a4ddc890fa0ccaa68a67c525daaf9d0495953a",
    "station_cmd.cpp":"7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5",
    "slope_type.h":"3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9",
    "slope_func.h":"1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a",
    "roadtypes.h":"3c150f1e160184dffa733e22ba90b1076482e51d3e2176ca3f626227ef7a1afd",
}
def read(name):
    for p in (SRC/name,SRC/"src"/name,SRC/"src/table"/name):
        if p.exists():
            b=p.read_bytes();assert sha256(b).hexdigest()==PINS[name],name
            return b.decode()
    raise FileNotFoundError(name)

def block(text,start):
    a=text.index(start);b=text.index("{",a)
    balance=1
    while balance and b<len(text):
        b+=1;balance+=(text[b]=="{")-(text[b]=="}")
    assert not balance
    return text[a:b+1]

tt=read("slope_type.h")
st=read("station_cmd.cpp")
depot=block(read("depot_func.h"),"inline bool CanBuildDepotByTileh")
inclined=block(read("slope_func.h"),"inline Slope InclinedSlope(DiagDirection")
buildable=block(st,"CommandCost CheckBuildableTile(")
stop=block(st,"static CommandCost CheckFlatLandRoadStop(")
road_bits=block(read("road_map.cpp"),"RoadBits GetAnyRoadBits(")
tram=read("roadtypes.h").split("/* Electrified Tram */",1)[1]
m=re.search(r"/\* flags \*/\s+(.*?),\s*/\* cost multiplier \*/\s+(\d+),\s*/\* maintenance cost multiplier \*/\s+(\d+),",tram)
assert m
errors=sorted(set(re.findall(r"STR_ERROR_[A-Z_]+",buildable+stop)))
SHIM=r"""
#include <cstdio>
#include <cstdlib>
#include <cassert>
using byte=unsigned char;
using uint=unsigned;
using TileIndex=int;
using Tile=int;
using DoCommandFlag=int;
using RoadBits=int;
using RoadTramType=int;
using RoadType=int;
using Owner=int;
using StationID=int;
using Axis=int;
using DiagDirection=int;
enum {DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END,DIAGDIR_BEGIN=0};
enum { AXIS_X,AXIS_Y, ROAD_NONE=0, ROAD_X=10, ROAD_Y=5, RTT_ROAD=0,RTT_TRAM=1 };
enum { MP_CLEAR,MP_ROAD,MP_STATION,MP_TUNNELBRIDGE,MP_RAILWAY };
enum { ROAD_TILE_NORMAL,ROAD_TILE_CROSSING,ROAD_TILE_DEPOT };
enum { TRANSPORT_ROAD=1,OWNER_TOWN=2,OWNER_NONE=3,INVALID_STATION=-1,INVALID_ROADTYPE=-1,
    EXPENSES_CONSTRUCTION,PR_BUILD_FOUNDATION=0,DRD_NONE=0,DC_AUTO=0,CMD_LANDSCAPE_CLEAR,
    ROTFB_CATENARY=1, ROTFB_NO_HOUSES=4 };
#define NOT_REACHED() std::abort()
"""+"enum {"+",".join(errors)+"};\n"+block(tt,"enum Corner {")+";\n"+block(tt,"enum Slope : byte {")+";\n"+r"""
struct CommandCost {
    int value;
    CommandCost(int=EXPENSES_CONSTRUCTION,int cost=0):value(cost){}
    bool Failed() const {return value<0;}
    void AddCost(CommandCost other){value+=other.value;}
    void AddCost(int other){value+=other;}
};
#define return_cmd_error(error) return CommandCost(0,-(error)-1)
constexpr int _price[]={250};
bool HasBit(uint n,int d){return n&(1u<<d);}
int CountBits(int n){return __builtin_popcount(n);}
bool HasExactlyOneBit(int n){return n&&!(n&(n-1));}
bool IsSteepSlope(Slope s){return s&SLOPE_STEEP;}
int GetSlopeMaxZ(Slope s){return !s?0:IsSteepSlope(s)?2:1;}
int DiagDirToAxis(int d){return d&1;}
int ReverseDiagDir(int d){return (d+2)&3;}
int AxisToRoadBits(int a){return a?5:10;}
int DiagDirToRoadBits(int d){return 8>>d;}
struct {struct {bool build_on_slopes,road_stop_on_town_road,road_stop_on_competitor_road;} construction;} _settings_game;
struct Company {static bool IsValidID(int o){return o==0||o==1;}};
enum { OWNER_A=0, OWNER_B=1 };
struct Rec {
    int type=MP_CLEAR,subtype=ROAD_TILE_NORMAL,dir=0,overhead=0,occupied=0,
        base=2,rr=INVALID_ROADTYPE,tr=INVALID_ROADTYPE,rbits=0,tbits=0,
        ro=OWNER_A,to=OWNER_A,drd=DRD_NONE,through=0,transport=TRANSPORT_ROAD,
        station=0,has_stop=0;
    Slope slope=SLOPE_FLAT;
} state;
bool MayHaveRoad(Tile){return state.type==MP_ROAD||state.type==MP_TUNNELBRIDGE||state.type==MP_STATION;}
int GetTileType(int){return state.type;}
bool IsTileType(int t,int type){return GetTileType(t)==type;}
int GetRoadTileType(int){return state.subtype;}
bool IsNormalRoadTile(int){return state.type==MP_ROAD&&state.subtype==ROAD_TILE_NORMAL;}
bool IsRoadStopTile(int){return state.has_stop;}
bool IsRoadStop(int t){return IsRoadStopTile(t);}
bool IsDriveThroughStopTile(int){return state.through;}
bool IsTruckStop(int){return false;}
int GetStationIndex(int){return state.station;}
RoadType GetRoadType(int,int rtt){return rtt==RTT_TRAM?state.tr:state.rr;}
bool HasTileRoadType(int t,int rtt){return GetRoadType(t,rtt)!=INVALID_ROADTYPE;}
RoadBits GetRoadBits(int,int rtt){return rtt==RTT_TRAM?state.tbits:state.rbits;}
RoadBits GetAllRoadBits(int){return state.rbits|state.tbits;}
RoadBits GetCrossingRoadBits(int){return AxisToRoadBits(state.dir&1);}
int GetRoadDepotDirection(int){return state.dir;}
int GetRoadStopDir(int){return state.dir;}
int GetTunnelBridgeTransportType(int){return state.transport;}
int GetTunnelBridgeDirection(int){return state.dir;}
int GetDisallowedRoadDirections(int){return state.drd;}
Owner GetRoadOwner(int,int rtt){return rtt==RTT_TRAM?state.to:state.ro;}
bool RoadTypeIsTram(RoadType rt){return rt>0;}
bool RoadTypeIsRoad(RoadType rt){return rt==0;}
bool HasPowerOnRoad(RoadType a,RoadType b){return a==b;}
int RoadBuildCost(RoadType rt){return rt?190:95;}
bool IsBridgeAbove(int){return state.overhead;}
CommandCost EnsureNoVehicleOnGround(int){return state.occupied?CommandCost(0,-80):CommandCost();}
Slope GetTileSlope(int,int *z){*z=state.base;return state.slope;}
CommandCost CheckOwnership(Owner own){return own==OWNER_A||own==OWNER_NONE?CommandCost():CommandCost(0,-81);}
CommandCost ClearTile_Station(int,int){return CommandCost(0,-82);}
template<int> struct Command {
    static CommandCost Do(int,int){return {};}
};
"""+inclined+"\n"+depot+"\n"+buildable+"\n"+stop+"\n"+road_bits+r"""
int main(){
    constexpr int slopes[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30};
    std::printf("p %d %d %d\n","""+",".join(m.groups())+r""");
    for(int s:slopes)for(int d=0;d<4;d++)
        std::printf("d %d %d %d\n",s,d,s==0||CanBuildDepotByTileh(d,(Slope)s));
    for(int type=0;type<=4;type++)for(int sub=0;sub<=2;sub++)for(int d=0;d<4;d++)
    for(int tram=0;tram<2;tram++)for(int variants=0;variants<16;variants++){
        state={};state.dir=d;state.type=type;state.subtype=sub;
        state.tr=tram?1:INVALID_ROADTYPE;state.tbits=variants;
        state.has_stop=variants&1;state.through=variants&2;
        if(type==MP_STATION && state.through)state.dir&=1;
        state.transport=variants&4?TRANSPORT_ROAD:0;
        for(int inside=0;inside<2;inside++)
            std::printf("b %d %d %d %d %d %d %d\n",type,sub,d,tram,variants,inside,GetAnyRoadBits(100,RTT_TRAM,inside));
    }
    for(int axis=0;axis<2;axis++)for(int s:slopes)for(int opts=0;opts<32;opts++)
    for(int r=0;r<16;r++)for(int t=0;t<16;t++){
        state={};state.type=MP_ROAD;state.slope=(Slope)s;
        state.rr=r?0:INVALID_ROADTYPE;state.tr=t?1:INVALID_ROADTYPE;
        state.rbits=r;state.tbits=t;
        _settings_game.construction.build_on_slopes=opts&1;
        _settings_game.construction.road_stop_on_competitor_road=opts&2;
        _settings_game.construction.road_stop_on_town_road=opts&4;
        state.ro=opts&8?int(OWNER_TOWN):int(OWNER_B);
        state.to=opts&16?OWNER_A:OWNER_B;
        state.drd=(r+opts)%2;
        int z=-1;
        auto p=CheckFlatLandRoadStop(100,z,0,(1u<<axis)|(1u<<(axis+2)),true,false,axis,nullptr,1);
        std::printf("s %d %d %d %d %d %d %d\n",axis,s,opts,r,t,p.value,z);
    }
}
"""
LABELS={
    "STR_ERROR_DRIVE_THROUGH_DIRECTION":"DRIVE_THROUGH_DIRECTION",
    "STR_ERROR_DRIVE_THROUGH_CORNER":"DRIVE_THROUGH_CORNER",
    "STR_ERROR_DRIVE_THROUGH_JUNCTION":"DRIVE_THROUGH_JUNCTION",
    "STR_ERROR_DRIVE_THROUGH_ON_TOWN_ROAD":"DRIVE_THROUGH_ON_TOWN_ROAD",
    "STR_ERROR_FLAT_LAND_REQUIRED":"FLAT_LAND_REQUIRED",
    "STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST":"MUST_DEMOLISH_BRIDGE_FIRST",
}
LUA=r"""
local root="mods/luanttd_core/openttd/"
local B=dofile(root.."road_bridge.lua")(dofile(root.."slope.lua"))
local T=dofile(root.."tram_construction.lua")(dofile(root.."road_slope.lua"),B.roadtypes)
local n={p=0,d=0,b=0,s=0}
local errors={[-81]="OWNED_BY_ANOTHER"}
"""+ "\n".join(f'errors[{-i-1}]="{LABELS[k]}"' for i,k in enumerate(errors) if k in LABELS)+r"""
local function hit(a,i) return math.floor(a/2^i)%2==1 end
for line in io.lines() do
  local mode=line:sub(1,1)
  local a={}
  for k in line:gmatch("-?%d+") do a[#a+1]=tonumber(k) end
  n[mode]=n[mode]+1
  if mode=="p" then
    local rt=B.roadtypes[1]
    assert(rt.flags==a[1] and rt.cost_multiplier==a[2] and rt.maintenance_multiplier==a[3],line)
  elseif mode=="d" then
    assert(T.can_depot_slope(a[2],a[1])==(a[3]==1),line)
  elseif mode=="b" then
    local t={tramtype=a[4]==1 and 1 or nil,tram_bits=a[5],dir=a[3],axis=a[3]%2,
      transport=hit(a[5],2) and "road" or "rail"}
    if a[1]==1 then t.kind=({[0]="road","crossing","depot"})[a[2]]
    elseif a[1]==2 and hit(a[5],0) then t.kind=hit(a[5],1) and "drive_stop" or "bay_stop"
    elseif a[1]==3 then t.kind=hit(a[5],0) and "bridge" or "tunnel" end
    assert(T.effective_bits(t,a[6]==1)==a[7],line)
  elseif mode=="s" then
    local p,why=T.stop({kind="road",base=2,slope=a[2],roadtype=a[4]>0 and 0 or nil,
      tramtype=a[5]>0 and 1 or nil,road_bits=a[4],tram_bits=a[5],
      road_owner=hit(a[3],3) and "town" or "B",tram_owner=hit(a[3],4) and "A" or "B",
      disallowed=(a[4]+a[3])%2},a[1],1,{owner="A",build_on_slopes=hit(a[3],0),
      on_competitor_road=hit(a[3],1),on_town_road=hit(a[3],2)})
    if a[6]<0 then assert(not p and why==errors[a[6]],line.." "..tostring(why))
    else assert(p and p.cost==a[6]+200 and p.base==a[7],line.." "..tostring(why)) end
  end
end
assert(n.p==1 and n.d==76 and n.b==3840 and n.s==311296)
print(("PASS: exact stock ELRL flags/prices, %d depot grades, %d effective tile bits, %d drive-through legality and cost cases"):format(n.d,n.b,n.s))
"""
with tempfile.TemporaryDirectory() as directory:
    p=Path(directory)
    (p/"reference.cpp").write_text(SHIM)
    (p/"verify.lua").write_text(LUA)
    subprocess.run(["c++","-std=c++17","-O2",p/"reference.cpp","-o",p/"reference"],check=True)
    expected=subprocess.check_output([p/"reference"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],
        cwd=ROOT,input=expected,check=True)
