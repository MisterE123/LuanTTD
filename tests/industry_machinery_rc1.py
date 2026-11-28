#!/usr/bin/env python3
"""Compile pinned RC1 industry machinery, animation and tile-visit logic."""
from itertools import product
from pathlib import Path
import re
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
end = raw.index("\n}", visit)
tile_switch = raw[visit:end]
shim = r"""
#include <cstdint>
#include <iostream>
using TileIndex=int;
using IndustryGfx=int;
@CONSTANTS@
struct TimerGameTick { static uint64_t counter; };
uint64_t TimerGameTick::counter;
struct { struct { bool ambient=true; } sound; } _settings_client;
int gfx, anim, frame, stage, dirty, sounds, draws, loop, inbound, effect;
constexpr int TILE_SIZE=16;
unsigned r;
enum {SND_0C_POWER_STATION,SND_0B_MINE,SND_2E_BUBBLE_GENERATOR,SND_2D_SUGAR_MINE_1,SND_29_SUGAR_MINE_2,
  SND_30_TOFFEE_QUARRY,SND_2C_TOY_FACTORY_1,SND_2B_TOY_FACTORY_2,SND_2A_TOY_FACTORY_3};
enum {EV_COPPER_MINE_SMOKE,EV_BUBBLE};
struct EffectVehicle{int animation_substate=-1;};
EffectVehicle vehicle;
EffectVehicle* CreateEffectVehicleAbove(int,int,int,int kind){effect=kind;return &vehicle;}
int TileX(TileIndex){return 5;}
int TileY(TileIndex){return 6;}
struct Industry {bool was_cargo_delivered;static Industry* GetByTile(TileIndex);};
Industry firm;
Industry* Industry::GetByTile(TileIndex){return &firm;}
enum class AnimationStatus {NoAnimation};
struct {struct {AnimationStatus status=AnimationStatus::NoAnimation;}animation;} spec;
auto GetIndustryTileSpec(int){return &spec;}
void AnimateNewIndustryTile(TileIndex){}
uint32_t Random(){++draws;return r;}
int GetIndustryAnimationLoop(TileIndex){return loop;}
void SetIndustryAnimationLoop(TileIndex,int n){loop=n;}
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
  while(std::cin>>op>>gfx>>anim>>frame>>stage>>TimerGameTick::counter>>r>>loop>>inbound){
    dirty=sounds=draws=0;effect=-1;vehicle.animation_substate=-1;firm.was_cargo_delivered=inbound;
    if(op==0) Visit(0);
    else if(anim) AnimateTile_Industry(0);
    std::cout<<gfx<<' '<<anim<<' '<<frame<<' '<<stage<<' '<<sounds<<' '<<draws<<' '<<loop<<' '
      <<firm.was_cargo_delivered<<' '<<effect<<' '<<vehicle.animation_substate<<'\n';
  }
}
"""
lua_script = r"""
local M=dofile("mods/luanttd_core/openttd/industry_machinery_rc1.lua")
for line in io.lines() do
 local c={}
 for n in line:gmatch("%d+") do c[#c+1]=tonumber(n) end
 local op,gfx,anim,frame,stage,tick,word,loop,inbound=unpack(c)
 local t={gfx=gfx,animated=anim==1 or nil,animation_frame=frame,stage=stage,completed=true,animation_loop=loop}
 local firm={was_cargo_delivered=inbound==1}
 local draws=0
 local _,sound,fx=(op==0 and M.visit or M.animate)(t,tick,function() draws=draws+1;return word end,firm)
 print(("%d %d %d %d %d %d %d %d %d %d"):format(t.gfx,t.animated and 1 or 0,t.animation_frame,t.stage,sound and 1 or 0,draws,
   t.animation_loop,firm.was_cargo_delivered and 1 or 0,fx and (fx.effect=="bubble" and 1 or 0) or -1,fx and fx.direction or -1))
end
"""
visit_cases = [(0,g,a,f,3,t,r) for g,a,f,t,r in product(
    (0,1,2,10,29,30,31,32,47,48,49,79,88,143,148,155,161,162,165,174),(0,1),(0,6,128,192),(0,1023,1024,2047,2048),
    (0,9361,9362,10921,10922,21844,21845,32767,32768,65535,4294967295))]
animation_cases = [(1,1,1,f,3,t,0) for f,t in product((0x80,0x81,0x82,0xC0,0xC1,0xC2),range(2048))]
animation_cases += [(1,g,a,f,3,t,r) for g,a,t,r in product(
    (10,30,31,32),(0,1),range(16),(0,9361,9362,65535)) for f in range(7 if g == 10 else 4)]
animation_cases += [(1,g,1,f,3,t,0) for g,n in ((143,50),(162,40),(165,70),(174,96)) for f in range(n) for t in range(8)]
animation_cases += [(1,g,1,0,3,t,0) for g,t in product(range(148,156),range(16))]
animation_cases += [(1,g,1,f,3,t,0) for g,f,t in product((48,88),(0x80,0x81,0x82,0xC0,0xC1,0xC2),range(2048))]
cases = [(*r, loop, inbound) for r in visit_cases + animation_cases
         for loop,inbound in ((0,0),(7,1))]
data = "".join(" ".join(map(str, c)) + "\n" for c in cases)
with tempfile.TemporaryDirectory() as folder:
    p = Path(folder)
    header=(source / "src/industry_type.h").read_text()
    constants="enum {"+",".join(f"{k}={n}" for k,n in re.findall(r"IndustryGfx (GFX_\w+) = (\d+);",header))+"};"
    land=(source / "src/table/industry_land.h").read_text()
    toffee=re.search(r"static const uint8_t _industry_anim_offs_toffee\[\] = \{.*?\};",land,re.S)[0]
    code = shim.replace("@CONSTANTS@",constants)+toffee+"\n"+"\n".join(function(n) for n in (
       "AnimatePowerPlantSparks","AnimateOilWell","AnimateMineTower","AnimateSugarSieve","AnimateToffeeQuarry",
       "AnimateBubbleCatcher","AnimateToyFactory","AnimatePlasticFountain","AnimateTile_Industry",
       "TileLoopIndustry_BubbleGenerator"))
    code += "\nvoid Visit(TileIndex tile) {\n" + tile_switch + "\n}\n" + main
    (p / "test.cpp").write_text(code)
    (p / "test.lua").write_text(lua_script)
    subprocess.run(["c++", "-std=c++17", "-O2", str(p / "test.cpp"), "-o", str(p / "oracle")], check=True)
    expected = subprocess.check_output([p / "oracle"], text=True, input=data).splitlines()
    actual = subprocess.check_output([lua, p / "test.lua"], text=True, input=data, cwd=repo).splitlines()
assert len(actual) == len(expected) == len(cases)
for case, a, b in zip(cases, expected, actual):
    assert a == b, (case, a, b)
print(f"PASS {len(cases):,} compiled RC1 machinery animation and tile RNG decisions")
