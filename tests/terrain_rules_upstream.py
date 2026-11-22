#!/usr/bin/env python3
"""Compile the pinned OpenTTD 14.1 standalone corner-mutation functions and compare Lua.

Usage: python3 tests/terrain_rules_upstream.py /path/to/OpenTTD [lua5.1]
Use either the OpenTTD repository root or a directory containing terraform_cmd.cpp.
The surrounding grid/economy shim is a test fixture, not an engine port.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
path = Path(sys.argv[1]) / "src" / "terraform_cmd.cpp"
if not path.exists():
    path = Path(sys.argv[1]) / "terraform_cmd.cpp"
source = path.read_bytes()
assert sha256(source).hexdigest() == "1390a6fffa9ff9f4cec1b2845b3dc1ca465384d1a641a239744c558c51daa012"
source = source.decode()

def block(pattern):
    start = re.search(pattern, source, re.MULTILINE).start()
    at = source.index("{", start)
    depth = 1
    while depth:
        at += 1
        depth += (source[at] == "{") - (source[at] == "}")
    return source[start:at + 1]

base = r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <set>
#include <tuple>
#include <vector>
using TileIndex = uint32_t;
constexpr TileIndex INVALID_TILE=UINT_MAX;
constexpr int STR_ERROR_ALREADY_AT_SEA_LEVEL=1, STR_ERROR_TOO_HIGH=2, STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP=3;
constexpr int EXPENSES_CONSTRUCTION=6, PR_TERRAFORM=0;
struct CommandCost {
  int error=0, cost=0;
  CommandCost(int n): error(n==EXPENSES_CONSTRUCTION?0:n) {}
  bool Failed() const {return error!=0;}
  void AddCost(int n) {cost+=n;}
  void AddCost(CommandCost n) {cost+=n.cost;}
};
const CommandCost CMD_ERROR(4);
using TileIndexSet=std::set<TileIndex>;
using TileIndexToHeightMap=std::map<TileIndex,int>;
struct Settings {struct Construction {int map_height_limit; bool freeform_edges;} construction;} _settings_game;
int _price[1];
uint32_t width,depth;
struct Map {
 static uint32_t SizeX() {return width;}
 static uint32_t SizeY() {return depth;}
 static uint32_t MaxX() {return width-1;}
 static uint32_t MaxY() {return depth-1;}
 static uint32_t Size() {return width*depth;}
};
std::vector<int> levels;
int TileHeight(TileIndex t) {return levels.at(t);}
uint32_t TileX(TileIndex t) {return t%width;}
uint32_t TileY(TileIndex t) {return t/width;}
uint32_t TileXY(int x,int y) {return y*width+x;}
uint32_t Delta(uint32_t a,uint32_t b) {return a>b?a-b:b-a;}
int TileDiffXY(int x,int y) {return y*(int)width+x;}
struct TileIndexDiffC {int x,y;};
int ToTileIndexDiff(TileIndexDiffC d){return TileDiffXY(d.x,d.y);}
template <typename T,std::size_t I> const T *endof(const T (&t)[I]) {return t+I;}
"""
for declaration in [
    r"^struct TerraformerState", r"^static int TerraformGetHeightOfTile",
    r"^static void TerraformSetHeightOfTile", r"^static void TerraformAddDirtyTile\(",
    r"^static void TerraformAddDirtyTileAround", r"^static std::tuple<CommandCost, TileIndex> TerraformTileHeight",
]:
    base += block(declaration) + (";\n" if "struct " in declaration else "\n")

