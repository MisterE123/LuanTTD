"""Differential OpenTTD 14.1 PBS allocation/release and path-end queries.

python tests/rail_reservation_upstream.py SOURCE_TREE [lua5.1]
Compiles stock reservation/follower code with a synthetic tile array.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_yapf_cost_upstream import cpp as cost_cpp
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "rail_map.h":"13855adaa34c4184bc32bf8f74f0e3610ffc1da3081636de27a0d628a5911b6b",
    "pathfinder/yapf/yapf_rail.cpp":"da45c1103168f0d5e81c965f98d680da9fb178567ad596cda69f6288eeb9e49d",
})

LUA = r"""
local T=dofile("mods/luanttd_core/openttd/rail_track.lua")
local F=dofile("mods/luanttd_core/openttd/rail_follow.lua")(T)
local C=dofile("mods/luanttd_core/openttd/rail_yapf_cost.lua")(T,F)
local R=dofile("mods/luanttd_core/openttd/rail_reservation.lua")(T,F,C)
local kinds={[0]="void","rail","signals","crossing","depot","station","waypoint","bridge","tunnel"}
local function yes(b) return b and 1 or 0 end
for line in io.lines() do
  local tag=line:sub(1,1)
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  local tiles,bits={},{}
  local dir=q[4]
  local board={tile=function(id)return tiles[id] end,
    adjacent=function(id,d)return id+(d==dir and 1 or -1) end,
    railtype=function() return {compatible={[0]=true,[1]=true}} end}
  for i=5,9 do
    local j=6+(i-5)*11
    if q[j]~=0 then
      tiles[i]={kind=kinds[q[j]],trackbits=q[j+1],axis=q[j+2]%2,dir=q[j+2],
        owner=q[j+3],railtype=q[j+4],station=q[j+5],
        present_signals=q[j+7],upper_signal_type=q[j+8],lower_signal_type=q[j+9],
        blocked=q[j+10]==1,other=9,skip=3}
      if q[j+6]~=0 then bits[i]=q[j+6] end
    end
  end
  local out
  if tag=="M" then
    local okay
    if q[2]==1 then okay=R.try_reserve(board,bits,q[1],q[3])
    else okay=R.unreserve(board,bits,q[1],q[3]) end
    out={yes(okay),R.bits(board,bits,q[1])}
  elseif tag=="P" then
    local ok,after=R.reserve_platform(board,bits,q[1],q[4],q[5])
    out={yes(ok),after}
  elseif tag=="S" then
    local ok,after=R.set_platform(board,bits,q[1],q[4],q[2]==1)
    out={yes(ok),after or -1}
  elseif tag=="F" then
    local train={owner=1,railtype=0,compatible={[0]=true,[1]=true}}
    local last,td=R.follow_end(board,bits,train,q[1],q[3],q[2]==1)
    out={last,td,
      yes(R.safe_end(board,bits,train,last,td,true,{forbid_90=q[5]==1})),
      yes(R.waiting_free(board,bits,train,last,td,{forbid_90=q[5]==1}))}
  else error(line) end
  for i=5,9 do out[#out+1]=R.bits(board,bits,i) end
  print(table.concat(out," "))
end
local board={tile=function()return {kind="rail",trackbits=63} end}
local state={}
assert(not R.try_reserve(board,state,7,-1))
assert(not R.try_reserve(board,state,7,8))
assert(next(state)==nil)
"""


def cpp(source):
    r=cost_cpp(source).split("struct Node {",1)[0]
    a=r.index("TrackBits GetReservedTrackbits(TileIndex id){")
    z=r.index("DiagDirection GetRailDepotDirection",a)
    r=r[:a]+"TrackBits GetReservedTrackbits(TileIndex id);\n"+r[z:]
    r+=r"""
inline bool IsRailDepotTile(TileIndex tile);
bool HasTrack(Tile tile,Track tr){return HasTrack(GetTrackBits(tile),tr);}
TrackBits GetRailReservationTrackBits(TileIndex id){return TrackBits(Get(id).reserved_bits);}
TrackBits GetDepotReservationTrackBits(TileIndex id){return TrackBits(Get(id).reserved_bits);}
TrackBits GetCrossingReservationTrackBits(TileIndex id){return TrackBits(Get(id).reserved_bits);}
TrackBits GetStationReservationTrackBits(TileIndex id){return TrackBits(Get(id).reserved_bits);}
TrackBits GetTunnelBridgeReservationTrackBits(TileIndex id){return TrackBits(Get(id).reserved_bits);}
void SetTrackReservation(TileIndex id,TrackBits bits){board[id].reserved_bits=bits;}
bool HasDepotReservation(TileIndex id){return Get(id).reserved_bits!=0;}
bool HasCrossingReservation(TileIndex id){return Get(id).reserved_bits!=0;}
void SetDepotReservation(TileIndex id,bool b){SetTrackReservation(id,b?DiagDirToDiagTrackBits(GetRailDepotDirection(id)):TRACK_BIT_NONE);}
void SetCrossingReservation(TileIndex id,bool b){SetTrackReservation(id,b?GetCrossingRailBits(id):TRACK_BIT_NONE);}
void SetRailStationReservation(TileIndex id,bool b){board[id].reserved=b;SetTrackReservation(id,b?TrackToTrackBits(GetRailStationTrack(id)):TRACK_BIT_NONE);}
void SetTunnelBridgeReservation(TileIndex id,bool b){SetTrackReservation(id,b?DiagDirToDiagTrackBits(GetTunnelBridgeDirection(id)):TRACK_BIT_NONE);}
bool IsRailStation(TileIndex id){return IsRailStationTile(id);}
TrackBits TrackStatusToTrackBits(TrackStatus s){return TrackdirBitsToTrackBits(TrackStatusToTrackdirBits(s));}
void MarkBridgeDirty(TileIndex){}
void MarkTileDirtyByTile(TileIndex){}
void UpdateLevelCrossing(TileIndex,bool=true){}
constexpr int SRT_PATH_RESERVATION=1;
void TriggerStationRandomisation(void*,TileIndex,int){}
struct {struct {bool show_track_reservation=false;}gui;} _settings_client;
struct PBSTileInfo{
 TileIndex tile;Trackdir td;bool okay;
 PBSTileInfo(TileIndex i,Trackdir d,bool o):tile(i),td(d),okay(o){}
};
Trackdir DiagDirToDiagTrackdir(DiagDirection d){
 const Trackdir track[]={TRACKDIR_X_NE,TRACKDIR_Y_SE,TRACKDIR_X_SW,TRACKDIR_Y_NW};
 return track[d];
}
"""
    rail_map=src(source,"rail_map.h")
    r+=block(rail_map,r"^inline bool TryReserveTrack\(")
    r+=block(rail_map,r"^inline void UnreserveTrack\(")
    pbs=src(source,"pbs.cpp")
    for signature in (r"^TrackBits GetReservedTrackbits\(",r"^bool TryReserveRailTrack\(",
                      r"^void UnreserveRailTrack\(",r"^static PBSTileInfo FollowReservation\(",
                      r"^void SetRailStationPlatformReservation\("):
        r+=block(pbs,signature)
    r+="struct Reserve { TileIndex m_origin_tile;\n"
    r+=block(src(source,"pathfinder/yapf/yapf_rail.cpp"),r"^\s*bool ReserveRailStationPlatform\(")
    r+="};\n"
    r+=r"""
int main(){
 char mode;
 int id,flag,track,d,extra;
 types[0]={0,0,3};types[1]={0,0,3};
 while(std::cin>>mode>>id>>flag>>track>>d>>extra){
  for(int i=5;i<=9;++i){
   auto &t=board[i];
   if(!(std::cin>>t.kind>>t.bits>>t.dir>>t.owner>>t.railtype>>t.station
                >>t.reserved_bits>>t.present>>t.upper>>t.lower>>t.blocked))return 1;
   t.reserved=t.reserved_bits!=0;
   t.skip=3;
  }
  move_direction=DiagDirection(d);
  if(mode=='M'){
   bool success=true;
   if(flag)success=TryReserveRailTrack(id,Track(track),true);
   else UnreserveRailTrack(id,Track(track));
   std::cout<<success<<" "<<int(GetReservedTrackbits(id));
  }else if(mode=='P'){
   Reserve r{extra};
   bool ok=r.ReserveRailStationPlatform(id,move_direction);
   std::cout<<ok<<" "<<id;
  }else if(mode=='S'){
   SetRailStationPlatformReservation(id,move_direction,flag!=0);
   // The stock setter returns void; this endpoint is bookkeeping for Lua.
   int i=id;
   do {i=TileAddByDiagDir(i,move_direction);} while(IsCompatibleTrainStationTile(i,id));
   std::cout<<"1 "<<i;
  }else{
   auto e=FollowReservation(1,3,id,Trackdir(track),flag!=0);
   Train v;v.owner=1;v.railtype=0;v.compatible_railtypes=3;
   std::cout<<e.tile<<" "<<int(e.td)<<" "<<IsSafeWaitingPosition(&v,e.tile,e.td,true,extra!=0)
     <<" "<<IsWaitingPositionFree(&v,e.tile,e.td,extra!=0);
  }
  for(int i=5;i<=9;++i) std::cout<<" "<<int(GetReservedTrackbits(i));
  std::cout<<"\n";
 }
}
"""
    return r


def corpus():
    rng=random.Random(14149)
    legal=[0,1,2,4,8,16,32,12,48]
    empty=[0]*11
    def tile(kind=1,bits=1,dir_=0,res=0,sid=3):
        return [kind,bits,dir_,1,0,sid,res,0,0,0,0]
    def record(tag,args,board):
        return tag+" "+" ".join(map(str,args+sum(board,[])))
    for kind in (1,2):
        for tracks in range(1,64):
            for reserve in legal:
                if reserve & ~tracks:continue
                for track in range(6):
                    if not ((tracks>>track)&1):continue
                    for op in range(2):
                        yield record("M",[5,op,track,0,0],[tile(kind,tracks,0,reserve)]+[empty]*4)
    for kind in range(3,9):
        for direction in range(4):
            track=direction%2
            for res in (0,1<<track):
                for op in range(2):
                    yield record("M",[5,op,track,direction,0],[tile(kind,0,direction,res)]+[empty]*4)
    for i in range(2400):
        travel=rng.randrange(4)
        bit=1<<(travel%2)
        start=rng.randrange(5,10)
        origin=rng.randrange(4,10)
        board=[tile(5,0,travel,bit if rng.randrange(4)==0 else 0,sid=3 if rng.randrange(4) else 4) for _ in range(5)]
        for m in board:
            m[4]=rng.randrange(2)
            m[10]=int(rng.randrange(16)==0)
        board[start-5][10]=0
        yield record(rng.choice(["P","P","S"]),[start,rng.randrange(2),0,travel,origin],board)
    for i in range(4800):
        travel=rng.randrange(4)
        td=(0,1,8,9)[travel]
        bit=1<<(travel%2)
        start=tile(1,bit,travel,bit if i%9!=0 else 0)
        board=[start]+[tile(1,bit,travel,bit if rng.randrange(7) else 0) for _ in range(4)]
        if i%5==1:
            board[1]=tile(5,0,travel,bit)
            board[2]=tile(5,0,travel,bit if i%11 else 0)
            board[3]=tile(5,0,travel,0) # over a partial platform
        elif i%5==2:
            signal=board[2]
            signal[0]=2
            signal[7]=rng.choice([0,4,8,12])
            signal[8]=rng.randrange(6)
        elif i%5==3:
            board[3]=tile(4,0,(travel+2)%4,bit)
        elif i%5==4:
            kind=rng.choice([7,8])
            board[0]=tile(kind,0,travel,bit)
            board[4]=tile(kind,0,(travel+2)%4,bit if i%7 else 0)
        yield record("F",[5,rng.randrange(2),td,travel,rng.randrange(2)],board)


def main():
    cases=list(corpus())
    payload=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        p=Path(d)
        (p/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        want=subprocess.check_output([p/"ref"],input=payload).splitlines()
        got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"port.lua"],
                                    cwd=ROOT,input=payload).splitlines()
    assert len(cases)==len(want)==len(got)
    for i,(a,b) in enumerate(zip(want,got)):
        assert a==b,(i,cases[i],a,b)
    n_ops=sum(line.startswith("M") for line in cases)
    print(f"PASS: {len(cases):,} rail PBS comparisons; {n_ops:,} allocate/release operations, "
          "2,400 platform writes and 4,800 directional path-end/safe queries")


if __name__=="__main__":
    main()
