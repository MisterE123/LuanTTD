"""Build OpenTTD 14.1 water status and ship YAPF costs against a small C++ map shim."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "water_cmd.cpp":"f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847",
    "station_cmd.cpp":"7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5",
    "tunnelbridge_cmd.cpp":"48b5401e1262964cb961b266a4dd0cf81d171a7f60e264597be8e4f138fad305",
    "rail_cmd.cpp":"09c9ddedb7d94af9f21bcb2f71859f93b96bf9dbaab9d5eb1da51de11d9972d9",
    "ship_cmd.cpp":"f664841259821ee557109c15f2f2e6497b7416030a78e0275875f47f1fb8851a",
    "yapf_ship.cpp":"4dc25b9dff5922c6c95c9cb70c954f3b72bd5e467a0e450a997f3f31a56418ac",
    "rail.cpp":"1d990c0a35ef14c1fc072ace3952734bac087f7981d18943932a96de8e1f0887",
    "track_type.h":"db919468ff6a319383fe936d081933048c8c23d97ea95c869b269e404059b9e8",
    "pathfinding_settings.ini":"8d5e898307aa12be1f9fee610caaafa76f902c4ed8c3217167e011fc4dc7bd80",
}
def read(name):
    for d in ("","src","src/pathfinder/yapf","src/table/settings"):
        p=SRC/d/name
        if p.is_file():
            data=p.read_bytes()
            assert sha256(data).hexdigest()==PINS[name],name
            return data.decode()
    raise FileNotFoundError(name)

def block(text,pattern):
    a=re.search(pattern,text,re.M).start()
    b=text.index("{",a);n=1
    while n:
        b+=1;n+=(text[b]=="{")-(text[b]=="}")
    return text[a:b+1]

rail=read("rail.cpp")
ship=read("yapf_ship.cpp")
tracks=read("track_type.h")
settings=read("pathfinding_settings.ini")
defaults=[re.search(r"ship_curve"+a+r"_penalty.*?def\s*=\s*([^\n]+)",settings,re.S).group(1)
          for a in ("45","90")]
CPP=r"""
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
using byte=uint8_t;
using uint=unsigned;
using TileIndex=int;
enum DiagDirection {DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,INVALID_DIAGDIR};
enum TransportType {TRANSPORT_RAIL,TRANSPORT_ROAD,TRANSPORT_WATER};
enum {WATER_TILE_CLEAR,WATER_TILE_COAST,WATER_TILE_LOCK,WATER_TILE_DEPOT};
enum {RTT_ROAD,RTT_TRAM,MP_WATER,MP_TUNNELBRIDGE,MP_RAILWAY,MP_STATION,MP_INDUSTRY};
enum {RAIL_GROUND_WATER,RAIL_GROUND_GRASS};
enum WaterClass {WATER_CLASS_SEA,WATER_CLASS_CANAL,WATER_CLASS_RIVER,WATER_CLASS_INVALID};
using TrackStatus=uint32_t;
using Axis=int;
#define NOT_REACHED() std::abort()
"""+ "".join(block(tracks,pat)+";\n" for pat in (r"^enum Track :",r"^enum TrackBits",r"^enum Trackdir :",r"^enum TrackdirBits"))+r"""
#define BITOPS(T) \
    T operator&(T a,T b){return T(int(a)&int(b));} \
    T operator|(T a,T b){return T(int(a)|int(b));} \
    T operator~(T a){return T(~int(a));} \
    T& operator&=(T &a,T b){return a=a&b;}
