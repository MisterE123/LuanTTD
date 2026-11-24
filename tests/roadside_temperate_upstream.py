#!/usr/bin/env python3
"""Compile the 16.0-RC1 normal Temperate roadside transition verbatim."""
from pathlib import Path
import argparse
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"
road = (src / "road_cmd.cpp").read_text()
layout = (src / "road_map.h").read_text()
lo = layout.index("enum class Roadside :")
enum = layout[lo:layout.index("};", lo) + 2]
lo = road.index("static const Roadside _town_road_types[][2]")
table = road[lo:road.index("};", lo) + 2]
lo = road.index("Roadside cur_rs = GetRoadside(tile);", road.index("static void TileLoop_Road"))
body = road[lo:road.index("MarkTileDirtyByTile(tile);", lo) + len("MarkTileDirtyByTile(tile);")]
main = r"""
static Roadside cur;
static bool dirty;
Roadside GetRoadside(int){return cur;}
void SetRoadside(int,Roadside q){cur=q;}
void MarkTileDirtyByTile(int){dirty=true;}
void visit(int zone) {
  const Roadside* new_rs = _town_road_types[zone];
  constexpr int tile=0;
  BODY
}
int main() {
 for(int z=0;z<5;z++) for(int old : {0,1,2,3,5}) {
   cur=Roadside(old);dirty=false;
   visit(z);
   std::cout.put(char(int(cur)));std::cout.put(char(dirty));
 }
}
"""
lua = r"""
local R=dofile("mods/luanttd_core/openttd/roadside_temperate.lua")
local states={[0]="barren","grass","paved","street_lights",[5]="trees"}
local number={}
for k,v in pairs(states) do number[v]=k end
for zone=0,4 do
  for _,i in ipairs({0,1,2,3,5}) do
    local new,changed=R.visit(states[i],zone)
    io.write(string.char(number[new],changed and 1 or 0))
  end
end
"""
with tempfile.TemporaryDirectory() as d:
    path = Path(d)
    (path / "road.cpp").write_text("#include <cstdint>\n#include <iostream>\n" + enum + "\n" + table + "\n" + main.replace("BODY", body))
    exe = path / "road"
    subprocess.run(["g++", "-std=c++20", str(path / "road.cpp"), "-o", str(exe)], check=True)
    expected = subprocess.check_output([exe])
actual = subprocess.run([a.lua, "-"], input=lua.encode(), capture_output=True, check=True).stdout
assert actual == expected and len(actual) == 50
print("PASS 25 compiled RC1 roadside ground and decoration transitions")
