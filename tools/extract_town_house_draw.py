#!/usr/bin/env python3
"""Read the stage/slot sprite pairs from the pinned OpenTTD town_land.h.

Only stock Temperate one-tile houses are represented. Numeric sprite
IDs carry no image data. Verify the vendored Lua rows with --check.
"""
from hashlib import sha256
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
OUT=MOD/"openttd/stock_town_draw_rows.lua"
SOURCE_HASH="993109d2943e0a5a155d3da65ac8fb72125da567233fe846226f3d315c9cf8aa"
HEADER="""-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, src/table/town_land.h, _town_draw_tile_data
-- 16.0-RC1 Git blob 07b339c0aaeb0a87be9490b2f1c3f17c6b00b837.
-- Plot sprite and upper sprite. 0 means absent; -1 bare land, -2 paving,
-- -3 grass. Slots preserve source order; each sequence runs stages 0..3.
-- Refresh using tools/extract_town_house_draw.py with the pinned source.
return {
"""


def extract(p):
    source=p.read_text(encoding="utf-8")
    assert sha256(source.encode()).hexdigest()==SOURCE_HASH,"Use unmodified OpenTTD 16.0-RC1 town_land.h"
    raw=source.split("_town_draw_tile_data[] = {",1)[1].split("};",1)[0]
    records=[tuple(t.strip() for t in data.split(",")) for data in re.findall(r"\bM\(([^)]+)\)",raw)]
    assert len(records)%16==0 and all(len(r)==10 for r in records)
    catalog=(MOD/"openttd/town_growth_houses.lua").read_text()
    houses=[int(m,16) for m in re.findall(r"{0x([A-F0-9]+),\d+,\d+,\d+,\d+,1,1,",catalog)]
    assert len(houses)==27
    symbols={"SPR_FLAT_BARE_LAND":-1,"SPR_CONCRETE_GROUND":-2,"SPR_FLAT_GRASS_TILE":-3}
    rows=[]
    for id in houses:
        groups=[]
        slots=[]
        for slot in range(4):
            ref=records[(id*4+slot)*4:(id*4+slot+1)*4]
            pairs=[(symbols[r[0]] if r[0] in symbols else int(r[0],0),int(r[2],0)) for r in ref]
            # Ground rows use the base house palettes. An unchanged upper
            # sprite does not switch its own palette when its yard changes.
            assert all(a[1]==b[1] for a in ref for b in ref if a[0]==b[0])
            assert all(a[3]==b[3] for a in ref for b in ref if a[2]==b[2])
            if pairs not in groups:
                groups.append(pairs)
            slots.append(groups.index(pairs)+1)
        a=",".join(map(str,slots))
        rows.append(f"  [0x{id:02X}]={{slots={{{a}}},")
        for stages in groups:
            line=",".join(f"{{{g},{b}}}" for g,b in stages)
            rows.append("    {"+line+"},")
        rows.append("  },")
    return HEADER+"\n".join(rows)+"\n}\n"

if __name__=="__main__":
    if len(sys.argv)<2:
        sys.exit("usage: extract_town_house_draw.py PINNED/town_land.h [--check]")
    expected=extract(Path(sys.argv[1]))
    if "--check" in sys.argv:
        assert OUT.read_text()==expected
        print("PASS exact OpenTTD 16.0-RC1 27-root house draw selector")
    else:
        OUT.write_text(expected)
