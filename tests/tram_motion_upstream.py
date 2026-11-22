"""Differential check against unmodified OpenTTD 14.1 tram table/control branches."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "roadveh_cmd.cpp":"facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45",
    "roadveh.h":"c29e00fa1b8f5d7504644aa4d69ca1b187be49b645a5f96f7a71c19cd066a454",
    "roadveh_movement.h":"ce036feb9134f26351014dbaeebf91083206a25bb594f6ac7d70c25a863e6cee",
}
subprocess.run([sys.executable,ROOT/"tools/import_tram_motion.py","--check",
                SRC/"roadveh_movement.h" if (SRC/"roadveh_movement.h").exists()
                else SRC/"src/table/roadveh_movement.h"],check=True)

def read(name):
    for p in (SRC/name,SRC/"src"/name,SRC/"src/table"/name):
        if p.exists():
            b=p.read_bytes()
            assert sha256(b).hexdigest()==PINS[name],name
            return b.decode()
    raise FileNotFoundError(name)

def block(text,start):
    a=text.index(start);b=text.index("{",a)
    balance=1
    while balance and b<len(text):
        b+=1
        balance+=(text[b]=="{")-(text[b]=="}")
    assert not balance
    return text[a:b+1]

cmd=read("roadveh_cmd.cpp")
h=read("roadveh.h")
frames="\n".join(re.findall(r"^static const uint RVC_(?:DEFAULT_START_FRAME|TURN_AROUND_START_FRAME(?:_SHORT_TRAM)?|START_FRAME_AFTER_LONG_TRAM).*?;",h,re.M))
decision=block(cmd,"if (RoadTypeIsTram(v->roadtype)) {\n\t\t\t\t/* Determine")
turn=block(cmd,"if (RoadTypeIsTram(v->roadtype) && !IsRoadDepotTile")
reverse=block(cmd,"if (RoadTypeIsTram(v->roadtype)) {\n\t\t\t/* Trams may only reverse")
assert "CanBuildTramTrackOnTile" in decision and "RVC_TURN_AROUND_START_FRAME_SHORT_TRAM" in decision
assert len(frames.splitlines())==4
SHIM=r"""
#include <cstdio>
#include <cstdlib>
using uint=unsigned int;
using byte=unsigned char;
using TileIndex=int;
using Trackdir=int;
using RoadBits=int;
using DiagDirection=int;
using Direction=int;
using DirDiff=int;
enum { DIAGDIR_NE, DIAGDIR_SE, DIAGDIR_SW, DIAGDIR_NW };
enum { DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW, INVALID_DIR=255 };
enum { DIRDIFF_REVERSE=4, DIRDIFF_45LEFT=7, DIRDIFF_45RIGHT=1 };
enum { ROAD_NONE=0, ROAD_NW=1, ROAD_SW=2, ROAD_SE=4, ROAD_NE=8, RTT_TRAM=1 };
enum { TRACKDIR_RVREV_NE=6, TRACKDIR_RVREV_SE=7, TRACKDIR_RVREV_SW=14, TRACKDIR_RVREV_NW=15 };
enum { RDE_NEXT_TILE=128,RDE_TURNED=64 };
struct RoadDriveEntry {byte x,y;};
#include "roadveh_movement.h"
#define NOT_REACHED() std::abort()
RoadBits DiagDirToRoadBits(int d){return 8>>d;}
int DiagDirToAxis(int d){return d&1;}
RoadBits AxisToRoadBits(int a){return a?5:10;}
bool HasExactlyOneBit(int n){return n && !(n&(n-1));}
bool RoadTypeIsTram(int){return true;}
bool normal,work,compatible,buildable,depot;
int current,neighbor;
bool IsNormalRoadTile(TileIndex){return normal;}
bool IsRoadDepotTile(TileIndex){return depot;}
bool HasRoadWorks(TileIndex){return work;}
bool HasTileAnyRoadType(TileIndex,int){return compatible;}
RoadBits GetRoadBits(TileIndex,int){return neighbor;}
RoadBits GetAnyRoadBits(TileIndex,int,bool=false){return current;}
bool CanBuildTramTrackOnTile(int,TileIndex,int,RoadBits){return buildable;}
struct RoadVehicle {
    bool front; RoadVehicle *previous;
    TileIndex tile=100;
    int cur_speed=100,roadtype=1,owner=1,compatible_roadtypes=2;
    Direction direction=0;
    int x_pos=64,y_pos=80;
    const RoadVehicle *Previous() const {return previous;}
    bool IsFrontEngine() const {return front;}
};
int DirDifference(int a,int b){return (a-b)&7;}
int ChangeDir(int a,int b){return (a+b)&7;}
"""+frames+"\n"+block(cmd,"static Direction RoadVehGetNewDirection")+"\n"+block(cmd,"static Direction RoadVehGetSlidingDirection")+r"""
bool can_reverse(RoadVehicle *v,int enterdir){
    const TileIndex tile=101;
    bool reverse=true;
    """+reverse+r"""
    return reverse;
}
bool start_turn(RoadVehicle *v,Trackdir dir,TileIndex &tile,uint &start_frame){
    """+decision+r"""
    return true;
}
void turned(RoadVehicle *v,RoadDriveEntry rd,Trackdir fallback){
    Trackdir dir;
    uint turn_around_start_frame=RVC_TURN_AROUND_START_FRAME;
    """+turn+r"""
    else dir=fallback;
    std::printf("%d %u\n",dir,turn_around_start_frame);
}
int main(){
    const Trackdir reverse_td[]={6,7,14,15};
    RoadVehicle v,prev;
    for(int approach=0;approach<4;approach++)for(current=0;current<16;current++){
        std::printf("r %d %d %d\n",approach,current,can_reverse(&v,approach));
        for(int is_depot=0;is_depot<2;is_depot++){
            depot=is_depot;
            std::printf("t %d %d %d ",approach,current,is_depot);
            turned(&v,{byte(RDE_TURNED|approach),0},8);
        }
        for(neighbor=0;neighbor<16;neighbor++)for(int bits=0;bits<64;bits++){
            v.front=bits&1; v.previous=(bits&2)? &prev:nullptr;
            prev.tile=101;
            normal=bits&4;work=bits&8;compatible=bits&16;buildable=bits&32;
            TileIndex tile=101;
            uint start=RVC_DEFAULT_START_FRAME;
            bool ok=start_turn(&v,reverse_td[approach],tile,start);
            std::printf("a %d %d %d %d %d %d %u\n",approach,current,neighbor,bits,ok,tile,start);
        }
    }
    for(int side=0;side<2;side++)for(int state=0;state<16;state++){
        auto row=_road_tram_drive_data[state+side*16];
        for(int f=0;!(row[f].x&RDE_NEXT_TILE);f++){
            if(row[f].x&RDE_TURNED) continue;
            const auto rd=row[f+1];
            if(rd.x&(RDE_TURNED|RDE_NEXT_TILE)) continue;
            v.x_pos=64+row[f].x;v.y_pos=80+row[f].y;
            int x=64+rd.x,y=80+rd.y;
            for(v.direction=0;v.direction<8;v.direction++){
                auto d=RoadVehGetSlidingDirection(&v,x,y);
                bool rotate=d!=v.direction;
                std::printf("s %d %d %d %d %d %d %d %d %d %d %d\n",side,state,f,v.direction,
                    v.x_pos,v.y_pos,rotate,rotate?v.x_pos:x,rotate?v.y_pos:y,d,rotate?f:f+1);
            }
        }
    }
}
"""
LUA=r"""
local root="mods/luanttd_core/openttd/"
local Motion=dofile(root.."road_motion.lua")(dofile(root.."road_motion_data.lua"))
local M=dofile(root.."tram_motion.lua")(dofile(root.."tram_motion_data.lua"),Motion)
local n={r=0,t=0,a=0,s=0}
local rev={[0]=6,7,14,15}
for line in io.lines() do
    local mode=line:sub(1,1)
    local a={}
    for k in line:gmatch("%d+") do a[#a+1]=tonumber(k) end
    n[mode]=n[mode]+1
    if mode=="r" then
        assert(M.can_reverse_request(a[2],a[1])==(a[3]==1),line)
    elseif mode=="t" then
        local td,f=M.turned({kind=a[3]==1 and "depot" or "road"},a[2],a[1],8)
        assert(td==a[4] and f==a[5],line)
    elseif mode=="a" then
        local function b(i) return math.floor(a[4]/2^i)%2==1 end
        local o={front=b(0),previous_tile=b(1) and 101 or nil,tile=100}
        local board={
            tile=function(id) assert(id==101);return {kind=b(2) and "road" or "crossing",tram_bits=a[3],roadworks=b(3),tramtype=1} end,
            has_compatible=function() return b(4) end,
            can_build_tram=function(_,id,need) assert(id==101);return b(5) end,
            tram_bits=function(id,inside) assert(id==100 and not inside);return a[2] end,
        }
        local choice,id,f,needed=M.start_reverse(board,o,101,rev[a[1]])
        local bits={[0]=2,1,8,4}
        assert(needed==bits[a[1]],line)
        assert((choice=="wait")== (a[5]==0),line)
        if a[5]==1 then assert(id==a[6] and f==a[7],line) end
    else
        local k,x,y,d,f=M.step({state=a[2],frame=a[3],direction=a[4],x=a[5],y=a[6]},a[1])
        assert(k==(a[7]==1 and "rotate" or "move") and x==a[8] and y==a[9] and d==a[10] and f==a[11],line)
    end
end
assert(n.r==64 and n.t==128 and n.a==65536 and n.s>4000)
print(("PASS: pinned C++ tram controller: %d reverse permissions, %d TURNED markers, %d entry choices, %d movement/heading frames"):format(n.r,n.t,n.a,n.s))
"""

with tempfile.TemporaryDirectory() as directory:
    p=Path(directory)
    (p/"roadveh_movement.h").write_text(read("roadveh_movement.h"))
    (p/"reference.cpp").write_text(SHIM)
    (p/"verify.lua").write_text(LUA)
    subprocess.run(["c++","-std=c++17","-O2",p/"reference.cpp","-o",p/"reference"],check=True)
    expected=subprocess.check_output([p/"reference"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],
        cwd=ROOT,input=expected,check=True)
