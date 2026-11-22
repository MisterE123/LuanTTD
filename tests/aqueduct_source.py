#!/usr/bin/env python3
"""Compile and compare the pinned source's water-specific aqueduct rules.

python tests/aqueduct_source.py /path/to/OpenTTD [lua5.1]
Only the board/Company/Tile containers are fixture shims. The stock
branches for length availability, pricing, storage ID, canal class and
infrastructure are compiled from untouched, verified 14.1 source lines.
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
CHECKOUT=Path(sys.argv[1])


def source(name, checksum):
    candidates=(CHECKOUT/"src"/name,CHECKOUT/name,CHECKOUT/Path(name).name)
    file=next(f for f in candidates if f.is_file())
    data=file.read_bytes()
    assert sha256(data).hexdigest()==checksum,(file,"not pinned OpenTTD 14.1")
    return data.decode()


def block(text, needle):
    start=text.index(needle)
    last=text.index("{",start)
    depth=1
    while depth:
        last+=1
        depth+=(text[last]=="{")-(text[last]=="}")
    return text[start:last+1]


bridge=source("tunnelbridge_cmd.cpp","48b5401e1262964cb961b266a4dd0cf81d171a7f60e264597be8e4f138fad305")
tiles=source("bridge_map.h","f1eba14db0379559109deff9827fc983a54bf3e4cf93a5eedf9dedda3465b6b1")
ships=source("ship_cmd.cpp","f664841259821ee557109c15f2f2e6497b7416030a78e0275875f47f1fb8851a")
econ=source("economy_type.h","3ceaeaae7a62363f3243a1b337f1e84c98c74d22a81c0dd71c74921955e6697b")
prices=source("table/pricebase.h","17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356")
settings=source("table/world_settings.ini","4c08978820994e9a975a1a135b9d1ebcf01764772e49ecc2ad2c71c05e93642e")
make=block(tiles,"inline void MakeAqueductBridgeRamp")
water=block(ships,"WaterClass GetEffectiveWaterClass")
length=block(bridge,"int CalcBridgeLenCostFactor")
upper=re.search(r"if \(bridge_len > _settings_game.construction.max_bridge_length\)[^;]+;",bridge)[0]
query=re.search(r"if \(!\(flags & DC_QUERY_COST\) \|\| \(c != nullptr && c->is_ai && company != _local_company\)\)",bridge)[0]
price_fn=re.search(r"if \(c != nullptr\) bridge_len = CalcBridgeLenCostFactor\(bridge_len\);",bridge)[0]
build=re.search(r"cost.AddCost\(\(int64_t\)bridge_len \* _price\[PR_BUILD_AQUEDUCT\]\);",bridge)[0]
remove=re.search(r"case TRANSPORT_WATER: (base_cost = _price\[PR_CLEAR_AQUEDUCT\];)",bridge)[1]
infra=re.search(r"if \(is_new_owner && c != nullptr\) c->infrastructure.water \+= bridge_len \* TUNNELBRIDGE_TRACKBIT_FACTOR;",bridge)[0]
factor=re.search(r"static const uint TUNNELBRIDGE_TRACKBIT_FACTOR = \d+;",econ)[0]
build_base=int(re.search(r"{\s*(\d+),[^\n]+///< PR_BUILD_AQUEDUCT\s*$",prices,re.M)[1])
clear_base=int(re.search(r"{\s*(\d+),[^\n]+///< PR_CLEAR_AQUEDUCT\s*$",prices,re.M)[1])
max_length=int(re.search(r"var\s*=\s*construction.max_bridge_length[\s\S]*?def\s*=\s*(\d+)",settings)[1])

cpp=r"""
#include <cstdint>
#include <cstdlib>
#include <cassert>
#include <iostream>
using uint=unsigned;
using Owner=int;
using WaterClass=int;
using DiagDirection=int;
using TileIndex=int;
struct Stored { int id, dir, tt; };
using Tile=Stored *;
const int TRANSPORT_WATER=2, WATER_CLASS_CANAL=1, WATER_CLASS_SEA=0;
const int MP_TUNNELBRIDGE=0, MP_RAILWAY=1, RAIL_GROUND_WATER=0;
constexpr int STR_ERROR_BRIDGE_TOO_LONG=1, DC_QUERY_COST=1;
#define return_cmd_error(n) return -n
#define NOT_REACHED() std::abort()
constexpr int PR_BUILD_AQUEDUCT=0, PR_CLEAR_AQUEDUCT=1;
struct {struct {uint max_bridge_length;} construction;} _settings_game;
constexpr int64_t _price[2]={#BUILD#, #CLEAR#};
struct Company {
 bool is_ai;
 struct {int water;} infrastructure;
};
struct Cost {
 int64_t value=0;
 void AddCost(int64_t x){value+=x;}
};
void MakeBridgeRamp(Tile t,Owner, int catalogue,DiagDirection d,int transport) {
    t->id=catalogue;t->dir=d;t->tt=transport;
}
bool HasTileWaterClass(TileIndex){return false;}
WaterClass GetWaterClass(TileIndex){return -2;}
bool IsTileType(TileIndex,int t){return t==MP_TUNNELBRIDGE;}
int GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_WATER;}
int GetRailGroundType(TileIndex){return RAIL_GROUND_WATER;}
""".replace("#BUILD#",str(build_base)).replace("#CLEAR#",str(clear_base))
cpp+="\n"+"\n".join((factor,make,water,length))
cpp+="\nint64_t plan(uint bridge_len, int flags, Company *c, Owner company, Owner _local_company) {\n"
cpp+=f"""
 {upper}
 bridge_len += 2;
 bool is_new_owner=true;
 {infra}
 Cost cost;
 {query} {{
    {price_fn}
    {build}
 }}
 return cost.value;
}}
int main(){{
 std::cout<<_price[0]<<" "<<_price[1]<<" "<<{max_length}<<" "<<TUNNELBRIDGE_TRACKBIT_FACTOR<<"\\n";
 uint middle;
 int limit,kind,q,local,d;
 while(std::cin>>middle>>limit>>kind>>q>>local>>d){{
   Company comp{{kind==2,{{0}}}};
   Company *c=kind==0?nullptr:&comp;
   _settings_game.construction.max_bridge_length=limit;
   auto price=plan(middle,q?DC_QUERY_COST:0,c,0,local?0:1);
   if(price<0){{std::cout<<price<<"\\n";continue;}}
   Stored tile;
   MakeAqueductBridgeRamp(&tile,0,d);
   int64_t base_cost=0; {remove}
   std::cout<<price<<" "<<(middle+2)*base_cost<<" "<<comp.infrastructure.water<<" "<<tile.id
     <<" "<<tile.dir<<" "<<GetEffectiveWaterClass(0)<<"\\n";
 }}
}}
"""
lua=r"""
local Bridge=dofile("mods/luanttd_core/openttd/road_bridge.lua")(dofile("mods/luanttd_core/openttd/slope.lua"))
local A=dofile("mods/luanttd_core/openttd/aqueduct.lua")(Bridge)
print(table.concat({A.base_prices.aqueduct,A.base_prices.clear_aqueduct,Bridge.default_max_length,A.INFRASTRUCTURE_FACTOR}," "))
for line in io.lines() do
 local n={}; for v in line:gmatch("%d+") do n[#n+1]=tonumber(v) end
 local middle,limit,kind,q,me,d=unpack(n)
 local axis=d%2
 local finish=middle+2
 local t={}
 for i=1,finish do t[i]={kind="clear",base=2,max_z=2,slope=0} end
 t[1].slope=axis==0 and 12 or 9
 t[finish].slope=axis==0 and 3 or 6
 local b={tile=function(i)return t[i] end,
          xy=function(i)return axis==0 and i or 1,axis==1 and i or 1 end,
          id=function(x,z)return axis==0 and x or z end}
 local p,err=A.plan(b,1,finish,{max_length=limit,company=kind~=0,ai=kind==2,query=q==1,local_company=me==1})
 if not p then assert(err=="BRIDGE_TOO_LONG");print(-1)
 else
  local r=A.head_record(p,(d==1 or d==2) and 1 or finish)
  print(table.concat({p.price,A.clear_cost(p),p.water_infrastructure_delta,r.bridge_type,r.dir,r.water_class=="canal" and 1 or 0}," "))
 end
end
"""
cases=[]
for limit in (0,2,13,max_length,511):
    for interior in (0,1,2,3,7,12,13,15,63,64,65,511,512):
        for kind in range(3):
            for query in range(2):
                for local in range(2):
                    for d in range(4):
                        cases.append(f"{interior} {limit} {kind} {query} {local} {d}")
dataset="\n".join(cases)+"\n"
with tempfile.TemporaryDirectory(prefix="aqueduct-source-") as temp:
    path=Path(temp)
    (path/"test.cpp").write_text(cpp)
    (path/"test.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",path/"test.cpp","-o",path/"probe"],check=True)
    ref=subprocess.check_output([path/"probe"],input=dataset,text=True,cwd=ROOT).splitlines()
    actual=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",path/"test.lua"],
                                   input=dataset,text=True,cwd=ROOT).splitlines()
assert len(ref)==len(actual)==len(cases)+1
for i,(a,b) in enumerate(zip(ref,actual)):
    assert a==b,(cases[i-1] if i else "constants",a,b)
print(f"PASS: {len(cases):,} compiled OpenTTD 14.1 water-branch fixtures and aqueduct price/limit constants.")
