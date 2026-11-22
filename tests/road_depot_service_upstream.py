"""Differential OpenTTD 14.1 road servicing threshold and detour decisions.

Usage: python tests/road_depot_service_upstream.py SOURCE_TREE [lua5.1]
The pathfinder lookup uses injected costs/reachability, not guessed distances.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "vehicle.cpp": "1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
    "ground_vehicle.cpp": "62486015e19a0211cf8b572acd88681c6c5321a942e2357a9cab2a98bb9aba5a",
    "roadveh_cmd.cpp": "facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45",
    "order_cmd.cpp": "458bd35b50c639f01b61c3b3617c1cbcba23fc140379140b6bda209998de8e5c",
    "order_base.h": "8defa7426d8ea87f73da14a0faecf41e12da9046905b1954d78d4fbf55377c04",
    "order_type.h": "738a2dbf386e4f4832b11f6c43d4b6824fa871a3b6287c71ef459d579c57ffb2",
    "timer/timer_game_economy.h": "71b85a167292bc793a6a6c74eb2901efcccb3a0fe9fb1b6cd3ac490f4a2e72d0",
    "pathfinder/pathfinder_type.h": "d96905e55d17150686b10b4095d34393e5537b9ce1c0456e07adddc3de13d664",
    "pathfinder/pathfinding_settings.ini": "8d5e898307aa12be1f9fee610caaafa76f902c4ed8c3217167e011fc4dc7bd80",
    "core/random_func.hpp": "b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef",
})


CPP_HEADER = r"""
#include <cstdint>
#include <cstdlib>
#include <climits>
#include <cassert>
#include <iostream>
#include <vector>
using byte=uint8_t;
using uint=unsigned;
using Money=int64_t;
using TileIndex=int;
using DepotID=int;
using CargoID=int;
using CargoTypes=uint64_t;
using EngineID=int;
using TransportType=int;
using VehicleType=int;
constexpr int VEH_TRAIN=0,VEH_ROAD=1,TRANSPORT_RAIL=0,TRANSPORT_ROAD=1;
constexpr int VPF_NPF=1,VPF_YAPF=2,VS_STOPPED=1,VS_CRASHED=2,GVF_SUPPRESS_IMPLICIT_ORDERS=2;
constexpr int WC_VEHICLE_VIEW=1,WID_VV_START_STOP=1,INVALID_TILE=-1,INVALID_ENGINE=-1,CARGO_NO_REFIT=255;
#define NOT_REACHED() std::abort()
uint GB(uint v,uint start,uint bits){return (v>>start)&((1u<<bits)-1);}
template<typename T,typename V> void SB(T &dest,uint start,uint bits,V value){
 uint mask=((1u<<bits)-1)<<start;
 dest=(dest&~mask)|((unsigned(value)<<start)&mask);
}
template<typename T> bool HasBit(T v,int bit){return (uint64_t(v)>>bit)&1;}
template<typename T> void SetBit(T &v,int bit){v|=1<<bit;}
bool HasAtMostOneBit(uint64_t n){return (n&(n-1))==0;}
bool IsValidCargoID(CargoID cargo){return cargo>=0&&cargo<64;}
"""
CPP_HOST = r"""
namespace TimerGameEconomy {
 int date; bool wallclock;
 bool UsingWallclockUnits(){return wallclock;}
}
struct {
 struct {bool no_servicing_if_no_breakdowns;} order;
 struct {int vehicle_breakdowns;} difficulty;
 struct {int pathfinder_for_roadvehs; struct {uint maximum_go_to_depot_penalty;} npf,yapf;} pf;
} _settings_game;
uint rword; int random_calls,query_calls,query_mode,query_cap,service_calls;
bool order_dirty,road_depot_here;
TileIndex vehicle_tile;
int depot_id(TileIndex t){return t+2000;}
DepotID GetDepotIndex(TileIndex t){return depot_id(t);}
bool IsRoadDepotTile(TileIndex t){return road_depot_here&&t==vehicle_tile;}
bool IsDepotTypeTile(TileIndex t,TransportType tr){return tr==TRANSPORT_ROAD&&IsRoadDepotTile(t);}
uint Random(){random_calls++;return rword;}
void SetWindowWidgetDirty(int,int,int){order_dirty=true;}
struct Company {
 int index=0;
 struct {
  bool engine_renew=false;int engine_renew_months;
  Money engine_renew_money;struct {uint servint_roadveh;} vehicle;
 } settings;
 static Company *Get(int);
} company;
Company *Company::Get(int){return &company;}
Money money;
Money GetAvailableMoney(int){return money;}
struct Engine {
 uint16_t reliability;
 uint64_t company_avail;
 Money price;
 Money GetCost()const{return price;}
 static Engine *Get(EngineID e);
} original,replacement;
Engine *Engine::Get(EngineID){return &replacement;}
bool replace_when_old,has_replacement;
CargoID current_cargo;
CargoTypes union_refit,refit_mask;
EngineID EngineReplacementForCompany(const Company*,EngineID,int,bool *when){
 *when=replace_when_old;return has_replacement?1:INVALID_ENGINE;
}
void GetArticulatedRefitMasks(EngineID,bool,CargoTypes *u,CargoTypes *m){*u=union_refit;*m=refit_mask;}
CargoTypes GetCargoTypesOfArticulatedParts(EngineID){return 0;}
struct Vehicle {
 int owner=0,type=VEH_ROAD,index=0,engine_type=0,group_id=0,age=0,max_age=0,date_of_last_service=0,vehstatus=0;
 TileIndex tile=0;
 uint16_t cur_speed=0,reliability=0,service_interval=0;
 bool percent=false;
 Order current_order;
 std::vector<const Order*> list;
 const std::vector<const Order*>& Orders()const{return list;}
 const Engine *GetEngine() const{return &original;}
 uint16_t GetServiceInterval()const{return service_interval;}
 bool ServiceIntervalIsPercent()const{return percent;}
 bool NeedsServicing()const;
 bool NeedsAutomaticServicing()const;
 bool NeedsAutorenewing(const Company*,bool)const;
 bool HasDepotOrder()const;
};
CargoTypes GetCargoTypesOfArticulatedVehicle(const Vehicle*,CargoID *id){
 *id=current_cargo;return IsValidCargoID(*id)?(uint64_t(1)<<*id):0;
}
struct Train : Vehicle {
 static const Train *From(const Vehicle *v){return static_cast<const Train*>(v);}
 const Train *GetNextUnit()const{return nullptr;}
 bool IsEngine()const{return true;}
};
template<class T,VehicleType Type> struct GroundVehicle : Vehicle {
 const T *First()const{return static_cast<const T*>(this);}
 bool IsChainInDepot()const;
};
struct RouteCache {bool cleared=false;void clear(){cleared=true;}};
struct RoadVehicle:GroundVehicle<RoadVehicle,VEH_ROAD> {
 RouteCache path;
 TileIndex dest_tile;
 bool depot_state=false,front=true;
 int gv_flags=0,day_counter=0,blocked_ctr=0;
 bool IsInDepot()const{return depot_state;}
 const RoadVehicle *Next()const{return nullptr;}
 bool IsFrontEngine()const{return front;}
 void SetDestTile(TileIndex);
 void OnNewEconomyDay();
};
void VehicleServiceInDepot(Vehicle*){service_calls++;}
void EconomyAgeVehicle(Vehicle*){}
void DecreaseVehicleValue(Vehicle*){}
void CheckVehicleBreakdown(Vehicle*){}
FindDepotData injected;
FindDepotData NPFRoadVehicleFindNearestDepot(const RoadVehicle*,int max_distance){
 ++query_calls;query_mode=VPF_NPF;query_cap=max_distance;return injected;
}
FindDepotData YapfRoadVehicleFindNearestDepot(const RoadVehicle*,int max_distance){
 ++query_calls;query_mode=VPF_YAPF;query_cap=max_distance;return injected;
}
"""

RUN = r"""
int main(){
 uint flags;
 while(std::cin>>flags){
  RoadVehicle v;
  int mode,order_kind,order_type,non_stop,order_action,dest,refit,has_list,diff,canbuy,canrefit,chain;
  uint npf,yapf;
  std::cin>>v.service_interval>>company.settings.vehicle.servint_roadveh>>v.reliability>>original.reliability
   >>v.date_of_last_service>>TimerGameEconomy::date>>v.age>>v.max_age>>v.cur_speed>>diff
   >>order_kind>>order_type>>non_stop>>order_action>>dest>>refit>>has_list
   >>mode>>npf>>yapf>>v.tile>>v.dest_tile>>injected.tile>>injected.best_length>>rword
   >>chain>>canbuy>>replace_when_old>>company.settings.engine_renew_months>>canrefit>>current_cargo
   >>union_refit>>company.settings.engine_renew_money>>money>>replacement.price;
  v.current_order.type=order_kind|(non_stop<<6);
  v.current_order.flags=order_type|(order_action<<3);
  v.current_order.dest=dest;v.current_order.refit_cargo=refit;
  Order listed;listed.type=OT_GOTO_DEPOT;if(has_list)v.list.push_back(&listed);
  v.vehstatus=(flags&1?VS_STOPPED:0)|(flags&2?VS_CRASHED:0);
  v.percent=flags&4; TimerGameEconomy::wallclock=flags&8;
  _settings_game.order.no_servicing_if_no_breakdowns=flags&16;
  road_depot_here=flags&32;v.depot_state=flags&64;v.front=!(flags&128);
  _settings_game.difficulty.vehicle_breakdowns=diff;
  _settings_game.pf.pathfinder_for_roadvehs=mode;
  _settings_game.pf.npf.maximum_go_to_depot_penalty=npf;
  _settings_game.pf.yapf.maximum_go_to_depot_penalty=yapf;
  vehicle_tile=v.tile;has_replacement=chain!=0;replacement.company_avail=canbuy;
  refit_mask=canrefit&&IsValidCargoID(current_cargo)?uint64_t(1)<<current_cargo:0;
  bool due=v.NeedsServicing(),automatic=v.NeedsAutomaticServicing(),here=v.IsChainInDepot();
  random_calls=query_calls=query_mode=query_cap=service_calls=0;order_dirty=false;
  v.OnNewEconomyDay();
  int decision=service_calls?1:order_dirty?(v.current_order.IsType(OT_DUMMY)?2:4):random_calls?3:0;
  std::cout<<due<<" "<<automatic<<" "<<here<<" "<<decision<<" "
   <<query_calls<<" "<<query_mode<<" "<<query_cap<<" "<<random_calls<<" "
   <<int(v.current_order.GetType())<<" "<<v.current_order.GetDepotOrderType()<<" "<<v.current_order.GetNonStopType()
   <<" "<<v.current_order.GetDepotActionType()<<" "<<v.current_order.dest<<" "<<v.current_order.refit_cargo
   <<" "<<v.dest_tile<<" "<<v.path.cleared<<" "<<HasBit(v.gv_flags,GVF_SUPPRESS_IMPLICIT_ORDERS)<<"\n";
 }
}
"""

LUA = r"""
local S=dofile("mods/luanttd_core/openttd/road_depot_service.lua")
local kind={[0]="nothing","goto_station","goto_depot","loading","leave","dummy"}
local number={};for k,v in pairs(kind) do number[v]=k end
local action={none=0,service_here=1,cancel=2,keep=3,route=4}
local function bit(flags,n) return math.floor(flags/2^n)%2==1 end
local function num(b) return b and 1 or 0 end
for line in io.lines() do
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  local f=q[1]
  local h={reliability=q[4],date_of_last_service=q[6],age=q[8],max_age=q[9]}
  local order={kind=kind[q[12]],depot_type=q[13],non_stop=q[14],depot_action=q[15],destination=q[16],refit=q[17]}
  local ctx={
    stopped=bit(f,0),crashed=bit(f,1),percent=bit(f,2),wallclock=bit(f,3),no_servicing_if_no_breakdowns=bit(f,4),
    tile_is_road_depot=bit(f,5),depot_state=bit(f,6),front=not bit(f,7),
    interval=q[2],company_service_interval=q[3],engine_reliability=q[5],economy_date=q[7],cur_speed=q[10],
    difficulty=q[11],current_order=order,orders=q[18]==1 and {{kind="goto_depot"}} or {},
    pathfinder=q[19]==1 and S.NPF or S.YAPF,npf_max_depot_penalty=q[20],yapf_max_depot_penalty=q[21],
    tile=q[22],depot=q[22]+2000,dest_tile=q[23],
  }
  local function replacement()
    if q[27]==0 then return end
    return {engine_available=q[28]==1,replace_when_old=q[29]==1,renew_months=q[30],
      accepts_current_cargo=q[31]==1,cargo_valid=q[32]>=0 and q[32]<64,has_refit_union=q[33]~=0,
      reserve_money=q[34],available_money=q[35],replacement_price=q[36]}
  end
  local calls,mode,cap,rands=0,0,0,0
  local plan=S.plan(h,ctx,{
    replacement=replacement,
    nearest=function(which,max_penalty)
      calls,mode,cap=calls+1,which==S.NPF and 1 or 2,max_penalty
      return {tile=q[24],depot=q[24]+2000,cost=q[25]}
    end,
    random32=function() rands=rands+1;return q[26] end,
  })
  local dest=ctx.dest_tile
  if plan.kind=="route" then
    order=plan.order;order.refit=order.no_refit and 255;dest=plan.dest_tile
  elseif plan.kind=="cancel" then
    order.kind=plan.order.kind;order.depot_type=0;order.non_stop=0;order.depot_action=0
  end
  print(table.concat({num(S.needs_servicing(h,ctx,replacement)),
    num(S.needs_automatic_servicing(h,ctx,replacement)),num(S.in_depot(ctx)),action[plan.kind],
    calls,mode,cap,rands,number[order.kind],order.depot_type,order.non_stop,order.depot_action,order.destination,
    order.refit,dest,num(plan.clear_cached_path),num(plan.suppress_implicit_orders)}," "))
