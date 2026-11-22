"""Check against the unmodified OpenTTD 14.1 road slope tables and functions."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
src = Path(sys.argv[1])
def read(name):
    p=src/name
    return (p if p.exists() else src/"src"/name).read_bytes()
road=read("road_cmd.cpp")
assert sha256(road).hexdigest()=="a693439b151a675b79ffff11d97d481931524872a02e8b4818ce6dd20430b2e3"
rail=read("slope_type.h")
assert sha256(rail).hexdigest()=="3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9"

def block(text, regex):
    begin=re.search(regex,text,re.M).start()
    stop=text.index("{",begin)
    n=1
    while n:
        stop+=1
        n+=(text[stop]=="{")-(text[stop]=="}")
    return text[begin:stop+1]

r=road.decode()
s=rail.decode()
cpp="""
#include <cstdio>
#include <cstdlib>
using byte=unsigned char;
""" + block(s,r"^enum Corner \{")+";\n"+block(s,r"^enum Slope : byte \{")+";\n"+block(s,r"^enum Foundation \{")+";\n"+"""
using RoadBits=int;
constexpr RoadBits ROAD_NONE=0, ROAD_NW=1, ROAD_SW=2, ROAD_SE=4, ROAD_NE=8,
  ROAD_X=10, ROAD_Y=5, ROAD_ALL=15;
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
bool IsSteepSlope(Slope s){return s&16;}
Corner GetHighestSlopeCorner(Slope s){
  switch(s){case SLOPE_STEEP_W:return CORNER_W;case SLOPE_STEEP_S:return CORNER_S;
    case SLOPE_STEEP_E:return CORNER_E;case SLOPE_STEEP_N:return CORNER_N;
    default: std::abort();}
}
Slope SlopeWithOneCornerRaised(Corner c){return static_cast<Slope>(1<<c);}
bool IsStraightRoad(RoadBits b){return b==5||b==10;}
RoadBits MirrorRoadBits(RoadBits b){return ((b&3)<<2) | (b>>2);}
bool HasExactlyOneBit(RoadBits b){return b && !(b&(b-1));}
#define CLRBITS(n,m) ((n)&=~(m))
struct CommandCost{int value; CommandCost():value(0){} CommandCost(int,int v):value(v){}};
CommandCost CMD_ERROR(0,-1);
constexpr int EXPENSES_CONSTRUCTION=0,PR_BUILD_FOUNDATION=0;
const int _price[]={1};
struct {struct {bool build_on_slopes;} construction;} _settings_game;
""" + block(r,r"^static const RoadBits _invalid_tileh_slopes_road\[2\]\[15\]")+";\n"+block(r,r"^static Foundation GetRoadFoundation\(Slope tileh, RoadBits bits\)\n\{")+"\n"+block(r,r"^static CommandCost CheckRoadSlope")+"\n"+"""
int main(){
 for(int i=0;i<=30;i++){
  if(i>=15 && i!=23 && i!=27 && i!=29 && i!=30)continue;
  Slope slope=static_cast<Slope>(i);
  for(int b=0;b<16;b++)printf("f %d %d %d\\n",i,b,GetRoadFoundation(slope,b));
  for(int on=0;on<2;on++){
   _settings_game.construction.build_on_slopes=on;
   for(int add=0;add<16;add++)for(int e=0;e<16;e++)for(int o=0;o<16;o++){
    int pieces=add;
    auto cost=CheckRoadSlope(slope,&pieces,e,o).value;
    printf("p %d %d %d %d %d %d %d\\n",i,on,add,e,o,pieces,cost);
   }
  }
 }
}
"""
lua=r"""
local R=dofile("mods/bayline/openttd/road_slope.lua")
local F={[0]="none","leveled","x","y"}
local n=0
for line in io.lines() do
 local q={}
 for x in line:gmatch("-?%d+") do q[#q+1]=tonumber(x) end
 if line:sub(1,1)=="f" then assert(R.foundation(q[1],q[2])==F[q[3]],line)
 else
  local b,c=R.prepare(q[1],q[3],q[4],q[5],q[2]==1)
  assert((q[7]==-1 and b==nil) or (b==q[6] and c==(q[7]==1)),line)
 end
 n=n+1
end
assert(n==155952)
print("PASS: "..n.." C++/Lua road slope and foundation cases")
"""
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"ref.cpp").write_text(cpp)
    (p/"verify.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
    truth=subprocess.check_output([p/"ref"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],cwd=root,input=truth,check=True)
