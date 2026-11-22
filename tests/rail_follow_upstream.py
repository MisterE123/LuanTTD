"""Run unchanged OpenTTD 14.1 CFollowTrackT against the Lua rail follower.

python tests/rail_follow_upstream.py SOURCE_TREE [lua5.1]
The compiled shim supplies map records; it is not a stock game playtest.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, block, declarations, src

LUA = r"""
local T=dofile("mods/bayline/openttd/rail_track.lua")
local F=dofile("mods/bayline/openttd/rail_follow.lua")(T)
local kinds={[0]="void","rail","signals","crossing","depot","station","waypoint","bridge","tunnel"}
local function yn(b) return b and 1 or 0 end
for line in io.lines() do
  local n={}
  for a in line:gmatch("-?%d+") do n[#n+1]=tonumber(a) end
  local types={}
  for i=0,3 do
    local start=5+i*3
    local type_={allow_90=T.has(n[start],4),disallow_90=T.has(n[start],5),
      max_speed=n[start+1],compatible={}}
    for t=0,3 do type_.compatible[t]=T.has(n[start+2],t) end
    types[i]=type_
  end
  local tiles={}
  for i=0,4 do
    local start=17+i*11
    tiles[5+i]={kind=kinds[n[start]],trackbits=n[start+1],dir=n[start+2],axis=n[start+2]%2,
      owner=n[start+3],railtype=n[start+4],station=n[start+5],blocked=n[start+6]==1,
      reserved=n[start+7]==1,reserved_bits=n[start+8],bridge_speed=n[start+9],other=9,skip=n[start+10]}
  end
  local old=n[4]
  local status=T.status(tiles[5])
  while old>0 do
    if T.has(status,old%16) then break end
    old=old-1
  end
  if not T.has(status,old%16) then
    for td=1,13 do if T.has(status,td) then old=td;break end end
  end
  if not T.has(status,old%16) then print("empty")
  else
    local move=T.exit_side(old%16)
    local train={owner=n[1],compatible={}}
    for i=0,3 do train.compatible[i]=T.has(n[2],i) end
    local board={tile=function(i) return tiles[i] end,railtype=function(i) return types[i] end,
      adjacent=function(i,d) return i+(d==move and 1 or -1) end}
    local f=F.follow(board,train,5,old%16,{forbid_90=n[3]==1})
    local g=F.mask_reserved(board,f)
    local max,min=F.speed_limit(board,board.tile(5))
    local out={yn(f.ok),f.error,f.tile or -1,f.trackdirs,f.exit,yn(f.station),yn(f.bridge),yn(f.tunnel),f.skip,
      yn(g.ok),g.error,g.trackdirs,max,min}
    print(table.concat(out," "))
  end
end
"""


def cpp(source):
    track, direction, roadtypes = (src(source,p) for p in
        ("track_type.h","direction_type.h","road_type.h"))
    r = r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
using byte=unsigned char;
using uint=unsigned;
using uint16=uint16_t;
using TrackStatus=uint32_t;
using TileIndex=int;
using TileIndexDiff=int;
using Tile=int;
using Owner=int;
using RailType=int;
using RailTypes=uint64_t;
using RoadType=int;
using Axis=int;
enum RoadTramType {RTT_ROAD, RTT_TRAM};
enum TransportType {TRANSPORT_RAIL,TRANSPORT_ROAD,TRANSPORT_WATER};
enum {AXIS_X,AXIS_Y};
enum {MP_CLEAR,MP_RAILWAY,MP_ROAD,MP_STATION,MP_TUNNELBRIDGE};
enum {RAIL_TILE_NORMAL,RAIL_TILE_SIGNALS,RAIL_TILE_DEPOT};
enum {ROAD_TILE_NORMAL,ROAD_TILE_CROSSING,ROAD_TILE_DEPOT};
enum {VEH_TRAIN};
constexpr int INVALID_TILE=-1, INVALID_OWNER=-1, INVALID_RAILTYPE=255;
constexpr RailTypes INVALID_RAILTYPES=UINT64_MAX;
#define debug_inline inline
#define TILE_ADD(tile,diff) ((tile)+(diff))
#define NOT_REACHED() std::abort()
"""
    r += declarations(direction,[r"enum DiagDirection\s*:"])
    r += declarations(track,[r"enum Track\s*:",r"enum TrackBits",r"enum Trackdir\s*:",r"enum TrackdirBits"])
    r += declarations(roadtypes,[r"enum RoadBits",r"enum DisallowedRoadDirections"])
    r += r"""
#define BITOPS(T) \
 T operator|(T a,T b) {return T(int(a)|int(b));} \
 T operator&(T a,T b) {return T(int(a)&int(b));} \
 T operator~(T a) {return T(~int(a));} \
 T& operator|=(T &a,T b) {return a=a|b;} \
 T& operator&=(T &a,T b) {return a=a&b;}
BITOPS(RoadBits)
BITOPS(TrackBits)
BITOPS(TrackdirBits)
template<class T> bool HasBit(uint64_t b,T t){return t>=0 && t<64 && (b&(1ULL<<t));}
constexpr TrackBits KillFirstBit(TrackBits b){return TrackBits(b & (b-1));}
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
Axis GetCrossingRoadAxis(TileIndex){return AXIS_X;}
DiagDirection AxisToDiagDir(Axis a){return DiagDirection(a==AXIS_X ? DIAGDIR_SW : DIAGDIR_SE);}
TrackStatus CombineTrackStatus(TrackdirBits bits,TrackdirBits red){return TrackStatus(bits)|(TrackStatus(red)<<16);}
"""
    r += declarations(src(source,"rail.cpp"), [r"extern const .* "+name for name in (
        "_trackdir_to_exitdir","_track_crosses_trackdirs","_exitdir_reaches_trackdirs","_signal_on_track")])
    r += block(src(source,"track_func.h"),r"^inline bool TracksOverlap")
    r += r"""
DiagDirection TrackdirToExitdir(Trackdir td){return _trackdir_to_exitdir[td];}
TrackdirBits DiagdirReachesTrackdirs(DiagDirection d){return _exitdir_reaches_trackdirs[d];}
TrackdirBits TrackdirCrossesTrackdirs(Trackdir td){return _track_crosses_trackdirs[td%8];}
struct SetTrackBitIterator {
 std::vector<Track> tracks;
 explicit SetTrackBitIterator(TrackBits bits){for(int t=0;t<6;t++)if(HasBit(bits,t))tracks.emplace_back(Track(t));}
 auto begin()const{return tracks.begin();}auto end()const{return tracks.end();}
};
constexpr int K_VOID=0,K_RAIL=1,K_SIGNAL=2,K_CROSS=3,K_DEPOT=4,K_STATION=5,K_WAYPOINT=6,K_BRIDGE=7,K_TUNNEL=8;
struct TileRecord {
 int kind=0,bits=0,dir=0,owner=0,railtype=0,station=0,blocked=0,reserved=0,reserved_bits=0,
   bridge_speed=0,skip=0;
};
TileRecord board[11], empty;
const TileRecord &Get(TileIndex id){return id>=5 && id<=9 ? board[id] : empty;}
DiagDirection move_direction;
TileIndexDiff TileOffsByDiagDir(DiagDirection d){return d==move_direction?1:-1;}
TileIndex TileAddByDiagDir(TileIndex id,DiagDirection d){return id+TileOffsByDiagDir(d);}
int GetTileType(TileIndex id){
 switch(Get(id).kind) {
 case K_RAIL: case K_SIGNAL: case K_DEPOT: return MP_RAILWAY;
 case K_CROSS: return MP_ROAD;
 case K_STATION: case K_WAYPOINT: return MP_STATION;
 case K_BRIDGE: case K_TUNNEL: return MP_TUNNELBRIDGE;
 default:return MP_CLEAR;}}
bool IsTileType(TileIndex id,int k){return GetTileType(id)==k;}
bool IsPlainRail(TileIndex id){return Get(id).kind==K_RAIL||Get(id).kind==K_SIGNAL;}
bool IsPlainRailTile(TileIndex id){return IsPlainRail(id);}
bool IsRailStationTile(TileIndex id){return Get(id).kind==K_STATION;}
bool IsDepotTypeTile(TileIndex id,TransportType t){return t==TRANSPORT_RAIL&&Get(id).kind==K_DEPOT;}
bool IsStationTileBlocked(TileIndex id){return Get(id).blocked!=0;}
bool HasStationRail(TileIndex id){return Get(id).kind==K_STATION || Get(id).kind==K_WAYPOINT;}
bool HasStationTileRail(TileIndex id){return HasStationRail(id);}
Track GetRailStationTrack(TileIndex id){return Track(Get(id).dir%2);}
Axis GetRailStationAxis(TileIndex id){return Get(id).dir%2;}
int GetStationIndex(TileIndex id){return Get(id).station;}
bool IsTunnel(TileIndex id){return Get(id).kind==K_TUNNEL;}
bool IsBridgeTile(TileIndex id){return Get(id).kind==K_BRIDGE;}
bool IsLevelCrossing(TileIndex id){return Get(id).kind==K_CROSS;}
bool IsLevelCrossingTile(TileIndex id){return IsLevelCrossing(id);}
bool IsCrossingBarred(TileIndex){return false;}
bool TrainOnCrossing(TileIndex){return false;}
TrackBits GetCrossingRailBits(TileIndex id){return AxisToTrackBits(Get(id).dir%2);}
DiagDirection GetTunnelBridgeDirection(TileIndex id){return DiagDirection(Get(id).dir);}
TileIndex GetOtherTunnelEnd(TileIndex){return 9;}
TileIndex GetOtherBridgeEnd(TileIndex){return 9;}
uint GetTunnelBridgeLength(TileIndex,TileIndex old){return Get(old).skip;}
TransportType GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_RAIL;}
Owner GetTileOwner(TileIndex id){return Get(id).owner;}
TrackBits GetTrackBits(TileIndex id){return TrackBits(Get(id).bits);}
bool HasStationReservation(TileIndex id){return Get(id).reserved!=0;}
TrackBits GetReservedTrackbits(TileIndex id){
 return TrackBits(Get(id).reserved_bits|(HasStationRail(id)&&HasStationReservation(id)?1<<(Get(id).dir%2):0));
}
DiagDirection GetRailDepotDirection(TileIndex id){return DiagDirection(Get(id).dir);}
RailType GetTileRailType(TileIndex id){return Get(id).railtype;}
RailType GetRailType(TileIndex id){return Get(id).railtype;}
int GetBridgeType(TileIndex id){return Get(id).bridge_speed;}
struct BridgeSpec {int speed=0;};
const BridgeSpec *GetBridgeSpec(int spd){static BridgeSpec info;info.speed=spd;return &info;}
struct RailTypeInfo {uint flags=0;uint16_t max_speed=0;RailTypes compatible_railtypes=0;};
RailTypeInfo types[4];
const RailTypeInfo *GetRailTypeInfo(int typ){return &types[typ];}
constexpr int RTF_ALLOW_90DEG=4,RTF_DISALLOW_90DEG=5;
struct {struct {bool forbid_90_deg;} pf;} _settings_game;

bool IsNormalRoadTile(TileIndex){return false;}
bool IsRoadStopTile(TileIndex){return false;}
bool IsRoadStop(TileIndex){return false;}
bool IsBayRoadStopTile(TileIndex){return false;}
bool HasTileRoadType(TileIndex,RoadTramType){return false;}
bool IsBuoy(TileIndex){return false;}
bool HasRoadWorks(TileIndex){return false;}
int TileX(TileIndex){return 0;}
int TileY(TileIndex){return 0;}
int GetRoadTileType(TileIndex){return -1;}
RoadBits GetRoadBits(TileIndex,RoadTramType){return ROAD_NONE;}
RoadType GetRoadType(TileIndex,RoadTramType){return 0;}
DiagDirection GetRoadDepotDirection(TileIndex){return DIAGDIR_NE;}
DiagDirection GetRoadStopDir(TileIndex){return DIAGDIR_NE;}
DisallowedRoadDirections GetDisallowedRoadDirections(TileIndex){return DRD_NONE;}
struct RoadVehicle {RoadType roadtype=0;RailTypes compatible_roadtypes=0;
 template<class V> static const RoadVehicle *From(const V*){static RoadVehicle v;return &v;}};
RoadTramType GetRoadTramType(RoadType){return RTT_ROAD;}
bool RoadTypeIsTram(RoadType){return false;}
const RailTypeInfo *GetRoadTypeInfo(RoadType){return &types[0];}
using Slope=int;
constexpr Slope SLOPE_FLAT=0;
constexpr int RAIL_GROUND_WATER=0;
int GetRailGroundType(TileIndex){return -1;}
Slope GetTileSlope(TileIndex){return SLOPE_FLAT;}
bool IsSlopeWithOneCornerRaised(Slope){return false;}
int GetRailTileType(TileIndex id){return Get(id).kind==K_DEPOT ? RAIL_TILE_DEPOT :
  Get(id).kind==K_SIGNAL ? RAIL_TILE_SIGNALS : RAIL_TILE_NORMAL;}
int GetPresentSignals(TileIndex){return 0;}
int GetSignalStates(TileIndex){return 0;}
bool IsOnewaySignal(TileIndex,Track){return true;}
byte SignalOnTrack(Track tr){return _signal_on_track[tr];}
"""
    rail_h=src(source,"rail.h")
    for name in ("IsCompatibleRail","Rail90DegTurnDisallowed"):
        r+=block(rail_h,rf"^inline bool {name}\(")
    r+=block(src(source,"station_map.h"),r"^inline bool IsCompatibleTrainStationTile\(")
    r+=r"""
struct Station {
 uint GetPlatformLength(TileIndex tile, DiagDirection dir) const;
};
struct BaseStation {
 static BaseStation *GetByTile(TileIndex id){static BaseStation b;b.is_waypoint=Get(id).kind==K_WAYPOINT;return &b;}
 uint GetPlatformLength(TileIndex id,DiagDirection dir) const{return is_waypoint?1:Station{}.GetPlatformLength(id,dir);}
 bool is_waypoint=false;
};
struct Train {
 Owner owner=1;
 RailTypes compatible_railtypes=0;
 int type=VEH_TRAIN;
 static const Train *From(const Train *p){return p;}
};
"""
    r+=block(src(source,"station.cpp"),r"^/\* virtual \*/ uint Station::GetPlatformLength\(TileIndex tile, DiagDirection dir\)")
    road=src(source,"road_cmd.cpp")
    r+=declarations(road,[r"static const TrackBits _road_trackbits"])
    for name,file in (("Road","road_cmd.cpp"),("Track","rail_cmd.cpp"),("Station","station_cmd.cpp"),
                      ("TunnelBridge","tunnelbridge_cmd.cpp")):
        r+=block(src(source,file),rf"^static TrackStatus GetTileTrackStatus_{name}\(")
    r+=r"""
TrackStatus GetTileTrackStatus(TileIndex id,TransportType t,int rt,DiagDirection d=INVALID_DIAGDIR){
 switch(GetTileType(id)) {
 case MP_RAILWAY:return GetTileTrackStatus_Track(id,t,rt,d);
 case MP_ROAD:return GetTileTrackStatus_Road(id,t,rt,d);
 case MP_STATION:return GetTileTrackStatus_Station(id,t,rt,d);
 case MP_TUNNELBRIDGE:return GetTileTrackStatus_TunnelBridge(id,t,rt,d);
 default:return 0;
 }}
"""
    r+=block(src(source,"pathfinder/pathfinder_func.h"),r"^inline TrackdirBits GetTrackdirBitsForRoad")
    r+=block(src(source,"pathfinder/follow_track.hpp"),r"^template <TransportType Ttr_type_")+";\n"
    r+=r"""
bool Read(TileRecord &r) {
 return bool(std::cin>>r.kind>>r.bits>>r.dir>>r.owner>>r.railtype>>r.station>>r.blocked
    >>r.reserved>>r.reserved_bits>>r.bridge_speed>>r.skip);
}
template<bool allow90> void run(Train &v,Trackdir td) {
 CFollowTrackT<TRANSPORT_RAIL,Train,allow90,true> f(&v);
 bool ok=f.Follow(5,td);
 std::cout<<ok<<" "<<int(f.m_err)<<" "<<f.m_new_tile<<" "<<int(f.m_new_td_bits)<<" "<<int(f.m_exitdir)
  <<" "<<f.m_is_station<<" "<<f.m_is_bridge<<" "<<f.m_is_tunnel<<" "<<f.m_tiles_skipped;
 bool mask=ok&&f.MaskReservedTracks();
 int min=-1;
 int max=f.GetSpeedLimit(&min);
 std::cout<<" "<<mask<<" "<<int(f.m_err)<<" "<<int(f.m_new_td_bits)<<" "<<max<<" "<<min<<"\n";
}
int main(){
 int owner=1,types=1,forbid=0,choice=0;
 while(std::cin>>owner>>types>>forbid>>choice){
  for(auto &typ : ::types) if(!(std::cin>>typ.flags>>typ.max_speed>>typ.compatible_railtypes))return 1;
  for(int i=5;i<=9;++i)if(!Read(board[i]))return 2;
  auto bits=TrackStatusToTrackdirBits(GetTileTrackStatus(5,TRANSPORT_RAIL,0));
  if(!bits){std::cout<<"empty\n";continue;}
  int td=choice;
  while(td>0&&!HasBit(bits,td%16)) --td;
  if(!HasBit(bits,td%16)) {
   for(int i=1;i<14;i++)if(HasBit(bits,i)){td=i;break;}
  }
  move_direction=TrackdirToExitdir(Trackdir(td%16));
  Train v;v.owner=owner;v.compatible_railtypes=types;
  if (forbid) run<false>(v,Trackdir(td%16)); else run<true>(v,Trackdir(td%16));
 }
}
"""
    return r


def corpus():
    rng=random.Random(14_01)
    def tile(kind=None):
        kind=rng.randrange(9) if kind is None else kind
        return [
            kind,rng.randrange(64),rng.randrange(4),rng.choices([1,2],[8,2])[0],
            rng.randrange(4),rng.randrange(5),int(rng.random()<0.1),
            int(rng.random()<0.35),rng.choice([0,0,0,0,1,2,4,8,16,32,12,48]),
            rng.choice([45,65,100,120,150]),3,
        ]
    for case in range(24000):
        seed=[1,rng.choices([15,1,10,5],[6,1,1,1])[0],rng.randrange(2),rng.randrange(14)]
        for i in range(4):
            seed += [rng.choice([0,0,16,32,48]),rng.choice([0,55,65,100]),rng.randrange(16)|(1<<i)]
        old=tile(rng.choice([1,1,1,1,2,3,4,5,6,7,8]))
        dest=tile()
        p2,p3,end=tile(),tile(),tile()
        if case%9==0:
            # Connected, exact same-type platform followed by a fourth tile.
            # Randomized flags can reserve early, late, or on the far end.
            parity=rng.randrange(2)
            old=[1,1<<parity,0,1,0,0,0,0,0,0,3]
            dest=[5,0,parity,1,0,3,0,int(case%18==0),0,0,3]
            p2=dest[:];p2[7]=int(case%27==0)
            p3=dest[:];p3[7]=int(case%45==0)
        if case%17==1:
            # Upper eastbound enters the next tile toward NE. A left
            # northbound piece reaches that entry but is a 90° turn.
            seed=[1,15,1,2]+[0,0,15]*4
            old=[1,4,0,1,0,0,0,0,0,0,3]
            dest=[1,16,0,1,0,0,0,0,0,0,3]
            if case%34==1:
                # Rail type explicitly permits 90° over the setting.
                seed[4]=16
        if case%19==4:
            # The directional platform check is dictated by the later
            # tile railtype's compatibility, not the arrival vehicle.
            seed=[1,15,0,0]+[0,0,1,0,0,3,0,0,4,0,0,8]
            old=[1,1,0,1,0,0,0,0,0,0,3]
            dest=[5,0,0,1,0,3,0,0,0,0,3]
            p2=dest[:];p2[4]=1
            p3=dest[:];p3[4]=2
        if case%21==5:
            seed=[1,15,0,0]+[0,0,15]*4
            old=[1,1,0,1,0,0,0,0,0,0,3]
            dest=[6,0,0,1,0,3,0,0,0,0,3]
            p2=dest[:];p2[7]=1  # Waypoints don't skip another waypoint.
        if old[0] in (7,8):
            end[0]=old[0];end[2]=(old[2]+2)%4
        yield " ".join(map(str,seed+old+dest+p2+p3+end))


def main():
    samples=list(corpus())
    data=("\n".join(samples)+"\n").encode()
    with tempfile.TemporaryDirectory() as directory:
        t = Path(directory)
        (t/"reference.cpp").write_text(cpp(Path(sys.argv[1])))
        (t/"compare.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",t/"reference.cpp","-o",t/"reference"],check=True)
        ref=subprocess.run([t/"reference"],input=data,capture_output=True,check=True).stdout.splitlines()
        got=subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",t/"compare.lua"],
                           cwd=ROOT,input=data,capture_output=True,check=True).stdout.splitlines()
    assert len(ref)==len(got)==len(samples)
    for i,(want,actual) in enumerate(zip(ref,got)):
        assert want==actual,(i,samples[i],want,actual)
    passed=[tuple(map(int,a.split())) for a in ref if a != b"empty"]
    skipped=sum(x[5] and x[8]>0 for x in passed)
    bridges=sum(x[6] for x in passed)
    tunnels=sum(x[7] for x in passed)
    reserved=sum(x[10]==5 for x in passed)
    no90=sum(x[1]==3 for x in passed)
    reversals=sum(x[0] and x[2]==5 for x in passed)
    assert skipped>500 and bridges>100 and tunnels>100 and reserved>500 and no90>100 and reversals>100,(skipped,bridges,tunnels,reserved,no90,reversals)
    print(f"PASS: {len(passed)} compiled stock rail transitions of {len(samples)} maps;"
          f" {skipped} platform skips, {bridges} bridge/{tunnels} tunnel steps,"
          f" {reserved} reservation and {no90} 90° refusals, {reversals} depot reversals")


if __name__=="__main__":
    main()
