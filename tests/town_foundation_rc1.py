"""Compile the original 16.0-RC1 town autoslope callback and compare the Lua port."""
import re
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from rc1_rail_foundation_shim import source_block

tree = Path(sys.argv[1])
assert subprocess.check_output(["git", "-C", tree, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
src = tree / "src"
table = (src / "table/town_land.h").read_text()
assert "BuildingFlag::NotSloped" not in table and "HouseCallbackMasks{}" in table
price = re.search(r"PriceBaseSpec\((\d+),.*?\)\s*,?\s*// Price::BuildFoundation",
                  (src / "table/pricebase.h").read_text())[1]
cpp = r"""
#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>
using TileIndex=int;
using HouseID=int;
using DoCommandFlags=int;
enum class Slope:int{};
enum class ExpensesType{Construction};
enum class BuildingFlag{NotSloped};
enum class HouseCallbackMask{Autoslope};
enum class Price{BuildFoundation};
enum class Commands{LandscapeClear};
struct CommandCost {
 int cost;
 CommandCost(ExpensesType,int n):cost(n){}
};
bool enabled,flat_only;
int prior_top;
bool AutoslopeEnabled(){return enabled;}
HouseID GetHouseType(int){return 0;}
void GetHouseNorthPart(HouseID&){}
struct HouseSpec {
 struct {bool Test(BuildingFlag)const{return flat_only;}} building_flags;
 struct {bool Test(HouseCallbackMask)const{return false;}} callback_mask;
 struct {int grffile;} grf_prop;
 static const HouseSpec *Get(HouseID){static HouseSpec h{};return &h;}
};
bool IsSteepSlope(Slope s){return int(s)>=16;}
int GetTileMaxZ(int){return prior_top;}
int GetSlopeMaxZ(Slope s){return IsSteepSlope(s)?2:int(s)?1:0;}
struct Town{static Town *GetByTile(int){return nullptr;}};
constexpr int CBID_HOUSE_AUTOSLOPE=0,CALLBACK_FAILED=0;
int GetHouseCallback(int,int,int,HouseID,Town*,int){std::abort();}
bool ConvertBooleanCallback(int,int,int){std::abort();}
struct Prices{int operator[](Price)const{return FOUNDATION_PRICE;}} _price;
template<Commands C>struct Command{
 static CommandCost Do(DoCommandFlags,int){return {ExpensesType::Construction,-1};}
};
""".replace("FOUNDATION_PRICE", price)
cpp += source_block(src, "town_cmd.cpp", r"^static CommandCost TerraformTile_Town")
cpp += r"""
int main() {
  constexpr int shapes[]{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30};
  for(int a:shapes)for(int b:shapes)for(int az=1;az<=3;++az)for(int bz=0;bz<=4;++bz)
     for(int on=0;on<2;++on)for(int ns=0;ns<2;++ns){
       enabled=on;flat_only=ns;prior_top=az+GetSlopeMaxZ(Slope(a));
       const auto q=TerraformTile_Town(0,0,bz,Slope(b));
       std::cout << a << " " << az << " " << b << " " << bz << " " << on << " " << ns << " " << q.cost << "\n";
     }
}
"""
lua=r"""
local T=dofile("mods/luanttd_core/openttd/town_foundation.lua")
local n=0
for row in io.lines() do
  local v={}
  for a in row:gmatch("%-?%d+") do v[#v+1]=tonumber(a) end
  local a,az,b,bz,on,ns,cost=unpack(v)
  assert((T.autoslope(a,az,b,bz,{autoslope=on==1},ns==1) or -1)==cost,row)
  n=n+1
end
assert(n==21660)
print(("PASS %d compiled RC1 town foundation quotes"):format(n))
"""
with TemporaryDirectory() as temp:
    cc, program, driver = (Path(temp) / f for f in ("town.cpp", "town", "town.lua"))
    cc.write_text(cpp)
    driver.write_text(lua)
    subprocess.run(["g++", "-O2", "-std=c++20", cc, "-o", program], check=True)
    cmd = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
    subprocess.run([cmd, driver], input=subprocess.check_output([program]), check=True)
