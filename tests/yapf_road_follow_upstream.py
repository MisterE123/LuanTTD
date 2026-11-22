#!/usr/bin/env python3
"""Differential test the unchanged OpenTTD 14.1 road follower over synthetic tiles.

Usage: python3 tests/yapf_road_follow_upstream.py /path/to/OpenTTD [lua5.1]
The C++ shim supplies tile/vehicle records rather than running OpenTTD UI or search.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
upstream_root = Path(sys.argv[1])
def src(file, digest):
    candidates = [upstream_root / "src" / file, upstream_root / file, upstream_root / Path(file).name]
    path = next((p for p in candidates if p.is_file()), candidates[0])
    content = path.read_bytes()
    assert sha256(content).hexdigest() == digest, f"{path}: not pinned OpenTTD 14.1"
    return content.decode()

def block(source, pattern):
    start = re.search(pattern, source, re.MULTILINE).start()
    cursor = source.index("{", start)
    depth = 1
    while depth:
        cursor += 1
        depth += (source[cursor] == "{") - (source[cursor] == "}")
    return source[start:cursor + 1]

rail = src("rail.cpp", "1d990c0a35ef14c1fc072ace3952734bac087f7981d18943932a96de8e1f0887")
road = src("road_cmd.cpp", "a693439b151a675b79ffff11d97d481931524872a02e8b4818ce6dd20430b2e3")
station = src("station_cmd.cpp", "7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5")
bridge = src("tunnelbridge_cmd.cpp", "48b5401e1262964cb961b266a4dd0cf81d171a7f60e264597be8e4f138fad305")
follow = src("pathfinder/follow_track.hpp", "9c2c48e093c73f3cdf2c669757e5669543433a6b040eda36945b4960365fd39f")
pf = src("pathfinder/pathfinder_func.h", "d375de0d34da01f97a9dcebaae049df204072370220213df1d667ca401094835")
tracktype = src("track_type.h", "db919468ff6a319383fe936d081933048c8c23d97ea95c869b269e404059b9e8")
direction = src("direction_type.h", "d1cdad0afebbf6dce3d73d742ea352129ab05f0b5af30a5ba216b7030e6a085c")
roadtype = src("road_type.h", "ad06673a815b4dd3418f3353e990a25a64ba59b38b132d195c09e5ef55e4f7f0")

cpp = r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned;
using byte=uint8_t;
using uint16=uint16_t;
using TileIndex=int;
using TileIndexDiff=int;
using Owner=int;
using TrackStatus=uint32_t;
using RailTypes=uint32_t;
using RailType=int;
using RoadType=int;
enum RoadTramType {RTT_ROAD,RTT_TRAM};
enum {AXIS_X,AXIS_Y};
using Axis=int;
enum TransportType {TRANSPORT_RAIL,TRANSPORT_ROAD,TRANSPORT_WATER};
enum {MP_CLEAR,MP_ROAD,MP_STATION,MP_TUNNELBRIDGE};
enum {ROAD_TILE_NORMAL,ROAD_TILE_CROSSING,ROAD_TILE_DEPOT};
enum {VEH_TRAIN};
constexpr auto INVALID_TILE=-1;
constexpr auto INVALID_OWNER=-1;
constexpr auto INVALID_RAILTYPES=UINT32_MAX;
#define debug_inline inline
"""
for regex,source in [(r"^enum DiagDirection",direction),(r"^enum RoadBits",roadtype),(r"^enum DisallowedRoadDirections",roadtype),
                     (r"^enum Track\s*:",tracktype),(r"^enum TrackBits",tracktype),(r"^enum Trackdir\s*:",tracktype),(r"^enum TrackdirBits",tracktype)]:
    cpp+=block(source,regex)+";\n"
