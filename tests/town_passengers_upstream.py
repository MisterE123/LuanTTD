#!/usr/bin/env python3
"""Compare native Lua house cargo and tick schedule to compiled OpenTTD 14.1."""
import argparse
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHIM = r"""
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
using uint = unsigned;
using byte = unsigned char;
struct TownProductionEffect {
  int i;
  operator int() const { return i; }
};
constexpr TownProductionEffect TPE_PASSENGERS{0}, TPE_MAIL{1};
using CargoID = int;
struct CargoSpec {
  static std::vector<const CargoSpec *> town_production_cargoes[2];
  uint town_production_multiplier=256;
  CargoID id;
  CargoID Index() const { return id; }
};
CargoSpec passengers{256,0}, mail{256,1};
std::vector<const CargoSpec *> CargoSpec::town_production_cargoes[2] = {{&passengers},{&mail}};
constexpr uint TOWN_PRODUCTION_DIVISOR=256;
struct TileIndex {
  uint i;
  TileIndex(uint i=0): i(i) {}
  uint base() const { return i; }
  operator uint() const { return i; }
};
struct StationFinder {
  StationFinder(...) {}
  int GetStations() { return 0; }
};
struct TileArea { TileArea(TileIndex,int,int) {} };
struct Town {
  struct Flow { uint new_max=0,new_act=0; };
  Flow supplied[2];
  int index=0;
  static Town *GetByTile(TileIndex);
};
Town town;
Town *Town::GetByTile(TileIndex) { return &town; }
enum class SourceType { Town };
constexpr int GM_MENU=1;
int _game_mode=0;
int is_recession;
bool EconomyIsInRecession() { return is_recession; }
enum { TCGM_ORIGINAL, TCGM_BITCOUNT };
struct {
  struct {
    int town_cargogen_mode;
    uint16_t town_cargo_scale, industry_cargo_scale;
  } economy;
} _settings_game;
std::vector<uint> rolls;
uint stage=0;
uint Random() {
  assert(stage<rolls.size());
  return rolls[stage++];
}
bool Chance16I(uint a,uint b,uint32_t roll);
bool Chance16(uint a,uint b) { return Chance16I(a,b,Random()); }
uint GB(uint32_t r,uint start,uint count) { return (r>>start)&((1u<<count)-1); }
bool HasBit(uint r,uint idx) { return (r & (1u<<idx)) != 0; }
int CountBits(uint x) { return std::popcount(x); }
uint MoveGoodsToStation(CargoID id,uint amount,SourceType,int,int) {
  std::cout << id << ":" << amount << ",";
  return amount;
}
using HouseID=int;
constexpr HouseID NEW_HOUSE_OFFSET=110;
constexpr int BUILDING_IS_ANIMATED=1;
struct HouseSpec {
  uint8_t population,mail_generation;
  int temperate,building_flags,min_year,max_year,w,h,callback_mask=0;
  struct { int grffile=0; } grf_prop;
  static const HouseSpec *Get(HouseID);
};
HouseID house_id;
int complete,has_lift;
int animated;
HouseID GetHouseType(TileIndex) { return house_id; }
bool NewHouseTileLoop(TileIndex) { return false; }
bool IsHouseCompleted(TileIndex) { return complete; }
void AdvanceHouseConstruction(TileIndex) {}
bool LiftHasDestination(TileIndex) { return has_lift; }
void AddAnimatedTile(TileIndex) { animated++; }
constexpr int CBM_HOUSE_PRODUCE_CARGO=0,CBID_HOUSE_PRODUCE_CARGO=0, CALLBACK_FAILED=65535,CALLBACK_HOUSEPRODCARGO_END=0;
uint GetHouseCallback(...) { std::abort(); }
int GetCargoTranslation(...) { std::abort(); }
bool IsValidCargoID(int) { std::abort(); }
void NOT_REACHED() { std::abort(); }
struct TimerGameTick { static uint64_t counter; };
uint64_t TimerGameTick::counter;
constexpr int PFE_GL_LANDSCAPE=0,MIN_MAP_SIZE_BITS=6,MAX_MAP_SIZE_BITS=12;
struct PerformanceAccumulator { PerformanceAccumulator(int) {} };
template<typename T, size_t L> constexpr size_t lengthof(const T (&)[L]) { return L; }
struct Map {
  static uint x,y;
  static uint LogX() { return x; }
  static uint LogY() { return y; }
};
uint Map::x,Map::y;
uint GetTileType(TileIndex) { return 0; }
void RecordTile(TileIndex tile) { std::cout << tile.base() << ","; }
struct { void (*tile_loop_proc)(TileIndex); } procs{RecordTile};
auto _tile_type_procs=std::array{&procs};
"""
DRIVER = r"""
int main() {
  char kind;
  while (std::cin >> kind) {
    if (kind=='L') {
      uint ticks;
      std::cin >> Map::x >> Map::y >> _cur_tileloop_tile.i >> TimerGameTick::counter >> ticks;
      for (uint n=0; n<ticks; n++) {
        ++TimerGameTick::counter;
        RunTileLoop();
        std::cout << ";";
      }
      std::cout << "|" << _cur_tileloop_tile.i << "|" << TimerGameTick::counter << "\n";
    } else if (kind=='T') {
      TileIndex tile;
      std::cin >> tile.i >> TimerGameTick::counter >> house_id >> complete >> has_lift
          >> _settings_game.economy.town_cargogen_mode >> is_recession
          >> _settings_game.economy.town_cargo_scale;
      stage=0;animated=0;
      rolls.resize(6);
      for (uint &r : rolls) std::cin >> r;
      TileLoop_Town(tile);
      std::cout << "|" << stage << "|" << animated << "\n";
    } else if (kind=='M') {
      std::cin >> house_id;
      auto *h=HouseSpec::Get(house_id);
      std::cout << +h->population<<","<<+h->mail_generation<<","<<h->temperate<<","
                << h->building_flags<<","<<h->min_year<<","<<h->max_year<<","<<h->w<<","<<h->h<<"\n";
    } else {
      std::abort();
    }
  }
}
"""
LUA = r"""
local H=dofile("mods/bayline/openttd/town_passengers.lua")
for line in io.lines() do
  local a={}
  for part in line:gmatch("%S+") do a[#a+1]=tonumber(part) or part end
  if a[1]=="L" then
    local K=H.new_clock(a[2],a[3],a[4],a[5])
    local parts={}
    for _=1,a[6] do
      H.advance(K,1,function(tile) parts[#parts+1]=tile.."," end)
      parts[#parts+1]=";"
    end
    print(table.concat(parts).."|"..K.head.."|"..K.counter)
  elseif a[1]=="T" then
    local parts,rng,animated={},0,0
    H.produce_tile(a[2],a[3],{id=a[4],completed=a[5]==1,lift_has_destination=a[6]==1},
      {mode=a[7]==0 and "original" or "bitcount",recession=a[8]==1,percentage=a[9],
       start_lift=function() animated=animated+1 end},
      function() rng=rng+1;return assert(a[9+rng],"Too many RNG calls") end,
      function(kind,amount) parts[#parts+1]=(kind=="passenger" and "0" or "1")..":"..amount.."," end)
    print(table.concat(parts).."|"..rng.."|"..animated)
  else
    print(table.concat(H.specs[a[2]],","))
  end
end
"""


