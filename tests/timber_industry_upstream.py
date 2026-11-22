#!/usr/bin/env python3
"""Diff forest/sawmill production and settlement against pinned OpenTTD 14.1."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIGEST = {
    "build_industry.h": "4e13ea7b25aeba2c349801c8808f9802e200e7ade79bb624bd78f4e618e237db",
    "town_land.h": "a6925280753e551f4426a92d76a8c57f49171a519c860d855b3cd29946c817d7",
    "industry_cmd.cpp": "0dfb1a169c42754a771093059948c51a62cd1ea378b42663ba8e9a9697f1a914",
    "industry.h": "a6ca3fbb9228f2f7fc85bc8bf785ecc133ede21bdeeb7c98d98ba57f71bb0f0c",
    "economy.cpp": "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "cargo_const.h": "3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "engines.h": "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "timer_game_tick.h": "be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
}


def read(root, name):
    for d in (".", "src", "src/table", "src/timer"):
        path = root / d / name
        if path.is_file():
            data = path.read_bytes()
            assert hashlib.sha256(data).hexdigest() == DIGEST[name], f"Wrong source pin: {name}"
            return data.decode()
    raise FileNotFoundError(name)


def function(src, name):
    return re.search(r"static [^\n]*\b" + name + r"\([^\n]*\)\n\{.*?^\}", src, re.M | re.S)[0]


def args_of(s):
    return [x.strip() for x in s.split(",")]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--lua", default="lua5.1")
    p.add_argument("--compiler", default="g++")
    args = p.parse_args()
    layouts, town, industry, industry_h, economy, cargo, eng, timer = (read(args.source, k) for k in DIGEST)
    actual_houses = []
    for req,id_ in re.findall(r"MS\((.*?)\),\s*//\s*([\dA-Fa-f]{2})\b", town.split("_original_house_specs",1)[1],re.S):
        a=args_of(req)
        assert int(id_,16)==len(actual_houses) and len(a)==15
        actual_houses.append(sum(int(a[7+i]) for i,c in enumerate(a[-3:]) if c=="CT_GOODS"))
    assert len(actual_houses)==110
    expected_lines=["houses="+",".join(map(str,actual_houses))]
    for ind in ("forest","sawmill"):
        idx=re.search(rf"IT_{ind.upper()}\s*=\s*(\d+)",layouts)[1]
        q=args_of(re.search(rf"MI\(_tile_table_{ind},(.*?)\),",layouts,re.S)[1])
        assert q[17]==("CT_WOOD" if ind=="forest" else "CT_GOODS"),q
        expected_lines.append(f"{ind}="+",".join(str(int(x,0)) for x in (idx,q[2],q[3],q[18],q[21],q[23])))
        for variant in (0,1):
            tbl=re.search(rf"_tile_table_{ind}_{variant}\s*\{{(.*?)\}}",layouts,re.S)[1]
            tiles=re.findall(r"MK\((\d+),\s*(\d+),\s*(\d+)\)",tbl)
            expected_lines.append(ind+str(variant)+"="+";".join(",".join(tile) for tile in tiles))
    for key,name in (("wood","Witcombe Wood Truck"),("goods","Balogh Goods Truck")):
        c=args_of(re.search(rf"MK\((.*CT_{key.upper()}.*)\),",cargo)[1])
        expected_lines.append(f"{key}="+",".join(str(int(c[i],0)) for i in (0,3,4,5,6,7)))
        t=re.search(rf"ROV\((.*)\), //\s+(\d+) {name}\b",eng)
        spec=args_of(t[1])
        row=re.search(rf"MR\((.*)\), //\s+(\d+) {name}\b",eng)
        age=re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",timer)[1]
        load=args_of(re.search(r"#define MR\(.*\) \{(.*)\}",eng)[1])[4]
        expected_lines.append(key+"_vehicle="+",".join((row[2],t[2],spec[5],spec[1],spec[2],spec[4],load,age)))
    assert "PROCESSING_INDUSTRY_ABANDONMENT_YEARS = 5" in industry_h
    assert "INDUSTRY_PRODUCE_TICKS = 256" in timer
    assert "num_pieces : accepted_ind;" in economy
    assert "st->town->received[cs->town_acceptance_effect].new_act += accepted_total" in economy

    cpp = r'''
#include <array>
#include <algorithm>
#include <cstdint>
#include <iostream>
using uint=unsigned;
using TileIndex=int;
constexpr int THIS_MONTH=0, CBM_IND_PRODUCTION_CARGO_ARRIVAL=0, CBM_IND_PRODUCTION_256_TICKS=1;
constexpr int WC_INDUSTRY_VIEW=0, INDUSTRY_TRIGGER_RECEIVED_CARGO=0, IAT_INDUSTRY_RECEIVED_CARGO=0;
enum class SourceType { Industry };
template<class T, class U> T ClampTo(U a) { return std::min<U>(a, (T)~(T)0); }
bool IsValidCargoID(int n) { return n>=0; }
bool HasBit(uint n,uint i) { return (n>>i)&1; }
struct History { uint16_t production{},transported{}; };
struct Input { int cargo; uint16_t waiting; };
struct Output { int cargo; uint16_t waiting; uint8_t rate; std::array<History,2> history{}; };
struct Industry {
  int type{},index{},stations_near{},exclusive_consumer{};
  bool was_cargo_delivered{};
  std::array<Input,1> accepted{};
  std::array<Output,1> produced{};
  static Industry *GetByTile(TileIndex);
};
struct IndustrySpec {
  int minimal_cargo{};
  uint callback_mask{};
  int input_cargo_multiplier[1][1]{{256}};
};
Industry ind;
IndustrySpec spec;
Industry *Industry::GetByTile(TileIndex) { return &ind; }
const IndustrySpec *GetIndustrySpec(int) { return &spec; }
void IndustryProductionCallback(Industry*,int) {}
void SetWindowDirty(int,int) {}
void TriggerIndustry(Industry*,int) {}
void StartStopIndustryTileAnimation(Industry*,int) {}
bool recession;
bool EconomyIsInRecession() { return recession; }
uint moved;
uint MoveGoodsToStation(int,uint n,SourceType,int,int*,int) { moved=n/2; return moved; }
int ScaleByCargoScale(int a,bool) { return a; }
'''
    cpp += function(industry,"ProduceIndustryGoodsHelper") + "\n"
    cpp += function(industry,"TransportIndustryGoods") + "\n"
    cpp += function(economy,"TriggerIndustryProduction") + "\n"
    cpp += r'''
int main() {
  unsigned timber,waiting,input,rate,rec;
  while(std::cin>>timber>>waiting>>input>>rate>>rec) {
    ind={}; moved=0; recession=rec; spec.minimal_cargo=timber?30:5;
    ind.produced[0]={0,(uint16_t)waiting,(uint8_t)rate};
    ind.accepted[0]={timber?-1:1,(uint16_t)input};
    if (!timber) TriggerIndustryProduction(&ind);
    unsigned converted=ind.produced[0].waiting;
    ProduceIndustryGoodsHelper(&ind,true);
    bool sent=TransportIndustryGoods(0);
    auto &p=ind.produced[0];
    std::cout<<converted<<' '<<ind.accepted[0].waiting<<' '<<p.waiting<<' '<<p.history[0].production
      <<' '<<p.history[0].transported<<' '<<sent<<'\n';
  }
}
'''
    lua = r'''
local r="mods/luanttd_core/"
local function m(n) return dofile(r..n..".lua") end
local H=m("openttd/town_goods")
local Coal=m("openttd/coal_industry")()
local T=m("openttd/timber_industry")(nil,nil,nil,nil,Coal,H)
local h={}
for k=0,109 do h[#h+1]=assert(H.house_acceptance(k)) end
assert(H.house_acceptance(110)==nil)
print("houses="..table.concat(h,","))
for _,ind in ipairs({"forest","sawmill"}) do
  local x=T.spec[ind]
  print(ind.."="..table.concat({x.id,x.cost_factor,x.probability,x.rate,x.minimum,x.multiplier or 256},","))
  for variant=0,1 do
    local a={}
    for _,g in ipairs(T.layout[ind][variant]) do a[#a+1]=table.concat(g,",") end
    print(ind..variant.."="..table.concat(a,";"))
  end
end
for _,cargo in ipairs({"wood","goods"}) do
  local c,b=T.cargo[cargo],T.trucks[cargo]
  print(cargo.."="..table.concat({c.id,c.weight_16,c.capacity_multiplier,c.payment,c.days1,c.days2},","))
  print(cargo.."_vehicle="..table.concat({b.id,b.index,b.capacity,b.buy_factor,b.running_factor,b.speed,b.load_amount,b.age_ticks},","))
end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local ind=T.new(a[1]==1 and "forest" or "sawmill",0,0,0,{counter=1,completed=true,original=true})
  ind.produced.rate,ind.produced.waiting=a[4],a[2]
  if ind.accepted then ind.accepted.waiting=a[3];T.trigger(ind) end
  local converted=ind.produced.waiting
  T.production_tick(ind)
  local _,moved=T.tile_loop(ind,ind.tiles[1],{recession=a[5]~=0},function(_,_,n) return math.floor(n/2) end)
  local p=ind.produced
  print(table.concat({converted,ind.accepted and ind.accepted.waiting or a[3],p.waiting,p.current.production,
    p.current.transported,moved>0 and 1 or 0}," "))
end
'''
    rng=random.Random(14_01)
    cases=[]
    for i in range(6000):
        forest=i%2
        waiting=rng.choice([0,5,6,29,30,31,254,255,256,65529,65535,rng.randrange(65536)])
        cases.append((forest,waiting,0 if forest else rng.choice([0,1,5,6,30,255,65535,rng.randrange(65536)]),rng.randrange(32) if forest else 0,rng.randrange(2)))
    inputs="".join(" ".join(map(str,row))+"\n" for row in cases)
    with tempfile.TemporaryDirectory(prefix="timber-diff-") as d:
        src,elf,l=map(lambda n:Path(d)/n, ("probe.cpp","probe","probe.lua"))
        src.write_text(cpp)
        l.write_text(lua)
        subprocess.run([args.compiler,"-std=c++17","-O2",str(src),"-o",str(elf)],check=True)
        got=subprocess.check_output([args.lua,str(l)],cwd=ROOT,input=inputs,text=True).splitlines()
        want=expected_lines+subprocess.check_output([str(elf)],input=inputs,text=True).splitlines()
    assert len(got)==len(want)
    for i,(g,w) in enumerate(zip(got,want)):
        assert g==w, (i,cases[i-len(expected_lines)] if i>=len(expected_lines) else None,g,w)
    print("PASS: all 110 HouseID goods values, four source footprints, both road bodies, and 6,000 compiled produce/convert/ship cases")


if __name__=="__main__":
    main()
