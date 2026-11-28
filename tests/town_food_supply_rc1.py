#!/usr/bin/env python3
"""Native-stock Food industry data and compiled cargo-arrival arithmetic."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
from random import Random
from tempfile import TemporaryDirectory

from rc1_rail_foundation_shim import source_block

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
def text(name,checksum):
    b=(src/name).read_bytes()
    assert sha256(b).hexdigest()==checksum,name
    return b.decode()
econ=text("economy.cpp","e9a41c922184f446fbb25099fb4213b3c50683030d5834c3db7b65af91ab1b6c")
data=text("table/build_industry.h","eb7938fd37dd37854927253f2f3beeed3c6cafa7425d959035cefef149b66056")
cargo=text("table/cargo_const.h","cac711a29f0bcd906a8c202219ead4ba5cec90bfc5ea2e2fc03c990ab86f43d2")
vals=[int(s,0) for s in re.search(r"MK\(\s*12, CT_FOOD,\s+\d+,\s*(\d+),\s*(0x\w+),\s*(\d+),\s*(\d+),\s*(\d+),\s*true,\s*TownAcceptanceEffect::Food,",cargo).groups()]
proc=data.split("MI(_tile_table_food_process,",1)[1].split("STR_INDUSTRY_NAME_FOOD_PROCESSING_PLANT",1)[0]
assert "MCT_LIVESTOCK_FRUIT,     256, MCT_GRAIN_WHEAT_MAIZE,       256" in proc
assert "IT_FRUIT_PLANTATION, IT_FARM,           IT_FARM_2" in proc
for table in ("food_process","fruit_plantation","farm2"):
    fields=re.search(r"MI\(_tile_table_"+table+r",\s*\{\},(.*?)IndustryCheck::",data,re.S)[1].split(",")
    vals.extend(int(fields[j].strip()) for j in (0,10))
for table,count in (("food_process",2),("fruit_plantation",1),("farm2",3),("farm",3)):
    for i in range(count):
        layout=re.search(rf"_tile_table_{table}_{i} \{{(.*?)\n\}};",data,re.S)[1]
        coords=[tuple(map(int,m)) for m in re.findall(r"\{\{(\d+), (\d+)\}, (\d+)\}",layout)]
        vals.append(len(coords))
        for cell in coords:
            vals.extend(cell)
engines=text("table/engines.h","d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74")
for engine in (141,142,143,156,157,158,165,166,167,168,169,170):
    mr=re.search(rf"MR\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*\w+\s*, LandscapeTypes\(\{{([^}}]*)}}\)\), // {engine} ",engines)
    assert mr,engine
    m=mr.groups()
    rov=re.search(rf"ROV\(\s*(\d+),\s*(\d+),\s*(\d+),\s*\w+,\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\), //\s+{engine-116} ",engines)
    assert rov,engine
    vals.extend((engine,*(int(v) for v in m[:4]),sum(1<<i for i,k in enumerate("TASY") if k in m[4]),*(int(v) for v in rov.groups())))
cpp=r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint=unsigned;
enum class IndustryCallbackMask { ProductionCargoArrival,Production256Ticks };
struct IndustryCallbackMasks { bool Test(IndustryCallbackMask){return false;} };
enum class WindowClass { IndustryView };
enum class IndustryRandomTrigger { CargoReceived };
enum class IndustryAnimationTrigger { CargoReceived };
struct Cargo { int cargo; int waiting; };
struct Industry {
    int type=13,index=0;
    bool was_cargo_delivered=false;
    std::array<Cargo,2> accepted,produced;
};
struct IndustrySpec {
    IndustryCallbackMasks callback_mask;
    int input_cargo_multiplier[2][2];
} spec;
int hooks=0;
const IndustrySpec *GetIndustrySpec(int){return &spec;}
void IndustryProductionCallback(Industry*,int){assert(false);}
void SetWindowDirty(WindowClass,int){assert(false);}
bool IsValidCargoType(int c) {return c>=0;}
template<class T>T ClampTo(int x){return std::clamp(x,0,65535);}
void TriggerIndustryRandomisation(Industry*,IndustryRandomTrigger){assert(hooks==0);hooks=1;}
void TriggerIndustryAnimation(Industry*,IndustryAnimationTrigger){assert(hooks==1);hooks=2;}
"""
cpp+=source_block(src,"economy.cpp",r"^static void TriggerIndustryProduction\(Industry \*i\)\s*\n")
cpp+=r"""
int main(){
  Industry i;
  while(std::cin>>i.accepted[0].cargo>>i.accepted[0].waiting>>i.accepted[1].cargo>>i.accepted[1].waiting
                >>i.produced[0].cargo>>i.produced[0].waiting>>i.produced[1].cargo>>i.produced[1].waiting
                >>spec.input_cargo_multiplier[0][0]>>spec.input_cargo_multiplier[0][1]
                >>spec.input_cargo_multiplier[1][0]>>spec.input_cargo_multiplier[1][1]){
    hooks=0;i.was_cargo_delivered=false;
    TriggerIndustryProduction(&i);
    std::cout<<i.accepted[0].waiting<<" "<<i.accepted[1].waiting<<" "
       <<i.produced[0].waiting<<" "<<i.produced[1].waiting<<" "<<hooks<<" "<<i.was_cargo_delivered<<"\n";
  }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local F=dofile(p.."town_food_supply_rc1.lua")
local P=dofile(p.."industry_production_arrival_rc1.lua")
local G=dofile(p.."town_growth.lua")
local Stats=dofile(p.."town_cargo_stats.lua")
local expected={}
for n in io.read("*l"):gmatch("%S+") do expected[#expected+1]=tonumber(n) end
for i,k in ipairs{"weight_sixteenths","capacity_multiplier","base_payment","transit_period_1","transit_period_2"} do
  assert(F.cargo[k]==expected[i])
end
local offset=6
for _,spec in ipairs{F.process,F.fruit,F.maize} do
  assert(spec.cost_factor==expected[offset] and spec.map_colour==expected[offset+1])
  offset=offset+2
end
local kernel=dofile(p.."farm_factory_industry.lua")()
assert(kernel.layout.farm[0])
local function layout(plan)
  assert(#plan==expected[offset]);offset=offset+1
  for _,cell in ipairs(plan) do for _,v in ipairs(cell) do assert(v==expected[offset]);offset=offset+1 end end
end
for _,plan in ipairs(F.process.layout) do layout(plan) end
layout(F.fruit.layout[0])
for i=0,2 do layout(F.maize.layout[i]) end
for i=0,2 do layout(kernel.layout.farm[i]) end
local D=dofile(p.."climate_road_freight_rc1.lua")
local by={}
for _,id in ipairs(D.all) do
  local row=D.rows[id]
  by[row.stock_id]=by[row.stock_id] or {}
  by[row.stock_id][#by[row.stock_id]+1]=row
end
while offset<=#expected do
  local n=assert(by[expected[offset]])
  local keys={"stock_id","intro_after_1920","decay_speed","life","base_life","climates",
    "image","purchase_factor","running_factor","speed","capacity","weight_quarters","power_tens_hp"}
  assert(#n==(expected[offset]<=143 and 2 or 1))
  for j,k in ipairs(keys) do
    for _,row in ipairs(n) do assert(row[k]==expected[offset+j-1],row.name.."/"..k) end
  end
  offset=offset+#keys
end
assert(offset==#expected+1 and #D.by_landscape.tropic==12 and #D.by_landscape.arctic==6)
assert(D.rows.maize_hereford.cargo=="maize" and D.rows.wheat_hereford.cargo=="wheat")
local a,b=F.inputs("arctic");assert(a=="livestock" and b=="wheat")
a,b=F.inputs("tropic");assert(a=="fruit" and b=="maize")
assert(not F.inputs("temperate") and not F.inputs("toyland"))
assert(F.acceptance_eighths(63,"wheat","arctic")==8 and F.acceptance_eighths(62,"wheat","tropic")==0)
assert(F.acceptance_eighths(60,"fruit","tropic")==8 and F.acceptance_eighths(64,"fruit","tropic")==0)
assert(F.plantation_anchor(0) and not F.plantation_anchor(1) and F.plantation_anchor(2))
local factory={accepted={{cargo="fruit",waiting=12},{cargo="maize",waiting=8}},produced={{cargo="food",waiting=3}}}
assert(P.apply(factory,F.process.multiplier)==20 and factory.produced[1].waiting==23)
local t=G.new(1,0,0,{population=121,climate="arctic",has_effect=function(i) return i==5 end})
local state={stock_town_growth={towns={[1]=t}}}
local nearby={{x=0,z=0,time_since_load=0}}
local function climate()return {snowline=9,tile_height=9} end
assert(not G.month(t,nearby,2,nil,climate))
Stats.accept(state,1,"food",factory.produced[1].waiting,factory.produced[1].waiting)
assert(G.month(t,nearby,2,nil,climate))
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  local function slot(i)return {cargo=a[i]>=0 and a[i] or false,waiting=a[i+1]} end
  local industry={accepted={slot(1),slot(3)},produced={slot(5),slot(7)}}
  local m={{a[9],a[10]},{a[11],a[12]}}
  local hooks=0
  P.apply(industry,m,function(i,reason)
    assert(hooks==0 and i.was_cargo_delivered and reason=="cargo_received");hooks=1
  end,function(i,reason)
    assert(hooks==1 and reason=="cargo_received");hooks=2
  end)
  print(industry.accepted[1].waiting,industry.accepted[2].waiting,industry.produced[1].waiting,
    industry.produced[2].waiting,hooks,industry.was_cargo_delivered and 1 or 0)
end
"""
rng=Random(16013)
cases=[]
for _ in range(5600):
    row=[]
    for i in range(4):
        row.extend([rng.choice([-1,0,i]),rng.choice([0,1,23,4096,65534,65535,rng.randrange(65536)])])
    row.extend(rng.choice([0,16,64,255,256,257,512]) for i in range(4))
    cases.append(row)
data_in="\n".join(" ".join(map(str,r)) for r in cases)+"\n"
with TemporaryDirectory(prefix="food-rc1-") as d:
    r=Path(d)
    (r/"ref.cc").write_text(cpp)
    (r/"test.lua").write_text(program)
    subprocess.run(["c++","-std=c++20","-O2",r/"ref.cc","-o",r/"ref"],check=True)
    ref=subprocess.check_output([r/"ref"],input=data_in,text=True).splitlines()
    got=subprocess.check_output([lua,r/"test.lua"],cwd=root,input=" ".join(map(str,vals))+"\n"+data_in,text=True).splitlines()
assert len(ref)==len(got)==len(cases)
for i,(a,b) in enumerate(zip(ref,got)):
    assert a.split()==b.split(),(i,cases[i],a,b)
print(f"PASS RC1 climate food supply and {len(cases)} compiled stock industry cargo-arrival cases")
