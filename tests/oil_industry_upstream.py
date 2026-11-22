#!/usr/bin/env python3
"""Differential OpenTTD 14.1 well, refinery, permission and pump tick rules."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from farm_factory_upstream import CPP, DECL, CHANGE
from road_loading_upstream import extract
from timber_industry_upstream import ROOT, read, function, args_of

DIGEST = {
    "map.cpp":"386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378",
    "random_func.hpp":"b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef",
    "industry_map.h":"b357bae16c2b177239d70926fcaa13a6adc9c6fba45400be29523108455e2150",
    "world_settings.ini":"4c08978820994e9a975a1a135b9d1ebcf01764772e49ecc2ad2c71c05e93642e",
}
GEOM = r"""
enum DiagDirection { DIAGDIR_NE, DIAGDIR_SE, DIAGDIR_SW, DIAGDIR_NW };
uint width,height;
struct Map {
 static uint SizeX() {return width;}
 static uint SizeY() {return height;}
 static uint MaxX() {return width-1;}
 static uint MaxY() {return height-1;}
};
uint TileX(TileIndex t) {return t%width;}
uint TileY(TileIndex t) {return t/width;}
int TileXY(int x,int z) {return z*width+x;}
[[noreturn]] void NOT_REACHED() {std::abort();}
"""
ANIM = r"""
using IndustryGfx=int;
enum {GFX_OILWELL_NOT_ANIMATED=29, GFX_OILWELL_ANIMATED_1=30,
      GFX_OILWELL_ANIMATED_2=31,GFX_OILWELL_ANIMATED_3=32};
