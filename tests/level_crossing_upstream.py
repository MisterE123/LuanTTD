#!/usr/bin/env python3
"""Compile pinned OpenTTD crossing quotes, grouped barriers and road admission."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
PINS={
    "rail_cmd.cpp":"09c9ddedb7d94af9f21bcb2f71859f93b96bf9dbaab9d5eb1da51de11d9972d9",
    "road_cmd.cpp":"a693439b151a675b79ffff11d97d481931524872a02e8b4818ce6dd20430b2e3",
    "train_cmd.cpp":"206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "roadveh_cmd.cpp":"facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45",
    "track_func.h":"1b49b94fe0f759fba9cc80b79f52f58c9c35cffaf42e0fe14b92b9b893453ca5",
    "slope_type.h":"3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9",
    "road_type.h":"ad06673a815b4dd3418f3353e990a25a64ba59b38b132d195c09e5ef55e4f7f0",
    "pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "pbs.cpp":"65e7659b7291384e325a63be663a5b8f9a5ddb5e7acace4f5710153a1f616a5b",
    "roadtypes.h":"3c150f1e160184dffa733e22ba90b1076482e51d3e2176ca3f626227ef7a1afd",
    "railtypes.h":"849641b9e16d2b5dcf6036caf1f939f3e8bc7b6425711fc6baea1ddfc02b3261",
}
CPP=r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
using byte=unsigned char;
using uint=unsigned int;
using uint32_t=unsigned;
using TileIndex=int;
using Owner=int;
using Track=int;
using TrackBits=int;
using TrackdirBits=int;
using RoadType=int;
using RoadBitsAlias=int;
using RailType=int;
using Axis=int;
using Direction=int;
using DiagDirection=int;
using SlopeAlias=int;
using TransportType=int;
enum { MP_ROAD=0,MP_RAILWAY=1,OWNER_TOWN=-2,OWNER_DEITY=-3,INVALID_DIAGDIR=-1,
  RAIL_TILE_NORMAL=0,EXPENSES_CONSTRUCTION=0,DRD_NONE=0,DIAGDIR_END=4,DIAGDIRDIFF_90LEFT=3,
  TRACK_X=0,TRACK_Y=1,TRACK_BIT_X=1,TRACK_BIT_Y=2,TRACK_BIT_UPPER=4,
  TRACK_BIT_LOWER=8,TRACK_BIT_LEFT=16,TRACK_BIT_RIGHT=32,INVALID_ROADTYPE=-1,
  RTT_ROAD=0,RTT_TRAM=1,ROAD_TILE_CROSSING=2,TRACKDIR_BIT_X_NE=1,TRACKDIR_BIT_Y_SE=2,
  TRACKDIR_BIT_X_SW=256,TRACKDIR_BIT_Y_NW=512,SND_0E_LEVEL_CROSSING=0,VEH_TRAIN=0,
  TRACKDIR_BIT_NONE=0,AXIS_X=0,AXIS_Y=1,CORNER_W=0,CORNER_S=1,CORNER_E=2,CORNER_N=3};
ENUMS
bool HasBit(uint bits,int n){return bits&(1u<<n);}
int CountBits(uint bits){return __builtin_popcount(bits);}
bool HasExactlyOneBit(uint v){return CountBits(v)==1;}
int DirToDiagDir(int d){return d>>1;}
int ChangeDiagDir(int d,int diff){return (d+diff)&3;}
int AxisToDiagDir(int a){return 2-a;}
int ReverseDiagDir(int d){return (d+2)&3;}
int DiagDirToAxis(int d){return d&1;}
TrackBits AxisToTrackBits(Axis a){return 1<<a;}
TrackdirBits TrackBitsToTrackdirBits(TrackBits bits){return bits*257;}
int TrackToTrackBits(int t){return 1<<t;}
struct CommandCost {
  int value=0;
  std::string error;
  CommandCost()=default;
  CommandCost(int,int n=0):value(n){}
  CommandCost(const char* msg):error(msg){}
  bool Failed()const{return !error.empty();}
  void AddCost(int n){value+=n;}
};
std::ostream& operator<<(std::ostream& os,const CommandCost& c){
  if(c.Failed())return os<<c.error;
  return os<<c.value;
}
#define return_cmd_error(msg) return CommandCost(#msg+10)
struct Company {static bool IsValidID(int o){return o>=0;}};
struct {
  struct {bool crossing_with_competitor;} construction;
} _settings_game;
struct {struct {bool ambient;} sound;} _settings_client;
int _current_company=0;
struct T {
  int kind=0,axis=0,slope=0,tracks=0,rb=0,tb=0,roadowner=0,tramowner=0,owner=0,railtype=0;
  bool occupied=false,works=false,oneway=false,road=false,tram=false,reserved=false,
       barred=false,train=false,approach=false;
} world[64];
int road_deny,rail_deny;
const int road_muls[]={ROAD_MULTIPLIERS},rail_muls[]={RAIL_MULTIPLIERS};
int RoadBuildCost(int t){assert(t>=0 && t<2);return ROAD_PRICE*road_muls[t]/8;}
int RailBuildCost(int t){assert(t>=0 && t<4);return RAIL_PRICE*rail_muls[t]/8;}
bool IsSteepSlope(int slope){return slope&16;}
bool IsNormalRoad(int i){return world[i].kind==0;}
bool HasRoadWorks(int i){return world[i].works;}
int GetDisallowedRoadDirections(int i){return world[i].oneway;}
int GetRoadTypeRoad(int i){return world[i].road?0:-1;}
int GetRoadTypeTram(int i){return world[i].tram?1:-1;}
bool RoadNoLevelCrossing(int){return road_deny;}
bool RailNoLevelCrossings(int){return rail_deny;}
RoadBits GetRoadBits(int i,int kind){return static_cast<RoadBits>(kind==RTT_ROAD?world[i].rb:world[i].tb);}
int GetRoadOwner(int i,int kind){return kind==RTT_ROAD?world[i].roadowner:world[i].tramowner;}
bool IsLevelCrossing(int i){return i>=0 && i<64 && world[i].kind==2;}
bool IsLevelCrossingTile(int i){return IsLevelCrossing(i);}
int GetCrossingRoadAxis(int i){return world[i].axis;}
int GetCrossingRailBits(int i){return 1<<(1-world[i].axis);}
int GetRailTileType(int i){return world[i].kind;}
int GetTrackBits(int i){return world[i].tracks;}
int GetRailType(int i){return world[i].railtype;}
CommandCost CheckTileOwnership(int i){return world[i].owner==_current_company?CommandCost{}:CommandCost("OWNED_BY_ANOTHER");}
CommandCost CheckOwnership(int o){return o==_current_company?CommandCost{}:CommandCost("OWNED_BY_ANOTHER");}
CommandCost EnsureNoVehicleOnGround(int i){return world[i].occupied?CommandCost("VEHICLE_IN_THE_WAY"):CommandCost{};}
CommandCost RailQuote(int tile,int track,int railtype){
  int tileh=world[tile].slope,trackbit=TrackToTrackBits(track);
  CommandCost cost;
  switch(MP_ROAD){
  RAIL_CASE
  default: return CommandCost("FALLBACK_CLEAR");
  }
  cost.AddCost(RailBuildCost(railtype));
  return cost;
}
CommandCost RoadQuote(int tile,int pieces,int rt,int company){
  int tileh=world[tile].slope;
  switch(MP_RAILWAY){
  ROAD_CASE
  default: break;
  }
  do_clear: return CommandCost("FALLBACK_CLEAR");
}
bool TrainOnCrossing(int tile){return world[tile].train;}
bool TrainApproachingCrossing(int tile){return world[tile].approach;}
bool HasCrossingReservation(int tile){return world[tile].reserved;}
bool IsCrossingBarred(int tile){return world[tile].barred;}
void SetCrossingBarred(int tile,bool barred){world[tile].barred=barred;}
std::vector<int> dirty,sounds;
void MarkTileDirtyByTile(int tile){dirty.push_back(tile);}
void SndPlayTileFx(int,int tile){sounds.push_back(tile);}
namespace Map {int Size(){return 64;}}
int TileAddByDiagDir(int tile,int d){
  const int dx[]={-1,0,1,0},dy[]={0,1,0,-1};
  int x=tile%8+dx[d],y=tile/8+dy[d];
  if(x<0 || x>=8 || y<0 || y>=8)return 64;
  return x+y*8;
}
BARRIER
EXIT
struct Vehicle {int type,x_pos,y_pos,z_pos;};
COLLISION

std::array<int,2> Status(int tile,int side){
  TrackdirBits trackdirbits=0,red_signals=0;
  switch(ROAD_TILE_CROSSING){
  STATUS_CASE
  }
  return {trackdirbits,red_signals};
}
int main(){
  char c;
  while(std::cin>>c){
    if(c=='Q'){
      auto &t=world[0];
      int input,sub,track,pieces,type_,coop,who,rv,tv,walk,bar,one;
      std::cin>>input>>sub>>t.slope>>t.tracks>>t.rb>>t.tb>>track>>pieces>>type_>>
        coop>>who>>t.owner>>t.roadowner>>t.tramowner>>road_deny>>rail_deny>>rv>>tv>>walk>>bar>>one;
      t.kind=sub;t.axis=1-(t.tracks==2);
      t.railtype=type_;
      t.road=rv;t.tram=tv;t.occupied=walk;t.works=bar;t.oneway=one;
      _settings_game.construction.crossing_with_competitor=coop;
      _current_company=who;
      std::cout<<(input==0?RailQuote(0,track,type_):RoadQuote(0,pieces,input-1,who))<<"\n";
    }else if(c=='U'){
      int axis,group,other,res,previous,occ,approach,request,force,ambient,side;
      std::cin>>axis>>group>>other>>res>>previous>>occ>>approach>>request>>force>>ambient>>side;
      std::fill(std::begin(world),std::end(world),T{});
      dirty.clear();sounds.clear();
      int d=AxisToDiagDir(axis);
      int tiles[3]={27,TileAddByDiagDir(27,d),TileAddByDiagDir(27,ReverseDiagDir(d))};
      for(int i=0;i<3;++i){
        auto &t=world[tiles[i]];
        t.kind=(group&(1<<i))?2:0;
        t.axis=(other&(1<<i))?1-axis:axis;
        t.reserved=res&(1<<i);t.barred=previous&(1<<i);t.train=occ&(1<<i);t.approach=approach&(1<<i);
      }
      _settings_client.sound.ambient=ambient;
      UpdateLevelCrossing(27,request,force);
      for(int i=0;i<3;++i)std::cout<<world[tiles[i]].barred;
      for(int k:dirty) std::cout<<" "<<k<<":"<<(std::find(sounds.begin(),sounds.end(),k)!=sounds.end());
      auto status=Status(27,side);
      std::cout<<" / "<<status[0]<<" "<<status[1]<<"\n";
    }else if(c=='X'){
      int d,track; std::cin>>d>>track;
      std::cout<<VehicleExitDir(d,track)<<"\n";
    }else if(c=='C'){
      Vehicle u{1},t{};
      std::cin>>u.x_pos>>u.y_pos>>u.z_pos>>t.type>>t.x_pos>>t.y_pos>>t.z_pos;
      std::cout<<(EnumCheckRoadVehCrashTrain(&t,&u)!=nullptr)<<"\n";
    }
  }
}
"""

