#!/usr/bin/env python3
"""Differential RC1 rotor tick and both AircraftController vertical branches."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import subprocess

root=Path(sys.argv[1]).resolve()
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
game=Path(__file__).resolve().parents[1]
src=(root/"src/aircraft_cmd.cpp").read_text()

def scope(marker):
    a=src.index(marker);n=src.index("{",a);depth=1;b=n+1
    while depth:
        depth+=(src[b]=="{")-(src[b]=="}");b+=1
    return src[a:b]

decl=r"""
#include <algorithm>
#include <cstdint>
#include <iostream>
enum class VehState {Hidden,Stopped};
enum class VehicleAirFlag {HelicopterDirectDescent};
enum class AirportMovingDataFlag {HeliRaise,HeliLower};
enum {AT_OILRIG=1,FLYING=14,OT_LOADING=2,SPR_ROTOR_STOPPED=3, AIR_HELICOPTER=5};
enum {HRS_ROTOR_STOPPED,HRS_ROTOR_MOVING_1,HRS_ROTOR_MOVING_2,HRS_ROTOR_MOVING_3};
enum {SND_18_TAKEOFF_HELICOPTER,ORIGINAL_SAMPLE_COUNT=100};
enum class VehicleSoundEvent {Start};
enum class EngineImageType {OnMap};
using TileIndex=int;using SoundID=int;
template<class E> struct Flags {
 uint32_t mask;
 bool Test(E e) const {return mask & (1u<<int(e));}
 void Set(E e) {mask |= 1u<<int(e);}
 void Reset(E e) {mask &= ~(1u<<int(e));}
};
struct VehicleSpriteSeq {
 int id=0;
 void Set(int n) {id=n;}
 friend bool operator==(const VehicleSpriteSeq&a,const VehicleSpriteSeq&b) {return a.id==b.id;}
};
struct Aircraft {
 Aircraft *next=nullptr;
 Aircraft* Next(){return next;}
 uint8_t state=0,tick_counter=0;
 uint16_t cur_speed=0;
 int x_pos=1,y_pos=2,z_pos=65,tile=99,engine_type=0;
 Flags<VehState> vehstatus{};
 Flags<VehicleAirFlag> flags{};
 struct {VehicleSpriteSeq sprite_seq;} sprite_cache;
 struct Order{int t=0;bool IsType(int k){return t==k;}} current_order;
 void UpdatePositionAndViewport(){}
};
using Vehicle=Aircraft;
struct AV {int sfx=0;} vi;
AV* AircraftVehInfo(int) {return &vi;}
int sounds=0, terrain=0, count=0, expected_x=0,expected_y=0,replans=0;
void UpdateAircraftCache(Aircraft*) {}
void AircraftNextAirportPos_and_Order(Aircraft*) {replans++;}
bool PlayVehicleSound(Aircraft*,VehicleSoundEvent) {return false;}
void SndPlayVehicleFx(int,Aircraft*) {sounds++;}
void GetAircraftFlightLevelBounds(Aircraft*,int *min_z,int*) {*min_z=128;}
int UpdateAircraftSpeed(Aircraft*) {return count;}
void SetAircraftPosition(Aircraft*v,int x,int y,int z){v->x_pos=x;v->y_pos=y;v->z_pos=z;}
int GetSlopePixelZ(int x,int y) {if(x!=expected_x||y!=expected_y) std::abort(); return terrain;}
TileIndex TileVirtXY(int x,int y){return x*100+y;}
struct Station{struct {int type=1;} airport{};};
struct Fta {int delta_z;};
struct Moving {Flags<AirportMovingDataFlag> flags;};
void GetRotorImage(const Aircraft *v,EngineImageType, VehicleSpriteSeq *s) {s->Set(SPR_ROTOR_STOPPED + v->next->next->state);}
"""
cpp=decl+scope("static void HelicopterTickHandler(Aircraft *v)")+"\n"
cpp+=r"""
bool move(Aircraft*v,int part,int delta,int site) {
 Moving amd{{1u<<(part-1)}};
 Station station;station.airport.type=site==1;
 const Station*st=site==2?nullptr:&station;
 Fta profile{delta};const Fta*afc=&profile;
 TileIndex tile=77;
 int x=12,y=13;
"""
cpp+=scope("if (amd.flags.Test(AirportMovingDataFlag::HeliRaise))")+"\n"
cpp+=scope("if (amd.flags.Test(AirportMovingDataFlag::HeliLower))")+r"""
 return false;
}
int main(){
 Aircraft v,u,r; v.next=&u;u.next=&r;
 int op,part,delta,site,loading,stop,hide,spd,stage,tick,height,lasttile;
 while(std::cin>>op>>part>>delta>>site>>loading>>stop>>hide>>spd>>stage>>tick>>height>>lasttile>>count>>terrain){
  r.cur_speed=spd;r.state=stage;r.tick_counter=tick;r.vehstatus.mask=hide;
  v.vehstatus.mask=(stop<<1);v.current_order.t=loading?OT_LOADING:0;
  v.flags.mask=0;v.state=0;v.cur_speed=55;v.z_pos=height;v.tile=lasttile;
  expected_x=site==1?12:v.x_pos;expected_y=site==1?13:v.y_pos;
  sounds=replans=0;bool done=false;
  if(op==1) HelicopterTickHandler(&v); else done=move(&v,part,delta,site);
  std::cout<<done<<' '<<r.cur_speed<<' '<<+r.state<<' '<<+r.tick_counter<<' '<<v.cur_speed<<' '<<v.z_pos<<' '<<v.tile<<' '<<v.flags.mask<<' '<<+v.state<<' '<<sounds<<' '<<replans<<'\n';
 }
}
"""
port=r"""
local function f(v) return v and 1 or 0 end
local h=dofile("mods/luanttd_core/openttd/airport_rotary_motion.lua")({
  speed=function(v) return v.count end,bounds=function() return 128 end})
