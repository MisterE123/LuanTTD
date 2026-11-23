#!/usr/bin/env python3
"""Compare native field maintenance against pinned RC1 TileLoop_Clear."""
from argparse import ArgumentParser
from hashlib import sha256
from itertools import product
from pathlib import Path
import subprocess
import tempfile
from road_loading_upstream import extract

ROOT = Path(__file__).resolve().parents[1]
PIN = "f7371b59b0ad26b5b0c7d24f9eff7fad5b5dc8d57500fdd2599e5e0af47cd7ae"
CPP = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
enum class TileType { Clear, Other };
enum class ClearGround { Grass, Rough, Rocks, Fields, Desert };
enum class LandscapeType { Temperate, Tropic, Arctic };
enum class GameMode { Normal, Editor };
enum class DiagDirection { NE, SE, SW, NW, End };
using Dir=DiagDirection;
std::array<Dir,4> EnumRange(Dir) { return {Dir::NE,Dir::SE,Dir::SW,Dir::NW}; }
struct { struct { LandscapeType landscape=LandscapeType::Temperate; } game_creation; } _settings_game;
GameMode _game_mode;
struct IndustryID { static int Invalid() { return -1; } };
struct Tile {
  ClearGround kind=ClearGround::Grass;
  int density=3, counter=0, variant=0, owner=-1;
  std::array<int,4> fences{};
};
std::array<Tile,5> land;
int TileOffsByDiagDir(Dir d) { return 1+int(d); }
bool IsTileType(int,TileType kind) { return kind==TileType::Clear; }
bool IsClearGround(int id,ClearGround kind) { return land[id].kind==kind; }
ClearGround GetClearGround(int id) { return land[id].kind; }
int GetFence(int tile,Dir d) { return land[tile].fences[int(d)]; }
void SetFence(int tile,Dir d,int n) { land[tile].fences[int(d)]=n; }
void MarkTileDirtyByTile(int) {}
void AmbientSoundEffect(int) {}
void TileLoopClearDesert(int) {}
void TileLoopClearAlps(int) {}
bool IsSnowTile(int) { return false; }
int GetClearDensity(int i) { return land[i].density; }
void AddClearDensity(int i,int n) { land[i].density+=n; }
int GetClearCounter(int i) { return land[i].counter; }
void SetClearCounter(int i,int n) { land[i].counter=n; }
void AddClearCounter(int i,int n) { land[i].counter+=n; }
void SetClearGroundDensity(int i,ClearGround kind,int n) { land[i].kind=kind;land[i].density=n; }
void MakeClear(int i,ClearGround kind,int n) { land[i]={kind,n}; }
int GetIndustryIndexOfField(int i) { return land[i].owner; }
uint GetFieldType(int i) { return land[i].variant; }
void SetFieldType(int i,uint n) { land[i].variant=n; }
uint Random() { return 200; }
uint GB(uint v,uint a,uint n) { return (v>>a)&((1u<<n)-1); }
"""
DRIVER = r"""
int main() {
 int variant,counter,owned,editor,neighbors,fences,rounds;
 while(std::cin>>variant>>counter>>owned>>editor>>neighbors>>fences>>rounds) {
  land={};
  land[0]={ClearGround::Fields,3,counter,variant,owned?101:-1};
  _game_mode=editor?GameMode::Editor:GameMode::Normal;
  for(int i=0;i<4;i++) {
   if(neighbors&(1<<i)) land[1+i].kind=ClearGround::Fields;
   if(fences&(1<<i)) land[0].fences[i]=1+i;
  }
  for(int i=0;i<rounds;i++) TileLoop_Clear(0);
  const Tile &q=land[0];
  bool f=q.kind==ClearGround::Fields;
  std::cout<<(f?1:0)<<","<<(f?q.variant:0)<<","<<q.counter<<","<<q.density;
  for(int s:q.fences) std::cout<<","<<s;
  std::cout<<"\n";
 }
}
"""
LUA = r"""
local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.tiles={}
for i=1,64^2 do s.tiles[i]={h=2,terrain="grass",variant=1} end
s.corner_grid=T.new(64,64,function()return 2 end)
s.stock_generated_profile={width=64,depth=64}
local W=assert(Sim.mount_farm_world(s,T,true))
local x,z=8,8
local center=Sim.id(x+1,z+1)
local ids={Sim.id(x,z+1),Sim.id(x+1,z+2),Sim.id(x+2,z+1),Sim.id(x+1,z)}
local function field(variant,counter,owner)
  return {kind="clear",ground="field",variant=variant,counter=counter,industry=owner,fences={},slope=0,base=2}
end
for line in io.lines() do
  local p={};for n in line:gmatch("%d+") do p[#p+1]=tonumber(n) end
  local variant,counter,owned,editor,neighbors,fences,rounds=unpack(p)
  s.changed,s.stock_farm_grass=nil,nil
  local q=field(variant,counter,owned==1 and 101 or nil)
  s.stock_farm_fields={[center]=q}
  s.stock_farm_industries={[101]={kind="farm",id=101}}
  for i=0,3 do
    local flag=2^i
    if math.floor(neighbors/flag)%2==1 then s.stock_farm_fields[ids[i+1]]=field(0,0,101) end
    if math.floor(fences/flag)%2==1 then q.fences[i]=i+1 end
  end
  local b=W.field_board(s)
  for tick=1,rounds do b.visit(x,z,tick,editor==1) end
  q=s.stock_farm_fields[center]
  local g=s.stock_farm_grass and s.stock_farm_grass[center]
  local a={q and 1 or 0,q and q.variant or 0,q and q.counter or g or 0,g~=nil and 2 or 3}
  for i=0,3 do a[#a+1]=q and q.fences[i] or 0 end
  print(table.concat(a,","))
end
"""

def main():
    p=ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path,help="RC1 clear_cmd.cpp")
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    data=a.source.read_bytes()
    assert sha256(data).hexdigest()==PIN,"Not the pinned 16.0-RC1 source"
    src=data.decode()
    cases=list(product(range(9),range(8),range(2),range(2),range(16),(0,5,10,15),(1,8,15,24)))
    # Cover every variant/counter and edge mask, with several paired
    # fence masks and intervals, while keeping native CI-sized runtime.
    cases=[c for c in cases if (c[0]+c[1]+c[4]+c[5]+c[6])%7==0]
    inputs="".join(" ".join(map(str,c))+"\n" for c in cases).encode()
    with tempfile.TemporaryDirectory() as t:
        d=Path(t)
        (d/"clear.cpp").write_text(CPP+extract(src,"static void UpdateFences(")+extract(src,"static void TileLoop_Clear(")+DRIVER)
        (d/"clear.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"clear.cpp"),"-o",str(d/"clear")],check=True)
        reference=subprocess.check_output([str(d/"clear")],input=inputs).splitlines()
        port=subprocess.check_output([a.lua,str(d/"clear.lua")],cwd=ROOT,input=inputs).splitlines()
    for c,r,l in zip(cases,reference,port,strict=True):
        assert r==l,(c,r,l)
    print(f"PASS {len(cases)} compiled 16.0-RC1 field visits: fences, crop counters, editor, orphan expiry and grass regrowth")

if __name__=="__main__":
    main()