cpp += r"""
#define BITOPS(T) \
 T operator|(T a,T b) {return T(int(a)|int(b));} \
 T operator&(T a,T b) {return T(int(a)&int(b));} \
 T operator~(T a) {return T(~int(a));} \
 T& operator|=(T &a,T b) {return a=a|b;} \
 T& operator&=(T &a,T b) {return a=a&b;}
BITOPS(RoadBits)
BITOPS(TrackBits)
BITOPS(TrackdirBits)

DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((int(d)+2)%4);}
Axis DiagDirToAxis(DiagDirection d){return int(d)%2;}
TrackBits AxisToTrackBits(Axis a){return TrackBits(1<<a);}
TrackBits DiagDirToDiagTrackBits(DiagDirection d){return AxisToTrackBits(DiagDirToAxis(d));}
TrackBits TrackToTrackBits(Track t){return TrackBits(1<<int(t));}
TrackdirBits TrackBitsToTrackdirBits(TrackBits b){return TrackdirBits(b*257);}
TrackdirBits TrackStatusToTrackdirBits(TrackStatus s){return TrackdirBits(s&TRACKDIR_BIT_MASK);}
TrackdirBits TrackdirToTrackdirBits(Trackdir d){return TrackdirBits(1<<int(d));}
Trackdir ReverseTrackdir(Trackdir d){return Trackdir(int(d)^8);}
TrackdirBits TrackToTrackdirBits(Track t){return TrackBitsToTrackdirBits(TrackToTrackBits(t));}
TrackBits TrackdirBitsToTrackBits(TrackdirBits b){return TrackBits((b|(b>>8))&63);}
RoadBits DiagDirToRoadBits(DiagDirection dir){return RoadBits(8>>dir);}
DiagDirection AxisToDiagDir(Axis a){return DiagDirection(a==AXIS_X ? DIAGDIR_SW : DIAGDIR_SE);}
TrackStatus CombineTrackStatus(TrackdirBits bits,TrackdirBits red){return TrackStatus(bits)|(TrackStatus(red)<<16);}
template<class T> bool HasBit(uint b,T t){return t>=0 && t<32 && (b&(1u<<t));}
"""
for regex in (r"^extern const TrackdirBits _exitdir_reaches_trackdirs", r"^extern const DiagDirection _trackdir_to_exitdir",
              r"^extern const TrackdirBits _track_crosses_trackdirs"):
    cpp+=block(rail, regex)+";\n"