end
"""


def cpp(tree):
    v = src(tree,"vehicle.cpp")
    road = src(tree,"roadveh_cmd.cpp")
    setup = CPP_HEADER + declarations(src(tree,"order_type.h"),
        [r"enum OrderType\s*:",r"enum OrderNonStopFlags\s*\{",r"enum OrderDepotTypeFlags\s*\{",r"enum OrderDepotActionFlags\s*\{"])
    setup += "struct Order {byte type=0,flags=0; int dest=0,refit_cargo=255;"
    setup += """
void SetRefit(CargoID);
void MakeDummy();
void MakeGoToDepot(DepotID,OrderDepotTypeFlags,OrderNonStopFlags=ONSF_NO_STOP_AT_INTERMEDIATE_STATIONS,
 OrderDepotActionFlags=ODATF_SERVICE_ONLY,CargoID=CARGO_NO_REFIT);
"""
    ob = src(tree,"order_base.h")
    for name in ("GetType","GetNonStopType","GetDepotOrderType","GetDepotActionType","SetNonStopType",
                 "SetDepotOrderType","SetDepotActionType","IsType"):
        setup += block(ob, rf"^\s*inline \w+ {name}\(")
    setup += "};\n"
    settings = src(tree,"pathfinder/pathfinding_settings.ini")
    path = src(tree,"pathfinder/pathfinder_type.h")
    for mode in ("npf","yapf"):
        unit=f"{mode.upper()}_TILE_LENGTH"
        assert re.search(rf"{unit}\s*=\s*100;",path)
        section=settings.split(f"var      = pf.{mode}.maximum_go_to_depot_penalty",1)[1]
        assert f"def      = 20 * {unit}" in section.split("[SDT_",1)[0]
    setup += declarations(path,[r"struct FindDepotData"])
    setup += "struct EconomyTime {\n"+next(x for x in src(tree,"timer/timer_game_economy.h").splitlines()
        if " DAYS_IN_ECONOMY_MONTH =" in x)+"\n};\n"+CPP_HOST
    core=src(tree,"core/random_func.hpp")
    setup += block(core,r"^inline bool Chance16I")+block(core,r"^inline bool Chance16\(")
    for name in ("MakeDummy","MakeGoToDepot","SetRefit"):
        setup += block(src(tree,"order_cmd.cpp"),rf"^void Order::{name}\(")
    setup += block(src(tree,"order_cmd.cpp"),r"^bool Vehicle::HasDepotOrder\(")
    for name in ("NeedsAutorenewing","NeedsServicing","NeedsAutomaticServicing"):
        setup += block(v,rf"^bool Vehicle::{name}\(")
    setup += "template <class T,VehicleType Type>\n"+block(src(tree,"ground_vehicle.cpp"),r"^bool GroundVehicle<T, Type>::IsChainInDepot")
    for pattern in (r"^static FindDepotData FindClosestRoadDepot",r"^void RoadVehicle::SetDestTile",
                    r"^static void CheckIfRoadVehNeedsService"):
        setup += block(road,pattern)
    daily=block(road,r"^void RoadVehicle::OnNewEconomyDay")
    setup += daily.split("CheckOrders(this);",1)[0]+"}\n"
    return setup+RUN


def samples():
    rng=random.Random(14119351)
    u=2**32-1
    for i in range(22000):
        flags=rng.choice((0,0,0,0,4,4,8,8,16,16,16,32,32,48,64,96,112,128,rng.randrange(256)))
        interval=rng.randrange(101) if flags&4 else rng.randrange(2000)
        previous=rng.randint(300,10000)
        threshold=interval*(30 if flags&8 else 1)
        today=previous+threshold+rng.choice((-1,0,1,20,10000))
        design=rng.randrange(65536)
        rel=max(0,min(65535,design*(100-interval)//100+rng.choice((-20,-1,0,1,1000)))) if flags&4 else rng.randrange(65536)
        mode=rng.choice((1,2))
        npf,yapf=[rng.choice((0,300,2000,5000)) for _ in range(2)]
        cap=npf if mode==1 else yapf
        cost=rng.choice((u,0,max(cap-1,0),cap,cap+1,rng.randrange(6000)))
        old_age=rng.randrange(6000)
        renew_months=rng.randrange(-12,13)
        age=max(0,old_age+30*renew_months+rng.choice((-1,0,1,1000)))
        reserve=rng.randrange(50000)
        price=rng.randrange(40000)
        money=rng.choice((0,reserve-1 if reserve else 0,reserve,reserve+2*price-1,reserve+2*price,200000))
        yield (flags,interval,rng.choice((0,40,150)),rel,design,previous,today,age,old_age,
            rng.choice((0,0,2,90)),rng.choice((0,0,1,2)),rng.choice((0,1,1,1,2,2,2,3,4,5)),
            rng.choice((0,1,1,1,2,3)),rng.randrange(4),rng.randrange(16),rng.randrange(5000,9999),rng.randrange(256),
            rng.choice((0,0,0,0,1)),mode,npf,yapf,101,rng.choice((401,402,101)),
            rng.choice((401,402)),cost,rng.choice((0,3276,3277,3278,u,rng.randrange(2**32))),
            rng.choice((0,1)),rng.choice((0,1)),rng.choice((0,1)),renew_months,rng.choice((0,1)),
            rng.choice((-1,0,10,63,64)),rng.choice((0,1)),reserve,money,price)


def main():
    source=Path(sys.argv[1]);lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    rows=list(samples())
    data="".join(" ".join(map(str,row))+"\n" for row in rows)
    with tempfile.TemporaryDirectory(prefix="luanttd-depot-service-") as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(source))
        (p/"test.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        a=subprocess.check_output([p/"ref"],input=data,text=True,cwd=ROOT).splitlines()
        b=subprocess.check_output([lua,p/"test.lua"],input=data,text=True,cwd=ROOT).splitlines()
    assert len(a)==len(b)==len(rows)
    actions=set()
    for i,(x,y) in enumerate(zip(a,b)):
        assert x==y,(i,rows[i],x,y)
        actions.add(int(x.split()[3]))
    assert actions==set(range(5))
    print(f"PASS: {len(a):,} stock service/depot decisions match compiled OpenTTD 14.1, all five decisions reached")


if __name__=="__main__":
    main()
