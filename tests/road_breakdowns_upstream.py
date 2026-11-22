"""Deterministic differential against OpenTTD 14.1 road breakdown source.

Usage: python tests/road_breakdowns_upstream.py SOURCE_TREE [lua5.1]
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "vehicle.cpp": "1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
    "roadveh_cmd.cpp": "facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45",
    "core/random_func.hpp": "b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef",
    "timer/timer_game_common.h": "99cd3d7f24d8539d9de72cea942b566911ce7e5cebc1e19e22eddfa368b988cf",
    "table/settings/difficulty_settings.ini": "a396cb3d32b3bcc19dd41f52426b4bc032da55065ce0b9fe194c3f189bd6d7b8",
})

CPP = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
using uint=unsigned;
using byte=uint8_t;
struct Year {constexpr Year(int n):n(n){} int n; constexpr int base()const{return n;} constexpr operator int()const{return n;}};
struct Date {constexpr Date(int n):n(n){} int n; constexpr int base()const{return n;} constexpr operator int()const{return n;}};
namespace TimerGameCalendar {int date;}
namespace TimerGameEconomy {int date;}
enum {VEH_ROAD=0,VEH_TRAIN,VEH_SHIP,VEH_AIRCRAFT};
enum {GM_NORMAL,GM_MENU};
enum {VS_STOPPED=1,VS_CRASHED=2,VS_HIDDEN=4,VS_AIRCRAFT_BROKEN=8};
enum {WC_VEHICLE_VIEW,WC_VEHICLE_DETAILS,WC_ROADVEH_LIST};
enum {LT_TEMPERATE,LT_TOYLAND};
enum {SND_10_BREAKDOWN_TRAIN_SHIP,SND_0F_BREAKDOWN_ROADVEHICLE,SND_3A_BREAKDOWN_TRAIN_SHIP_TOYLAND,SND_35_BREAKDOWN_ROADVEHICLE_TOYLAND};
enum {OT_LOADING=1,VSE_BREAKDOWN,EV_BREAKDOWN_SMOKE};
constexpr int EF_NO_BREAKDOWN_SMOKE=0,PFE_GL_ROADVEHS=0,EXPENSES_ROADVEH_RUN=0;
int _game_mode=GM_NORMAL;
struct {
 struct {bool no_servicing_if_no_breakdowns;} order;
 struct {int vehicle_breakdowns;} difficulty;
 struct {int landscape;} game_creation;
} _settings_game;
struct PerformanceAccumulator {PerformanceAccumulator(int){}};
uint32_t rword;
unsigned calls;
bool details_dirty,start_event,effect,train_crashed,last_speed_called;
uint32_t Random(){calls++;return rword;}
uint32_t GB(uint32_t v,unsigned shift,unsigned width){return (v>>shift)&((1u<<width)-1);}
template<typename T>T ClampTo(int x){return std::clamp(x,0,int(std::numeric_limits<T>::max()));}
struct Engine {uint16_t reliability;};
struct Vehicle {
 Engine engine;
 int type=VEH_ROAD,vehstatus=0,engine_type=0,index=0;
 bool front=true;
 byte tick_counter=0;
 uint16_t reliability=0,reliability_spd_dec=0;
 byte breakdown_chance=0,breakdown_ctr=0,breakdown_delay=0,breakdowns_since_last_service=0;
 int32_t age=0,max_age=0,date_of_last_service=0,date_of_last_service_newgrf=0;
 uint16_t cur_speed=0;
 struct {int kind=0;bool IsType(int k){return kind==k;}} current_order;
 Engine *GetEngine(){return &engine;}
 Vehicle *Next(){return nullptr;}
 bool HasEngineType(){return true;}
 bool IsPrimaryVehicle(){return front;}
 void MarkDirty(){}
 bool HandleBreakdown();
};
struct Train: Vehicle {
 static Train *From(Vehicle *v){return static_cast<Train*>(v);}
 bool IsEngine(){return true;}
};
struct RoadVehicle : Vehicle {
 uint16_t blocked_ctr=0;
 byte reverse_ctr=0,day_counter=0;
 uint16_t running_ticks=0;
 int current_order_time=0,owner=0;
 int64_t profit_this_year=0;
 int64_t GetRunningCost()const{return 0;}
 bool IsFrontEngine(){return front;}
 void SetLastSpeed(){last_speed_called=true;}
 void OnNewCalendarDay();
 void OnNewEconomyDay();
 bool Tick();
};
struct EffectVehicle {int animation_state=0;} u;
void SetWindowDirty(int type,int){if(type==WC_VEHICLE_DETAILS)details_dirty=true;}
void SetWindowClassesDirty(int){}
void SndPlayVehicleFx(int,Vehicle*){}
bool PlayVehicleSound(Vehicle*,int){start_event=true;return false;}
struct EngineInfo {int misc_flags=0;} e;
const EngineInfo *EngInfo(int){return &e;}
bool HasBit(int v,int bit){return (v>>bit)&1;}
EffectVehicle *CreateEffectVehicleRel(Vehicle*,int,int,int,int){effect=true;return &u;}
bool RoadVehCheckTrainCrash(RoadVehicle*){return train_crashed;}
bool RoadVehIsCrashed(RoadVehicle*){return false;}
void EconomyAgeVehicle(Vehicle*){}
void DecreaseVehicleValue(Vehicle*){}

"""
RUN = r"""
int main(){
  RoadVehicle v;
  std::string op;
  while(std::cin>>op){
    unsigned flags=0,spd=0,scheduled=0,doubled=0,hold=0,recovered=0;
    details_dirty=start_event=effect=train_crashed=last_speed_called=false;u.animation_state=0;calls=0;
    v.vehstatus=0;v.current_order.kind=0;v.front=true;
    if(op=="I"){
      v=RoadVehicle{};
      unsigned rel,dec,tick,chance,ctr,delay,n;
      std::cin>>rel>>dec>>v.age>>v.max_age>>tick>>chance>>ctr>>delay>>n>>v.date_of_last_service>>v.date_of_last_service_newgrf;
      v.reliability=rel;v.reliability_spd_dec=dec;v.tick_counter=tick;v.breakdown_chance=chance;
      v.breakdown_ctr=ctr;v.breakdown_delay=delay;v.breakdowns_since_last_service=n;
    }else if(op=="E"){
      int d;
      std::cin>>d>>flags>>v.blocked_ctr>>spd>>rword;
      _settings_game.difficulty.vehicle_breakdowns=d;
      _settings_game.order.no_servicing_if_no_breakdowns=flags&1;
      v.vehstatus=(flags&2)?VS_STOPPED:0;_game_mode=(flags&4)?GM_MENU:GM_NORMAL;
      v.front=!(flags&8);v.cur_speed=spd;
      auto ctr=v.breakdown_ctr;
      v.OnNewEconomyDay();
      scheduled=ctr==0&&v.breakdown_ctr!=0;
    }else if(op=="C"){
      std::cin>>flags;v.front=!(flags&1);
      int previous=v.age;
      v.OnNewCalendarDay();
      for(int y=0;y<=4;y++){
        if(v.front && (previous!=v.age || v.age==CalendarTime::MAX_DATE) &&
            v.age-v.max_age==TimerGameCalendar::DateAtStartOfYear(y)) doubled=1;
      }
    }else if(op=="T"){
      std::cin>>flags>>spd;v.cur_speed=spd;
      v.front=!(flags&1);v.current_order.kind=(flags&2)?OT_LOADING:0;
      v.vehstatus=(flags&4?VS_CRASHED:0)|(flags&8?VS_HIDDEN:0)|(flags&64?VS_STOPPED:0);
      e.misc_flags=(flags&16?1<<EF_NO_BREAKDOWN_SMOKE:0);train_crashed=flags&32;
      bool controller_held=v.Tick();
      hold=v.front&&controller_held&&!last_speed_called;
      recovered=hold&&v.breakdown_ctr==0;
    }else if(op=="S"){
      std::cin>>_settings_game.difficulty.vehicle_breakdowns>>v.engine.reliability>>TimerGameEconomy::date>>TimerGameCalendar::date;
      VehicleServiceInDepot(&v);
    }else assert(false);
    if(op=="I")continue;
    std::cout<<v.reliability<<" "<<v.reliability_spd_dec<<" "<<v.age<<" "<<v.max_age<<" "<<int(v.tick_counter)
      <<" "<<int(v.breakdown_chance)<<" "<<int(v.breakdown_ctr)<<" "<<int(v.breakdown_delay)
      <<" "<<int(v.breakdowns_since_last_service)<<" "<<v.date_of_last_service<<" "<<v.date_of_last_service_newgrf
      <<" "<<calls<<" "<<scheduled<<" "<<(op=="E"&&details_dirty)<<" "<<doubled
      <<" "<<(op=="T"?v.cur_speed:0)<<" "<<hold<<" "<<start_event<<" "<<recovered
      <<" "<<(effect?u.animation_state:-1)<<"\n";
  }
}
"""

