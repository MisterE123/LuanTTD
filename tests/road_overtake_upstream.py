#!/usr/bin/env python3
"""Compile stock 14.1 overtaking decision, within-tile dispatch and timer.

Run from any directory: python3 tests/road_overtake_upstream.py /path/to/OpenTTD [lua5.1]
The exact source is SHA-pinned. Tile callbacks, company and body geometry
are input fixtures; the stock occupancy callback and timer are unmodified.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
upstream = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"


def read(name, digest):
    candidates = (upstream / 'src' / name, upstream / name, upstream / Path(name).name)
    path = next((p for p in candidates if p.exists()), candidates[0])
    data = path.read_bytes()
    assert sha256(data).hexdigest() == digest, f"{path}: not pinned 14.1"
    return data.decode()


def block(src, regex):
    start = re.search(regex, src, re.M).start()
    end = src.index("{", start)
    depth = 1
    while depth:
        end += 1
        depth += (src[end] == "{") - (src[end] == "}")
    return src[start:end + 1]


cmd = read("roadveh_cmd.cpp", "facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45")
header = read("roadveh.h", "c29e00fa1b8f5d7504644aa4d69ca1b187be49b645a5f96f7a71c19cd066a454")
dirs = read("direction_func.h", "fed254177acd43c100fec4e182a4e721ace1925fd6babee939a884eda81f9803")
rail = read("rail.cpp", "1d990c0a35ef14c1fc072ace3952734bac087f7981d18943932a96de8e1f0887")
track = read("track_func.h", "1b49b94fe0f759fba9cc80b79f52f58c9c35cffaf42e0fe14b92b9b893453ca5")
tracktypes = read("track_type.h", "db919468ff6a319383fe936d081933048c8c23d97ea95c869b269e404059b9e8")

cpp = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using byte=uint8_t; using uint=unsigned;
using Direction=int; using DiagDirection=int; using TileIndex=int;
constexpr int DIAGDIR_END=4;
bool IsValidDirection(Direction d) { return d>=0 && d<8; }
bool IsValidDiagDirection(DiagDirection d) { return d>=0 && d<4; }
#define DECLARE_POSTFIX_INCREMENT(X)
#define DECLARE_ENUM_AS_BIT_SET(X)
"""
cpp += re.sub(r"^#include .*\n", "", tracktypes, flags=re.M)
cpp += block(header, r"^enum RoadVehicleStates") + ";\n"
cpp += re.search(r"^static const byte RV_OVERTAKE_TIMEOUT .*",header,re.M)[0] + "\n"
for name in ("IsValidTrackdirForRoadVehicle", "TrackdirBitsToTrackBits", "TrackStatusToTrackdirBits",
             "TrackStatusToRedSignals", "DiagDirToDiagTrackdir", "IsStraightRoadTrackdir",
             "IsReversingRoadTrackdir"):
    cpp += block(track, r"^inline \w+ " + name + r"\(") + "\n"
cpp += block(dirs,r"^inline DiagDirection DirToDiagDir") + "\n"
cpp += block(rail,r"^extern const Trackdir _dir_to_diag_trackdir") + ";\n"
cpp += r"""
constexpr int VEH_ROAD=0, VEH_RAIL=1, VS_STOPPED=2, TRANSPORT_ROAD=1, MP_STATION=2;
constexpr int AM_ORIGINAL=0, AM_REALISTIC=1;
struct { struct {int roadveh_acceleration_model;} vehicle; } _settings_game;
template<class T> bool HasBit(T n,int i) { return (n>>i)&1; }
bool RoadTypeIsTram(int type) { return type==1; }
int GetRoadTramType(int type) { return type; }
struct Vehicle {
    int type=VEH_ROAD;
    const Vehicle *first=this;
    const Vehicle *First() const { return first; }
};
struct RoadVehicle : Vehicle {
    TileIndex tile=0;
    Direction direction=0;
    int state=0,roadtype=0,vehstatus=0,cur_speed=0,max_speed=0,accel=0;
    byte overtaking=0,overtaking_ctr=0;
    uint64_t compatible_roadtypes=1;
    bool articulated=false;
    bool HasArticulatedPart() const { return articulated; }
    int GetCurrentMaxSpeed() const { return max_speed; }
    int GetAcceleration() const { return accel; }
    RoadVehicle *First() const { return const_cast<RoadVehicle*>(static_cast<const RoadVehicle*>(first)); }
};
RoadVehicle v,u;
struct Tile {bool compatible,station; uint trackdirs,red; uint others;};
std::array<Tile,3> board; // 0 current, 1 next, 2 leader's occupied tile
std::array<Vehicle,3> bystanders;
bool HasTileAnyRoadType(TileIndex t,uint64_t) { return board[t].compatible; }
bool IsTileType(TileIndex t,int type) { return type==MP_STATION && board[t].station; }
TrackStatus GetTileTrackStatus(TileIndex t,int,int) { return board[t].trackdirs | (board[t].red<<16); }
int expected_direction;
int TileOffsByDiagDir(DiagDirection d) { return d==expected_direction ? 1 : 2; }
bool HasVehicleOnPos(TileIndex t,void *data,Vehicle *(*cb)(Vehicle*,void*)) {
    if (t==0 && cb(&v,data)) return true;
    if (t==u.tile && cb(&u,data)) return true;
    for (unsigned i=0;i<bystanders.size();++i) {
        if ((board[t].others & (1u << i)) && cb(&bystanders[i],data)) return true;
    }
    return false;
}
"""
for symbol in ["struct OvertakeData", "static Vehicle \\*EnumFindVehBlockingOvertake",
               "static bool CheckRoadBlockedForOvertaking", "static void RoadVehCheckOvertake"]:
    cpp += block(cmd,r"^"+symbol) + (";\n" if symbol.startswith("struct") else "\n")
