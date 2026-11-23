#!/usr/bin/env python3
"""Check today's stock bridge kernel against 16.0-RC1 and the real opening UI family list."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import argparse
import json
import subprocess

from openttd_content_timeline import source_rows

root=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser(description=__doc__)
a.add_argument("source",type=Path)
a.add_argument("--lua",default="lua5.1")
a.add_argument("--native-opening",type=Path,default=root/"tests/fixtures/openttd-opening-1950-temperate.json")
args=a.parse_args()
source=source_rows(args.source.resolve())["bridges"]
native=json.loads(args.native_opening.read_text())
assert native["version"]=="16.0-RC1" and native["year"]==1950
check=r'''
local open="mods/luanttd_core/openttd/"
local b=dofile(open.."road_bridge.lua")(dofile(open.."slope.lua"))
for i=0,12 do
  local s=assert(b.catalog[i])
  print(table.concat({i,s.year,s.min_length,s.max_length,s.multiplier,s.speed}," "))
  for year=1925,2025 do
    for length=0,70 do
      local opts={year=year}
      local ok=b.available(i,length,opts)
      if ok then print(("Q %d %d %d"):format(i,year,length)) end
    end
  end
end
'''
answer=subprocess.check_output([args.lua,"-"],cwd=root,input=check,text=True)
must=set()
rows=[]
for row in source:
    number=row["stock_id"]; year=row["first_year"] or 0
    lo,hi=row["min_middle"],row["max_middle"] or 65535
    rows.append(f"{number} {year} {lo} {hi} {row['price_factor']} {row['stock_speed']}")
    for y in range(1925,2026):
        if y>=year:
            for length in range(lo,min(hi,64)+1):
                must.add(f"Q {number} {y} {length}")
seen=answer.splitlines()
assert [e for e in seen if not e.startswith("Q ")]==rows
assert set(e for e in seen if e.startswith("Q "))==must
native_ids={int(i.split()[0]) for i in native["bridge"]}
assert native_ids=={r["stock_id"] for r in source if (r["first_year"] or 0)<=1950}
print(f"PASS all 13 pinned bridge rows, {len(must)} dated length quotes; real 1950 has styles {sorted(native_ids)}")