cpp+=r"""
DiagDirection TrackdirToExitdir(Trackdir td){return _trackdir_to_exitdir[td];}
TrackdirBits DiagdirReachesTrackdirs(DiagDirection d){return _exitdir_reaches_trackdirs[d];}
TrackdirBits TrackdirCrossesTrackdirs(Trackdir td){return _track_crosses_trackdirs[td%8];}
constexpr int K_VOID=0,K_ROAD=1,K_CROSS=2,K_DEPOT=3,K_BAY=4,K_DRIVE=5,K_BRIDGE=6,K_TUNNEL=7;
struct Tile {
 int kind=0,road_bits=0,tram_bits=0,road_type=-1,tram_type=-1,dir=0,owner=0,
   other=-1,skip=0,disallowed=0,works=0,road_speed=0,tram_speed=0,bridge_speed=0;
};
Tile board[3], empty;
const Tile &Get(TileIndex i){return i>=1 && i<=2 ? board[i] : empty;}
DiagDirection move_direction;
TileIndex TileAddByDiagDir(TileIndex i,DiagDirection d){return i==1 && d==move_direction ? 2 : INVALID_TILE;}
TileIndexDiff TileOffsByDiagDir(DiagDirection d){return 1;}
#define TILE_ADD(tile,diff) ((tile)+(diff))
int GetTileType(TileIndex t){switch(Get(t).kind){
case K_ROAD:case K_CROSS:case K_DEPOT:return MP_ROAD;
case K_BAY:case K_DRIVE:return MP_STATION;
case K_BRIDGE:case K_TUNNEL:return MP_TUNNELBRIDGE;
default:return MP_CLEAR;}}
bool IsTileType(TileIndex t,int type){return GetTileType(t)==type;}
bool IsNormalRoadTile(TileIndex t){return Get(t).kind==K_ROAD;}
bool IsDepotTypeTile(TileIndex t,TransportType type){return type==TRANSPORT_ROAD&&Get(t).kind==K_DEPOT;}
bool IsRoadStopTile(TileIndex t){return Get(t).kind==K_BAY || Get(t).kind==K_DRIVE;}
bool IsRoadStop(TileIndex t){return IsRoadStopTile(t);}
bool IsBayRoadStopTile(TileIndex t){return Get(t).kind==K_BAY;}
bool IsTunnel(TileIndex t){return Get(t).kind==K_TUNNEL;}
bool IsBridgeTile(TileIndex t){return Get(t).kind==K_BRIDGE;}
bool IsLevelCrossing(TileIndex t){return Get(t).kind==K_CROSS;}
bool IsLevelCrossingTile(TileIndex t){return IsLevelCrossing(t);}
bool IsCrossingBarred(TileIndex t){return false;}
bool TrainOnCrossing(TileIndex t){return false;}
TrackBits GetCrossingRailBits(TileIndex t){return TrackBits(0);}
Axis GetCrossingRoadAxis(TileIndex t){return Get(t).dir;}
DiagDirection GetRoadDepotDirection(TileIndex t){return DiagDirection(Get(t).dir);}
DiagDirection GetRoadStopDir(TileIndex t){return DiagDirection(Get(t).dir);}
DiagDirection GetTunnelBridgeDirection(TileIndex t){return DiagDirection(Get(t).dir);}
TileIndex GetOtherTunnelEnd(TileIndex t){return Get(t).other;}
TileIndex GetOtherBridgeEnd(TileIndex t){return Get(t).other;}
uint GetTunnelBridgeLength(TileIndex newer,TileIndex old){return Get(old).skip;}
TransportType GetTunnelBridgeTransportType(TileIndex t){return TRANSPORT_ROAD;}
int GetRoadTileType(TileIndex t){return IsNormalRoadTile(t)?ROAD_TILE_NORMAL:IsLevelCrossing(t)?ROAD_TILE_CROSSING:ROAD_TILE_DEPOT;}
RoadBits GetRoadBits(TileIndex t,RoadTramType type){return RoadBits(type==RTT_ROAD?Get(t).road_bits:Get(t).tram_bits);}
RoadType GetRoadType(TileIndex t,RoadTramType type){return type==RTT_ROAD?Get(t).road_type:Get(t).tram_type;}
bool HasTileRoadType(TileIndex t,RoadTramType type){return GetRoadType(t,type)>=0;}
DisallowedRoadDirections GetDisallowedRoadDirections(TileIndex t){return DisallowedRoadDirections(Get(t).disallowed);}
bool HasRoadWorks(TileIndex t){return Get(t).works;}
Owner GetTileOwner(TileIndex t){return Get(t).owner;}
bool HasStationTileRail(TileIndex t){return false;}
bool HasStationRail(TileIndex t){return false;}
bool IsStationTileBlocked(TileIndex t){return false;}
Track GetRailStationTrack(TileIndex t){return Track(0);}
bool IsBuoy(TileIndex t){return false;}
int TileX(TileIndex t){return 0;}
int TileY(TileIndex t){return 0;}
bool IsPlainRailTile(TileIndex t){return false;}
TrackBits GetTrackBits(TileIndex t){return TrackBits(0);}
bool HasStationReservation(TileIndex t){return false;}
TrackBits GetReservedTrackbits(TileIndex t){return TrackBits(0);}
bool TracksOverlap(TrackBits b){return false;}
struct SetTrackBitIterator {explicit SetTrackBitIterator(TrackBits b){} const Track *begin()const{return nullptr;}const Track *end()const{return nullptr;}};
DiagDirection GetRailDepotDirection(TileIndex t){return DIAGDIR_NE;}
int GetTileRailType(TileIndex t){return 0;}
int GetRailType(TileIndex t){return 0;}
bool Rail90DegTurnDisallowed(RailType a,RailType b,bool c){return false;}
struct BaseStation {static BaseStation *GetByTile(TileIndex t){static BaseStation b;return &b;}int GetPlatformLength(TileIndex,DiagDirection){return 1;}};
bool RoadTypeIsTram(RoadType t){return t>=2;}
RoadTramType GetRoadTramType(RoadType t){return RoadTypeIsTram(t)?RTT_TRAM:RTT_ROAD;}
struct RoadVehicle {Owner owner=1;uint32_t compatible_roadtypes=1;RoadType roadtype=0;int type=1;
 static const RoadVehicle *From(const RoadVehicle *v){return v;}};
struct Train {RailTypes compatible_railtypes=0;static const Train *From(const RoadVehicle *v){static Train t;return &t;}};
int GetBridgeType(TileIndex t){return Get(t).bridge_speed;}
struct Bridge {int speed=0;};
const Bridge *GetBridgeSpec(int spd){static Bridge b;b.speed=spd;return &b;}
struct Speed {uint16_t max_speed=0;};
const Speed *GetRailTypeInfo(int t){static Speed s;return &s;}
const Speed *GetRoadTypeInfo(RoadType t){
 static Speed s;
 s.max_speed=t==Get(1).road_type?Get(1).road_speed:Get(1).tram_speed;
 return &s;
}
"""
for regex,source in (
    (r"^static const TrackBits _road_trackbits",road),
    (r"^static TrackStatus GetTileTrackStatus_Road",road),
    (r"^static TrackStatus GetTileTrackStatus_Station",station),
    (r"^static TrackStatus GetTileTrackStatus_TunnelBridge",bridge),
):
    cpp+=block(source,regex)+(";\n" if regex.startswith("^static const") else "\n")
