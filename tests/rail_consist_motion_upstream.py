"""Compare ordinary OpenTTD 14.1 multi-unit positions and depot activations.

python tests/rail_consist_motion_upstream.py SOURCE_TREE [lua5.1]
Compiles stock movement, coupling, depot and connecting-track primitives.
The shim supplies front route choices and intentionally omits live signals.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_motion_upstream import cpp as motion_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST["train.h"]="35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d"

LUA = r"""
local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local PBS=dofile(root.."rail_reservation.lua")(T,F,C)
local Life=dofile(root.."rail_consist_reservation.lua")(T,F,PBS)
local M=dofile(root.."rail_motion.lua")(T)
local K=dofile(root.."rail_consist_motion.lua")(T,M,F,Life)
local width=256
local off={[0]=-1,width,1,-width}
local id=function(x,y) return x+y*width end
for line in io.lines() do
  local q={}
  for n in line:gmatch("%d+") do q[#q+1]=tonumber(n) end
  local dir,np,nt,steps=q[1],q[2],q[3],q[4]
  local lengths={}
  for i=1,np do lengths[i]=q[4+i] end
  local origin=id(120,120)
  local pieces,tiles={},{[origin]={kind="depot",dir=dir,railtype=0,owner=1}}
  local at=origin
  for i=1,nt do
    local td=q[4+np+i]
    if not tiles[at] then tiles[at]={kind="rail",railtype=0,trackbits=0,owner=1} end
    tiles[at].trackbits=T.union(tiles[at].trackbits or 0,T.trackbit(T.track(td)))
    pieces[at]=td
    at=at+off[T.exit_side(td)]
  end
  local board={tile=function(i)return tiles[i] end,adjacent=function(i,d)return i+off[d] end,
    xy=function(i)return i%width,math.floor(i/width)end,tile_at=id}
  local train=assert(K.seed_depot(board,origin,lengths))
  assert(K.release_front(train))
  for i=1,steps do
    local p,why=K.plan(board,train,function(_,next_)return pieces[next_] end)
    assert(p,why)
    local extra=0
    for _,transition in ipairs(p.transitions) do
      if transition.index>1 and p.parts[transition.index-1].tile~=transition.tile then extra=extra+1 end
    end
    assert(K.commit(train,p))
    local words={extra}
    local spacing=K.check_spacing(board,train)
    words[#words+1]=spacing and 1 or 0
    for j,v in ipairs(train.parts) do
      local a=v.pose
      local next_=train.parts[j+1]
      local check=(not v.hidden and next_ and next_.hidden) and
        K.ticks_to_leave_depot(dir,a.x,a.y,v.length,next_.length) or 999
      words[#words+1]=a.x;words[#words+1]=a.y;words[#words+1]=a.td
      words[#words+1]=a.direction;words[#words+1]=v.hidden and 1 or 0;words[#words+1]=check
    end
    print(table.concat(words," "))
  end
end
"""


def cpp(source):
    r=motion_cpp(source).split("int main(){",1)[0]
    r=r.replace("#include <cassert>", "#include <cassert>\n#include <algorithm>\n#include <cstdlib>\n#include <map>")
    r=r.replace("struct Vehicle {int x_pos,y_pos;Direction direction;TileIndex tile;};",
                """enum {VEH_TRAIN,VS_HIDDEN=1};
struct Vehicle {int x_pos,y_pos;Direction direction;TileIndex tile;int type=VEH_TRAIN,vehstatus=0;};""")
    train_h=src(source,"train.h")
    train=src(source,"train_cmd.cpp")
    rail=src(source,"rail_cmd.cpp")
    r+=r"""
using VehicleEnterTileStatus=int;
constexpr int VETSB_CONTINUE=0,VETSB_CANNOT_ENTER=1,VETSB_ENTERED_WORMHOLE=2;
constexpr int AXIS_X=0;
#define NOT_REACHED() std::abort()
struct Train : Vehicle {
 TrackBits track=TRACK_BIT_DEPOT;
 Trackdir td=TRACKDIR_X_NE;
 struct {int cached_veh_length=0;} gcache;
 Train *following=nullptr;
 Train *Next() const{return following;}
 Train *First(){return this;}
 static Train *From(Vehicle *v){return static_cast<Train*>(v);}
"""
    r+=block(train_h,r"^\s*int CalcNextVehicleOffset\(")+"};\n"
    r+=declarations(train,[r"static const byte _vehicle_initial_x_fract",r"static const byte _vehicle_initial_y_fract",
                           r"\s*static const TrackBits _connecting_track"])
    r+=declarations(rail,[r"static const byte _fractcoords_behind",r"static const byte _fractcoords_enter",
                          r"static const int8_t _deltacoord_leaveoffset"])
    r+=r"""
TileIndex depot;
DiagDirection depot_dir;
bool IsRailDepotTile(TileIndex id){return id==depot;}
DiagDirection GetRailDepotDirection(TileIndex){return depot_dir;}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((d+2)%4);}
Direction ReverseDir(Direction d){return Direction((d+4)%8);}
Direction DiagDirToDir(DiagDirection d){return Direction(d*2+1);}
int DiagDirToAxis(DiagDirection d){return d%2;}
void VehicleEnterDepot(Train*){std::abort();}
void InvalidateWindowData(int,TileIndex){}
constexpr int WC_VEHICLE_DEPOT=0;
"""
    r+=block(rail,r"^int TicksToLeaveDepot\(")
    r+=block(rail,r"^static VehicleEnterTileStatus VehicleEnter_Track\(")
    r+=r"""
int main(){
 int dir,np,nt,steps;
 constexpr int off[]={-1,WIDTH,1,-WIDTH};
 while(std::cin>>dir>>np>>nt>>steps){
  std::vector<Train> units(np);
  depot=120+WIDTH*120;
  depot_dir=DiagDirection(dir);
  for(int i=0;i<np;i++){
   auto &v=units[i];
   std::cin>>v.gcache.cached_veh_length;
   v.tile=depot;v.direction=DiagDirToDir(depot_dir);
   v.x_pos=120*16+_vehicle_initial_x_fract[dir];v.y_pos=120*16+_vehicle_initial_y_fract[dir];
   v.track=TRACK_BIT_DEPOT;
   v.vehstatus=VS_HIDDEN;
   v.td=Trackdir(dir==0?0:dir==1?1:dir==2?8:9);
   v.following=i+1<np?&units[i+1]:nullptr;
  }
  units[0].track=TrackBits(1<<(dir%2));units[0].vehstatus=0;
  std::map<int,Trackdir> course;
  for(int k=0,i=depot;k<nt;k++){
   int td;std::cin>>td;
   course[i]=Trackdir(td);
   i+=off[_trackdir_to_exitdir[td]];
  }
  for(int step=0;step<steps;step++){
   int extra=0;
   for(int i=0;i<np;i++){
    auto &v=units[i];
    auto gp=GetNewVehiclePos(&v);
    if(gp.old_tile==gp.new_tile){
     if(v.track==TRACK_BIT_DEPOT){gp.x=v.x_pos;gp.y=v.y_pos;}
     else assert(VehicleEnter_Track(&v,gp.new_tile,gp.x,gp.y)==VETSB_CONTINUE);
    }else{
     assert(v.track!=TRACK_BIT_DEPOT);
     DiagDirection enterdir=between(gp.old_tile,gp.new_tile);
     TrackBits chosen_track;
     if(i==0) chosen_track=TrackBits(1<<(course.at(gp.new_tile)%8));
     else{
      const auto &prev=units[i-1];
      if(prev.tile==gp.new_tile) chosen_track=prev.track;
      else{
       const auto exitdir=between(gp.new_tile,prev.tile);
       assert(exitdir!=INVALID_DIAGDIR);
       chosen_track=_connecting_track[enterdir][exitdir];
       extra++;
      }
     }
     const auto heading=apply_entry(gp,chosen_track,enterdir);
     v.track=chosen_track;
     v.td=_track_direction_to_trackdir[FindFirstBit(chosen_track)][heading];
     v.tile=gp.new_tile;
     v.direction=heading;
    }
    v.x_pos=gp.x;v.y_pos=gp.y;
   }
   bool spacing=true;
   for(int i=0;i+1<np;i++){
    auto &a=units[i];auto &b=units[i+1];
    if(a.track==TRACK_BIT_DEPOT)continue;
    if(b.track!=TRACK_BIT_DEPOT){
     if(std::max(std::abs(a.x_pos-b.x_pos),std::abs(a.y_pos-b.y_pos))!=a.CalcNextVehicleOffset())spacing=false;
    }else if(TicksToLeaveDepot(&a)<=0)spacing=false;
   }
   std::cout<<extra<<" "<<spacing;
   for(auto &v:units)
    std::cout<<" "<<v.x_pos<<" "<<v.y_pos<<" "<<int(v.td)<<" "<<int(v.direction)<<" "
     <<bool(v.vehstatus&VS_HIDDEN)<<" "
     <<(v.track!=TRACK_BIT_DEPOT&&v.Next()!=nullptr&&v.Next()->track==TRACK_BIT_DEPOT?TicksToLeaveDepot(&v):999);
   std::cout<<"\n";
  }
 }
}
"""
    return r


def corpus():
    rng=random.Random(14114)
    tds=[0,1,2,3,4,5,8,9,10,11,12,13]
    exits=[0,1,0,1,2,1,-1,-1,2,3,3,2,3,0]
    enter=[(0,-1,8,-1),(-1,1,-1,9),(-1,2,10,-1),(3,-1,-1,11),
           (12,4,-1,-1),(-1,-1,5,13)]
    xy=[(-1,0),(0,1),(1,0),(0,-1)]
    for i in range(750):
        d=rng.randrange(4)
        td=(0,1,8,9)[d]
        x=y=120
        visited=set()
        path=[]
        for _ in range(28):
            path.append(td)
            visited.add((x,y))
            a,b=xy[exits[td]]
            x,y=x+a,y+b
            allowed=[]
            for next_td in tds:
                if enter[next_td%8][exits[td]]!=next_td:continue
                a,b=xy[exits[next_td]]
                if (x+a,y+b) in visited:continue
                # Restrict fixture to ordinary opposite straight/45
                # consist runs, with enough straight length to bootstrap.
                if td%8 in (2,3) and next_td%8 in (4,5):continue
                if td%8 in (4,5) and next_td%8 in (2,3):continue
                allowed.append(next_td)
            if not allowed:break
            td=rng.choice(allowed)
        if len(path)<8:continue
        lens=[rng.randrange(1,9) for _ in range(rng.randrange(2,7))]
        distance=sum(16 if td%8<2 else 8 for td in path[:-1])-6
        steps=rng.randrange(max(18,distance//2),distance)
        yield " ".join(map(str,[d,len(lens),len(path),steps,*lens,*path]))


def main():
    cases=list(corpus())
    inp=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        ref=subprocess.run([p/"ref"],input=inp,capture_output=True)
        actual=subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"port.lua"],
                              cwd=ROOT,input=inp,capture_output=True)
        assert ref.returncode==0,(ref.stderr,ref.stdout.count(b"\n"))
        assert actual.returncode==0,(actual.stderr,actual.stdout.count(b"\n"))
        want,got=ref.stdout.splitlines(),actual.stdout.splitlines()
    assert len(want)==len(got)
    for i,(a,b) in enumerate(zip(want,got)):
        assert a==b,(i,a,b)
    extra=sum(int(line.split(b" ",1)[0]) for line in want)
    assert extra>50 and len(cases)>400
    print(f"PASS: {len(want):,} stock consist movement rows from {len(cases):,} seeded routes; "
          f"{extra:,} predecessor-one-tile-ahead decisions")


if __name__=="__main__":
    main()
