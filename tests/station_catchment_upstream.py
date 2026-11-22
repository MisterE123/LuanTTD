#!/usr/bin/env python3
"""Compile stock station radius, acceptance and competing allocation for comparison."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PIN = {
    "station.cpp": "0c4d82f845fcf2ddb246668415e78dfbaa17ab5d939f702c6c0209bf5feaab42",
    "station_cmd.cpp": "7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5",
    "station_type.h": "54fb000b5a7ffbd1d5fc1cec7e839bb3c5160f58c90824acaa7c6e80367fbaf4",
    "station_base.h": "397bf6bfd7fe7194f265eb674b47899aaa156af0927800228eea30f938ed8c3b",
    "game_settings.ini": "68c0745dea1a485db62b0edff2950f04999703c847b1423e3f6c65a7eca4e23a",
    "town_land.h": "a6925280753e551f4426a92d76a8c57f49171a519c860d855b3cd29946c817d7",
}
SETUP = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <iostream>
#include <set>
#include <vector>
using byte = unsigned char;
using uint = unsigned int;
using TileIndex = int;
using CargoID = int;
using CargoTypes = unsigned int;
using Owner = int;
using SourceID = int;
enum class SourceType { Town };
constexpr Owner OWNER_NONE = 16, INVALID_OWNER = -1;
constexpr int NUM_CARGO = 2, CC_PASSENGERS=0, MP_STATION=0;
constexpr int WC_STATION_VIEW=0, WID_SV_ACCEPT_RATING_LIST=0;
constexpr bool IsTileType(TileIndex, int) { return true; }
constexpr bool IsCargoInClass(CargoID i, int) { return i==0; }
void SetWindowWidgetDirty(int,int,int) {}
#define NOT_REACHED() __builtin_unreachable()
#define SB(result,offset,width,value) { if (value) (result)|=1u<<(offset); else (result)&=~(1u<<(offset)); }
using CargoArray = std::array<uint, NUM_CARGO>;
struct Rect { bool covered=false; bool IsEmpty()const{return !covered;} };
struct Town { int exclusive_counter, exclusivity; };
struct GoodsEntry {
    int rating=0, last_speed=0, link_graph=-1, node=0;
    uint status=0;
    enum {GES_ACCEPTANCE=0};
    HAS_TRIED_LOADING
};
struct LinkGraph {
    static bool IsValidID(int){return false;}
    static LinkGraph* Get(int){return nullptr;}
    LinkGraph& operator[](int){return *this;}
    void SetDemand(int){}
};
struct Station {
    int index=0;
    Owner owner=0;
    Town* town=nullptr;
    byte facilities=0;
    std::array<GoodsEntry,NUM_CARGO> goods;
    Rect rect;
    CargoTypes always_accepted=0;
    struct { struct Spec { uint catchment=10; }; const Spec *GetSpec()const{return nullptr;} } airport;
    bool IsInUse()const{return true;}
};
struct StationCompare {
  bool operator()(const Station *a,const Station *b)const{return a->index<b->index;}
};
using StationList = std::set<Station*,StationCompare>;
struct {
  struct {bool modified_catchment;} station;
  struct {bool selectgoods;} order;
} _settings_game;
int _local_company=0;
CargoArray run_house{};
CargoArray GetAcceptanceAroundStation(const Station*, CargoTypes* always){
  *always=(run_house[0]>0) | ((run_house[1]>0)<<1);
  return run_house;
}
CargoTypes GetAcceptanceMask(Station* st){
  return st->goods[0].status | (st->goods[1].status<<1);
}
void ShowRejectOrAcceptNews(Station*,CargoTypes,bool){}
std::vector<std::pair<int,uint>> got;
uint UpdateStationWaiting(Station *st,CargoID,uint amount,SourceType,SourceID){
  got.emplace_back(st->index,amount);
  return 0;
}
StationType GetStationType(TileIndex tile) {
    const StationType by_kind[]={STATION_BUS,STATION_TRUCK,STATION_RAIL,STATION_DOCK,STATION_BUOY,STATION_WAYPOINT};
    return by_kind[tile-1];
}
"""
DRIVER = r"""
int main(){
  const byte facility[]={FACIL_BUS_STOP,FACIL_TRUCK_STOP,FACIL_TRAIN,FACIL_DOCK,0,0};
  const std::array<CargoArray,110> house_table{{HOUSE_ROWS}};
  int x,y,modified,select,owner,n;
  while(std::cin>>x>>y>>modified>>select>>owner>>n) {
    _settings_game.station.modified_catchment=modified;
    _settings_game.order.selectgoods=select;
    std::array<Town,12> towns;
    std::array<Station,12> stations;
    std::array<int,12> rating{},speed{};
    StationList nearby;
    for(int j=0;j<n;++j) {
      Station &s=stations[j];
      s.index=j+1;
      int ax,ay,a,bx,by,b;
      std::cin>>s.owner>>rating[j]>>speed[j]>>ax>>ay>>a>>bx>>by>>b
              >>towns[j].exclusive_counter>>towns[j].exclusivity;
      s.town=&towns[j];
      s.facilities=facility[a-1] | facility[b-1];
      bool covered=false;
      // Test a point in the union of GetTileCatchmentRadius + TileArea::Expand
      // after StationFinder's per-house lookup. No nearest-facility shortcut.
      int ra=GetTileCatchmentRadius(a,&s), rb=GetTileCatchmentRadius(b,&s);
      if(ra>0) covered|=std::max(std::abs(ax-x),std::abs(ay-y))<=ra;
      if(rb>0) covered|=std::max(std::abs(bx-x),std::abs(by-y))<=rb;
      s.rect.covered=true;
      if(covered) nearby.insert(&s);
    }
    int p;std::cin>>p;int cargo=p==1?0:1;
    for(int j=0;j<n;++j) {
      Station &s=stations[j];
      auto &g=s.goods[cargo];g.rating=rating[j];g.last_speed=speed[j];
      run_house=nearby.count(&s)?house_table[(x*16+y)%110]:CargoArray{};
      UpdateStationAcceptance(&s,false);
      if(j)std::cout<<",";
      std::cout<<(g.status&1)<<":"<<((s.always_accepted>>cargo)&1);
    }
    got.clear();
    MoveGoodsToStation(cargo,7,SourceType::Town,0,&nearby,owner);
    std::cout<<" ";
    for(size_t i=0;i<got.size();++i) {
      if(i)std::cout<<",";
      std::cout<<got[i].first<<":"<<got[i].second;
    }
    std::cout<<"\n";
  }
}
"""

