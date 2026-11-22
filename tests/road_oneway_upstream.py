#!/usr/bin/env python3
"""Compare ordinary OpenTTD 14.1 flat-road sign/drag rules against Lua.

Usage: python3 tests/road_oneway_upstream.py /path/to/OpenTTD [lua5.1]
Compile the complete long-road command, endpoint connectivity, normal-road
decision branch, final write and normal-road car track-status branch from
the pinned source. Shims replace building clearing, differing road types,
slope geometry, special tile construction and the draw routine.
"""
import hashlib
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def read(name,digest):
    paths=(src/"src"/name, src/name, src/Path(name).name)
    path=next((p for p in paths if p.is_file()),paths[0])
    b=path.read_bytes()
    assert hashlib.sha256(b).hexdigest()==digest,(path,"not pinned OpenTTD 14.1")
    return b.decode()


def block(txt,regex):
    start=re.search(regex,txt,re.M).start()
    p=txt.index("{",start)
    level=1
    while level:
        p+=1
        level+=(txt[p]=="{")-(txt[p]=="}")
    return txt[start:p+1]


cmd=read("road_cmd.cpp","a693439b151a675b79ffff11d97d481931524872a02e8b4818ce6dd20430b2e3")
rtype=read("road_type.h","ad06673a815b4dd3418f3353e990a25a64ba59b38b132d195c09e5ef55e4f7f0")
rfunc=read("road_func.h","937778e09276466883fb75bc8a05107e8e36809e0253e1b95c1ea6097a84d884")
dtypes=read("direction_type.h","d1cdad0afebbf6dce3d73d742ea352129ab05f0b5af30a5ba216b7030e6a085c")
dfunc=read("direction_func.h","fed254177acd43c100fec4e182a4e721ace1925fd6babee939a884eda81f9803")
track=read("track_type.h","db919468ff6a319383fe936d081933048c8c23d97ea95c869b269e404059b9e8")
gui=read("road_gui.cpp","2aefaf0cf0209508da8172a2d7f8db48fca13dc48a480a33a5e3378866357f3a")
assert "_one_way_button_clicked ? DRD_NORTHBOUND : DRD_NONE" in gui

cpp=r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned; using byte=uint8_t;
using TileIndex=int; using RoadType=int; using RoadTramType=int; using Owner=int;
using DoCommandFlag=int; using Money=int;
template<class T> int CountBits(T t) { return __builtin_popcount(unsigned(t)); }
"""
for key in ("Axis","DiagDirection"):
    cpp+=block(dtypes,r"^enum "+key+r"\b")+";\n"
for key in ("Track","TrackBits"):
    cpp+=block(track,r"^enum "+key+r"\b")+";\n"
for key in ("RoadBits","DisallowedRoadDirections"):
    cpp+=block(rtype,r"^enum "+key+r"\b")+";\n"
cpp+=r"""
#define ENUM_OP(T) \
inline T operator|(T a,T b) {return T(int(a)|int(b));} \
inline T operator&(T a,T b) {return T(int(a)&int(b));} \
inline T operator^(T a,T b) {return T(int(a)^int(b));} \
inline T &operator|=(T &a,T b) {return a=a|b;} \
inline T &operator&=(T &a,T b) {return a=a&b;} \
inline T &operator^=(T &a,T b) {return a=a^b;}
ENUM_OP(RoadBits)
ENUM_OP(TrackBits)
ENUM_OP(DisallowedRoadDirections)
bool IsValidRoadBits(RoadBits b) { return b<=ROAD_ALL; }
bool IsValidDisallowedRoadDirections(DisallowedRoadDirections d) {return d<DRD_END;}
bool IsValidAxis(Axis d) {return d<AXIS_END;}
bool IsValidDiagDirection(DiagDirection d) {return d<DIAGDIR_END;}
"""
for pat in ("ComplementRoadBits","IsStraightRoad","DiagDirToRoadBits","AxisToRoadBits"):
    cpp+=block(rfunc,r"^inline \w+ "+pat+r"\(")+"\n"
for pat in ("ReverseDiagDir","AxisToDiagDir"):
    cpp+=block(dfunc,r"^inline \w+ "+pat+r"\(")+"\n"
cpp+=r"""
enum {RTT_ROAD,RTT_TRAM, INVALID_ROADTYPE=-1, OWNER_NONE=-1, DC_EXEC=1, CMD_BUILD_ROAD=9,
    EXPENSES_CONSTRUCTION=0, MP_ROAD=1, MP_TUNNELBRIDGE=5};
