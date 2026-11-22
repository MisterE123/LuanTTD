#!/usr/bin/env python3
"""Compile SHA-pinned OpenTTD 14.1 RoadStop caches and controller branches.

Usage: python3 tests/road_stop_occupancy_upstream.py /path/to/OpenTTD [lua5.1]
The ordinary station/vehicle shims supply tile metadata and real actor
identities, with exact extracted source for pointer grouping, occupancy,
bay bits, frame-0 admission and parked-frame control.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def read(name,digest):
    paths=(source/"src"/name,source/name,source/Path(name).name)
    path=next((p for p in paths if p.is_file()),paths[0])
    data=path.read_bytes()
    assert sha256(data).hexdigest()==digest,f"{path}: not pinned OpenTTD 14.1"
    return data.decode()


def block(src,pat):
    start=re.search(pat,src,re.M).start()
    p=src.index("{",start)
    level=1
    while level:
        p+=1
        level+=(src[p]=="{")-(src[p]=="}")
    return src[start:p+1]


stop=read("roadstop.cpp","3ef278a791ca0723825151e54843d1f94bacd903d94568ddf47b1f1acb4c93e6")
base=read("roadstop_base.h","e4ff95c5eeb6ed8ce16524262284e5815a144149768f466361009df73d69307e")
veh=read("roadveh_cmd.cpp","facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45")
road=read("roadveh.h","c29e00fa1b8f5d7504644aa4d69ca1b187be49b645a5f96f7a71c19cd066a454")
station=read("station_cmd.cpp","7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5")
move=read("table/roadveh_movement.h","ce036feb9134f26351014dbaeebf91083206a25bb594f6ac7d70c25a863e6cee")
cpp=r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <list>
#include <memory>
#include <new>
#include <vector>
using byte=uint8_t; using uint=unsigned;
using TileIndex=int; using TileIndexDiff=int;
using Direction=int; using DiagDirection=int; using Trackdir=int;
using RoadStopType=int; using VehicleEnterTileStatus=int;
constexpr int TILE_SIZE=16,TRACKDIR_END=16,VEH_ROAD=0,VEH_TRAIN=1;
constexpr int VS_CRASHED=4,ROADSTOP_BUS=0,ROADSTOP_TRUCK=1,INVALID_TILE=-1;
constexpr int MP_STATION=1,OT_GOTO_STATION=1,OT_LEAVESTATION=2,VETSB_CONTINUE=1,VETSB_CANNOT_ENTER=0;
constexpr int WC_VEHICLE_VIEW=0,WID_VV_START_STOP=0;
template<class T> bool HasBit(T n,int i){return (n>>i)&1;}
template<class T> void ClrBit(T &n,int i){n &= ~(1u<<i);}
template<class T> void SetBit(T &n,int i){n |= 1u<<i;}
template<class T,class U> bool IsInsideMM(T n,U a,U b){return n>=a && n<b;}
template<class T,class U> void SB(T &n,int i,int bits,U v){n=(n&~(((1<<bits)-1)<<i))|(v<<i);}
template<class T> int GB(T n,int i,int bits){return (n>>i)&((1<<bits)-1);}
DiagDirection DirToDiagDir(Direction d){return d/2;}
DiagDirection ReverseDiagDir(DiagDirection d){return d^2;}
bool IsReversingRoadTrackdir(Trackdir d){return (d&7)>=6;}
int TileOffsByDiagDir(DiagDirection d){return std::array<int,4>{-1,16,1,-16}[d];}
int TileAddByDir(TileIndex t,Direction d){return t+TileOffsByDiagDir(DirToDiagDir(d));}
"""
cpp+=block(road,r"^enum RoadVehicleStates")+";\n"
cpp+=re.search(r"^static const uint RVC_DRIVE_THROUGH_STOP_FRAME.*",road,re.M)[0]+"\n"
cpp+=block(move,r"^extern const byte _road_stop_stop_frame")+";\n"
cpp+=r"""
struct Vehicle {
    int type=VEH_ROAD,index=0,vehstatus=0,owner=2,tile=0,direction=0;
    bool primary=true;
    bool IsPrimaryVehicle() const {return primary;}
};
struct Order {
    int kind=0,station=0; bool should=false;
    bool ShouldStopAtStation(Vehicle*,int s){return should;}
    bool IsType(int k){return kind==k;}
    int GetDestination(){return station;}
    void Free(){kind=0;}
};
struct RoadVehicle : Vehicle {
    bool front=true,articulated=false,bus=true,loading=false;
    int state=0,frame=0,cur_speed=50,last_station_visited=-1,compatible_roadtypes=1;
    int x_pos=0,y_pos=0;
    Order current_order;
    struct {int cached_total_length=8;} gcache;
    bool IsFrontEngine() const {return front;}
    bool HasArticulatedPart() const {return articulated;}
    bool IsBus() const {return bus;}
    void UpdatePosition(){}
    int UpdateInclination(bool,bool){return 0;}
    void BeginLoading(){loading=true;}
    static RoadVehicle* From(Vehicle*v){return static_cast<RoadVehicle*>(v);}
};
bool CleaningPool(){return false;}
"""
# The actual pool zero-initializes pointer storage. Make that explicit in
# the harness constructor, where automatic C++ object lifetime rules apply.
klass=re.sub(r"^struct RoadStop : [^{]+","struct RoadStop ",block(base,r"^struct RoadStop :"))
klass=klass.replace("status((1 << RSSFB_BAY_COUNT) - 1)",
                    "status((1 << RSSFB_BAY_COUNT) - 1), next(nullptr), east(nullptr), west(nullptr)")