def section(source, marker, suffix):
    start = source.index(marker)
    return source[start:source.index(suffix, start)+len(suffix)]

def get_source(path, name):
    for candidate in (path/name, path/"src"/name, path/"src"/"table"/name):
        if candidate.exists():
            data = candidate.read_bytes()
            assert sha256(data).hexdigest()==PIN[name], f"Expected pinned OpenTTD 14.1 {name}"
            return data.decode()
    raise FileNotFoundError(name)

def main():
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument("source",type=Path)
    args.add_argument("--lua",default="lua5.1")
    args.add_argument("--cxx",default="g++")
    arg=args.parse_args()
    sources={name:get_source(arg.source,name) for name in PIN}
    for name,value in [("station.station_spread","12"),("station.modified_catchment","true"),("order.selectgoods","true")]:
        pattern=r"var\s*=\s*"+re.escape(name)+r"[^\[]*?\bdef\s*=\s*"+value+r"\b"
        assert re.search(pattern,sources["game_settings.ini"])
    semantics=[section(sources["station_type.h"],f"enum {name}","\n};")
               for name in ["StationType {","StationFacility : byte","CatchmentArea {"]]
    method=section(sources["station_base.h"],"bool HasVehicleEverTriedLoading() const"," }")
    cpp=SETUP.replace("HAS_TRIED_LOADING",method)
    offset=cpp.index("using CargoArray")
    cpp=cpp[:offset]+"\n".join(semantics)+"\n"+cpp[offset:]
    station=sources["station.cpp"]; command=sources["station_cmd.cpp"]
    for body,marker in [(station,"static uint GetTileCatchmentRadius"),
                        (command,"void UpdateStationAcceptance("),
                        (command,"static bool CanMoveGoodsToStation("),
                        (command,"uint MoveGoodsToStation(")]:
        cpp+="\n"+section(body,marker,"\n}")
    data=sources["town_land.h"].split("static const HouseSpec _original_house_specs[] = {",1)[1]
    rows=[]
    for fields, ident in re.findall(r"MS\(([^)]*)\), // ([0-9A-F]{2})",data,re.S):
        fields=[s.strip() for s in fields.split(",")]
        assert len(rows)==int(ident,16) and fields[12:14]==["CT_PASSENGERS","CT_MAIL"]
        rows.append("{"+fields[7]+","+fields[8]+"}")
    assert len(rows)==110
    cpp+=DRIVER.replace("HOUSE_ROWS",",".join(rows))
    rng=random.Random(0x1471)
    cases=[]
    for i in range(6500):
        n=rng.randrange(1,12)
        x,y=[rng.randrange(16) for _ in range(2)]
        tokens=[x,y,i%2,(i//2)%2,rng.choice([-1,-1,-1,0,1,16]),n]
        for _ in range(n):
            a=rng.choice([1,2,3,4,5,6])
            b=rng.choice([1,2,3,4]) if a<=4 else a
            tokens.extend([rng.choice([0,1,16]),rng.choice([0,100,100,255,rng.randrange(256)]),
                rng.choice([0,1,200]),rng.randrange(16),rng.randrange(16),a,
                rng.randrange(16),rng.randrange(16),b,rng.choice([0,5]),rng.randrange(2)])
        tokens.append((i//4)%2)
        cases.append(" ".join(map(str,tokens)))
    data="\n".join(cases)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        source=Path(tmp)/"ref.cpp"; out=Path(tmp)/"ref"
        source.write_text(cpp)
        subprocess.run([arg.cxx,"-std=c++17","-O2",str(source),"-o",str(out)],check=True)
        expected=subprocess.check_output([str(out)],input=data,text=True).splitlines()
        actual=subprocess.check_output([arg.lua,"tests/station_catchment.lua","differential"],
            cwd=ROOT,input=data,text=True).splitlines()
    assert len(expected)==len(actual)==len(cases)
    for case,want,got in zip(cases,expected,actual):
        assert want==got,(case,want,got)
    print(f"PASS: {len(cases)} OpenTTD 14.1 combined radius/acceptance/selective allocation cases")

if __name__=="__main__":
    main()
