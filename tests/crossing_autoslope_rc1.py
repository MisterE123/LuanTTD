"""Compare Lua crossing autoslope against the extracted stock RC1 predicate."""
import re
import subprocess as sp
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
), "Use the exact OpenTTD 16.0-RC1 source checkout"
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"

slope = (source / "src/slope_type.h").read_text()
decl = slope.split("enum Slope : uint8_t {", 1)[1].split("SLOPE_HALFTILE", 1)[0]
decl = "\n".join(line.split("//", 1)[0] for line in decl.splitlines()).strip()
allowlist = re.search(r"static const uint32_t VALID_LEVEL_CROSSING_SLOPES = .*?;", slope)[0]
road = (source / "src/road_cmd.cpp").read_text().split("static CommandCost TerraformTile_Road(", 1)[1]
condition = re.search(
    r"if \((.+)\) return CommandCost\(ExpensesType::Construction, _price\[Price::BuildFoundation\]\);", road
)[1]
assert condition.startswith("!IsSteepSlope(tileh_new)")
pricebase = (source / "src/table/pricebase.h").read_text()
price = int(re.search(r"PriceBaseSpec\((\d+),.*?\)\s*,?\s*// Price::BuildFoundation", pricebase)[1])
max_z = re.search(r"static constexpr int GetSlopeMaxZ\(Slope s\)\s*\{[^}]+}", (
    source / "src/slope_func.h"
).read_text())[0]
assert max_z
cpp = f"""#include <cstdint>
#include <iostream>
enum Slope : uint8_t {{ {decl} }};
#define M(x) (1U << (x))
{allowlist}
#undef M
constexpr bool IsSteepSlope(Slope s) {{ return (s & SLOPE_STEEP) != 0; }}
{max_z}
constexpr bool HasBit(uint32_t bits, Slope s) {{ return (bits & (1U << s)) != 0; }}
int main() {{
  int tile, raw, z_new, slopes, autoslope;
  while (std::cin >> tile >> raw >> z_new >> slopes >> autoslope) {{
    auto tileh_new = static_cast<Slope>(raw);
    auto GetTileMaxZ = [](int t) {{ return t; }};
    std::cout << ((slopes && autoslope && ({condition})) ? {price} : 0) << '\\n';
  }}
}}"""
runner = """
local base="mods/luanttd_core/openttd/"
local C=dofile(base.."level_crossing.lua")(dofile(base.."rail_track.lua"))
for line in io.lines() do
  local a,b,c,d,e=line:match("^(%d+) (%d+) (%d+) (%d+) (%d+)$")
  print(C.autoslope(tonumber(a),tonumber(b),tonumber(c),{build_on_slopes=d=="1",autoslope=e=="1"}) or 0)
end
"""
rows = [
    (top, shape, base, slopes, autoslope)
    for top in range(4)
    for shape in [*range(15), 23, 27, 29, 30]
    for base in range(4)
    for slopes in range(2)
    for autoslope in range(2)
]
data = "".join(" ".join(map(str, row)) + "\n" for row in rows)
with TemporaryDirectory() as tmp:
    path = Path(tmp)
    (path / "oracle.cpp").write_text(cpp)
    (path / "probe.lua").write_text(runner)
    sp.run(["c++", "-std=c++17", "-O2", path / "oracle.cpp", "-o", path / "oracle"], check=True)
    want = sp.check_output([path / "oracle"], input=data, text=True).splitlines()
    got = sp.check_output([lua, path / "probe.lua"], input=data, text=True).splitlines()
assert len(got) == len(want) == len(rows)
for row, a, b in zip(rows, got, want):
    assert a == b, (row, "Lua", a, "RC1", b)
print(f"PASS {len(rows)} crossing autoslope prices compared with the compiled RC1 branch")
