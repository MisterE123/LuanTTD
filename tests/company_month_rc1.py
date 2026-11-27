#!/usr/bin/env python3
"""Compare the generated campaign's default fees to original RC1 company code."""
import argparse
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CPP = r"""
#include <array>
#include <cstdint>
#include <cstdio>
using Money = int64_t;
using CompanyID = int;
enum class ExpensesType { LoanInterest, Other };
enum Price { StationValue };
struct CommandCost {
    ExpensesType kind;
    Money cost;
    CommandCost(ExpensesType t,Money v):kind(t),cost(v){}
};
struct Company {
    Money current_loan, cash;
    int infinite;
    CompanyID index;
    static std::array<const Company *,1> Iterate();
};
Company c;
std::array<const Company *,1> Company::Iterate() { return {&c}; }
Money GetAvailableMoney(CompanyID) { return c.infinite ? 9000000000000 : c.cash; }
Money _price[1];
struct { int interest_rate; } _economy;
namespace TimerGameEconomy { int month; }
Money interest,other;
void SubtractMoneyFromCompany(CompanyID,CommandCost n) {
    if (n.kind==ExpensesType::LoanInterest) interest=n.cost;
    else other=n.cost;
}
__ORIGINAL__
int main(){
    int month;
    long long loan, cash, station;
    while (std::scanf("%lld%lld%d%d%lld%d",&loan,&cash,&month,&_economy.interest_rate,&station,&c.infinite)==6){
        c.current_loan=loan;c.cash=cash;c.index=0;
        _price[Price::StationValue]=station;TimerGameEconomy::month=month-1;
        CompaniesPayInterest();
        std::printf("%lld,%lld\n",static_cast<long long>(interest),static_cast<long long>(other));
    }
}
"""
LUA = """
local M=dofile("mods/luanttd_core/openttd/company_quarters_rc1.lua")
for line in io.lines() do
  local a={}
  for k in line:gmatch("-?%d+") do a[#a+1]=tonumber(k) end
  local interest,other=M.monthly_fees(a[1],a[2],a[3],a[4],a[5],a[6]==1)
  print(interest..","..other)
end
"""

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    source=(a.source/"economy.cpp").read_text()
    begin=source.index("static void CompaniesPayInterest()")
    end=source.index("\n}",begin)+2
    assert re.search(r"PriceBaseSpec\(100,\s*PriceCategory::None[^\n]+Price::StationValue",
                     (a.source/"table/pricebase.h").read_text())
    rng=random.Random(160)
    rows=[(rng.randrange(300000000),rng.randrange(-100000000,100000000),i%12+1,
           rng.randrange(2,5),rng.randrange(1,50000),rng.randrange(2)) for i in range(12000)]
    rows.extend((300000,100000,m,2,100,0) for m in range(1,13))
    data="".join(" ".join(map(str,r))+"\n" for r in rows).encode()
    with tempfile.TemporaryDirectory() as directory:
        d=Path(directory)
        (d/"original.cpp").write_text(CPP.replace("__ORIGINAL__",source[begin:end]))
        (d/"implementation.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",d/"original.cpp","-o",d/"original"],check=True)
        orig=subprocess.check_output([d/"original"],input=data)
        port=subprocess.check_output([a.lua,d/"implementation.lua"],input=data,cwd=ROOT)
    assert orig==port
    print(f"PASS {len(rows):,} original RC1 loan-interest and overhead calculations.")

if __name__=="__main__":
    main()
