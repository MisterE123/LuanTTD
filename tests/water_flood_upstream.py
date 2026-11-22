#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Source differential: pinned OpenTTD 14.1 ordinary clear/sea/coast flood visits.

Usage: TMPDIR=/path/to/qa_temp python3 tests/water_flood_upstream.py /path/to/OpenTTD [lua5.1]
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
water=next(p for p in (src/"src/water_cmd.cpp",src/"water_cmd.cpp") if p.is_file()).read_bytes()
assert sha256(water).hexdigest()=="f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847"
water=water.decode()


def block(pattern):
    first=re.search(pattern,water,re.M).start()
    j=water.index("{",first)
    depth=1
    while depth:
        j+=1
        depth+=(water[j]=="{")-(water[j]=="}")
    return water[first:j+1]


cpp=r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned;using TileIndex=unsigned;using Slope=int;
enum {DIR_N=0,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW,DIR_END,DIR_BEGIN=0};
using Direction=int;
enum {MP_CLEAR,MP_WATER,MP_RAILWAY,MP_TREES,MP_STATION,MP_INDUSTRY,MP_OBJECT,MP_VOID,MP_HOUSE};
enum {WATER_CLASS_SEA=0,WATER_CLASS_CANAL,WATER_CLASS_RIVER};
enum {SLOPE_FLAT=0,SLOPE_STEEP=16,SLOPE_HALFTILE_MASK=992,TREE_GROUND_SHORE=1,TREE_GROUND_GRASS=0,
      RAIL_GROUND_WATER=9,TRACK_BIT_UPPER=4,TRACK_BIT_LOWER=8,TRACK_BIT_LEFT=16,TRACK_BIT_RIGHT=32,
      RAIL_GROUND_FENCE_HORIZ1=1,RAIL_GROUND_FENCE_HORIZ2=2,RAIL_GROUND_FENCE_VERT1=3,RAIL_GROUND_FENCE_VERT2=4};
using RailGroundType=int;
enum FloodingBehaviour{FLOOD_NONE,FLOOD_ACTIVE,FLOOD_DRYUP,FLOOD_PASSIVE};
struct Row {int kind=5,slope=0,base=0,fslope=0,fbase=0,blocked=0;};
std::array<Row,4096> board;
std::vector<int> transitions;
constexpr int CENTER=64*32+32;
struct Map{static unsigned Size(){return 4096;}};
int GetTileType(int id){
  static const int types[]={MP_CLEAR,MP_WATER,MP_WATER,MP_WATER,MP_WATER,MP_HOUSE,
                            MP_VOID,MP_STATION,MP_STATION,MP_INDUSTRY,MP_OBJECT};
  return types[board.at(id).kind];
}
int GetWaterClass(int id){auto k=board.at(id).kind;return k==3?1:(k==4 || k==8)?2:0;}
bool IsTileType(int id,int t){return GetTileType(id)==t;}
bool IsValidTile(unsigned id){return id<Map::Size() && !IsTileType(id,MP_VOID);}
bool IsCoast(int id){return board.at(id).kind==2;}
Slope GetTileSlope(int id){return board.at(id).slope;}
Slope GetFoundationSlope(int id,int *base=nullptr){
  auto &r=board.at(id);
  if(base)*base=r.fbase;
  return r.fslope;
}
bool IsSlopeWithOneCornerRaised(int m){return m==1||m==2||m==4||m==8;}
int TileOffsByDir(Direction d){static const int offs[]={-65,-1,63,64,65,1,-63,-64};return offs[d];}
int ReverseDir(Direction d){return (d+4)%8;}
bool HasBit(int n,int b){return (n>>b)&1;}
std::vector<unsigned> SetBitIterator(int n){
  std::vector<unsigned> out;
  for(int i=0;i<8;i++) if (HasBit(n,i)) out.push_back(i);
  return out;
}
int GetRailGroundType(int){return 0;}
int GetTreeGround(int){return TREE_GROUND_GRASS;}
bool IsPlainRail(int){return false;}
bool FloodHalftile(int){return false;}
void FloodVehicles(int){}
void SetTreeGroundDensity(int,int,int){}
void SetRailGroundType(int,RailGroundType){}
int GetTrackBits(int){return TRACK_BIT_UPPER;}
void MarkTileDirtyByTile(int){}
void MarkCanalsAndRiversAroundDirty(int){}
void UpdateSignalsInBuffer(){}
bool IsPossibleDockingTile(int){return false;}
void CheckForDockingTile(int){}
void AmbientSoundEffect(int){}
void write_tile(int id,int k){
  int dx=(id%64)-(CENTER%64),dz=(id/64)-(CENTER/64);
  transitions.push_back((dz+1)*3+dx+1);transitions.push_back(k);
  board[id].kind=k;
}
void MakeSea(int id){write_tile(id,1);}
void MakeShore(int id){write_tile(id,2);}
constexpr int CLEAR_GRASS=0;
void MakeClear(int id,int,int){write_tile(id,0);}
using CompanyID=int;
constexpr int OWNER_WATER=12,CMD_LANDSCAPE_CLEAR=1,DC_EXEC=1,FILE_LINE=0;
int _current_company=0;
template<class T> struct Backup{Backup(T,int,int){}void Restore(){}};
struct Result{bool yes;bool Succeeded() const{return yes;}};
template<int C> struct Command{
  static Result Do(int,int t){auto &q=board[t];return {!q.blocked && (q.kind==0||q.kind==2)};}
};
#define NOT_REACHED() std::abort()
"""
for signature in (r"^static const uint8_t _flood_from_dirs",r"^FloodingBehaviour GetFloodingBehaviour",
                  r"^void DoFloodTile",r"^static void DoDryUp",r"^void TileLoop_Water"):
    cpp+=block(signature)+(";\n" if "_flood_from_dirs" in signature else "\n")
cpp+=r"""
int main(){
  while(std::cin.peek()!=EOF){
    for(int z=-1;z<=1;z++) for(int x=-1;x<=1;x++){
      auto &r=board[CENTER+z*64+x];
      if(!(std::cin>>r.kind>>r.slope>>r.base>>r.fslope>>r.fbase>>r.blocked))return 0;
    }
    transitions.clear();
    const auto mode=GetFloodingBehaviour(CENTER);
    TileLoop_Water(CENTER);
    std::cout<<mode;
    for(int n:transitions)std::cout<<' '<<n;
    std::cout<<'\n';
  }
}
"""
program=r"""
local F=dofile("mods/bayline/openttd/water_flood.lua")
local kinds={[0]="clear","sea","coast","canal","river","protected","void",
             "station","station","industry","object"}