prefix = cmd.index("bool IndividualRoadVehicleController(RoadVehicle")
prefix = cmd.index("{",prefix) + 1
end = cmd.index("/* If this vehicle is in a depot",prefix)
cpp += "static void BeforeAttempt(RoadVehicle *v) {\n" + cmd[prefix:end] + "\n}\n"
begin = cmd.index("if (u != nullptr) {\n\t\t\tu = u->First();",cmd.index("/* Calculate new position for the vehicle */"))
end = cmd.index("/* In case an RV is stopped in a road stop",begin)
cpp += "static bool WithinBlocked(RoadVehicle *v,RoadVehicle *u) {\n" + cmd[begin:end] + "\nreturn false;\n}\nreturn true;\n}\n"
begin = cmd.index("if (IsReversingRoadTrackdir(dir)) {\n\t\t\t/* When turning around we can't be overtaking. */")
end = cmd.index("/* Turning around */",begin)
cpp += "static bool Reversing(RoadVehicle *v,Trackdir dir) {\n" + cmd[begin:end] + "\nreturn true;\n}\nreturn false;\n}\n"
cpp += r"""
int main() {
    int op;
    bystanders[0].type=VEH_RAIL;
    bystanders[1].first=&v; // not a front engine
    while (std::cin>>op) {
        int ctr,ot;
        if (op==0) {
            int model;
            std::cin>>model>>v.direction>>u.direction>>v.state>>v.roadtype>>v.articulated
               >>u.tile>>v.cur_speed>>v.max_speed>>u.cur_speed>>u.max_speed>>u.accel>>u.vehstatus>>ot>>ctr;
            _settings_game.vehicle.roadveh_acceleration_model=model;
            for (auto &t:board) std::cin>>t.station>>t.compatible>>t.trackdirs>>t.red>>t.others;
            v.overtaking=ot; v.overtaking_ctr=ctr;
            expected_direction=v.direction/2;
            bool moved=WithinBlocked(&v,&u);
            std::cout<<unsigned(v.overtaking)<<" "<<unsigned(v.overtaking_ctr)<<" "<<v.cur_speed<<" "<<moved<<"\n";
        } else if (op==1) {
            bool station;
            std::cin>>v.state>>ot>>ctr>>station;
            v.overtaking=ot; v.overtaking_ctr=ctr; board[0].station=station;
            BeforeAttempt(&v);
            std::cout<<unsigned(v.overtaking)<<" "<<unsigned(v.overtaking_ctr)<<"\n";
        } else {
            int td;
            std::cin>>td>>ot>>ctr;
            v.overtaking=ot; v.overtaking_ctr=ctr;
            bool reversal=Reversing(&v,Trackdir(td));
            std::cout<<unsigned(v.overtaking)<<" "<<unsigned(v.overtaking_ctr)<<" "<<reversal<<"\n";
        }
    }
}
"""
lua_program = r"""
local O=dofile("mods/bayline/openttd/road_overtake.lua")
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  if a[1]==0 then
    local _,model,vd,ud,state,rt,art,tile,speed,vm,us,um,accel,stopped,ot,ctr=unpack(a)
    local v={id=1,first=1,type="road",tile=0,direction=vd,state=state,tram=rt~=0,
      articulated=art~=0,speed=speed,max_speed=vm,overtaking=ot,overtaking_ctr=ctr}
    local u={id=2,first=2,type="road",tile=tile,direction=ud,speed=us,max_speed=um,
      acceleration=accel,stopped=stopped==2}
    local tiles={}
    for i=0,2 do
      local j=17+i*5
      local b={station=a[j]==1,compatible=a[j+1]==1,bits=a[j+2],red=a[j+3],vehicles={}}
      if i==0 then b.vehicles[#b.vehicles+1]=v end
      if i==tile then b.vehicles[#b.vehicles+1]=u end
      if a[j+4]%2==1 then b.vehicles[#b.vehicles+1]={type="rail",id=3,first=3} end
      if math.floor(a[j+4]/2)%2==1 then b.vehicles[#b.vehicles+1]={type="road",id=4,first=1} end
      if math.floor(a[j+4]/4)%2==1 then b.vehicles[#b.vehicles+1]={type="road",id=5,first=5} end
      tiles[i]=b
    end
    local board={
      is_station=function(i) return tiles[i].station end,
      tile_status=function(i) local t=tiles[i];return t.compatible,t.bits,t.red end,
      vehicles_at=function(i) return tiles[i].vehicles end,
      adjacent=function(i,d) return d==math.floor(vd/2) and 1 or 2 end,
    }
    local moved=O.within_blocked(board,v,u,model==0)
    print(v.overtaking,v.overtaking_ctr,v.speed,moved and 1 or 0)
  elseif a[1]==1 then
    local v={state=a[2],overtaking=a[3],overtaking_ctr=a[4]}
    O.before_step(v,a[5]==1)
    print(v.overtaking,v.overtaking_ctr)
  else
    local v={overtaking=a[3],overtaking_ctr=a[4]}
    local reversal=O.reversing(v,a[2])
    print(v.overtaking,v.overtaking_ctr,reversal and 1 or 0)
  end
end
"""

