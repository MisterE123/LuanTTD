#!/usr/bin/env python3
"""Compare ordinary ClearTile_Water and TerraformTile_Water to OpenTTD 14.1.

Compile the hash-pinned water and coast branches, the whole Terraform
entry point, and the stock IsInsideMM helper. Excludes structure
branches, which have their own authority and are not ordinary water.
"""
from hashlib import sha256
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
import tempfile

repo=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def get(n, digest):
    options=(src/"src"/n, src/n, src/Path(n).name)
    p=next(p for p in options if p.is_file())
    data=p.read_bytes()
    assert sha256(data).hexdigest()==digest,p
    return data.decode()


def block(code, setup):
    a=code.index(setup)
    b=code.index("{",a)
    level=1
    while level:
        b+=1
        level+=(code[b]=="{")-(code[b]=="}")
    return code[a:b+1]


water=get("water_cmd.cpp","f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847")
prices=get("table/pricebase.h","17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356")
limits=get("core/math_func.hpp","96557de406ae7c7252b607dfcfe3fb7711b1e591199d2196c12fb84eaefc7773")
inside=block(limits,"constexpr bool IsInsideMM(")
ordinary=water[water.index("static CommandCost ClearTile_Water("):water.index("\n\t\tcase WATER_TILE_LOCK:",water.index("static CommandCost ClearTile_Water("))]
p=[int(re.search(r"{\s*(\d+),[^\n]*///< PR_CLEAR_"+k+r"\b",prices).group(1)) for k in ("WATER","CANAL","ROUGH")]
prefix=r'''
#include <cassert>
#include <iostream>
#include <cstddef>
#include <type_traits>
struct StrongTypedefBase{};
using TileIndex=unsigned; using Owner=int; using Money=int; using Slope=int;
using DoCommandFlag=unsigned;
enum {WATER_TILE_CLEAR,WATER_TILE_COAST,EXPENSES_CONSTRUCTION};
enum {OWNER_NONE,OWNER_WATER,OWNER_LOCAL,OWNER_OTHER};
enum {STR_ERROR_CAN_T_BUILD_ON_WATER=1,STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP,
      STR_ERROR_VEHICLE,STR_ERROR_OWNER,STR_ERROR_MUST_DEMOLISH_CANAL_FIRST};
constexpr DoCommandFlag DC_NO_WATER=1,DC_EXEC=2;
enum {PR_CLEAR_WATER,PR_CLEAR_CANAL,PR_CLEAR_ROUGH};
struct CommandCost{
  int value; int error;
  CommandCost(int expense=0,int value=0):value(value),error(0){}
  bool Failed() const {return error!=0;}
};
CommandCost CommandError(int error){CommandCost c;c.error=error;return c;}
#define return_cmd_error(error) return CommandError(error)
struct Map {static size_t MaxX(){return 63;} static size_t MaxY(){return 63;}};
struct Settings { struct Team {bool freeform_edges;} construction; } _settings_game;
struct Company {
 struct{int water=4;} infrastructure;
 static bool IsValidID(Owner who){return who==OWNER_LOCAL||who==OWNER_OTHER;}
 static Company* Get(Owner);
};
Company company;
Company* Company::Get(Owner){return &company;}
struct Case {int kind,slope,x,z,owned,busy;} row;
int cleared,touched;
bool IsCanal(TileIndex){return row.kind==2;}
bool IsWaterTile(TileIndex){return row.kind!=3;}
int GetWaterTileType(TileIndex){return row.kind==3?WATER_TILE_COAST:WATER_TILE_CLEAR;}
int TileX(TileIndex){return row.x;}
int TileY(TileIndex){return row.z;}
int GetTileSlope(TileIndex){return row.slope;}
bool IsSlopeWithOneCornerRaised(int s){return s==1||s==2||s==4||s==8;}
CommandCost EnsureNoVehicleOnGround(TileIndex){
  return row.busy?CommandError(STR_ERROR_VEHICLE):CommandCost{};
}
Owner GetTileOwner(TileIndex){return row.owned;}
CommandCost CheckTileOwnership(TileIndex){
  return row.owned==OWNER_LOCAL?CommandCost{}:CommandError(STR_ERROR_OWNER);
}
void DirtyCompanyInfrastructureWindows(Owner){}
void DoClearSquare(TileIndex){cleared++;}
void MarkCanalsAndRiversAroundDirty(TileIndex){touched++;}
'''
tail=r'''
enum {CMD_LANDSCAPE_CLEAR};
template<int K> struct Command{
  static CommandCost Do(DoCommandFlag flags,TileIndex tile){return ClearTile_Water(tile,flags);}
};
'''
cpp=prefix+f"const int _price[]={{ {','.join(map(str,p))} }};\n"+"template <typename T> "+inside+"\n"+ordinary+'''\n default: assert(false); return {};\n}\n}\n'''+tail+block(water,"static CommandCost TerraformTile_Water(")+r'''
int main(){
  int free,flags,terraform;
  while(std::cin>>row.kind>>row.slope>>row.x>>row.z>>row.owned>>row.busy>>free>>flags>>terraform){
    _settings_game.construction.freeform_edges=free!=0;
    cleared=touched=0;company.infrastructure.water=4;
    auto quote=terraform?TerraformTile_Water(0,flags,0,0):ClearTile_Water(0,flags);
    std::cout<<(quote.error?-quote.error:quote.value)<<' '<<cleared<<' '<<touched<<' '<<company.infrastructure.water<<'\n';
  }
}
'''
program=r'''
local F=dofile("mods/luanttd_core/openttd/water_flood.lua")
local cls={[0]="sea","river","canal","coast"}
local owners={[0]="none","water","own","other"}
local code={CAN_T_BUILD_ON_WATER=1,TOO_CLOSE_TO_EDGE_OF_MAP=2,VEHICLE_IN_THE_WAY=3,OWNED_BY_ANOTHER=4,
 MUST_DEMOLISH_CANAL_FIRST=5}
for line in io.lines() do
 local a={}
 for e in line:gmatch("%S+") do a[#a+1]=tonumber(e) end
 local k,s,x,z,own,busy,free,flags,terra=unpack(a)
 local opt={owner="own",no_water=flags%2==1,clear_allowed=free==1 or x>=1 and x<62 and z>=1 and z<62}
 local cmd=terra==1 and F.terraform_water or F.clear_water
 -- For a natural river, this historical 14.1 fixture covers the
 -- ordinary clear path only. Its terraform result is identical to
 -- clear, unlike the version-pinned RC1 comparator.
 if k==1 then cmd=F.clear_water end
 local n,why=cmd({kind=cls[k],slope=s,owner=owners[own],occupied=busy==1},opt)
 local exec=n and flags>=2 and 1 or 0
 local account=4-(k==2 and own==2 and exec or 0)
 io.write(table.concat({n or -assert(code[why]),exec,exec,account}," "),"\n")
end
'''
rows=[]
for kind in range(4):
    for data in product([0,1,2,3,4,6,8,9,12,23] if kind in (1,3) else [0],
                        (0,1,2,61,62,63),(0,1,61,62),range(4),range(2),range(2),range(4),range(2)):
        rows.append(" ".join(map(str,(kind,)+data)))
inp="\n".join(rows)+"\n"
with tempfile.TemporaryDirectory() as d:
    case=Path(d)
    (case/"stock.cpp").write_text(cpp)
    (case/"stock.lua").write_text(program)
    subprocess.run(["c++","-std=c++17","-O2",str(case/"stock.cpp"),"-o",str(case/"stock")],check=True)
    expected=subprocess.check_output([str(case/"stock")],input=inp,text=True,cwd=repo).splitlines()
    observed=subprocess.check_output([lua,str(case/"stock.lua")],input=inp,text=True,cwd=repo).splitlines()
    assert len(rows)==len(expected)==len(observed)
    for data,e,o in zip(rows,expected,observed):
        assert e==o,(data,e,o)
print(f"PASS: {len(rows):,} pinned OpenTTD 14.1 ordinary water/shore clear and terraform cases")
