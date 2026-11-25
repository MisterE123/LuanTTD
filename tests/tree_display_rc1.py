"""Compare the Temperate native display selector against the pinned RC1 table."""
import itertools as it
import re
import subprocess as sp
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

path = Path(sys.argv[1])
assert sp.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
data = (path / "src/table/tree_land.h").read_text()
offsets = re.search(r"static const Coord2D<uint8_t> _tree_layout_xy\[\]\[4\].*?\n};", data, re.S)[0]
sprites = data.split("_tree_layout_sprite", 1)[1].splitlines()[1:49]
assert len(sprites) == 48
code = (path / "src/tree_cmd.cpp").read_text().split("static void DrawTile_Trees", 1)[1]
stage = (path / "src/tree_map.h").read_text().split("enum class TreeGrowthStage : uint8_t", 1)[1].split("};", 1)[0]
steps = re.search(r"uint tmp = CountBits\(.*?\n\tuint index = .*?;", code, re.S)[0]
position = re.search(r"const Coord2D<uint8_t> \*d = _tree_layout_xy[^;]+;", code)[0]
formula = re.search(r"SpriteID sprite = s\[0\].sprite \+ .*?;", code)[0]
cpp = r"""
#include <bit>
#include <cstdint>
#include <iostream>
using uint=unsigned;
using SpriteID=unsigned;
const int PAL_NONE=0;
template<typename T> struct Coord2D { T x,y; };
struct PalSpriteID { uint sprite,pal; };
enum class TreeGrowthStage : uint8_t GROWTH };
struct ID { uint n; uint base() const { return n; } };
struct Tile { ID tile; uint x,y,species,growth; };
uint CountBits(uint i) { return std::popcount(i); }
uint GB(uint i,uint start,uint bits) { return (i>>start)&((1u<<bits)-1); }
uint GetTreeType(ID);
TreeGrowthStage GetTreeGrowth(ID);
constexpr int to_underlying(TreeGrowthStage x) { return static_cast<int>(x); }
OFFSETS
static const PalSpriteID _tree_layout_sprite[48][4] = {
SPRITES
};
Tile *ti;
uint GetTreeType(ID) { return ti->species; }
TreeGrowthStage GetTreeGrowth(ID) { return static_cast<TreeGrowthStage>(ti->growth); }
int main() {
  Tile t;
  ti=&t;
  uint trees;
  while (std::cin >> t.tile.n >> t.x >> t.y >> t.species >> trees >> t.growth) {
    t.x*=16; t.y*=16;
    STEPS
    const PalSpriteID *s = _tree_layout_sprite[index];
    POSITION
    for (uint i=0; i<trees; i++,s++,d++) {
      FORMULA
      std::cout << sprite << ':' << unsigned(d->x) << ':' << unsigned(d->y) << (i+1==trees?'\n':' ');
    }
  }
}
""".replace("GROWTH", stage).replace("OFFSETS", offsets).replace("SPRITES", "\n".join(sprites)).replace(
    "STEPS", steps
).replace("POSITION", position).replace("FORMULA", formula)
runner = r"""
local A=dofile("mods/luanttd_core/openttd/tree_display.lua")
local found={}
for line in io.lines() do
  local n,x,z,s,c,g=line:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)$")
  local out={}
  for _,p in ipairs(A.sample(tonumber(n),tonumber(x),tonumber(z),tonumber(s),tonumber(c),tonumber(g))) do
    found[p.shape]=true
    out[#out+1]=("%d:%d:%d"):format(p.shape+p.phase,p.dx,p.dz)
  end
  print(table.concat(out," "))
end
local seen=0
for _ in pairs(found) do seen=seen+1 end
assert(seen==19 and #A.shapes==19)
"""
cells = [(w * z + x, x, z) for w in (64, 128, 256, 4096) for x, z in (
    (0, 0), (0, 1), (1, 0), (7, 7), (8, 31), (w - 1, w - 1),
    (w - 1, 0), (1, w - 2), (52, 4), (w - 2, w - 2), (w // 3, w // 4))]
rows = [(*cell, t, c, g) for cell, t, c, g in it.product(cells, range(12), range(1, 5), range(7))]
payload = "".join(" ".join(map(str, row)) + "\n" for row in rows)
with TemporaryDirectory() as tmp:
    d = Path(tmp)
    (d / "oracle.cpp").write_text(cpp)
    (d / "test.lua").write_text(runner)
    sp.run(["c++", "-std=c++20", "-O2", d / "oracle.cpp", "-o", d / "oracle"], check=True)
    rc1 = sp.check_output([d / "oracle"], input=payload, text=True).splitlines()
    port = sp.check_output([lua, d / "test.lua"], input=payload, text=True).splitlines()
assert len(rows) == len(port) == len(rc1)
for row, a, b in zip(rows, rc1, port):
    assert a == b, (row, "RC1", a, "Lua", b)
print(f"PASS {len(rows):,} exact RC1 Temperate stem selectors, source identifiers and growth phases")