BITOPS(TrackBits)
BITOPS(TrackdirBits)
TrackBits AxisToTrackBits(Axis a){return TrackBits(1<<a);}
TrackBits TrackToTrackBits(Track t){return TrackBits(1<<t);}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((d+2)%4);}
Axis DiagDirToAxis(DiagDirection d){return d%2;}
TrackBits DiagDirToDiagTrackBits(DiagDirection d){return AxisToTrackBits(DiagDirToAxis(d));}
TrackdirBits TrackBitsToTrackdirBits(TrackBits b){return TrackdirBits(b*257);}
TrackStatus CombineTrackStatus(TrackdirBits m,TrackdirBits s){return uint(m)|(uint(s)<<16);}
"""+ "".join(block(rail,pat)+";\n" for pat in (r"^extern const TrackdirBits _track_crosses_trackdirs",
r"^extern const DiagDirection _trackdir_to_exitdir",r"^extern const Trackdir _next_trackdir"))+r"""
TrackdirBits TrackdirCrossesTrackdirs(Trackdir d){return _track_crosses_trackdirs[d%8];}
Trackdir NextTrackdir(Trackdir d){return _next_trackdir[d];}
bool IsValidTrackdir(Trackdir td){return td>=0&&td<14&&td%8<6;}
bool HasTrackdir(TrackdirBits b,Trackdir t){return b&(1<<t);}
bool IsDiagonalTrackdir(Trackdir td){return td%8<2;}
DiagDirection TrackdirToExitdir(Trackdir td){return _trackdir_to_exitdir[td];}

