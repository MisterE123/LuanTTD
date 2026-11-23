"""Compare unchanged conventional-only block propagation with pinned 14.1.

RC1 changed how PBS heads participate in blocks, so mixed/PBS fixtures
are no longer compared to the 14.1 reference. See rail_block_signals.lua
for RC1 signals and rail_owned_multi_native.lua for native mixed service.

python tests/rail_block_signals_upstream.py SOURCE_TREE [lua5.1]
Only the map and vehicle enumeration are synthetic. The reference compiles
the original SmallSet, exploration, buffered update, and signal aspect code.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "signal.cpp": "94f4a4cf598dbbd69792b3468d65e482d5bcb261a1a5ef9a28628d5b42c8a5fb",
    "rail_map.h": "13855adaa34c4184bc32bf8f74f0e3610ffc1da3081636de27a0d628a5911b6b",
    "signal_func.h": "1a63ecc1a2c2796e95482bace40fb89729c78d093163764fe61cdd0f0ce26127",
    "signal_type.h": "c2eceb70a17d3bb0c4ae679394e07e75f6c9ad709e45ca03e2fc32459f895a29",
    "train_cmd.cpp": "206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "vehicle.cpp": "1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
})

CPP = r"""
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <vector>
using uint=unsigned;
using byte=uint8_t;
using Owner=int;
using TileIndex=int;
constexpr Owner INVALID_OWNER=-1;
constexpr TileIndex INVALID_TILE=-1;
"""
MAP_CPP = r"""
#define DECLARE_ENUM_AS_BIT_SET(T) \
 constexpr T operator|(T a,T b){return T(int(a)|int(b));} \
 constexpr T operator&(T a,T b){return T(int(a)&int(b));} \
 inline T& operator|=(T &a,T b){return a=a|b;}
DECLARE_ENUM_AS_BIT_SET(TrackBits)
DECLARE_ENUM_AS_BIT_SET(TrackdirBits)
#define lengthof(x) (sizeof(x)/sizeof(*(x)))
DiagDirection operator++(DiagDirection& d,int){auto o=d; d=DiagDirection(d+1); return o;}
DiagDirection ReverseDiagDir(DiagDirection d){assert(d<4);return DiagDirection(d^2);}
bool IsValidDiagDirection(DiagDirection d){return d<4;}
Trackdir ReverseTrackdir(Trackdir td){return Trackdir(td^8);}
Track TrackdirToTrack(Trackdir td){return Track(td&7);}
DiagDirection TrackdirToExitdir(Trackdir td){return _trackdir_to_exitdir[td];}
TrackBits KillFirstBit(TrackBits bits){return TrackBits(bits&(bits-1));}
int FindFirstBit(unsigned bits){assert(bits);return __builtin_ctz(bits);}
Track TrackBitsToTrack(TrackBits bits){return Track(FindFirstBit(bits));}
enum {MP_CLEAR,MP_RAILWAY,MP_STATION,MP_ROAD,MP_TUNNELBRIDGE};
enum {K_CLEAR,K_RAIL,K_SIGNAL,K_DEPOT,K_STATION,K_CROSSING,K_BRIDGE,K_TUNNEL,K_WAYPOINT};
enum {TRANSPORT_RAIL};
constexpr int RAIL_TILE_SIGNALS=K_SIGNAL;
constexpr int VEH_TRAIN=0;
struct Vehicle {int type; TrackBits track;};
struct Train: Vehicle {static Train *From(Vehicle *v){return static_cast<Train *>(v);}};
struct MapRecord {
  int kind=0,owner=0,track=0,dir=0,axis=0,other=0,blocked=0,present=0,green=0,high=0,low=0;
  std::vector<Train> vehicles;
};
using Tile=TileIndex;
std::map<int,MapRecord> tiles;
MapRecord& Get(TileIndex t){return tiles[t];}
int GetTileType(TileIndex tile){
  constexpr int kinds[]={MP_CLEAR,MP_RAILWAY,MP_RAILWAY,MP_RAILWAY,MP_STATION,MP_ROAD,
    MP_TUNNELBRIDGE,MP_TUNNELBRIDGE,MP_STATION};
  return kinds[Get(tile).kind];
}
bool IsTileType(TileIndex t,int type){return GetTileType(t)==type;}
int GetRailTileType(TileIndex t){return Get(t).kind;}
TrackdirBits TrackBitsToTrackdirBits(TrackBits bits){return TrackdirBits(bits*0x101);}
TrackdirBits DiagdirReachesTrackdirs(DiagDirection d){return _exitdir_reaches_trackdirs[d];}
Trackdir FindFirstTrackdir(TrackdirBits bits){return Trackdir(FindFirstBit(bits));}
Owner GetTileOwner(TileIndex tile){return Get(tile).owner;}
int TileOffsByDiagDir(DiagDirection dir){constexpr int delta[]={-1,64,1,-64}; return delta[dir];}
bool IsRailDepot(TileIndex t){return Get(t).kind==K_DEPOT;}
DiagDirection GetRailDepotDirection(TileIndex t){return DiagDirection(Get(t).dir);}
TrackBits GetTrackBits(TileIndex t){return TrackBits(Get(t).track);}
bool HasSignals(TileIndex t){return Get(t).kind==K_SIGNAL;}
bool HasSignalOnTrack(TileIndex t,Track tr){return Get(t).present & _signal_on_track[tr];}
bool HasSignalOnTrackdir(TileIndex t,Trackdir td){return Get(t).present & _signal_along_trackdir[td];}
SignalType GetSignalType(TileIndex t,Track tr)
  {return SignalType(tr==TRACK_LOWER||tr==TRACK_RIGHT?Get(t).low:Get(t).high);}
