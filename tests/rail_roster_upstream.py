"""Differential stock rail purchase, consist, capacity and running ledger.

python3 tests/rail_roster_upstream.py SOURCE_TREE [lua5.1]
Compiles OpenTTD 14.1 core functions with a plain vanilla train/price shim.
NewGRF and company availability are outside the harness, not approximated.
"""
from pathlib import Path
import re
import random
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "table/engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "table/pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "table/cargo_const.h":"3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "engine.cpp":"b2bbfc2fb77e4b9695730b5e7623f0311e8f7d4d75dbc4fcd166d4ac08691db9",
    "train_cmd.cpp":"206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "train.h":"35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d",
    "company_cmd.cpp":"1cf942041d5b8729e8eeba102c838b2ecb693ac68609aee5336dd538f16ed0d8",
    "economy.cpp":"073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "ground_vehicle.cpp":"62486015e19a0211cf8b572acd88681c6c5321a942e2357a9cab2a98bb9aba5a",
    "cargotype.cpp":"ab55f017e6dce9a87d48bab64a51d1b0365600bae719f5830785f3c16a555c51",
    "cargotype.h":"4b197ae98b933c63a147402b74a87a58b91b46d6685e960239f7683b01e3bef2",
    "core/random_func.cpp":"6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3",
    "timer/timer_game_common.h":"99cd3d7f24d8539d9de72cea942b566911ce7e5cebc1e19e22eddfa368b988cf",
    "strings.cpp":"023d253c2850e318a72520f18157e655b966c66b200401df1f316f1a0e651451",
    "vehicle_type.h":"a941b74ff14f5b930a11430debd518370e0c338dbc49f3a7d7a51ad7f1da8c7c",
})

LUA=r"""
local R=dofile("mods/bayline/openttd/rail_roster.lua")
for line in io.lines() do
  local n={}
  for s in line:gmatch("%d+") do n[#n+1]=tonumber(s) end
  local N,cf,rf,inf,freight,slope,track,platform,ticks,frac,years,gen,seed,gradual,penalty=n[1],n[2],n[3],n[4],n[5],n[6],n[7],n[8],n[9],n[10],n[11],n[12],n[13],n[14],n[15]
  local parts,limits={},{}
  local front
  for i=1,N do
    local a=16+(i-1)*6
    parts[i]={stock_id=n[a],cargo_count=n[a+1]}
    limits[i]=n[a+2]
    local half=n[a+5]
    if half==1 then front=i;parts[i].role="front"
    elseif half==2 then
      parts[i].role,parts[i].mate="rear",assert(front)
      parts[front].mate=i;front=nil
    end
  end
  local opts={construction_difficulty=cf,running_difficulty=rf,inflation=inf,freight_trains=freight,
    slope_steepness=slope,track_limits=limits,wagon_speed_limits=track==1}
  local s,e=R.stats(parts,opts);assert(s,e)
  local out={s.price,s.weight,s.max_weight,s.power,s.max_track_speed,s.display_max_speed,s.acceleration,
    s.air_drag,s.tractive_effort,s.axle_resistance,s.running_year_fp,s.total_length}
  local amount=R.day_running_charge(s.running_year_fp,ticks)
  local whole,left=R.debit_fraction(frac,amount)
  out[#out+1]=amount;out[#out+1]=whole;out[#out+1]=left
  local loaded,unloaded=0,0
  for i,part in ipairs(s.parts) do
    local offset=16+(i-1)*6
    local got=R.load_slice(parts[i],n[offset+3],gradual==1)
    local gave=math.min(n[offset+4],R.unload_slice(parts[i],gradual==1))
    loaded=loaded+got;unloaded=unloaded+gave
    local d=R.display(part.stock_id)
    for _,x in ipairs({part.price,part.weight,part.max_weight,part.capacity,s.coupling[i],part.slope_resistance,
      got,gave,R.introduction(part.stock_id,years,gen,seed),part.climates,part.load_amount,part.image_index,part.cargo_id or -1,part.liters_per_unit or 0,
      part.power,d.weight,d.capacity,part.purchase_charge}) do out[#out+1]=x end
  end
  out[#out+1]=R.loading_wait(s.total_length,platform,loaded,unloaded,{gradual_loading=gradual==1,platform_penalty=penalty==1})
  for i,v in ipairs(out) do out[i]=string.format("%.0f",v) end
  print(table.concat(out," "))
end
"""


