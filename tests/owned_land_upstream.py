#!/usr/bin/env python3
"""Compile the pinned stock owned-land price and clear-cost expressions."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("--lua", default="lua5.1")
args = parser.parse_args()
src = args.source / "src"
objs = (src / "table/object_land.h").read_text()
rules = (src / "object_cmd.cpp").read_text()
econ = (src / "economy.cpp").read_text()
specs = (src / "newgrf_object.h").read_text()
base = (src / "table/pricebase.h").read_text()
line, = (x for x in objs.splitlines() if "M(STR_LAI_OBJECT_DESCRIPTION_COMPANY_OWNED_LAND" in x)
size, buy, clear, height = (int(x, 0) for x in re.search(
    r"LAND,\s*(0x[\da-f]+),\s*(\d+),\s*(\d+),\s*(\d+),", line).groups())
assert size == 0x11 and height == 0
assert all("ObjectFlag::" + flag in line for flag in ["Autoremove", "OnlyInGame", "ClearIncome", "HasNoFoundation"])
assert "AllowUnderBridge" not in line
build_base, clear_base = (int(re.search(r"PriceBaseSpec\((\d+),[^\n]+// Price::" + kind + r"\b", base)[1])
    for kind in ("BuildObject", "ClearObject"))
lo = econ.index("Money GetPrice(Price index")
get_price = econ[lo:econ.index("\n}", lo) + 2]
methods = "\n".join(x.replace("this->grf_prop.grffile", "nullptr")
    for x in specs.splitlines() if "Money GetBuildCost()" in x or "Money GetClearCost()" in x)
assert "cost.AddCost(spec->GetBuildCost() * build_object_size);" in rules
lo = rules.index("CommandCost cost(ExpensesType::Construction, spec->GetClearCost()")
formula = "\n".join(rules[lo:].splitlines()[:2])
main = r"""
#include <iostream>
using Money = long long;
enum Price { BuildObject, ClearObject, End };
const unsigned ObjectClearIncome = 1;
enum class ObjectFlag { ClearIncome };
struct Flags { bool Test(ObjectFlag) const { return true; } };
struct GRFFile { int price_base_multipliers[Price::End]; };
Money _price[Price::End];
GET_PRICE
struct ObjectSpec { unsigned build_cost_multiplier, clear_cost_multiplier; Flags flags;
METHODS
};
enum class ExpensesType { Construction };
struct CommandCost {
 Money value;
 CommandCost(ExpensesType, Money cost):value(cost){}
 void MultiplyCost(int factor){value*=factor;}
};
int main() {
 const ObjectSpec specs{BUY,CLEAR,{}};
 const ObjectSpec *spec=&specs;
 const struct {int w=1,h=1;} ta;
 for (int factor : {0,1,2,31}) {
   _price[BuildObject]=BUILD_BASE+factor;
   _price[ClearObject]=CLEAR_BASE+factor;
   FORMULA
   std::cout<<spec->GetBuildCost()<<" "<<-cost.value<<"\n";
 }
}
"""
for marker, source in (("GET_PRICE", get_price), ("METHODS", methods), ("BUILD_BASE", str(build_base)),
        ("CLEAR_BASE", str(clear_base)), ("FORMULA", formula), ("BUY", str(buy)), ("CLEAR", str(clear))):
    main = main.replace(marker, source)
with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    cxx, exe = work / "land.cpp", work / "land"
    cxx.write_text(main)
    subprocess.run(["g++", "-std=c++20", str(cxx), "-o", str(exe)], check=True)
    expected = subprocess.check_output([exe], text=True)
lua = """
local K=dofile("mods/luanttd_core/openttd/owned_land.lua")({})
for _,factor in ipairs({0,1,2,31}) do
    io.write(K.price(%d+factor).." "..K.resale(%d+factor).."\\n")
end
""" % (build_base, clear_base)
actual = subprocess.check_output([args.lua, "-"], input=lua, text=True)
assert actual == expected, (actual, expected)
print("PASS RC1 compiled stock purchase and resale prices at four price levels")
