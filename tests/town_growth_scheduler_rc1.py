#!/usr/bin/env python3
"""SHA-pinned OpenTTD 16.0-RC1 growth eligibility, counters and scheduler.

Usage: TMPDIR=/path/to/qa_temp python3 tests/town_growth_scheduler_rc1.py /path/to/OpenTTD [lua5.1]
Compile actual RC1 rate, radius, station, and tick functions. Stock Temperate
inputs exercise both isolated calls and consecutive growth windows. GrowTown
is a call recorder: this does not compare placement or world-clock delivery.
"""
from hashlib import sha256
from pathlib import Path
import os
import random
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
exe=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def read(name,digest):
    paths=(source/"src"/name,source/name,source/Path(name).name)
    p=next((p for p in paths if p.is_file()),paths[0])
    b=p.read_bytes()
    assert sha256(b).hexdigest()==digest, f"{p} not pinned 16.0-RC1"
    return b.decode()


def block(src,sig):
    start=re.search(sig,src,re.M).start()
    stop=src.index("{",start)
    level=1
    while level:
        stop+=1
        level+=(src[stop]=="{")-(src[stop]=="}")
    return src[start:stop+1]


town=read("town_cmd.cpp","9483d2c1b188f62241de9a4aef682db940592eb7bf0b40086c4af7b7da77a7e0")
townh=read("town.h","d10c79d839f7b5f2f440582df5eb3b72965d4801dd4afdd622db362f7403e6b2")
tickh=read("timer/timer_game_tick.h","9b2c19319b97ab83958789122fea5f081c654c3eacab1a4dd804c959ba5576c2")
radius=read("station_kdtree.h","e671e3cc17476d0c25e222ffe0160654f8e6d0d884d80ebe711051b45531afac")
randomh=read("core/random_func.hpp","6015c6cc0c91db94ef8f44e99bb4fa48a1b1211b0f44d56b979af578199a90a7")
mathh=read("core/math_func.hpp","6d3fb6bd176dd375f05ccc991f69749241b44244dd5256dafd2603edf20b221b")

cpp=r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned; using TileIndex=int; using StationID=int;
struct TimerGameTick { using Ticks=uint64_t; };
"""
cpp+="struct Ticks {"+re.search(r"^\s*static constexpr TimerGameTick::Ticks TOWN_GROWTH_TICKS[^\n]+",tickh,re.M)[0]+"\n};\n"
for name in ("TOWN_GROWTH_WINTER","TOWN_GROWTH_DESERT","TOWN_GROWTH_RATE_NONE","MAX_TOWN_GROWTH_TICKS"):
    cpp+=re.search(r"^static const \w+ "+name+r"[^\n]+",townh,re.M)[0]+"\n"
cpp+=block(townh,r"^inline uint16_t TownTicksToGameTicks")+"\n"
cpp+=block(mathh,r"^constexpr int RoundDivSU")+"\n"
cpp+=block(randomh,r"^inline bool Chance16I")+"\n"
cpp+=r"""
enum class TownFlag { CustomGrowth, IsGrowing };
struct Flags {
    unsigned bits=0;
    bool Test(TownFlag f) const { return bits & (1u << int(f)); }
    void Set(TownFlag f) { bits |= 1u << int(f); }
    void Reset(TownFlag f) { bits &= ~(1u << int(f)); }
};
enum class HouseZone { TownEdge, TownOutskirt, TownOuterSuburb, TownInnerSuburb, TownCentre };
constexpr auto HZ_ZONE_ALL = std::array{HouseZone::TownEdge, HouseZone::TownOutskirt,
    HouseZone::TownOuterSuburb, HouseZone::TownInnerSuburb, HouseZone::TownCentre};
