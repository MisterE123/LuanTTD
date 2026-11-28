#!/usr/bin/env python3
"""Source-checked Tropic Water Supply, Water Tower and growth accounting."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
def read(name,digest):
    data=(src/name).read_bytes()
    assert sha256(data).hexdigest()==digest, name
    return data.decode()
data=read("table/build_industry.h","eb7938fd37dd37854927253f2f3beeed3c6cafa7425d959035cefef149b66056")
cargo=read("table/cargo_const.h","cac711a29f0bcd906a8c202219ead4ba5cec90bfc5ea2e2fc03c990ab86f43d2")
engines=read("table/engines.h","d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74")
tanks=[]
for name in ("Uhl","Balogh","MPS"):
    mr,stock=re.search(r"MR\(([^\n]*?CT_WATER[^\n]*?)\),\s*//\s*(\d+) "+name+r" Water Tanker",engines).groups()
    props,idx=re.search(r"ROV\(([^\n]*?)\),\s*//\s*(\d+) "+name+r" Water Tanker",engines).groups()
    intro=[int(v.strip()) for v in mr.split(",")[:4]]
    visual=[int(v.strip()) for j,v in enumerate(props.split(",")) if j!=3]
    assert re.search(r"LandscapeTypes\(\{\s*S\s*\}\)",mr)
    tanks.extend([int(stock),int(idx),*intro,*visual])
inds=[]
for k,id in [("supply",21),("tower",22)]:
    row=re.search(r"MI\(_tile_table_water_"+k+r",\s+\{\},(.*?)STR_INDUSTRY_NAME_WATER_"+k.upper(),data,re.S)[1]
    q=row.split(",")
    # MI(..., d, ..., col, ...) maps d to the construction factor;
    # col is the map legend colour and must never drive the price.
    build,colour=int(q[0].strip()),int(q[10].strip())
    other=22 if id==21 else 21
    assert q[11].strip()=="IT_WATER_"+("TOWER" if id==21 else "SUPPLY")
    layout=re.search(r"\b_tile_table_water_"+k+r"_0\s*\{(.*?)\n\};",data,re.S)[1]
    layout=[tuple(map(int,r)) for r in re.findall(r"\{\{(\d+), (\d+)\}, (\d+)\}",layout)]
    inds.append((k,id,build,colour,other,layout))
water_defaults=re.search(r"MK\(\s*(15), CT_WATER,\s+\d+,\s*(\d+),\s*(0x\w+),\s*(\d+),\s*(\d+),\s*(\d+),\s*true,\s*TownAcceptanceEffect::Water,",cargo)
assert water_defaults
water=[int(x,0) for x in water_defaults.groups()[1:]]
accept=int(re.search(r"/\* Water tower \*/\s*\{0, CT_INVALID, (\d+), CT_WATER, false\}",data)[1])
program=r"""
local p="mods/luanttd_core/openttd/"
local M=dofile(p.."town_water_industry_rc1.lua")
local G=dofile(p.."town_growth.lua")
local Stats=dofile(p.."town_cargo_stats.lua")
local Calendar=dofile(p.."stock_engine_calendar.lua")
local fields={"weight_sixteenths","capacity_multiplier","base_payment","transit_period_1","transit_period_2"}
for _,k in ipairs(fields) do assert(M.cargo[k]==io.read("*n")) end
assert(M.tile_acceptance(120,"water")==io.read("*n") and M.tile_acceptance(119,"water")==0)
assert(M.tile_acceptance(120,"food")==0)
for _,k in ipairs({"supply","tower"}) do
  local spec=M[k]
  assert(spec.id==io.read("*n") and spec.construction_factor==io.read("*n") and spec.map_colour==io.read("*n") and spec.conflict==io.read("*n"))
  local n=io.read("*n");assert(n==#spec.layout)
  for i=1,n do for j=1,3 do assert(spec.layout[i][j]==io.read("*n")) end end
  local calls=0
  local function clear(as,automatic,ignore,unchanged)
    calls=calls+1
    if k=="tower" then assert(as=="town" and not automatic and not ignore and not unchanged)
    else assert(as=="company" and automatic and ignore and unchanged) end
    return true
  end
  assert(M.surface(spec,{valid=true,house=true,population=40},clear))
  local clears_empty=M.surface(spec,{valid=true},clear)
  assert(clears_empty==(k=="supply"))
  assert(not M.surface(spec,{valid=true,house=true,bridge_above=true},clear))
  assert(not M.surface(spec,{valid=true,house=true,vehicle=true},clear))
  assert(not M.surface(spec,{valid=true,on_water=true},clear))
  assert(calls==(k=="supply" and 2 or 1))
  assert(M.conflict(spec,0,0,{{type=spec.conflict,x=14,z=14}}))
  assert(not M.conflict(spec,0,0,{{type=spec.conflict,x=15,z=14}}))
end
assert(M.anchor(1) and not M.anchor(0) and not M.anchor(2))
for _,r in ipairs(M.road_tankers) do
  for _,k in ipairs{"stock_id","road_model","intro_after_1920","decay_speed","life","base_life",
    "image","purchase_factor","running_factor","speed","capacity","weight_quarters","power_tens_hp"} do
    assert(r[k]==io.read("*n"),k)
  end
  local options={starting_year=1950,generation_seed=1751,startup_seed=123,climate="tropic"}
  assert(Calendar.prepare_original(r,options).climate_matches)
  options.climate="temperate"
  assert(not Calendar.prepare_original(r,options).climate_matches)
end
-- DeliverGoods credits actual accepted industry water to the *station's*
-- town growth effect; it must not report it as household water receipt.
local t=G.new(1,5,5,{population=91,climate="tropic",has_effect=function(e) return e==4 or e==5 end})
local state={stock_town_growth={towns={[1]=t}}}
local nearby={{x=5,z=5,time_since_load=0}}
local function desert()return {is_desert=true} end
Stats.accept(state,1,"food",1,1)
assert(not G.month(t,nearby,2,nil,desert))
Stats.accept(state,1,"food",1,1)
Stats.accept(state,1,"water",1,0)
assert(G.month(t,nearby,2,nil,desert))
assert(t.received[4].old_act==1 and t.accepted.water==nil)
assert(not G.month(t,nearby,2,nil,desert))
"""
values=water+[accept]
for k,id,build,colour,other,layout in inds:
    values.extend([id,build,colour,other,len(layout)])
    for tile in layout:
        values.extend(tile)
values.extend(tanks)
with TemporaryDirectory(prefix="luanttd-water-tower-") as d:
    script=Path(d)/"run.lua";script.write_text(program)
    subprocess.run([lua,script],cwd=root,input=" ".join(map(str,values))+"\n",text=True,check=True)
print("PASS RC1 Water Supply and Water Tower, Water Tankers, siting, and town monthly receipts")
