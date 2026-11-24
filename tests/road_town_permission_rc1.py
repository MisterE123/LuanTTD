"""Differential against the original town-owned branch of CheckAllowRemoveRoad."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1]).resolve()
head = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
assert head == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src = repo / "src"
constants = (src / "town_type.h").read_text()
constants = "\n".join(re.findall(r"^static constexpr int RATING_(?:MINIMUM|ROAD_[A-Z_]+)\s*=\s*[^;]+;", constants, re.M))
assert len(constants.splitlines()) == 8
roads = (src / "road_cmd.cpp").read_text()
logic = roads.split("CommandCost CheckAllowRemoveRoad(",1)[1].split("/* Get a bitmask",1)[1]
logic = "/* Get a bitmask" + logic[:logic.index("\n}")]
town = (src / "town_cmd.cpp").read_text()
check = town.split("CommandCost CheckforTownRating(",1)[1]
check = check.split("static const int needed_rating",1)[1].split("if (GetRating(t) < needed)",1)[0]
minima = re.findall(r"\{\s*(RATING_ROAD_NEEDED_[A-Z]+),", check)
assert len(minima) == 4
rating_body = town.split("int rating = GetRating(t);",1)[1].split("if (_town_rating_test)",1)[0]
stub = r'''
#include <array>
#include <bit>
#include <cstdint>
#include <cstdio>
#include <initializer_list>
struct RoadBits {
  unsigned b=0;
  RoadBits()=default;
  explicit RoadBits(unsigned x):b{x}{}
  unsigned Count()const{return std::popcount(b);}
  bool Any(RoadBits a)const{return (a.b&b)!=0;}
  template <typename T> bool Test(T d)const{return (b&(1U<<static_cast<unsigned>(d)))!=0;}
  template <typename T> void Set(T d){b|=1U<<static_cast<unsigned>(d);}
};
enum class RoadBit {NW,SW,SE,NE};
constexpr int STR_ERROR_LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS=1;
struct Town {int index{};};
struct CommandCost {int error=0;};
CommandCost CommandCostWithParam(int, int){return {1};}
struct {struct {bool extra_dynamite;} construction;} _settings_game;
unsigned present_mask, neighbor_mask;
int TileAddXY(int,int dx,int dz){return dz<0?1:dx>0?2:dz>0?3:4;}
RoadBits GetAnyRoadBits(int tile,int) {
 if(tile==0) return RoadBits(present_mask);
 return RoadBits((neighbor_mask&(1U<<(tile-1)))!=0?(1U<<((tile+1)%4)):0);
}
int rd;
int GetRating(Town*){return rd;}
'''
main = r'''
int main() {
 const int values[]{500,212,112,64,63,16,15,-70,-120,-1000};
 for(int tol=0;tol<4;tol++)for(int r:values)for(int extra=0;extra<2;extra++)
 for(present_mask=1;present_mask<16;present_mask++)
 for(neighbor_mask=0;neighbor_mask<16;neighbor_mask++)
 for(unsigned remove=1;remove<16;remove++){
  rd=r; _settings_game.construction.extra_dynamite=extra!=0;
  int allowed=!Check(0,RoadBits(remove),tol).error;
  printf("%d,%d,%d,%u,%u,%u,%d,%d\n",tol,r,extra,present_mask,neighbor_mask,remove,allowed,rd);
 }
}
'''
cpp = stub + constants + "\nvoid ChangeTownRating(Town *t,int add,int max,int){int rating=GetRating(t);" + rating_body + "\nrd=rating;}\n"
cpp += "CommandCost Check(int tile,RoadBits remove,int tol){\n Town T; Town *t=&T; int flags=0,rtt=0;\n"
cpp += "const int needed[]={" + ",".join(minima) + "};\n if(GetRating(t)<needed[tol])return {1};\n" + logic + "\n}\n" + main
lua = r'''
local r=dofile('mods/luanttd_core/openttd/road_town_permission.lua')
local n=0
for line in io.lines(arg[1]) do
  local values={}
  for value in line:gmatch('[-%d]+') do values[#values+1]=tonumber(value) end
  local t,rate,extra,present,connections,remove,allowed,next=unpack(values)
  local neighbors={}
  for i,b in ipairs{4,8,1,2} do neighbors[i]=math.floor(connections/2^(i-1))%2*b end
  local got,err=r.check(rate,t,extra==1,present,remove,neighbors)
  assert(allowed==1 and got==next or allowed==0 and got==nil and err=='TOWN_REFUSES',line)
  n=n+1
end
assert(n==288000)
print('PASS '..n..' RC1 town street permission and rating cases against compiled original source')
'''
with tempfile.TemporaryDirectory() as td:
    out = Path(td)
    (out / "cfg.cpp").write_text(cpp)
    (out / "test.lua").write_text(lua)
    subprocess.run(["g++", "-std=c++20", "-O2", out / "cfg.cpp", "-o", out / "cfg"], check=True)
    with (out / "data.csv").open("wb") as dest:
        subprocess.run([out / "cfg"], stdout=dest, check=True)
    subprocess.run([os.environ.get("LUA","lua5.1"),out / "test.lua",out / "data.csv"],
                   cwd=Path(__file__).resolve().parents[1], check=True)
