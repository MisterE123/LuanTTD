"""Differential for the stock slope admission/terraform branch."""
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
stock = Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert subprocess.check_output(["git", "-C", stock, "rev-parse", "HEAD"], text=True).strip() == \
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
town = (stock / "src/town_cmd.cpp").read_text()
town_shape = town.index("static bool IsRoadAllowedHere(")
start = town.index("\tif (cur_slope == SLOPE_FLAT) return ret;", town_shape)
end = town.index("\n}\n", start)
random = (stock / "src/core/random_func.hpp").read_text()
a = random.index("inline bool Chance16I(")
b = random.index("\n}", a) + 2
chance = random[a:b]
prefix = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <initializer_list>
using Slope=int;
using TileIndex=int;
using std::uint16_t;
using std::uint32_t;
constexpr Slope SLOPE_FLAT=0,SLOPE_NE=12,SLOPE_NW=9;
constexpr Slope RemoveSteepSlope(Slope s){return s&15;}
constexpr Slope RemoveHalftileSlope(Slope s){return s&31;}
constexpr Slope ComplementSlope(Slope s){return 15-s;}
enum class DiagDirection {NE,SE,SW,NW};
enum class Commands {TerraformLand};
enum class DoCommandFlag {Execute=1,Auto=2,NoWater=4};
struct CommandCost {bool fail; bool Failed() const{return fail;}};
const CommandCost CMD_ERROR{true};
CommandCost ExtractCommandCost(CommandCost cost){return cost;}
int used,called,corner_bits,up;
bool _generating_world,ok;
std::array<uint32_t,4> words;
template<Commands C> struct Command {
  static CommandCost Do(std::initializer_list<DoCommandFlag> flags,TileIndex,Slope s,bool raise){
    int bits=0; for(auto f:flags) bits|=int(f);
    assert(flags.size()==3 && bits==7); ++called; corner_bits=s&15; up=raise; return {!ok};
  }
};
"""
after = r"""
bool Chance16(uint32_t a,uint32_t b) { assert(used<4);return Chance16I(a,b,words[used++]); }
bool evaluate(Slope cur_slope,DiagDirection dir,bool ret){
  TileIndex tile=1;
"""
driver = r"""
}
int main(){
  int slope,direction,room,generating,legal;
  while(std::cin>>slope>>direction>>room>>generating>>legal>>words[0]>>words[1]>>words[2]>>words[3]){
    used=called=corner_bits=up=0;
    _generating_world=generating;ok=legal;
    bool valid=evaluate(slope,DiagDirection(direction),room);
    std::cout<<slope<<" "<<direction<<" "<<room<<" "<<generating<<" "<<legal;
    for(auto v:words) std::cout<<" "<<v;
    std::cout<<" "<<valid<<" "<<used<<" "<<called<<" "<<corner_bits<<" "<<up<<"\n";
  }
}
"""
check = r"""
local root="mods/luanttd_core/openttd/"
local G=dofile(root.."town_growth.lua")
local M=dofile(root.."town_road_grade.lua")(G.chance)
local count,calls,allowed=0,0,0
for line in io.lines() do
  local v={}
  for n in line:gmatch("%d+") do v[#v+1]=tonumber(n) end
  local used,asked,bits,up=0,0,0,0
  local got=M.allowed(v[1],v[2],v[3]==1,v[4]==1,function()
    used=used+1;assert(used<=4,line);return v[5+used]
  end,function(_,_,mask,raise)
    asked=asked+1;bits,up=mask,raise and 1 or 0;return v[5]==1
  end)
  assert((got and 1 or 0)==v[10] and used==v[11] and asked==v[12] and bits==v[13] and up==v[14],line)
  count,calls,allowed=count+1,calls+asked,allowed+(got and 1 or 0)
end
assert(count==34816 and calls>1500 and allowed>2000)
print(("PASS %d actual RC1 slope admissions (including %d matching command attempts)"):format(count,calls))
"""
vectors = [
    (0, 0, 0, 0), (0, 65535, 0, 65535), (0, 0, 65535, 0),
    (0, 0, 0, 65535), (65535, 0, 0, 0), (8191, 6553, 4095, 21845),
    (8192, 6554, 4096, 21846), (0, 0xF37F0000, 0xFFFFFFFF, 1),
]
# This branch only decides from masks, including half-tile foundation
# encodings. The fake Terraform command consumes the effective corners
# (actual CmdTerraformLand reads N/W/S/E independently).
cases = "\n".join(
    f"{s} {d} {r} {g} {q} {' '.join(map(str, v))}"
    for s in range(136) for d in range(4) for r in range(2)
    for g in range(2) for q in range(2) for v in vectors
).encode()
with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    (folder/"grade.cpp").write_text(prefix+chance+after+town[start:end]+driver)
    (folder/"compare.lua").write_text(check)
    subprocess.run(["c++", "-std=c++20", "-O2", str(folder/"grade.cpp"), "-o", str(folder/"grade")], check=True)
    reference = subprocess.check_output([folder/"grade"], input=cases)
    subprocess.run([lua, folder/"compare.lua"], input=reference, cwd=repo, check=True)
