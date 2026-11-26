#!/usr/bin/env python3
"""Compare the dock join lookup against compiled OpenTTD 16.0-RC1 source."""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv)>2 else "lua5.1"
root = Path(__file__).resolve().parents[1]
cmd = (source / "src/station_cmd.cpp").read_text()

def extract(name):
    m = re.search(r"template <class T, class F>\nCommandCost " + name + r"\(", cmd)
    assert m, name
    begin = cmd.index("{", m.end())
    depth = 0
    for i in range(begin, len(cmd)):
        if cmd[i] == "{":
            depth += 1
        elif cmd[i] == "}":
            depth -= 1
            if not depth:
                return cmd[m.start():i+1]
    raise AssertionError(name)

raw_offsets = re.search(r"_dock_tileoffs_chkaround\{\{\{(.*?)\}\}\}", cmd, re.S)[1]
assert [int(n) for n in re.findall(r"-?\d+", raw_offsets)] == [-1,0,0,0,0,0,0,-1]
for name, vals in (("_dock_w_chk", [2,1,2,1]), ("_dock_h_chk", [1,2,1,2])):
    assert [int(n) for n in re.findall(r"\d+", re.search(name + r"\{(.*?)\}", cmd)[1])] == vals

cpp = r'''
#include <algorithm>
#include <cassert>
#include <iostream>
#include <vector>
using TileIndex = int;
using CompanyID = int;
using StringID = int;
constexpr int STR_ERROR_ADJOINS_MORE_THAN_ONE_EXISTING = 1;
constexpr int W=32;
struct StationID {int id; constexpr static StationID Invalid(){return {-1};}
  auto operator<=>(const StationID &) const =default;
};
struct CommandCost {int error=0; bool Failed() const {return error != 0;}};
enum class TileType { Station };
int flags[W*W];
CompanyID _current_company=1;
bool IsTileType(TileIndex t,TileType){return flags[t]!=-1;}
StationID GetStationIndex(TileIndex t){return {flags[t]};}
struct TileArea {
  int x,y,w,h;
  void Expand(int p){
    int u=std::min(W,x+w+p), v=std::min(W,y+h+p);
    x=std::max(0,x-p);y=std::max(0,y-p);w=u-x;h=v-y;
  }
  struct It {TileArea *a;int i;auto operator<=>(const It &) const=default;
    void operator++(){++i;}
    int operator*(){return (a->y+i/a->w)*W+a->x+i%a->w;}
  };
  It begin(){return {this,0};} It end(){return {this,w*h};}
};
struct Station{
  int owner;
  static Station stations[4];
  static bool IsValidID(StationID id){return id.id>=0&&id.id<4;}
  static Station *Get(StationID id){return &stations[id.id];}
  static Station *GetIfValid(StationID id){return IsValidID(id)?Get(id):nullptr;}
};
Station Station::stations[4]={{1},{1},{2},{1}};
''' + "\n" + extract("GetStationAround") + "\n" + extract("FindJoiningBaseStation") + r'''
int main(){
  int x,y,d,j,a,n;
  int dx[]={-1,0,0,0},dy[]={0,0,0,-1},w[]={2,1,2,1},h[]={1,2,1,2};
  while(std::cin>>x>>y>>d>>j>>a>>n){
    std::fill(std::begin(flags),std::end(flags),-1);
    for(int i=0;i<n;i++){int t,k;std::cin>>t>>k;flags[t]=k;}
    Station *st=nullptr;
    TileArea area{x+dx[d],y+dy[d],w[d],h[d]};
    const auto r=FindJoiningBaseStation<Station>(2,{-1},{j},a,area,&st,[](const Station *){return true;});
    std::cout<<(r.error? -2 : !st ? -1 : st->owner!=_current_company ? -3 : st-Station::stations)<<'\n';
  }
}
'''
adapter = r'''
local D=dofile("mods/luanttd_core/openttd/dock_station_area.lua")
local flags={}
local stations={[0]={id=0,owner=1},{id=1,owner=1},{id=2,owner=2},{id=3,owner=1}}
local B={xy=function(t)return t%32,math.floor(t/32) end,
 id=function(x,z) if x>=0 and z>=0 and x<32 and z<32 then return z*32+x end end,
 station=function(t)return stations[t] end,station_at=function(t)return stations[flags[t]] end}
while true do
  local x,y,d,j,a,n=io.read("*n","*n","*n","*n","*n","*n")
  if not x then break end
  flags={}
  for i=1,n do local t,k=io.read("*n","*n");flags[t]=k end
  local area=D.search_area(B,y*32+x,d)
  local r,e=D.join(B,area,1,{adjacent=a==1,join=j>=0 and j or nil},32,true)
  print(r and (r.id or -1) or (e=="OWNED_BY" and -3 or e=="ADJOINS_MULTIPLE_STATIONS" and -2 or e))
end
'''
rng = random.Random(81)
cases = []
for k in range(8192):
    x, y = rng.randrange(1,31),rng.randrange(1,31)
    d,j,a = k%4,rng.randrange(-1,4),rng.randrange(2)
    cells = {}
    for _ in range(rng.randrange(13)):
        u,v = x+rng.randrange(-3,4),y+rng.randrange(-3,4)
        if 0 <= u < 32 and 0 <= v < 32:
            cells[v*32+u] = rng.randrange(4)
    cases.append((x,y,d,j,a,len(cells),*(n for item in cells.items() for n in item)))
data = "\n".join(" ".join(map(str,row)) for row in cases)+"\n"
with tempfile.TemporaryDirectory() as folder:
    p=Path(folder)
    (p/"source.cpp").write_text(cpp)
    (p/"adapter.lua").write_text(adapter)
    subprocess.run(["g++","-std=c++20","-O2",str(p/"source.cpp"),"-o",str(p/"source")],check=True)
    expected=subprocess.check_output([p/"source"],input=data,text=True).splitlines()
    observed=subprocess.check_output([lua,p/"adapter.lua"],input=data,text=True,cwd=root).splitlines()
assert len(expected)==len(observed)==len(cases)
for row,a,b in zip(cases,expected,observed):
    assert a==b,(row,a,b)
print(f"PASS {len(cases):,} original C++ dock joining and conflict decisions")