for line in io.lines() do
  local cells={}
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  for i=0,8 do
    local n,s,b,fs,fb,protected=unpack(a,i*6+1,i*6+6)
    cells[i]={kind=kinds[n],slope=s,base=b,foundation_slope=fs,foundation_base=fb,
      blocked=protected==1,
      water_class=(n>=7 and n~=8) and "sea" or n==8 and "river" or nil}
  end
  local board={tile=function(x,z)
    if x< -1 or x>1 or z< -1 or z>1 then return end
    return cells[(z+1)*3+x+1]
  end,can_clear=function(x,z,t)return not t.blocked end}
  local output={({none=0,active=1,dryup=2})[F.behaviour(cells[4])]}
  for _,c in ipairs(F.visit(board,0,0)) do
    output[#output+1]=(c.z+1)*3+c.x+1
    output[#output+1]=({clear=0,sea=1,coast=2})[c.kind]
  end
  print(unpack(output))
end
"""
rng=random.Random(141)
rows=[]
slopes=list(range(15))+[23,27,29,30]
for _ in range(24000):
    row=[]
    for i in range(9):
        kind=rng.randrange(11) if i==4 else rng.choice([0]*10+list(range(1,11)))
        slope=rng.choice(slopes if kind in (0,2,4) else [0])
        base=rng.choice([0]*6+[1,2,4]) if kind in (0,4) else 0
        if kind==2 and slope==0: slope=1
        fslope,fbase=slope,base
        if kind==0 and rng.randrange(8)==0:
            fslope=rng.choice(slopes)+32
            fbase=rng.choice([0,0,1])
        row.extend([kind,slope,base,fslope,fbase,int(rng.randrange(7)==0)])
    rows.append(row)
data="\n".join(" ".join(map(str,a)) for a in rows)+"\n"
with tempfile.TemporaryDirectory(prefix="stock-flood-upstream-") as work:
    p=Path(work)
    (p/"ref.cpp").write_text(cpp)
    (p/"probe.lua").write_text(program)
    subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
    left=subprocess.check_output([p/"ref"],input=data,text=True).splitlines()
    right=subprocess.check_output([lua,p/"probe.lua"],input=data,text=True,cwd=root).splitlines()
    assert len(left)==len(right)==len(rows)
    for i,(a,b) in enumerate(zip(left,right)):
        assert a.split()==b.split(),(i,rows[i],a,b)
print(f"PASS {len(rows)} actual 14.1 flood/dry visits, stock direction and ordinary clear/shore transitions")
