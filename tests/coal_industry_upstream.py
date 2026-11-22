#!/usr/bin/env python3
"""Compile the OpenTTD 14.1 ordinary coal production/transfer/delivery functions.

python3 tests/coal_industry_upstream.py /path/to/OpenTTD [lua5.1]
A directory with the pinned source files flattened also works. The reference
compiles production, transport, delivery and layouts verbatim. Its shims
replace station allocation, tile ownership, game RNG and the UI/monitor.
"""
import hashlib
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
path = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"


def read(name, digest):
    paths = (path / 'src' / name, path / name, path / Path(name).name)
    p = next((p for p in paths if p.is_file()), paths[0])
    b = p.read_bytes()
    assert hashlib.sha256(b).hexdigest() == digest, f"{p}: not the pinned 14.1 source"
    return b.decode()


def block(txt, pattern):
    start = re.search(pattern, txt, re.M).start()
    end = txt.index('{', start)
    depth = 1
    while depth:
        end += 1
        depth += (txt[end] == '{') - (txt[end] == '}')
    return txt[start:end + 1]


industry = read("industry_cmd.cpp", "0dfb1a169c42754a771093059948c51a62cd1ea378b42663ba8e9a9697f1a914")
econh = read("economy_func.h", "324a21a61429409bdd3f0bf98c214b8954362664d4420574a6541062ddac9111")
econ = read("economy.cpp", "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb")
randomh = read("random_func.hpp", "b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef")
build = read("table/build_industry.h", "4e13ea7b25aeba2c349801c8808f9802e200e7ade79bb624bd78f4e618e237db")
eng = read("table/engines.h", "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182")
cargo = read("table/cargo_const.h", "3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45")
timer = read("timer/timer_game_tick.h", "be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1")

