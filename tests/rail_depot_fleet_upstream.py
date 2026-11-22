"""Compare stock rail design ages, public sale and reliability to pinned 14.1.

python3 tests/rail_depot_fleet_upstream.py SOURCE_TREE [lua5.1]
"""
from pathlib import Path
import re
import random
import subprocess
import sys
import tempfile
from rail_roster_upstream import ROOT, block, src

LUA=r"""
local R=dofile("mods/luanttd_core/openttd/rail_roster.lua")
local F=dofile("mods/luanttd_core/rail_depot_fleet.lua")({}, {}, R)
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local s={day=0}
  assert(F.initialize(s,{starting_year=a[1],generation_seed=a[2],startup_random=a[3],
    climate=a[4],never_expire=a[5]==1}))
  s.day=a[6]
  local out={}
  for _,r in ipairs(F.catalog(s)) do
    local p=r.availability
    for _,v in ipairs({p.public and 1 or 0,p.intro,p.age_months,p.phase1,p.phase2,p.phase3,
        p.reliability_start,p.reliability_max,p.reliability_final,p.reliability,p.reliability_decay}) do
      out[#out+1]=string.format("%.0f",v)
    end
  end
  print(table.concat(out," "))
end
"""


def cpp(tree):
    engine=src(tree,"engine.cpp")
    engines=src(tree,"table/engines.h")
    random_src=src(tree,"random_func.cpp")
    start=block(engine,r"^void StartupOneEngine")
    seed_impl=start[start.index("SavedRandomSeeds saved_seeds;"):start.index("/* Get parent variant index")]
    seed_impl=seed_impl[seed_impl.index("SetRandomSeed"):seed_impl.index("if (e->intro_date")]
    seed_impl=seed_impl.replace("e->type", "0").replace("e->GetGRFID()", "0")
    phases=start[start.index("/* Base reliability defined"):start.index("RestoreRandomSeeds(saved_seeds)")]
    seed_parts=start.partition("SetRandomSeed(_settings_game.game_creation.generation_seed ^ seed ^")[2]
    seed_parts="SetRandomSeed(_settings_game.game_creation.generation_seed ^ seed ^"+seed_parts.partition("SetRandomSeed(_settings_game.game_creation.generation_seed ^ seed ^")[2].split("/* Base reliability")[0]
    seed_parts=seed_parts.replace("re->","e->").replace("e->type","0").replace("e->GetGRFID()","0")
    assert "if (this->u.rail.railveh_type == RAILVEH_WAGON) this->info.base_life = 0xFF;" in engine
    ids=[0,1,8,9,10,11,15,27,29,30,32]
    rows={}
    for base,decay,life,model,clim,id in re.findall(
      r"^\s*M[TWM]\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),[^,]+,([^)]*)\),\s*//\s*(\d+) (?:Kirby Paul Tank|MJS 250|Chaney|Ginzu|SH '8P'|Manley-Morel|Floss|Passenger Carriage|Coal Truck|Oil Tanker|Goods Van)",
      engines,re.M):
        if int(id) not in ids: continue
        rows[int(id)]=(base,decay,life,"255" if int(id) in (27,29,30,32) else model,clim.strip())
    assert set(ids)==set(rows)
    header=r"""
#include <algorithm>
#include <bit>
#include <chrono>
#include <climits>
#include <cstdint>
#include <iostream>
using uint=unsigned int;
using namespace std::chrono;
constexpr int T=1,A=2,S=4,Y=8,INVALID_ENGINE=-1;
enum class ExtraEngineFlags {None, SyncReliability};
ExtraEngineFlags operator&(ExtraEngineFlags a,ExtraEngineFlags b){return ExtraEngineFlags(unsigned(a)&unsigned(b));}
struct Scalar {int v;int base()const{return v;}operator int()const{return v;}};
struct Settings {
 struct {uint32_t generation_seed;int starting_year;} game_creation;
 struct {bool never_expire_vehicles;} vehicle;
} _settings_game;
struct EngineInfo {
 Scalar base_intro;
 uint32_t decay_speed;
 Scalar lifelength,base_life;
 int climates,retire_early=0,variant_id=INVALID_ENGINE;
 ExtraEngineFlags extra_flags=ExtraEngineFlags::None;
};
struct Engine {
 EngineInfo info;
 int index,type=0,company_avail=0;
 uint32_t age=0;
 uint16_t reliability=0,reliability_start,reliability_max,reliability_final;
 int duration_phase_1,duration_phase_2,duration_phase_3,intro_date,reliability_spd_dec;
 static Engine *Get(int){std::abort();}
};
void ClearLastVariant(int,int){}
void AddRemoveEngineFromAutoreplaceAndBuildWindows(int){}
struct Randomizer {uint32_t state[2];uint32_t Next();void SetSeed(uint32_t);};
Randomizer gen;
void SetRandomSeed(uint32_t seed){gen.SetSeed(seed);}
uint32_t Random(){return gen.Next();}
uint32_t GB(uint32_t a,unsigned p,unsigned n){return (a>>p)&((1u<<n)-1);}
const auto origin=sys_days{year{0}/1/1};
namespace TimerGameCalendar {
 using Date=int;
 int ConvertYMDToDate(int year,int month,int day){return (sys_days{std::chrono::year{year}/(month+1)/day}-origin).count();}
}
int mon(int date){year_month_day d{origin+days{date}};return int(d.year())*12+unsigned(d.month())-1;}
int mon_ceil(int date){year_month_day d{origin+days{date}};return mon(date)+(unsigned(d.day())>1);}
"""
    init=r"""
void startup(Engine *e,uint32_t seed){
 const auto *ei=&e->info;
"""+seed_impl+seed_parts+phases+r"""
 e->reliability_spd_dec=ei->decay_speed<<2;
}
int main(){
 int start,climate,elapsed,never;uint32_t generation,seed;
 while(std::cin>>start>>generation>>seed>>climate>>never>>elapsed){
  _settings_game={{generation,start},{bool(never)}};
  const int start_date=TimerGameCalendar::ConvertYMDToDate(start,0,1);
  const int origin1920=TimerGameCalendar::ConvertYMDToDate(1920,0,1);
  const int cutoff=2050*12;
  const int stop=mon(start_date+elapsed);
  Engine all[] = {
"""+",\n".join(
   f'{{{{{{origin1920+{rows[i][0]}}}, {rows[i][1]}, {{{rows[i][2]}}}, {{{rows[i][3]}}}, {rows[i][4]}}}, {i}}}' for i in ids)+r"""
  };
  bool first=true;
  for(auto& record:all){
   auto *e=&record;startup(e,seed);
   bool introduced=e->intro_date<=start_date;
   if (introduced) { e->age=std::max(0,std::min(mon(start_date),cutoff)-mon_ceil(e->intro_date)); e->company_avail=1; }
   bool enabled=e->info.climates&(1<<climate);
   if(!enabled){introduced=true;e->company_avail=0;}
   CalcEngineReliability(e,false);
   for(int month=mon(start_date)+1;month<=stop && month<cutoff;month++){
    if(introduced){e->age++;CalcEngineReliability(e,true);}
    if(enabled && !introduced && month>=mon_ceil(e->intro_date+365)){
     introduced=true;e->company_avail=1;
    }
   }
   if(!first)std::cout<<" ";first=false;
   std::cout<<e->company_avail<<" "<<e->intro_date<<" "<<e->age<<" "<<e->duration_phase_1<<" "<<e->duration_phase_2
      <<" "<<e->duration_phase_3<<" "<<e->reliability_start<<" "<<e->reliability_max<<" "<<e->reliability_final
      <<" "<<e->reliability<<" "<<e->reliability_spd_dec;
  }
  std::cout<<"\n";
 }
}
"""
    return header+block(random_src,r"^uint32_t Randomizer::Next\(\)")+block(random_src,r"^void Randomizer::SetSeed")+block(engine,r"^void CalcEngineReliability")+init


