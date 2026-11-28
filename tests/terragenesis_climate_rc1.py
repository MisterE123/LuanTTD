#!/usr/bin/env python3
"""Pinned RC1 comparison for all four relative-height profiles and climates."""
from hashlib import sha256
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
data=(Path(sys.argv[1])/"src"/"tgp.cpp").read_bytes()
assert sha256(data).hexdigest()=="7af0e4c238be485ed5871235701a79991c302474cb5ae048fca7f5161de8ba0a"
source=data.decode()
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"

def function(name):
    i=source.index(name)
    j=source.index("{",i)
    depth=1
    while depth:
        j+=1
        depth+=(source[j]=="{")-(source[j]=="}")
    return source[i:j+1]

cpp=r"""
#include <cmath>
#include <iostream>
#include <vector>
#include <cstdint>
#include <cstdlib>
#define NOT_REACHED() std::abort()
#define I2H(x) ((x)*16)
using Height=int16_t;
enum class LandscapeType { Temperate, Arctic, Tropic, Toyland };
enum class GenworldAverageHeight { Auto, Lowlands, Normal, Plateaus };
struct {struct {LandscapeType landscape;GenworldAverageHeight average_height;} game_creation;} _settings_game;
struct {std::vector<Height> h;} _height_map;
"""
for label in ("static double SineTransformLowlands","static double SineTransformNormal",
              "static double SineTransformPlateaus","static void HeightMapSineTransform"):
    cpp+=function(label)+"\n"
cpp+=r"""
int main(){
    int climate,average,upper;
    while(std::cin>>climate>>average>>upper){
        _settings_game.game_creation.landscape=LandscapeType(climate);
        _settings_game.game_creation.average_height=GenworldAverageHeight(average);
        _height_map.h.resize(upper);
        for(int h=0;h<upper;h++) _height_map.h[h]=h;
        HeightMapSineTransform(16,upper);
        for(Height h:_height_map.h) std::cout<<h<<" ";
        std::cout<<"\n";
    }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."terragenesis.lua")(dofile(p.."slope.lua"))
local landscapes={"temperate","arctic","tropic","toyland"}
local averages={"auto","lowlands","normal","plateaus"}
for line in io.lines() do
  local climate,average,upper=line:match("(%d+) (%d+) (%d+)")
  local lut=G.sine_lut(tonumber(upper),landscapes[tonumber(climate)+1],averages[tonumber(average)+1])
  for i=0,tonumber(upper)-1 do io.write(lut[i]," ") end
  io.write("\n")
end
-- Mount the new dispatch in the complete ordinary TGP raster, not just
-- standalone LUTs. With a stock automatic profile, Arctic is Plateaus,
-- Tropic is Lowlands. Each must have the same RNG as its explicit profile.
local function sample(climate,average)
  return G.generate({seed=49832,width=64,depth=64,terrain_type=3,
    landscape=climate,average_height=average,rng_state=G.startup_rng(49832)})
end
local t=sample("temperate","auto")
for _,case in ipairs{{"arctic","plateaus"},{"tropic","lowlands"},{"toyland","normal"}} do
  local a,b=sample(case[1],"auto"),sample("temperate",case[2])
  local changed=0
  for z=1,a.depth do for x=1,a.width do
    assert(a.corner(x,z)==b.corner(x,z) and a.tile(x,z)==b.tile(x,z))
    if a.corner(x,z)~=t.corner(x,z) then changed=changed+1 end
  end end
  assert((changed>0)==(case[1]~="toyland"))
  for i=1,2 do assert(a.rng_after[i]==b.rng_after[i]) end
  assert(a.base_id~=t.base_id and b.base_id~=t.base_id)
end
"""
heights=[17,20,31,32,47,64,87,127,128,255,256,383,512,777,1024,1536,2048,4096]
rows=[(c,a,h) for c in range(4) for a in range(4) for h in heights]
inputs="\n".join(" ".join(map(str,r)) for r in rows)+"\n"
with tempfile.TemporaryDirectory(prefix="luanttd-rc1-tgp-climate-") as tmp:
    d=Path(tmp)
    (d/"ref.cc").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cc","-o",d/"ref"],check=True)
    ref=subprocess.check_output([d/"ref"],text=True,input=inputs).splitlines()
    got=subprocess.check_output([lua,d/"test.lua"],cwd=root,text=True,input=inputs).splitlines()
    assert len(ref)==len(got)==len(rows)
    for r,a,b in zip(rows,ref,got):
        av,bv=a.split(),b.split()
        assert len(av)==len(bv)==r[2]
        for i,(x,y) in enumerate(zip(av,bv)):
            assert x==y,(r,i,x,y)
print(f"PASS {len(rows)} RC1 climate/average relief profiles and {16*sum(heights)} exact fixed-point heights")
