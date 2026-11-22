"""Check OpenTTD 14.1's stock ordinary front-signal and tail release rules.

python tests/rail_consist_reservation_upstream.py SOURCE_TREE [lua5.1]
The reference compiles ClearPathReservation and the TrainController event
snippets. Positions, ownership labels and consist ordering are fixtures.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_reservation_upstream import cpp as reservation_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST["train_cmd.cpp"]="206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059"

LUA=r"""
local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local P=dofile(root.."rail_reservation.lua")(T,F,C)
local R=dofile(root.."rail_consist_reservation.lua")(T,F,P)
local kinds={[0]="void","rail","signals","crossing","depot","station","waypoint","bridge","tunnel"}
for line in io.lines() do
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  if line:sub(1,1)=="K" then print(R.connecting_track(q[1],q[2]))
  else
    local td,dir,k,flags,prior,sig,extra=q[1],q[2],q[3],q[4],q[5],q[6],q[7]
    local p=dir%2
    local next_td=T.diagonal_trackdir(dir)
    local track=T.track(td)
    local function t(kind,bits,sd)
      return {kind=kinds[kind],owner=1,railtype=0,dir=sd,axis=sd%2,trackbits=bits,station=1}
    end
    local records={}
    records[6]=prior~=0 and t(5,2^p,dir) or nil
    local old_dir=k==4 and dir or track%2
    records[7]=t(k,T.union(2^track,extra),old_dir)
    records[7].axis=p
    records[8]=t(sig==1 and 2 or (flags==1 and 5 or 1),2^p,dir)
    if sig==1 then
      records[8].present_signals=T.signal_along(next_td)
      records[8].green_signals=records[8].present_signals
      records[8].upper_signal_type=4
    end
    local b={tile=function(i)return records[i] end,adjacent=function(i,d)return i+(d==dir and 1 or -1)end}
    local state=R.new()
    if extra~=0 then
      local tr=0
      while not T.has(extra,tr) do tr=tr+1 end
      assert(R.register(b,state,2,1,{{tile=7,td=tr}}))
    end
    local index
    if q[8]==0 then
      assert(R.register(b,state,1,1,{{tile=7,td=td}}));index=1
    elseif q[8]==1 then
      assert(R.register(b,state,1,1,{{tile=7,td=td},{tile=7,td=td}}));index=1
    else
      assert(R.register(b,state,1,1,{{tile=8,td=next_td},{tile=7,td=td}}));index=2
    end
    if prior~=0 then
      assert(P.try_reserve(b,state.bits,6,p))
      state.claims[6]={[p]=1}
    end
    local okay,events=R.enter(b,state,1,index,8,next_td)
    assert(okay,events)
    local red=0
    for _,e in ipairs(events) do if e.kind=="front_passed_pbs" then red=1 end end
    assert(R.valid_state(b,state))
    print(table.concat({P.bits(b,state.bits,6),P.bits(b,state.bits,7),P.bits(b,state.bits,8),red}," "))
  end
end
"""


def cpp(source):
    r=reservation_cpp(source).split("int main(){",1)[0]
    r=r.replace("struct Train {",r"""struct Train {
 bool front=true,tail=true;
 Trackdir td=TRACKDIR_X_NE;
 bool IsFrontEngine()const{return front;}
 const Train *Next()const{return tail?nullptr:this;}
 Trackdir GetVehicleTrackdir()const{return td;}""")
    train=src(source,"train_cmd.cpp")
    r+=declarations(train,[r"\s*static const TrackBits _connecting_track"])
    r+=r"""
struct DummyCost { bool Succeeded() const { return true; }};
DummyCost TunnelBridgeIsFree(TileIndex,TileIndex,const Train*){return {};}
TileIndex GetOtherTunnelBridgeEnd(TileIndex){return 9;}
bool IsBridge(TileIndex i){return IsBridgeTile(i);}
int closed;
void SetSignalStateByTrackdir(TileIndex,Trackdir,SignalState s){closed=(s==SIGNAL_STATE_RED);}
"""
    r+=block(train,r"^static void ClearPathReservation\(")
    red=block(train,r"^\s*if \(v->IsFrontEngine\(\) && HasPbsSignalOnTrackdir\(gp.new_tile, tdir\)\)")
    leave=re.search(r"if \(v->Next\(\) == nullptr\) ClearPathReservation\(v, v->tile, v->GetVehicleTrackdir\(\)\);",train).group()
    r+="void crossed(Train *v,Trackdir tdir){\n struct { TileIndex new_tile=8; } gp;\n"+red+leave+"\n}\n"
    r+=r"""
int main(){
 char kind;
 types[0]={0,0,1};
 while(std::cin>>kind){
  if(kind=='K'){
   int from,to;std::cin>>from>>to;
   std::cout<<int(_connecting_track[from][to])<<"\n";
   continue;
  }
  int td,dir,k,joins,prior,sig,extra,part;
  std::cin>>td>>dir>>k>>joins>>prior>>sig>>extra>>part;
  move_direction=DiagDirection(dir);
  int axis=dir%2;
  board[6]={};board[7]={};board[8]={};board[9]={};
  auto &a=board[7];auto &b=board[8];auto &p=board[6];
  a.kind=k;a.bits=(1<<(td%8))|extra;a.dir=k==K_DEPOT?dir:axis;a.station=1;
  a.reserved_bits=a.bits;a.reserved=1;
  b.kind=sig?K_SIGNAL:joins?K_STATION:K_RAIL;b.bits=1<<axis;b.dir=dir;b.station=1;
  b.reserved_bits=b.bits;b.reserved=1;
  auto next=DiagDirToDiagTrackdir(DiagDirection(dir));
  if(sig){b.present=_signal_along_trackdir[next];b.upper=4;}
  if(prior){p.kind=K_STATION;p.dir=axis;p.station=1;p.reserved_bits=1<<axis;p.reserved=1;}
  Train v;
  v.tile=7;v.td=Trackdir(td);v.front=part!=2;v.tail=part!=1;
  closed=0;
  crossed(&v,next);
  std::cout<<int(GetReservedTrackbits(6))<<" "<<int(GetReservedTrackbits(7))<<" "
   <<int(GetReservedTrackbits(8))<<" "<<closed<<"\n";
 }
}
"""
    return r


def cases():
    rng=random.Random(1419)
    for a in range(4):
        for b in range(4):
            yield f"K {a} {b}"
    exits={0:0,1:1,2:0,3:1,4:2,5:1,8:2,9:3,10:3,11:2,12:3,13:0}
    for i in range(2100):
        td=rng.choice(list(exits))
        d=exits[td]
        tr=td%8
        kind=rng.choice([1,2,3,4,5,6] if tr<2 else [1,2])
        part=rng.randrange(3)
        continuation=int(kind==5 and rng.randrange(2)==0)
        platform_before=int(kind==5 and rng.randrange(2)==0)
        sig=int(not continuation and i%5==0)
        parallel=(1<<(tr^1)) if tr>=2 and rng.randrange(2)==0 else 0
        yield " ".join(map(str,["T",td,d,kind,continuation,platform_before,sig,parallel,part]))


def main():
    inputs=list(cases())
    data=("\n".join(inputs)+"\n").encode()
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        want=subprocess.check_output([p/"ref"],input=data).splitlines()
        got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"port.lua"],
                                    cwd=ROOT,input=data).splitlines()
    assert len(inputs)==len(want)==len(got)
    for i,(a,b) in enumerate(zip(want,got)):
        assert a==b,(i,inputs[i],a,b)
    print(f"PASS: {len(want):,} stock front-signal/tail-release and following-track cases")


if __name__=="__main__":
    main()
