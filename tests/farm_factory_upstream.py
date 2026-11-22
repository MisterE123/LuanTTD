#!/usr/bin/env python3
"""Compare stock farm/factory table and lifecycle to compiled OpenTTD 14.1 source."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from timber_industry_upstream import ROOT, read, function, args_of

CPP = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint=unsigned;
using byte=uint8_t;
using TileIndex=int;
using StringID=int;
constexpr int THIS_MONTH=0, LAST_MONTH=1, STR_NULL=0;
constexpr int CBM_IND_PRODUCTION_CARGO_ARRIVAL=0, CBM_IND_PRODUCTION_256_TICKS=1;
constexpr int WC_INDUSTRY_VIEW=0, INDUSTRY_TRIGGER_RECEIVED_CARGO=0, IAT_INDUSTRY_RECEIVED_CARGO=0;
constexpr int CT_PASSENGERS=0, INDUSTRYBEH_NO_PAX_PROD_CLAMP=1;
constexpr int ET_SMOOTH=0, INDUSTRYLIFE_PROCESSING=1;
constexpr int INDCTL_NO_CLOSURE=1, INDCTL_NO_PRODUCTION_DECREASE=2, INDCTL_NO_PRODUCTION_INCREASE=4, INDCTL_EXTERNAL_PROD_LEVEL=8;
constexpr int PRODLEVEL_CLOSURE=0, PRODLEVEL_MINIMUM=4, PRODLEVEL_MAXIMUM=128, PRODLEVEL_DEFAULT=16;
constexpr int PERCENT_TRANSPORTED_60=153, PERCENT_TRANSPORTED_80=204;
constexpr int PROCESSING_INDUSTRY_ABANDONMENT_YEARS=5;
struct TimerGameEconomy { static inline int year; };
struct { struct { int type=ET_SMOOTH; } economy; } _settings_game;
enum class SourceType {Industry};
template<class T,class U> T ClampTo(U a) { return std::min<U>(a,(T)~(T)0); }
template<class T> T Clamp(T a,T l,T h) { return std::clamp(a,l,h); }
int ClampU(int a,int b,int c) { return Clamp(a,b,c); }
int CeilDiv(int a,int b) { return (a+b-1)/b; }
bool IsValidCargoID(int n) { return n>=0; }
int GetCargoIDByLabel(int n) { return n; }
bool HasBit(uint n,uint i) { return (n>>i)&1; }
struct History {
  uint16_t production{}, transported{};
  uint8_t PctTransported() const;
};
struct Input { int cargo=-1; uint16_t waiting{}; };
struct Output { int cargo=-1; uint16_t waiting{}; uint8_t rate{}; std::array<History,2> history{}; };
struct Industry {
  int type{},index{},stations_near{},exclusive_consumer{},last_prod_year{},ctlflags{};
  byte prod_level=16;
  bool was_cargo_delivered{};
  std::array<Input,16> accepted{};
  std::array<Output,16> produced{};
  static Industry *GetByTile(TileIndex);
  void RecomputeProductionMultipliers();
};
struct IndustrySpec {
  int minimal_cargo=5,life_type{},behaviour{}, production_up_text=1,production_down_text=2,closure_text=3;
  uint callback_mask{};
  int input_cargo_multiplier[16][16]{{256},{256},{256}};
  int production_rate[16]{};
  bool UsesOriginalEconomy() const;
};
Industry ind;
IndustrySpec spec;
bool orig, protect;
bool IndustrySpec::UsesOriginalEconomy() const {return orig; }
bool CheckIndustryCloseDownProtection(int) {return protect; }
Industry *Industry::GetByTile(TileIndex) {return &ind;}
const IndustrySpec *GetIndustrySpec(int) {return &spec;}
void IndustryProductionCallback(Industry *,int) {}
void SetWindowDirty(int,int) {}
void TriggerIndustry(Industry *,int) {}
void StartStopIndustryTileAnimation(Industry *,int) {}
void ReportNewsProductionChangeIndustry(Industry *,int,int) {}
bool recession;
bool EconomyIsInRecession() {return recession;}
uint MoveGoodsToStation(int id,uint n,SourceType,int,int *,int) {return id==6?n/2:n/3;}
uint32_t rand_values[12];
int rand_index;
uint32_t Random() {assert(rand_index<12);return rand_values[rand_index++];}
uint32_t RandomRange(uint limit) {return (uint64_t(Random())*limit)>>32;}
using std::abs;
"""
DECL = r"""
bool Chance16(int a,int b) { return Chance16I(a,b,Random()); }
int ScaleByCargoScale(int a,bool) { return a; }
"""
CHANGE = r"""
void ChangeStock(Industry *i) {
 StringID str=STR_NULL;
 const IndustrySpec *indspec=&spec;
 bool closeit=false,recalculate_multipliers=false,callback_enabled=false,original_economy=orig;
 byte div=0,mul=0;
 int8_t increment=0;
 if (i->type==9) {
   const bool only_decrease=false;
"""
DRIVER = r"""
int main() {
 char kind;
 while(std::cin>>kind) {
  ind={}; spec={}; rand_index=0;
  unsigned farm,n,x,y,z,u,v,w,rr,ss;
  if(kind=='P') {
    std::cin>>farm>>n>>x>>y>>z>>u>>v>>w>>rr>>ss;
    recession=ss;
    ind.type=farm?9:6;
    ind.produced[0]={farm?6:5,(uint16_t)n,(uint8_t)rr};
    ind.produced[1]={farm?4:-1,(uint16_t)x,(uint8_t)ss};
    ind.produced[0].history[0]={(uint16_t)u,(uint16_t)v};
    ind.produced[1].history[0]={(uint16_t)v,(uint16_t)w};
    if(!farm) {
      ind.accepted[0]={4,(uint16_t)x};
      ind.accepted[1]={6,(uint16_t)y};
      ind.accepted[2]={9,(uint16_t)z};
      TriggerIndustryProduction(&ind);
    }
    std::cout<<ind.produced[0].waiting<<' '<<ind.accepted[0].waiting<<' '<<ind.accepted[1].waiting<<' '<<ind.accepted[2].waiting;
    ProduceIndustryGoodsHelper(&ind,true);
    bool sent=TransportIndustryGoods(0);
    for(int k=0;k<2;k++) {
      const auto &p=ind.produced[k];
      std::cout<<' '<<p.waiting<<' '<<p.history[0].production<<' '<<p.history[0].transported;
    }
    std::cout<<' '<<sent<<'\n';
  }
  if(kind=='C') {
    unsigned level,control,year,last,protect_v,original,r1,r2,p1,t1,p2,t2,monthly;
    std::cin>>farm>>level>>control>>year>>last>>protect_v>>original>>r1>>r2>>p1>>t1>>p2>>t2>>monthly;
    for (auto &v:rand_values) std::cin>>v;
    ind.type=farm?9:6;
    ind.prod_level=level; ind.ctlflags=control; ind.last_prod_year=last; TimerGameEconomy::year=year;
    spec.life_type=farm?0:INDUSTRYLIFE_PROCESSING;
    spec.production_rate[0]=farm?10:0; spec.production_rate[1]=farm?10:0;
    protect=protect_v;orig=original;
    ind.produced[0]={farm?6:5,0,(uint8_t)r1};
    ind.produced[1]={farm?4:-1,0,(uint8_t)r2};
    ind.produced[0].history[1]={(uint16_t)p1,(uint16_t)t1};
    ind.produced[1].history[1]={(uint16_t)p2,(uint16_t)t2};
    if(monthly!=orig) ChangeStock(&ind);
    std::cout<<+ind.prod_level<<' '<<+ind.produced[0].rate<<' '<<+ind.produced[1].rate<<' '<<rand_index<<'\n';
  }
 }
}
"""
LUA = r"""
local r="mods/bayline/"
local function m(n) return dofile(r..n..".lua") end
local Coal=m("openttd/coal_industry")()
local F=m("openttd/farm_factory_industry")(nil,nil,nil,nil,Coal)
for _,kind in ipairs({"farm","factory"}) do
  local x=F.spec[kind]
  print(kind.."="..table.concat({x.id,x.sounds,x.cost_factor,x.procurement_probability,
    x.appearance[1],x.appearance[2],x.generation[1],x.generation[2],x.map_colour,
    x.rates[1],x.rates[2] or 0,x.minimum,x.multiplier[1] or 256,x.multiplier[2] or 256,x.multiplier[3] or 256},","))
  for variant=0,#F.layout[kind] do
    local list={}
    for _,row in ipairs(F.layout[kind][variant]) do list[#list+1]=table.concat(row,",") end
    print(kind..variant.."="..table.concat(list,";"))
  end
end
for _,cargo in ipairs({"livestock","goods","grain","steel"}) do
  local c,v=F.cargo[cargo],F.trucks[cargo]
  print(cargo.."="..table.concat({c.id,c.weight_16,c.capacity_multiplier,c.payment,c.days1,c.days2},","))
  print(cargo.."_vehicle="..table.concat({v.id,v.index,v.image,v.capacity,v.buy_factor,
    v.running_factor,v.speed,v.load_amount,v.age_ticks},","))
end
for gfx=33,42 do
  print("tile"..gfx.."="..table.concat({F.tile_acceptance(gfx,"passenger"),F.tile_acceptance(gfx,"grain"),
    F.tile_acceptance(gfx,"livestock"),F.tile_acceptance(gfx,"steel")},","))
end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) or n end
  local farm=a[2]==1
  local ind=F.new(farm and "farm" or "factory",0,0,0,{counter=1,completed=true,original=true})
  local p0,p1=ind.produced[1],ind.produced[2]
  if a[1]=="P" then
    p0.waiting,p0.rate=a[3],a[10]
    p1.waiting,p1.rate=a[4],a[11]
    p0.current.production,p0.current.transported=a[7],a[8]
    p1.current.production,p1.current.transported=a[8],a[9]
    if not farm then
      p1.waiting=a[4]
      ind.accepted[1].waiting,ind.accepted[2].waiting,ind.accepted[3].waiting=a[4],a[5],a[6]
      F.trigger(ind)
    end
    local b={p0.waiting,ind.accepted[1].waiting,ind.accepted[2].waiting,ind.accepted[3].waiting}
    F.production_tick(ind)
    local _,m=F.tile_loop(ind,ind.tiles[1],{recession=a[11]~=0},function(i,c,n)
      return math.floor(n/(c=="grain" and 2 or 3))
    end)
    for _,p in ipairs({p0,p1}) do
      b[#b+1]=p.waiting;b[#b+1]=p.current.production;b[#b+1]=p.current.transported
    end
    b[#b+1]=m>0 and 1 or 0
    print(table.concat(b," "))
  else
    local k=0
    ind.prod_level,ind.last_prod_year=a[3],a[6]
    p0.rate,p1.rate=a[9],a[10]
    p0.last.production,p0.last.transported=a[11],a[12]
    p1.last.production,p1.last.transported=a[13],a[14]
    local flags=a[4]
    F.change(ind,a[5],{closure_protected=a[7]==1,original=a[8]==1,monthly=a[15]==1,
      no_closure=flags%2==1,no_decrease=math.floor(flags/2)%2==1,
      no_increase=math.floor(flags/4)%2==1,external_prod_level=math.floor(flags/8)%2==1,
      random_u32=function() k=k+1;return assert(a[15+k]) end})
    print(table.concat({ind.prod_level,p0.rate,p1.rate,k}," "))
  end
end
"""


