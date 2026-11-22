"""Differential OpenTTD 14.1 signal eligibility, occupancy/aspects and admission.

python tests/rail_signals_upstream.py SOURCE_TREE [lua5.1]
Compiles original eligibility conditions, status, PBS runtime aspect update,
TrainController signal gate, and TrainApproachingLineEnd.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_yapf_cost_upstream import cpp as cost_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "train_cmd.cpp":"206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "train.h":"35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d",
    "rail_map.h":"13855adaa34c4184bc32bf8f74f0e3610ffc1da3081636de27a0d628a5911b6b",
    "timer/timer_game_tick.h":"be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
})

LUA=r"""
local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local R=dofile(root.."rail_signals.lua")(T)
local kinds={[0]="void","rail","signals","crossing","depot","station","waypoint","bridge","tunnel"}
local words={parameter=-1,no_track=-2,owner=-3,overlap=-4,no_signal=-5,skip=0,new=1,existing=1}
local function yn(b)return b and 1 or 0 end
for line in io.lines() do
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  local out
  local tag=line:sub(1,1)
  if tag=="E" then
    local t={kind=kinds[q[1]],trackbits=q[2],owner=q[3],present_signals=q[4]}
    local ok,why=R.eligible(t,1,q[5],{kind=q[6],variant=q[7],cycle_start=q[8],cycle_stop=q[9],
      skip=q[10]==1,convert=q[11]==1,copy_mask=q[12]})
    out={words[why]}
  elseif tag=="P" then
    local t={present_signals=q[1],green_signals=q[2]}
    out={R.placed_pbs_state(t,q[3],q[4],q[5]==1)}
  elseif tag=="A" then
    local v={direction=q[1],x=q[2],y=q[3],front_length=q[4],speed=q[5],slowing=q[8]==1}
    local verdict=R.approaching_end(v,q[6]==1)
    out={verdict=="reverse" and 0 or 1,v.speed,yn(v.slowing),yn(verdict=="reverse" and q[7]==1)}
  else
    local t={kind=kinds[q[1]],trackbits=q[2],present_signals=q[3],green_signals=q[4],
      upper_signal_type=q[5],lower_signal_type=q[6]}
    local c=R.capture_entry(t,q[7],q[8],q[9]==1)
    if c.tracks==0 then out={c.trackdirs,c.tracks,c.red_tracks}
    else
      local track=0
      while not T.has(c.tracks,track) do track=track+1 end
      local v={force=q[10],stuck=q[11]==1,wait_counter=q[12],speed=q[13],subspeed=q[14],progress=q[15]}
      local result=R.entry_wait(t,c,track,v,{reverse_at_signals=q[16]==1,wait_oneway_signal=q[17],
        wait_twoway_signal=q[18],opposing_waiting=q[19]==1,pbs_segment=q[20]==1,execute_reverse=q[21]==1})
      local face=T.trackdir_for_entry(track,q[7])
      out={c.trackdirs,c.tracks,c.red_tracks,result=="enter" and 1 or result=="reverse" and 2 or 0,
        v.speed,v.subspeed,v.progress,v.force,v.wait_counter,yn(R.along(t,face)),yn(R.pbs_along(t,face)),
        yn(R.oneway_blocking(t,face))}
    end
  end
  print(table.concat(out," "))
