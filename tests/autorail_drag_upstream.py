#!/usr/bin/env python3
"""Compile OpenTTD 14.1 CmdRailTrackHelper and compare ordered build results.
Usage: python3 tests/autorail_drag_upstream.py PATH_TO_OPENTTD_SRC [lua5.1]
"""
from itertools import product
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
rail = (root / "rail_cmd.cpp").read_text()
helper = rail.split("static CommandCost CmdRailTrackHelper", 1)[1].split("\n/**", 1)[0]
cpp = r'''
#include <iostream>
#include <string>
using TileIndex=unsigned;
using Trackdir=int; using Track=int; using RailType=int; using DoCommandFlag=int;
struct CommandCost {
  int error=0, cost=0;
  constexpr CommandCost(int error=0,int cost=0):error(error),cost(cost){}
  bool Failed()const{return error!=0;}
  int GetErrorMessage()const{return error;}
  void AddCost(CommandCost other){cost+=other.cost;}
};
constexpr CommandCost CMD_ERROR={3,0};
constexpr int EXPENSES_CONSTRUCTION=0, STR_ERROR_ALREADY_BUILT=1, STR_ERROR_OWNED_BY=2;
constexpr int CMD_REMOVE_SINGLE_RAIL=0,CMD_BUILD_SINGLE_RAIL=1;
struct Map {static unsigned Size(){return 256;}};
struct Point {int x,y;};
constexpr Point _trackdelta[]={{1,0}};
int TrackToTrackdir(int){return 0;}
int TrackdirToTrack(int){return 0;}
bool ValParamRailType(int){return true;}
bool ValParamTrackOrientation(int){return true;}
bool IsDiagonalTrackdir(int){return true;}
unsigned ToTileIndexDiff(Point p){return p.x;}
void ToggleBit(Trackdir&, int){}
CommandCost ValidateAutoDrag(Trackdir*,TileIndex start,TileIndex end){return start<=end?CommandCost{}:CMD_ERROR;}
static std::string cells, added, seen;
template<int which> struct Command {
  template<typename... Args> static CommandCost Do(DoCommandFlag,TileIndex tile,Args...){
    char c=cells[tile];
    seen += c;
    if(c=='A')return {STR_ERROR_ALREADY_BUILT,0};
    if(c=='O')return {STR_ERROR_OWNED_BY,0};
    if(c=='B')return {3,0};
    added+=char('0'+tile);
    return {0,120};
  }
};
static CommandCost CmdRailTrackHelper''' + helper + r'''
int main(){
  int strict=0;
  while(std::cin>>strict>>cells){
    added.clear(); seen.clear();
    auto result=CmdRailTrackHelper(0,0,cells.size()-1,0,0,false,false,strict!=0);
    std::cout<<result.error<<":"<<result.cost<<":"<<added<<":"<<seen<<"\n";
  }
}
'''
port = r'''
local drag=dofile("mods/luanttd_core/openttd/rail_drag_build.lua")
for line in io.lines() do
  local strict,cells=line:match("(%d) (%a+)")
  local map,used,seen={}, {}, {}
  for i=1,#cells do map[i]={id=i-1,case=cells:sub(i,i)} end
  local ok,err=drag(map,function(p)
    seen[#seen+1]=p.case
    if p.case=="A" then return false,1 end
    if p.case=="O" then return nil,2 end
    if p.case=="B" then return nil,3 end
    used[#used+1]=p.id
    return true
  end,strict=="1")
  print(("%d:%d:%s:%s"):format(ok and 0 or err,ok and #used*120 or 0,
    table.concat(used),table.concat(seen)))
end
'''
cases=[f"{strict} {''.join(row)}" for strict in (0,1) for n in range(1,7)
       for row in product("SAOB",repeat=n)]
data="\n".join(cases)+"\n"
with tempfile.TemporaryDirectory() as tmp:
    path=Path(tmp); (path/"source.cpp").write_text(cpp); (path/"port.lua").write_text(port)
    subprocess.run(["g++","-O2","-std=c++17",str(path/"source.cpp"),"-o",str(path/"source")],check=True)
    source=subprocess.check_output([str(path/"source")],input=data,text=True).splitlines()
    ours=subprocess.check_output([lua,str(path/"port.lua")],input=data,text=True).splitlines()
assert len(source)==len(ours)==len(cases)
for case,a,b in zip(cases,source,ours):
    assert a==b,(case,a,b)
print(f"PASS: {len(cases):,} exact pinned C++ track sweeps with built rail, ownership and obstructions.")