SignalState GetSignalStateByTrackdir(TileIndex t,Trackdir td)
  {return SignalState((Get(t).green & _signal_along_trackdir[td])!=0);}
void SetSignalStateByTrackdir(TileIndex t,Trackdir td,SignalState s)
  {if(s) Get(t).green|=_signal_along_trackdir[td]; else Get(t).green&=~_signal_along_trackdir[td];}
int DiagDirToAxis(DiagDirection d){return d&1;}
bool HasStationRail(TileIndex t){return Get(t).kind==K_STATION||Get(t).kind==K_WAYPOINT;}
int GetRailStationAxis(TileIndex t){return Get(t).axis;}
bool IsStationTileBlocked(TileIndex t){return Get(t).blocked;}
bool IsLevelCrossing(TileIndex t){return Get(t).kind==K_CROSSING;}
int GetCrossingRoadAxis(TileIndex t){return Get(t).axis^1;}
int GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_RAIL;}
DiagDirection GetTunnelBridgeDirection(TileIndex t){return DiagDirection(Get(t).dir);}
TileIndex GetOtherTunnelBridgeEnd(TileIndex t){return Get(t).other;}
uint GetTileTrackStatus(TileIndex t,int,int){
  const auto& a=Get(t); int bits=0;
  switch(a.kind){
    case K_RAIL: case K_SIGNAL: bits=a.track; break;
    case K_STATION: case K_WAYPOINT: if(!a.blocked)bits=1<<a.axis; break;
    case K_CROSSING: bits=1<<a.axis; break;
    case K_DEPOT: case K_BRIDGE: case K_TUNNEL: bits=1<<(a.dir&1); break;
  }
  return bits*0x101;
}
TrackBits TrackStatusToTrackBits(uint bits){return TrackBits((bits|(bits>>8))&63);}
namespace Company { bool IsValidID(Owner o){return o>0;} }
#define Debug(...) ((void)0)
using VehicleQuery=Vehicle*(*)(Vehicle*,void*);
Vehicle *VehicleFromPos(TileIndex tile,void *data,VehicleQuery f,bool){
  for(auto& v:Get(tile).vehicles) if(auto result=f(&v,data)) return result;
  return nullptr;
}
bool HasVehicleOnPos(TileIndex tile,void *data,VehicleQuery f)
  {return VehicleFromPos(tile,data,f,true)!=nullptr;}