int frame,gfx,stage;
bool registered;
byte GetAnimationFrame(TileIndex) {return frame;}
void SetAnimationFrame(TileIndex,int n) {frame=n;}
void SetIndustryGfx(TileIndex,int n) {gfx=n;}
void SetIndustryConstructionStage(TileIndex,int n) {stage=n;}
void DeleteAnimatedTile(TileIndex) {registered=false;}
void MarkTileDirtyByTile(TileIndex) {}
"""
DRIVER = r"""
int main() {
 char kind;
 while (std::cin>>kind) {
  ind={};spec={};rand_index=0;
  int oil;
  if(kind=='R') {
   unsigned output,input,rate,recess,p,t;
   std::cin>>oil>>output>>input>>rate>>recess>>p>>t;
   recession=recess;
   ind.type=oil?11:4;
   ind.produced[0]={oil?3:5,(uint16_t)output,(uint8_t)rate};
   ind.produced[0].history[0]={(uint16_t)p,(uint16_t)t};
   if(!oil) {ind.accepted[0]={3,(uint16_t)input};TriggerIndustryProduction(&ind);}
   std::cout<<ind.produced[0].waiting<<' '<<ind.accepted[0].waiting<<' ';
   ProduceIndustryGoodsHelper(&ind,true);
   bool sent=TransportIndustryGoods(0);
   auto &q=ind.produced[0];
   std::cout<<q.waiting<<' '<<q.history[0].production<<' '<<q.history[0].transported<<' '<<sent<<'\n';
  } else if(kind=='C') {
   unsigned level,flags,year,last,pv,ov,monthly,rate,p,t;
   std::cin>>oil>>level>>flags>>year>>last>>pv>>ov>>monthly>>rate>>p>>t;
   for(auto &v:rand_values) std::cin>>v;
   ind.type=oil?11:4;ind.prod_level=level;ind.ctlflags=flags;ind.last_prod_year=last;
   TimerGameEconomy::year=year;
   // CheckIndustryCloseDownProtection: only-decrease temperate wells exempt.
   orig=ov;protect=!oil && pv;
   spec.life_type=oil?0:INDUSTRYLIFE_PROCESSING;spec.production_rate[0]=oil?12:0;
   ind.produced[0]={oil?3:5,0,(uint8_t)rate};
   ind.produced[0].history[1]={(uint16_t)p,(uint16_t)t};
   if(monthly!=orig) ChangeStock(&ind);
   std::cout<<+ind.prod_level<<' '<<+ind.produced[0].rate<<' '<<rand_index<<'\n';
  } else if(kind=='A') {
   int tick;
   std::cin>>gfx>>frame>>tick>>rand_values[0];
   stage=3;registered=gfx>=30 && gfx<=32;
   if(registered && !(tick&7)) AnimateOilWell(0,gfx);
   std::cout<<gfx<<' '<<frame<<' '<<stage<<' '<<registered<<' '<<rand_index<<'\n';
  } else {
   uint x,z,l;
   bool freeform;
   std::cin>>width>>height>>x>>z>>l>>freeform;
   _settings_game.construction.freeform_edges=freeform;
   std::cout<<CheckScaledDistanceFromEdge(TileXY(x+1,z+1),l)<<'\n';
  }
 }
}
"""
LUA = r"""
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local C=m("openttd/coal_industry")()
local O=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),nil,nil,nil,nil,C)
local function bool(v) return v and 1 or 0 end
for _,kind in ipairs({"oil_well","oil_refinery"}) do
  local s=O.spec[kind]
  print(kind.."="..table.concat({s.id,s.sounds,s.cost_factor,s.procurement_probability,
    s.appearance[1],s.generation[1],s.map_colour,s.rates[1],s.minimum,s.multiplier[1] or 256},","))
  for v=0,1 do
    local t={}
    for _,row in ipairs(O.layout[kind][v]) do t[#t+1]=table.concat(row,",") end
    print(kind..v.."="..table.concat(t,";"))
  end
end
for _,cargo in ipairs({"oil","goods"}) do
  local v,s=O.trucks[cargo],O.cargo[cargo]
  print(cargo.."="..table.concat({s.id,s.weight_16,s.capacity_multiplier,s.payment,s.days1,s.days2},","))
  print(cargo.."_truck="..table.concat({v.id,v.index,v.image,v.capacity,v.buy_factor,v.running_factor,
    v.speed,v.load_amount,v.age_ticks},","))
end
for _,interval in ipairs({{18,23},{29,32}}) do
  for gfx=interval[1],interval[2] do
    print(("tile%d=%d,%d,%d,%d"):format(gfx,O.tile_acceptance(gfx,"oil"),O.tile_acceptance(gfx,"passenger"),
      bool(O.slope_allowed(gfx,0)),bool(O.slope_allowed(gfx,1))))
  end
end
print("edge="..O.EDGE_LIMIT)
for line in io.lines() do
  local a={}
  for p in line:gmatch("%S+") do a[#a+1]=tonumber(p) or p end
  if a[1]=="E" then
    print(bool(O.refinery_edge(a[4],a[5],a[2],a[3],{limit=a[6],freeform=a[7]==1})))
  elseif a[1]=="A" then
    local t={gfx=a[2],animation_frame=a[3],stage=3}
    local draws=0
    O.animate(t,a[4],function() draws=draws+1;return a[5] end)
    print(table.concat({t.gfx,t.animation_frame,t.stage,bool(t.gfx>=30 and t.gfx<=32),draws}," "))
  else
    local well=a[2]==1
    local ind=O.new(well and "oil_well" or "oil_refinery",0,0,0,{counter=1,completed=true,original=true})
    local out=ind.produced[1]
    if a[1]=="R" then
      out.waiting,out.rate=a[3],a[5]
      out.current.production,out.current.transported=a[7],a[8]
      if not well then ind.accepted[1].waiting=a[4];O.trigger(ind) end
      local before,input=out.waiting,ind.accepted[1].waiting
      O.production_tick(ind)
      local _,m=O.tile_loop(ind,ind.tiles[1],{recession=a[6]==1},function(_,_,n) return math.floor(n/3) end)
      print(table.concat({before,input,out.waiting,out.current.production,out.current.transported,bool(m>0)}," "))
    else
      local flags,k=a[4],0
      ind.prod_level,ind.last_prod_year=a[3],a[6]
      out.rate,out.last.production,out.last.transported=a[10],a[11],a[12]
      O.change(ind,a[5],{closure_protected=a[7]==1, original=a[8]==1,monthly=a[9]==1,
        no_closure=flags%2==1,no_decrease=math.floor(flags/2)%2==1,
        no_increase=math.floor(flags/4)%2==1,external_prod_level=math.floor(flags/8)%2==1,
        random_u32=function() k=k+1;return a[12+k] end})
      print(table.concat({ind.prod_level,out.rate,k}," "))
    end
  end
end
"""


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    def pin(name):
        for d in (".","src","src/table"):
            path=a.source/d/name
            if path.is_file():
                data=path.read_bytes()
                assert hashlib.sha256(data).hexdigest()==DIGEST[name],path
                return data.decode()
        raise FileNotFoundError(name)
    b,ind,h,eco,c,eng,timer=(read(a.source,key) for key in ("build_industry.h","industry_cmd.cpp","industry.h","economy.cpp","cargo_const.h","engines.h","timer_game_tick.h"))
    expected=[]
    for kind in ("oil_well","oil_refinery"):
        idx=re.search(rf"IT_{kind.upper()}\s*=\s*(\d+)",b)[1]
        q=args_of(re.search(rf"MI\(_tile_table_{kind},(.*?)\),",b,re.S)[1])
        assert (q[17],q[22])==(("CT_OIL","CT_INVALID") if kind=="oil_well" else ("CT_GOODS","CT_OIL"))
        expected.append(kind+"="+",".join(str(int(x,0)) for x in (idx,*[q[i] for i in (0,2,3,4,8,12,18,21,23)])))
        for variant in (0,1):
            t=re.search(rf"_tile_table_{kind}_{variant}\s*\{{(.*?)\}}",b,re.S)[1]
            expected.append(kind+str(variant)+"="+";".join(",".join(v) for v in re.findall(r"MK\((\d+),\s*(\d+),\s*(\d+)\)",t)))
    for key,name in (("oil","Witcombe Oil Tanker"),("goods","Balogh Goods Truck")):
        values=args_of(re.search(rf"MK\((.*CT_{key.upper()}.*)\),",c)[1])
        expected.append(key+"="+",".join(str(int(values[i],0)) for i in (0,3,4,5,6,7)))
        v=re.search(rf"ROV\((.*)\), //\s+(\d+) {name}\b",eng)
        g=re.search(rf"MR\((.*)\), //\s+(\d+) {name}\b",eng)
        raw=args_of(v[1])
        load=args_of(re.search(r"#define MR\(.*\) \{(.*)\}",eng)[1])[4]
        age=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",timer)[1]
        expected.append(key+"_truck="+",".join((g[2],v[2],raw[0],raw[5],raw[1],raw[2],raw[4],load,age)))
    for start,label,end in ((18,"/* Oil refinery */","/* Oil Rig */"),(29,"/* Oil Wells artic, temperate and sub-tropical */","/* Farm tropic")):
        sect=b[b.index(label):].split(end)[0]
        for i,mt in enumerate(re.findall(r"MT\((.*?)\),",sect), start):
            row=args_of(mt)
            table=dict(zip(row[1:6:2],row[:6:2]))
            assert row[6]=="SLOPE_STEEP"
            expected.append(f"tile{i}="+",".join((table.get("CT_OIL","0"),table.get("CT_PASSENGERS","0"),"1","0")))
    expected.append("edge="+re.search(r"var\s*=\s*game_creation\.oil_refinery_limit.*?def\s*=\s*(\d+)",pin("world_settings.ini"),re.S)[1])
    assert re.findall(r"GFX_OILWELL_\w+\s*=\s*(\d+)",pin("industry_map.h"))==["29","30","31","32"]
    style=CPP.replace("economy; } _settings_game;", "economy; struct {bool freeform_edges;} construction; } _settings_game;")
    chance=extract(pin("random_func.hpp"),"inline bool Chance16I(")
    pct=re.search(r"uint8_t PctTransported\(\) const\s*\{.*?^\s*}",h,re.S|re.M)[0].replace("PctTransported","History::PctTransported")
    change=function(ind,"ChangeIndustryProduction")
    branch=change[change.index("\t\tif (original_economy)"):change.index("\n\tif (!suppress_message")]
    code=style+chance+DECL+pct+extract(ind,"void Industry::RecomputeProductionMultipliers()")
    code+=function(ind,"ProduceIndustryGoodsHelper")+function(ind,"TransportIndustryGoods")+function(eco,"TriggerIndustryProduction")
    code+=CHANGE.replace("i->type==9","i->type==11").replace("only_decrease=false","only_decrease=true")+branch+"\n}\n"
    code+=GEOM+extract(pin("map.cpp"),"uint DistanceFromEdgeDir(")+function(ind,"CheckScaledDistanceFromEdge")
    code+=ANIM+function(ind,"AnimateOilWell")+DRIVER
    rng=random.Random(411)
    cases=[]
    for i in range(5000):
        initial,received=rng.choice((0,5,6,254,255,256,rng.randrange(65536))),rng.randrange(65536)
        cases.append("R "+" ".join(map(str,[i%2,initial,received,rng.randrange(256),rng.randrange(2),rng.randrange(65536),rng.randrange(65536)])))
    for i in range(5000):
        original=rng.randrange(2);monthly=rng.randrange(2) if i%3==0 else 1-original
        p0=rng.randrange(200)
        cases.append("C "+" ".join(map(str,[i%2,rng.choice((0,4,8,16,32,64,128)),rng.randrange(16),
            1957,rng.randrange(1946,1958),rng.randrange(2),original,monthly,rng.choice((1,2,12,rng.randrange(256))),
            p0,rng.randrange(p0+1),*[rng.randrange(2**32) if i%6 else rng.randrange(3000) for _ in range(12)]])))
    for i in range(4000):
        w,z=rng.choice((64,128,256,512,1024)),rng.choice((64,128,256,512,1024))
        cases.append("E "+" ".join(map(str,[w,z,rng.randrange(w-2),rng.randrange(z-2),rng.randrange(12,129),i%2])))
        cases.append("A "+" ".join(map(str,[rng.randrange(29,33),rng.randrange(4),rng.randrange(0,50) if i%2 else 8,rng.randrange(2**32)])))
    inputs=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        (d/"stock.cpp").write_text(code)
        (d/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",str(d/"stock.cpp"),"-o",str(d/"stock")],check=True)
        c=subprocess.check_output([str(d/"stock")],input=inputs).decode().splitlines()
        l=subprocess.check_output([a.lua,str(d/"port.lua")],input=inputs,cwd=ROOT).decode().splitlines()
    for before,after in zip(expected,l[:len(expected)],strict=True):
        assert before==after,(before,after)
    for inp,before,after in zip(cases,c,l[len(expected):],strict=True):
        assert before==after,(inp,before,after)
    print("PASS: pinned wells/refinery tables and 18,000 compiled production, conversion, closure, edge and pump cases")

if __name__=="__main__":
    main()
