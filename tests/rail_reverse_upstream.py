"""Compare stopped ordinary-consist reversal to pinned OpenTTD 14.1.

python tests/rail_reverse_upstream.py SOURCE_TREE [lua5.1]
Compiles the exact swap and before/after adjustment functions. The shim
uses source vehicle motion and entry/wagon selection on an owned rail board.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_motion_upstream import cpp as motion_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST["train.h"]="35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d"

LUA=r"""
local r="mods/bayline/openttd/"
local T=dofile(r.."rail_track.lua")
local F=dofile(r.."rail_follow.lua")(T)
local Costs=dofile(r.."rail_yapf_cost.lua")(T,F)
local P=dofile(r.."rail_reservation.lua")(T,F,Costs)
local Life=dofile(r.."rail_consist_reservation.lua")(T,F,P)
local Raw=dofile(r.."rail_motion.lua")(T)
local K=dofile(r.."rail_consist_motion.lua")(T,Raw,F,Life)
local Signal=dofile(r.."rail_signals.lua")(T)
local Reverse=dofile(r.."rail_reverse.lua")(T,Raw,K,Life,Signal,F,P)
local function id(x,y)return x+y*256 end
local off={[0]=-1,256,1,-256}
for line in io.lines() do
  local q={}
  for x in line:gmatch("%-?%d+") do q[#q+1]=tonumber(x) end
  local nt,np,ts=q[1],q[2],q[3]
  local at=id(128,128)
  local board={}
  local tiles,route={},{}
  for i=1,nt do
    local td=q[3+i]
    tiles[at]={kind="rail",owner=1,railtype=0,trackbits=2^T.track(td)}
    route[at]=td;at=at+off[T.exit_side(td)]
  end
  function board.tile(i)return tiles[i] end
  function board.adjacent(i,d)return i+off[d] end
  function board.xy(i)return i%256,math.floor(i/256) end
  board.tile_at=id
  local poses={[0]=assert(Raw.entry_trackdir(128,128,q[4]))}
  for i=1,ts do
    local prev=poses[i-1]
    local next_id=id(prev.tx,prev.ty)+off[T.exit_side(prev.td)]
    local tag,pose=Raw.step(prev,route[next_id])
    assert(tag=="move" or tag=="enter")
    poses[i]=pose
  end
  local parts={}
  local offset=0
  for i=1,np do
    local p=assert(poses[ts-offset])
    local len=q[3+nt+i]
    parts[i]={length=len,tile=id(p.tx,p.ty),pose=p}
    if i<np then offset=offset+K.next_offset(len,q[4+nt+i]) end
  end
  local train,why=K.place(board,1,parts)
  if not train then print("skip")
  else
    local parts_identity={}
    for i=1,np do train.parts[i].vehicle_id=100+i;parts_identity[i]=train.parts[i].length end
    local result,why=Reverse.plan(board,train,{speed=0})
    assert(result,why)
    assert(Reverse.commit(train,result))
    local words={result.spacing_ok and 1 or 0,#result.adjustments}
    for i,p in ipairs(train.parts) do
      assert(p.vehicle_id==100+i and p.length==parts_identity[i])
      words[#words+1]=p.pose.x;words[#words+1]=p.pose.y;words[#words+1]=p.tile
      words[#words+1]=p.pose.td;words[#words+1]=p.pose.direction
    end
    print(table.concat(words," "))
  end
end
"""


def cpp(source):
    b=motion_cpp(source).split("int main(){",1)[0]
    b="#include <algorithm>\n#include <cstdlib>\n#include <map>\n"+b
    train=src(source,"train_cmd.cpp")
    h=src(source,"train.h")
    b+=r"""
constexpr int GVF_GOINGUP_BIT=0,GVF_GOINGDOWN_BIT=1;
constexpr int VS_HIDDEN=1;
bool HasBit(uint16_t x,int n){return x&(1<<n);}
void SetBit(uint16_t &x,int n){x|=(1<<n);}
void ClrBit(uint16_t &x,int n){x&=~(1<<n);}
template <class T> void Swap(T &x,T &y){std::swap(x,y);}
Direction ReverseDir(Direction direction){return Direction((direction+4)%8);}
struct Train : Vehicle {
 int z_pos=0, vehstatus=0;
 uint16_t gv_flags=0;
 TrackBits track=TRACK_BIT_X;
 struct {int cached_veh_length=0;} gcache;
 Train *next=nullptr,*previous=nullptr;
 Train *Next() const{return next;}
 Train *Previous() const{return previous;}
 Train *Last(){Train *v=this;while(v->Next())v=v->Next();return v;}
 void UpdatePosition(){}
 void UpdateViewport(bool,bool){}
 int UpdateInclination(bool,bool){return 0;}
"""
    b+=block(h,r"^\s*int CalcNextVehicleOffset\(")+"};\n"
    b+=r"""
int CountVehiclesInChain(Train *v){int n=0;while(v){n++;v=v->Next();}return n;}
bool IsTileType(TileIndex,int){return false;}
bool IsBridgeTile(TileIndex){return false;}
constexpr int MP_TUNNELBRIDGE=0;
int VehicleEnterTile(Train *,TileIndex,int,int){return 0;}
Track GetRailDepotTrack(TileIndex){std::abort();}
TrackBits TrackToTrackBits(Track t){return TrackBits(1<<t);}
bool IsValidDiagDirection(DiagDirection d){return unsigned(d)<4;}
int TicksToLeaveDepot(Train*){std::abort();}
int steps_crossed;
bool TrainController(Train *v,Train *nomove,bool reverse=true){
 Train *prev=v->Previous();
 for(;v!=nomove;prev=v,v=v->Next()){
  auto gp=GetNewVehiclePos(v);
  if(gp.old_tile!=gp.new_tile){
    auto enterdir=between(gp.old_tile,gp.new_tile);
    assert(enterdir!=INVALID_DIAGDIR && prev);
    TrackBits chosen_track;
"""
    b+=declarations(train,[r"\s*static const TrackBits _connecting_track"])
    a=train.index("if (prev->tile == gp.new_tile) {",train.index("bool TrainController(Train *v, Vehicle *nomove, bool reverse)"))
    end=train.index("chosen_track &= bits;",a)
    fragment=train[a:end].replace("DiagdirBetweenTiles","between")
    b+="constexpr TrackBits bits=TRACK_BIT_MASK;bool IsTunnel(TileIndex);\n"+fragment
    b+=r"""
    v->direction=apply_entry(gp,chosen_track,enterdir);
    v->track=chosen_track;
    ++steps_crossed;
  }
  v->x_pos=gp.x;v->y_pos=gp.y;v->tile=gp.new_tile;
 }
 return true;
}
bool IsTunnel(TileIndex){return false;}
"""
    for sig in [r"^static void SwapTrainFlags",r"^static void UpdateStatusAfterSwap",
                r"^void ReverseTrainSwapVeh",r"^static void AdvanceWagonsBeforeSwap",
                r"^static void AdvanceWagonsAfterSwap"]:
        b+=block(train,sig)
    # Unchanged orchestration for the non-depot part of ReverseTrainDirection.
    a=train.index("/* count number of vehicles */",train.index("\nvoid ReverseTrainDirection("))
    end=train.index("AdvanceWagonsAfterSwap(v);",a)+len("AdvanceWagonsAfterSwap(v);")
    b+="void reverse_ordinary(Train *v) {\n"+train[a:end]+"}\n"
    b+=r"""
constexpr int off[]={-1,WIDTH,1,-WIDTH};
Vehicle seed(TileIndex id,int td){
 auto direction=_trackdir_to_exitdir[(td+8)%16];
 direction=DiagDirection((direction+2)%4);
 GetNewVehiclePosResult gp{16*(id%WIDTH),16*(id/WIDTH),id,id};
 auto d=apply_entry(gp,TrackBits(1<<(td%8)),direction);
 return Vehicle{gp.x,gp.y,d,id};
}
bool spacing(Train *head){
 for(Train *v=head;v->Next();v=v->Next()){
  auto *u=v->Next();
  if(std::max(std::abs(v->x_pos-u->x_pos),std::abs(v->y_pos-u->y_pos))!=v->CalcNextVehicleOffset()) return false;
 }
 return true;
}
int main(){
 int nt,np,ts;
 while(std::cin>>nt>>np>>ts){
  std::map<int,int> line;
  int id=128+128*WIDTH,td;
  for(int i=0;i<nt;i++){std::cin>>td;line[id]=td;id+=off[_trackdir_to_exitdir[td]];}
  std::vector<Vehicle> samples;
  samples.push_back(seed(128+128*WIDTH,line[128+128*WIDTH]));
  for(int i=0;i<ts;i++){
   auto prev=samples.back();
   auto gp=GetNewVehiclePos(&prev);
   auto d=prev.direction;
   if(gp.new_tile!=gp.old_tile) d=apply_entry(gp,TrackBits(1<<(line.at(gp.new_tile)%8)),between(gp.old_tile,gp.new_tile));
   samples.push_back({gp.x,gp.y,d,gp.new_tile});
  }
  std::vector<Train> chain(np);
  for(int i=0;i<np;i++){
   std::cin>>chain[i].gcache.cached_veh_length;
   if(i+1<np){chain[i].next=&chain[i+1];chain[i+1].previous=&chain[i];}
  }
  int offset=0;
  for(auto &v:chain){
   static_cast<Vehicle&>(v)=samples.at(ts-offset);
   v.track=TrackBits(1<<(line.at(v.tile)%8));
   offset+=v.CalcNextVehicleOffset();
  }
  if(!spacing(&chain[0])){std::cout<<"skip\n";continue;}
  steps_crossed=0;
  reverse_ordinary(&chain[0]);
  std::cout<<spacing(&chain[0])<<" "<<steps_crossed;
  for(auto &v:chain){
   auto td=_track_direction_to_trackdir[FindFirstBit(v.track)][v.direction];
   std::cout<<" "<<v.x_pos<<" "<<v.y_pos<<" "<<v.tile<<" "<<int(td)<<" "<<int(v.direction);
  }
  std::cout<<"\n";
 }
}
"""
    return b


def main():
    source=Path(sys.argv[1])
    rng=random.Random(141142)
    entry=[(0,-1,8,-1),(-1,1,-1,9),(-1,2,10,-1),(3,-1,-1,11),
           (12,4,-1,-1),(-1,-1,5,13)]
    exit_=[0,1,0,1,2,1,-1,-1,2,3,3,2,3,0]
    lines=[]
    for east,south in [(0,1),(0,3),(2,1),(2,3)]:
        for curved in (False,True):
            for n in range(1,13):
                for _ in range(80):
                    d=rng.choice((east,south))
                    route=[]
                    for i in range(28):
                        eligible=[row[d] for row in entry if row[d]!=-1 and
                                  exit_[row[d]] in (east,south) and (curved or row[d]%8<2)]
                        td=rng.choice(eligible)
                        route.append(td)
                        d=exit_[td]
                    lengths=[rng.randrange(1,9) for _ in range(n)]
                    reserve=sum(lengths)+14
                    lines.append([len(route),n,rng.randrange(reserve,reserve+90),*route,*lengths])
    inp="".join(" ".join(map(str,q))+"\n" for q in lines)
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/"stock.cpp").write_text(cpp(source))
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(tmp/"stock.cpp"),"-o",str(tmp/"stock")],check=True)
        orig=subprocess.check_output([str(tmp/"stock")],input=inp,text=True,cwd=ROOT).splitlines()
        lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
        port=subprocess.check_output([lua,str(tmp/"port.lua")],input=inp,text=True,cwd=ROOT).splitlines()
    assert len(orig)==len(port)==len(lines)
    for i,(stock,ported) in enumerate(zip(orig,port)):
        if stock!=ported: raise AssertionError((i,lines[i],stock,ported))
    valid=[x.split() for x in orig if x!="skip"]
    crossings=sum(int(x[1]) for x in valid)
    assert len(valid)>5000 and crossings>250
    print(f"PASS: {len(valid)} reversals match OpenTTD 14.1; {crossings} mixed-length correction steps across tile boundaries")


if __name__=="__main__":
    main()