constexpr size_t NUM_HOUSE_ZONES=HZ_ZONE_ALL.size();
enum class TownAcceptanceEffect { None, Passengers, Mail, Goods, Water, Food, End };
template<class E> auto EnumRange(E end) {
    assert(int(end)==6); return std::array{E(0), E(1), E(2), E(3), E(4), E(5)};
}
template<class E> constexpr auto to_underlying(E e) { return int(e); }
enum class WindowClass { TownView };
enum class TropicZone { Normal, Desert };
enum class TownExpandMode { Buildings, Roads };
struct TownExpandModes { bool buildings=false, roads=false;
    TownExpandModes(TownExpandMode m) { Set(m); }
    void Set(TownExpandMode m) { (m==TownExpandMode::Buildings ? buildings : roads)=true; }
};
struct Settings {struct {uint town_growth_rate=2;bool allow_town_roads=true;} economy;} _settings_game;
struct Map {static int SizeX(){return 512;}static int SizeY(){return 512;}};
int TileX(int tile){return tile%512;} int TileY(int tile){return tile/512;}
uint DistanceSquare(int a,int b){auto x=TileX(a)-TileX(b),y=TileY(a)-TileY(b);return x*x+y*y;}
int TileHeight(int){return 0;} int GetSnowLine(){return 255;} TropicZone GetTropicZone(int){return TropicZone::Normal;}
void SetWindowDirty(WindowClass,int){}
template<class T> struct Effects {
    std::array<T,6> values{};
    T &operator[](TownAcceptanceEffect e){return values[int(e)];}
};
struct Town{
    Flags flags;
    int xy=0,index=0;
    bool larger_town=false;
    uint16_t grow_counter=0,growth_rate=0;
    int fund_buildings_months=0;
    Effects<uint> goal;
    struct Cache {uint num_houses=0,population=0;std::array<uint32_t,NUM_HOUSE_ZONES> squared_town_zone_radius{};} cache;
    struct Cargo {uint old_act=0;};
    Effects<Cargo> received;
};
struct Station {
    TileIndex xy=0;uint time_since_load=255,time_since_unload=255;
    static Station* Get(int id);
};
std::vector<Station> stations;
Station* Station::Get(int id){return &stations[id];}
struct Index {
    template<class Func> void FindContained(int x1,int y1,int x2,int y2,Func func){
        for(size_t i=0;i<stations.size();i++){
            const auto x=TileX(stations[i].xy),y=TileY(stations[i].xy);
            if(x1<=x && x<x2 && y1<=y && y<y2)func(i);
        }
    }
} _station_kdtree;
uint32_t random_sample;int samples=0,attempts=0;bool succeeds=false;
bool Chance16(uint a,uint b){samples++;return Chance16I(a,b,random_sample);}
uint16_t replacement_rate=0;
bool GrowTown(Town *t,TownExpandModes m){assert(m.buildings && m.roads==_settings_game.economy.allow_town_roads);attempts++;if(succeeds)t->growth_rate=replacement_rate;return succeeds;}
"""
cpp+="template<class Func>\n"+block(radius,r"^void ForAllStationsRadius")+"\n"
for sig in [r"^void UpdateTownRadius",r"^HouseZone GetTownRadiusGroup",r"^static void ForAllStationsNearTown",
            r"^static int CountActiveStations",r"^static uint GetNormalGrowthRate",
            r"^static void UpdateTownGrowCounter",r"^static void UpdateTownGrowthRate\(Town \*t\)\n",
            r"^static void UpdateTownGrowth\(Town \*t\)\n",r"^static void TownTickHandler"]:
    cpp+=("template<class Func>\n" if "ForAllStationsNearTown" in sig else "")+block(town,sig)+"\n"

cpp+=r"""
int main(){
    int kind;
    while(std::cin>>kind){
        Town t;
        if(kind==0){
            int city,custom,count,x,y,dx,dy;
            t.xy=256+256*512;
            std::cin>>t.cache.num_houses>>t.cache.population>>t.fund_buildings_months>>city>>custom
                >>t.growth_rate>>t.grow_counter>>_settings_game.economy.town_growth_rate>>random_sample>>count>>dx>>dy;
            t.larger_town=city;
            if(custom)t.flags.Set(TownFlag::CustomGrowth);
            for(auto effect:EnumRange(TownAcceptanceEffect::End))std::cin>>t.goal[effect]>>t.received[effect].old_act;
            stations.assign(count,{});
            for(auto &s:stations){
                std::cin>>x>>y>>s.time_since_load>>s.time_since_unload;
                s.xy=t.xy+x+y*512;
            }
            UpdateTownRadius(&t);
            samples=0;UpdateTownGrowth(&t);
            std::cout<<CountActiveStations(&t)<<" "<<int(GetTownRadiusGroup(&t,t.xy+dx+dy*512))<<" "<<t.growth_rate
              <<" "<<t.grow_counter<<" "<<t.flags.Test(TownFlag::IsGrowing)<<" "<<samples;
            for(uint r:t.cache.squared_town_zone_radius)std::cout<<" "<<r;
            std::cout<<"\n";
        } else if(kind==2){
            int city,months;
            t.xy=256+256*512;
            std::cin>>t.cache.num_houses>>city>>t.growth_rate>>t.grow_counter>>months;
            t.larger_town=city;
            stations.assign(1,{t.xy,255,255});
            for(int month=0;month<months;month++){
                int ticks,interval;
                std::cin>>t.fund_buildings_months>>_settings_game.economy.town_growth_rate
                    >>stations[0].time_since_load>>random_sample>>ticks>>succeeds>>interval;
                UpdateTownRadius(&t);
                attempts=0;samples=0;
                UpdateTownGrowth(&t);
                for(int i=0;i<ticks;i++){
                    int old=attempts;
                    replacement_rate=t.growth_rate;
                    TownTickHandler(&t);
                    if(old!=attempts){
                        std::cout<<" "<<i;
                        if(succeeds && ((attempts-1)%interval==0)){
                            t.cache.num_houses++;
                            UpdateTownRadius(&t);
                            UpdateTownGrowthRate(&t);
                            t.grow_counter=t.growth_rate;
                        }
                    }
                }
                std::cout<<" -1 "<<month<<" "<<t.cache.num_houses<<" "<<t.growth_rate
                    <<" "<<t.grow_counter<<" "<<t.flags.Test(TownFlag::IsGrowing)<<" "<<samples;
            }
            std::cout<<"\n";
        } else{
            int grow,n;
            std::cin>>grow>>t.growth_rate>>t.grow_counter>>n>>succeeds>>replacement_rate;
            if(grow)t.flags.Set(TownFlag::IsGrowing);
            attempts=0;
            for(int i=0;i<n;i++)TownTickHandler(&t);
            std::cout<<t.growth_rate<<" "<<t.grow_counter<<" "<<attempts<<"\n";
        }
    }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  if a[1]==0 then
    local _,n,p,fund,city,custom,rate,counter,setting,u32,count,x,y=unpack(a)
    local t=G.new(0,256,256,{num_houses=n,population=p,fund_buildings_months=fund,
      larger_town=city==1,custom_growth=custom==1,growth_rate=rate,grow_counter=counter})
    for i=0,5 do t.goal[i]=a[14+2*i];t.received[i]={old_act=a[15+2*i]} end
    local st={}
    for i=0,count-1 do
      local x,y,l,u=unpack(a,26+i*4,29+i*4)
      st[i+1]={x=x+256,z=y+256,time_since_load=l,time_since_unload=u}
    end
    local samples=0
    G.update(t,st,setting,function() samples=samples+1;return u32 end)
    local active=G.active_stations(t,st)
    st.count_near=G.index_active_stations(st)
    assert(G.active_stations(t,st)==active,"indexed station count")
    print(active,G.zone(t,x+256,y+256),t.growth_rate,t.grow_counter,
      t.growing and 1 or 0,samples,unpack(t.radii))
  elseif a[1]==2 then
    local _,houses,city,rate,counter,months=unpack(a)
    local t=G.new(0,256,256,{num_houses=houses,larger_town=city==1,
      growth_rate=rate,grow_counter=counter})
    local stations={{x=256,z=256,time_since_unload=255}}
    local out={}
    for month=0,months-1 do
      local fund,setting,age,word,ticks,succeeds,interval=unpack(a,7+month*7,13+month*7)
      stations[1].time_since_load=age
      t.fund_buildings_months=fund
      local samples=0
      G.update(t,stations,setting,function() samples=samples+1;return word end)
      local attempts=0
      for i=0,ticks-1 do
        G.tick(t,function()
          out[#out+1]=i
          attempts=attempts+1
          if succeeds==1 and (attempts-1)%interval==0 then
            G.house_added(t,stations,setting)
          end
          return succeeds==1
        end)
      end
      local values={-1,month,t.num_houses,t.growth_rate,t.grow_counter,t.growing and 1 or 0,samples}
      for _,v in ipairs(values) do out[#out+1]=v end
    end
    print(table.concat(out," "))
  else
    local _,g,r,c,n,s,m=unpack(a)
    local t=G.new(0,0,0,{growth_rate=r,grow_counter=c,growing=g==1})
    local k=0
    for i=1,n do
      G.tick(t,function(t) k=k+1;if s==1 then t.growth_rate=m;return true end;return false end)
    end
    print(t.growth_rate,t.grow_counter,k)
  end
end
"""
rng=random.Random(16001)
rows=[]
edges=[0,1,4,49,50,51,89,91,92,93,95,96,999]
for _ in range(12000):
    n=rng.choice(edges+[rng.randrange(1000)])
    fund=rng.choice([0]*4+[1,2,3])
    setting=rng.randrange(5)
    old=rng.choice([0,69,1420,52000,65535,rng.randrange(65535)])
    counter=rng.randrange(old+1)
    c=rng.choice([0,1,2,7,31,32,77])
    row=[0,n,rng.randrange(100000),fund,rng.randrange(2),rng.randrange(2),
         old,counter,setting,rng.randrange(2**32),c,rng.randrange(-15,16),rng.randrange(-15,16)]
    for i in range(6):
        row.extend([rng.choice([0,0,0,20,40]),rng.randrange(65)])
    for i in range(c):
        row.extend([rng.randrange(-20,21),rng.randrange(-20,21),
                    rng.choice([0,19,20,21,255]),rng.choice([0,19,20,21,255])])
    rows.append(row)
for _ in range(6500):
    rows.append([1,rng.randrange(2),rng.choice([0,1,69,70,71,400]),
                 rng.randrange(300),rng.randrange(300),rng.randrange(2),rng.randrange(350)])
for _ in range(128):
    row=[2,rng.choice(edges),rng.randrange(2),rng.randrange(10000),rng.randrange(4),12]
    for month in range(12):
        row.extend([3-month%3 if month<3 else 0,rng.choice([1,2,3,4]),rng.choice([0,20,21,255]),
                    rng.randrange(2**32),rng.randrange(1200,2500),rng.randrange(2),rng.randrange(1,4)])
    rows.append(row)
with tempfile.TemporaryDirectory(prefix="town-growth-scheduler-rc1-") as work:
    d=Path(work)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
    ref=subprocess.check_output([d/"ref"],text=True,input=data).splitlines()
    lua=subprocess.check_output([exe,d/"test.lua"],text=True,input=data,cwd=root).splitlines()
    assert len(ref)==len(lua)==len(rows)
    for i,(a,b) in enumerate(zip(ref,lua)):
        assert list(map(int,a.split()))==list(map(int,b.split())),(i,rows[i],a,b)
print(f"PASS {len(rows)} RC1 radius, station gate, and growth timer cases (including 128 twelve-window traces)")