rng = random.Random(141)
rows = []
for i in range(30000):
    td, vd = rng.choice([(0,1), (1,3), (8,5), (9,7)])
    ud = rng.choice([vd]*6+list(range(8)))
    state = rng.choice([td]*12+list(range(16))+[32,41,64,73,254,255])
    original, stopped = rng.randrange(2), rng.choice([0,0,0,2])
    leader_speed = rng.choice([0, 0, rng.randrange(200)])
    vmax, umax = rng.randrange(1,200), rng.randrange(1,200)
    row = [0, original, vd, ud, state, rng.randrange(8)==0, rng.randrange(8)==0,
           rng.randrange(3), rng.randrange(200), vmax, leader_speed, umax,
           rng.randrange(-40,41), stopped, rng.choice([0,0,0,0,16]), rng.randrange(256)]
    for j in range(3):
        row += [rng.randrange(12)==0, rng.randrange(12)!=0,
                rng.choice([1<<td,1<<td,0x101<<(td%8),0x303,
                            (1<<td)|(4<<rng.choice([0,8])),0x3F3F,0,rng.randrange(16384)&0x3F3F]),
                rng.choice([0]*15+[1<<rng.choice([0,1,8,9])]), rng.choice([0]*4+list(range(8)))]
    rows.append(list(map(int,row)))
for state in [*range(16), 32,33,41,64,73,254,255]:
    for ctr in range(256):
        for side in (0,16):
            for station in (0,1):
                rows.append([1,state,side,ctr,station])
for td in range(16):
    for ctr in (0,17,34,35,255):
        rows.append([2,td,16,ctr])

with tempfile.TemporaryDirectory(prefix="road-overtake-") as directory:
    d = Path(directory)
    (d/"ref.cpp").write_text(cpp)
    (d/"compare.lua").write_text(lua_program)
    subprocess.run(["c++","-std=c++17","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    inputs="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
    source=subprocess.check_output([d/"ref"],text=True,input=inputs).splitlines()
    actual=subprocess.check_output([lua,d/"compare.lua"],text=True,input=inputs,cwd=root).splitlines()
    assert len(source)==len(actual)==len(rows)
    started=0
    for row,a,b in zip(rows,source,actual):
        want=list(map(int,a.split()))
        got=list(map(int,b.split()))
        assert want==got,(row,want,got)
        if row[0]==0 and row[14]==0 and got[0]==16:
            started+=1
    assert started>100,started
    print(f"PASS pinned OpenTTD 14.1: {len(rows)} overtaking decisions/timers/reversals ({started} actual starts)")
