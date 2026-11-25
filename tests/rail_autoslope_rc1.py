"""Compare dry and flooded rail landscaping with the unmodified OpenTTD 16.0-RC1 command."""
import re
import subprocess as sp
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from rc1_rail_foundation_shim import rail_foundation_shim, source_block

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
src = source / "src"
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
prices = (src / "table/pricebase.h").read_text()
foundation = int(re.search(r"PriceBaseSpec\((\d+),.*?\)\s*,?\s*// Price::BuildFoundation", prices)[1])
clear_water = int(re.search(r"PriceBaseSpec\((\d+),.*?\)\s*,?\s*// Price::ClearWater", prices)[1])

def block(file, pattern):
    return source_block(src, file, pattern)

cpp = rail_foundation_shim(src) + r"""
#include <utility>
enum class DoCommandFlag{Execute};
struct DoCommandFlags { bool Test(DoCommandFlag) const {return true;} };
enum class Commands{LandscapeClear};
enum class Price{BuildFoundation,ClearWater};
enum class ExpensesType{Construction};
using Money=int;
struct CommandCost{
  int value;
  CommandCost(int v):value(v){}
  CommandCost(ExpensesType,int v):value(v){}
  bool Failed() const{return value<0;}
  void AddCost(int a){value+=a;}
};
constexpr int STR_ERROR_CAN_T_BUILD_ON_WATER=-1, STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION=-1,
 STR_ERROR_MUST_REMOVE_RAILROAD_TRACK=-1, STR_ERROR_SHIP_IN_THE_WAY=-1;
std::array<int,2> prices{FOUNDATION_PRICE,WATER_PRICE};
struct Prices{
  int operator[](Price p) const{return prices[int(p)];}
} _price;
struct {struct {bool build_on_slopes;} construction;} _settings_game;
bool autoslope;
bool AutoslopeEnabled(){return autoslope;}
enum class FloodingBehaviour{None,Active,DryOut};
static FloodingBehaviour flood;
FloodingBehaviour GetFloodingBehaviour(int){return flood;}
enum class VehicleType{Ship};
struct Vehicle{VehicleType type;};
static bool ship_in_way;
template<class F> bool HasVehicleOnTile(int,F f){Vehicle v{VehicleType::Ship};return ship_in_way&&f(&v);}
template<class E> constexpr auto EnumRange(E e){assert(int(e)==4);return std::array{E(0),E(1),E(2),E(3)};}
template<Commands C> struct Command{static CommandCost Do(DoCommandFlags,int){return -1;}};
static Slope raw;
static int base;
static TrackBits bits;
static RailGroundType ground;
bool IsPlainRail(int){return true;}
RailGroundType GetRailGroundType(int){return ground;}
void SetRailGroundType(int,RailGroundType g){ground=g;}
TrackBits GetTrackBits(int){return bits;}
std::pair<Slope,int> GetTileSlopeZ(int){return {raw,base};}
int GetRailDepotDirection(int){std::abort();}
bool AutoslopeCheckForEntranceEdge(int,int,Slope,int){std::abort();}
""".replace("FOUNDATION_PRICE", str(foundation)).replace("WATER_PRICE", str(clear_water))
cpp = cpp.replace("constexpr TrackBits& Reset", "constexpr TrackBits& Set(TrackBits t){n|=t.n;return *this;}\n constexpr TrackBits& Reset")
for f,p in [
    ("slope_func.h", r"^inline Slope SteepSlope"),
    ("landscape.cpp", r"^int GetSlopeZInCorner"),
    ("rail_cmd.cpp", r"^static CommandCost CheckRailSlope"),
    ("rail_cmd.cpp", r"^static CommandCost TestAutoslopeOnRailTile"),
    ("rail_cmd.cpp", r"^static CommandCost TerraformTile_Rail"),
]:
    cpp += block(f,p)
cpp += r"""
int main(){
  constexpr int shapes[]{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30};
  base=3;
  for (int s:shapes) for (int b=1;b<64;++b) {
    bits=b;raw=Slope(s);
    if(GetRailFoundation(raw,bits)==Foundation::Invalid) continue;
    for(int i:shapes) for (int z=1;z<=5;++z) for(int a=0;a<2;++a) for(int on=0;on<2;++on){
      for(int liquid=0;liquid<=2;++liquid){
      autoslope=a;_settings_game.construction.build_on_slopes=on;
      ground=liquid?RailGroundType::HalfTileWater:RailGroundType::Grass;
      ship_in_way=liquid==2;
      flood=liquid?(IsSlopeWithOneCornerRaised(raw)?FloodingBehaviour::Active:FloodingBehaviour::DryOut):FloodingBehaviour::None;
      auto q=TerraformTile_Rail(0,{},z,Slope(i));
      std::cout<<b<<" "<<s<<" "<<i<<" "<<z<<" "<<a<<" "<<on<<" "<<liquid<<" "<<q.value<<" "<<int(ground==RailGroundType::Barren)<<"\n";
      }
    }
  }
}
"""
verify=r"""
local dir="mods/luanttd_core/openttd/"
local function m(s)return dofile(dir..s..".lua")end
local Q=m("rail_autoslope")(m("rail_track"),m("slope"))
local cases=0
for row in io.lines() do
  local vals={};for field in row:gmatch("%-?%d+") do vals[#vals+1]=tonumber(field) end
  local b,s,i,z,a,on,liquid,cost,barren=unpack(vals)
  local q=Q.quote(b,s,3,i,z,{autoslope=a==1,build_on_slopes=on==1,half_water=liquid~=0,ship_in_way=liquid==2})
  assert((q and q.price or -1)==cost and (not not (q and q.barren))==(barren==1),row)
  cases=cases+1
end
assert(cases>500000)
print(("PASS %d compiled RC1 running-rail terraform queries"):format(cases))
"""
with TemporaryDirectory() as tmp:
    cc, oracle, script = (Path(tmp) / name for name in ("rail.cpp", "rail", "rail.lua"))
    cc.write_text(cpp)
    script.write_text(verify)
    sp.run(["g++", "-std=c++20", "-O2", cc, "-o", oracle], check=True)
    sp.run([lua, script], input=sp.check_output([oracle]), check=True)