enum Error {OK=0, PARAMETERS, UNSUPPORTED, ROAD_WORKS, JUNCTION, ALREADY, OWNED, VEHICLE};
constexpr Error STR_ERROR_ALREADY_BUILT=ALREADY, STR_ERROR_ROAD_WORKS_IN_PROGRESS=ROAD_WORKS,
    STR_ERROR_ONEWAY_ROADS_CAN_T_HAVE_JUNCTION=JUNCTION;
struct CommandCost {
    Error error=OK;
    Money cost=0;
    CommandCost()=default;
    CommandCost(Error e):error(e){}
    CommandCost(int,Money m=0):cost(m){}
    bool Failed() const {return error!=OK;}
    Error GetErrorMessage() const {return error;}
    void AddCost(CommandCost c) {cost+=c.cost;}
};
const CommandCost CMD_ERROR{PARAMETERS};
#define return_cmd_error(e) return CommandCost(e)
struct Map { static int Size(){return 256;} };
struct Tile {
    int kind=0;
    RoadBits bits=ROAD_NONE;
    Owner owner=OWNER_NONE;
    DisallowedRoadDirections drd=DRD_NONE;
    bool occupied=false,works=false;
};
std::array<Tile,256> world;
TileIndex TileOffsByDiagDir(DiagDirection d) {return std::array<int,4>{-1,16,1,-16}[d];}
int TileX(TileIndex i){return i%16;}
int TileY(TileIndex i){return i/16;}
bool IsValidTile(TileIndex i){return i>=0 && i<Map::Size();}
bool ValParamRoadType(RoadType rt){return rt==0;}
bool MayHaveRoad(TileIndex i){return world[i].kind!=0;}
RoadType GetRoadType(TileIndex i,RoadTramType){return world[i].bits!=ROAD_NONE?0:INVALID_ROADTYPE;}
RoadTramType GetRoadTramType(RoadType rt){return rt;}
RoadTramType OtherRoadTramType(RoadTramType rtt){return rtt^1;}
bool HasPowerOnRoad(RoadType a,RoadType b){return a==b;}
RoadBits GetRoadBits(TileIndex i,RoadTramType rtt){return rtt==RTT_ROAD?world[i].bits:ROAD_NONE;}
RoadBits GetAnyRoadBits(TileIndex i,RoadTramType rtt,bool){return GetRoadBits(i,rtt);}
bool HasTileRoadType(TileIndex i,RoadTramType rtt){return GetRoadBits(i,rtt)!=ROAD_NONE;}
bool IsNormalRoadTile(TileIndex i){return world[i].kind==1;}
bool IsTileType(TileIndex i,int kind){return kind==MP_ROAD && IsNormalRoadTile(i);}
bool IsBridge(TileIndex){return false;}
DiagDirection GetTunnelBridgeDirection(TileIndex){return DIAGDIR_NE;}
DisallowedRoadDirections GetDisallowedRoadDirections(TileIndex i){return world[i].drd;}
void SetDisallowedRoadDirections(TileIndex i,DisallowedRoadDirections drd){world[i].drd=drd;}
bool HasRoadWorks(TileIndex i){return world[i].works;}
Owner GetRoadOwner(TileIndex i,RoadTramType){return world[i].owner;}
template<class T> bool HasExactlyOneBit(T t) {return CountBits(t)==1;}
struct Company {static bool IsValidID(int id){return id>=0 && id<2;}};
CommandCost CheckOwnership(Owner o,TileIndex=0){return o==0 ? CommandCost():CommandCost(OWNED);}
CommandCost EnsureNoVehicleOnGround(TileIndex i){return world[i].occupied ? CommandCost(VEHICLE):CommandCost();}
void MarkTileDirtyByTile(TileIndex){}
std::vector<std::array<int,3>> attempts;
"""
normal=block(cmd[cmd.index("CommandCost CmdBuildRoad("):],r"^\s*case ROAD_TILE_NORMAL:")
tail=block(cmd,r"^\s*if \(rtt == RTT_ROAD && IsNormalRoadTile\(tile\)\) \{")
cpp+=r"""
static CommandCost CmdBuildRoadFlat(DoCommandFlag flags,TileIndex tile,RoadBits pieces,
                                   RoadType rt,DisallowedRoadDirections toggle_drd,int) {
    attempts.push_back({tile,pieces,toggle_drd});
    if (pieces==ROAD_NONE || !IsValidRoadBits(pieces)) return CMD_ERROR;
    if (world[tile].kind==2) return CommandCost(UNSUPPORTED);
    RoadBits existing=ROAD_NONE,other_bits=ROAD_NONE;
    RoadTramType rtt=GetRoadTramType(rt);
    if (IsNormalRoadTile(tile)) {
      switch(0) {
#define ROAD_TILE_NORMAL 0
""" + normal + r"""
      }
    }
    /* Ordinary flat, no overlay, roads-only subset. */
    auto clear=EnsureNoVehicleOnGround(tile);
    if (clear.Failed()) return clear;
    pieces &= ComplementRoadBits(existing);
    auto cost=CommandCost(EXPENSES_CONSTRUCTION,CountBits(pieces)*95);
    if (flags & DC_EXEC) {
        auto &t=world[tile];
        if (existing==ROAD_NONE) t.owner=0;
        t.kind=1;t.bits=existing|pieces;
""" + tail + r"""
    }
    return cost;
}
template<int N> struct Command {
    template<class... A> static CommandCost Do(A... a) {return CmdBuildRoadFlat(a...);}
};
"""
cpp+=block(cmd,r"^static bool CanConnectToRoad")+"\n"
cpp+=block(cmd,r"^CommandCost CmdBuildLongRoad")+"\n"
cpp+=block(cmd,r"^static const TrackBits _road_trackbits")+";\n"
part=cmd[cmd.index("static TrackStatus GetTileTrackStatus_Road"):]
gt=block(part,r"^\s*case ROAD_TILE_NORMAL:")
cpp+=r"""
using TrackdirBits=uint16_t;
constexpr TrackdirBits TRACKDIR_BIT_NONE=0;
static TrackdirBits NormalStatus(TileIndex tile){
    if (!IsNormalRoadTile(tile) || !HasTileRoadType(tile,RTT_ROAD)) return 0;
    RoadTramType rtt=RTT_ROAD;
    DiagDirection side=INVALID_DIAGDIR;
    TrackdirBits trackdirbits=TRACKDIR_BIT_NONE;
    switch(0) {
""" + gt + r"""
    }
    return trackdirbits;
}
"""
cpp+=r"""
int main(){
    int axis,start,last,drd;
    bool sh,eh,ai;
    while(std::cin>>axis>>start>>last>>drd>>sh>>eh>>ai){
        world={};attempts.clear();
        for(int k=1;k<=8;++k){
            auto &t=world[axis==0 ? 64+k : 16*k+4];
            int bits,td;
            std::cin>>t.kind>>bits>>t.owner>>td>>t.occupied>>t.works;
            t.bits=RoadBits(bits);t.drd=DisallowedRoadDirections(td);
        }
        const auto r=CmdBuildLongRoad(DC_EXEC,last,start,0,Axis(axis),DisallowedRoadDirections(drd),sh,eh,ai);
        std::cout<<r.error<<" "<<r.cost;
        if (!r.Failed()){
            for(const auto &item:attempts) for(int d:item) std::cout<<" "<<d;
            std::cout<<" -1";
            for(int k=1;k<=8;++k){
                auto &t=world[axis==0 ? 64+k : 16*k+4];
                std::cout<<" "<<t.kind<<" "<<int(t.bits)<<" "<<t.owner<<" "<<int(t.drd)
                    <<" "<<NormalStatus(axis==0 ? 64+k : 16*k+4);
            }
        }
        std::cout<<"\n";
    }
}
"""
program=r"""
local d="mods/bayline/openttd/"
local F=dofile(d.."yapf_road_follow.lua")
local R=dofile(d.."road_oneway.lua")(dofile(d.."road_slope.lua"),F)
local codes={PARAMETERS=1,UNSUPPORTED_TILE=2,ROAD_WORKS_IN_PROGRESS=3,ONEWAY_JUNCTION=4,
  ALREADY_BUILT=5,OWNED_BY=6,VEHICLE_IN_THE_WAY=7}
