#!/usr/bin/env python3
"""Compare the stock statue placement loop with real RC1 spiral shapes."""
from argparse import ArgumentParser
from pathlib import Path
from random import Random
import subprocess
from tempfile import TemporaryDirectory

from scenery_object_rc1_upstream import CPP as STOCK_MAP, extract

p = ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"
header = (src / "tilearea_spiral.h").read_text()
iterator = header[header.index("class SpiralTileIterator"):header.rindex("#endif")]
source = (src / "tilearea_spiral.cpp").read_text()
iterator += "\n" + source[source.index("SpiralTileIterator::SpiralTileIterator"):]
town = (src / "town_cmd.cpp").read_text()
lo = town.index("static const int STATUE_NUMBER_INNER_TILES", town.index("static CommandCost TownActionBuildStatue"))
body = town[lo:town.index("if (best_position == INVALID_TILE) return", lo)]
random_next = extract((src / "core/random_func.cpp").read_text(), "uint32_t Randomizer::Next()")
cpp = STOCK_MAP.replace("Void=7", "House=3, Trees=4, Void=7") + iterator + random_next + r"""
bool IsSteepSlope(int slope) { return (slope & 16) != 0; }
int GetTileSlope(TileIndex tile) { return terrain[tile] & 31; }
bool CheckClearTile(TileIndex tile) { return bool(terrain[tile] & 16384); }
TileIndex Statue(const Town *t) {
BODY
 return best_position;
}
int main() {
 width=64; depth=64; tiles.resize(64*64); terrain.resize(64*64);
 int n, center;
 std::cin>>n;
 while(n--) {
  std::cin>>center;
  Town town{center};
  for(int i=0;i<64*64;i++) std::cin>>tiles[i]>>terrain[i];
  std::cout<<Statue(&town)<<"\n";
 }
}
""".replace("BODY", body)
lua = """
local function read() return io.read("*number") end
local root="mods/luanttd_core/openttd/"
local M=dofile(root.."town_statue_rc1.lua")(dofile(root.."spiral_tile_rc1.lua"))
assert(M.price()==187500 and M.price(2000001)==375000)
local names={[0]="clear",[3]="house",[4]="trees",[7]="void"}
for _=1,read() do
 local center,cells=read(),{}
 for i=0,4095 do
  local k,b=read(),read()
  cells[i]={class=names[k],slope=b%32,bridge_above=math.floor(b/8192)%2==1,clear=b>=16384}
 end
 io.write((M.site({width=64,depth=64,tile=function(i) return cells[i] end,
   can_clear=function(_,t) return t.clear end},center) or -1).."\\n")
end
"""
rng = Random(1681)
cases = []
for i in range(96):
    x, z = ((0,0), (63,1), (32,37), (1,62), (60,61), (13,22))[i % 6]
    centers = [0,3,4,7] if i % 3 else [7,7,7,3]
    data = [str(x+z*64)]
    for k in range(64*64):
        can_clear = rng.randrange(9) > i % 9
        slope = rng.choice([0,0,0,1,7,14,23,30])
        data.extend((str(rng.choice(centers)), str(slope + 8192*(rng.randrange(8)==0) + 16384*can_clear)))
    cases.append(" ".join(data))
fixture = str(len(cases)) + "\n" + "\n".join(cases) + "\n"
with TemporaryDirectory() as d:
    work = Path(d)
    (work / "test.cpp").write_text(cpp)
    subprocess.run(["g++","-std=c++20","-O2",str(work/"test.cpp"),"-o",str(work/"tester")],check=True)
    expected = subprocess.check_output([str(work/"tester")],input=fixture,text=True)
actual = subprocess.check_output([a.lua,"-e",lua],input=fixture,text=True)
assert actual==expected and "-1" in actual.splitlines() and len(set(actual.splitlines()))>10
print(f"PASS {len(cases)} stock Temperate town statue placement boards")