struct Rec {int kind,x,z,slope,dir,cls,half;bool plain,docking;int visible;} tile;
const int K_SEA=0,K_CANAL=1,K_RIVER=2,K_COAST=3,K_LOCK=4,K_DEPOT=5,K_BUOY=6,K_AQ=7,K_RAIL=8,K_DOCK=9;
int GetWaterTileType(TileIndex){return tile.kind<=2?WATER_TILE_CLEAR:tile.kind-2;}
int GetTileSlope(TileIndex){return tile.slope;}
bool IsTileFlat(TileIndex){return !tile.slope;}
bool IsSlopeWithOneCornerRaised(int s){return s==1||s==2||s==4||s==8;}
DiagDirection GetLockDirection(TileIndex){return DiagDirection(tile.dir);}
DiagDirection GetTunnelBridgeDirection(TileIndex){return DiagDirection(tile.dir);}
TransportType GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_WATER;}
Axis GetShipDepotAxis(TileIndex){return tile.dir%2;}
int TileX(TileIndex t){return t%64;}
int TileY(TileIndex t){return t/64;}
bool HasStationRail(TileIndex){return false;}
bool IsStationTileBlocked(TileIndex){return false;}
Track GetRailStationTrack(TileIndex){return TRACK_X;}
bool IsRoadStop(TileIndex){return false;}
bool IsBayRoadStopTile(TileIndex){return false;}
bool IsDriveThroughStopTile(TileIndex){return false;}
DiagDirection GetRoadStopDir(TileIndex){return DIAGDIR_NE;}
bool HasTileRoadType(TileIndex,int){return false;}
using RoadTramType=int;
bool IsBuoy(TileIndex){return tile.kind==K_BUOY;}
bool IsTileType(TileIndex,int t){return tile.kind==K_AQ?t==MP_TUNNELBRIDGE:tile.kind==K_RAIL?t==MP_RAILWAY:false;}
bool HasTileWaterClass(TileIndex){return tile.kind!=K_AQ&&tile.kind!=K_RAIL;}
WaterClass GetWaterClass(TileIndex){return WaterClass(tile.cls);}
int GetRailGroundType(TileIndex){return RAIL_GROUND_WATER;}
bool IsPlainRail(TileIndex){return tile.plain;}
TrackBits GetTrackBits(TileIndex){return TrackBits(tile.half);}
"""+block(read("water_cmd.cpp"),r"^static TrackStatus GetTileTrackStatus_Water")+"\n"+block(read("station_cmd.cpp"),
r"^static TrackStatus GetTileTrackStatus_Station")+"\n"+block(read("tunnelbridge_cmd.cpp"),
r"^static TrackStatus GetTileTrackStatus_TunnelBridge")+"\n"+r"""
static TrackStatus GetTrackStatusShoreRail(TileIndex tile,TransportType mode) {
    """+block(read("rail_cmd.cpp"),r"^\s*if \(mode == TRANSPORT_WATER && IsPlainRail\(tile\)") +r"""
    return 0;
}
"""+block(read("ship_cmd.cpp"),r"^WaterClass GetEffectiveWaterClass")+"\n"+r"""
constexpr int YAPF_TILE_LENGTH=100,YAPF_TILE_CORNER_LENGTH=71;
struct Vehicle {int type,vehstatus;};
enum {VEH_SHIP=0,VS_HIDDEN=1,VEH_AIRCRAFT=2};
struct ShipVehicleInfo {byte ocean_speed_frac,canal_speed_frac;} fractions;
const ShipVehicleInfo *ShipVehInfo(int){return &fractions;}
bool IsDockingTile(TileIndex){return tile.docking;}
using CountMethod=Vehicle *(*)(Vehicle *, void *);
bool HasVehicleOnPos(TileIndex,void *data,CountMethod callback){
    Vehicle v={VEH_SHIP,0};
    for(int i=0;i<tile.visible;i++)callback(&v,data);
    v.vehstatus=VS_HIDDEN;callback(&v,data);
    v.type=VEH_AIRCRAFT;v.vehstatus=0;callback(&v,data);
    return false;
}
struct TrackFollower {int m_tiles_skipped;};
struct Node {
    Node *m_parent=nullptr;
    Trackdir td=Trackdir(0),m_segment_last_td=Trackdir(0);
    TileIndex id=0,m_segment_last_tile=0;
    int m_cost=0,m_estimate=0;
    Trackdir GetTrackdir()const{return td;}
    int GetTile()const{return id;}
};
struct Test {
    struct {int ship_curve45_penalty="""+defaults[0]+",ship_curve90_penalty="+defaults[1]+r""";} setting;
    struct {int engine_type=0;} v;
    Test &Yapf(){return *this;}
    const auto &PfGetSettings(){return setting;}
    const auto *GetVehicle(){return &v;}
    TileIndex m_destTile=1,m_intermediate_dest_tile=0;
    bool m_has_intermediate_dest=false;
    bool PfDetectDestination(Node &n){return m_destTile==n.id;}
"""+"\n".join(block(ship,pat) for pat in (r"^\s*inline int CurveCost\(",r"^\s*static Vehicle \*CountShipProc",
  r"^\s*inline bool PfCalcCost\(",r"^\s*inline bool PfCalcEstimate\("))+r"""
};
int main(){
    Test test;
    std::printf("d %d %d\n",test.setting.ship_curve45_penalty,test.setting.ship_curve90_penalty);
    for(int k=0;k<10;k++)for(int slope=0;slope<=30;slope++)for(int dir=0;dir<4;dir++)
    for(int edge=0;edge<4;edge++)for(int side=0;side<=4;side++){
        tile={k,edge&1,(edge>>1)&1,slope,dir,k<=2?k:0,4<<dir,true,false,0};
        int id=tile.z*64+tile.x;
        TrackStatus s=0;
        if(k<=K_DEPOT) s=GetTileTrackStatus_Water(id,TRANSPORT_WATER,0,DiagDirection(side));
        else if(k==K_AQ) s=GetTileTrackStatus_TunnelBridge(id,TRANSPORT_WATER,0,DiagDirection(side));
        else if(k==K_RAIL) s=GetTrackStatusShoreRail(id,TRANSPORT_WATER);
        else s=GetTileTrackStatus_Station(id,TRANSPORT_WATER,0,DiagDirection(side));
        std::printf("w %d %d %d %d %d %d %d\n",k,slope,dir,tile.x,tile.z,side,s);
    }
    constexpr int frac[]={0,1,7,32,64,127,128,214,254,255};
    for(int kind : {0,1,2,7,8}) for(int a=0;a<14;a++)for(int b=0;b<14;b++)
    for(int d=0;d<4;d++)for(int speed=0;speed<10;speed++)for(int skip : {0,1,9,63}){
        if(!IsValidTrackdir(Trackdir(a))||!IsValidTrackdir(Trackdir(b)))continue;
        tile={kind,0,0,0,0,kind%3,4,true,d!=0,d};
        fractions={byte(frac[speed]),byte(frac[(speed+3)%10])};
        Node parent,n;parent.m_cost=123;parent.td=Trackdir(a);
        n.td=Trackdir(b);n.m_parent=&parent;
        TrackFollower f{skip};
        test.PfCalcCost(n,&f);
        std::printf("c %d %d %d %d %d %d %d %d\n",kind,a,b,d,fractions.ocean_speed_frac,
            fractions.canal_speed_frac,skip,n.m_cost-123);
    }
    for(int td=0;td<14;td++)for(int id=65;id<160;id++)for(int dest=45;dest<180;dest+=3){
        if(!IsValidTrackdir(Trackdir(td)))continue;
        Node parent,n;n.m_parent=&parent;
        n.id=n.m_segment_last_tile=id;n.td=n.m_segment_last_td=Trackdir(td);n.m_cost=3400;
        test.m_destTile=dest;
        test.PfCalcEstimate(n);
        std::printf("e %d %d %d %d\n",td,id,dest,n.m_estimate);
    }
}
"""
LUA=r"""
local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local W=dofile(root.."ship_follow.lua")(T)
local C=dofile(root.."ship_yapf.lua")(T,W,dofile(root.."yapf_road_search.lua"))
local kinds={[0]="sea","canal","river","coast","lock","ship_depot","buoy","aqueduct","shore_rail","dock"}
local t,visible
local B={
  tile=function(i)return t end,
  xy=function(i)return i%64,math.floor(i/64)end,
  docking_occupancy=function()return visible end
}
local n={d=0,w=0,c=0,e=0}
for line in io.lines() do
  local m=line:sub(1,1)
  local a={}
  for k in line:gmatch("%d+") do a[#a+1]=tonumber(k) end
  n[m]=n[m]+1
  if m=="d" then
    assert(C.default_settings.ship_curve45_penalty==a[1] and C.default_settings.ship_curve90_penalty==a[2],line)
  elseif m=="w" then
    t={kind=kinds[a[1]],slope=a[2],dir=a[3],axis=a[3]%2,rail_bits=4*2^a[3]}
    local side=a[6]~=4 and a[6] or nil
    local q=W.status(t,a[4],a[5],side)
    assert(q==a[7],line.." -> "..q)
  elseif m=="c" then
    t={kind=kinds[a[1]],docking=a[4]>0}
    visible=a[4]
    local q=C.tile_cost(B,{ocean_speed_frac=a[5],canal_speed_frac=a[6]},1,a[3],a[2],a[7])
    assert(q==a[8],line.." -> "..q)
  else
    t={kind="sea"}
    local q=C.estimate(B,{kind="tile",tile=a[3],trackdirs=0x3f3f},{last_tile=a[2],last_td=a[1],cost=3400})
    assert(q==a[4],line.." -> "..q)
  end
end
assert(n.d==1 and n.w==24800 and n.c==115200 and n.e==51300)
print(("PASS: OpenTTD 14.1 compared %d water status, %d cost and %d estimates"):format(n.w,n.c,n.e))
"""
with tempfile.TemporaryDirectory() as d:
    tmp=Path(d)
    (tmp/"reference.cpp").write_text(CPP)
    (tmp/"verify.lua").write_text(LUA)
    subprocess.run(["c++","-std=c++17","-O2",tmp/"reference.cpp","-o",tmp/"reference"],check=True)
    expected=subprocess.check_output([tmp/"reference"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",tmp/"verify.lua"],cwd=ROOT,input=expected,check=True)