cpp+=r"""
TrackStatus GetTileTrackStatus(TileIndex t,TransportType tt,int rtt,DiagDirection dir=INVALID_DIAGDIR){
 switch(GetTileType(t)){
 case MP_ROAD:return GetTileTrackStatus_Road(t,tt,rtt,dir);
 case MP_STATION:return GetTileTrackStatus_Station(t,tt,rtt,dir);
 case MP_TUNNELBRIDGE:return GetTileTrackStatus_TunnelBridge(t,tt,rtt,dir);
 default:return 0;}}
"""
cpp+=block(pf,r"^inline TrackdirBits GetTrackdirBitsForRoad")+"\n"
cpp+=block(follow,r"^template <TransportType Ttr_type_") + ";\n"
cpp += r"""
bool read(Tile &t){return bool(std::cin>>t.kind>>t.road_bits>>t.tram_bits>>t.road_type>>t.tram_type>>t.dir
 >>t.owner>>t.other>>t.skip>>t.disallowed>>t.works>>t.road_speed>>t.tram_speed>>t.bridge_speed);}
int main(){
 int tram,vowner,vtypes,move,choice;
 while(std::cin>>tram>>vowner>>vtypes>>move>>choice && read(board[1]) && read(board[2])) {
  move_direction=DiagDirection(move);
  auto rtt=tram?RTT_TRAM:RTT_ROAD;
  for(int tile=1;tile<=2;tile++) {
   for(int d=-1;d<=3;d++) std::cout<<int(TrackStatusToTrackdirBits(GetTileTrackStatus(tile,TRANSPORT_ROAD,rtt,d<0?INVALID_DIAGDIR:DiagDirection(d))))<<" ";
   std::cout<<int(GetTrackdirBitsForRoad(tile,rtt))<<" ";
  }
  TrackdirBits oldbits=GetTrackdirBitsForRoad(1,rtt);
  std::vector<int> dirs;
  for(int d=0;d<14;d++) if(HasBit(oldbits,d))dirs.push_back(d);
  if(dirs.empty()){std::cout<<"x\n";continue;}
  RoadVehicle v;v.owner=vowner;v.roadtype=tram?2:0;v.compatible_roadtypes=vtypes;
  CFollowTrackT<TRANSPORT_ROAD,RoadVehicle,true> f(&v);
  auto td=Trackdir(dirs[choice%dirs.size()]);
  bool works=f.Follow(1,td);
  int min_speed=-1;
  int max_speed=f.GetSpeedLimit(&min_speed);
  std::cout<<int(td)<<" "<<int(works)<<" "<<int(f.m_err)<<" "<<f.m_new_tile<<" "<<int(f.m_new_td_bits)<<" "<<int(f.m_exitdir)
    <<" "<<int(f.m_is_station)<<" "<<int(f.m_is_bridge)<<" "<<int(f.m_is_tunnel)<<" "<<f.m_tiles_skipped<<" "
    <<max_speed<<" "<<min_speed<<"\n";
 }
}
"""