end
"""


def cpp(source):
    r=cost_cpp(source).split("struct Node {",1)[0]
    r=r.replace("struct Train {",r"""struct Train {
 uint16_t cur_speed=0,wait_counter=0;
 byte progress=0,subspeed=0,force_proceed=0;
 int flags=0,vehstatus=0,x_pos=0,y_pos=0;
 Direction direction=DIR_N;""")
    # The cost shim declares only DiagDirection upstream; use the actual
    # 8-way Direction enum before injecting Train's extra fields above.
    offset=r.index("struct Train {")
    dir_enum=declarations(src(source,"direction_type.h"),[r"enum Direction\s*:"])
    r=r[:offset]+dir_enum+r[offset:]
    r=r.replace("struct {struct {bool forbid_90_deg;} pf;} _settings_game;",
                "struct {struct {bool forbid_90_deg,reverse_at_signals; int wait_oneway_signal,wait_twoway_signal;} pf;} _settings_game;")
    rail=src(source,"rail_cmd.cpp")
    train=src(source,"train_cmd.cpp")
    railmap=src(source,"rail_map.h")
    r+=declarations(src(source,"signal_type.h"),[r"enum SignalVariant\s*:"])
    r+=declarations(src(source,"train.h"),[r"enum TrainForceProceeding\s*:"])
    r+=declarations(src(source,"rail.cpp"),[
        r"extern const Trackdir _track_enterdir_to_trackdir",r"extern const TrackBits _track_crosses_tracks"])
    # Reuse the many-tile shim, but compile the directional PBS helpers
    # below directly from source in place of the shim's previous helpers.
    for sig in (r"^bool IsPbsSignal\(",r"^bool HasSignalOnTrackdir\(",r"^bool HasPbsSignalOnTrackdir\(",
                r"^bool HasOnewaySignalBlockingTrackdir\("):
        r=r.replace(block(r,sig),"")
    # Waiting helpers precede these definitions in the extracted shim.
    location=r.index("bool IsSafeWaitingPosition(")
    r=r[:location]+"""bool IsPbsSignal(SignalType);
bool HasSignalOnTrackdir(TileIndex,Trackdir);
bool HasPbsSignalOnTrackdir(TileIndex,Trackdir);
bool HasOnewaySignalBlockingTrackdir(TileIndex,Trackdir);
"""+r[location:]
    r+=r"""
bool HasTrack(Tile t,Track tr){return HasTrack(GetTrackBits(t),tr);}
bool IsValidTrack(Track tr){return tr<TRACK_END;}
byte SignalAlongTrackdir(Trackdir td){return _signal_along_trackdir[td];}
bool ValParamTrackOrientation(Track tr){return tr<TRACK_END;}
struct CommandCost{
 int code=0;
 CommandCost()=default;
 explicit CommandCost(int c):code(c){}
 bool Failed()const{return code!=0;}
 bool Succeeded()const{return code==0;}
};
constexpr int STR_ERROR_THERE_IS_NO_RAILROAD_TRACK=-2,STR_ERROR_NO_SUITABLE_RAILROAD_TRACK=-4,STR_ERROR_THERE_ARE_NO_SIGNALS=-5;
#define return_cmd_error(e) return CommandCost(e)
CommandCost CMD_ERROR(-1);
CommandCost CheckTileOwnership(TileIndex t){return CommandCost(GetTileOwner(t)==1 ? 0:-3);}
using DoCommandFlag=unsigned;
"""
    for sig in (r"^inline bool HasSignalOnTrack\(",r"^inline bool HasSignalOnTrackdir\(",
                r"^inline bool IsPbsSignal\(",r"^inline bool HasPbsSignalOnTrackdir\(",
                r"^inline bool HasOnewaySignalBlockingTrackdir\("):
        r+=block(railmap,sig)
    start=rail.index("CommandCost CmdBuildSingleSignal(")
    stop=rail.index("\n\tCommandCost cost;",start)
    r+=rail[start:stop]+"\n return CommandCost(1);\n}\n"
    r+=r"""
bool occupied;
const auto VTYPE_UNUSED=0;
unsigned SetSignalStates(TileIndex id,int val){return board[id].green=val;}
TrackBits GetRailReservationTrackBits(TileIndex id){return GetReservedTrackbits(id);}
CommandCost EnsureNoVehicleOnGround(TileIndex){return CommandCost(occupied?-1:0);}
int set_placed(TileIndex tile,Track track){
 SignalType sigtype=SIGTYPE_PBS;
"""
    i=rail.index("/* PBS signals should show red unless")
    a=rail.rfind("if (IsPbsSignal(sigtype))",0,i)
    r+=block(rail[a:],r"^if \(IsPbsSignal\(sigtype\)\)")
    r+="return GetSignalStates(tile);\n}\n"
    ticks=src(source,"timer/timer_game_tick.h")
    day=int(re.search(r"DAY_TICKS = (\d+)",ticks)[1])
    r+=f"struct Ticks {{static constexpr int DAY_TICKS={day};}};\n"
    r+=r"""
constexpr int VRF_TRAIN_STUCK=0,VS_TRAIN_SLOWING=1,WC_VEHICLE_VIEW=0;
constexpr int SIGSEG_PBS=1;
bool opposing_train,current_segment_pbs,reversed;
void SetWindowDirty(int,int){}
void ReverseTrainDirection(Train*){reversed=true;}
void* CheckTrainAtSignal(void*,void*){return nullptr;}
bool HasVehicleOnPos(TileIndex,DiagDirection *,void*(*)(void*,void*)){return opposing_train;}
int UpdateSignalsOnSegment(TileIndex,DiagDirection,int){return current_segment_pbs?SIGSEG_PBS:0;}
bool HasSignals(TileIndex tile){return GetRailTileType(tile)==RAIL_TILE_SIGNALS;}
bool IsDiagonalDirection(Direction d){return d&1;}
"""
    r=r.replace("int flags=0,vehstatus=0,x_pos=0,y_pos=0;","int flags=0,vehstatus=0,x_pos=0,y_pos=0,index=0;")
    r=r.replace("int cached_total_length=32;","int cached_total_length=32,cached_veh_length=8;")
    r+=declarations(train,[r"static const uint16_t _breakdown_speeds"])
    r+=block(train,r"^static bool TrainApproachingLineEnd\(")
    # Keep the red-signal snapshot and force-counter/stop changes exactly
    # as the train controller writes them; the wrapper tags return paths.
    r+=r"""
int entry(Train *v,TileIndex to,DiagDirection enterdir,TrackdirBits trackdirbits,TrackBits red_signals,
          TrackBits chosen_track,bool reverse) {
 struct {TileIndex new_tile;} gp{to};
"""
    r+=block(train,r"^\s*if \(v->force_proceed != TFP_NONE && IsPlainRailTile\(gp.new_tile\) && HasSignals")
    r+=block(train,r"^\s*if \(\(red_signals & chosen_track\) && v->force_proceed == TFP_NONE\)")
    before=train.index("reverse_train_direction:\n",train.index("bool TrainController(Train *v, Vehicle *nomove, bool reverse)\n{"))
    r+="return 1;\nreverse_train_direction:\n"+block(train[before:],r"^\s*if \(reverse\)")+"return 2;\n}\n"
    r+=r"""
int main(){
 char tag;
 while(std::cin>>tag){
  auto &t=board[7];
  t={};
  if(tag=='E'){
   int tr,kind,var,a,b,skip,convert,copy;
   std::cin>>t.kind>>t.bits>>t.owner>>t.present>>tr>>kind>>var>>a>>b>>skip>>convert>>copy;
   std::cout<<CmdBuildSingleSignal(0,7,Track(tr),SignalType(kind),SignalVariant(var),convert,skip,false,
      SignalType(a),SignalType(b),0,copy).code<<"\n";
  }else if(tag=='P'){
   int tr,on;
   std::cin>>t.present>>t.green>>tr>>t.reserved_bits>>on;
   occupied=on;t.kind=K_SIGNAL;
   std::cout<<set_placed(7,Track(tr))<<"\n";
  }else if(tag=='A'){
   Train v;
   int d,len,speed,signal,reverse,slowing;
   std::cin>>d>>v.x_pos>>v.y_pos>>len>>speed>>signal>>reverse>>slowing;
   v.direction=Direction(d);v.gcache.cached_veh_length=len;v.cur_speed=speed;
   v.vehstatus=slowing?VS_TRAIN_SLOWING:0;
   reversed=false;
   auto ok=TrainApproachingLineEnd(&v,signal,reverse);
   std::cout<<ok<<" "<<v.cur_speed<<" "<<bool(v.vehstatus&VS_TRAIN_SLOWING)<<" "<<reversed<<"\n";
  }else{
   Train v;v.tile=6;v.owner=1;
   int dir,oldtd,no90,force,stuck,speed,sub,prog,reverse_at,one,two,opp,pbs,rev;
   std::cin>>t.kind>>t.bits>>t.present>>t.green>>t.upper>>t.lower>>dir>>oldtd>>no90
    >>force>>stuck>>v.wait_counter>>speed>>sub>>prog>>reverse_at>>one>>two>>opp>>pbs>>rev;
   _settings_game.pf.reverse_at_signals=reverse_at;
   _settings_game.pf.wait_oneway_signal=one;
   _settings_game.pf.wait_twoway_signal=two;
   v.force_proceed=force;v.flags=stuck;v.cur_speed=speed;v.subspeed=sub;v.progress=prog;
   opposing_train=opp;current_segment_pbs=pbs;reversed=false;move_direction=DiagDirection(dir);
   auto ts=GetTileTrackStatus(7,TRANSPORT_RAIL,0,ReverseDiagDir(move_direction));
   auto reach=DiagdirReachesTrackdirs(move_direction);
   auto td=TrackStatusToTrackdirBits(ts)&reach;
   auto red=TrackdirBitsToTrackBits(TrackdirBits(ts>>16)&reach);
   auto tracks=TrackdirBitsToTrackBits(td);
   if(no90)tracks&=~_track_crosses_tracks[oldtd%8];
   std::cout<<td<<" "<<int(tracks)<<" "<<int(red);
   if(tracks){
    auto chosen=Track(__builtin_ctz(unsigned(tracks)));
    auto result=entry(&v,7,move_direction,td,red,TrackToTrackBits(chosen),rev);
    auto face=_track_enterdir_to_trackdir[chosen][dir];
    std::cout<<" "<<result<<" "<<v.cur_speed<<" "<<int(v.subspeed)<<" "<<int(v.progress)<<" "
       <<int(v.force_proceed)<<" "<<v.wait_counter<<" "<<HasSignalOnTrackdir(7,face)<<" "
       <<HasPbsSignalOnTrackdir(7,face)<<" "<<HasOnewaySignalBlockingTrackdir(7,face);
   }
   std::cout<<"\n";
  }
 }
}
"""
    return r


def cases():
    rng=random.Random(1441)
    td=[0,1,2,3,4,5,8,9,10,11,12,13]
    paths=[1,2,4,8,16,32,12,48]
    for _ in range(9000):
        cycle_a,cycle_b=rng.randrange(7),rng.randrange(7)
        bits=rng.choice([*paths,rng.randrange(64)])
        vals=[rng.randrange(3),bits,rng.choice([1,1,2]),rng.randrange(16),rng.randrange(7),
              rng.randrange(7),rng.randrange(3),cycle_a,cycle_b,rng.randrange(2),rng.randrange(2),rng.randrange(16)]
        yield " ".join(map(str,["E",*vals]))
    for present in range(16):
        for green in range(16):
            for t in range(6):
                for reserved in (0,1<<t):
                    for occupied in range(2):
                        yield f"P {present} {green} {t} {reserved} {occupied}"
    for i in range(6000):
        vals=[rng.randrange(8),rng.randrange(16),rng.randrange(16),rng.randrange(1,9),rng.randrange(1000),
              rng.randrange(2),rng.randrange(2),rng.randrange(2)]
        yield " ".join(map(str,["A",*vals]))
    for i in range(22000):
        one=rng.randrange(1,32)
        two=rng.randrange(1,54)
        wait=rng.choice([rng.randrange(65536),0,0,one*148-1,two*148-1,65535])
        vals=[rng.choice([1,2,2,2]),rng.choice(paths),rng.randrange(16),rng.randrange(16),rng.randrange(6),rng.randrange(6),
              rng.randrange(4),rng.choice(td),rng.randrange(2),rng.randrange(3),rng.randrange(2),wait,
              rng.randrange(400),rng.randrange(256),rng.randrange(256),rng.randrange(2),one,two,
              rng.randrange(2),rng.randrange(2),rng.randrange(2)]
        yield " ".join(map(str,["T",*vals]))


def main():
    card=list(cases())
    payload=("\n".join(card)+"\n").encode()
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        want=subprocess.check_output([p/"ref"],input=payload).splitlines()
        got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"port.lua"],
                                    cwd=ROOT,input=payload).splitlines()
    assert len(want)==len(got)==len(card)
    for i,(a,b) in enumerate(zip(want,got)):
        assert a==b,(i,card[i],a,b)
    results=[line.split()[3] for kind,line in zip(card,want) if kind.startswith("T") and len(line.split())>3]
    n_wait=results.count(b"0")
    n_turn=results.count(b"2")
    assert n_wait>150 and n_turn>80,(n_wait,n_turn)
    print(f"PASS: {len(card):,} pinned rail signal eligibility, aspect and entry cases;"
          f" {n_wait:,} waited and {n_turn:,} reversed in boundary gate")
if __name__=="__main__":
    main()