for line in io.lines() do
 local nums={} for n in line:gmatch("%d+") do nums[#nums+1]=tonumber(n) end
 local op,part,delta,site,loading,stop,hide,spd,stage,tick,height,lasttile,count,terrain=unpack(nums)
 local v={x=1,z=2,y=height,speed=55,rotor_speed=spd,rotor_state=stage,rotor_tick=tick,
    rotor_hidden=hide==1,loading=loading==1,stopped=stop==1,count=count,tile=lasttile,state=0}
 local sounds,replans=0,0
 local a={origin=77,x=12,z=13,delta_z=delta,layout=site==1 and "oilrig" or "country"}
 if site==2 then a=nil end
 local c={flying_state=14,flight_terrain_height=function() return 0 end,
    slope_pixel_z=function(x,z)
      assert(x==(site==1 and 12 or 1) and z==(site==1 and 13 or 2));return terrain
    end,tile_at=function(x,z) return x*100+z end,
    takeoff_sound=function() sounds=sounds+1 end,
    update_aircraft_cache=function()end,next_airport_order=function()replans=replans+1 end}
 local done
 if op==1 then h.tick(v,c) elseif part==1 then done=h.raise(v,c) else done=h.lower(a,v,c) end
 print(table.concat({f(done),v.rotor_speed,v.rotor_state,v.rotor_tick,v.speed,v.y,v.tile or 0,
    f(v.direct_descent),v.state,sounds,replans}," "))
end
"""
from random import Random
r=Random(1986)
cases=[]
for i in range(1220):
    op=1 if i<620 else 2
    spd=r.choice([0,16,31,32,33,48,75,80,83,127,128,130])
    cases.append([op,r.randint(1,2),54*(i%2),r.randrange(3),*([r.randrange(2) for _ in range(3)]),
       spd,r.randrange(4),r.randrange(256),r.choice([0,1,54,55,56,128,130,170]),r.randrange(200),
       r.randrange(9),r.randrange(2)])
input_data="".join(" ".join(map(str,t))+"\n" for t in cases)
with TemporaryDirectory() as out:
    p=Path(out)
    (p/"test.cpp").write_text(cpp)
    (p/"port.lua").write_text(port)
    subprocess.run(["c++","-std=c++17","-O2",str(p/"test.cpp"),"-o",str(p/"ref")],check=True)
    a=subprocess.check_output([p/"ref"],input=input_data,text=True).splitlines()
    b=subprocess.check_output([lua,p/"port.lua"],input=input_data,text=True,cwd=game).splitlines()
    assert len(a)==len(b)==len(cases)
    for x,y,z in zip(a,b,cases):
        assert x==y,(z,x,y)
print("PASS compiled RC1 helicopter: 1,220 rotor, hidden, loading, takeoff, missing-station and landing states including the oil rig anchor")
