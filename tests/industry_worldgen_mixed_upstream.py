"""Compare the extended native manifest directly with pinned RC1 stock data."""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

header, lua = Path(sys.argv[1]), sys.argv[2]
raw = header.read_bytes()
assert hashlib.sha256(raw).hexdigest() == "eb7938fd37dd37854927253f2f3beeed3c6cafa7425d959035cefef149b66056"
src = raw.decode()

expect = []
names = ("oil_refinery", "factory", "farm", "oil_well")
ids = dict(re.findall(r"IT_([A-Z0-9_]+)\s*=\s*(\d+)\s*,", src))
for kind in names:
    row = re.search(
        rf"MI\(_tile_table_{kind},[^\n]+\n([^\n]+)\n([^\n]+)\n",
        src,
    )
    fields = [field.strip() for field in row[1].split(",") if field.strip()]
    weight = int(fields[6])
    checks = row[2]
    conflicts = sorted(
        int(ids[r]) for r in re.findall(r"\bIT_([A-Z0-9_]+)\b", checks) if r != "INVALID"
    )
    scaled_coastal = int("IndustryCheck::Refinery" in checks)
    expect.append("spec {} {} {} {}".format(ids[kind.upper()], weight, scaled_coastal, ",".join(map(str, conflicts))))
    tiles = re.findall(rf"static const IndustryTileLayout _tile_table_{kind}_(\d+)\s*\{{(.*?)\n\}};", src, re.S)
    assert tiles
    for variant, body in tiles:
        cells = re.findall(r"\{\{(\d+),\s*(\d+)\},\s*(\d+)\}", body)
        assert cells
        expect.append(f"layout {variant} " + ";".join(",".join(c) for c in cells))

actual = subprocess.run([lua, "-"], text=True, capture_output=True, check=True, input=r"""
local mod="mods/luanttd_core/"
local function m(name) return dofile(mod..name..".lua") end
local P,Rating,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local Cat=m("openttd/station_catchment")(P,Rating)
local Coal=m("openttd/coal_industry")(P,Rating,Cat,Income)
local Timber=m("sim").timber_rules()
local Farm=m("openttd/farm_factory_industry")(P,Cat,Rating,Income,Coal,Timber)
local Oil=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),P,Cat,Rating,Income,Coal,Timber)
local Specs=m("openttd/industry_worldgen")(Coal,Timber,Oil,Farm).specs
for _,id in ipairs({4,6,9,11}) do
  local q=Specs[id]
  local ids={}
  for k,v in pairs(q.conflict) do if v then ids[#ids+1]=k end end
  table.sort(ids)
  io.write(("spec %d %d %d %s\n"):format(id,q.weight,q.coastal and 1 or 0,table.concat(ids,",")))
  for k=0,#q.layout do
    local tiles={}
    for i,t in ipairs(q.layout[k]) do tiles[i]=table.concat(t,",") end
    io.write(("layout %d %s\n"):format(k,table.concat(tiles,";")))
  end
end
""").stdout.splitlines()
assert expect == actual, "\n".join(
    f"upstream {a}\nLuanTTD  {b}" for a, b in zip(expect, actual) if a != b
)
print("PASS OpenTTD 16.0-RC1 original Oil/Farm type IDs, four weights, directional conflicts and all nine stock layouts")
