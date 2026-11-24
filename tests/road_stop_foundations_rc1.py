"""Run RC1's actual CheckBuildableTile and CanBuildDepotByTileh branches."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1]).resolve()
head = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
assert head == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src = repo / "src"
def function(path, declaration):
    data = (src / path).read_text()
    body = data[data.index(declaration):]
    return body.split("\n}",1)[0] + "\n}\n"

include = r'''
#include <cstdio>
#include <cassert>
#include <cstdlib>
#include <utility>
#include <initializer_list>
enum Slope { SLOPE_FLAT=0, SLOPE_NE=12, SLOPE_SE=6, SLOPE_SW=3, SLOPE_NW=9 };
enum class DiagDirection {NE, SE, SW, NW, End};
bool IsSteepSlope(Slope s){return s&16;}
int GetSlopeMaxZ(Slope s){ return IsSteepSlope(s)?2:(s==SLOPE_FLAT?0:1); }
#define NOT_REACHED() std::abort()
std::initializer_list<DiagDirection> EnumRange(DiagDirection) {
    static const auto dirs={DiagDirection::NE,DiagDirection::SE,DiagDirection::SW,DiagDirection::NW};
    return dirs;
}
using TileIndex=int;
struct DiagDirections { int bits; bool Test(DiagDirection d) const{return (bits>>static_cast<int>(d))&1;} };
int slope,base;
bool IsBridgeAbove(TileIndex){return false;}
std::pair<Slope,int> GetTileSlopeZ(TileIndex){return {static_cast<Slope>(slope),base};}
enum class ExpensesType {Construction};
constexpr int STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST=1;
constexpr int STR_ERROR_FLAT_LAND_REQUIRED=2;
enum class Price {BuildFoundation};
int Prices(Price){return 250;}
struct {int operator[](Price p)const{return Prices(p);}} _price;
struct {struct {bool build_on_slopes;} construction;} _settings_game;
struct CommandCost {
    bool failure=false;
    int cost=0;
    CommandCost(ExpensesType){}
    CommandCost(int){failure=true;}
    bool Failed(){return failure;}
    void AddCost(int n){cost+=n;}
};
CommandCost EnsureNoVehicleOnGround(TileIndex){return CommandCost(ExpensesType::Construction);}
'''
driver = r'''
int main() {
 for(slope=0;slope<=30;slope++){
  if(slope>=15&&slope!=23&&slope!=27&&slope!=29&&slope!=30)continue;
  for(base=0;base<=3;base++)for(int dir=0;dir<4;dir++)for(int through=0;through<2;through++)
  for(int z=-1;z<=6;z++)for(int settings=0;settings<2;settings++){
   int allowed=z;
   _settings_game.construction.build_on_slopes=settings==1;
   int mask=(1<<dir) | (through==1?(1<<((dir+2)%4)):0);
   auto result=CheckBuildableTile(42,DiagDirections{mask},allowed,through==0,false);
   printf("%d %d %d %d %d %d %d %d\n",slope,base,dir,through,z,settings,result.Failed()?-1:result.cost,allowed);
  }
 }
}
'''
oracle = r'''
local R=dofile("mods/luanttd_core/openttd/road_stop_build.lua")
local seen=0
for row in io.lines(arg[1]) do
 local A={}
 for val in row:gmatch("[-%d]+") do A[#A+1]=tonumber(val) end
 local slope,base,dir,through,want,allow,price,z=unpack(A)
 local cost,level=R.foundation(slope,base,dir,through==1,want>=0 and want or nil,{build_on_slopes=allow==1})
 assert(price<0 and cost==nil and level=="FLAT_LAND_REQUIRED" or price>=0 and cost==price and level==z,row)
 seen=seen+1
end
assert(seen==9728)
print("PASS "..seen.." 16.0-RC1 road-stop foundation, facing, and equal-platform-height cases")
'''
with tempfile.TemporaryDirectory() as target:
    p = Path(target)
    (p/"test.cpp").write_text(include + function("slope_func.h","inline Slope InclinedSlope(") +
         function("depot_func.h","inline bool CanBuildDepotByTileh(") +
         function("station_cmd.cpp","CommandCost CheckBuildableTile(") + driver)
    (p/"assert.lua").write_text(oracle)
    subprocess.run(["g++","-std=c++20","-O2",p/"test.cpp","-o",p/"test"],check=True)
    with (p/"cases.txt").open("wb") as out:
        subprocess.run([p/"test"],stdout=out,check=True)
    subprocess.run([os.environ.get("LUA","lua5.1"),p/"assert.lua",p/"cases.txt"],
        cwd=Path(__file__).resolve().parents[1],check=True)
