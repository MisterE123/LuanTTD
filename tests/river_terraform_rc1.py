#!/usr/bin/env python3
"""Compare Lua to the literal OpenTTD 16.0-RC1 TerraformTile_Water guard."""
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert subprocess.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
raw = (source / "src/water_cmd.cpp").read_text()
i = raw.index("static CommandCost TerraformTile_Water(")
body = raw[i:raw.index("\n}", i) + 2]
shim = r"""
#include <iostream>
using TileIndex=int;
using Slope=int;
using DoCommandFlags=int;
using CommandCost=int;
enum {STR_ERROR_MUST_DEMOLISH_CANAL_FIRST=-1,STR_ERROR_MUST_DEMOLISH_RIVER_FIRST=-2};
int kind, flags, dispatch;
bool IsWaterTile(TileIndex){return true;}
bool IsCanal(TileIndex){return kind==2;}
bool IsRiver(TileIndex){return kind==1;}
enum class Commands {LandscapeClear};
template<Commands> struct Command{
  static CommandCost Do(DoCommandFlags flags,TileIndex tile){
    ++dispatch;
    if(kind==3 || kind==4) return flags&2 ? -4 : kind==3 ? 10000 : 40;
    if(flags&1) return -3;
    if(flags&2) return -4;
    if(flags&4) return -5;
    return 10000;
  }
};
"""
main = r"""
int main(){
  while(std::cin>>kind>>flags){
    dispatch=0;
    auto cost=TerraformTile_Water(0,flags,0,0);
    std::cout<<cost<<' '<<dispatch<<'\n';
  }
}
"""
lua_test = r"""
local F=dofile("mods/luanttd_core/openttd/water_flood.lua")
local kinds={[0]="sea","river","canal","coast","coast"}
local errors={MUST_DEMOLISH_CANAL_FIRST=-1,MUST_DEMOLISH_RIVER_FIRST=-2,
  CAN_T_BUILD_ON_WATER=-3,VEHICLE_IN_THE_WAY=-4,OWNED_BY_ANOTHER=-5}
local real_clear=F.clear_water
local calls
F.clear_water=function(...)
  calls=calls+1
  return real_clear(...)
end
for line in io.lines() do
  local a,b=line:match("(%d+) (%d+)")
  local kind,flags=tonumber(a),tonumber(b)
  calls=0
  local cost,why=F.terraform_water({kind=kinds[kind],slope=kind==3 and 1 or 3,
    owner=math.floor(flags/4)%2==1 and "other" or "none", occupied=math.floor(flags/2)%2==1},
    {no_water=flags%2==1})
  print(("%d %d"):format(cost or assert(errors[why]),calls))
end
"""
cases = [f"{kind} {flags}" for kind in range(5) for flags in range(8)]
data = "\n".join(cases) + "\n"
with tempfile.TemporaryDirectory() as folder:
    p = Path(folder)
    (p / "test.cpp").write_text(shim + body + main)
    (p / "test.lua").write_text(lua_test)
    subprocess.run(["c++", "-std=c++17", "-O2", str(p / "test.cpp"), "-o", str(p / "oracle")], check=True)
    expected = subprocess.check_output([p / "oracle"], text=True, input=data).splitlines()
    actual = subprocess.check_output([lua, p / "test.lua"], text=True, input=data, cwd=repo).splitlines()
assert len(actual) == len(expected) == len(cases)
for case, a, b in zip(cases, expected, actual):
    assert a == b, (case, a, b)
print(f"PASS {len(cases)} direct RC1 water terraforming guard and delegated clear cases")
