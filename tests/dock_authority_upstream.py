#!/usr/bin/env python3
"""Compile OpenTTD's exact new-station council decision and compare Lua."""
from pathlib import Path
from itertools import product
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
src = Path(sys.argv[1]) / "src"
lua = sys.argv[2] if len(sys.argv)>2 else "lua5.1"
town = (src/"town_cmd.cpp").read_text()
decl = "CommandCost CheckIfAuthorityAllowsNewStation(TileIndex tile, DoCommandFlags flags)"
function = re.search(re.escape(decl)+r"\n\{.*?\n\}",town,re.S)[0]
threshold = int(re.search(r"RATING_VERYPOOR\s*=\s*(-?\d+)",(src/"town_type.h").read_text())[1])
cpp = r'''
#include <iostream>
using TileIndex=int;
struct CommandCost {bool denied=false;};
enum class DoCommandFlag {NoTestTownRating};
struct DoCommandFlags {
  bool notest;
  bool Test(DoCommandFlag f) const {return notest&&f==DoCommandFlag::NoTestTownRating;}
};
constexpr int TOWN_COUNCIL_PERMISSIVE=3;
constexpr int STR_ERROR_LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS=51;
constexpr int RATING_VERYPOOR=THRESHOLD;
struct Company {static bool IsValidID(int v){return v==0;}};
struct Settings {struct {int town_council_tolerance;} difficulty; struct {int dist_local_authority;} economy;};
Settings _settings_game;
int _current_company, dist;
struct Town {int ratings[1]; int index;};
Town sample;
Town *ClosestTownFromTile(TileIndex,int limit){return dist>=0&&dist<limit?&sample:nullptr;}
CommandCost CommandCostWithParam(int,int){return {true};}
''' .replace("THRESHOLD",str(threshold)) + function + r'''
int main(){
 int rating,limit,tolerance,no,valid;
 while(std::cin>>rating>>dist>>limit>>tolerance>>no>>valid) {
   sample.ratings[0]=rating;
   _current_company=valid ? 0 : -1;
   _settings_game={{tolerance},{limit}};
   std::cout << !CheckIfAuthorityAllowsNewStation(0,{bool(no)}).denied << '\n';
 }
}
'''
adapter = r'''
local R=dofile("mods/luanttd_core/openttd/road_town_permission.lua")
while true do
  local rating,dist,limit,tolerance,no,valid=io.read("*n","*n","*n","*n","*n","*n")
  if rating==nil then break end
  print((valid~=1 or R.allow_new_station(rating,dist>=0 and dist or nil,limit,tolerance,no==1)) and 1 or 0)
end
'''
cases=list(product(range(threshold-5,threshold+6),(-1,0,3,19,20,21),(1,4,20),(0,1,2,3),(0,1),(0,1)))
data="\n".join(" ".join(map(str,c)) for c in cases)+"\n"
with tempfile.TemporaryDirectory() as directory:
    p=Path(directory)
    (p/"native.cpp").write_text(cpp)
    (p/"adapter.lua").write_text(adapter)
    subprocess.run(["g++","-std=c++20","-O2",str(p/"native.cpp"),"-o",str(p/"native")],check=True)
    reference=subprocess.check_output([str(p/"native")],input=data,text=True).splitlines()
    translated=subprocess.check_output([lua,str(p/"adapter.lua")],cwd=root,input=data,text=True).splitlines()
assert len(reference)==len(translated)==len(cases)
for case,a,b in zip(cases,reference,translated):
    assert a==b,(case,a,b)
print(f"PASS {len(cases):,} original C++ station council decisions")
