#!/usr/bin/env python3
"""Test the stock road-vehicle proximity predicate and blocked-turn behavior."""
from pathlib import Path
import argparse
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHIM = r'''
#include <cstdint>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <vector>
using uint=unsigned int;
using Direction=int;
enum {VEH_ROAD,VEH_TRAIN,RVSB_WORMHOLE=255};
struct Vehicle {
  int index=0,x_pos=0,y_pos=0,z_pos=0,direction=0,type=VEH_ROAD;
  int chain=0; bool depot=false;
  bool IsInDepot() const { return depot; }
  const Vehicle* First() const { return reinterpret_cast<const Vehicle*>(std::uintptr_t(chain)); }
};
struct RoadVehicle : Vehicle {
  int reverse_ctr=0,blocked_ctr=0,state=0,tile=0;
  RoadVehicle *First() {return this;}
  static RoadVehicle* From(Vehicle *v){return static_cast<RoadVehicle*>(v);}
};
std::vector<RoadVehicle> candidates;
using Func=Vehicle*(*)(Vehicle*,void*);
static void FindVehicleOnPosXY(int x,int y,void* d,Func cb) {
  for (auto &v:candidates) cb(&v,d);
}
static void FindVehicleOnPos(int tile,void* d,Func cb) {}
static int GetOtherTunnelBridgeEnd(int tile) {return 0;}
'''
DRIVER = r'''
int main() {
  int x,y,h,u,n;
  RoadVehicle v;
  while (std::scanf("%d%d%d%d%d%d%d%d",&x,&y,&v.z_pos,&h,&v.reverse_ctr,&v.blocked_ctr,&u,&n)==8) {
    v.chain=1;
    candidates.assign(n,{});
    for (auto& o:candidates) {
      int in_depot;
      if (std::scanf("%d%d%d%d%d%d%d%d",&o.index,&o.x_pos,&o.y_pos,&o.z_pos,&o.direction,&o.type,&o.chain,&in_depot)!=8) return 2;
      o.depot=in_depot;
    }
    auto* leader=RoadVehFindCloseTo(&v,x,y,h,u);
    std::printf("%d,%d\n",leader?leader->index:-1,v.blocked_ctr);
  }
}
'''
LUA = '''
local P=dofile("mods/luanttd_core/openttd/road_proximity.lua")
local function get()
  local str=io.read()
  if not str then return end
  local out={}
  for n in str:gmatch("-?%d+") do out[#out+1]=tonumber(n) end
  return unpack(out)
end
while true do
  local x,y,z,d,r,b,u,n=get()
  if not x then break end
  local list={}
  for i=1,n do
    local id,a,c,j,h,t,chain,dep=get()
    list[i]={id=id,x=a,y=c,z=j,direction=h,type=t==0 and "road" or "rail",first=chain,in_depot=dep==1}
  end
  local v={reverse_ctr=r,blocked_ctr=b,first=1,z=z}
  local o=P.find(v,v,x,y,d,list,u==1)
  print((o and o.id or -1)..","..v.blocked_ctr)
end
'''
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    src=(a.source/"roadveh_cmd.cpp").read_text()
    start=src.index("struct RoadVehFindData {")
    end=src.index("/**",start)
    body=src[start:end]
    rng=random.Random(1480)
    rows=[]
    selected=0
    for i in range(18000):
        count=rng.randrange(1,20)
        h=i%8
        x,y,z=rng.randrange(9,1000),rng.randrange(9,1000),rng.randrange(9)
        rows.append([x,y,z,h,int(i%13==0),rng.choice([0,1,1479,1480,1481]),int(i%5!=0),count])
        for j in range(count):
            rows.append([j+2,x+rng.randrange(-7,8),y+rng.randrange(-7,8),z+rng.randrange(-6,7),
               rng.choice([h,h,h,rng.randrange(8)]),int(j%7==0),rng.randrange(1,7),int(j%9==0)])
        if i%7==0:
            # guaranteed same-lane control plus exact-distance ties on every direction
            rows[-1]=[j+2,x,y,z,h,0,2,0]
    cases="".join(" ".join(map(str,line))+"\n" for line in rows).encode()
    with tempfile.TemporaryDirectory() as d:
        t=Path(d)
        (t/"ref.cpp").write_text(SHIM+body+DRIVER)
        (t/"compare.lua").write_text(LUA)
        subprocess.run(["c++","-O2","-std=c++17",str(t/"ref.cpp"),"-o",str(t/"ref")],check=True)
        expected=subprocess.check_output([str(t/"ref")],input=cases)
        actual=subprocess.check_output([a.lua,str(t/"compare.lua")],cwd=ROOT,input=cases)
    want,got=expected.splitlines(),actual.splitlines()
    assert len(want)==len(got)==18000
    for i,(x,y) in enumerate(zip(want,got),1):
        assert x==y,(i,x,y)
        selected+=not x.startswith(b"-1,")
    print(f"PASS: 18,000 stock proximity decisions, {selected:,} leaders (matching IDs and blocked counters)")
if __name__=="__main__":
    main()