LUA = r"""
local B=dofile("mods/luanttd_core/openttd/road_breakdowns.lua")
local s
local function bit(flags,n) return math.floor(flags/2^n)%2==1 end
local function num(b) return b and 1 or 0 end
for line in io.lines() do
  local op=line:sub(1,1)
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  local calls,scheduled,dirty,doubled,speed,hold,started,recovered,smoke=0,false,false,false,0,false,false,false,-1
  if op=="I" then
    local keys={"reliability","reliability_spd_dec","age","max_age","tick_counter","breakdown_chance","breakdown_ctr",
      "breakdown_delay","breakdowns_since_last_service","date_of_last_service","date_of_last_service_newgrf"}
    s={}
    for i,k in ipairs(keys) do s[k]=q[i] end
  elseif op=="E" then
    local f=q[2]
    scheduled,dirty=B.economy_day(s,{difficulty=q[1],no_servicing_if_no_breakdowns=bit(f,0),stopped=bit(f,1),
      menu=bit(f,2),front=not bit(f,3),blocked_ctr=q[3],cur_speed=q[4]},function() calls=calls+1; return q[5] end)
  elseif op=="C" then
    doubled=B.calendar_day(s,{front=not bit(q[1],0)})
  elseif op=="T" then
    local f=q[1]
    local out=B.tick(s,{front=not bit(f,0),loading=bit(f,1),crashed=bit(f,2) or bit(f,5),
      hidden=bit(f,3),no_breakdown_smoke=bit(f,4),stopped=bit(f,6),cur_speed=q[2]})
    speed,hold,started,recovered,smoke=out.cur_speed,out.hold_motion,out.started,out.recovered,out.smoke_animation_state or -1
  else
    B.service(s,q[2],q[3],q[4],q[1])
  end
  if op~="I" then
    print(table.concat({s.reliability,s.reliability_spd_dec,s.age,s.max_age,s.tick_counter,s.breakdown_chance,s.breakdown_ctr,
      s.breakdown_delay,s.breakdowns_since_last_service,s.date_of_last_service,s.date_of_last_service_newgrf,
      calls,num(scheduled),num(dirty),num(doubled),speed,num(hold),num(started),num(recovered),smoke}," "))
  end
end
"""


