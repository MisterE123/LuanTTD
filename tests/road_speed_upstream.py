#!/usr/bin/env python3
"""Compile the unmodified stock speed methods and compare the Lua port."""
from pathlib import Path
import argparse
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CPP = r'''
#include <algorithm>
#include <cstdint>
#include <cstdio>
using uint = unsigned;
using byte = std::uint8_t;
__DISTANCES__
struct Vehicle {
  int direction, cur_speed, progress, subspeed;
  __BASE_METHODS__
  __DYNAMIC_METHOD__
};
int main() {
  int dir, speed, sub, progress, accel, lo, hi;
  while (std::scanf("%d%d%d%d%d%d%d",&dir,&speed,&sub,&progress,&accel,&lo,&hi)==7) {
    Vehicle v{dir,speed,progress,sub};
    auto d=v.GetAdvanceDistance(), n=v.DoUpdateSpeed(accel,lo,hi);
    std::printf("%u,%u,%d,%d,%d\n",d,n,v.cur_speed,v.subspeed,v.progress);
  }
}
'''
LUA = '''
local M=dofile("mods/bayline/openttd/road_speed.lua")
for line in io.lines() do
  local a={}
  for n in line:gmatch("-?%d+") do a[#a+1]=tonumber(n) end
  local v={heading=a[1],speed=a[2],subspeed=a[3],progress=a[4]}
  local n=M.update(v,a[5],a[6],a[7])
  print(table.concat({M.advance_distance(v.heading),n,v.speed,v.subspeed,v.progress},","))
end
local r={heading=3,speed=111,subspeed=0,progress=180}
assert(M.tick(r,112,false,function(v) v.speed=0;return false end))
assert(r.progress==191 and r.speed==0)
assert(not M.tick(r,112,false,function(v) v.heading=2;return true end))
assert(r.progress==191) -- 191 + floor(1*.75) is not yet enough
assert(not M.tick(r,112,false,function(v) v.heading=2;M.turn(v);return true end))
assert(r.speed==2 and r.progress==0)
M.grade(r,0,8,112); assert(r.speed==1)
M.grade(r,8,0,112); assert(r.speed==3)
'''
def extract(src, signature):
    i=src.index(signature)
    j=src.index("\n\t}",i)+3
    return src[i:j]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    base=(a.source/"vehicle_base.h").read_text()
    ground=(a.source/"ground_vehicle.hpp").read_text()
    lengths="\n".join(line for line in base.splitlines()
                       if line.startswith(("const uint TILE_AXIAL_DISTANCE","const uint TILE_CORNER_DISTANCE")))
    methods="\n".join(extract(base,s) for s in ("static inline uint GetAdvanceSpeed(","inline uint GetAdvanceDistance("))
    shim=CPP.replace("__DISTANCES__",lengths).replace("__BASE_METHODS__",methods).replace("__DYNAMIC_METHOD__",extract(ground,"inline uint DoUpdateSpeed("))
    rng=random.Random(141)
    rows=[]
    for i in range(24000):
        rows.append("%d %d %d %d %d %d %d\n"%(i%8,rng.randrange(0,600),rng.randrange(256),
                    rng.randrange(256),rng.randrange(-4096,4096),rng.randrange(5),rng.randrange(1,500)))
    cases="".join(rows).encode()
    with tempfile.TemporaryDirectory() as d:
        tmp=Path(d)
        (tmp/"reference.cpp").write_text(shim)
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["c++","-O2","-std=c++17",str(tmp/"reference.cpp"),"-o",str(tmp/"reference")],check=True)
        expected=subprocess.check_output([str(tmp/"reference")],input=cases)
        actual=subprocess.check_output([a.lua,str(tmp/"port.lua")],cwd=ROOT,input=cases)
    assert expected==actual
    print(f"PASS: {len(rows):,} stock speed/subspeed and progress updates; blocked restart, turn and grade fixtures.")
if __name__=="__main__":
    main()
