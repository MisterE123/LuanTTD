"""Compare ordinary station stop behavior and original train speed, OpenTTD 14.1.

python tests/rail_station_speed_upstream.py SOURCE_TREE [lua5.1]
Compiles unchanged C++ order/stop/acceleration functions with a tile and vehicle shim.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "train.h":"35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d",
    "train_cmd.cpp":"206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "order_cmd.cpp":"458bd35b50c639f01b61c3b3617c1cbcba23fc140379140b6bda209998de8e5c",
    "order_type.h":"738a2dbf386e4f4832b11f6c43d4b6824fa871a3b6287c71ef459d579c57ffb2",
    "ground_vehicle.hpp":"689d301a97c85d16dc37e1761c6352e238363c31cff724c923b8a38745b6d617",
    "vehicle_base.h":"98b6c85830d272fd06d8d760c01f019db84748caab8363c6c121450623e6132e",
})

LUA = r"""
local T=dofile("mods/bayline/openttd/rail_track.lua")
local F=dofile("mods/bayline/openttd/rail_follow.lua")(T)
local R=dofile("mods/bayline/openttd/rail_station_speed.lua")(T,F)
local names={[0]="tile","station","depot","waypoint"}
for line in io.lines() do
  local n={}
  for q in line:gmatch("%-?%d+") do n[#n+1]=tonumber(q) end
  local out={}
  if line:sub(1,1)=="S" then
    local k,l,total,front,heading,x,y,order,target,where,nonstop,dep,last,speed,front_=unpack(n)
    local rows={}
    local axis=math.floor(heading/2)%2
    for i=1,l do rows[i]={kind="station",axis=axis,railtype=0,station=1} end
    local board={tile=function(i) return rows[i] end,
      adjacent=function(i,d) return i+((d==0 or d==3) and -1 or 1) end}
    local v={total_length=total,front_length=front,last_station=last,speed=speed,front=front_==1,
      order={kind=names[order],station=target,stop_location=where,nonstop=nonstop,part_of_orders=dep==1}}
    local stop,ahead,length=R.stop_location(board,k,v,heading)
    local status=R.station_step(board,k,{x=x,y=y},v,heading)
    out={stop,ahead,length,status=="arrived" and 1 or 0,v.slowing and 1 or 0,v.speed}
    if status=="arrived" then R.begin_loading(v,1) end
    out[#out+1]=v.speed
  else
    local power,weight,brake,rev,stuck,speed,sub,prog,dir,limit,order,bridge,next_dir,z0,z1,incl,action=unpack(n)
    local v={speed=speed,subspeed=sub,progress=prog,direction=dir,
      max_track_speed=limit,order_max_speed=order,visible_bridge_speed=bridge,
      stopped=brake==1,reversing=rev==1,stuck=stuck==1,
      acceleration=R.acceleration(power,weight)}
    local pass=R.advance_distance(dir)
    local calls=R.move_pass(v,function(state)
      R.after_turn(state,state.direction,next_dir,incl)
      state.direction=next_dir
      R.after_grade(state,z0,z1)
      if action==1 then R.begin_loading(state,1)
      elseif action==2 then state.progress=255
      elseif action==3 then return "crashed" end
    end)
    out={v.acceleration,R.original_speed_limit(v),pass,calls,v.speed,v.subspeed,v.progress,v.direction}
  end
  print(table.concat(out," "))
end
"""


def cpp(source):
    train=src(source,"train_cmd.cpp")
    vehiclebase=src(source,"vehicle_base.h")
    stop=src(source,"station_cmd.cpp")
    r=r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
using byte=uint8_t;using uint=unsigned;using TileIndex=int;using StationID=int;
constexpr int TILE_SIZE=16,AXIS_X=0;
#define NOT_REACHED() std::abort()
"""
    r+=declarations(src(source,"direction_type.h"),[r"enum Direction\s*:",r"enum DiagDirection\s*:"])
    r+=declarations(src(source,"order_type.h"),[
        r"enum OrderNonStopFlags\s*\{",r"enum OrderStopLocation\s*\{",r"enum OrderDepotTypeFlags\s*\{"])
    r+=r"""
template<class T, class U, class W> T Clamp(T a,U b,W c){return std::max(T(b),std::min(a,T(c)));}
template<class T,class U> bool HasBit(T a,U b){return (a>>int(b))&1;}
template<class T> void Swap(T&a,T&b){std::swap(a,b);}
enum {OT_GOTO_TILE,OT_GOTO_STATION,OT_GOTO_DEPOT,OT_GOTO_WAYPOINT};
enum {VEH_TRAIN,VEH_ROAD};
enum {AM_ORIGINAL,AM_REALISTIC};
enum {AS_BRAKE,AS_ACCEL};
enum {VS_TRAIN_SLOWING=1, VS_STOPPED=2, VRF_REVERSING=0, VRF_TRAIN_STUCK=1};
enum {VETS_STATION_ID_OFFSET=4, VETSB_CONTINUE=0,VETSB_ENTERED_STATION=1,
 VETSB_CANNOT_ENTER=2};
using VehicleEnterTileStatus=uint32_t;
DiagDirection DirToDiagDir(Direction d){return DiagDirection(d>>1);}
int DiagDirToAxis(DiagDirection d){return d%2;}
inline bool IsRailStation(TileIndex){return true;}
inline StationID GetStationIndex(TileIndex){return 1;}
struct Vehicle;
struct Order{
 int kind=OT_GOTO_TILE;
 StationID dest=0;
 int where=1,nonstop=0,part_of_orders=0,max_speed=65535;
 bool IsType(int id)const{return kind==id;}
 StationID GetDestination()const{return dest;}
 OrderStopLocation GetStopLocation()const{return OrderStopLocation(where);}
 OrderNonStopFlags GetNonStopType()const{return OrderNonStopFlags(nonstop);}
 OrderDepotTypeFlags GetDepotOrderType()const{return part_of_orders?ODTFB_PART_OF_ORDERS:ODTF_MANUAL;}
 int GetMaxSpeed() const{return max_speed;}
 bool ShouldStopAtStation(const Vehicle*,StationID)const;
};
struct Vehicle {
 int type=VEH_TRAIN,last_station_visited=0;
 bool front=true;
 Order current_order;
 Direction direction=DIR_NE;
 int z_pos=0,vehstatus=0,flags=0;
 uint16_t cur_speed=0;
 byte subspeed=0,progress=0;
 bool IsFrontEngine()const{return front;}
};
int platform_total;
struct Station{
 static Station *Get(StationID){static Station st;return &st;}
 int GetPlatformLength(TileIndex k,DiagDirection dir)const{return (dir==DIAGDIR_NE||dir==DIAGDIR_NW)?k:platform_total-k+1;}
 int GetPlatformLength(TileIndex)const{return platform_total;}
};
struct {struct {int train_acceleration_model=AM_ORIGINAL;} vehicle;} _settings_game;
struct RailInfo{int acceleration_type=0;};
RailInfo rail;
RailInfo *GetRailTypeInfo(int){return &rail;}
"""
    for name in ("TILE_AXIAL_DISTANCE","TILE_CORNER_DISTANCE"):
        r+=re.search(rf"const uint {name} = \d+;",vehiclebase).group(0)+"\n"
    r+=r"""
struct Train:Vehicle{
 struct {int cached_total_length=32,cached_veh_length=8;uint cached_power=1,cached_weight=1;
   uint16_t cached_max_track_speed=103;} gcache;
 int bridge_speed=65535,acceleration=1,railtype=0;
 static Train *From(Vehicle *v){return static_cast<Train*>(v);}
 bool IsFreeWagon()const{return false;}
 int GetCurrentMaxSpeed()const{return std::min<int>({gcache.cached_max_track_speed,current_order.GetMaxSpeed(),bridge_speed});}
 void UpdateAcceleration();
 int UpdateSpeed();
 int GetAcceleration(){std::abort();}
"""
    r+=block(vehiclebase,r"^\s*static inline uint GetAdvanceSpeed\(")
    r+=block(vehiclebase,r"^\s*inline uint GetAdvanceDistance\(")
    r+=block(src(source,"train.h"),r"^\s*inline AccelStatus GetAccelerationStatus\(").replace("AccelStatus","int")
    r+=block(src(source,"ground_vehicle.hpp"),r"^\s*inline uint DoUpdateSpeed\(")+"};\n"
    r+=block(src(source,"order_cmd.cpp"),r"^bool Order::ShouldStopAtStation\(")
    for signature in (r"^int GetTrainStopLocation\(",r"^int Train::UpdateSpeed\(",r"^void Train::UpdateAcceleration\("):
        r+=block(train,signature)
    r+=declarations(train,[r"struct AccelerationSlowdownParams",r"static const AccelerationSlowdownParams _accel_slowdown"])
    r+=block(train,r"^static inline void AffectSpeedByZChange\(")
    r+=r"""
enum {RVSB_IN_ROAD_STOP=32};
struct RoadStop{
 static RoadStop *GetByTile(TileIndex,int){static RoadStop stop;return &stop;}
 struct RoadVehicle *unused;
 template<class T> bool Enter(T*){return false;}
};
struct RoadVehicle:Vehicle{
 static RoadVehicle *From(Vehicle *v){return static_cast<RoadVehicle*>(v);}
 int state=0,frame=0;
 bool IsFrontEngine()const{return false;}
};
bool IsRoadStop(TileIndex){return false;}
int GetRoadStopType(TileIndex){return 0;}
bool IsReversingRoadTrackdir(int){return false;}
using Trackdir=int;
enum {DIRDIFF_45LEFT=7,DIRDIFF_45RIGHT=1};
using DirDiff=int;
int DirDifference(Direction a,Direction b){return (a-b)&7;}
"""
    r+=block(stop,r"^static VehicleEnterTileStatus VehicleEnter_Station\(")
    # Extract the instruction that applies the original turn-speed fraction.
    a=train.index("const AccelerationSlowdownParams *asp =",train.index("if (chosen_dir != v->direction)"))
    b=train.index("v->cur_speed -=",a)
    b=train.index(";",b)+1
    r+=r"""
void turn(Train *v,Direction chosen_dir){
 if(chosen_dir!=v->direction){
"""
    r+=train[a:b]+"\n }\n v->direction=chosen_dir;\n}\n"
    r+=r"""
int main(){
 std::string typ;
 while(std::cin>>typ){
  Train v;
  if(typ=="S"){
   int k,total,front,dir,x,y,speed,front_;
   std::cin>>k>>platform_total>>total>>front>>dir>>x>>y>>v.current_order.kind>>v.current_order.dest
     >>v.current_order.where>>v.current_order.nonstop>>v.current_order.part_of_orders
     >>v.last_station_visited>>speed>>front_;
   v.gcache.cached_total_length=total;v.gcache.cached_veh_length=front;
   v.direction=Direction(dir);v.cur_speed=speed;v.front=front_;
   int ahead,length;
   int stop=GetTrainStopLocation(1,k,&v,&ahead,&length);
   auto status=VehicleEnter_Station(&v,k,x,y);
   std::cout<<stop<<" "<<ahead<<" "<<length<<" "<<HasBit(status,0)<<" "
     <<HasBit(v.vehstatus,0)<<" "<<v.cur_speed<<" ";
   if(HasBit(status,0))v.cur_speed=0; // BeginLoading's speed commit.
   std::cout<<v.cur_speed<<"\n";
  }else{
   int power,weight,brake,rev,stuck,speed,sub,prog,dir,limit,order,bridge,next,z0,z1,incl,action;
   std::cin>>power>>weight>>brake>>rev>>stuck>>speed>>sub>>prog>>dir>>limit>>order>>bridge>>next>>z0>>z1>>incl>>action;
   v.gcache.cached_power=power;v.gcache.cached_weight=weight;v.UpdateAcceleration();
   v.vehstatus=brake?VS_STOPPED:0;v.flags=rev|(stuck<<1);
   v.cur_speed=speed;v.subspeed=sub;v.progress=prog;v.direction=Direction(dir);
   v.gcache.cached_max_track_speed=limit;v.current_order.max_speed=order;v.bridge_speed=bridge;
   rail.acceleration_type=incl;
   const int start_step=v.GetAdvanceDistance();
   int j=v.UpdateSpeed(),adv_spd=v.GetAdvanceDistance(),calls=0;
   if (j>=adv_spd) {
    for (;;) {
     j-=adv_spd;++calls;
     turn(&v,Direction(next));
     v.z_pos=z1;AffectSpeedByZChange(&v,z0);
     if(action==1)v.cur_speed=0;
     else if(action==2)v.progress=255;
     else if(action==3)break;
     adv_spd=v.GetAdvanceDistance();
     if (j<adv_spd || v.cur_speed==0)break;
    }
   }
   if(v.progress==0)v.progress=j;
   std::cout<<v.acceleration<<" "<<v.GetCurrentMaxSpeed()<<" "<<start_step<<" "<<calls<<" "
    <<v.cur_speed<<" "<<int(v.subspeed)<<" "<<int(v.progress)<<" "<<int(v.direction)<<"\n";
  }
 }
}
"""
    return r


def corpus():
    r=random.Random(1423)
    for i in range(20000):
        l,k,head=r.randrange(1,12),None,r.randrange(8)
        k=r.randrange(1,l+1)
        x,y=r.randrange(16),r.randrange(16)
        if i%3==0:
            if head//2%2==0:y=8
            else:x=8
        if i%8==1:
            # Long train into the far-end target's exact local position.
            head=1+(i//8)%4*2
            neg=head//2 in (0,3)
            k=1 if neg else l
            along=3 if neg else 12
            x,y=(along,8) if head//2%2==0 else (8,along)
            yield "S "+ " ".join(map(str,[k,l,16*l,8,head,x,y,1,1,2,0,0,0,177,1]))
        else:
            total=r.randrange(8,256);front=r.randrange(4,9)
            yield "S "+" ".join(map(str,[k,l,total,front,head,x,y,r.randrange(4),r.randrange(2),
                        r.randrange(3),r.randrange(4),r.randrange(2),r.randrange(2),r.randrange(0,1000),r.randrange(2)]))
    for i in range(16000):
        yield "A "+" ".join(map(str,[
            r.randrange(8000),r.randrange(1,950),r.randrange(2),r.randrange(2),r.randrange(2),
            r.randrange(65536) if i%4==0 else r.randrange(350),r.randrange(256),r.randrange(256),r.randrange(8),
            r.randrange(2,65536) if i%6==0 else r.randrange(40,330),r.randrange(40,330) if i%7==0 else 65535,
            r.randrange(40,330) if i%11==0 else 65535,r.randrange(8),r.randrange(8),r.randrange(8),
            r.randrange(3),r.randrange(4),
        ]))


def main():
    cases=list(corpus())
    data=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as temp:
        t=Path(temp)
        (t/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (t/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",t/"ref.cpp","-o",t/"ref"],check=True)
        want=subprocess.check_output([t/"ref"],input=data).splitlines()
        got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",t/"port.lua"],
                                    cwd=ROOT,input=data).splitlines()
    for i,(a,b) in enumerate(zip(want,got)):
        assert a == b,(i,cases[i],a,b)
    assert len(want)==len(got)==len(cases)
    arrived=sum(x.split()[3]==b"1" for x in want[:20000])
    approaches=sum(x.split()[4]==b"1" for x in want[:20000])
    multi_steps=sum(int(x.split()[3])>1 for x in want[20000:])
    assert arrived>2400 and approaches>40 and multi_steps>200,(arrived,approaches,multi_steps)
    print(f"PASS: {len(cases):,} station/speed samples: {arrived:,} arrivals, {approaches:,} approach caps,"
          f" {multi_steps:,} multi-step speed passes")


if __name__=="__main__":
    main()