LUA=r"""
local T=dofile("mods/luanttd_core/openttd/rail_track.lua")
local C=dofile("mods/luanttd_core/openttd/level_crossing.lua")(T)
local function owner(i)
  return i==-2 and "town" or i==-3 and "deity" or i==-1 and "none" or i
end
local function has(bits,i)return T.has(bits,i) end
for line in io.lines() do
  local op=line:sub(1,1)
  local n={}
  for item in line:sub(3):gmatch("%S+") do n[#n+1]=tonumber(item) end
  if op=="Q" then
    local q,which=n[1],n[2]
    local t={kind=(q==0 and {[0]="road","road_depot","crossing"} or {[0]="rail","signals","rail_depot"})[which],
      slope=n[3],trackbits=n[4],road_bits=n[5],tram_bits=n[6],railtype=n[9],
      owner=owner(n[12]),rail_owner=owner(n[12]),road_owner=owner(n[13]),tram_owner=owner(n[14]),
      roadtype=n[17]==1 and 0 or nil,tramtype=n[18]==1 and 1 or nil,
      occupied=n[19]==1,roadworks=n[20]==1,disallowed=n[21],
      rail_axis=n[4]==2 and 1 or 0}
    local plan,why=C.quote(t,{kind=({[0]="rail","road","tram"})[q],track=n[7],pieces=n[8],
           railtype=n[9],owner=owner(n[11])},
      {crossing_with_competitor=n[10]==1,road_types={[0]={no_crossing=n[15]==1},[1]={no_crossing=n[15]==1}},
       rail_types={[n[9]]={no_crossing=n[16]==1}}})
    print(plan and plan.cost or why)
  elseif op=="U" then
    local tiles={}
    local board={tile=function(i)return tiles[i] end}
    function board.adjacent(v,d)
      local x,y=v%8,math.floor(v/8)
      x,y=x+({[0]=-1,0,1,0})[d],y+({[0]=0,1,0,-1})[d]
      if x>=0 and x<8 and y>=0 and y<8 then return x+y*8 end
    end
    local d=2-n[1]
    local ids={27,board.adjacent(27,d),board.adjacent(27,(d+2)%4)}
    local occ={}
    for k,id in ipairs(ids) do
      local i=k-1
      local ax=has(n[3],i) and 1-n[1] or n[1]
      tiles[id]={kind=has(n[2],i) and "crossing" or "rail",road_axis=ax,rail_axis=1-ax,
        roadtype=0,tramtype=1,railtype=0,rail_owner=0,reserved=has(n[4],i),barred=has(n[5],i)}
      if has(n[6],i) then occ[id]={{type="train",tile=id,x=0,y=0,z=0}} end
      if has(n[7],i) then
        -- Move along the rail axis of this crossing.
        local ra=1-ax
        local source=board.adjacent(id,ra)
        tiles[source]=tiles[source] or {kind="rail"}
        occ[source]=occ[source] or {}
        occ[source][#occ[source]+1]={type="train",tile=source,front=true,owner=0,compatible={[0]=true},
          direction=2*((ra+2)%4)+1,trackbits=2^ra}
      end
    end
    local ctx={vehicles_at=function(i)return occ[i] end,ambient=n[10]==1}
    local e=C.update(board,27,ctx,n[8]==1,n[9]==1)
    local out={}
    for _,id in ipairs(ids) do out[#out+1]=tiles[id].barred and "1" or "0" end
    io.write(table.concat(out))
    for _,change in ipairs(e) do io.write(" ",change.tile,":",change.sound and 1 or 0) end
    local a,b=C.road_status(board,27,false,n[11]>=0 and n[11] or nil,ctx)
    io.write(" / ",a," ",b,"\n")
  elseif op=="X" then
    print(C.vehicle_exit(n[1],n[2]))
  else
    local a={x=n[1],y=n[2],z=n[3]}
    local b={type=n[4]==0 and "train" or "road",x=n[5],y=n[6],z=n[7]}
    print(C.stock_collision_pair(a,b) and 1 or 0)
  end
end
"""

