#!/usr/bin/env python3
"""Validate three OpenTTD 14.1 bus engines and 3,615 consecutive finance days."""
import argparse
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import tempfile

from airport_roster_upstream import PINS
from road_loading_upstream import ROOT, extract

BUS_PINS = dict(PINS, **{
    "roadveh_cmd.cpp":"facfaea8fdab59f1375226af474a5809395165a7109cc85fda80cef63cfcdb45",
    "vehicle.cpp":"1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
})


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()

    def read(name):
        for base in (".","src","src/table","src/timer"):
            path=a.source/base/name
            if path.is_file():
                data=path.read_bytes()
                assert sha256(data).hexdigest()==BUS_PINS[name],path
                return data.decode()
        raise FileNotFoundError(name)

    eng=read("engines.h")
    def row(macro,name):
        m=re.search(rf"^\s*{macro}\(([^\n]+)\), //\s+(\d+) {name}\s*$",eng,re.M)
        return int(m[2]),m[1].replace(" ","").split(",")
    def entries():
        for i,name in enumerate(("MPS Regal Bus","Hereford Leopard Bus","Foster Bus")):
            id_, mr=row("MR",name)
            offset, rv=row("ROV",name)
            assert (id_,offset)==(116+i,i) and mr[4]=="CT_PASSENGERS" and mr[5]=="T|A|S"
            yield id_,mr,rv
    macro=re.search(r"#define ROV\([^\n]+\) \{ ([^\n]+) \}",eng)[1].replace(" ","").split(",")
    assert macro[3]=="PR_RUNNING_ROADVEH" and macro[13]=="ROADTYPE_ROAD"
    meta_macro=re.search(r"#define MR\([^\n]+\) \{ ([^\n]+) \}",eng)[1].replace(" ","").split(",")
    ages=re.search(r"\bCARGO_AGING_TICKS = (\d+)",read("timer_game_tick.h"))[1]
    days=re.search(r"DAYS_IN_YEAR = (\d+)",read("timer_game_common.h"))[1]
    ticks=re.search(r"\bDAY_TICKS = (\d+)",read("timer_game_tick.h"))[1]
    prices=read("pricebase.h")
    def price(k): return re.search(r"{\s*(\d+),\s*PCAT_.*///< "+k+r"\b",prices)[1]
    buy,run=price("PR_BUILD_VEHICLE_ROAD"),price("PR_RUNNING_ROADVEH")
    get_cost=extract(read("engine.cpp"),"Money Engine::GetCost()")
    assert "case VEH_ROAD:" in get_cost and "PR_BUILD_VEHICLE_ROAD" in get_cost
    shift=re.search(r"GetPrice\(base_price, cost_factor, this->GetGRF\(\), (-\d+)\)",get_cost)[1]
    rv_cmd=read("roadveh_cmd.cpp")
    assert "if (!(this->vehstatus & VS_STOPPED)) this->running_ticks++;" in extract(rv_cmd,"bool RoadVehicle::Tick()")
    rev=extract(rv_cmd,"Money RoadVehicle::GetRunningCost()")
    assert "if (cost_factor == 0) return 0;" in rev and "GetPrice(e->u.road.running_cost_class, cost_factor, e->GetGRF())" in rev
    source_day=extract(rv_cmd,"void RoadVehicle::OnNewEconomyDay()")
    assert "if ((++this->day_counter & 7) == 0) DecreaseVehicleValue(this);" in source_day
    fixed=(re.search(r"CommandCost cost\(EXPENSES_ROADVEH_RUN, (.*?)\);",source_day)[1]
        .replace("this->GetRunningCost()","GetPrice(1,running_factor,nullptr,0)").replace("this->running_ticks","running")
        .replace("CalendarTime::DAYS_IN_YEAR",days).replace("Ticks::DAY_TICKS",ticks))
    lua=r"""
local B=dofile("mods/bayline/openttd/road_bus_catalog.lua")
local count=0;local f,last_price,balance
for l in io.lines() do
  local n={};for v in l:gmatch("%d+") do n[#n+1]=tonumber(v) end
  local q=B.quote(n[1],n[2],n[12])
  assert(q.cost==n[5] and q.annual_fp==n[6],l)
  if last_price~=n[1] or not f or f.stock_id~=n[12] then
    last_price=n[1];f=B.new(q);balance=n[10]
  end
  for i=1,n[4] do B.tick(f) end
  local charged,rem=B.day(f,balance)
  assert(f.day==n[3] and f.value==n[7] and f.running_fp==n[8] and charged==n[9] and rem==n[11],l)
  balance=rem;count=count+1
end
assert(count==3615)
print("PASS: stock OpenTTD 14.1 #116–118 catalog, five price regimes and 3,615 exact economics days")
"""
    for id_,mr,rv in entries():
        fields={"stock_id":id_,"image":rv[0],"purchase_factor":rv[1],"running_factor":rv[2],
                "intro_after_1920":mr[0],"life":mr[2],"base_life":mr[3],"model_life":mr[1],"capacity":rv[5],
                "source_speed":rv[4],"weight_quarters":rv[6],"power_tens_hp":rv[7],
                "tractive_effort":macro[9],"air_drag":macro[10],"load_amount":meta_macro[9],"age_ticks":ages}
        lua+=f"\ndo local q=B.quote(nil,nil,{id_});assert("+" and ".join(
            f"q.{k}=={v}" for k,v in fields.items())+") end"
    cpp=r'''
#include <cstdio>
#include <cstdint>
using uint=unsigned;using byte=uint8_t;using Money=int64_t;using Price=int;using CompanyID=int;
struct GRFFile { int price_base_multipliers[2]; };
struct CommandCost {
  int e; Money c;
  CommandCost(int e_,Money c_):e(e_),c(c_){}
  Money GetCost() const{return c;}
  int GetExpensesType() const{return e;}
};
struct Company {
  byte money_fraction;
  Money charged;
  static Company *Get(int){static Company c;return &c;}
};
struct Vehicle { int index; Money value; };
const Price PR_END=2;
const int WC_VEHICLE_DETAILS=0;
void SetWindowDirty(int,int){}
Money _price[2];
void SubtractMoneyFromAnyCompany(Company*c,const CommandCost&m){c->charged+=m.GetCost();}
'''+extract(read("economy.cpp"),"Money GetPrice(")+"\n"+extract(read("company_cmd.cpp"),
    "void SubtractMoneyFromCompanyFract(")+"\n"+extract(read("vehicle.cpp"),"void DecreaseVehicleValue(")+f'''
void bus(int id,int purchase_factor,int running_factor){{
  for(int i=0;i<5;i++){{
    _price[0]={buy}+i*3137;
    _price[1]={run}+i*499;
    Money price=GetPrice(0,purchase_factor,nullptr,{shift});
    Money annual=GetPrice(1,running_factor,nullptr,0), fp=0;
    Vehicle v={{0,price}};
    auto *c=Company::Get(0);
    c->money_fraction=i*51;
    for(int day=1;day<=241;day++){{
      int old=c->money_fraction;
      int running=(day*37+i*29)%75;
      if(day%11==0)running=0;
      if((day&7)==0)DecreaseVehicleValue(&v);
      Money fixed={fixed};
      fp+=fixed;
      c->charged=0;
      SubtractMoneyFromCompanyFract(0,CommandCost(0,fixed));
      printf("%lld %lld %d %d %lld %lld %lld %lld %lld %d %d %d\\n",(long long)_price[0],(long long)_price[1],
        day,running,(long long)price,(long long)annual,(long long)v.value,(long long)fp,
        (long long)c->charged,old,(int)c->money_fraction,id);
    }}
  }}
}}
'''
    cpp += "int main(){\n"
    for id_,_,rv in entries():
        cpp += f"bus({id_},{rv[1]},{rv[2]});\n"
    cpp += "}\n"
    with tempfile.TemporaryDirectory() as d:
        p=Path(d); (p/"test.cpp").write_text(cpp); (p/"test.lua").write_text(lua)
        subprocess.run(["c++","-std=c++17","-O2",str(p/"test.cpp"),"-o",str(p/"test")],check=True)
        proc=subprocess.check_output([str(p/"test")])
        subprocess.run([a.lua,str(p/"test.lua")],input=proc,cwd=ROOT,check=True)


if __name__=="__main__":
    main()
