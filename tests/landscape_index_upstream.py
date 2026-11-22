#!/usr/bin/env python3
"""Compile the stock tile loop and compare event windows and arbitrary jumps.

Usage: python3 tests/landscape_index_upstream.py OPEN_TTD_SRC [lua5.1]
"""
# SPDX-License-Identifier: GPL-2.0-only
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
path=next(p for p in (source/"src"/"landscape.cpp",source/"landscape.cpp") if p.is_file())
raw=path.read_bytes()
assert sha256(raw).hexdigest()=="0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97"
land=raw.decode()
begin=land.index("void RunTileLoop()")
end=land.index("\nvoid InitializeLandscape()",begin)
stock=land[begin:end]
table=re.search(r"static const uint32_t feedbacks\[\] = \{.*?\};",stock,re.S)[0]
step=re.search(r"^\s*tile = .*feedback\);$",stock,re.M)[0]
cpp=r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned;
constexpr uint MIN_MAP_SIZE_BITS=6,MAX_MAP_SIZE_BITS=12;
template <class T,size_t N> constexpr size_t lengthof(const T (&)[N]){return N;}
struct Map{
 static inline uint x,z;
 static uint LogX(){return x;}
 static uint LogY(){return z;}
};
struct TileIndex{
 uint32_t i;TileIndex(uint32_t j=0):i(j){}
 uint32_t base()const{return i;}
 operator uint32_t()const{return i;}
} _cur_tileloop_tile;
namespace TimerGameTick{uint64_t counter;}
constexpr int PFE_GL_LANDSCAPE=0;
struct PerformanceAccumulator{PerformanceAccumulator(int){}};
int GetTileType(TileIndex){return 0;}
uint slot;
std::vector<uint> active;
void visit(TileIndex tile){
  uint t=tile.base();
  if(std::find(active.begin(),active.end(),t)!=active.end()){
    std::cout<<" | "<<t<<','<<TimerGameTick::counter<<','<<slot
      <<','<<(t%((uint)1<<Map::x))<<','<<(t>>Map::x);
  }
  ++slot;
}
struct Procs{void(*tile_loop_proc)(TileIndex);};
const Procs only{visit};
const Procs* _tile_type_procs[]={&only};
'''
cpp+=stock+"\n"+table+"\n"
cpp+="TileIndex Step(TileIndex tile,uint32_t feedback){"+step+" return tile;}\n"
cpp+=r'''
int main(){
 char op;
 while(std::cin>>op>>Map::x>>Map::z>>_cur_tileloop_tile.i){
   const uint n=Map::x+Map::z;
   const uint32_t f=feedbacks[n-12], period=((uint32_t)1<<n)-1;
   if(op=='J'){
     int64_t offset;
     std::cin>>offset;
     uint32_t q=(offset%period+period)%period;
     TileIndex tile=_cur_tileloop_tile;
     for(uint32_t i=0;i<q;i++)tile=Step(tile,f);
     std::cout<<tile.base()<<'\n';
   }else if(op=='R'){
     TileIndex tile=1;
     uint32_t rank=0;
     while(tile.base()!=_cur_tileloop_tile.i&&rank<period){tile=Step(tile,f);rank++;}
     assert(rank<period);
     std::cout<<rank<<'\n';
   }else{
     assert(op=='W');
     uint ticks,k;
     std::cin>>TimerGameTick::counter>>ticks>>k;
     active.assign(k,0);
     for(auto& v:active)std::cin>>v;
     for(uint t=0;t<ticks;t++){
       ++TimerGameTick::counter;
       slot=0; RunTileLoop();
     }
     std::cout<<" : "<<_cur_tileloop_tile.i<<' '<<TimerGameTick::counter<<'\n';
   }
 }
}
'''
program=r'''
local I=dofile("mods/luanttd_core/openttd/landscape_index.lua")
local worlds={}
local function read(x,z)
  local key=x*16+z
  if not worlds[key] then worlds[key]=I.new(x,z) end
  return worlds[key]
end
for line in io.lines() do
  local q={}
  for token in line:gmatch("%S+") do q[#q+1]=tonumber(token) or token end
  local op,lx,lz,head=unpack(q)
  local index=read(lx,lz)
  if op=="J" then print(("%.0f"):format(index.jump(head,q[5])))
  elseif op=="R" then print(("%.0f"):format(index.index(head)))
  else
    local ids={}
    for k=1,q[7] do ids[k]=q[7+k] end
    local clock={log_x=lx,log_y=lz,head=head,counter=q[5]}
    local active=index.compile(ids)
    local events,last=index.window(clock,q[6],active)
    local out={}
    for tile,tick,slot,x,z in events do
      out[#out+1]=(" | %.0f,%.0f,%d,%d,%d"):format(tile,tick,slot,x,z)
    end
    out[#out+1]=(" : %.0f %.0f"):format(last.head,last.counter)
    print(table.concat(out))
  end
end
'''
cases=[]
for lx in range(6,13):
    for lz in range(6,13):
        p=(1<<(lx+lz))-1
        head=1+(p*713+lx*773+lz*991)%p
        ticks=6 if lx+lz<20 else 4
        counter=254+(1<<(40+((lx+lz)%5)))
        active=sorted({0,1,p,p//3,p//2,head})
        cases.append(("W",lx,lz,head,counter,ticks,len(active),*active))
for n in range(12,25):
    lx=min(12,n-6)
    lz=n-lx
    p=(1<<n)-1
    head=1+(p*943//1024)
    for offset in (0,1,-1,-p,p,2*p+1,9007199254740991,-9007199254740991,
                   -(2**52//p)*p+1, (2**52//p)*p-1):
        cases.append(("J",lx,lz,head,offset))
    for key in (1,head,p):
        cases.append(("R",lx,lz,key))
cases += [("W",7,6,6090,254,770,5,0,1,6090,8191,3451),
          ("W",7,7,6090,9007199254740734,257,4,0,1,6090,16383)]
case_bytes="".join(" ".join(map(str,c))+"\n" for c in cases).encode()
with tempfile.TemporaryDirectory(prefix="landscape-stock-index-") as folder:
    d=Path(folder)
    c,exe,l=d/"oracle.cpp",d/"oracle",d/"compare.lua"
    c.write_text(cpp);l.write_text(program)
    subprocess.run(["g++","-std=c++20","-O2",c,"-o",exe],check=True)
    def run(args):
        return subprocess.run(args,input=case_bytes,stdout=subprocess.PIPE,cwd=root,check=True).stdout.splitlines()
    a,b=run([exe]),run([lua,l])
    assert len(a)==len(b)==len(cases)
    for case,want,got in zip(cases,a,b):
        assert want==got,(case,want,got)
print(f"STOCK LANDSCAPE INDEX ORACLE PASS: {sum(c[0]=='W' for c in cases)} windows, "
      f"{sum(c[0]=='J' for c in cases)} signed jumps, {sum(c[0]=='R' for c in cases)} absolute ranks")
