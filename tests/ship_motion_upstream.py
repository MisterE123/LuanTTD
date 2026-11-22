"""Differential against compiled unmodified OpenTTD 14.1 ship movement primitives."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "ship_cmd.cpp":"f664841259821ee557109c15f2f2e6497b7416030a78e0275875f47f1fb8851a",
    "vehicle.cpp":"1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
    "track_func.h":"1b49b94fe0f759fba9cc80b79f52f58c9c35cffaf42e0fe14b92b9b893453ca5",
    "vehicle_base.h":"98b6c85830d272fd06d8d760c01f019db84748caab8363c6c121450623e6132e",
}
def src(name):
    p=SRC/name if (SRC/name).is_file() else SRC/"src"/name
    b=p.read_bytes()
    assert sha256(b).hexdigest()==PINS[name],name
    return b.decode()

def block(text,pattern):
    a=re.search(pattern,text,re.M).start()
    b=text.index("{",a);balance=1
    while balance:
        b+=1;balance+=(text[b]=="{")-(text[b]=="}")
    return text[a:b+1]

ship=src("ship_cmd.cpp")
base=src("vehicle_base.h")
ctrl=block(ship,r"^static void ShipController")
rotate=block(ctrl,r"^\s*if \(v->direction != v->rotation\)")
CPP=r"""
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <limits>
#include <cstdint>
using uint=unsigned;
using byte=uint8_t;
using TileIndex=int;
using TrackBits=int;
using DirDiff=int;
enum Direction {DIR_N,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW,DIR_END,INVALID_DIR=255};
enum DiagDirection {DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END};
enum {TRACK_END=6,TRACK_BIT_RIGHT=32,TRACK_BIT_LOWER=8,TRACK_BIT_LEFT=16,TRACK_BIT_UPPER=4};
enum {DIRDIFF_REVERSE=4,DIRDIFF_45LEFT=7,DIRDIFF_45RIGHT=1,DIAGDIRDIFF_90LEFT=3};
enum {MP_WATER,LOCK_PART_MIDDLE=1,TILE_HEIGHT=8,WC_VEHICLE_VIEW,WID_VV_START_STOP};
struct GetNewVehiclePosResult{int x,y; TileIndex old_tile,new_tile;};
void SetWindowWidgetDirty(int,int,int){}
using Slope=int;
uint TileVirtXY(int x,int y){return (x/16)+(y/16)*64;}
DiagDirection DirToDiagDir(Direction d){return DiagDirection(d>>1);}
DiagDirection ChangeDiagDir(DiagDirection d,int i){return DiagDirection((d+i)&3);}
Direction ChangeDir(Direction d,int i){return Direction((d+i)&7);}
int DirDifference(Direction a,Direction b){return (a-b)&7;}
bool HasBit(int n,int b){return n&(1<<b);}
bool IsValidDiagDirection(DiagDirection d){return d>=0&&d<4;}
int kind,part,slope,low,high;
bool IsTileType(int,int){return kind!=0;}
bool IsLock(int){return kind==1;}
int GetLockPart(int){return part;}
int GetTileSlope(int){return slope;}
int GetTileZ(int){return low;}
int GetTileMaxZ(int){return high;}
DiagDirection GetInclinedSlopeDirection(Slope s){return s==12?DIAGDIR_NE:s==6?DIAGDIR_SE:s==3?DIAGDIR_SW:DIAGDIR_NW;}
"""+ "\n".join(re.findall(r"^const uint TILE_(?:AXIAL|CORNER)_DISTANCE =[^;]*;",base,re.M))+r"""
struct Vehicle {
    Direction direction=DIR_NE,rotation=DIR_NE;
    int x_pos=808,y_pos=808,z_pos=0,tile=3250,tick_counter=0,cur_speed=0,acceleration=0,progress=0,index=0;
    struct{int cached_max_speed;}vcache;
    struct{int max_speed=65535; int GetMaxSpeed(){return max_speed;}} current_order;
    struct{Direction last_direction=INVALID_DIR;} sprite_cache;
    void UpdatePosition(){}
    void UpdateViewport(bool,bool=true){}
"""+block(base,r"^\s*static inline uint GetAdvanceSpeed\(uint speed")+"\n"+block(base,r"^\s*inline uint GetAdvanceDistance\(")+r"""
};
using Ship=Vehicle;
"""+ "\n".join(block(ship,p) +(";\n" if p.endswith("Data") or p.endswith("_ship_subcoord") else "") for p in (
    r"^struct ShipSubcoordData",r"^static const ShipSubcoordData _ship_subcoord",r"^static int ShipTestUpDownOnLock",
    r"^static bool ShipMoveUpDownOnLock", r"^static uint ShipAccelerate"))+"\n"+block(src("vehicle.cpp"),
    r"^GetNewVehiclePosResult GetNewVehiclePos")+"\n"+block(src("track_func.h"),
    r"^inline DiagDirection VehicleExitDir")+r"""