def cpp(base):
    train=src(base,"train_cmd.cpp")
    h=src(base,"train.h")
    eng=src(base,"engine.cpp")
    econ=src(base,"economy.cpp")
    gr=src(base,"ground_vehicle.cpp")
    roster=src(base,"table/engines.h")
    prices=src(base,"table/pricebase.h")
    cargo=src(base,"table/cargo_const.h")
    parts=(0,1,8,9,10,11,15,23,24,27,29,30,32)
    def get(regex):
        tab=re.findall(regex,roster,re.M)
        return {int(i):values for values,i in tab if int(i) in parts}
    names=r"(?:Kirby Paul Tank|MJS 250|Chaney|Ginzu|SH '(?:8P|30|40)'|Manley-Morel|Floss|Passenger Carriage|Coal Truck|Oil Tanker|Goods Van)"
    orig_rails=get(r"^\s*RVI\(([^)]*)\),\s*//\s*(\d+) "+names)
    orig_engines=get(r"^\s*M[TWM]\(([^)]*)\),\s*//\s*(\d+) "+names)
    load_values={k:int(re.search(r"^#define "+k+r"\([^)]*\).*?\bb,\s*(\d+),",roster,re.M)[1]) for k in ("MT","MW","MM")}
    keys=("PR_BUILD_VEHICLE_TRAIN","PR_BUILD_VEHICLE_WAGON","PR_RUNNING_TRAIN_STEAM","PR_RUNNING_TRAIN_DIESEL","PR_RUNNING_TRAIN_ELECTRIC")
    base_rows=[re.search(r"\{\s*(\d+),\s*(PCAT_\w+)[^\n]*///< "+k+r"\b",prices).groups() for k in keys]
    out=r"""
#include <algorithm>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
using Money=int64_t;
using uint=unsigned;
using byte=uint8_t;
using VehicleType=int;
using CompanyID=int;
constexpr int VEH_TRAIN=0,RAILVEH_WAGON=1,RAILVEH_SINGLEHEAD=0,RAILVEH_MULTIHEAD=2,TILE_SIZE=16;
constexpr int EXPENSES_TRAIN_RUN=1,WC_VEHICLE_DETAILS=0,WC_VEHICLE_VIEW=0,WID_VV_START_STOP=0;
constexpr int VS_STOPPED=1,VRF_POWEREDWAGON=1,VEHICLE_LENGTH=8;
constexpr int GROUND_ACCELERATION=9800; // Guarded by separately pinned vehicle_type.h.
struct CalendarTime {static constexpr int DAYS_IN_YEAR=365;};
struct Ticks {static constexpr int DAY_TICKS=74;};
enum {PCAT_CONSTRUCTION,PCAT_RUNNING};
"""
    assert "GROUND_ACCELERATION = 9800" in src(base,"vehicle_type.h")
    out+="enum Price {"+",".join(keys)+",PR_END,INVALID_PRICE=99};\n"
    out+=r"""
constexpr Price PR_BEGIN=PR_BUILD_VEHICLE_TRAIN;
Price operator++(Price &a,int){Price prev=a;a=Price(a+1);return prev;}
struct PriceBase {int start_price,category;};
"""
    out+="PriceBase _price_base_specs[]={"+",".join("{"+a+","+b+"}" for a,b in base_rows)+"};\n"
    out+=r"""
Money _price[PR_END];
int _price_base_multiplier[PR_END]={};
struct {uint32_t inflation_prices;} _economy;
struct {
 struct {uint construction_cost,vehicle_costs;} difficulty;
 struct {uint freight_trains,train_slope_steepness;bool wagon_speed_limits;} vehicle;
 struct {bool station_length_loading_penalty,gradual_loading;} order;
} _settings_game;
#define NOT_REACHED() std::abort()
template <class T,class U,class V> auto Clamp(T n,U lo,V hi){return std::min(std::max(int64_t(n),int64_t(lo)),int64_t(hi));}
bool HasBit(int n,int bit){return (n&(1<<bit))!=0;}
int GB(uint32_t n,int bit,int width){return (n>>bit)&((1u<<width)-1);}
struct GRFFile {int price_base_multipliers[PR_END];};
"""
    start=econ.index("for (Price i = PR_BEGIN; i < PR_END; i++)",econ.index("void RecomputePrices()"))
    out+="void recompute(){"+block(econ[start:],r"^for \(Price i")+"}\n"
    out+="Money GetPrice(Price,uint,const GRFFile*,int=0);\n"+block(econ,r"^Money GetPrice\(")
    out+=r"""
using CargoID=int;
constexpr int NONE=0,PASS=1,COAL=2,OIL=3,GOODS=4;
struct CargoSpec {
 int weight;bool is_freight;
 static CargoSpec *Get(CargoID id);
 uint64_t WeightOfNUnitsInTrain(uint32_t n) const;
"""
    out+=block(src(base,"cargotype.h"),r"^\s*inline uint64_t WeightOfNUnits\(")+"};\n"
    pw=re.search(r"MK\(\s*\d+,\s*CT_PASSENGERS,\s*\d+,\s*(\d+),[^\n]*?\b(false|true),",cargo).groups()
    cw=re.search(r"MK\(\s*\d+,\s*CT_COAL,\s*\d+,\s*(\d+),[^\n]*?\b(false|true),",cargo).groups()
    oil_rows=re.findall(r"MK\(\s*(\d+),\s*CT_OIL,\s*\d+,\s*(\d+),[^\n]*?\b(false|true),[^\n]*?STR_LITERS",cargo)
    assert len(oil_rows)==2 and oil_rows[0]==oil_rows[1]
    oil_slot,ow,of=oil_rows[0]
    goods_slot,gw,gf=re.search(r"MK\(\s*(\d+),\s*CT_GOODS,\s*\d+,\s*(\d+),[^\n]*?\b(false|true),[^\n]*?STR_CRATES",cargo).groups()
    oil_liters=re.search(r"\{\s*([0-9.]+)\s*\},\s*STR_UNITS_VOLUME_SHORT_METRIC",src(base,"strings.cpp"))[1]
    out+=f"constexpr int OilSlot={oil_slot},OilLiters=int({oil_liters}),GoodsSlot={goods_slot};\n"
    out+=f"CargoSpec *CargoSpec::Get(CargoID id){{static CargoSpec spec[]={{ {{0,false}},{{{pw[0]},{pw[1]}}},{{{cw[0]},{cw[1]}}},{{{ow},{of}}},{{{gw},{gf}}} }};return &spec[id];}}\n"
    out+=block(src(base,"cargotype.cpp"),r"^uint64_t CargoSpec::WeightOfNUnitsInTrain")
    out+=r"""
enum {PROP_TRAIN_COST_FACTOR,PROP_TRAIN_RUNNING_COST_FACTOR,PROP_TRAIN_WEIGHT,PROP_TRAIN_SPEED,
  PROP_TRAIN_CARGO_CAPACITY,PROP_TRAIN_POWER};
struct Vehicle;
template <class T,class U> U GetEngineProperty(T,int,U u,const Vehicle *v=nullptr){return u;}
template <class T,class U> U GetVehicleProperty(T,int,U u){return u;}
struct Rail {
 int sprite,railveh_type,cost_factor,max_speed,power,weight,running_cost;
 Price running_cost_class;
 int capacity;
};
struct Engine {
 struct {Rail rail;} u;
 struct {int load_amount,cargo,climates,base_intro;} info;
 int index;
 const GRFFile *GetGRF() const{return nullptr;}
 uint DetermineCapacity(const Vehicle *v) const;
 uint GetDisplayWeight() const;
 Money GetCost() const;
};
"""
    # The three function body statements retain source shift, lookups and
    # separate purchase base for locomotives vs wagons exactly.
    engine_cost=block(eng,r"^Money Engine::GetCost")
    a=engine_cost.index("case VEH_TRAIN:")
    z=engine_cost.index("case VEH_SHIP:",a)
    q=engine_cost[a:z]
    ret=next(x for x in engine_cost.splitlines() if "return GetPrice" in x)
    out+="Money Engine::GetCost() const{Price base_price;uint cost_factor;switch(VEH_TRAIN){"+q+"}"+ret+"}\n"
    c=block(eng,r"^uint Engine::DetermineCapacity")
    c=c[c.index("case VEH_TRAIN:"):c.index("case VEH_ROAD:")]
    out+="uint Engine::DetermineCapacity(const Vehicle *v) const{uint capacity;switch(VEH_TRAIN){"+c+"}return capacity;}\n"
    out+=block(eng,r"^uint Engine::GetDisplayWeight")
    out=out.replace("switch (this->type)", "switch (VEH_TRAIN)").replace(
        "return GetEngineProperty(this->index, PROP_ROADVEH_WEIGHT, this->u.road.weight) / 4;", "std::abort();")
    out=out.replace("case VEH_ROAD:", "case 1:").replace("default: NOT_REACHED();","default: std::abort();")
    field={"G":"RAILVEH_SINGLEHEAD","W":"RAILVEH_WAGON","M":"RAILVEH_MULTIHEAD","RC_S":"PR_RUNNING_TRAIN_STEAM",
           "RC_D":"PR_RUNNING_TRAIN_DIESEL","RC_E":"PR_RUNNING_TRAIN_ELECTRIC","RC_W":"INVALID_PRICE","CT_NONE":"NONE","CT_PASSENGERS":"PASS","CT_COAL":"COAL","CT_OIL":"OIL","CT_GOODS":"GOODS",
           "T":"1","A":"2","S":"4","Y":"8"}
    out+="Engine engines[]={\n"
    for i in parts:
        data=[x.strip() for x in orig_rails[i].split(",")][:9]
        data=[field.get(x,x) for x in data]
        intro,decay,life,model,default,climate=[q.strip() for q in orig_engines[i].split(",")]
        climate="|".join(field[v] for v in climate.split("|"))
        load=load_values["MW" if i>=27 else "MM" if i==11 else "MT"]
        out+=" {{ {"+",".join(data)+"} },{"+f"{load},{field[default]},{climate},{intro}"+"},"+str(i)+"},\n"
    out+="};\n"
    out+=r"""
struct Cache {int cached_weight=0,cached_axle_resistance=0,cached_air_drag=0,cached_max_te=0,
 cached_max_track_speed=0,cached_veh_length=0,cached_total_length=0,cached_slope_resistance=0,
 cached_power=0,first_engine=0;};
struct Vehicle {
 const Engine *engine=nullptr;
 int type=VEH_TRAIN,load_unload_ticks=0,tile=1,vehstatus=0,index=1;
 Cache gcache;
 const Engine *GetEngine() const{return engine;}
 const Cache *GetGroundVehicleCache() const{return &gcache;}
};
void SetWindowDirty(int,int){}
void SetWindowWidgetDirty(int,int,int){}
template <class T,VehicleType Type> struct GroundVehicle:Vehicle {
 struct {uint16_t cached_max_speed=65535;} vcache;
 GroundVehicle *First(){return this;}
 void CargoChanged();
 void PowerChanged();
};
bool HasPowerOnRail(int,int){return true;}
int GetRailType(int){return 0;}
struct Train : GroundVehicle<Train,VEH_TRAIN> {
 uint16_t flags=0;
 int half=0,railtype=0;
 int engine_type=0,cargo_type=0,acceleration=0,limit=0;
 struct {int count=0;int StoredCount() const{return count;}} cargo;
 Train *following=nullptr;
 Train *Next() const{return following;}
 Train *GetNextVehicle() const{return following;}
 static Train *From(GroundVehicle *v){return static_cast<Train *>(v);}
 uint32_t GetPoweredPartPower(const Train*) const{return 0;}
 uint32_t GetTractiveEffort() const{return 76;}
 uint16_t GetMaxTrackSpeed() const{return limit;}
 uint16_t GetDisplayMaxSpeed() const{return vcache.cached_max_speed;}
 byte GetAirDrag() const{return 0;}
 uint32_t GetSlopeSteepness() const{return _settings_game.vehicle.train_slope_steepness;}
 bool IsMultiheaded() const{return engine->u.rail.railveh_type==RAILVEH_MULTIHEAD;}
 bool IsArticulatedPart() const{return false;}
 bool IsFrontEngine() const{return engine->u.rail.railveh_type!=RAILVEH_WAGON && half!=2;}
 bool IsFreeWagon() const{return !IsFrontEngine();}
 Money GetRunningCost() const;
 uint16_t GetMaxWeight() const;
 void UpdateAcceleration();
"""
    out=out.replace("capacity;\n};\nstruct Engine","capacity;int pow_wag_weight=0;\n};\nstruct Engine")
    out=out.replace("struct Train : GroundVehicle", "const Rail *RailVehInfo(int index){for(const auto &e:engines)if(e.index==index)return &e.u.rail;std::abort();}\nstruct Train : GroundVehicle")
    for name in ("CalcNextVehicleOffset","GetWeight","GetPower"):
        out+=block(h,rf"^\s*(?:inline )?\w+ {name}\(")
    out+="};\nbool UsesWagonOverride(const Train *){return false;}\n"
    for name in ("PowerChanged","CargoChanged"):
        out+="template <class T,VehicleType Type>\n"+block(gr,rf"^void GroundVehicle<T, Type>::{name}\(")
    for n in ("GetRunningCost","GetMaxWeight","UpdateAcceleration"):
        out+=block(train,rf"^\w+ Train::{n}\(")
    out+=r"""
struct CommandCost {
 int exp;Money amount;
 CommandCost(int e,Money a):exp(e),amount(a){}
 Money GetCost() const{return amount;}
 int GetExpensesType() const{return exp;}
};
struct Company {
 byte money_fraction=0;
 Money paid=0;
 static Company *Get(CompanyID){static Company c;return &c;}
};
void SubtractMoneyFromAnyCompany(Company *c,const CommandCost &q){c->paid+=q.GetCost();}
"""
    out+=block(src(base,"company_cmd.cpp"),r"^void SubtractMoneyFromCompanyFract")
    out+=r"""
struct Station {int platform;int GetPlatformLength(int) const{return platform;}};
"""
    out+=block(econ,r"^static void UpdateLoadUnloadTicks")
    load=block(econ,r"^static uint GetLoadAmount")
    out+="uint stock_load(Vehicle *v){"+next(x for x in load.splitlines() if "const Engine *e" in x)
    out+=next(x for x in load.splitlines() if "uint load_amount =" in x)+next(x for x in load.splitlines() if "return std::max" in x)+"}\n"
    out+="struct Randomizer{uint32_t state[2];uint32_t Next();void SetSeed(uint32_t);};\n"
    ran=src(base,"core/random_func.cpp")
    out+=block(ran,r"^uint32_t Randomizer::Next\(\)")+block(ran,r"^void Randomizer::SetSeed")
    cal=src(base,"timer/timer_game_common.h")
    out+=r"""
struct Year {int val;int base() const{return val;}bool operator==(int x) const{return val==x;}};
using Date=int;
"""
    out+=block(cal,r"^\s*static constexpr Date DateAtStartOfYear").replace("static constexpr Date","static Date")
    init=block(eng,r"^void StartupOneEngine")
    rand_line=next(x for x in init.splitlines() if "e->intro_date = ei->base_intro <=" in x)
    rand_line=rand_line.replace("e->intro_date","intro").replace("ei->base_intro","base_intro")
    rand_line=rand_line.replace("TimerGameCalendar::ConvertYMDToDate(_settings_game.game_creation.starting_year + 2, 0, 1)","DateAtStartOfYear({years+2})")
    rand_line=rand_line.replace("TimerGameCalendar::Date","Date")
    out+=r"""
int intro_date(int original,int years,uint32_t gen,uint32_t seed){
 int base_intro=DateAtStartOfYear({1920})+original;
 uint32_t hashed=gen^seed^uint32_t(base_intro);
 Randomizer rdm;rdm.SetSeed(hashed);
 uint32_t r=rdm.Next();
 int intro;
"""+rand_line+r"""
 return intro;
}
"""
    station_const=next(x for x in econ.splitlines() if "const uint gradual_loading_wait_time[]" in x)
    collect=block(train,r"^void Train::ConsistChanged")
    a=collect.index("if ((rvi_u->railveh_type != RAILVEH_WAGON")
    max_speed=block(collect[a:],r"^if \(\(rvi_u->railveh_type")
    daily=block(train,r"^void Train::OnNewEconomyDay")
    daily_line=next(x for x in daily.splitlines() if "CommandCost cost(EXPENSES_TRAIN_RUN, this->GetRunningCost()" in x)
    out+=r"""
int main(){
 int n,cf,rf,track,platform,ticks,frac,years,gradual,penalty;
 uint32_t inf,freight,slope,gen,seed;
 while(std::cin>>n>>cf>>rf>>inf>>freight>>slope>>track>>platform>>ticks>>frac>>years>>gen>>seed>>gradual>>penalty){
  _settings_game.difficulty={uint(cf),uint(rf)};
  _settings_game.vehicle={freight,slope,bool(track)};
  _settings_game.order={bool(penalty),bool(gradual)};
  _economy.inflation_prices=inf;
  recompute();
  std::vector<Train> parts(n);
  std::vector<int> take(n),drop(n);
  uint16_t max_speed=UINT16_MAX;
  Money purchase=0;
  int full=0;
  for(int i=0;i<n;i++){
   Train &p=parts[i];
   std::cin>>p.engine_type>>p.cargo.count>>p.limit>>take[i]>>drop[i]>>p.half;
   for(const auto &e:engines)if(e.index==p.engine_type)p.engine=&e;
   assert(p.engine);
   p.cargo_type=p.engine->info.cargo;
   p.following=i+1<n?&parts[i+1]:nullptr;
   const Train *u=&p;
   const Rail *rvi_u=&u->GetEngine()->u.rail;
"""+max_speed+r"""
   p.gcache.cached_veh_length=VEHICLE_LENGTH;
   assert((p.half!=0)==p.IsMultiheaded());
   if(p.half!=2) purchase+=p.engine->GetCost();
   full+=p.GetMaxWeight();
  }
  auto *head=&parts[0];
  head->vcache.cached_max_speed=max_speed;
  head->gcache.cached_total_length=n*VEHICLE_LENGTH;
  head->CargoChanged();
  head->UpdateAcceleration();
  auto shell=head->gcache;
  auto year=head->GetRunningCost();
  CommandCost charge(EXPENSES_TRAIN_RUN,year*ticks/(CalendarTime::DAYS_IN_YEAR*Ticks::DAY_TICKS));
  auto *company=Company::Get(0);company->paid=0;company->money_fraction=frac;
  SubtractMoneyFromCompanyFract(0,charge);
  std::cout<<purchase<<" "<<shell.cached_weight<<" "<<full<<" "<<shell.cached_power<<" "<<shell.cached_max_track_speed<<" "
    <<max_speed<<" "<<head->acceleration<<" "<<shell.cached_air_drag<<" "<<shell.cached_max_te<<" "<<shell.cached_axle_resistance<<" "
    <<year<<" "<<shell.cached_total_length<<" "<<charge.GetCost()<<" "<<company->paid<<" "<<int(company->money_fraction);
  int activity=0;
  for(int i=0;i<n;i++){
   auto *v=&parts[i];
   int load=stock_load(v),space=v->GetEngine()->DetermineCapacity(v);
   int taking=std::min(take[i],space-v->cargo.count);
   int dropping=std::min(drop[i],v->cargo.count);
   if(gradual){taking=std::min(taking,load);dropping=std::min(dropping,load);}
   activity+=taking+dropping;
   auto *e=v->GetEngine();
   Money cost=e->GetCost();
   std::cout<<" "<<(v->IsMultiheaded()?cost>>1:cost)<<" "<<v->GetWeight()<<" "<<v->GetMaxWeight()<<" "<<space<<" "<<v->CalcNextVehicleOffset()
        <<" "<<v->gcache.cached_slope_resistance<<" "<<taking<<" "<<dropping<<" "
        <<intro_date(v->engine->info.base_intro,years,gen,seed)<<" "<<v->engine->info.climates<<" "<<load<<" "<<v->engine->u.rail.sprite+(v->half==2)
        <<" "<<(v->engine->info.cargo==OIL?OilSlot:v->engine->info.cargo==GOODS?GoodsSlot:-1)<<" "<<(v->engine->info.cargo==OIL?OilLiters:0)
        <<" "<<v->GetPower()<<" "<<e->GetDisplayWeight()<<" "<<e->DetermineCapacity(nullptr)<<" "<<(v->half==2?0:cost);
  }
"""+station_const+r"""
  Station st{platform};
  UpdateLoadUnloadTicks(head,&st,activity==0?20:gradual?gradual_loading_wait_time[0]:activity);
  std::cout<<" "<<head->load_unload_ticks<<"\n";
 }
}
"""
    # Verify the oracle daily formula agrees with the declaration in source.
    out=out.replace("CommandCost charge(EXPENSES_TRAIN_RUN,year*ticks/(CalendarTime::DAYS_IN_YEAR*Ticks::DAY_TICKS));",
                    daily_line.replace("CommandCost cost","CommandCost charge").replace("this->GetRunningCost()","year").replace("this->running_ticks","ticks"))
    return out