cpp+=klass+";\n"
cpp+=r"""
struct Tile {int kind=0,dir=0,station=0,type=0,owner=2;bool compat=true;RoadStop *rs=nullptr;};
std::array<Tile,256> tiles;
std::array<std::vector<Vehicle *>,256> hash;
struct Station {
    int index;
    RoadStop *heads[2]={nullptr,nullptr};
    RoadStop *GetPrimaryRoadStop(RoadStopType type) const {return heads[type];}
    static Station* GetByTile(TileIndex t);
};
std::array<Station,10> stations;
bool IsTileType(TileIndex t,int type){return t>=0 && t<256 && type==MP_STATION && tiles[t].kind!=0;}
int GetRoadStopType(TileIndex t){return tiles[t].type;}
int GetStationType(TileIndex t){return tiles[t].type;}
int GetStationIndex(TileIndex t){return tiles[t].station;}
int GetTileOwner(TileIndex t){return tiles[t].owner;}
DiagDirection GetRoadStopDir(TileIndex t){return tiles[t].dir;}
bool IsDriveThroughStopTile(TileIndex t){return t>=0 && t<256 && tiles[t].kind==2;}
bool IsBayRoadStopTile(TileIndex t){return t>=0 && t<256 && tiles[t].kind==1;}
bool IsRoadStop(TileIndex t){return IsTileType(t,MP_STATION);}
bool HasTileAnyRoadType(TileIndex t,int){return IsRoadStop(t)&&tiles[t].compat;}
void DoClearSquare(TileIndex t){tiles[t].kind=0;}
void FindVehicleOnPos(TileIndex t,void *data,Vehicle*(*fn)(Vehicle*,void*)){
    for(auto *v:hash[t]) fn(v,data);
}
Station* Station::GetByTile(TileIndex t){return &stations[GetStationIndex(t)];}
void RoadVehArrivesAt(RoadVehicle*,Station*){}
void StartRoadVehSound(RoadVehicle*){}
void RoadZPosAffectSpeed(RoadVehicle*,int){}
void SetWindowWidgetDirty(int,int,int){}
struct {struct {int road_side=1;}vehicle;} _settings_game;
"""
for regex in [r"^RoadStop::~RoadStop",r"^void RoadStop::MakeDriveThrough",r"^void RoadStop::ClearDriveThrough",
              r"^void RoadStop::Leave",r"^bool RoadStop::Enter",r"^/\* static \*/ RoadStop \*RoadStop::GetByTile",
              r"^void RoadStop::Entry::Enter",r"^void RoadStop::Entry::Leave",
              r"^/\* static \*/ bool RoadStop::IsDriveThroughRoadStopContinuation",r"^struct RoadStopEntryRebuilderHelper",
              r"^Vehicle \*FindVehiclesInRoadStop",r"^void RoadStop::Entry::Rebuild"]:
    cpp+=block(stop,regex)+(";\n" if regex.startswith("^struct") else "\n")