def main():
    tree=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    rng=random.Random(141)
    cases=[(rng.randint(1800,2100),rng.randrange(2**32),rng.randrange(2**32),rng.randrange(4),rng.randrange(2),
      rng.choice((0,1,rng.randrange(36600)))) for _ in range(4800)]
    cases.extend((1950,1751,9001,c,0,day) for c in range(4) for day in range(0,37000,13))
    cases.extend((1930,1751,9001,c,never,day)
        for c in (0,1) for never in (0,1) for day in range(0,18000,19))
    cases.extend((1966,1751,9001,c,never,day)
        for c in (0,1) for never in (0,1) for day in range(0,32000,31))
    samples="".join(" ".join(map(str,row))+"\n" for row in cases)
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)
        (p/"ref.cpp").write_text(cpp(tree))
        (p/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        ref=subprocess.check_output([p/"ref"],input=samples,text=True,cwd=ROOT).splitlines()
        port=subprocess.check_output([lua,p/"port.lua"],input=samples,text=True,cwd=ROOT).splitlines()
    assert len(ref)==len(port)==len(cases)
    for i,(a,b) in enumerate(zip(ref,port)):
        if a!=b:
            a,b=list(map(int,a.split())),list(map(int,b.split()))
            j=next(k for k,(aa,bb) in enumerate(zip(a,b)) if aa!=bb)
            raise AssertionError((cases[i],j//11,j%11,a[j],b[j]))
    print(f"PASS: {len(cases)*8} pinned stock rail intro, sales availability, age and seeded reliability design snapshots")


if __name__=="__main__":
    main()
