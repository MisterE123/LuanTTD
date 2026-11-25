"""Compare every Temperate footprint in the worldgen catalog with stock RC1.

This intentionally tests definitions, not whether each footprint has playable
art or an enabled native placement path.
"""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

header = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(header).hexdigest() == "eb7938fd37dd37854927253f2f3beeed3c6cafa7425d959035cefef149b66056"
lua = sys.argv[2]
src = header.decode()
# Oil rigs and banks are mounted by dedicated runtime adapters, rather than
# the shared terrestrial world-generation factory.
kinds = {
    0: "coal_mine",
    1: "power_station",
    2: "sawmill",
    3: "forest",
    4: "oil_refinery",
    6: "factory",
    8: "steel_mill",
    9: "farm",
    11: "oil_well",
    18: "iron_mine",
}
source = {}
for ident, kind in kinds.items():
    pattern = rf"static const IndustryTileLayout _tile_table_{kind}_(\d+)\s*\{{(.*?)\n\}};"
    for variant, body in re.findall(pattern, src, re.S):
        cells = re.findall(r"\{\{(-?\d+),\s*(-?\d+)\},\s*(\d+)\}", body)
        assert cells and len(cells) == body.count("{{"), (kind, variant)
        source[ident, int(variant)] = tuple(tuple(map(int, cell)) for cell in cells)

port = subprocess.run([lua, "-"], input=r"""
local function m(p) return dofile("mods/luanttd_core/"..p..".lua") end
local P,R,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local coal=m("openttd/coal_industry")(P,R,C,I)
local timber=m("sim").timber_rules()
local Farm=m("openttd/farm_factory_industry")
local farm=Farm(P,C,R,I,coal,timber)
farm=m("openttd/iron_steel_rules")(farm,m("openttd/iron_steel_data"))
local oil=m("openttd/oil_industry")(Farm,P,C,R,I,coal,timber)
local world=m("openttd/industry_worldgen")(coal,timber,oil,farm,true)
for id,spec in pairs(world.specs) do
  for i,layout in pairs(spec.layout) do
    local columns={id,i}
    for _,part in ipairs(layout) do columns[#columns+1]=table.concat(part,",") end
    print(table.concat(columns," "))
  end
end
""", text=True, stdout=subprocess.PIPE, check=True)

native = {}
for row in port.stdout.splitlines():
    ident, index, *cells = row.split()
    key = int(ident), int(index)
    native[key] = tuple(tuple(map(int, cell.split(","))) for cell in cells)

assert source.keys() == native.keys(), (source.keys() - native.keys(), native.keys() - source.keys())
for key, cells in source.items():
    assert native[key] == cells, (kinds[key[0]], key[1], cells, native[key])
    assert len({(x, z) for x, z, _ in cells}) == len(cells), key
print(f"PASS pinned RC1 ordered native layout data: {len(kinds)} types and {len(source)} variants")
print("Origin absent in:", ", ".join(f"{kinds[k]}:{v}" for (k, v), cs in source.items()
                                     if not any(x == z == 0 for x, z, _ in cs)))