lua=r"""
local R=dofile('mods/bayline/openttd/yapf_road_follow.lua')
local kinds={[0]='void','road','crossing','depot','bay_stop','drive_stop','bridge','tunnel'}
local function bool(b) return b and 1 or 0 end
for line in io.lines() do
  local n={}
  for a in line:gmatch('-?%d+') do n[#n+1]=tonumber(a) end
  local function tile(i)
    local function nullable(x) if x>=0 then return x end end
    return {kind=kinds[n[i]],road_bits=n[i+1],tram_bits=n[i+2],roadtype=nullable(n[i+3]),tramtype=nullable(n[i+4]),
      dir=n[i+5],axis=n[i+5],owner=n[i+6],other=nullable(n[i+7]),skip=n[i+8],disallowed=n[i+9],roadworks=n[i+10]==1,
      road_speed=n[i+11],tram_speed=n[i+12],bridge_speed=n[i+13]}
  end
  local tiles={tile(6),tile(20)}
  local tram=n[1]==1
  local v={owner=n[2],tram=tram,compatible={}}
  for i=0,3 do if math.floor(n[3]/2^i)%2==1 then v.compatible[i]=true end end
  local board={
    tile=function(id) return tiles[id] end,
    adjacent=function(i,dir) if i==1 and dir==n[4] then return 2 end end,
  }
  local out={}
  for i=1,2 do
    for d=-1,3 do out[#out+1]=R.status(tiles[i],tram,d>=0 and d or nil) end
    out[#out+1]=R.tile_trackdirs(tiles[i],tram)
  end
  local dirs=R.trackdirs(R.tile_trackdirs(tiles[1],tram))
  if #dirs==0 then out[#out+1]='x'
  else
    local td=dirs[(n[5]%#dirs)+1]
    local f=R.follow(board,v,1,td)
    local speed,min=R.speed_limit(tiles[1],tram)
    for _,k in ipairs({td,bool(f.ok),f.error,f.tile or -1,f.trackdirs,f.exit,bool(f.station),
                    bool(f.bridge),bool(f.tunnel),f.skip,speed,min}) do out[#out+1]=k end
  end
  print(table.concat(out,' '))
end
"""

rng = random.Random(14132)
def tile(k):
    dirs = rng.randrange(2 if k==2 else 4)
    return [k,rng.randrange(16),rng.randrange(16),rng.choice([-1,0,1]),rng.choice([-1,2,3]),dirs,rng.randrange(2),
            2,rng.randrange(9),rng.randrange(4),rng.randrange(10)==0,rng.randrange(80),rng.randrange(80),rng.randrange(100)]

samples = []
for _ in range(34000):
    first,second=tile(rng.choice([1,1,1,2,3,4,5,6,7])),tile(rng.randrange(8))
    values=[rng.randrange(2),rng.randrange(2),rng.randrange(16),rng.randrange(4),rng.randrange(100),*first,*second]
    # Define speed limits from the actually present types in the C++ mock.
    if first[3]<0: first[11]=0
    if first[4]<0: first[12]=0
    # Preserve true opposite tunnel/bridge ramp while traversing an actual pair.
    if first[0] in [6,7]:
        second[0]=first[0];second[5]=(first[5]+2)%4
    values[5:]=first+second
    samples.append(" ".join(str(int(n)) for n in values))

data=("\n".join(samples)+"\n").encode()
with tempfile.TemporaryDirectory() as temp:
    t=Path(temp)
    (t/"reference.cpp").write_text(cpp)
    (t/"compare.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",str(t/"reference.cpp"),"-o",str(t/"reference")],check=True)
    ref=subprocess.run([str(t/"reference")],input=data,capture_output=True,check=True).stdout.decode().splitlines()
    got=subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(t/"compare.lua")],input=data,
                        capture_output=True,check=True,cwd=root).stdout.decode().splitlines()
    assert len(ref)==len(got)==len(samples)
    for i,(a,b) in enumerate(zip(ref,got)):
        assert a==b, (samples[i],a,b)
    transitions = sum(not case.endswith(" x") for case in ref)
    print(f"PASS: {len(samples)} road track-status cases; {transitions} CFollowTrackRoad transitions vs pinned OpenTTD 14.1")
