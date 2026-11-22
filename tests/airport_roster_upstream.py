#!/usr/bin/env python3
"""Compare stocked small-plane catalog and exact daily fixed-point money with OpenTTD 14.1."""
import argparse
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import tempfile

from road_loading_upstream import ROOT, extract

PINS={
    "company_cmd.cpp":"1cf942041d5b8729e8eeba102c838b2ecb693ac68609aee5336dd538f16ed0d8",
    "engines.h":"7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "aircraft_cmd.cpp":"2cbab20d910072dfc2dd490de9032fd9873224c890b7e8160e6cfe1514f96056",
    "economy.cpp":"073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "engine.cpp":"b2bbfc2fb77e4b9695730b5e7623f0311e8f7d4d75dbc4fcd166d4ac08691db9",
    "timer_game_common.h":"99cd3d7f24d8539d9de72cea942b566911ce7e5cebc1e19e22eddfa368b988cf",
    "timer_game_tick.h":"be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()

    def read(n):
        for d in (".","src","src/table","src/timer"):
            path=a.source/d/n
            if path.is_file():
                data=path.read_bytes()
                assert sha256(data).hexdigest()==PINS[n],path
                return data.decode()
        raise FileNotFoundError(n)

    def lines(macro):
        return [re.search(rf"^\s*{macro}\(([^\n]+)\), //\s+(\d+) "+name+r"\s*$",eng,re.M)
                for name in ("Sampson U52","Coleman Count","Bakewell Cotswald LB-3")]

    eng=read("engines.h")
    avi=lines("AVI")
    ma=lines("MA")
    def split(m): return m[1].replace(" ","").split(",")
    base=re.search(r"ORIGINAL_BASE_YEAR = (\d+)",read("timer_game_common.h"))[1]
    days=re.search(r"DAYS_IN_YEAR = (\d+)",read("timer_game_common.h"))[1]
    day=re.search(r"\bDAY_TICKS = (\d+)",read("timer_game_tick.h"))[1]
    prices=read("pricebase.h")
    def price(key): return re.search(r"{\s*(\d+),\s*PCAT_.*///< "+key+r"\b",prices)[1]
    buy=price("PR_BUILD_VEHICLE_AIRCRAFT")
    run=price("PR_RUNNING_AIRCRAFT")
    cost=extract(read("engine.cpp"),"Money Engine::GetCost()")
    assert "case VEH_AIRCRAFT:" in cost and "PR_BUILD_VEHICLE_AIRCRAFT" in cost
    buy_shift=re.search(r"GetPrice\(base_price, cost_factor, this->GetGRF\(\), (-\d+)\)",cost)[1]
    aircraft=read("aircraft_cmd.cpp")
    real_running=extract(aircraft,"Money Aircraft::GetRunningCost()")
    assert "GetPrice(PR_RUNNING_AIRCRAFT, cost_factor, e->GetGRF())" in real_running
    real_tick=extract(aircraft,"bool Aircraft::Tick()")
    assert "if (!(this->vehstatus & VS_STOPPED)) this->running_ticks++;" in real_tick
    fixed=re.search(r"CommandCost cost\(EXPENSES_AIRCRAFT_RUN, (.*?)\);",aircraft)[1].replace(
        "this->GetRunningCost()","GetPrice(1, running, nullptr, 0)").replace(
        "this->running_ticks","t").replace("CalendarTime::DAYS_IN_YEAR",days).replace("Ticks::DAY_TICKS",day)
    lua=["local R=dofile('mods/luanttd_core/openttd/airport_roster.lua')","local Z=0"]
    cpp=r'''
#include <cstdint>
#include <cstdio>
using Money=int64_t;
using uint=unsigned;
using byte=uint8_t;
using Price=int;
using CompanyID=int;
const Price PR_END=2;
struct GRFFile{int price_base_multipliers[2];};
Money _price[2];
struct CommandCost{
  int e; Money c;
  CommandCost(int e_,Money c_):e(e_),c(c_) {}
  Money GetCost() const{return c;}
  int GetExpensesType() const{return e;}
};
struct Company{
  byte money_fraction;
  Money charged;
  static Company *Get(int){static Company c;return &c;}
};
void SubtractMoneyFromAnyCompany(Company *c,const CommandCost &m){c->charged+=m.GetCost();}
'''+extract(read("economy.cpp"),"Money GetPrice(")+"\n"+extract(read("company_cmd.cpp"),
    "void SubtractMoneyFromCompanyFract(")+f'''
void compare(int id,int factor,int running) {{
  auto *c=Company::Get(0);
  for (int i=0;i<6;i++) {{
    _price[0]={buy}+i*161741;
    _price[1]={run}+i*1793;
    for (int t=0;t<={day};t++) {{
      Money fixed={fixed};
      c->money_fraction=byte((t*233+i*73)&255);
      int balance=c->money_fraction;
      c->charged=0;
      SubtractMoneyFromCompanyFract(0,CommandCost(0,fixed));
      printf("%d %lld %lld %d %d %lld %lld %d\\n",id,(long long)_price[0],(long long)_price[1],t,balance,
        (long long)GetPrice(0,factor,nullptr,{buy_shift}), (long long)c->charged, (int)c->money_fraction);
    }}
  }}
}}
int main(){{
'''
    for m, global_row in zip(avi,ma):
        av, gr=split(m),split(global_row)
        assert av[3]=="P" and "T" in gr[4]
        id_=int(global_row[2])
        src_speed=int(av[6])
        fields={"stock_id":id_,"image":av[0],"buy_factor":av[1],"running_factor":av[2],
                 "intro_after_1920":gr[0],"life":gr[2],"model_life":gr[3],"acceleration":av[5],
                 "source_speed":src_speed,"max_speed":src_speed*128//10,"passengers":av[8],"mail":av[7]}
        assert int(base)+int(gr[0])//int(days)<1950
        lua += [f"do local e=R.entry({id_}); assert(e.small and "+" and ".join(
            f"e.{k}=={v}" for k,v in fields.items())+") end"]
        cpp+=f"  compare({id_},{av[1]},{av[2]});\n"
    cpp+="}\n"
    lua += [f"assert(R.BUY_BASE=={buy} and R.RUN_BASE=={run} and R.DAY_TICKS=={day} and R.DAYS_IN_YEAR=={days})",
            """for l in io.lines() do
  local k={};for n in l:gmatch("%d+") do k[#k+1]=tonumber(n) end
  local q=assert(R.quote(k[1],k[2],k[3]))
  local m,b=R.debit_fraction(k[5],R.day_charge(q.annual_fp,k[4]))
  assert(q.price==k[6] and m==k[7] and b==k[8],l)
  Z=Z+1
end
assert(Z==1350)
print("PASS: pinned OpenTTD 14.1 engine fields, exact purchase and 1350 daily aircraft charge/company-fraction cases")
"""]
    with tempfile.TemporaryDirectory() as d:
        source=Path(d)/"roster.cpp"; driver=Path(d)/"roster.lua";exe=Path(d)/"roster"
        source.write_text(cpp);driver.write_text("\n".join(lua))
        subprocess.run(["c++","-std=c++17","-O2",str(source),"-o",str(exe)],check=True)
        result=subprocess.check_output([str(exe)])
        subprocess.run([a.lua,str(driver)],input=result,cwd=ROOT,check=True)


if __name__=="__main__": main()
