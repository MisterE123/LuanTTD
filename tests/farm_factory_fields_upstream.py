#!/usr/bin/env python3
"""Compare farm planting with compiled OpenTTD 16.0-RC1 field functions."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from timber_industry_upstream import ROOT, function
from road_loading_upstream import extract

# All four inputs come from https://github.com/OpenTTD/OpenTTD/tree/16.0-RC1/src.
DIGEST = {
    "industry_cmd.cpp": "1e6bc18f0c26e56f2c50bad4c9e1039174ad2da7b404750ce688dcea2b10c752",
    "map.cpp": "1562ab2110a9611bcaaf20df6b771433c962fa5b3c75b9704263c021abe946ea",
    "tilearea_orthogonal.cpp": "100b3050f39ed3ebe78fee46896de3f783e3c49180cae4e6123585ba71f6055c",
    "random_func.hpp": "6015c6cc0c91db94ef8f44e99bb4fa48a1b1211b0f44d56b979af578199a90a7",
}
CPP = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <tuple>
#include <vector>
using uint=unsigned;
using byte=uint8_t;
using TileIndex=int;
using TileIndexDiff=int;
using IndustryID=int;
constexpr int INVALID_TILE=-1;
enum class TileType { Void, Clear, Trees, Water, Occupied };
enum class ClearGround { Grass, Rocks, Rough, Desert, Fields };
enum class TreeGround { Grass, Shore, Rough, Snow };
enum class LandscapeType { Temperate, Arctic, Tropic, Toyland };
enum class DiagDirection { NE, SE, SW, NW };
struct Map {
 static inline uint width=64, height=64;
 static uint Size() {return width*height;}
 static uint SizeX() {return width;}
 static uint SizeY() {return height;}
 static uint MaxX() {return width-1;}
 static uint MaxY() {return height-1;}
 static int WrapToMap(int i) {return i&(Size()-1);}
};
struct Settings {
 struct { LandscapeType landscape=LandscapeType::Temperate; } game_creation;
 struct { bool freeform_edges; } construction;
} _settings_game;
uint TileX(int i) {return i%Map::SizeX();}
uint TileY(int i) {return i/Map::SizeX();}
int TileXY(int x,int y) {return y*int(Map::SizeX())+x;}
int TileDiffXY(int x,int y) {return TileXY(x,y);}
int TileOffsByDiagDir(DiagDirection d) {const int w=Map::SizeX(), n[]={-1,w,1,-w};return n[int(d)];}
int DiagDirToAxis(DiagDirection d) {return int(d)&1;}
int OtherAxis(int a) {return 1-a;}
int TileOffsByAxis(int a) {return a==0 ? 1 : Map::SizeX();}
DiagDirection ReverseDiagDir(DiagDirection d) {return DiagDirection((int(d)+2)%4);}
int GetTileZ(int tile) {return (TileX(tile)+3*TileY(tile))%16;}
int snowline;
int GetSnowLine() {return snowline;}
struct OrthogonalTileArea {
 int tile;
 uint w,h;
 void ClampToMap();
 struct Iterator {
   int start; uint width,offset;
   bool operator!=(const Iterator &other) const {return offset!=other.offset;}
   void operator++() {++offset;}
   int operator*() const {return start+(offset/width)*Map::SizeX()+offset%width;}
 };
 Iterator begin() const {return {tile,w,0};}
 Iterator end() const {return {tile,w,w*h};}
};
using TileArea=OrthogonalTileArea;
struct Industry {OrthogonalTileArea location; int index=72;};
struct Ground {
 TileType type=TileType::Void;
 ClearGround clear=ClearGround::Grass;
 TreeGround tree=TreeGround::Grass;
 bool snow=false;
 int variant=0,owner=0,counter=0;
 std::array<int,4> fences{};
};
std::vector<Ground> board;
std::vector<std::tuple<int,int,int>> writes;
TileType GetTileType(int i) {assert(i>=0 && i<int(Map::Size())); return board[i].type;}
bool IsTileType(int i, TileType type) {return GetTileType(i)==type;}
ClearGround GetClearGround(int i) {return board[i].clear;}
bool IsClearGround(int i,ClearGround g) {return GetClearGround(i)==g;}
TreeGround GetTreeGround(int i) {return board[i].tree;}
bool IsSnowTile(int i) {return board[i].snow;}
int GetFence(int i,DiagDirection side) {return board[i].fences[int(side)];}
void SetFence(int i,DiagDirection side,int style) {
 board[i].fences[int(side)]=style;writes.emplace_back(i,int(side),style);
}
void MakeField(int i,int type,int owner) {
 board[i]={TileType::Clear,ClearGround::Fields,TreeGround::Grass,false,type,owner};
}
void SetClearCounter(int i,int counter) {board[i].counter=counter;}
void MarkTileDirtyByTile(int i) {writes.emplace_back(i,4,board[i].counter);}
uint32_t GB(uint32_t x,uint start,uint len) {return (x>>start)&((1u<<len)-1);}
uint32_t Next(uint32_t x) {return 1664525u*x+1013904223u;}
uint32_t rstate, draws;
uint32_t Random() {draws++;return rstate=Next(rstate);}
"""
DRIVER=r"""
int main() {
 unsigned x,z,w,h,rseed,tseed,loops,freeform,climate,shape,mix;
 while(std::cin>>x>>z>>w>>h>>rseed>>tseed>>loops>>freeform>>climate>>snowline>>shape>>mix) {
  Map::width=shape==1 ? 128 : 64;
  Map::height=shape==2 ? 128 : 64;
  _settings_game.construction.freeform_edges=freeform;
  _settings_game.game_creation.landscape=LandscapeType(climate);
  rstate=rseed;
  draws=0;
  writes.clear();
  board.resize(Map::Size());
  for(int i=0;i<int(Map::Size());i++) {
    tseed=Next(tseed);
    auto k=tseed>>27;
    Ground t;
    const auto u=TileX(i), v=TileY(i);
    if(u==Map::MaxX()||v==Map::MaxY()||(freeform&&(u==0||v==0))) t.type=TileType::Void;
    else if((!freeform&&v==0) || (u>=x&&u<x+w&&v>=z&&v<z+h)) t.type=TileType::Occupied;
    else if(k<=8 || (mix==1 && k<=15)) t.type=TileType::Clear;
    else if(k<=13) {t.type=TileType::Clear;t.clear=ClearGround::Rough;}
    else if(k<=15) {t.type=TileType::Trees;t.tree=TreeGround::Rough;}
    else if(k<=17) t.type=TileType::Trees;
    else if(k==18) {t.type=TileType::Trees;t.tree=TreeGround::Shore;}
    else if(k==19) {t.type=TileType::Trees;t.tree=TreeGround::Snow;}
    else if(k==20) {t.type=TileType::Clear;t.clear=ClearGround::Rocks;}
    else if(k<=23) {t.type=TileType::Clear;t.clear=ClearGround::Fields;t.owner=4;t.fences={1,0,2,0};}
    else if(k==24) {t.type=TileType::Clear;t.clear=ClearGround::Desert;}
    else if(k<=26) {t.type=TileType::Clear;t.clear=ClearGround::Rocks;t.snow=true;}
    else if(k<=29) t.type=TileType::Water;
    else t.type=TileType::Occupied;
    board[i]=t;
  }
  const Industry ind{{TileXY(x,z),w,h}};
  for(unsigned i=0;i<loops;i++) PlantRandomFarmField(&ind);
  std::cout<<draws<<','<<rstate<<'|';
  for (auto [i, side, kind] : writes) std::cout<<i<<','<<side<<','<<kind<<';';
  std::cout<<'|';
  for(int i=0;i<int(Map::Size());i++) {
    const auto &t=board[i];
    if(t.clear!=ClearGround::Fields || t.type!=TileType::Clear) continue;
    std::cout<<i<<','<<t.owner<<','<<t.variant<<','<<t.counter;
    for(auto f:t.fences) std::cout<<','<<f;
    std::cout<<';';
  }
  std::cout<<'\n';
 }
}
"""
LUA=r"""
local root="mods/luanttd_core/openttd/"
local C=dofile(root.."coal_industry.lua")()
local F=dofile(arg[1] or root.."farm_factory_fields.lua")(C)
local floor=math.floor
local function next_(n) return (1664525*n+1013904223)%4294967296 end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local x,z,w,h,rs,ts,loops,freeform,climate,snowline,shape,mix=unpack(a)
  local wid,hei=shape==1 and 128 or 64,shape==2 and 128 or 64
  local seen,writes={},{}
  local count=0
  local function rnd() count=count+1;rs=next_(rs);return rs end
  for i=0,wid*hei-1 do
    local u,v=i%wid,floor(i/wid)
    ts=next_(ts)
    local k=floor(ts/134217728)
    local t
    if u==wid-1 or v==hei-1 or freeform==1 and (u==0 or v==0) then t={kind="void"}
    elseif freeform==0 and v==0 or u>=x and u<x+w and v>=z and v<z+h then t={kind="protected"}
    elseif k<=8 or mix==1 and k<=15 then t={kind="clear",ground="grass"}
    elseif k<=13 then t={kind="clear",ground="rough"}
    elseif k<=15 then t={kind="trees",ground="rough"}
    elseif k<=17 then t={kind="trees",ground="grass"}
    elseif k==18 then t={kind="trees",ground="shore"}
    elseif k==19 then t={kind="trees",ground="snow"}
    elseif k==20 then t={kind="clear",ground="rocks"}
    elseif k<=23 then t={kind="clear",ground="field",owner=4,fences={[0]=1,[2]=2}}
    elseif k==24 then t={kind="clear",ground="desert"}
    elseif k<=26 then t={kind="clear",ground="rocks",snow=true}
    elseif k<=29 then t={kind="water"}
    else t={kind="protected"} end
    seen[i]=t
  end
  local ind={kind=climate==2 and "maize_farm" or "farm",x=x,z=z,width=w,height=h,id=72}
  local function key(u,v) return v*wid+u end
  local board={width=wid,height=hei,freeform=freeform==1,tile=function(u,v) return seen[key(u,v)] end,
    climate=({"temperate","arctic","tropic","toyland"})[climate+1],snowline=snowline,
    height_at=function(u,v) return (u+3*v)%16 end,
    make_field=function(u,v,style,owner,counter)
      local i=key(u,v)
      writes[#writes+1]=i..",4,"..counter..";"
      seen[i]={kind="clear",ground="field",variant=style,owner=owner,counter=counter,fences={}}
    end,
    set_fence=function(u,v,side,n)
      local i=key(u,v)
      writes[#writes+1]=i..","..side..","..n..";"
      seen[i].fences[side]=n
    end,
  }
  if loops==50 then F.on_built(ind,board,rnd)
  else for _=1,loops do F.random(ind,board,rnd) end end
  local out={}
  for i=0,wid*hei-1 do
    local t=seen[i]
    if t.kind=="clear" and t.ground=="field" then
      local q={i,t.owner,t.variant or 0,t.counter or 0}
      for d=0,3 do q[#q+1]=t.fences[d] or 0 end
      out[#out+1]=table.concat(q,",")..";"
    end
  end
  print(("%.0f,%.0f|%s|%s"):format(count,rs,table.concat(writes),table.concat(out)))
end
"""


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    p.add_argument("--kernel",type=Path, help="Override the Lua kernel, for regression comparisons")
    a=p.parse_args()
    def pin(name):
        for prefix in (Path(), Path("src"), Path("src/core")):
            path=a.source/prefix/name
            if path.is_file():
                b=path.read_bytes()
                assert hashlib.sha256(b).hexdigest()==DIGEST[name],path
                return b.decode()
        raise FileNotFoundError(name)
    industry=pin("industry_cmd.cpp")
    code=CPP+extract(pin("random_func.hpp"),"inline bool Chance16I(")
    code+="\nbool Chance16(int a,int b) {return Chance16I(a,b,Random());}\n"
    code+=extract(pin("map.cpp"),"TileIndex TileAddWrap(")
    code+=extract(pin("tilearea_orthogonal.cpp"),"void OrthogonalTileArea::ClampToMap(")
    code+=re.search(r"static const uint8_t _plantfarmfield_type\[\].*?;",industry)[0]
    for f in ("IsSuitableForFarmField","SetupFarmFieldFence","PlantFarmField"):
        code+=function(industry,f)
    code+=extract(industry,"void PlantRandomFarmField(")+DRIVER
    rng=random.Random(9)
    cases=[]
    for i in range(600):
        shape=i%3
        mw,mh=128 if shape==1 else 64,128 if shape==2 else 64
        w,h=3,rng.randrange(3,5)
        if i%5==0:  # each edge and corners: rejected targets and clipped fields
            x,z=rng.choice((1,2,mw-w-1)),rng.choice((1,2,mh-h-1))
        else:
            x,z=rng.randrange(1,mw-w),rng.randrange(1,mh-h)
        states=[rng.randrange(2**32),rng.randrange(2**32)]
        cases.append(" ".join(map(str,(x,z,w,h,*states,rng.choice((1,2,20,50)),(i//3)%2,
                                        (i//6)%4,rng.choice((8,10,12,18)),shape,(i//24)%2))))
    inputs=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(code)
        (d/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        c=subprocess.check_output([str(d/"stock")],input=inputs).splitlines()
        args=[a.lua,str(d/"port.lua")]
        if a.kernel: args.append(str(a.kernel.resolve()))
        l=subprocess.check_output(args,input=inputs,cwd=ROOT).splitlines()
    for case,before,after in zip(cases,c,l,strict=True):
        assert before==after,(case,before[:180],after[:180])
    assert len(cases)==len(c)==len(l)
    print(f"PASS: {len(cases)} pinned 16.0-RC1 scenarios; exact RNG, ordered field/fence writes and final board")


if __name__=="__main__":
    main()
