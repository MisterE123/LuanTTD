"""Compare existing road and terminal autoslope with compiled RC1 branches."""
import re
import subprocess as sp
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"

def src(name):
    return (source / "src" / name).read_text()

def block(text, start):
    begin = re.search(start, text, re.M).start()
    opening = text.index("{", begin)
    count = 1
    for end in range(opening + 1, len(text)):
        count += (text[end] == "{") - (text[end] == "}")
        if not count:
            return text[begin:end + 1]
    raise AssertionError(start)

road = src("road_cmd.cpp")
sl = src("slope_type.h")
sf = src("slope_func.h")
ef = src("depot_func.h")
tf = block(road, r"^static CommandCost TerraformTile_Road")
raw_slopes = sl.split("enum Slope : uint8_t {", 1)[1].split("SLOPE_HALFTILE", 1)[0]
initializers = [
    line.split("//", 1)[0].strip().removesuffix(",")
    for line in block(road, r"^static const .* _invalid_tileh_slopes_road =").splitlines()
    if "// SLOPE_" in line
]
assert len(initializers) == 30
road_seed = "{" + ",".join(initializers[:15]) + "},{" + ",".join(initializers[15:]) + "}"
normal = block(tf, r"case RoadTileType::Normal:").split("{", 1)[1].rsplit("}", 1)[0]
normal = normal[:normal.rfind("break;")]
price0 = int(re.search(r"PriceBaseSpec\((\d+),.*?\)\s*,?\s*// Price::BuildFoundation",src("table/pricebase.h"))[1])
cpp = r"""
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <iostream>
#include <type_traits>
#include <utility>
#define NOT_REACHED() std::abort()
template<typename T> constexpr auto to_underlying(T x) {return static_cast<std::underlying_type_t<T>>(x);}
enum class Corner {W,S,E,N};
constexpr bool IsValidCorner(Corner c) {return int(c)>=0&&int(c)<4;}
enum Slope : uint8_t { %SLOPES% };
enum class DiagDirection {NE,SE,SW,NW};
constexpr Slope RemoveHalftileSlope(Slope s){return static_cast<Slope>(s&31);}
enum class RoadBit {NW,SW,SE,NE};
struct RoadBits {
  unsigned b=0;
  constexpr RoadBits()=default;
  constexpr RoadBits(unsigned x):b(x){}
  constexpr RoadBits(RoadBit x):b(1u<<int(x)){}
  constexpr RoadBits(std::initializer_list<RoadBit> a){for(auto x:a)b|=1u<<int(x);}
  constexpr RoadBits operator|(RoadBits r) const {return b|r.b;}
  constexpr bool operator==(RoadBits r) const {return b==r.b;}
  constexpr bool Any(RoadBits r) const {return (b&r.b)!=0;}
  constexpr bool None() const {return b==0;}
  constexpr int Count() const {return std::popcount(b);}
  constexpr void Reset(RoadBits r){b&=~r.b;}
  constexpr void Set(RoadBits r){b|=r.b;}
};
constexpr RoadBits ROAD_X=10u,ROAD_Y=5u,ROAD_ALL=15u;
constexpr bool IsStraightRoad(RoadBits b){return b==ROAD_X||b==ROAD_Y;}
constexpr RoadBits MirrorRoadBits(RoadBits b){return ((b.b&3u)<<2)|(b.b>>2);}
constexpr RoadBits _invalid_tileh_slopes_road[2][15]={%ROAD%};
enum class Foundation {None,Leveled,InclinedX,InclinedY,SteepLower,SteepBoth};
constexpr bool IsFoundation(Foundation f){return f!=Foundation::None;}
constexpr bool IsLeveledFoundation(Foundation f){return f==Foundation::Leveled;}
bool IsNonContinuousFoundation(Foundation){return false;}
bool IsSpecialRailFoundation(Foundation){return false;}
Corner GetHalftileFoundationCorner(Foundation){std::abort();}
Corner GetRailFoundationCorner(Foundation){std::abort();}
Corner OppositeCorner(Corner){std::abort();}
Slope SlopeWithThreeCornersRaised(Corner){std::abort();}
Slope HalftileSlope(Slope,Corner){std::abort();}
enum class ExpensesType {Construction};
struct CommandCost {
  int value=0;
  CommandCost()=default;
  CommandCost(ExpensesType,int v):value(v){}
  bool Succeeded() const {return value>=0;}
};
const CommandCost CMD_ERROR(ExpensesType::Construction,-1);
namespace Price { constexpr int BuildFoundation=0; }
const int _price[]={%PRICE%};
struct {struct {bool build_on_slopes=true;} construction;} _settings_game;
""" + "\n".join(block(sf, pattern) for pattern in (
    r"^static constexpr bool IsSteepSlope", r"^inline bool IsSlopeWithOneCornerRaised",
    r"^inline Slope SlopeWithOneCornerRaised",r"^inline Corner GetHighestSlopeCorner",
    r"^static constexpr int GetSlopeMaxZ", r"^inline Slope InclinedSlope",
)) + "\n" + block(ef,r"^inline bool CanBuildDepotByTileh") + "\n" + "\n".join([
    block(road,r"^static Foundation GetRoadFoundation\(Slope tileh, RoadBits bits\)\s*\{"),
    block(road,r"^static CommandCost CheckRoadSlope"),
    block(src("landscape.cpp"),r"^uint ApplyFoundationToSlope"),
]) + r"""
using TileIndex=int;
int GetTileMaxZ(int tile){return tile;}
""" + block(src("autoslope.h"),r"^inline bool AutoslopeCheckForEntranceEdge") + r"""
CommandCost normal_(RoadBits physical_bits,Slope old,int oldz,Slope tileh_new,int z_new){
  int tile=0;
  auto GetAllRoadBits=[&](int){return physical_bits;};
  auto GetTileSlopeZ=[&](int){return std::pair{old,oldz};};
  %NORMAL%
  return CMD_ERROR;
}
int main() {
 int kind,bit,old,base,shape,new_base,on,autoslope;
 while (std::cin>>kind>>bit>>old>>base>>shape>>new_base>>on>>autoslope) {
   auto old_s=static_cast<Slope>(old), new_s=static_cast<Slope>(shape);
   _settings_game.construction.build_on_slopes=on;
   int cost=0;
   if(kind==3) {
     RoadBits pieces(static_cast<unsigned>(bit));
     auto q=CheckRoadSlope(old_s,&pieces,RoadBits{},RoadBits{});
     std::cout << (q.Succeeded()&&pieces.b==static_cast<unsigned>(bit)) << '\n';
     continue;
   }
   if(on && autoslope) {
     if(kind==0) {
       auto q=normal_(RoadBits(unsigned(bit)),old_s,base,new_s,new_base);
       if(q.Succeeded())cost=q.value;
     } else {
       int top=base+GetSlopeMaxZ(old_s);
       if(AutoslopeCheckForEntranceEdge(top,new_base,new_s,DiagDirection(bit)) &&
        (kind==1||AutoslopeCheckForEntranceEdge(top,new_base,new_s,DiagDirection((bit+2)%4))))
         cost=_price[Price::BuildFoundation];
     }
   }
   std::cout<<cost<<'\n';
 }
}
"""
cpp = cpp.replace("%SLOPES%",raw_slopes).replace("%ROAD%",road_seed).replace("%NORMAL%",normal).replace("%PRICE%",str(price0))
runner = r"""
local src="mods/luanttd_core/openttd/"
local function m(n) return dofile(src..n..".lua") end
local R=m("road_autoslope")(m("road_slope"),m("slope"),m("road_stop_build"))
for row in io.lines() do
  local b={};for n in row:gmatch("%d+") do b[#b+1]=tonumber(n) end
  local opts={build_on_slopes=b[7]==1,autoslope=b[8]==1}
  local got
  if b[1]==0 then got=R.normal(b[2],b[3],b[4],b[5],b[6],opts)
  else got=R.terminal(b[2],b[1]==2,b[3],b[4],b[5],b[6],opts) end
  print(got or 0)
end
"""
masks = [*range(15),23,27,29,30]
# Physical starting infrastructure is selected by the original command
# rather than assuming that an invalid starting road can exist.
with TemporaryDirectory() as d:
    p=Path(d)
    (p/"oracle.cpp").write_text(cpp)
    (p/"probe.lua").write_text(runner)
    sp.run(["c++","-std=c++20","-O2",p/"oracle.cpp","-o",p/"oracle"],check=True)
    all_roads=[(old,b) for old in masks for b in range(1,16)]
    old_cases="".join(f"3 {b} {old} 0 0 0 1 1\n" for old,b in all_roads)
    valid=sp.check_output([p/"oracle"],input=old_cases,text=True).splitlines()
    assert len(valid)==len(all_roads)
    roads=[pair for pair,flag in zip(all_roads,valid) if flag=="1"]
    sources=[(0,b,old) for old,b in roads]+[(mode,b,s) for mode in (1,2) for b in range(4) for s in masks]
    rows=[(m,b,s,oldz,n,newz,on,a) for m,b,s in sources for n in masks
          for oldz,newz in ((1,0),(1,1),(1,2),(1,3)) for on,a in ((1,1),(0,1),(1,0))]
    data="".join(" ".join(map(str,r))+"\n" for r in rows)
    want=sp.check_output([p/"oracle"],input=data,text=True).splitlines()
    got=sp.check_output([lua,p/"probe.lua"],input=data,text=True).splitlines()
    assert len(want)==len(got)==len(rows)
    for row,a,b in zip(rows,got,want):
        assert a==b,(row,a,b)
    print(f"PASS {len(rows)} RC1 normal road and terminal autoslope comparisons")