cpp=cpp.replace("struct RoadStopEntryRebuilderHelper", "using RVList=std::list<const RoadVehicle *>;\nstruct RoadStopEntryRebuilderHelper")
station_body=block(station,r"^static VehicleEnterTileStatus VehicleEnter_Station")
station_branch=block(station_body,r"else if \(v->type == VEH_ROAD\)").removeprefix("else ")
cpp+="static bool StationCallback(Vehicle *v, TileIndex tile){\n"+station_branch+"\nreturn VETSB_CONTINUE;\n}\n"
start=veh.index("/* If the vehicle is in a normal road stop and the frame equals")
at=block(veh[start:],r"^\s*if \(v->IsFrontEngine\(\)")
cpp+="static int AtStop(RoadVehicle *v){int x=8,y=9;\n"+at+"\nreturn 2;\n}\n"
part=veh[veh.index("bool IndividualRoadVehicleController"):]
transition=block(part,r"^\s*if \(IsInsideMM\(v->state, RVSB_IN_ROAD_STOP, RVSB_IN_DT_ROAD_STOP_END\) &&")
cpp+="static bool Transition(RoadVehicle *v,TileIndex tile,Trackdir &dir){\n"+transition+"\nreturn true;\n}\n"
early=block(part,r"^\s*if \(v->cur_speed == 0 && IsInsideMM\(v->state, RVSB_IN_DT_ROAD_STOP")
cpp+="static void Early(RoadVehicle *v){if(!v->IsFrontEngine()) return;\n"+early+"\n}\n"
cpp+=r"""
void reset() {
    for(auto &t:tiles){delete t.rs;t=Tile{};}
    for(auto &h:hash)h.clear();
    for(int i=0;i<10;++i) stations[i]=Station{i};
}
RoadStop* add(int id,int kind,int dir,int station=7,int type=0,bool compat=true){
    auto *rs=new RoadStop(id);
    tiles[id]={kind,dir,station,type,2,compat,rs};
    rs->next=stations[station].heads[type];stations[station].heads[type]=rs;
    if(kind==2)rs->MakeDriveThrough();
    return rs;
}
void output(int axis){
    for(int i=1;i<=7;++i){
        int id=(axis==0?64+i:16*i+4);
        auto *r=tiles[id].kind?tiles[id].rs:nullptr;
        if(r==nullptr) std::cout<<" -1 -1 -1 -1 -1";
        else {
            auto *a=r->GetEntry(axis),*b=r->GetEntry(ReverseDiagDir(axis));
            std::cout<<" "<<int(r->status)<<" "<<a->GetLength()<<" "<<a->GetOccupied()<<" "
                <<b->GetLength()<<" "<<b->GetOccupied();
        }
    }
}
int main(){
    int mode;
    while(std::cin>>mode){
        reset();
        if(mode==0){
            int kind,status,op,flags,compatible,other,axis,next,order;
            RoadVehicle v;
            std::cin>>kind>>status>>op>>flags>>compatible>>other>>axis>>next
                >>v.state>>v.frame>>v.direction>>v.cur_speed>>v.owner>>v.gcache.cached_total_length
                >>order>>v.current_order.station>>v.current_order.should>>_settings_game.vehicle.road_side;
            v.front=flags&1;v.primary=v.front;v.articulated=flags&2;v.bus=flags&4;
            v.current_order.kind=order;v.tile=68;
            auto *rs=add(68,kind,axis);
            if (next) {
                int t=TileAddByDir(68,v.direction);
                add(t,2,axis,7,other,compatible!=0);
            }
            if (kind==1) rs->status=status;
            const bool in_group=kind==2;
            if(in_group && op==2){
                byte state=v.state;
                rs->GetEntry(DirToDiagDir(v.direction))->Enter(&v);
                v.state=state;
            }
            int ret=2,td=other?7:(axis?1:8);
            if(op==0) ret=StationCallback(&v,68);
            else if(op==1) ret=AtStop(&v);
            else if(op==2)ret=Transition(&v,TileAddByDir(68,v.direction),td);
            else Early(&v);
            std::cout<<ret<<" "<<int(rs->status)<<" "<<v.state<<" "<<v.frame<<" "<<v.cur_speed<<" "
              <<v.current_order.kind<<" "<<v.last_station_visited<<" "<<v.loading<<" "<<td<<" "
              <<(in_group?rs->GetEntry(DirToDiagDir(v.direction))->GetOccupied():-1)<<"\n";
        } else {
            int axis,gap,order[7],mask,act_count;
            std::cin>>axis>>gap>>mask>>act_count;
            std::array<RoadVehicle,24> actors;
            auto id=[&](int i){return axis==0?64+i:16*i+4;};
            for(auto &k:order)std::cin>>k;
            for(int k:order)if(mask&(1<<k))add(id(k),2,axis);
            for(int i=0;i<act_count;++i){
                int k,flags;
                auto &v=actors[i];
                std::cin>>k>>v.direction>>v.gcache.cached_total_length>>flags;
                v.tile=id(k);v.index=i;
                v.primary=flags&1;v.type=(flags&2)?VEH_TRAIN:VEH_ROAD;
                v.vehstatus=(flags&4)?VS_CRASHED:0;
                v.state=(flags&8)?64:0;
                if (v.primary && v.type==VEH_ROAD && !v.vehstatus && v.state==64)
                    tiles[v.tile].rs->Enter(&v);
                hash[v.tile].push_back(&v);
                if(flags&16)hash[v.tile].push_back(&v);
            }
            add(id(gap),2,axis);
            output(axis);
            for(int i=1;i<=7;++i)if(auto *r=tiles[id(i)].rs){
                if(HasBit(r->status,RoadStop::RSSFB_BASE_ENTRY)){
                    r->GetEntry(axis)->Rebuild(r);
                    r->GetEntry(ReverseDiagDir(axis))->Rebuild(r);
                }
            }
            output(axis);
            tiles[id(gap)].rs->ClearDriveThrough();
            output(axis);
            std::cout<<"\n";
        }
    }
    reset();
}
"""
program=r"""
local d="mods/luanttd_core/openttd/"
local Motion=dofile(d.."road_motion.lua")(dofile(d.."road_motion_data.lua"))
local O=dofile(d.."road_stop_occupancy.lua")(Motion)
local function has(n,v) return math.floor(n/v)%2==1 end
local function kind(n) return n==1 and "bay_stop" or "drive_stop" end
for line in io.lines() do
  local p={}
  for v in line:gmatch("%S+") do p[#p+1]=tonumber(v) end
  local tiles,hash,s={},{},O.new()
  local b={tile=function(t) return tiles[t] end,adjacent=function(i,d) return i+({[0]=-1,16,1,-16})[d] end}
  local function add(id,k,dir,g,other,compatible)
    tiles[id]={kind=kind(k),dir=dir,station=g or 7,stop_type=other and "truck" or "bus",owner=2,compatible=compatible}
    return O.register(s,b,id)
  end
  local function direction(v) return math.floor(v.direction/2) end
  if p[1]==0 then
    local _,nk,status,op,flags,compatible,other,axis,next_td,state,frame,dir,speed,owner,len,ord,station,should,side=unpack(p)
    local v={state=state,frame=frame,direction=dir,speed=speed,owner=owner,total_length=len,
      front=has(flags,1),articulated=has(flags,2),bus=has(flags,4),tile=68}
    local order={kind=({[0]=nil,"go_station","leave_station"})[ord],station=station,should_stop=should==1}
    local rs=add(68,nk,axis)
    if next_td==1 then add(b.adjacent(68,direction(v)),2,axis,7,other==1,compatible==1) end
    if nk==1 then rs.status=status end
    if nk==2 and op==2 then O.get_entry(s,68,direction(v)).occupied=len end
    local ret,loaded,td=2,false,(other==1 and 7 or (axis==1 and 1 or 8))
    if op==0 then ret=O.station_callback(s,b,68,v) and 1 or 0
    elseif op==1 then
      local k=O.at_stop(s,b,v,side,order,function(t) return tiles[t].compatible end)
      if k=="move_inline" then ret=1;v.frame=v.frame+1
      elseif k=="load" or k=="wait_entrance" then ret=0;loaded=k=="load" end
    elseif op==2 then
      local ok,new=O.transition(s,b,v,b.adjacent(68,direction(v)),td)
      if ok then td=new end
      ret=ok and 1 or 0
    else loaded=O.blocked_load(b,v,order) end
    local en=nk==2 and O.get_entry(s,68,direction(v))
    print(ret,rs.status,v.state,v.frame,v.speed,order.kind=="go_station" and 1 or order.kind=="leave_station" and 2 or 0,
      v.last_station_visited or -1,loaded and 1 or 0,td,en and en.occupied or -1)
  else
    local _,axis,gap,mask,num=unpack(p)
    local function id(i) return axis==0 and 64+i or 16*i+4 end
    for i=6,12 do local k=p[i];if has(mask,2^k) then add(id(k),2,axis) end end
    for a=1,num do
      local at=13+(a-1)*4
      local k,dir,len,flags=unpack(p,at,at+3)
      local v={id=a,tile=id(k),direction=dir,total_length=len,primary=has(flags,1),
        type=has(flags,2) and "rail" or "road",crashed=has(flags,4),state=has(flags,8) and 64 or 0}
      if v.primary and v.type=="road" and not v.crashed and v.state==64 then O.enter(s,b,v.tile,v) end
      hash[v.tile]=hash[v.tile] or {}
      local h=hash[v.tile];h[#h+1]=v
      if has(flags,16) then h[#h+1]=v end
    end
    local out={}
    local function dump()
      for i=1,7 do
        local rs=s.stops[id(i)]
        local a,c=O.get_entry(s,id(i),axis),O.get_entry(s,id(i),(axis+2)%4)
        out[#out+1]=rs and rs.status or -1
        out[#out+1]=a and a.length or -1
        out[#out+1]=a and a.occupied or -1
        out[#out+1]=c and c.length or -1
        out[#out+1]=c and c.occupied or -1
      end
    end
    local function occupants(id) return hash[id] or {} end
    add(id(gap),2,axis)
    dump()
    for i=1,7 do
      local rs=s.stops[id(i)]
      if rs and rs.base==id(i) then O.rebuild(s,b,id(i),occupants) end
    end
    dump()
    O.clear(s,b,id(gap),occupants)
    tiles[id(gap)]=nil
    dump()
    print(unpack(out))
  end
end
"""
rng=random.Random(1416)
rows=[]
for i in range(22000):
    kind=rng.choice([1,2])
    op=rng.randrange(4)
    axis=rng.randrange(2)
    side=rng.randrange(2)
    drive_d=rng.choice([axis,axis+2])
    dir=drive_d*2+1
    straight=drive_d%2+8*(drive_d>=2)
    state=rng.choice([straight,straight+(32 if kind==1 else 64)+rng.choice([0,2,4,6]),254,255])
    if op==1 or op==3:
        state=straight+(32 if kind==1 else 64)+rng.choice([0,2,4,6])
    # Include the real four parked indices, plus non-stop and entry frames.
    frame=rng.choice([0,4,11,11,12,12,15,15,16,19,20])
    flags=rng.randrange(8)
    rows.append([0,kind,rng.randrange(4)+128*rng.randrange(2),op,flags,rng.randrange(2),
                 rng.randrange(2),axis,rng.randrange(2),state,frame,dir,rng.choice([0,0,30,99]),
                 rng.choice([2,2,3]),rng.randrange(1,40),rng.randrange(3),rng.choice([7,7,9]),
                 rng.randrange(2),side])
