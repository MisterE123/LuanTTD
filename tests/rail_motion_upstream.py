"""Compare stock rail position samples to OpenTTD 14.1.

python tests/rail_motion_upstream.py SOURCE_TREE [lua5.1]
Compiles unchanged GetNewVehiclePos and the stock train entry table/commit.
Supplies a tile grid and the track chooser in place of the full game.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "vehicle.cpp":"1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
    "train_cmd.cpp":"206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
})

LUA = r"""
local T=dofile("mods/bayline/openttd/rail_track.lua")
local M=dofile("mods/bayline/openttd/rail_motion.lua")(T)
local function print_pose(tag,p)
  print(table.concat({tag,p.tx,p.ty,p.x,p.y,p.direction,p.td,p.enterdir or -1}," "))
end
for line in io.lines() do
  local n={}
  for q in line:gmatch("%-?%d+") do n[#n+1]=tonumber(q) end
  local tx,ty,track,side=n[1],n[2],n[3],n[4]
  local pose=M.entry(tx,ty,track,side)
  if not pose then print("invalid-entry")
  else
    local p2=M.entry_trackdir(tx,ty,pose.td)
    assert(pose.x==p2.x and pose.y==p2.y and pose.direction==p2.direction)
    pose.enterdir=side
    print_pose("entry",pose)
    local idx=5
    while true do
      local tag,p=M.step(pose,n[idx] and n[idx]>=0 and n[idx] or nil)
      if tag=="invalid" then
        assert(p.crossing)
        print_pose(tag,p)
        break
      end
      if tag=="boundary" then
        assert(p.crossing)
        print_pose(tag,p)
        break
      end
      if tag=="enter" then
        assert(pose.tx~=p.tx or pose.ty~=p.ty)
        idx=idx+1
      else
        assert(p.direction==pose.direction and p.tx==pose.tx and p.ty==pose.ty)
      end
      local x,z,h=M.world_pose(p)
      assert(x+.5==p.x/8 and z+.5==p.y/8 and math.abs(h-(p.direction-3)*math.pi/4)<1e-12)
      print_pose(tag,p)
      pose=p
    end
  end
end
local p={x=16,y=16,tx=1,ty=1,direction=0,td=12}
local tag,next_=M.step(p)
assert(tag=="invalid" and next_.crossing and next_.enterdir==nil,"corner skipped an adjacent tile")
local tx,ty=11,31
for t=0,5 do
  for s=0,3 do
    local r=M.entry(tx,ty,t,s)
    if r then
      local steps=1
      local tag,p=M.step(r)
      while tag=="move" do steps=steps+1;tag,p=M.step(p) end
      assert(tag=="boundary" and p.enterdir==T.exit_side(r.td))
      assert(steps==(t<2 and 16 or 8),"straight/corner did not have stock pixel count")
    end
  end
end
"""


def cpp(source):
    track=src(source,"track_type.h")
    direction=src(source,"direction_type.h")
    rail=src(source,"rail.cpp")
    r=r"""
#include <cassert>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
using byte=uint8_t;
using uint=unsigned;
"""
    r+=declarations(direction,[r"enum Direction\s*:",r"enum DiagDirection\s*:"])
    r+=declarations(track,[r"enum Track\s*:",r"enum TrackBits",r"enum Trackdir\s*:",r"enum TrackdirBits"])
    r+=declarations(rail,[r"extern const .* "+n for n in (
        "_track_enterdir_to_trackdir","_track_direction_to_trackdir","_trackdir_to_exitdir")])
    train=src(source,"train_cmd.cpp")
    r+=declarations(train,[r"static const byte _initial_tile_subcoord"])
    # Ensure the action-bearing fragment is from TrainController, not an
    # independently mirrored approximation of its snap operation.
    a=train.index("const byte *b = _initial_tile_subcoord[")
    b=train.index("/* Call the landscape function",a)
    commit=train[a:b]
    r+=r"""
using TileIndex=int;
constexpr int WIDTH=256;
TileIndex TileVirtXY(int x,int y){return (x>>4)+WIDTH*(y>>4);}
struct Vehicle {int x_pos,y_pos;Direction direction;TileIndex tile;};
struct GetNewVehiclePosResult {int x,y;TileIndex old_tile,new_tile;};
"""
    r+=block(src(source,"vehicle.cpp"),r"^GetNewVehiclePosResult GetNewVehiclePos\(")
    r+=r"""
int FindFirstBit(TrackBits t){assert(t);return __builtin_ctz(unsigned(t));}
Direction apply_entry(GetNewVehiclePosResult &gp,TrackBits chosen_track,DiagDirection enterdir) {
"""
    r+=commit+"return chosen_dir;\n}\n"
    r+=r"""
DiagDirection between(TileIndex old,TileIndex next) {
 int dx=(next%WIDTH)-(old%WIDTH),dy=(next/WIDTH)-(old/WIDTH);
 if(dx==-1&&dy==0)return DIAGDIR_NE;
 if(dx==0&&dy==1)return DIAGDIR_SE;
 if(dx==1&&dy==0)return DIAGDIR_SW;
 if(dx==0&&dy==-1)return DIAGDIR_NW;
 return INVALID_DIAGDIR;
}
void output(const char *tag,TileIndex tile,int x,int y,Direction dir,Trackdir td,int side){
 std::cout<<tag<<" "<<tile%WIDTH<<" "<<tile/WIDTH<<" "<<x<<" "<<y<<" "
    <<int(dir)<<" "<<int(td)<<" "<<side<<"\n";
}
int main(){
 std::string line;
 while(std::getline(std::cin,line)){
  std::stringstream in(line);
  int tx,ty,track,side;
  in>>tx>>ty>>track>>side;
  std::vector<int> route;
  int q;
  while(in>>q)route.push_back(q);
  Trackdir td=_track_enterdir_to_trackdir[track][side];
  if(td==INVALID_TRACKDIR){std::cout<<"invalid-entry\n";continue;}
  TileIndex tile=tx+WIDTH*ty;
  GetNewVehiclePosResult first{tx*16,ty*16,tile,tile};
  Direction dir=apply_entry(first,TrackBits(1<<track),DiagDirection(side));
  assert(_track_direction_to_trackdir[track][dir]==td);
  Vehicle v{first.x,first.y,dir,tile};
  output("entry",tile,v.x_pos,v.y_pos,v.direction,td,side);
  size_t idx=0;
  while(true){
   auto gp=GetNewVehiclePos(&v);
   if(gp.old_tile==gp.new_tile){
    output("move",gp.new_tile,gp.x,gp.y,v.direction,td,-1);
   }else{
    auto enterdir=between(gp.old_tile,gp.new_tile);
    if(enterdir==INVALID_DIAGDIR){output("invalid",gp.new_tile,gp.x,gp.y,v.direction,td,-1);break;}
    if(idx==route.size()||route[idx]<0){output("boundary",gp.new_tile,gp.x,gp.y,v.direction,td,enterdir);break;}
    int next=route[idx++];
    int nt=next%8;
    if(nt>=6||_track_enterdir_to_trackdir[nt][enterdir]!=next){
     output("invalid",gp.new_tile,gp.x,gp.y,v.direction,td,enterdir);break;
    }
    v.direction=apply_entry(gp,TrackBits(1<<nt),enterdir);
    td=_track_direction_to_trackdir[nt][v.direction];
    output("enter",gp.new_tile,gp.x,gp.y,v.direction,td,enterdir);
   }
   v.x_pos=gp.x;v.y_pos=gp.y;v.tile=gp.new_tile;
  }
 }
}
"""
    return r


def main():
    # Every track/side pair and every physically possible continuation,
    # plus all invalid choices. Additional seeded longer runs follow the
    # original entry/exit table over multiple contiguous boundaries.
    source=Path(sys.argv[1])
    rng=random.Random(1416)
    lines=[]
    for track in range(6):
        for side in range(4):
            for next_td in [-1,*range(16)]:
                lines.append([8+track,10+side,track,side,next_td])
    # This table supplies maps, not expected positions. The oracle checks
    # every emitted row against the C++ source rather than these values.
    entry=[(0,-1,8,-1),(-1,1,-1,9),(-1,2,10,-1),(3,-1,-1,11),
           (12,4,-1,-1),(-1,-1,5,13)]
    exit_=[0,1,0,1,2,1,-1,-1,2,3,3,2,3,0]
    for _ in range(1400):
        track=rng.randrange(6)
        side=rng.choice([d for d,td in enumerate(entry[track]) if td>=0])
        row=[120,120,track,side]
        td=entry[track][side]
        for _ in range(rng.randrange(2,47)):
            side=exit_[td]
            td=rng.choice([e[side] for e in entry if e[side]>=0])
            row.append(td)
        lines.append(row)
    inp=("\n".join(" ".join(map(str,line)) for line in lines)+"\n").encode()
    with tempfile.TemporaryDirectory() as temp:
        t=Path(temp)
        (t/"ref.cpp").write_text(cpp(source))
        (t/"compare.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",t/"ref.cpp","-o",t/"ref"],check=True)
        expected=subprocess.check_output([t/"ref"],input=inp)
        actual=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",t/"compare.lua"],
                                       cwd=ROOT,input=inp)
    if expected!=actual:
        for i,(want,got) in enumerate(zip(expected.splitlines(),actual.splitlines())):
            assert want==got,(i,want,got)
        raise AssertionError("Trace lengths differ")
    print(f"PASS: {expected.count(bytes([10])):,} position/entry rows from {len(lines):,} stock rail routes")


if __name__=="__main__":
    main()
