#!/usr/bin/env python3
"""Compile the pinned RC1 mine, power sparks and oil animation logic."""
from itertools import product
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert subprocess.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
raw = (source / "src/industry_cmd.cpp").read_text()

def function(name):
    i = raw.index("static void " + name + "(")
    return raw[i:raw.index("\n}", i) + 2]

visit = raw.index("IndustryGfx gfx = GetIndustryGfx(tile);", raw.index("static void TileLoop_Industry("))
end = raw.index("\n\tcase GFX_COPPER_MINE_CHIMNEY:", visit)
tile_switch = raw[visit:end]
shim = r"""
#include <cstdint>
#include <iostream>
using TileIndex=int;
using IndustryGfx=int;
enum {
  GFX_COAL_MINE_TOWER_NOT_ANIMATED=0,GFX_COAL_MINE_TOWER_ANIMATED=1,
  GFX_POWERPLANT_SPARKS=10,GFX_OILWELL_NOT_ANIMATED=29,
  GFX_OILWELL_ANIMATED_1=30,GFX_OILWELL_ANIMATED_3=32,
  GFX_COPPER_MINE_TOWER_NOT_ANIMATED=80,GFX_COPPER_MINE_TOWER_ANIMATED=81,
  GFX_GOLD_MINE_TOWER_NOT_ANIMATED=82,GFX_GOLD_MINE_TOWER_ANIMATED=83
};
struct TimerGameTick { static uint64_t counter; };
uint64_t TimerGameTick::counter;
struct { struct { bool ambient=true; } sound; } _settings_client;
int gfx, anim, frame, stage, dirty, sounds, draws;
unsigned r;
enum {SND_0C_POWER_STATION,SND_0B_MINE};
void SndPlayTileFx(int,TileIndex){++sounds;}
int GetIndustryGfx(TileIndex){return gfx;}
void SetIndustryGfx(TileIndex,int g){gfx=g;}
int GetAnimationFrame(TileIndex){return frame;}
void SetAnimationFrame(TileIndex,int f){frame=f;}
void SetIndustryConstructionStage(TileIndex,int s){stage=s;}
void SetIndustryCompleted(TileIndex){}
void AddAnimatedTile(TileIndex){anim=1;}
void DeleteAnimatedTile(TileIndex){anim=0;}
void MarkTileDirtyByTile(TileIndex){++dirty;}
bool Chance16(int n,int d) {++draws;return ((r&65535)*d+d/2)/65536<n;}
"""
main = r"""
int main() {
  int op;
  while(std::cin>>op>>gfx>>anim>>frame>>stage>>TimerGameTick::counter>>r){
    dirty=sounds=draws=0;
    if(op==0) Visit(0);
    else if(anim) {
      if(gfx==GFX_COAL_MINE_TOWER_ANIMATED) AnimateMineTower(0);
      else if(gfx==GFX_POWERPLANT_SPARKS && TimerGameTick::counter%4==0) AnimatePowerPlantSparks(0);
      else if(gfx>=GFX_OILWELL_ANIMATED_1 && gfx<=GFX_OILWELL_ANIMATED_3 &&
              TimerGameTick::counter%8==0) AnimateOilWell(0,gfx);
    }
    std::cout<<gfx<<' '<<anim<<' '<<frame<<' '<<stage<<' '<<sounds<<' '<<draws<<'\n';
  }
}
"""
lua_script = r"""
local M=dofile("mods/luanttd_core/openttd/industry_machinery_rc1.lua")
for line in io.lines() do
 local c={}
 for n in line:gmatch("%d+") do c[#c+1]=tonumber(n) end
 local op,gfx,anim,frame,stage,tick,word=unpack(c)
 local t={gfx=gfx,animated=anim==1 or nil,animation_frame=frame,stage=stage,completed=true}
 local draws=0
 local _,sound=(op==0 and M.visit or M.animate)(t,tick,function() draws=draws+1;return word end)
 print(("%d %d %d %d %d %d"):format(t.gfx,t.animated and 1 or 0,t.animation_frame,t.stage,sound and 1 or 0,draws))
end
"""
visit_cases = [(0,g,a,f,3,t,r) for g,a,f,t,r in product(
    (0,1,2,10,29,30,31,32),(0,1),(0,6,128,192),(0,1023,1024,2047,2048),
    (0,9361,9362,10921,10922,21844,21845,32767,32768,65535,4294967295))]
animation_cases = [(1,1,1,f,3,t,0) for f,t in product((0x80,0x81,0x82,0xC0,0xC1,0xC2),range(2048))]
animation_cases += [(1,g,a,f,3,t,r) for g,a,t,r in product(
    (10,30,31,32),(0,1),range(16),(0,9361,9362,65535)) for f in range(7 if g == 10 else 4)]
cases = visit_cases + animation_cases
data = "".join(" ".join(map(str, c)) + "\n" for c in cases)
with tempfile.TemporaryDirectory() as folder:
    p = Path(folder)
    code = shim + "\n".join(function(n) for n in ("AnimatePowerPlantSparks","AnimateOilWell","AnimateMineTower"))
    code += "\nvoid Visit(TileIndex tile) {\n" + tile_switch + "\n default: break;\n}\n}\n" + main
    (p / "test.cpp").write_text(code)
    (p / "test.lua").write_text(lua_script)
    subprocess.run(["c++", "-std=c++17", "-O2", str(p / "test.cpp"), "-o", str(p / "oracle")], check=True)
    expected = subprocess.check_output([p / "oracle"], text=True, input=data).splitlines()
    actual = subprocess.check_output([lua, p / "test.lua"], text=True, input=data, cwd=repo).splitlines()
assert len(actual) == len(expected) == len(cases)
for case, a, b in zip(cases, expected, actual):
    assert a == b, (case, a, b)
print(f"PASS {len(cases):,} compiled RC1 mine, power sparks, oil animation and tile RNG decisions")
