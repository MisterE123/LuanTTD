#!/usr/bin/env python3
"""Verify pinned RC1 house acceptance data and active road adapters."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])/"src"
exe=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
def read(path,digest):
    data=(source/path).read_bytes()
    assert sha256(data).hexdigest()==digest,path
    return data.decode()
houses=read("table/town_land.h","993109d2943e0a5a155d3da65ac8fb72125da567233fe846226f3d315c9cf8aa")
cargo=read("table/cargo_const.h","cac711a29f0bcd906a8c202219ead4ba5cec90bfc5ea2e2fc03c990ab86f43d2")
town=read("town_cmd.cpp","9483d2c1b188f62241de9a4aef682db940592eb7bf0b40086c4af7b7da77a7e0")
assert "if (!IsValidCargoType(cargo) || amount == 0) return;" in town
assert "acceptance[cargo] += amount;" in town and "always_accepted.Set(cargo);" in town
names={"CT_PASSENGERS":"passenger","CT_MAIL":"mail","CT_GOODS":"goods",
       "CT_FOOD":"food","CT_CANDY":"candy","CT_FIZZY_DRINKS":"fizzy_drinks",
       "CT_WATER":"water", "CargoLabel{}":None}
# The stock climate table supplies the installed labels, which determine
# validity in the no-NewGRF jobs tested here rather than global cargo IDs.
d=cargo.split("_default_climate_cargo[",1)[1]
rosters=[set(re.findall(r"CT_[A-Z_]+",s)) for s in re.findall(r"^\s*\{(.*?)\}",d,re.M)]
assert len(rosters)==4
rows=[]
for match in re.finditer(r"^\s*MS\((.*)\n.*\n.*\n\s*(.*)\),\s*// ([A-F0-9]{2})",houses,re.M):
    fields,labels,index=match.groups()
    fields=fields.strip().strip(",").split(",")
    labels=[x.strip() for x in labels.split(",")]
    assert len(fields)==10 and len(labels)==3 and int(index,16)==len(rows),(index,fields,labels)
    amounts=list(map(int,fields[7:10]))
    if any(k not in names for k in labels):
        assert amounts==[0,0,0],(index,labels,amounts)
        labels=[k if k in names else "CargoLabel{}" for k in labels]
    rows.append((labels,amounts))
assert len(rows)==110
header="""-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, pinned 16.0-RC1 src/table/town_land.h.
-- Source HouseID order. Passenger/mail eighths, third-slot eighths and cargo.
-- Data only, including each child tile of a multi-tile house.
return {
"""
data=[]
for labels,amounts in rows:
    assert labels[:2]==["CT_PASSENGERS","CT_MAIL"] or not any(amounts), (labels,amounts)
    label=names[labels[2]]
    v=f'"{label}"' if label is not None else "false"
    data.append("  {%d,%d,%d,%s}," % (*amounts,v))
file=root/"mods/luanttd_core/openttd/town_house_acceptance_data_rc1.lua"
content=header+"\n".join(data)+"\n}\n"
if "--write-data" in sys.argv[3:]:
    file.write_text(content)
    sys.exit(0)
assert file.read_text()==content
climates=["temperate","arctic","tropic","toyland"]
active=list(names.values())[:-1]
expected=[]
for climate,roster in zip(climates,rosters):
    for i,(labels,amounts) in enumerate(rows):
        for cargo_key in active:
            total=sum(a for label,a in zip(labels,amounts) if label in roster and names[label]==cargo_key)
            expected.append(f"{climate} {i} {cargo_key} {total}")
program=r"""
local folder="mods/luanttd_core/"
local A=dofile(folder.."openttd/town_house_acceptance_rc1.lua")
local road=dofile(folder.."road_station_service.lua")()
local mail=dofile(folder.."road_mail_runtime.lua")()
local goods=dofile(folder.."openttd/town_goods.lua")
for line in io.lines() do
  local landscape,i,cargo,amt=line:match("(%S+) (%d+) (%S+) (%d+)")
  i,amt=tonumber(i),tonumber(amt)
  local accept,mask={},{}
  A.add_to(accept,mask,i,landscape)
  assert((accept[cargo] or 0)==amt and not not mask[cargo]==(amt>0),line)
  assert(A.eighths(i,cargo,landscape)==amt,line)
  if landscape=="temperate" then
    if cargo=="passenger" then assert(road.house_passenger_acceptance(i)==amt) end
    if cargo=="mail" then assert(mail.house_acceptance(i)==amt) end
    if cargo=="goods" then assert(goods.house_acceptance(i)==amt) end
  end
end
-- Food belongs to the house acceptance slot; water must go to industry.
local food,flags={},{}
A.add_to(food,flags,44,"tropic")
assert(food.food==2 and flags.food and not flags.water)
A.add_to(food,flags,45,"tropic")
A.add_to(food,flags,46,"tropic")
A.add_to(food,flags,47,"tropic")
assert(food.food==8 and flags.food)
"""
with TemporaryDirectory(prefix="house-acceptance-rc1-") as d:
    p=Path(d)/"compare.lua"
    p.write_text(program)
    subprocess.run([exe,p],cwd=root,text=True,input="\n".join(expected)+"\n",check=True)
print(f"PASS {len(expected)} RC1 house/cargo/climate acceptance cases and stock road adapters")
