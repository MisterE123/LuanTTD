"""Compile OpenTTD 14.1 original startup, calendar-month and reliability.

Usage: python3 tests/stock_engine_calendar_upstream.py SOURCE_TREE [lua5.1]
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "engine.cpp":"b2bbfc2fb77e4b9695730b5e7623f0311e8f7d4d75dbc4fcd166d4ac08691db9",
    "engine_base.h":"ef9035208650931638ffe15c41913b204972125d4463fdd0fe425e5c41756c8b",
    "table/engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "core/random_func.cpp":"6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3",
    "timer/timer_game_common.h":"99cd3d7f24d8539d9de72cea942b566911ce7e5cebc1e19e22eddfa368b988cf",
    "vehicle_type.h":"a941b74ff14f5b930a11430debd518370e0c338dbc49f3a7d7a51ad7f1da8c7c",
})

LUA=r"""
local E=dofile("mods/bayline/openttd/stock_engine_calendar.lua")
for row in io.lines() do
  local a={}
  for v in row:gmatch("%d+") do a[#a+1]=tonumber(v) end
  if row:sub(1,1)=="d" then
    local date=assert(E.date(a[1],a[2],a[3]))
    local y,m,d=E.ymd(date)
    print(date,y,m,d)
  else
    local cfg={starting_year=a[1],startup_date=a[2],generation_seed=a[4],startup_seed=a[5],
      climate=a[6],never_expire=a[7]==1,aging_stop_year=a[8]}
    local row=assert(E.stock(a[9]))
    row.stock_id=a[10]
    local m=assert(E.prepare_original(row,cfg))
    local r=assert(E.snapshot(m,a[3]))
    print(m.base_date,r.intro_date,r.age_months,r.public and 1 or 0,r.engine_available_flag and 1 or 0,
      r.phase1,r.phase2,r.phase3,r.reliability_start,r.reliability_max,r.reliability_final,
      r.reliability,r.reliability_decay,m.startup_age)
  end
end
"""

def cpp(tree):
    ec,eb,stock,rng,cal,veh=(src(tree,p) for p in (
        "engine.cpp","engine_base.h","table/engines.h","core/random_func.cpp",
        "timer/timer_game_common.h","vehicle_type.h"))
    assert "int32_t age;" in eb
    row=block(stock,r"^static const EngineInfo _orig_engine_info\[\]")
    wanted={}
    for d,decay,life,model,clim,id in re.findall(
        r"^\s*MR\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*CT_PASSENGERS\s*,\s*([^)]*)\),\s*//\s*(\d+) ",
        row,re.M):
        if 116<=int(id)<=118: wanted[int(id)]=(d,decay,life,model,clim.strip())
    assert set(wanted)=={116,117,118}
    core=r"""
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
using byte=uint8_t;
using uint=unsigned;
using CompanyMask=uint16_t;
#define MAX_UVALUE(x) std::numeric_limits<x>::max()
"""
    core+=block(veh,r"^enum VehicleType : byte")+";\n"
    core+=r"""
struct Value {
 int v;
 constexpr Value(int v=0):v(v){}
 constexpr int base()const{return v;}
 constexpr operator int()const{return v;}
 friend constexpr Value operator+(Value a,Value b){return a.v+b.v;}
 friend constexpr Value operator+(Value a,int b){return a.v+b;}
};
struct TimerGameCalendar {
 using Year=Value;
 using Date=Value;
 using Month=uint8_t;
 using Day=uint8_t;
 struct YearMonthDay {Year year;Month month;Day day;};
 static Date date;
 static Year year;
"""
    core+=block(cal,r"^\s*static constexpr Date DateAtStartOfYear\(")+"\n"
    core+=block(cal,r"^\s*static constexpr bool IsLeapYear\(")+r"""
 static int MonthLength(Year y, int m) {
   constexpr int ml[]{31,28,31,30,31,30,31,31,30,31,30,31};
   return ml[m]+(m==1 && IsLeapYear(y));
 }
 static Date ConvertYMDToDate(Year y, Month m, Day d) {
    int day=DateAtStartOfYear(y)+d-1;
    for (int i=0;i<m;i++) day+=MonthLength(y,i);
    return day;
 }
 static YearMonthDay ConvertDateToYMD(Date d) {
   int lo=0,hi=5000001;
   while (lo+1<hi) {
     int mid=(lo+hi)/2;
     if (DateAtStartOfYear(mid)<=d) lo=mid;
     else hi=mid;
   }
   int rem=d-DateAtStartOfYear(lo),m=0;
   while(rem>=MonthLength(lo,m)){rem-=MonthLength(lo,m);m++;}
   return {lo,Month(m),Day(rem+1)};
 }
};
Value TimerGameCalendar::date{},TimerGameCalendar::year{};
namespace CalendarTime { constexpr int DAYS_IN_YEAR=365,DAYS_IN_LEAP_YEAR=366; }
enum class ExtraEngineFlags : int {None=0,SyncReliability=1,NoPreview=2};
ExtraEngineFlags operator&(ExtraEngineFlags a,ExtraEngineFlags b){return ExtraEngineFlags(int(a)&int(b));}
constexpr int INVALID_ENGINE=-1,STR_NEWGRF_INVALID_ENGINE=-2,ENGINE_AVAILABLE=1,ENGINE_EXCLUSIVE_PREVIEW=2,
   INVALID_COMPANY=-1,WC_BUILD_VEHICLE=0,WC_REPLACE_VEHICLE=1,T=1,A=2,S=4,Y=8;
int _year_engine_aging_stops=2050;
struct Settings {
 struct {uint32_t generation_seed;int starting_year;int landscape;} game_creation;
 struct {bool never_expire_vehicles;} vehicle;
} _settings_game;
bool HasBit(uint32_t n,int b){return (n>>b)&1;}
uint32_t GB(uint32_t n,int start,int length){return (n>>start)&((1u<<length)-1);}
struct EngineInfo {
 Value base_intro,lifelength,base_life;
 int decay_speed,climates,retire_early=0,variant_id=INVALID_ENGINE,string_id=0;
 ExtraEngineFlags extra_flags=ExtraEngineFlags::None;
};
struct Engine {
 EngineInfo info;
 int index,type=VEH_ROAD;
 Value intro_date;
 int32_t age;
 uint16_t reliability,reliability_spd_dec,reliability_start,reliability_max,reliability_final;
 uint16_t duration_phase_1,duration_phase_2,duration_phase_3;
 byte flags;
 CompanyMask company_avail,company_hidden,preview_asked;
 int preview_company;
 static Engine *only;
 static auto Iterate(){return std::array<Engine*,1>{only};}
 static Engine *Get(int){assert(false);return nullptr;}
 bool IsEnabled()const;
 uint32_t GetGRFID()const{return 0;}
};
Engine *Engine::only;
void ClearLastVariant(int,int){}
void AddRemoveEngineFromAutoreplaceAndBuildWindows(int){}
void InvalidateWindowClassesData(int){}
void SetWindowClassesDirty(int){}
bool IsVehicleTypeDisabled(int,bool){return false;}
bool IsWagon(int){return false;}
struct Randomizer {uint32_t state[2];uint32_t Next();void SetSeed(uint32_t);};
Randomizer _random,_interactive_random;
struct SavedRandomSeeds {Randomizer a,b;};
void SaveRandomSeeds(SavedRandomSeeds *s){s->a=_random;s->b=_interactive_random;}
void RestoreRandomSeeds(const SavedRandomSeeds &s){_random=s.a;_interactive_random=s.b;}
uint32_t Random(){return _random.Next();}
"""
    core+="\n".join(block(rng,p) for p in (
        r"^uint32_t Randomizer::Next\(\)",r"^void Randomizer::SetSeed",r"^void SetRandomSeed"))
    publish=block(ec,r"^static void NewVehicleAvailable\(")
    share=re.search(r"e->flags = \(e->flags.*?ENGINE_AVAILABLE;",publish)[0]
    rights=re.search(r"e->company_avail = MAX_UVALUE\(CompanyMask\);",publish)[0]
    core+=f"\nstatic void NewVehicleAvailable(Engine *e){{{share}{rights}}}\n"
    core+="\n".join(block(ec,p) for p in (
        r"^bool Engine::IsEnabled",r"^void StartupOneEngine",r"^void CalcEngineReliability",
        r"^void CalendarEnginesMonthlyLoop"))
    core+=r"""
int main(){
 const int base=TimerGameCalendar::DateAtStartOfYear(1920);
 EngineInfo roads[]={
"""
    for id in range(116,119):
        d,decay,life,model,clim=wanted[id]
        core+=f"{{base+{d},{life},{model},{decay},{clim}}},\n"
    core+=r"""
 };
 char kind;
 while(std::cin>>kind){
   if(kind=='d'){
      int y,m,d;std::cin>>y>>m>>d;
      auto a=TimerGameCalendar::ConvertYMDToDate(y,m-1,d);
      auto cur=TimerGameCalendar::ConvertDateToYMD(a);
      std::cout<<a<<' '<<cur.year<<' '<<int(cur.month)+1<<' '<<int(cur.day)<<'\n';
      continue;
   }
   assert(kind=='m');
   int first,start,now,climate,never,freeze,id,index;
   uint32_t generation,seed;
   std::cin>>first>>start>>now>>generation>>seed>>climate>>never>>freeze>>id>>index;
   _settings_game={{generation,first,climate},{bool(never)}};
   _year_engine_aging_stops=freeze;
   TimerGameCalendar::date=start;
   TimerGameCalendar::year=TimerGameCalendar::ConvertDateToYMD(start).year;
   Engine e;
   e.info=roads[id-116];e.index=index;
   Engine::only=&e;
   SetRandomSeed(0xDDDD0714);
   StartupOneEngine(&e,TimerGameCalendar::ConvertDateToYMD(std::min(start,
      TimerGameCalendar::DateAtStartOfYear(freeze).base())),seed);
   assert(_random.state[0]==0xDDDD0714 && _random.state[1]==0xDDDD0714);
   CalcEngineReliability(&e,false);
   int startup_age=e.age;
   auto a=TimerGameCalendar::ConvertDateToYMD(start);
   auto b=TimerGameCalendar::ConvertDateToYMD(now);
   int im=int(a.year)*12+a.month+1;
   int end=std::min(int(b.year)*12+b.month,freeze*12-1);
   for(;im<=end;im++){
      TimerGameCalendar::year=im/12;
      TimerGameCalendar::date=TimerGameCalendar::ConvertYMDToDate(im/12,im%12,1);
      CalendarEnginesMonthlyLoop();
   }
   std::cout<<e.info.base_intro<<' '<<e.intro_date<<' '<<e.age<<' '<<bool(e.company_avail)
      <<' '<<bool(e.flags&ENGINE_AVAILABLE)<<' '<<e.duration_phase_1<<' '<<e.duration_phase_2
      <<' '<<e.duration_phase_3<<' '<<e.reliability_start<<' '<<e.reliability_max
      <<' '<<e.reliability_final<<' '<<e.reliability<<' '<<e.reliability_spd_dec<<' '<<startup_age<<'\n';
 }
}
"""
    return core


def jan1(y):
    return 0 if y==0 else 365*y+(y-1)//4-(y-1)//100+(y-1)//400+1


def cases():
    r=random.Random(1410118)
    dates=[("d",y,m,d) for y in (0,1,4,99,100,399,400,1899,1900,1920,1950,1999,2000,2050,2100,2400,5000000)
        for m,d in [(1,1),(2,28),(3,1),(6,15),(12,31)]]
    for _ in range(3800):
        y=r.randrange(5000001)
        dates.append(("d",y,r.randint(1,12),r.randint(1,28)))
    modes=[]
    for _ in range(8700):
        y=r.choice([0,1920,1950,1986,2049,2050,2400,5000000,r.randint(1750,2190)])
        start=jan1(y)+r.choice([0,1,59,364,r.randrange(3650)])
        start=min(start,jan1(5000001)-1)
        now=min(start+r.choice([0,1,30,365,r.randrange(73000)]),jan1(5000001)-1)
        gen,seed=r.randrange(2**32),r.randrange(2**32)
        cl,never,stop,i=r.randrange(4),r.randrange(2),r.choice([2050,2051,2500]),r.randint(116,118)
        modes.append(("m",y,start,now,gen,seed,cl,never,stop,i,i))
    # Deliberately dense around actual same-month startup, public
    # introduction, retirement, and a synthetic same-date sibling whose
    # reliability seed differs only by the engine index bits.
    for i,offset in enumerate((3378,16071,24107),116):
        base=jan1(1920)+offset
        y=1920
        for off in range(0,1200,5):
            for startup in (jan1(y),base+off):
                for asset in (i,515):
                    now=max(startup,base+off)
                    modes.append(("m",y,startup,now,1751,97721,0,0,2050,i,asset))
    for y in range(1960,2060):
        for i in (116,117,118):
            for seed in (0,1,2**32-1):
                modes.append(("m",1950,jan1(1950),jan1(y)+55,1751,seed,0,0,2050,i,i))
    return dates,modes


def main():
    tree=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    dates,models=cases()
    rows=dates+models
    data="".join(" ".join(map(str,x))+"\n" for x in rows)
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(tree))
        (p/"runtime.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++20","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        ref=subprocess.check_output([p/"ref"],input=data,text=True,cwd=ROOT).splitlines()
        port=subprocess.check_output([lua,p/"runtime.lua"],input=data,text=True,cwd=ROOT).splitlines()
    assert len(ref)==len(port)==len(rows)
    for row,a,b in zip(rows,ref,port):
        if a.split()!=b.split():
            raise AssertionError((row,a,b))
    print(f"PASS: pinned Gregorian calendar {len(dates)} cases, original road engine startup/public life {len(models)} cases")


if __name__=="__main__":
    main()