struct CommandCost {int err=0; bool Failed()const{return err!=0;}};
constexpr int STR_ERROR_TRAIN_IN_THE_WAY=1;
#define return_cmd_error(e) return CommandCost{e}
std::vector<TileIndex> change;
void MarkTileDirtyByTile(TileIndex tile){change.push_back(tile);}
"""
RUN_CPP = r"""
int main(){
  int nt,ne,mode,owner;
  while(std::cin>>nt>>ne>>mode>>owner){
    change.clear(); tiles.clear(); ResetSets(); _last_owner=INVALID_OWNER;
    std::vector<int> rails;
    for(int i=0;i<nt;i++){
      int id,n; std::cin>>id;
      auto& t=Get(id);
      std::cin>>t.kind>>t.owner>>t.track>>t.dir>>t.axis>>t.other>>t.blocked>>t.present>>t.green>>t.high>>t.low>>n;
      for(int j=0;j<n;j++){int bits;std::cin>>bits;t.vehicles.push_back(Train{{bits==512?1:VEH_TRAIN,TrackBits(bits)}});}
      if(t.kind==K_SIGNAL)rails.push_back(id);
    }
    int result=-1;
    for(int i=0;i<ne;i++){
      int id,side,track;std::cin>>id>>side>>track;
      if(mode==0)result=UpdateSignalsOnSegment(id,DiagDirection(side),owner);
      else if(mode==1)SetSignalsOnBothDir(id,Track(track),owner);
      else if(mode==3)result=TrainMovedChangeSignals(id,DiagDirection(side))?1:0;
      else if(track>=0)AddTrackToSignalBuffer(id,Track(track),owner);
      else AddSideToSignalBuffer(id,DiagDirection(side),owner);
    }
    if(mode==2)UpdateSignalsInBuffer();
    std::cout<<result<<" "<<change.size();
    for(int id:change)std::cout<<" "<<id;
    for(int id:rails)std::cout<<" "<<Get(id).green;
    std::cout<<"\n";
  }
}
"""

LUA = r"""
local dir="mods/luanttd_core/openttd/"
local T=dofile(dir.."rail_track.lua")
local R=dofile(dir.."rail_signals.lua")(T)
local B=dofile(dir.."rail_block_signals.lua")(T,R)
local kinds={[0]="void","rail","signals","depot","station","crossing","bridge","tunnel","waypoint"}
local status={free=0,full=1,pbs=2}
local delta={[0]=-1,64,1,-64}
local function num() return assert(io.read("*n")) end
while true do
  local nt=io.read("*n"); if nt==nil then break end
  local ne,mode,owner=num(),num(),num()
  local tiles,rails,stock={},{},{}
  for i=1,nt do
    local id,kind=num(),kinds[num()]
    tiles[id]={kind=kind,owner=num(),trackbits=num(),dir=num(),axis=num(),other=num(),
      blocked=num()==1,present_signals=num(),green_signals=num(),upper_signal_type=num(),lower_signal_type=num()}
    local n=num(); stock[id]={}
    for _=1,n do local bits=num(); if bits~=512 then stock[id][#stock[id]+1]=bits end end
    if kind=="signals" then rails[#rails+1]=id end
  end
  local board={tile=function(id) return tiles[id] end,adjacent=function(id,side) return id+delta[side] end}
  local train=function(id) return stock[id] end
  local state=R.new()
  local entries={}
  for i=1,ne do
    local id,side,track=num(),num(),num()
    entries[i]={tile=id,side=side>=0 and side or nil,track=track>=0 and track or nil}
  end
  local result,change
  local e=entries[1]
  if mode==0 then
    result,change=B.update_segment(board,state,owner,train,e.tile,e.side)
  elseif mode==1 then
    local _; _,change=B.update_track(board,state,owner,train,e.tile,e.track)
  elseif mode==3 then
    local reserve; reserve,change=B.train_moved_change_signals(board,state,train,e.tile,e.side)
    result=reserve and "full" or "free"
  else change=B.update_buffer(board,state,owner,train,entries) end
  local out={status[result] or -1,#change}
  for _,c in ipairs(change) do out[#out+1]=c.tile end
  local view=R.view(board,state)
  for _,id in ipairs(rails) do out[#out+1]=view.tile(id).green_signals end
  print(table.concat(out," "))
end
"""


def reference(source):
    cpp = CPP
    for fn, patterns in [
        ("direction_type.h", [r"enum DiagDirection\s*:"]),
        ("track_type.h", [r"enum Track\s*:", r"enum TrackBits\s*:", r"enum Trackdir\s*:", r"enum TrackdirBits\s*:"]),
        ("signal_type.h", [r"enum SignalType\s*:", r"enum SignalState\s*\{"]),
        ("signal_func.h", [r"enum SigSegState\s*\{"]),
        ("rail.cpp", [r"extern const .* " + n for n in (
            "_trackdir_to_exitdir", "_signal_on_track", "_signal_along_trackdir")]),
    ]:
        cpp += declarations(src(source, fn), patterns)
    table = declarations(src(source, "rail.cpp"), [r"extern const TrackdirBits _exitdir_reaches_trackdirs"])
    cpp += MAP_CPP.replace("TrackdirBits DiagdirReachesTrackdirs", table+"\nTrackdirBits DiagdirReachesTrackdirs")
    cpp += block(src(source, "track_func.h"), r"^inline bool TracksOverlap")
    for name in ("IsPbsSignal", "IsPresignalEntry", "IsPresignalExit", "IsOnewaySignal"):
        cpp += block(src(source, "rail_map.h"), rf"^inline bool {name}\(")
    for name in ("EnsureNoTrainOnTrackProc", "EnsureNoTrainOnTrackBits"):
        cpp += block(src(source, "vehicle.cpp"), rf"^(?:static Vehicle \*|CommandCost ){name}\(")
    signal = src(source, "signal.cpp")
    cpp += signal[signal.index("static const uint SIG_TBU_SIZE"):]  # Every original algorithm after the includes
    cpp += block(src(source, "train_cmd.cpp"), r"^static bool TrainMovedChangeSignals")
    return cpp + RUN_CPP


def tile(id, kind=1, *, owner=1, track=1, direction=0, axis=0, other=0,
         blocked=0, present=0, green=15, high=0, low=0, vehicles=()):
    return (id, kind, owner, track, direction, axis, other, blocked, present, green,
            high, low, len(vehicles), *vehicles)


def cases():
    rng = random.Random(141251)
    for i in range(5200):
        # Arbitrarily connected small yards and section removals, both paired
        # half-track layouts, signal directions, occupancy, and company edges.
        rows, updates = [], []
        mode = i % 3
        for z in range(6, 11):
            for x in range(6, 12):
                id = 64*z + x
                kind = rng.choices((0,1,2,3,4,5,8), (12,30,40,2,3,3,2))[0]
                bits = rng.choice((1,2,4,8,16,32,12,48,*range(1,64))) if kind==1 else rng.choice((1,2,4,8,16,32,12,48))
                axis, direction = rng.randrange(2), rng.randrange(4)
                present = rng.randint(1, 15 if bits in (12,48) else 12)
                if bits not in (12,48):
                    mask = 3 if bits in (8,32) else 12
                    present = rng.choice((mask,mask&-mask,mask-(mask&-mask)))
                hi,lo = rng.choices((0,1,2,3,4,5),(13,2,1,1,2,1),k=2)
                if hi>=4 and present&12==12: present^=4
                if lo>=4 and present&3==3: present^=1
                occupied = ()
                if rng.random()<.32:
                    if kind==3: occupied=(rng.choice((512,128,1<<(direction%2))),)
                    elif kind in (4,5,8): occupied=(rng.choice((512,1<<axis)),)
                    else: occupied=tuple(rng.choice([512]+[1<<tr for tr in range(6) if bits&(1<<tr)]) for _ in range(rng.randint(1,3)))
                rows.append(tile(id,kind,owner=rng.choice((1,1,1,1,2)),track=bits,
                    direction=direction,axis=axis,blocked=int(rng.random()<.13),present=present,
                    green=rng.randrange(16),high=hi,low=lo,vehicles=occupied))
                if mode==1 and kind!=3:
                    updates.append((id,-1,rng.randrange(6)))
                elif mode!=1:
                    updates.append((id,direction if kind==3 else rng.randrange(4),-1))
        if mode!=2: updates=[rng.choice(updates)]
        else: updates=rng.choices(updates,k=rng.choice((2,7,18,79)))
        yield mode,1,rows,updates
    for kind in (6,7):
        # Valid stock span portal axes and generations, within-wormhole train
        # registration on either endpoint, plus full/pass closure.
        for side in range(4):
            a=350
            delta=(-1,64,1,-64)[side]
            b=a+4*delta
            for pos in (None,a,b,a-delta,b+delta):
                tracks=1<<(side%2)
                rows=[tile(a,kind,track=tracks,direction=side,other=b,vehicles=(64,) if pos==a else ()),
                    tile(b,kind,track=tracks,direction=side^2,other=a,vehicles=(64,) if pos==b else ()),
                    tile(a-delta,2,track=tracks,present=12,vehicles=(tracks,) if pos==a-delta else ()),
                    tile(b+delta,2,track=tracks,present=12,vehicles=(tracks,) if pos==b+delta else ())]
                for start,d in ((a,255),(a,side^2),(b,255),(b,side)):
                    yield 0,1,rows,[(start,d,-1)]
    # First/last vehicle movement hook: conventional vs PBS in all facing and
    # occupancy combinations, plus the source's no-op on un-signaled rail.
    for x in range(2):
        railbits=1<<x
        delta=(1,64)[x]
        travel=(2,1)[x]
        for s in range(6):
            for q in range(6):
                for presence in (4,8,12):
                    if s>=4 and presence==12: continue
                    for occupied in (False,True):
                        rows=[tile(410,2,track=railbits,present=presence,high=s),
                              tile(410+delta,1,track=railbits,vehicles=(railbits,) if occupied else ()),
                              tile(410+2*delta,2,track=railbits,present=8,high=q)]
                        yield 3,1,rows,[(410,travel,-1)]
                        yield 3,1,rows,[(410,travel^2,-1)]
                        yield 3,1,rows,[(410+delta,travel,-1)]
    # 100 boundary signals reached about the same common block: the first
    # 64 is the real source limit; no partial block aspect changes.
    rows=[tile(64*10+x,track=3) for x in range(8,60)]
    rows.extend(tile(64*z+x,2,track=2,present=12,green=0) for z in (9,11) for x in range(8,60))
    yield 0,1,rows,[(64*10+8,0,-1)]


def main():
    src_dir=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    all_cases=[(mode,owner,rows,entries) for mode,owner,rows,entries in cases()
               if all(r[1] != 2 or r[10] < 4 and r[11] < 4 for r in rows)]
    payload="".join(f"{len(rows)} {len(entries)} {mode} {owner}\n"+"\n".join(
        " ".join(map(str,r)) for r in [*rows,*entries])+"\n" for mode,owner,rows,entries in all_cases)
    with tempfile.TemporaryDirectory(prefix="luanttd-signal-oracle-") as work:
        work=Path(work)
        (work/"test.cpp").write_text(reference(src_dir))
        (work/"test.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(work/"test.cpp"),"-o",str(work/"test")],check=True)
        expected=subprocess.run([str(work/"test")],input=payload,text=True,capture_output=True,check=True).stdout.splitlines()
        actual=subprocess.run([lua,str(work/"test.lua")],input=payload,text=True,capture_output=True,check=True,cwd=ROOT).stdout.splitlines()
    assert len(expected)==len(actual)==len(all_cases)
    for i,(want,got) in enumerate(zip(expected,actual)):
        assert want==got,(i,want,got,all_cases[i])
    print(f"OpenTTD 14.1 block signals: {len(actual)} conventional compiled graph/update cases agree")


if __name__=="__main__":
    main()