def extract(source, name):
    start = source.index(name)
    return source[start:source.index("\n}", start)+2]


def specs(source, max_year):
    source = source.split("static const HouseSpec _original_house_specs[] = {", 1)[1]
    rows = []
    for args, ident in re.findall(r"MS\(([^)]*)\), // ([0-9A-F]{2})", source, re.S):
        fields = [s.strip() for s in args.split(",")]
        assert len(fields)==15 and int(ident,16)==len(rows)
        start,end,pop,_,_,_,mail,_,_,_,flags,climate,*_ = fields
        temp = int("HZ_TEMP" in climate.split())
        anim = int("BUILDING_IS_ANIMATED" in flags)
        dims = re.search(r"TILE_SIZE_([12])x([12])", flags)
        w,h = dims.groups() if dims else ("0","0")
        rows.append(f"{{{pop},{mail},{temp},{anim},{start},{end.replace('CalendarTime::MAX_YEAR',max_year)},{w},{h}}}")
    assert len(rows)==110
    return ("static const HouseSpec houses[] = {" + ",\n".join(rows)
            + "};\nconst HouseSpec *HouseSpec::Get(HouseID id) { return &houses[id]; }\n")


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path,help="flat staging of OpenTTD 14.1 source files")
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    def read(s): return (a.source/s).read_text()
    src=read("town_cmd.cpp")
    town="\n".join(extract(src,sig) for sig in (
        "static void TownGenerateCargo(", "static void TownGenerateCargoOriginal(",
        "static void TownGenerateCargoBinominal("))
    town += "\n" + extract(src,"static void TileLoop_Town(").split("\n\tBackup<CompanyID>",1)[0] + "\n}\n"
    economy="\n".join(extract(read("economy_func.h"),sig) for sig in (
        "static uint ScaleByInverseCargoScale(", "inline uint ScaleByCargoScale("))
    chance=extract(read("random_func.hpp"),"inline bool Chance16I(")
    loop="TileIndex _cur_tileloop_tile;\n" + extract(read("landscape.cpp"),"void RunTileLoop()")
    max_year=re.search(r"\bMAX_YEAR = (\d+);",read("timer_game_common.h"))[1]
    dat=specs(read("town_land.h"),max_year)

    rng=random.Random(141)
    cases=[f"M {i}" for i in range(110)]
    sizes=[(6,6),(6,7),(8,6),(7,9),(12,12)]
    for lx,lz in sizes:
        n=1<<(lx+lz)
        log=256 if lx+lz<16 else 5
        cases.append(f"L {lx} {lz} {rng.randrange(1,n)} 0 {log}")
        cases.append(f"L {lx} {lz} {rng.randrange(1,n)} 251 6")
    for i in range(18000):
        tick=rng.randrange(1000000)
        tile=rng.randrange(1<<24)
        if i%3==1:
            tile=(tile&~3)|((tick>>8)&3)
        rolls=" ".join(str(rng.randrange(1<<32)) for _ in range(6))
        cases.append(f"T {tile} {tick} {i%110} {int(i%20!=0)} {i%2} {i%3==2:d} {i%2} "
                     f"{rng.choice([10,25,50,75,99,100,101,175,500])} {rolls}")
    fixtures=("\n".join(cases)+"\n").encode()

    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        cpp=tmp/"stock.cpp"
        cpp.write_text("\n".join((SHIM,dat,chance,economy,town,loop,DRIVER)))
        lua=tmp/"port.lua"
        lua.write_text(LUA)
        subprocess.run(["c++","-std=c++20","-O2",str(cpp),"-o",str(tmp/"stock")],check=True)
        stock=subprocess.check_output([str(tmp/"stock")],input=fixtures).splitlines()
        port=subprocess.check_output([a.lua,str(lua)],cwd=ROOT,input=fixtures).splitlines()
    assert len(stock)==len(port)==len(cases)
    for i,(lhs,rhs) in enumerate(zip(stock,port)):
        if lhs!=rhs: raise AssertionError(f"{cases[i]}: stock {lhs[:200]!r} vs Lua {rhs[:200]!r}")
    print("PASS: all 110 vanilla HouseSpec rows, 18,000 completed/uncompleted house visits and 10 exact stock tile schedules")


if __name__=="__main__":
    main()