cpp = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>
using uint = unsigned;
using TileIndex = uint16_t;
using CompanyID = int;
using CargoID = int;
using IndustryID = int;
enum class SourceType { Industry };
constexpr int THIS_MONTH=0, INVALID_OWNER=-1, GM_MENU=1;
int _game_mode=0;
struct { struct { uint16_t town_cargo_scale, industry_cargo_scale; } economy; } _settings_game;
uint32_t random_sample;
int calls;
template<class T> T ClampTo(uint32_t u) { return std::min<uint32_t>(u,std::numeric_limits<T>::max()); }
bool IsValidCargoID(int c) { return c>=0; }
struct History { uint16_t production=0, transported=0; };
struct Product { int cargo=1; uint16_t waiting=0; uint8_t rate=0; History history[2]; };
struct Accepted { uint16_t waiting=0; int last_accepted=0; };
struct Industry {
    int type=0,index=0,exclusive_consumer=INVALID_OWNER,exclusive_supplier=INVALID_OWNER,stations_near=0;
    bool refuse=false;
    std::array<Product,1> produced;
    std::array<Accepted,1> accepted;
    auto GetCargoAccepted(CargoID) { return accepted.begin(); }
    static Industry *current;
    static Industry *GetByTile(TileIndex) { return current; }
};
Industry *Industry::current=nullptr;
struct IndustrySpec { uint minimal_cargo=5; };
const IndustrySpec *GetIndustrySpec(int) { static IndustrySpec s; return &s; }
bool recession;
bool EconomyIsInRecession() { return recession; }
uint percentage;
uint MoveGoodsToStation(CargoID, uint n, SourceType, IndustryID, const int *, int) { return n*percentage/100; }
struct Station {
    int owner;
    struct Near { Industry *industry; };
    std::array<Near,2> industries_near;
};
struct TimerGameEconomy { static constexpr int date=491; };
std::vector<Industry *> _cargo_delivery_destinations;
template<class T> void include(std::vector<T> &set,T value) {
    if (std::find(set.begin(),set.end(),value)==set.end()) set.push_back(value);
}
bool IndustryTemporarilyRefusesCargo(Industry *i,CargoID) { return i->refuse; }
void AddCargoDelivery(CargoID,CompanyID,uint,SourceType,IndustryID,const Station*,IndustryID) {}
struct IndustryTileLayoutTile { struct { int x,y; } ti; int gfx; };
using IndustryTileLayout=std::vector<IndustryTileLayoutTile>;
"""
cpp += "\n" + block(randomh, r"^inline bool Chance16I")
cpp += "\nbool Chance16(uint a,uint b) { ++calls; return Chance16I(a,b,random_sample); }\n"
cpp += "\n".join([block(econh, r"^static uint ScaleByInverseCargoScale"),
                  block(econh, r"^inline uint ScaleByCargoScale"),
                  block(industry, r"^static void ProduceIndustryGoodsHelper"),
                  block(industry, r"^static bool TransportIndustryGoods"),
                  block(econ, r"^static uint DeliverGoodsToIndustry")]) + "\n"
cpp += build[build.index("#define MK(x, y, m)"):build.index("static const IndustryTileLayout _tile_table_sawmill_0")]
cpp += r"""
int main() {
    int type;
    while (std::cin>>type) {
        if (type==0) {
            uint waiting,rate,scale,p,t,prod_tick;
            std::cin>>waiting>>rate>>scale>>p>>t>>recession>>percentage>>prod_tick>>random_sample;
            Industry i; Industry::current=&i; auto &a=i.produced[0];
            a.waiting=waiting; a.rate=rate; a.history[0].production=p; a.history[0].transported=t;
            calls=0; _settings_game.economy.industry_cargo_scale=scale;
            if (prod_tick) ProduceIndustryGoodsHelper(&i,true);
            std::cout<<a.waiting<<" "<<calls<<" ";
            bool moved=TransportIndustryGoods(0);
            std::cout<<a.waiting<<" "<<a.history[0].production<<" "<<a.history[0].transported<<" "<<moved<<"\n";
        } else if (type==1) {
            uint w1,w2,n;
            int e1,e2,owner,src;
            bool r1,r2;
            std::cin>>w1>>w2>>n>>e1>>e2>>owner>>src>>r1>>r2;
            Industry a,b; a.index=1; b.index=2;
            a.accepted[0].waiting=w1; a.exclusive_supplier=e1; a.refuse=r1;
            b.accepted[0].waiting=w2; b.exclusive_supplier=e2; b.refuse=r2;
            Station s{owner,{{{&a},{&b}}}};
            _cargo_delivery_destinations.clear();
            uint accepted=DeliverGoodsToIndustry(&s,1,n,src,owner);
            std::cout<<accepted<<" "<<a.accepted[0].waiting<<" "<<b.accepted[0].waiting<<" "
              <<a.accepted[0].last_accepted<<" "<<b.accepted[0].last_accepted<<" "<<_cargo_delivery_destinations.size()<<"\n";
        } else if (type==2) {
            for (auto ls:{&_tile_table_coal_mine,&_tile_table_power_station}) {
                for (auto &layout:*ls) {
                    std::cout<<layout.size();
                    for (auto &tile:layout) std::cout<<" "<<tile.ti.x<<" "<<tile.ti.y<<" "<<tile.gfx;
                    std::cout<<"\n";
                }
            }
        }
    }
}
"""
mr = re.search(r"MR\(([^\n]+?)\),\s*// 123 Balogh Coal Truck", eng)[1].split(",")
rov = re.search(r"ROV\(([^\n]+?)\),\s*//\s+7 Balogh Coal Truck", eng)[1].split(",")
rov_macro = re.search(r"^#define ROV.*",eng,re.M)[0]
coal = re.search(r"MK\(([^\n]+?CT_COAL[^\n]+?)\),",cargo)[1].split(",")
mine_spec = re.search(r"MI\(_tile_table_coal_mine,.*?\),",build,re.S)[0]
power_spec = re.search(r"MI\(_tile_table_power_station,.*?\),",build,re.S)[0]
number = lambda s: int(s.strip(),0)
engine = [*map(number, mr[:4]), *(number(rov[i]) for i in (0,1,2,4,5,6,7))]
engine += list(map(int,re.search(r"f, g, h, (\d+), (\d+),",rov_macro).groups()))
engine += [int(re.search(r"\bb, (\d+), f, INVALID_CARGO",re.search(r"^#define MR.*",eng,re.M)[0])[1])]
engine += [int(re.search(r"CARGO_AGING_TICKS\s*=\s*(\d+)",timer)[1])]
coal_values = [number(coal[i]) for i in (0,3,4,5,6,7)]
metadata = [*map(number, re.search(r"(\d+),\s*(0x[0-9A-F]+)",mine_spec).groups()),
            *map(int,re.search(r"CT_COAL,\s*(\d+),\s*CT_INVALID,\s*0,\s*(\d+)",mine_spec).groups()),
            *map(number,re.search(r"(\d+),\s*(0x[0-9A-F]+)",power_spec).groups()),
            int(re.search(r"\n\s+CT_COAL,\s*(\d+)",power_spec)[1])]
cases = random.Random(1401)
rows = []
for n in range(18000):
    # Cover minimum threshold, recession rounding, byte and u16 saturation.
    rows.append([0, cases.choice([0,5,6,254,255,256,65530,65535,cases.randrange(65536)]),
                 cases.randrange(256),cases.choice([1,2,7,25,99,100,150,300]),
                 cases.choice([0,65535,cases.randrange(65536)]),cases.randrange(65536),
                 cases.randrange(2),cases.randrange(101),cases.randrange(2),cases.randrange(1<<32)])
for n in range(8000):
    rows.append([1, cases.choice([0,65535,65525,cases.randrange(65536)]),
                 cases.choice([0,65535,65534,cases.randrange(65536)]),cases.randrange(200),
                 cases.randrange(-1,3),cases.randrange(-1,3),cases.randrange(3),cases.randrange(-1,3),
                 cases.randrange(2),cases.randrange(2)])
rows.append([2])
lua_program = r"""
local d="mods/bayline/openttd/"
local P,R=dofile(d.."passengers.lua"),dofile(d.."station_rating.lua")
local C=dofile(d.."coal_industry.lua")(P,R,dofile(d.."station_catchment.lua")(P,R),dofile(d.."income.lua"))
local function owner(a) if a~=-1 then return a end end
for line in io.lines() do
  local f={}
  for n in line:gmatch("%S+") do f[#f+1]=tonumber(n) end
  if f[1]==0 then
    local _,waiting,rate,scale,p,t,recession,percentage,prod,rv=unpack(f)
    local i=C.new("coal_mine",0,0,0,{completed=true})
    i.produced.rate,i.produced.waiting,i.produced.current=rate,waiting,{production=p,transported=t}
    local calls=0
    if prod==1 then C.production_tick(i,{scale=scale,random_u32=function() calls=calls+1;return rv end}) end
    local after=i.produced.waiting
    local _,moved=C.tile_loop(i,i.tiles[1],{recession=recession==1},function(_,n)
      return math.floor(n*percentage/100)
    end)
    print(after,calls,i.produced.waiting,i.produced.current.production,i.produced.current.transported,moved>0 and 1 or 0)
  elseif f[1]==1 then
    local _,w1,w2,n,e1,e2,co,src,r1,r2=unpack(f)
    local a=C.new("power_station",1,0,0,{exclusive_supplier=owner(e1)})
    local b=C.new("power_station",2,0,0,{exclusive_supplier=owner(e2)})
    a.accepted.waiting,b.accepted.waiting=w1,w2
    local p=C.delivery({id=2,owner=co},{accepts=true,near={{ind=a},{ind=b}}},
      {source_type="industry",source=src,origin_station=0,units=n},
      {distance=10,date=491,refused=function(i) return i.id==1 and r1==1 or i.id==2 and r2==1 end})
    print(p.accepted,a.accepted.waiting,b.accepted.waiting,a.accepted.last_accepted or 0,b.accepted.last_accepted or 0,#p.plants)
  else
    for _,layouts in ipairs({C.mine_layouts,C.power_layouts}) do
      for i=0,#layouts do
        local data={#layouts[i]}
        for _,t in ipairs(layouts[i]) do for _,part in ipairs(t) do data[#data+1]=part end end
        print(unpack(data))
      end
    end
    local e,co,m,p=C.truck,C.cargo,C.spec.coal_mine,C.spec.power_station
    print(e.intro_days_after_1920,e.decay_speed,e.life_years,e.base_life_years,e.image_index,
      e.buy_factor,e.running_factor,e.speed,e.capacity,e.weight_quarters,e.power_tens_hp,e.tractive_effort,
      e.air_drag,e.load_amount,e.cargo_age_ticks)
    print(co.id,co.weight_16,co.capacity_multiplier,co.payment,co.days1,co.days2)
    print(m.build_cost_factor,m.procurement_probability,m.rate,m.minimum,
      p.build_cost_factor,p.procurement_probability,p.input_multiplier)
  end
end
"""
with tempfile.TemporaryDirectory(prefix="coal-industry-upstream-") as directory:
    d = Path(directory)
    (d / "ref.cpp").write_text(cpp)
    (d / "compare.lua").write_text(lua_program)
    subprocess.run(["c++", "-std=c++17", "-O2", d / "ref.cpp", "-o", d / "ref"], check=True)
    stdin = "\n".join(" ".join(map(str, row)) for row in rows) + "\n"
    expected = subprocess.check_output([d / "ref"], text=True, input=stdin).splitlines()
    got = subprocess.check_output([lua, d / "compare.lua"], input=stdin, cwd=root, text=True).splitlines()
    expected += [" ".join(map(str, row)) for row in (engine, coal_values, metadata)]
    assert len(expected) == len(got), (len(expected), len(got))
    for i, (want, actual) in enumerate(zip(expected, got)):
        assert list(map(int,want.split())) == list(map(int,actual.split())), (i, rows[min(i,len(rows)-1)],want,actual)

print("PASS pinned 14.1: 18,000 production/transport, 8,000 delivery cases, seven layouts and three spec rows")
