#!/usr/bin/env python3
"""Differential-check manual staging and road loading waits against OpenTTD 14.1."""
import argparse
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SHIM=r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <list>
#include <map>
#include <vector>
using uint=unsigned int;
using Money=int64_t;
using StationID=int;
using TileIndex=int;
using CargoTypes=uint;
constexpr StationID INVALID_STATION=-1;
constexpr int OUFB_UNLOAD=1,OUFB_TRANSFER=2,OUFB_NO_UNLOAD=4;
constexpr int OLFB_FULL_LOAD=2,OLF_FULL_LOAD_ANY=3;
constexpr int VEH_TRAIN=0,VEH_ROAD=1,VEH_AIRCRAFT=3,TILE_SIZE=16;
constexpr int VF_STOP_LOADING=0,VF_LOADING_FINISHED=1;
constexpr int CC_PASSENGERS=0;
constexpr int OT_LOADING=1,OT_DUMMY=2,OT_IMPLICIT=3,OT_GOTO_STATION=4;
template<class T> bool HasBit(T x,int b) { return (x & (1u<<b))!=0; }
template<class T> void SetBit(T &x,int b) { x |= (1u<<b); }
template<class T> void ClrBit(T &x,int b) { x &= ~(1u<<b); }
template<class T> void SB(T &x,int b,int /*len*/,bool v) { if(v) SetBit(x,b);else ClrBit(x,b); }
void NOT_REACHED() { std::abort(); }
struct TimerGameTick { using Ticks=int; };
struct Order {
  int wait,flags,type,dest;
  int GetLoadType() const {return flags;}
  int GetTimetabledWait() const {return wait;}
  int GetType() const {return type;}
  bool IsType(int t) const {return t==type;}
  int GetDestination() const {return dest;}
};
struct Station { int GetPlatformLength(int) const {return 0;} };
struct Ground { int cached_total_length=0; };
struct Vehicle {
  Order current_order;
  int type=VEH_ROAD, cargo_type=0, cargo_cap=0, tile=0;
  int lateness_counter=0,current_order_time=0,cur_implicit_order_index=0,last_station_visited=12;
  uint vehicle_flags=0,load_unload_ticks=0;
  struct { int StoredCount() { return 0; } } cargo;
  bool refreshed=false,left=false;
  void PlayLeaveStationSound() {}
  void LeaveStation() { left=true; }
  void IncrementImplicitOrderIndex() {}
  const Order *GetOrder(int) { return nullptr; }
  Ground* GetGroundVehicleCache() {static Ground g;return &g;}
  void HandleLoading(bool mode);
};
bool IsCargoInClass(int,int) { return false; }
struct LinkRefresher {static void Run(Vehicle *v,bool,bool) { v->refreshed=true; }};
struct {struct { bool gradual_loading,station_length_loading_penalty; } order;} _settings_game;
struct CargoPacket {
  int id,first_station;
  uint count;
  int next_hop=-1;
  void AddFeederShare(Money) {}
};
struct CargoPayment { Money PayTransfer(CargoPacket *,uint,int) {return 0;} };
struct StationIDStack {
  bool Contains(int) const {return false;}
  bool IsEmpty() const {return true;}
  int Pop() const {std::abort();}
};
struct FlowStat {
  void ChangeShare(int,int) {}
  const std::vector<int> *GetShares() const {static std::vector<int> z;return &z;}
  int GetVia() const {std::abort();}
  int GetViaWithRestricted(bool&) const {std::abort();}
};
using FlowStatMap=std::map<int,FlowStat>;
struct GoodsEntry { FlowStatMap flows; };
struct VehicleCargoList {
  enum MoveToAction {MTA_TRANSFER,MTA_DELIVER,MTA_KEEP,MTA_LOAD};
  using Iterator=std::list<CargoPacket *>::iterator;
  uint count=0,action_counts[4]={};
  Money feeder_share=0;
  std::list<CargoPacket *> packets;
  void AssertCountConsistency() {}
  static MoveToAction ChooseAction(const CargoPacket *,StationID,StationID,bool,StationIDStack);
  bool Stage(bool,StationID,StationIDStack,uint8_t,const GoodsEntry *,CargoPayment *,TileIndex);
};
"""
DRIVER=r"""
int main() {
  char kind;
  while(std::cin >> kind) {
    if(kind=='T') {
      int loaded,unloaded,retry,full_slice,reservation,gradual,not_full,finished,mode,wait,lateness,elapsed,first;
      std::cin>>loaded>>unloaded>>retry>>full_slice>>reservation>>gradual>>not_full>>finished>>
               mode>>wait>>lateness>>elapsed>>first;
      Vehicle u;
      u.current_order={wait,mode,OT_LOADING,12};
      u.current_order_time=elapsed;
      u.lateness_counter=lateness;
      if(finished) SetBit(u.vehicle_flags,VF_LOADING_FINISHED);
      _settings_game.order.gradual_loading=gradual;
      RoadPulse(&u,loaded,unloaded,retry,full_slice,reservation,not_full);
      // RoadVehController increments immediately before HandleLoading.
      ++u.current_order_time;
      u.HandleLoading(!first);
      std::cout<<u.load_unload_ticks<<","<<HasBit(u.vehicle_flags,VF_STOP_LOADING)<<","
               <<HasBit(u.vehicle_flags,VF_LOADING_FINISHED)<<","<<u.refreshed<<","<<u.left<<"\n";
    } else if(kind=='S') {
      int flags,accept,n;
      std::cin>>flags>>accept>>n;
      VehicleCargoList v;
      std::vector<CargoPacket> p(n);
      for (int i=0;i<n;i++) {
        p[i].id=i+1;
        std::cin>>p[i].first_station>>p[i].count;
        v.count+=p[i].count;
        v.packets.push_back(&p[i]);
      }
      GoodsEntry g;
      CargoPayment payment;
      bool staged=v.Stage(accept,12,{},flags,&g,&payment,0);
      std::cout<<staged<<"|";
      for (auto x:v.action_counts) std::cout<<x<<",";
      std::cout<<"|";
      for (auto *p:v.packets) std::cout<<p->id<<",";
      std::cout<<"\n";
    } else std::abort();
  }
}
"""
LUA=r"""
local base="mods/luanttd_core/"
local T=dofile(base.."openttd/loading_timing.lua")
local P=dofile(base.."openttd/passengers.lua")
local L=dofile(base.."road_loading_runtime.lua")(T,P)
local function b(v) return v and 1 or 0 end
for line in io.lines() do
  local a={}
  for part in line:gmatch("%S+") do a[#a+1]=tonumber(part) or part end
  if a[1]=="T" then
    local delay,stop,complete,refresh=T.pulse({
      loaded=a[2],unloaded=a[3],retry_unload=a[4]==1,full_slice=a[5]==1,reservations=a[6],
      gradual=a[7]==1,cargo_not_full=a[8]==1,finished=a[9]==1,full=a[10]==2 or a[10]==3,
      wait=a[11],lateness=a[12],elapsed=a[13]})
    local leave=T.can_leave(a[14]==1,complete,a[13]+1,a[11],a[12])
    print(table.concat({delay,b(stop),b(complete),b(refresh),b(leave)},","))
  else
    local v={id=3,cargo="passenger",batches={}}
    local st={id=12,stock={passenger={}}}
    for i=1,a[4] do
      local first=a[3+i*2]
      v.batches[i]={tag=i,origin_station=first>=0 and first or nil,units=a[4+i*2]}
    end
    local flags=a[2]
    local l=L.begin(st,v,2000,{force_unload=flags%2==1,transfer=math.floor(flags/2)%2==1,
      no_unload=math.floor(flags/4)%2==1},{accepts=function() return a[3]==1 end})
    local t,d,k,packets=0,0,0,{}
    for _,x in ipairs(l.unload) do
      if x.action=="transfer" then t=t+x.packet.units else d=d+x.packet.units end
      packets[#packets+1]=x.packet.tag..","
    end
    for _,x in ipairs(v.batches) do k=k+x.units;packets[#packets+1]=x.tag.."," end
    print(b(l.unloading).."|"..t..","..d..","..k..",0,|"..table.concat(packets))
  end
end
"""

def extract(s,name):
    start=s.index(name)
    return s[start:s.index("\n}",start)+2]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    def read(n):
        d=a.source/n
        return d.read_text() if d.exists() else (a.source/"src"/n).read_text()
    eco=read("economy.cpp")
    block=extract(eco,"static void LoadUnloadVehicle(Vehicle *front)")
    rules=block[block.index("ClrBit(front->vehicle_flags, VF_STOP_LOADING)"):
                block.index("/* Calculate the loading indicator")]
    prelude=r"""
void RoadPulse(Vehicle *front,int loaded,int unloaded,bool retry,bool sliced,int reserved,bool not_full) {
  Station *st=nullptr;
  int new_load_unload_ticks=loaded+unloaded;
  bool anything_loaded=loaded>0,anything_unloaded=unloaded>0 || retry;
  CargoTypes full_load_amount=sliced,reservation_left=reserved,cargo_not_full=not_full,cargo_full=!not_full;
"""
    timer=extract(eco,"static void UpdateLoadUnloadTicks(")
    veh=extract(read("vehicle.cpp"),"void Vehicle::HandleLoading(bool mode)")
    pkt=read("cargopacket.cpp")
    stage=extract(pkt,"bool VehicleCargoList::Stage(")
    choose=extract(pkt,"/* static */ VehicleCargoList::MoveToAction VehicleCargoList::ChooseAction(")
    defs=timer+"\n"+prelude+rules+"\n}\n"+veh+"\n"+choose+"\n"+stage+"\n"
    rng=random.Random(141)
    cases=[]
    for _ in range(24000):
        vals=(rng.randrange(9),rng.randrange(9),rng.randrange(2),rng.randrange(2),
              rng.randrange(4),rng.randrange(2),rng.randrange(2),rng.randrange(2),
              rng.choice([0,2,3,4]),rng.randrange(400),rng.randrange(-150,150),
              rng.randrange(600),rng.randrange(2))
        cases.append("T "+" ".join(map(str,vals)))
    for _ in range(8000):
        n=rng.randrange(25)
        args=(rng.randrange(8),rng.randrange(2),n)
        cargo=[f"{rng.choice([-1,3,5,12,12])} {rng.randrange(1,39)}" for _ in range(n)]
        cases.append("S "+" ".join(map(str,args))+" "+" ".join(cargo))
    data=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(SHIM+defs+DRIVER)
        (d/"test.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        stock=subprocess.check_output([str(d/"stock")],input=data).splitlines()
        port=subprocess.check_output([a.lua,str(d/"test.lua")],input=data,cwd=ROOT).splitlines()
    assert len(stock)==len(port)==len(cases)
    for i,(want,got) in enumerate(zip(stock,port)):
        if want!=got: raise AssertionError(f"{cases[i]}: OpenTTD {want!r} != Lua {got!r}")
    print("PASS: 24,000 compiled OpenTTD loading/leave decisions and 8,000 manual packet staging/order cases")

if __name__=="__main__":
    main()
