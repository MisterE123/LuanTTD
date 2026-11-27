#!/usr/bin/env python3
"""Compile exact RC1 GrowTown/GenRandomRoadBits for the no-existing-street path."""
from hashlib import sha256
from pathlib import Path
from random import Random
import os
import subprocess
import sys
from tempfile import TemporaryDirectory

from rc1_rail_foundation_shim import source_block

src = Path(sys.argv[1]) / "src"
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert sha256((src / "town_cmd.cpp").read_bytes()).hexdigest() == (
    "9483d2c1b188f62241de9a4aef682db940592eb7bf0b40086c4af7b7da77a7e0"
)
cpp = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
using TownExpandModes=bool;
struct TileIndexDiffC {int x,y;};
int ToTileIndexDiff(TileIndexDiffC d){return d.x+d.y*64;}
int TileAdd(int tile,int diff){return tile+diff;}
enum class RoadBit{NW};
struct RoadBits {
    uint n;
    RoadBits(uint n):n(n){}
    RoadBits(RoadBit):n(1){}
    bool Any()const{return n!=0;}
    uint base()const{return n;}
};
enum class TileType{House};
enum class Commands{LandscapeClear,BuildRoad};
enum class DoCommandFlag{Auto,NoWater,Execute};
struct Cost {bool okay;bool Succeeded()const{return okay;}};
struct Town{TileIndex xy;int index;};
int _current_company=1;
constexpr int OWNER_TOWN=2;
struct AutoRestoreBackup {
    int &slot,value;
    AutoRestoreBackup(int &i,int x):slot(i),value(i){i=x;}
    ~AutoRestoreBackup(){slot=value;}
};
using RoadType=int;
int GetTownRoadType(){return 0;}
constexpr int center=32+32*64;
std::array<int,4096> board;
int result,bits,draws;
uint32_t word;
uint32_t Random(){draws++;return word;}
uint GB(uint32_t r,int offset,int count){return (r>>offset)&((1u<<count)-1);}
bool IsTileType(TileIndex t,TileType type){assert(type==TileType::House);return board[t]==3;}
bool IsTileFlat(TileIndex t){return board[t]!=1;}
bool TownAllowedToBuildRoads(TownExpandModes r){return r;}
RoadBits GetTownRoadBits(TileIndex){return 0;} // no street connected to any of the search coordinates
bool GrowTownAtRoad(Town *,TileIndex,TownExpandModes){assert(false);return false;}
template<Commands c> struct Command{
    static Cost Do(std::initializer_list<DoCommandFlag> flags,TileIndex tile,RoadBits rb=0,
            RoadType type=0,int=0,int=0) {
        assert(_current_company==OWNER_TOWN);
        if constexpr(c==Commands::BuildRoad){
            assert(type==0 && *flags.begin()==DoCommandFlag::Execute);
            result=tile;bits=rb.base();return {true};
        } else {
            assert(*flags.begin()==DoCommandFlag::Auto && *(flags.begin()+1)==DoCommandFlag::NoWater);
            return {board[tile]==0 || board[tile]==2};
        }
    }
};
"""
cpp += source_block(src, "town_cmd.cpp", r"^static RoadBits GenRandomRoadBits")
cpp += source_block(src, "town_cmd.cpp", r"^static bool GrowTown[(]Town [*]t, TownExpandModes modes[)]$")
cpp += r"""
int main(){
    int allow,count,dx,dz,kind;
    while(std::cin>>allow>>word>>count){
        board.fill(4);
        for(int i=0;i<count;i++){std::cin>>dx>>dz>>kind;board[center+dx+64*dz]=kind;}
        Town t{center,1};
        result=center;bits=0;draws=0;
        const bool ok=GrowTown(&t,allow);
        assert(_current_company==1);
        std::cout<<ok<<" "<<(result%64-32)<<" "<<(result/64-32)<<" "<<bits<<" "<<draws<<"\n";
    }
}
"""
program = r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local B=dofile(p.."town_growth_build.lua")(G,{})
local kind={[0]="clear","clear","trees","house","water","clear","industry"}
local water={slope=0,kind="water"}
local function key(x,z) return x+64*z end
for line in io.lines() do
  local a={}
  for word in line:gmatch("%S+") do a[#a+1]=tonumber(word) end
  local cells={}
  for pos=4,#a,3 do
    local k=a[pos+2]
    cells[key(a[pos],a[pos+1])]={kind=kind[k],slope=k==1 and 3 or 0,owner=k==5 and "Private" or nil}
  end
  local function tile(x,z) return cells[key(x,z)] or water end
  local function clear(x,z)
    local t=tile(x,z)
    return not t.owner and (t.kind=="clear" or t.kind=="trees")
  end
  local draws=0
  local b={tile=tile,seed_road_clear_quote=clear,road_quote=function(_,x,z,bits)
    assert(clear(x,z) and bits>0);return {bits=bits}
  end}
  local plan=B.grow(G.new(1,0,0),b,{allow_roads=a[1]==1,year=1950},function()
    draws=draws+1;return a[2]
  end)
  print(plan and 1 or 0,plan and plan.x or 0,plan and plan.z or 0,plan and plan.bits or 0,draws)
end
"""
rng = Random(16002)
rows = []
for i in range(8192):
    cells = [(x,z,rng.randrange(7)) for z in range(-2,3) for x in range(-2,3)]
    rows.append([int(i % 13 != 0), rng.getrandbits(32), len(cells), *(v for c in cells for v in c)])
data = "".join(" ".join(map(str, r)) + "\n" for r in rows)
with TemporaryDirectory(prefix="town-reseed-rc1-") as d:
    d = Path(d)
    (d / "ref.cpp").write_text(cpp)
    (d / "test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX", "c++"), "-std=c++20", "-O2", d/"ref.cpp", "-o", d/"ref"], check=True)
    outputs = [subprocess.check_output(cmd, input=data, text=True).splitlines()
               for cmd in [[d/"ref"], [lua,d/"test.lua"]]]
    assert len(outputs[0]) == len(outputs[1]) == len(rows)
    for i,(a,b) in enumerate(zip(*outputs)):
        assert a.split() == b.split(), (i, rows[i], a, b)
print(f"PASS {len(rows)} RC1 roadless town choices, ordered clear quotes, road masks and RNG counts")