def rows():
    r=random.Random(1412729)
    sizes={0:0,1:0,8:0,9:0,10:0,15:0,23:0,24:0,27:40,29:30,30:30,32:25}
    for t in range(7500):
        n=r.randint(1,60)
        if t%31==0: kinds=[(8,9,10,15,23,24)[(t//31)%6]]*n  # stock unsigned effort at the long/high-powered edge
        elif t%4==0: kinds=[r.choice([27,29,30,32]) for _ in range(n)]
        else:kinds=[r.choice(list(sizes)) for _ in range(n)]
        physical=[]
        pending=False
        if t%3==0: kinds=[11,*kinds]
        if t%13==0: kinds=[11,27,29,11,30,0,27,11]
        for k in kinds:
            if k<27 and pending: physical.append((11,2));pending=False
            if k==11: physical.append((11,1));pending=True
            else: physical.append((k,0))
        if pending: physical.append((11,2))
        a=[len(physical),r.randrange(3),r.randrange(3),r.choice([0,1,65536,73921,131072,r.randrange(2**32)]),
           r.randint(1,255),r.randint(0,10),r.randrange(2),r.randint(1,30),r.randint(0,12000),
           r.randrange(256),r.randint(1850,2000),r.randrange(2**32),r.randrange(2**32),r.randrange(2),r.randrange(2)]
        for k,half in physical:
            a.extend([k,r.randint(0,38 if half else sizes[k]),r.choice([0,0,0,42,64,95]),r.randint(0,100),r.randint(0,40),half])
        yield a


def main():
    base=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    samples=list(rows())
    data="".join(" ".join(map(str,x))+"\n" for x in samples)
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(base))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["g++","-O2","-std=c++20",str(p/"ref.cpp"),"-o",str(p/"ref")],check=True)
        cpp_result=subprocess.check_output([p/"ref"],input=data,text=True,cwd=ROOT).splitlines()
        lua_result=subprocess.check_output([lua,p/"port.lua"],input=data,text=True,cwd=ROOT).splitlines()
    assert len(cpp_result)==len(lua_result)==len(samples)
    for i,(c,l) in enumerate(zip(cpp_result,lua_result)):
        if c!=l:
            cr=[int(v) for v in c.split()]
            lr=[int(v) for v in l.split()]
            first=next((j for j,(a,b) in enumerate(zip(cr,lr)) if a!=b),min(len(cr),len(lr)))
            raise AssertionError((i,first,samples[i][:25],cr[first:first+5],lr[first:first+5]))
    print(f"PASS: {len(samples)} stock consist quotes/cache/ledger cases covering {sum(r[0] for r in samples)} rail vehicle rows")


if __name__=="__main__":
    main()