local function bool(i) return i==1 end
for line in io.lines() do
  local a={}
  for s in line:gmatch("%S+") do a[#a+1]=tonumber(s) end
  local axis,start,last,toggle,sh,eh,ai=unpack(a)
  local world={}
  local function id(k) return axis==0 and (64+k) or (16*k+4) end
  for k=1,8 do
    local p=8+(k-1)*6
    local t={kind=({"clear","road","crossing"})[a[p]+1],road_bits=a[p+1],owner=a[p+2]~=-1 and a[p+2] or nil,
      disallowed=a[p+3],occupied=bool(a[p+4]),roadworks=bool(a[p+5]),roadtype=a[p+1]~=0 and 0 or nil}
    t.numeric=a[p]
    world[id(k)]=t
  end
  local board={
    tile=function(i) return world[i] end,
    xy=function(i) return i%16,math.floor(i/16) end,
    adjacent=function(i,di) return i+({[0]=-1,16,1,-16})[di] end,
  }
  local opts={toggle=toggle,company=0,start_half=bool(sh),end_half=bool(eh),ai=bool(ai)}
  local p,why=R.plan(board,start,last,axis,opts)
  if not p then print(assert(codes[why],why),0)
  else
    local out={0,p.cost}
    for _,req in ipairs(p.drag.requests) do
      out[#out+1]=req.tile;out[#out+1]=req.bits;out[#out+1]=req.toggle
      if p.stopped_at==req.tile then break end
    end
    out[#out+1]=-1
    for _,e in ipairs(p.changes) do world[e.tile]={numeric=1,kind="road",roadtype=0,road_bits=e.road_bits,owner=e.owner,disallowed=e.disallowed} end
    for k=1,8 do
      local t=world[id(k)]
      out[#out+1]=t.numeric;out[#out+1]=t.road_bits;out[#out+1]=t.owner or -1;out[#out+1]=t.disallowed
      out[#out+1]=t.numeric==1 and F.status(t,false) or 0
    end
    print(unpack(out))
  end
end
"""

r=random.Random(14011)
rows=[]
for i in range(18000):
    axis=r.randrange(2)
    tile=lambda k:64+k if axis==0 else 16*k+4
    row=[axis,tile(r.randrange(2,8)),tile(r.randrange(2,8)),r.randrange(4),r.randrange(2),r.randrange(2),r.randrange(2)]
    for k in range(8):
        typ=r.choice([0,1,1,1,1,2])
        possible=[10,10,8,2,15,5] if axis==0 else [5,5,4,1,15,10]
        bits=r.choice(possible) if typ!=0 else 0
        drd=r.randrange(4) if typ==1 and bits in (5,10) else 0
        row.extend([typ,bits,r.choice([-1,0,0,0,1,2]) if typ!=0 else -1,drd,r.randrange(7)==0,r.randrange(13)==0 and typ==1])
    rows.append(list(map(int,row)))
with tempfile.TemporaryDirectory(prefix="road-oneway-") as work:
    d=Path(work)
    (d/"ref.cpp").write_text(cpp)
    (d/"compare.lua").write_text(program)
    subprocess.run(["c++","-std=c++17","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
    ref=subprocess.check_output([d/"ref"],input=data,text=True).splitlines()
    got=subprocess.check_output([lua,d/"compare.lua"],input=data,text=True,cwd=root).splitlines()
    assert len(ref)==len(got)==len(rows),(len(ref),len(got),len(rows),ref[:2],got[:2])
    for row,a,b in zip(rows,ref,got):
        assert list(map(int,a.split()))==list(map(int,b.split())),(row,a,b)
print(f"PASS pinned OpenTTD 14.1: {len(rows)} flat-road drag/occupancy/ownership and resulting track directions")
