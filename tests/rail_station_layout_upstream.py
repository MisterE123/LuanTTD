#!/usr/bin/env python3
"""Compare both Lua station axes with the actual stock RC1 layout iterator."""
import argparse
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
arg = argparse.ArgumentParser()
arg.add_argument("upstream", type=pathlib.Path)
arg.add_argument("--lua", default="lua5.1")
opts = arg.parse_args()
src = (opts.upstream / "src/station_cmd.cpp").read_text()
body = re.search(r"RailStationTileLayout<StationType::Rail>::Iterator::operator\*\(\) const\n\{(.*?)\n\}", src, re.S)[1]
source = """
#include <span>
#include <cstdio>
#include <cstdint>
using StationGfx=uint8_t;
struct Layout { std::span<const StationGfx> layout; unsigned platforms, length; };
struct Iterator { Layout stl; unsigned position; StationGfx value() const; };
StationGfx Iterator::value() const {
""" + body + """
}
int main() {
  for (unsigned n = 1; n <= 12; ++n)
    for (unsigned l = 1; l <= 12; ++l)
      for (unsigned i = 0; i < n; ++i)
        for (unsigned j = 0; j < l; ++j)
          for (unsigned axis = 0; axis < 2; ++axis)
            std::printf("%u\\n", unsigned(Iterator{{{},n,l},i*l+j}.value())+axis);
}
"""
# Render meshes stay aligned with the actual rail across all variants.
def running_way(path):
    active = False
    found = []
    for line in path.read_text().splitlines():
        if line.startswith("o "):
            active = line[2:] == "Polished_railhead"
        elif active and line.startswith("v "):
            found.append(line)
    assert len(found) >= 4, path
    return found
meshes = root / "mods/luanttd_core/models"
for axis in (0, 1):
    want = running_way(meshes / f"bl_rail_station_gfx_{axis}.obj")
    for gfx in range(axis+2, 8, 2):
        assert running_way(meshes / f"bl_rail_station_gfx_{gfx}.obj") == want
with tempfile.TemporaryDirectory() as tmp:
    code = pathlib.Path(tmp) / "stock.cpp"
    native = code.with_suffix("")
    code.write_text(source)
    subprocess.run(["g++", "-std=c++20", "-O2", str(code), "-o", str(native)], check=True)
    stock = subprocess.check_output([native], text=True)
    lua = """
local u=dofile('mods/luanttd_core/openttd/bridge_underlay.lua')
for n=1,12 do for l=1,12 do for i=0,n-1 do for j=0,l-1 do for axis=0,1 do
print(u.rail_gfx(n,l,i,j,axis))
end end end end end
"""
    port = subprocess.check_output([opts.lua, "-"], input=lua, cwd=root, text=True)
    assert stock == port
print("PASS: 12,168 stock platform cells/axes match the extracted RC1 C++ graphics iterator, and all roofs share the same running rails")