def cpp(tree):
    v = src(tree, "vehicle.cpp")
    road = src(tree, "roadveh_cmd.cpp")
    cal = src(tree, "timer/timer_game_common.h")
    config = src(tree, "table/settings/difficulty_settings.ini").split("var      = difficulty.vehicle_breakdowns", 1)[1]
    assert "def      = 1\nmin      = 0\nmax      = 2" in config.split("[SDT_", 1)[0]
    out = CPP + "namespace TimerGameCalendar {\n"
    out += block(cal, r"^\s+static constexpr Date DateAtStartOfYear") + "}\n"
    out += "struct CalendarTime {\n" + next(x for x in cal.splitlines() if " MAX_YEAR =" in x).replace("typename TimerGame<T>::", "") + "\n"
    out += next(x for x in cal.splitlines() if " MAX_DATE =" in x).replace("typename TimerGame<T>::", "").replace("TimerGame<T>::", "TimerGameCalendar::") + "\n};\n"
    out += block(src(tree, "core/random_func.hpp"), r"^inline bool Chance16I")
    start = v.index("static const byte _breakdown_chance")
    end = v.index("/**\n * Update economy age",start)
    out += v[start:end]
    for name in ("VehicleServiceInDepot", "AgeVehicle"):
        fn = block(v, rf"^void {name}")
        if name == "AgeVehicle":
            # Stop before owner-specific advice/UI; all age/decay code above is verbatim.
            fn = fn.split("/* Don't warn about vehicles",1)[0] + "}\n"
        out += fn
    out += block(road, r"^void RoadVehicle::OnNewCalendarDay")
    daily = block(road, r"^void RoadVehicle::OnNewEconomyDay")
    out += daily.split("CheckIfRoadVehNeedsService(this);",1)[0] + "}\n"
    # Reproduce actual host tick/early controller order up through
    # HandleBreakdown and the player stop gate; the rest is not reliability.
    out += block(road, r"^static bool RoadVehController").split("ProcessOrders(v);",1)[0] + "return false;\n}\n"
    out += block(road, r"^bool RoadVehicle::Tick")
    return out + RUN


