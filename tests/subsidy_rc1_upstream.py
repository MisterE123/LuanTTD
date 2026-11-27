#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile the RC1 subsidy route selection and monthly dispatch against controlled inputs."""
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
import subprocess
import sys

sys.path.insert(0, str(Path.cwd() / "tests"))
from rc1_rail_foundation_shim import source_block

root = Path(sys.argv[1])
assert subprocess.check_output(["git","-C",root,"rev-parse","HEAD"],text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
src = root / "src"
kernel = Path(sys.argv[2]).resolve()
prefix = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <ranges>
#include <vector>
using uint=unsigned;
using TileIndex=int;
using CargoType=int;
using IndustryID=int;
using TownID=int;
using CompanyID=int;
constexpr int NUM_CARGO=8, LAST_MONTH=1;
#define NOT_REACHED() std::abort()
uint32_t first,second; uint draws=0;
uint32_t Random() {
 const uint32_t a=first,b=second,x=b^0x1234567F;
 first=a+((x>>7)|(x<<25))+1;
 return second=((a>>3)|(a<<29))-1;
}
uint32_t RandomRange(uint32_t cap) {++draws;return (uint64_t(Random())*cap)>>32;}
bool Chance16(uint16_t a,uint16_t b) {++draws; return (((Random()&0xFFFF)*b+b/2)>>16)<a;}
enum class SourceType:int {Industry=0,Town=1};
struct Source {
 static constexpr int Invalid=-1;
 int id; SourceType type;
 bool operator==(const Source &) const=default;
 int ToTownID()const{return id;}
 int ToIndustryID()const{return id;}
 void SetIndex(int n){id=n;}
 int GetFormat()const{return 0;}
 int GetNewsReference()const{return 0;}
};
enum class TownProductionEffect {Passengers};
struct CargoSpec {
 int id=0,name=0;
 int Index()const{return id;}
 bool IsValid()const{return id>=0 && id<7;}
 static const CargoSpec *Get(int);
 struct Categories {
  std::vector<const CargoSpec *> passengers;
  const auto &operator[](TownProductionEffect)const{return passengers;}
 };
 static Categories town_production_cargoes;
};
std::array<CargoSpec,NUM_CARGO> cargos;
const CargoSpec *CargoSpec::Get(int i){return &cargos.at(i);}
CargoSpec::Categories CargoSpec::town_production_cargoes;
bool IsValidCargoType(int i){return i>=0 && i<NUM_CARGO;}
struct CargoArray {
 std::array<int,NUM_CARGO> rows{};
 int &operator[](int i){return rows.at(i);}
 int GetCount(){return std::count_if(rows.begin(),rows.end(),[](int n){return n>0;});}
};
struct Town {
 struct {int population;} cache;
 int index,xy,mail,goods,pct_mail,pct_pass;
 int GetPercentTransported(int cargo)const{return cargo==0?pct_pass:pct_mail;}
 static Town *GetRandom();
 static Town *Get(size_t);
 static bool IsValidID(size_t i){return i<7 && Get(i)!=nullptr;}
 static size_t GetPoolSize(){return 7;}
 static size_t GetNumItems();
};
std::array<Town*,7> towns{};
Town *Town::Get(size_t n){return towns.at(n);}
size_t Town::GetNumItems(){return std::count_if(towns.begin(),towns.end(),[](auto p){return p!=nullptr;});}
struct Industry {
 struct History {unsigned production;uint8_t percent;uint8_t PctTransported()const{return percent;}};
 struct Cargo {int cargo;std::array<History,2> history;};
 std::array<Cargo,3> produced;
 int index,accepts;
 struct{int tile;} location;
 bool IsCargoAccepted(int cargo)const{return (accepts & (1<<cargo))!=0;}
 static Industry *GetRandom();
 static Industry *Get(size_t);
 static bool IsValidID(size_t i){return i<6 && Get(i)!=nullptr;}
 static size_t GetPoolSize(){return 6;}
 static size_t GetNumItems();
};
std::array<Industry*,6> industries{};
Industry *Industry::Get(size_t n){return industries.at(n);}
size_t Industry::GetNumItems(){return std::count_if(industries.begin(),industries.end(),[](auto p){return p!=nullptr;});}
struct TileArea {
 int tile;
 TileArea(int t,int w,int h):tile(t){assert(w==1&&h==1);}
 auto Expand(int r)const{assert(r==6);return *this;}
 const int *begin()const{return &tile;}
 const int *end()const{return &tile+1;}
};
enum class TileType {House}; bool IsTileType(int,TileType){return true;}
const Town &at(int tile){for(auto *p:towns)if(p && p->xy==tile)return *p;std::abort();}
void AddProducedCargo(int tile,CargoArray &array){array[0]=200;array[2]=at(tile).mail;array[5]=at(tile).goods;}
using CargoTypes=int;
void AddAcceptedCargo(int tile,CargoArray &array,CargoTypes &){array[2]=at(tile).mail;array[5]=at(tile).goods;}
unsigned DistanceManhattan(TileIndex a,TileIndex b){return abs(a/128-b/128)+abs(a%128-b%128);}
struct Subsidy {
 inline static std::array<Subsidy*,256> pool{};
 uint16_t remaining=12;int cargo_type=0,awarded=-1,index;
 Source src{},dst{};
 static bool CanAllocateItem(){return std::ranges::find(pool,nullptr)!=pool.end();}
 bool IsAwarded()const{return awarded!=-1;}
 static auto Iterate(){
  std::vector<Subsidy*> v;
  for(auto *e:pool)if(e)v.push_back(e);
  return v;
 }
 ~Subsidy(){pool[index]=nullptr;}
};
struct {struct{unsigned subsidy_duration;}difficulty;} _settings_game;
int _local_company=0;
using EncodedString=int;
enum class NewsType {Subsidies};
enum class NewsStyle {Normal};
enum class WindowClass {SubsidyList};
const int STR_NEWS_OFFER_OF_SUBSIDY_EXPIRED=0,STR_NEWS_SUBSIDY_WITHDRAWN_SERVICE=1;
int GetEncodedString(auto...){return 0;}
void AddNewsItem(int,NewsType,NewsStyle,int,int,int){}
struct ScriptEventSubsidyOfferExpired {explicit ScriptEventSubsidyOfferExpired(int){}};
struct ScriptEventSubsidyExpired {explicit ScriptEventSubsidyExpired(int){}};
struct AI {template<class T>static void BroadcastNewEvent(T *p){delete p;}};
struct Game {template<class T>static void NewEvent(T *p){delete p;}};
void InvalidateWindowData(WindowClass,int){}
void RebuildSubsidisedSourceAndDestinationCache(){}
void CreateSubsidy(int cargo,Source src,Source dst){
 auto it=std::ranges::find(Subsidy::pool,nullptr);assert(it!=Subsidy::pool.end());
 auto *e=new Subsidy; e->index=it-Subsidy::pool.begin();e->cargo_type=cargo;
 e->src=src;e->dst=dst;*it=e;
}
struct TimerGameEconomy {
 enum class Trigger{Month};enum class Priority{Subsidy};
 struct Period {Trigger t;Priority p;};
};
void (*go)();
template<class T> struct IntervalTimer {
 template<class F>IntervalTimer(typename T::Period,F f){go=+[]{F{}(0);};}
};
"""
source = (src / "subsidy.cpp").read_text()
blocks = [source_block(src,"town_cmd.cpp",r"^/\* static \*/ Town \*Town::GetRandom"),
    source_block(src,"industry_cmd.cpp",r"^/\* static \*/ Industry \*Industry::GetRandom")]
for name in ("CheckSubsidyDuplicate","CheckSubsidyDistance","FindSubsidyPassengerRoute",
    "FindSubsidyTownCargoRoute","FindSubsidyIndustryCargoRoute","FindSubsidyCargoDestination"):
    blocks.append(source_block(src,"subsidy.cpp",rf"^(?:static )?bool {name}\([^;\n]*\)$"))
blocks.insert(0, "bool FindSubsidyCargoDestination(CargoType,Source);\n")
start = source.index("static const IntervalTimer<TimerGameEconomy> _economy_subsidies_monthly")
blocks.append(source[start:source.index("\n});",start)+4])
constants = "".join(line.split("///<")[0]+"\n" for line in (src/"subsidy_base.h").read_text().splitlines() if line.startswith("static const uint SUBSIDY_"))
driver = r"""
int main(){
 for(int k=0;k<NUM_CARGO;k++)cargos[k]={k,k};
 CargoSpec::town_production_cargoes.passengers={CargoSpec::Get(0)};
 int d,t0,t1,t2,p,q,m,g,ind,pr,pt,acc,initial,months;
 uint s0,s1;
 while(std::cin>>s0>>s1>>d>>t0>>t1>>t2>>p>>q>>m>>g>>ind>>pr>>pt>>acc>>initial>>months){
  Town A{{t0},0,5+7*128,m,g,p,q};
  Town B{{t1},3,42+24*128,8,4,q,p};
  Town C{{t2},6,88+8*128,0,14,0,0};
  towns[0]=&A;towns[3]=&B;towns[6]=&C;
  Industry D{{Industry::Cargo{1,{{{0,0},{uint(pr),uint8_t(pt)}}}},
              Industry::Cargo{2,{{{0,0},{uint(pr+4),8}}}},
              Industry::Cargo{-1,{}}},4,acc,{51+26*128}};
  industries[4]=ind?&D:nullptr;
  _settings_game.difficulty.subsidy_duration=d;
  first=s0;second=s1;draws=0;
  if(initial) {
   CreateSubsidy(0,{0,SourceType::Town},{3,SourceType::Town});
   Subsidy::pool[0]->remaining=initial%4+1;
   if(initial>=4) Subsidy::pool[0]->awarded=0;
  }
  for(int n=0;n<months;n++)go();
  std::cout<<s0<<' '<<s1<<' '<<d<<' '<<t0<<' '<<t1<<' '<<t2<<' '<<p<<' '<<q<<' '<<m<<' '<<g<<' '<<ind<<' '<<pr<<' '<<pt<<' '<<acc<<' '<<initial<<' '<<months;
  std::cout<<' '<<draws<<' '<<first<<' '<<second;
  for(auto *e:Subsidy::Iterate()){
   std::cout<<' '<<e->index<<' '<<e->cargo_type<<' '<<int(e->src.type)<<' '<<e->src.id<<' '<<int(e->dst.type)<<' '<<e->dst.id<<' '<<e->remaining<<' '<<e->awarded;delete e;
  }
  std::cout<<'\n';
 }
}
"""
lua = r"""
local root="mods/luanttd_core/openttd/"
local G=dofile(root.."town_growth.lua")
local T=dofile(root.."terragenesis.lua")(dofile(root.."slope.lua"))
local S=dofile(assert(...))(G.range,G.chance)
local count,rows,month_tests=0,0,0
for line in io.lines() do
 local a={};for w in line:gmatch("-?%d+") do a[#a+1]=tonumber(w) end
 local rng={a[1],a[2]};local draws=0
 local function rnd() draws=draws+1;return T.next_random(rng) end
 local a0={type="town",id=0,x=5,z=7,population=a[4],mail=a[9],goods=a[10],mailpct=a[7],passpct=a[8]}
 local a1={type="town",id=3,x=42,z=24,population=a[5],mail=8,goods=4,mailpct=a[8],passpct=a[7]}
 local a2={type="town",id=6,x=88,z=8,population=a[6],mail=0,goods=14,mailpct=0,passpct=0}
 local industry={type="industry",id=4,x=51,z=26}
 local board={towns={a0,a1,a2},industries=a[11]==1 and {industry} or {},passengers={0}}
 function board.town_transported(t,cargo)return cargo==0 and t.passpct or t.mailpct end
 function board.town_cargo(t,r)
  assert(r==6);local c={};if t.mail>0 then c[#c+1]=2 end;if t.goods>0 then c[#c+1]=5 end;return c
 end
 function board.town_accepts(t,cargo,r)
  assert(r==6);return cargo==2 and t.mail or cargo==5 and t.goods or 0
 end
 function board.industry_produced(i)
  assert(i==industry);return {{cargo=1,production=a[12],transported_pct=a[13]},{cargo=2,production=a[12]+4,transported_pct=8}}
 end
 function board.industry_accepts(i,cargo)return math.floor(a[14]/2^cargo)%2==1 end
 function board.valid_cargo(cargo)return cargo<7 end
 local st=S.new()
 if a[15]>0 then
  local e=S.create(st,0,a0,a1); e.remaining=a[15]%4+1; if a[15]>=4 then e.awarded=0 end
 end
 for _=1,a[16] do S.month(st,board,a[3],rnd) end
 assert(draws==a[17] and rng[1]==a[18] and rng[2]==a[19],line.." actual "..draws.."/"..rng[1].."/"..rng[2])
 local i=20;local n=0
 for id=0,255 do
  local e=st.rows[id]
  if e then
   local got={id,e.cargo,e.src.type=="town" and 1 or 0,e.src.id,e.dst.type=="town" and 1 or 0,e.dst.id,e.remaining,e.awarded or -1}
   for j,v in ipairs(got) do assert(v==a[i],line.." field "..i.." got "..v);i=i+1 end
   n=n+1
  end
 end
 assert(i==#a+1 and n==st.count)
 count,rows,month_tests=count+1,rows+n,month_tests+a[16]
end
assert(count==1700 and rows>500 and month_tests>5000)
print(("PASS %d stock subsidy control cases, %d monthly dispatches, %d matching final awards/offers"):format(count,month_tests,rows))
"""
r = Random(667744)
cases=[]
for i in range(1700):
    args=(r.getrandbits(32),r.getrandbits(32),r.choices([0,1,3],[1,13,2])[0],
          r.choice([143,400,691,938,1302]),r.choice([0,399,847,901,1602]),r.choice([400,791,1000,2302]),
          r.randrange(65),r.randrange(58),r.choice([0,5,8,10]),r.choice([0,7,8,25]),r.randrange(2),
          r.choice([0,6,80]),r.randrange(55),r.randrange(63),r.choice([0,0,2,4,7]),r.randrange(1,18))
    cases.append(" ".join(map(str,args)))
with TemporaryDirectory() as work:
    p=Path(work)
    (p/"runner.cpp").write_text(prefix+constants+"\n".join(blocks)+driver)
    (p/"check.lua").write_text(lua)
    subprocess.run(["c++","-std=c++20","-O2",p/"runner.cpp","-o",p/"runner"],check=True)
    expected=subprocess.check_output([p/"runner"],input=("\n".join(cases)+"\n").encode())
    subprocess.run(["lua5.1",p/"check.lua",str(kernel)],input=expected,check=True)