for i in range(4500):
    axis=rng.randrange(2)
    order=list(range(1,8))
    rng.shuffle(order)
    gap=rng.randrange(1,8)
    active=[k for k in order if k!=gap and rng.randrange(3)]
    if not active: active=[min(k for k in order if k!=gap)]
    n=rng.randrange(13)
    row=[1,axis,gap,sum(1<<k for k in active),n,*order]
    for i in range(n):
        row.extend([rng.choice(active),rng.randrange(8),rng.randrange(1,46),rng.randrange(32)])
    rows.append(row)

with tempfile.TemporaryDirectory(prefix="road-stop-occupancy-") as tmp:
    d=Path(tmp)
    (d/"ref.cpp").write_text(cpp)
    (d/"match.lua").write_text(program)
    subprocess.run(["c++","-std=c++17","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
    ref=subprocess.check_output([d/"ref"],text=True,input=data).splitlines()
    got=subprocess.check_output([lua,d/"match.lua"],text=True,input=data,cwd=root).splitlines()
    assert len(ref)==len(got)==len(rows),(len(ref),len(got),len(rows))
    for i,(a,b) in enumerate(zip(ref,got)):
        assert list(map(int,a.split()))==list(map(int,b.split())),(i,rows[i],a,b)
print("PASS 22,000 source bay/drive controller branches and 4,500 source directional cache join/rebuild/split cases")