def read(base,name):
    for folder in (".","src","src/table"):
        file=base/folder/name
        if file.is_file():
            raw=file.read_bytes()
            assert sha256(raw).hexdigest()==PINS[name],f"Expected pinned OpenTTD 14.1 {name}"
            return raw.decode()
    raise FileNotFoundError(name)

def balanced(src,start):
    left=src.index("{",start)
    depth=1;i=left+1
    while depth:
        if src[i]=="{": depth+=1
        if src[i]=="}": depth-=1
        i+=1
    return i

def function(src,key):
    a=src.index(key)
    return src[a:balanced(src,a)]

def case(src,fn,marker):
    fn=src.index(fn)
    a=src.index(marker,fn)
    block=src[a:balanced(src,a)]
    token="if (flags & DC_EXEC)"
    while token in block:
        k=block.index(token)
        block=block[:k]+block[balanced(block,k):]
    return block

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    p.add_argument("--cxx",default="g++")
    a=p.parse_args()
    files={name:read(a.source,name) for name in PINS}
    rail=case(files["rail_cmd.cpp"],"CommandCost CmdBuildSingleRail(","case MP_ROAD:")
    road=case(files["road_cmd.cpp"],"CommandCost CmdBuildRoad(","case MP_RAILWAY:")
    status=case(files["road_cmd.cpp"],"static TrackStatus GetTileTrackStatus_Road","case ROAD_TILE_CROSSING:")
    struct=files["slope_type.h"]
    slope=struct[struct.index("enum Slope :"):struct.index("\n};",struct.index("enum Slope :"))+3]
    mask=re.search(r"static const uint32_t VALID_LEVEL_CROSSING_SLOPES[^;]+;",struct)[0]
    bits=function(files["road_type.h"],"enum RoadBits :")+";"
    src=files["train_cmd.cpp"]
    barrier="\n".join(function(src,key) for key in ["static inline bool CheckLevelCrossing(",
        "static void UpdateLevelCrossingTile(","void UpdateLevelCrossing("])
    cpp=CPP
    for k,v in {
        "ENUMS":slope+"\n#define M(x) (1u<<(x))\n"+mask+"\n#undef M\n"+bits,
        "BARRIER":barrier,
        "EXIT":function(files["track_func.h"],"inline DiagDirection VehicleExitDir("),
        "COLLISION":function(files["roadveh_cmd.cpp"],"static Vehicle *EnumCheckRoadVehCrashTrain("),
        "RAIL_CASE":rail,"ROAD_CASE":road,"STATUS_CASE":status,
        "RAIL_PRICE":re.search(r"\{\s*(\d+),[^\n]+///\< PR_BUILD_RAIL\b",files["pricebase.h"])[1],
        "ROAD_PRICE":re.search(r"\{\s*(\d+),[^\n]+///\< PR_BUILD_ROAD\b",files["pricebase.h"])[1],
        "RAIL_MULTIPLIERS":",".join(re.findall(r"/\* cost multiplier \*/\s*(\d+)",files["railtypes.h"])),
        "ROAD_MULTIPLIERS":",".join(re.findall(r"/\* cost multiplier \*/\s*(\d+)",files["roadtypes.h"])),
    }.items():
        cpp=cpp.replace(k,v)
    assert "SetCrossingReservation(tile, true);\n\t\t\t\tUpdateLevelCrossing(tile, false);" in files["pbs.cpp"]
    assert "SetCrossingReservation(tile, false);\n\t\t\t\tUpdateLevelCrossing(tile);" in files["pbs.cpp"]
    r=random.Random(141)
    lines=[]
    for i in range(15000):
        rb,tb=r.randint(0,15),r.randint(0,15)
        vals=[i%3,r.choices([0,1,2],[10,1,1])[0],r.choices([0,5,7,10,11,13,14,r.randrange(32)],[3,1,1,1,1,1,1,3])[0],
            r.choice([1,1,2,2,3,4]),rb,tb,r.randrange(6),r.randint(1,15),r.randrange(4),r.randrange(2),
            r.choice([0,1,-2,-3]),r.choice([0,1,-2,-1]),r.choice([0,1,-2,-1]),r.choice([0,1,-2,-1]),
            r.choices([0,1],[4,1])[0],r.choices([0,1],[4,1])[0],int(rb!=0),int(tb!=0),
            r.choices([0,1],[4,1])[0],r.choices([0,1],[4,1])[0],r.choices([0,1],[4,1])[0]]
        lines.append("Q "+" ".join(map(str,vals)))
    for i in range(6500):
        axis=i%2
        side=r.randrange(-1,4)
        # The two adjacent arms each may be missing or exactly the same
        # road axis. Perpendicular adjacent visuals are covered by Lua.
        vals=[axis,r.randrange(0,4)*2+1,0,r.randrange(8),r.randrange(8),r.randrange(8),
              r.randrange(8),r.randrange(2),r.randrange(2),r.randrange(2),side]
        lines.append("U "+" ".join(map(str,vals)))
    for d in range(8):
        for t in [1,2,4,8,16,32,64,128]:
            lines.append(f"X {d} {t}")
    for _ in range(3600):
        vals=[r.randrange(8),r.randrange(8),r.randrange(12),r.randrange(2),r.randrange(8),r.randrange(8),r.randrange(12)]
        lines.append("C "+" ".join(map(str,vals)))
    data="\n".join(lines)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)
        (path/"crossing.cpp").write_text(cpp);(path/"crossing.lua").write_text(LUA)
        subprocess.run([a.cxx,"-std=c++17","-O2",path/"crossing.cpp","-o",path/"ref"],check=True)
        expected=subprocess.check_output([path/"ref"],input=data,text=True).splitlines()
        actual=subprocess.check_output([a.lua,path/"crossing.lua"],cwd=ROOT,input=data,text=True).splitlines()
    assert len(expected)==len(actual)==len(lines)
    for line,want,got in zip(lines,expected,actual):
        assert want==got,(line,want,got)
    print(f"PASS: {len(lines)} pinned OpenTTD 14.1 crossing quotes, barrier/red status, exits and crash comparisons")
if __name__=="__main__":
    main()