base += r"""
int main(){
  int x,z,mask,direction,freeform,max_height,price;
  while (std::cin>>width>>depth>>x>>z>>mask>>direction>>freeform>>max_height>>price) {
    levels.resize(Map::Size());
    for (auto &h:levels) std::cin>>h;
    _settings_game.construction={max_height,freeform!=0};
    _price[PR_TERRAFORM]=price;
    TerraformerState ts;
    CommandCost result(EXPENSES_CONSTRUCTION);
    TileIndex err_tile=INVALID_TILE;
    for (int i=0;i<4;i++) {
      if (!(mask&(1<<i))) continue;
      const int dx[]={1,1,0,0}, dz[]={0,1,1,0};
      auto t=TileXY(x+dx[i],z+dz[i]);
      auto [cost,err]=TerraformTileHeight(&ts,t,TileHeight(t)+direction);
      if (cost.Failed()) {result=cost; err_tile=err;break;}
      result.AddCost(cost);
    }
    if(result.Failed()) {
      std::cout<<result.error;
      if (err_tile!=INVALID_TILE) std::cout<<" "<<TileX(err_tile)+1<<" "<<TileY(err_tile)+1;
      std::cout<<"\n";
    } else {
      std::cout<<"0 "<<result.cost;
      for (auto [t,h]:ts.tile_to_new_height) std::cout<<" "<<TileX(t)+1<<":"<<TileY(t)+1<<":"<<h;
      std::cout<<" |";
      for (auto t:ts.dirty_tiles) {
        if(TileX(t)==Map::MaxX()||TileY(t)==Map::MaxY()) continue; // void far edge, absent from our rendered tile domain
        std::cout<<" "<<TileX(t)+1<<":"<<TileY(t)+1;
      }
      std::cout<<"\n";
    }
  }
}
"""

lua = """
local T=dofile('mods/bayline/openttd/terrain.lua')
local code={ALREADY_AT_SEA_LEVEL=1,TOO_HIGH=2,TOO_CLOSE_TO_EDGE=3,NO_EFFECT=4}
for line in io.lines() do
  local a={}
  for n in line:gmatch('-?%d+') do a[#a+1]=tonumber(n) end
  local w,d,x,z,s,direction,freeform,limit,price=unpack(a,1,9)
  local g=T.new(w-1,d-1,function(cx,cz) return a[9+(cz-1)*w+cx] end,
    {max_height=limit,unit_cost=price,freeform_edges=freeform==1})
  local plan,err,ex,ez=T.plan(g,x+1,z+1,s,direction==1)
  if plan then
    local s={'0',plan.cost}
    for _,item in ipairs(plan.changes) do s[#s+1]=item.x..':'..item.z..':'..item.height end
    s[#s+1]='|'
    for _,item in ipairs(plan.dirty) do s[#s+1]=item.x..':'..item.z end
    print(table.concat(s,' '))
  else
    print(ex and (code[err]..' '..ex..' '..ez) or code[err])
  end
end
"""
rng = random.Random(141)
samples = []
for _ in range(800):
    w, d = rng.randrange(4, 11), rng.randrange(4, 11)
    limit = rng.randrange(2, 9)
    peaks = [(rng.randrange(w), rng.randrange(d), rng.randrange(limit + 1)) for _ in range(3)]
    x, z = rng.randrange(w - 1), rng.randrange(d - 1)
    mask, direction, ff = rng.randrange(1,16), rng.choice([-1,1]), rng.randrange(2)
    heights = [max(0, *(p - abs(px - a) - abs(pz - b) for px,pz,p in peaks)) for b in range(d) for a in range(w)]
    samples.append(" ".join(map(str,[w,d,x,z,mask,direction,ff,limit,rng.randrange(1,161)] + heights)))
data = ("\n".join(samples) + "\n").encode()
with tempfile.TemporaryDirectory() as tmp:
    t = Path(tmp)
    (t/"reference.cpp").write_text(base)
    (t/"adapter.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",str(t/"reference.cpp"),"-o",str(t/"reference")],check=True)
    ref = subprocess.run([str(t/"reference")],input=data,capture_output=True,check=True).stdout.decode().splitlines()
    dst = subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(t/"adapter.lua")],
                         input=data,capture_output=True,check=True,cwd=root).stdout.decode().splitlines()
    assert len(ref) == len(dst) == len(samples)
    for i,(expected,actual) in enumerate(zip(ref,dst)):
        assert expected==actual, (i,samples[i],expected,actual)
    print(f"PASS: {len(samples)} differential corner terraform cases vs OpenTTD 14.1 (height, cost, dirty tiles, rejections)")