void rotate(Ship *v) {
"""+rotate+r"""
}
int main(){
    Ship v;
    for(int d=0;d<4;d++)for(int tr=0;tr<6;tr++){
        auto s=_ship_subcoord[d][tr];
        std::printf("e %d %d %u %u %d\n",d,tr,s.x_subcoord,s.y_subcoord,s.dir);
    }
    for(int d=0;d<8;d++){
        v.direction=Direction(d);
        const auto p=GetNewVehiclePos(&v);
        std::printf("p %d %d %d\n",d,p.x-v.x_pos,p.y-v.y_pos);
        for(int tr=0;tr<6;tr++)
            std::printf("x %d %d %d\n",d,tr,VehicleExitDir(v.direction,1<<tr));
        for(int dest=0;dest<8;dest++)for(int tick=0;tick<=32;tick++){
            v.direction=Direction(dest);v.rotation=Direction(d);v.tick_counter=tick;
            rotate(&v);
            std::printf("r %d %d %d %d\n",d,dest,tick,v.rotation);
        }
        v.direction=Direction(d);
        for(int speed=0;speed<=1024;speed+=23)for(int accl : {0,1,85,700})
        for(int progress : {0,71,191,255})for(int om : {14,127,511}){
            v.cur_speed=speed;v.acceleration=accl;v.progress=progress;v.vcache.cached_max_speed=768;
            v.current_order.max_speed=om;auto steps=ShipAccelerate(&v);
            std::printf("a %d %d %d %d %d %u %d %d\n",d,speed,accl,progress,om,steps,v.cur_speed,v.progress);
        }
    }
    for(kind=0;kind<3;kind++)for(part=0;part<3;part++)for(int d=0;d<4;d++)for(int shape : {3,6,9,12})
    for(int center=0;center<=1;center++)for(int z=6;z<=18;z++)for(int tick : {3,8}){
        v.x_pos=center?808:807;v.y_pos=808;v.z_pos=z;v.cur_speed=500;
        v.direction=Direction(d*2+1);v.tick_counter=tick;
        low=1;high=2;slope=shape;
        int dz=ShipTestUpDownOnLock(&v);
        bool moved=ShipMoveUpDownOnLock(&v);
        std::printf("l %d %d %d %d %d %d %d %d %d %d %d\n",kind,part,d,shape,center,z,tick,
            dz,moved,v.cur_speed,v.z_pos);
    }
}
"""
LUA=r"""
local ref="mods/luanttd_core/openttd/"
local T=dofile(ref.."rail_track.lua")
local M=dofile(ref.."ship_motion.lua")(T,dofile(ref.."ship_follow.lua")(T))
local n={e=0,p=0,x=0,r=0,a=0,l=0}
for line in io.lines() do
  local m=line:sub(1,1)
  local a={}
  for k in line:gmatch("-?%d+") do a[#a+1]=tonumber(k) end
  n[m]=n[m]+1
  if m=="e" then
    local x,y,d=M.entry(a[1],a[2])
    if a[5]==255 then assert(x==nil,line)
    else assert(x==a[3] and y==a[4] and d==a[5],line) end
  elseif m=="p" then
    local dx,dy=M.displacement(a[1]);assert(dx==a[2] and dy==a[3],line)
  elseif m=="x" then
    assert(M.exit_direction(a[1],2^a[2])==a[3],line)
  elseif m=="r" then
    local v={rotation=a[1],direction=a[2],tick=a[3]}
    local r=M.rotate(v)
    assert(v.rotation==a[4] and r==(a[1]~=a[2]),line)
  elseif m=="a" then
    local v={direction=a[1],speed=a[2],acceleration=a[3],progress=a[4],order={max_speed=a[5]},max_speed=768}
    local steps=M.accelerate(v)
    assert(steps==a[6] and v.speed==a[7] and v.progress==a[8],line)
  elseif m=="l" then
    local rec={kind=a[1]==1 and "lock" or "sea",part=a[2]==1 and "middle" or "start",base=1,top=2,slope=a[4]}
    local board={tile=function()return rec end}
    local v={direction=a[3]*2+1,tick=a[7],x=a[5]==1 and 808 or 807,y=808,z=a[6],speed=500,tile=1}
    local dz=M.lock_delta(board,v)
    local moved=M.move_lock(board,v)
    assert(dz==a[8] and moved==(a[9]==1) and v.speed==a[10] and v.z==a[11],line)
  end
end
assert(n.e==24 and n.p==8 and n.x==48 and n.r==2112 and n.a==17280 and n.l==7488)
print(("PASS: pinned ship subcoordinates/displacement/exit %d, rotation %d, acceleration %d, lock clock %d"):format(n.e+n.p+n.x,n.r,n.a,n.l))
"""
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"upstream.cpp").write_text(CPP)
    (p/"verify.lua").write_text(LUA)
    subprocess.run(["c++","-std=c++17","-O2",p/"upstream.cpp","-o",p/"upstream"],check=True)
    truth=subprocess.check_output([p/"upstream"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],input=truth,cwd=ROOT,check=True)