def data_expected(layouts, cargo, engines, timer):
    expected=[]
    for kind,variants in (("farm",3),("factory",2)):
        idx=re.search(rf"IT_{kind.upper()}\s*=\s*(\d+)",layouts)[1]
        q=args_of(re.search(rf"MI\(_tile_table_{kind},(.*?)\),",layouts,re.S)[1])
        assert (q[17],q[19],q[22],q[24],q[26])==(
            ("MCT_GRAIN_WHEAT_MAIZE","MCT_LIVESTOCK_FRUIT","CT_INVALID","CT_INVALID","CT_INVALID") if kind=="farm"
            else ("CT_GOODS","CT_INVALID","MCT_LIVESTOCK_FRUIT","MCT_GRAIN_WHEAT_MAIZE","CT_STEEL"))
        expected.append(kind+"="+",".join(str(int(x,0)) for x in (idx,*[q[i] for i in (0,2,3,4,5,8,9,12,18,20,21,23,25,27)])))
        for variant in range(variants):
            tbl=re.search(rf"_tile_table_{kind}_{variant}\s*\{{(.*?)\}}",layouts,re.S)[1]
            tiles=re.findall(r"MK\((\d+),\s*(\d+),\s*(\d+)\)",tbl)
            expected.append(kind+str(variant)+"="+";".join(",".join(tile) for tile in tiles))
    names=("Talbott Livestock Van","Balogh Goods Truck","Hereford Grain Truck","Balogh Steel Truck")
    for key,name in zip(("livestock","goods","grain","steel"),names,strict=True):
        c=args_of(re.search(rf"MK\((.*CT_{key.upper()}.*)\),",cargo)[1])
        expected.append(key+"="+",".join(str(int(c[i],0)) for i in (0,3,4,5,6,7)))
        v=re.search(rf"ROV\((.*)\), //\s+(\d+) {name}\b",engines)
        row=re.search(rf"MR\((.*)\), //\s+(\d+) {name}\b",engines)
        spec=args_of(v[1])
        load=args_of(re.search(r"#define MR\(.*\) \{(.*)\}",engines)[1])[4]
        age=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",timer)[1]
        expected.append(key+"_vehicle="+",".join((row[2],v[2],spec[0],spec[5],spec[1],spec[2],spec[4],load,age)))
    tiles=layouts[layouts.index("/* Farm tropic, arctic and temperate */"):].split("/* Printing works */")[0]
    for i,row in enumerate(re.findall(r"MT\((.*?)\),",tiles,re.S),33):
        a=args_of(row)
        lookup=dict(zip(a[1:6:2],a[:6:2]))
        expected.append("tile"+str(i)+"="+",".join(lookup.get(k,"0") for k in (
            "CT_PASSENGERS","MCT_GRAIN_WHEAT_MAIZE","MCT_LIVESTOCK_FRUIT","CT_STEEL")))
    return expected


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    layouts,industry,header,eco,cargo,engines,timer=(
        read(a.source,k) for k in ("build_industry.h","industry_cmd.cpp","industry.h","economy.cpp",
            "cargo_const.h","engines.h","timer_game_tick.h"))
    rnd=(a.source/"random_func.hpp")
    if not rnd.is_file(): rnd=a.source/"src"/"random_func.hpp"
    b=rnd.read_bytes()
    assert hashlib.sha256(b).hexdigest()=="b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef"
    rand_src=b.decode()
    chance=re.search(r"inline bool Chance16I\(.*?^}",rand_src,re.S|re.M)[0]
    pct=re.search(r"uint8_t PctTransported\(\) const\s*\{.*?^\s*}",header,re.S|re.M)[0].replace("PctTransported","History::PctTransported")
    change=function(industry,"ChangeIndustryProduction")
    simp=change[change.index("\t\tif (original_economy)"):change.index("\n\tif (!suppress_message")]
    recomp=re.search(r"void Industry::RecomputeProductionMultipliers\(\)\n\{.*?^}",industry,re.M|re.S)[0]
    exact=CPP+chance+DECL+pct+recomp+function(industry,"ProduceIndustryGoodsHelper")+function(industry,"TransportIndustryGoods")+function(eco,"TriggerIndustryProduction")+CHANGE+simp+"\n}\n"+DRIVER
    expected=data_expected(layouts,cargo,engines,timer)
    rng=random.Random(141906)
    cases=[]
    for i in range(8000):
        farm=i%2
        v=[rng.randrange(65536) for _ in range(7)]
        if i%5:
            v[rng.randrange(4)]=rng.randrange(5,260)
        cases.append("P "+" ".join(map(str,[farm,*v,rng.randrange(256),rng.randrange(4)])))
    for i in range(6000):
        farm=i%2
        level=rng.choice((0,4,8,16,32,64,128))
        control=rng.randrange(16)
        year,last=1955,rng.randrange(1945,1956)
        protect,original=rng.randrange(2),rng.randrange(2)
        r1,r2=(rng.randrange(1,256) if i%5 else 1),(rng.randrange(1,256) if i%7 else 1)
        p1,p2=rng.randrange(1,200),rng.randrange(1,200)
        t1,t2=rng.randrange(p1+1),rng.randrange(p2+1)
        monthly=rng.randrange(2) if i%3==0 else 1-original
        draws=[rng.randrange(2**32) if i%5 else rng.randrange(3000) for _ in range(12)]
        cases.append("C "+" ".join(map(str,[farm,level,control,year,last,protect,original,r1,r2,p1,t1,p2,t2,monthly,*draws])))
    data=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(exact)
        (d/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        c=subprocess.check_output([str(d/"stock")],input=data).decode().splitlines()
        l=subprocess.check_output([a.lua,str(d/"port.lua")],input=data,cwd=ROOT).decode().splitlines()
    for before,after in zip(expected,l[:len(expected)],strict=True):
        assert before==after,(before,after)
    for inp,before,after in zip(cases,c,l[len(expected):],strict=True):
        assert before==after,(inp,before,after)
    print("PASS: pinned 14.1 tables, 8,000 compiled two-slot production/transport/stockpile and 6,000 original/smooth change cases")

if __name__=="__main__":
    main()