def scenarios():
    rng = random.Random(1416624)
    for t in range(9600):
        n = rng.choice([0,0,0,0,1,2,3,63,126,255])
        rel = rng.choice([rng.randrange(65536),1024*(t%64)+rng.choice([-1,0,1,1023])]) % 65536
        age = rng.choice([15*366-1,15*366,1826212864,1826212865,0,5,19*366-5,rng.randrange(60000)])
        maxage = rng.choice([0,15*366,1826212865] if t%5 else [max(0, age-q) for q in [0,365,730,1095,1460]])
        yield ("I",rel,rng.choice([0,80,81,32768,52444,65535]),age,maxage,
               rng.randrange(256),rng.randrange(256),n,rng.randrange(256),rng.randrange(256),-rng.randrange(8),rng.randrange(3000))
        for j in range(rng.randint(1,10)):
            op = rng.choice(("E","E","E","T","T","C","S"))
            if op=="E":
                flags=rng.choice([0,1,1,1,1,1,2,3,4,5,8,9,15])
                word=rng.choice([0,2620,2621,2622,2**32-1,rng.randrange(2**32)])
                yield "E",rng.randrange(3),flags,rng.choice([0,0,0,1,65535]),rng.choice([0,1,4,5,6,127,65535]),word
            elif op=="T":
                yield "T",rng.choice([0,0,0,2,4,8,16,32,64,127]),rng.choice([0,4,5,120,65535])
            elif op=="C":
                yield "C",rng.choice([0,0,0,1])
            else:
                yield "S",rng.randrange(3),rng.randrange(65536),rng.randrange(50000),rng.randrange(5000000)
    # Pinned boundary matrix for every reliability bucket, all RNG low-half
    # boost boundary, all modes, speed guards, and guaranteed regular ticks.
    for rel in range(0,65536,1024):
        for r in (0x7f3f0000,0x803f0a3c,0x113f0a3d,0x913f0a3e,0xffffffff):
            for diff in (0,1,2):
                for chance in (0,1,3,7,25,127,245,254,255):
                    yield "I",rel,0,0,1,255,chance,0,0,255,-1,-1
                    yield "E",diff,1,0,5,r
                    for _ in range(4):
                        yield "T",0,25


def main():
    tree = Path(sys.argv[1])
    lua = sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    samples = list(scenarios())
    payload = "".join(" ".join(map(str, item))+"\n" for item in samples)
    with tempfile.TemporaryDirectory(prefix="luanttd-road-breakdown-") as work:
        work=Path(work)
        (work/"ref.cpp").write_text(cpp(tree))
        (work/"test.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",work/"ref.cpp","-o",work/"ref"],check=True)
        a=subprocess.run([work/"ref"],input=payload,text=True,capture_output=True,cwd=ROOT,check=True).stdout.splitlines()
        b=subprocess.run([lua,work/"test.lua"],input=payload,text=True,capture_output=True,cwd=ROOT,check=True).stdout.splitlines()
    steps=[x for x in samples if x[0]!="I"]
    assert len(a)==len(b)==len(steps)
    for i,(x,y) in enumerate(zip(a,b)):
        assert x==y,(i,steps[i],x,y)
    print(f"PASS: {len(a):,} stock road breakdown state transitions match compiled OpenTTD 14.1")


if __name__=="__main__":
    main()
