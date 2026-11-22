#!/usr/bin/env python3
"""Differential exact stock farm-field draw order, clipping and fence placement."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from timber_industry_upstream import ROOT, read, function
from road_loading_upstream import extract

DIGEST = {
    "map.cpp": "386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378",
    "tilearea.cpp": "7a7071ad5c3e6a36e2abd4c10390398be914c139cf6f20ce31e5e3fe0e18484f",
    "random_func.hpp": "b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef",
}
CPP = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint=unsigned;
using byte=uint8_t;
using TileIndex=int;
using TileIndexDiff=int;
using IndustryID=int;
constexpr int INVALID_TILE=-1, MP_CLEAR=0, MP_TREES=1, MP_VOID=2, MP_OTHER=3;
constexpr int CLEAR_GRASS=0, CLEAR_SNOW=1, CLEAR_DESERT=2, CLEAR_FIELDS=3;
constexpr int TREE_GROUND_SHORE=1, LT_ARCTIC=1, LT_TROPIC=2, AXIS_Y=1;
enum DiagDirection { DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW };
struct Map {
 static uint Size() {return 4096;}
 static uint SizeX() {return 64;}
 static uint SizeY() {return 64;}
 static uint MaxX() {return 63;}
 static uint MaxY() {return 63;}
 static int WrapToMap(int i) {return i&4095;}
};
struct Settings {
 struct { int landscape=0; } game_creation;
 struct { bool freeform_edges; } construction;
} _settings_game;
uint TileX(int i) {return i%64;}
uint TileY(int i) {return i/64;}
int TileXY(int x,int y) {return y*64+x;}
int TileDiffXY(int x,int y) {return TileXY(x,y);}
int TileOffsByDiagDir(DiagDirection d) {constexpr int n[]={-1,64,1,-64};return n[d];}
int DiagDirToAxis(DiagDirection d) {return d&1;}
DiagDirection ReverseDiagDir(DiagDirection d) {return DiagDirection((d+2)%4);}
int GetTileZ(int) {return 0;}
int GetSnowLine() {return 10;}
struct TileArea {
 int tile;
 uint w,h;
 void ClampToMap() {
   w=std::min<int>(w, Map::SizeX()-TileX(tile)); h=std::min<int>(h,Map::SizeY()-TileY(tile));
 }
 struct Iterator {
   int start; uint width,offset;
   bool operator!=(const Iterator &other) const {return offset!=other.offset;}
   void operator++() {++offset;}
   int operator*() const {return start+(offset/width)*64+offset%width;}
 };
 Iterator begin() const {return {tile,w,0};}
 Iterator end() const {return {tile,w,w*h};}
};
struct Industry {TileArea location; int index=72;};
struct Ground {
 int type=MP_VOID,ground=0;
 int variant=0,owner=0,counter=0;
 std::array<int,4> fences{};
};
std::array<Ground,4096> board;
int GetTileType(int i) {return i>=0 && i<4096 ? board[i].type : MP_VOID;}
bool IsTileType(int i,int type) {return GetTileType(i)==type;}
bool IsClearGround(int i,int ground) {return board[i].ground==ground;}
int GetTreeGround(int i) {return board[i].ground;}
int GetFence(int i,DiagDirection side) {return board[i].fences[side];}
void SetFence(int i,DiagDirection side,int style) {board[i].fences[side]=style;}
void MakeField(int i,int type,int owner) {board[i]={MP_CLEAR,CLEAR_FIELDS,type,owner};}
void SetClearCounter(int i,int counter) {board[i].counter=counter;}
void MarkTileDirtyByTile(int) {}
uint32_t GB(uint32_t x,uint start,uint len) {return (x>>start)&((1u<<len)-1);}
uint32_t Next(uint32_t x) {return 1664525u*x+1013904223u;}
uint32_t rstate, draws;
uint32_t Random() {draws++;return rstate=Next(rstate);}
"""
DRIVER=r"""
int main() {
 unsigned x,z,w,h,rseed,tseed,loops,freeform;
 while(std::cin>>x>>z>>w>>h>>rseed>>tseed>>loops>>freeform) {
  _settings_game.construction.freeform_edges=freeform;
  rstate=rseed;
  draws=0;
  for(int i=0;i<4096;i++) {
    tseed=Next(tseed);
    auto k=tseed>>28;
    Ground t;
    if(TileX(i)==63||TileY(i)==63||(freeform&&(TileX(i)==0||TileY(i)==0))) t.type=MP_VOID;
    else if(TileX(i)>=(int)x&&TileX(i)<(int)(x+w)&&TileY(i)>=(int)z&&TileY(i)<(int)(z+h)) t.type=MP_OTHER;
    else if(k<=9) t.type=MP_CLEAR;
    else if(k==10) {t.type=MP_CLEAR;t.ground=CLEAR_FIELDS;t.owner=4;t.fences={1,0,2,0};}
    else if(k==11) {t.type=MP_CLEAR;t.ground=CLEAR_SNOW;}
    else if(k==12) {t.type=MP_CLEAR;t.ground=CLEAR_DESERT;}
    else if(k==13) t.type=MP_TREES;
    else if(k==14) {t.type=MP_TREES;t.ground=TREE_GROUND_SHORE;}
    else t.type=MP_OTHER;
    board[i]=t;
  }
  const Industry ind{{TileXY(x,z),w,h}};
  for(unsigned i=0;i<loops;i++) PlantRandomFarmField(&ind);
  std::cout<<draws<<'|';
  for(int i=0;i<4096;i++) {
    const auto &t=board[i];
    if(t.ground!=CLEAR_FIELDS || t.type!=MP_CLEAR) continue;
    std::cout<<i<<','<<t.owner<<','<<t.variant<<','<<t.counter;
    for(auto f:t.fences) std::cout<<','<<f;
    std::cout<<';';
  }
  std::cout<<'\n';
 }
}
"""
LUA=r"""
local root="mods/bayline/openttd/"
local C=dofile(root.."coal_industry.lua")()
local F=dofile(root.."farm_factory_fields.lua")(C)
local floor=math.floor
local function next_(n) return (1664525*n+1013904223)%4294967296 end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local x,z,w,h,rs,ts,loops,freeform=unpack(a)
  local seen={}
  local count=0
  local function rnd() count=count+1;rs=next_(rs);return rs end
  for i=0,4095 do
    local u,v=i%64,floor(i/64)
    ts=next_(ts)
    local k=floor(ts/268435456)
    local t
    if u==63 or v==63 or freeform==1 and (u==0 or v==0) then t={kind="void"}
    elseif u>=x and u<x+w and v>=z and v<z+h then t={kind="protected"}
    elseif k<=9 then t={kind="clear",ground="grass"}
    elseif k==10 then t={kind="clear",ground="field",owner=4,fences={[0]=1,[2]=2}}
    elseif k==11 then t={kind="clear",ground="snow"}
    elseif k==12 then t={kind="clear",ground="desert"}
    elseif k==13 then t={kind="trees",ground="grass"}
    elseif k==14 then t={kind="trees",ground="shore"}
    else t={kind="protected"} end
    seen[i]=t
  end
  local ind={kind="farm",x=x,z=z,width=w,height=h,id=72}
  local function key(u,v) return v*64+u end
  local board={width=64,height=64,freeform=freeform==1,tile=function(u,v) return seen[key(u,v)] end,
    make_field=function(u,v,style,owner,counter)
      seen[key(u,v)]={kind="clear",ground="field",variant=style,owner=owner,counter=counter,fences={}}
    end,
    set_fence=function(u,v,side,n) seen[key(u,v)].fences[side]=n end,
  }
  if loops==50 then F.on_built(ind,board,rnd)
  else for _=1,loops do F.random(ind,board,rnd) end end
  local out={}
  for i=0,4095 do
    local t=seen[i]
    if t.kind=="clear" and t.ground=="field" then
      local q={i,t.owner,t.variant or 0,t.counter or 0}
      for d=0,3 do q[#q+1]=t.fences[d] or 0 end
      out[#out+1]=table.concat(q,",")..";"
    end
  end
  print(count.."|"..table.concat(out))
end
"""


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    def pin(name):
        path=a.source/name
        if not path.is_file():
            path=a.source/"src"/name
        b=path.read_bytes()
        assert hashlib.sha256(b).hexdigest()==DIGEST[name],path
        return b.decode()
    industry=read(a.source,"industry_cmd.cpp")
    rand=pin("random_func.hpp")
    tilearea=pin("tilearea.cpp")
    assert "Map::SizeX() - TileX(this->tile)" in tilearea
    code=CPP+extract(rand,"inline bool Chance16I(")
    code+="\nbool Chance16(int a,int b) {return Chance16I(a,b,Random());}\n"
    code+=extract(pin("map.cpp"),"TileIndex TileAddWrap(")
    code+=re.search(r"static const byte _plantfarmfield_type\[\].*?;",industry)[0]
    for f in ("IsSuitableForFarmField","SetupFarmFieldFence","PlantFarmField"):
        code+=function(industry,f)
    code+=extract(industry,"void PlantRandomFarmField(")+DRIVER
    rng=random.Random(9)
    cases=[]
    for i in range(500):
        x,z=rng.randrange(61),rng.randrange(61)
        w,h=3,rng.randrange(3,5)
        states=[rng.randrange(2**32),rng.randrange(2**32)]
        cases.append(" ".join(map(str,(x,z,w,h,*states,rng.choice((1,2,20,50)),i%2))))
    inputs=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(code)
        (d/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        c=subprocess.check_output([str(d/"stock")],input=inputs).splitlines()
        l=subprocess.check_output([a.lua,str(d/"port.lua")],input=inputs,cwd=ROOT).splitlines()
    for case,before,after in zip(cases,c,l,strict=True):
        assert before==after,(case,before[:180],after[:180])
    print("PASS: 500 compiled stock field planting scenarios, exact draws, tile classes and all edge fences")


if __name__=="__main__":
    main()
