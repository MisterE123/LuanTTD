#!/usr/bin/env python3
"""SHA-pinned OpenTTD 14.1 town growth scheduler and service test.

Usage: TMPDIR=/path/to/qa_temp python3 tests/town_growth_upstream.py /path/to/OpenTTD [lua5.1]
Town, vehicle, window, k-d index and economy setting shims only. Compile
the actual rate/counter/radius/service/scheduler functions and constants,
and the house selector and footprint functions on nondestructive boards.
"""
from hashlib import sha256
from pathlib import Path
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
    assert sha256(b).hexdigest()==digest, f"{p} not pinned 14.1"
    return b.decode()


def block(src,sig):
    start=re.search(sig,src,re.M).start()
    stop=src.index("{",start)
    level=1
    while level:
        stop+=1
        level+=(src[stop]=="{")-(src[stop]=="}")
    return src[start:stop+1]


town=read("town_cmd.cpp","2fb473e5f77d374974348f12a9d9082dcf614de6983b886a91ef1b389f002a48")
houses=read("table/town_land.h","a6925280753e551f4426a92d76a8c57f49171a519c860d855b3cd29946c817d7")
townh=read("town.h","463e216ab5f8e0fe791b61865edab029cf9788feafe3b785eaaaaff4e3150b04")
tickh=read("timer/timer_game_tick.h","be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1")
radius=read("station_kdtree.h","aa8514400e77dc33ef41a0e2ef5e0a0d613643d52096effed6b4e5e80a0b40be")
randomh=read("core/random_func.hpp","b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef")
mathh=read("core/math_func.hpp","96557de406ae7c7252b607dfcfe3fb7711b1e591199d2196c12fb84eaefc7773")

cpp=r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>
using uint=unsigned; using byte=uint8_t; using TileIndex=int; using StationID=int;
struct TimerGameTick { using Ticks=uint64_t; };
"""
cpp+="struct Ticks {"+re.search(r"^\s*static constexpr TimerGameTick::Ticks TOWN_GROWTH_TICKS[^\n]+",tickh,re.M)[0]+"\n};\n"
for name in ("TOWN_GROWTH_WINTER","TOWN_GROWTH_DESERT","TOWN_GROWTH_RATE_NONE","MAX_TOWN_GROWTH_TICKS"):
    cpp+=re.search(r"^static const \w+ "+name+r"[^\n]+",townh,re.M)[0]+"\n"
cpp+=block(townh,r"^inline uint16_t TownTicksToGameTicks")+"\n"
cpp+=block(mathh,r"^constexpr int RoundDivSU")+"\n"
cpp+=block(randomh,r"^inline bool Chance16I")+"\n"
cpp+=r"""
enum {TOWN_CUSTOM_GROWTH=3,TOWN_IS_GROWING=4,WC_TOWN_VIEW=0,TAE_BEGIN=0,TAE_END=4,TROPICZONE_DESERT=1};
using HouseZonesBits=int;
enum {HZB_BEGIN=0,HZB_TOWN_EDGE=0,HZB_TOWN_OUTSKIRT=1,HZB_TOWN_OUTER_SUBURB=2,HZB_TOWN_INNER_SUBURB=3,HZB_TOWN_CENTRE=4,HZB_END=5};
struct Settings {struct {int town_growth_rate=2;} economy;struct {int landscape=0;} game_creation;} _settings_game;
struct Map {static int SizeX(){return 512;}static int SizeY(){return 512;}};
int TileX(int tile){return tile%512;} int TileY(int tile){return tile/512;}
uint DistanceSquare(int a,int b){auto x=TileX(a)-TileX(b),y=TileY(a)-TileY(b);return x*x+y*y;}
int TileHeight(int){return 0;} int GetSnowLine(){return 255;} int GetTropicZone(int){return 0;}
bool HasBit(int f,int i){return (f>>i)&1;} template<class T> void SetBit(T &f,int i){f|=1u<<i;}void ClrBit(int &f,int i){f&=~(1u<<i);}
void SetWindowDirty(int,int){}
struct Town{
    int flags=0,xy=0,index=0,layout=0;
    bool larger_town=false;
    uint16_t grow_counter=0,growth_rate=0;
    int fund_buildings_months=0;
    std::array<uint,4> goal{};
    struct Cache {uint num_houses=0,population=0;uint32_t squared_town_zone_radius[5]{};struct {uint class_count[1]{},id_count[110]{};} building_counts;} cache;
    struct Cargo {uint old_act=0;} received[4];
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
bool GrowTown(Town *t){attempts++;if(succeeds)t->growth_rate=replacement_rate;return succeeds;}
"""
cpp+="template<class Func>\n"+block(radius,r"^void ForAllStationsRadius")+"\n"
for sig in [r"^void UpdateTownRadius",r"^HouseZonesBits GetTownRadiusGroup",r"^static void ForAllStationsNearTown",
            r"^static int CountActiveStations",r"^static uint GetNormalGrowthRate",
            r"^static void UpdateTownGrowCounter",r"^static void UpdateTownGrowthRate\(Town \*t\)\n",
            r"^static void UpdateTownGrowth\(Town \*t\)\n",r"^static void TownTickHandler"]:
    cpp+=("template<class Func>\n" if "ForAllStationsNearTown" in sig else "")+block(town,sig)+"\n"
cpp+=r"""
enum {TL_2X2_GRID=2,TL_3X3_GRID=3,TOWN_HAS_CHURCH=0,TOWN_HAS_STADIUM=1};
enum {TILE_SIZE_1x1=1,TILE_SIZE_1x2=2,TILE_SIZE_2x1=4,TILE_SIZE_2x2=8,
      BUILDING_IS_CHURCH=16,BUILDING_IS_STADIUM=32,TILE_NOT_SLOPED=64};
enum {HZ_ZON1=1,HZ_ZON2=2,HZ_ZON3=4,HZ_ZON4=8,HZ_ZON5=16,HZ_TEMP=4096};
enum {LT_ARCTIC=1,INVALID_HOUSE_ID=65535,HOUSE_NO_CLASS=0,NUM_HOUSES=110,
      BUILDING_IS_HISTORICAL=1,CBM_HOUSE_ALLOW_CONSTRUCTION=0,CBID_HOUSE_ALLOW_CONSTRUCTION=0,
      CALLBACK_FAILED=65535,GM_EDITOR=1,TOWN_HOUSE_COMPLETED=3,SLOPE_FLAT=0,
      CMD_LANDSCAPE_CLEAR=0,DC_AUTO=1,DC_NO_WATER=2};
using Slope=int;using HouseID=uint16_t;
struct CalendarTime {static constexpr int MAX_YEAR=5000000;};
struct TimerGameCalendar {static int year;}; int TimerGameCalendar::year;
struct HouseSpec {
    int min_year,max_year,population,building_flags;uint building_availability;
    bool enabled=true;struct{int override=INVALID_HOUSE_ID,grffile=0;}grf_prop;
    int class_id=HOUSE_NO_CLASS,probability=16,extra_flags=0,callback_mask=0;
    static const HouseSpec* Get(HouseID id);
};
#define MS(mnd, mxd, p, rc, bn, rr, mg, ca1, ca2, ca3, bf, ba, cg1, cg2, cg3) {mnd,mxd,p,bf,ba}
"""
# Project only the original macro fields read by the stock selector.
source_rows=re.findall(r"^\s+(MS\(.*?\)),\s*// [A-F0-9]{2}",houses,re.M|re.S)
assert len(source_rows)==110
for macro in set(re.findall(r"\b(?:TILE_SIZE_\w+|TILE_NO_FLAG|TILE_NOT_\w+|BUILDING_\w+|HZ_\w+)\b"," ".join(source_rows)))-{
        "TILE_SIZE_1x1","TILE_SIZE_1x2","TILE_SIZE_2x1","TILE_SIZE_2x2","BUILDING_IS_CHURCH",
        "BUILDING_IS_STADIUM","TILE_NOT_SLOPED","HZ_TEMP","HZ_ZON1","HZ_ZON2","HZ_ZON3","HZ_ZON4","HZ_ZON5"}:
    cpp+=f"#define {macro} 0\n"
cpp+="const HouseSpec entries[]={\n"+",\n".join(source_rows)+"};\n"
cpp+=r"""
const HouseSpec* HouseSpec::Get(HouseID id){return entries+id;}
bool roads=false,_generating_world=false;
int _game_mode=0;
bool TownAllowedToBuildRoads(){return roads;}
enum DiagDirection {DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END};
DiagDirection operator++(DiagDirection &d,int){auto old=d;d=DiagDirection(d+1);return old;}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((d+2)%4);}
int TileOffsByDiagDir(DiagDirection d){return std::array<int,4>{-1,512,1,-512}[d];}
struct TileIndexDiffC {int x,y;};
TileIndexDiffC TileIndexToTileIndexDiffC(TileIndex a,TileIndex b){return {TileX(a)-TileX(b),TileY(a)-TileY(b)};}
std::array<int,9> local_map;
int base;
int state(TileIndex tile){
    int x=TileX(tile)-TileX(base),y=TileY(tile)-TileY(base);
    return x>=-1 && x<=1 && y>=-1 && y<=1 ? local_map[(y+1)*3+x+1] : 1;
}
Slope GetTileSlope(TileIndex tile){return state(tile)==3 ? 17 : state(tile)==4 ? 3 : 0;}
int GetTileMaxZ(TileIndex tile){return state(tile)==2 || state(tile)==4 ? 8 : 0;}
bool IsSteepSlope(Slope s){return s&16;}
bool IsBridgeAbove(TileIndex tile){return state(tile)==5;}
bool RoadTypesAllowHouseHere(TileIndex tile){return state(tile)!=6;}
struct Quote {bool good;bool Succeeded() const{return good;}};
template<int id> struct Command{static Quote Do(int,TileIndex tile){return {state(tile)!=1};}};
int HighestSnowLine(){return 255;}
uint16_t GetHouseCallback(int,int,int,int,Town*,int,bool,byte){return CALLBACK_FAILED;}
bool Convert8bitBooleanCallback(int,int,uint16_t){return true;}
int GB(uint32_t r,int p,int n){return (r>>p)&((1u<<n)-1);}
void ChangePopulation(Town *,int){}
std::vector<uint32_t> rng_values;
uint32_t Random(){assert((size_t)samples<rng_values.size());return rng_values[samples++];}
uint32_t RandomRange(uint32_t max){return (uint64_t(Random())*max)>>32;}
int selected_id,selected_tile,selected_random;
void MakeTownHouse(TileIndex tile,Town *,byte counter,byte stage,HouseID house,byte random_bits){
    assert(counter==0 && stage==0);selected_id=house;selected_tile=tile;selected_random=random_bits;
}
"""
for sig in ("CanBuildHouseHere","CheckBuildHouseSameZ","CheckFree2x2Area","TownLayoutAllowsHouseHere",
            "TownLayoutAllows2x2HouseHere","CheckTownBuild2House","CheckTownBuild2x2House","BuildTownHouse"):
    cpp+=block(town,r"^static (?:inline )?bool "+sig+r"\([^;\n]*\)\n")+"\n"
cpp+=r"""
int main(){
    int kind;
    while(std::cin>>kind){
        Town t;
        if(kind==0){
            int city,custom,count,x,y,dx,dy,funded,flag,old_growth,old_counter;
            t.xy=256+256*512;
            std::cin>>t.cache.num_houses>>t.cache.population>>funded>>city>>custom
                >>old_growth>>old_counter>>_settings_game.economy.town_growth_rate>>random_sample>>count
                >>dx>>dy;
            t.fund_buildings_months=funded;t.larger_town=city;t.growth_rate=old_growth;t.grow_counter=old_counter;
            if(custom)SetBit(t.flags,TOWN_CUSTOM_GROWTH);
            for(int i=0;i<4;i++)std::cin>>t.goal[i]>>t.received[i].old_act;
            stations.assign(count,{});
            for(auto &s:stations){
                std::cin>>x>>y>>s.time_since_load>>s.time_since_unload;
                s.xy=t.xy+x+y*512;
            }
            UpdateTownRadius(&t);
            samples=0;UpdateTownGrowth(&t);
            std::cout<<CountActiveStations(&t)<<" "<<GetTownRadiusGroup(&t,t.xy+dx+dy*512)<<" "<<t.growth_rate
              <<" "<<t.grow_counter<<" "<<HasBit(t.flags,TOWN_IS_GROWING)<<" "<<samples;
            for(uint r:t.cache.squared_town_zone_radius)std::cout<<" "<<r;
            std::cout<<"\n";
        } else if(kind==2){
            int layout,dx,dy,blocked,unique,count;
            std::cin>>t.cache.num_houses>>layout>>roads>>dx>>dy>>TimerGameCalendar::year>>unique>>blocked;
            t.layout=layout;t.xy=256+256*512;base=t.xy+dx+dy*512;t.flags=unique;
            if(blocked>=0)t.cache.building_counts.id_count[blocked]=65535;
            for(int &tile:local_map)std::cin>>tile;
            std::cin>>count;rng_values.resize(count);
            for(auto &r:rng_values)std::cin>>r;
            UpdateTownRadius(&t);samples=0;selected_id=selected_tile=selected_random=-1;
            const bool built=BuildTownHouse(&t,base);
            if(built) std::cout<<selected_id<<" "<<TileX(selected_tile)-256<<" "<<TileY(selected_tile)-256<<" "<<selected_random;
            else std::cout<<"-1 -1 -1 -1";
            std::cout<<" "<<samples<<"\n";
        } else if(kind==3){
            std::cin>>t.index;
            const HouseSpec &spec=*HouseSpec::Get(t.index);
            if(!(spec.building_availability&HZ_TEMP)) {std::cout<<"-1\n";continue;}
            int f=spec.building_flags;
            std::cout<<t.index<<" "<<(spec.building_availability&31)<<" "<<spec.min_year<<" "<<spec.max_year
              <<" "<<spec.population<<" "<<((f&(TILE_SIZE_2x1|TILE_SIZE_2x2)) ? 2:1)
              <<" "<<((f&(TILE_SIZE_1x2|TILE_SIZE_2x2)) ? 2:1)<<" "<<((f&BUILDING_IS_CHURCH) ? 1:(f&BUILDING_IS_STADIUM) ? 2:0)
              <<" "<<spec.probability<<"\n";
        } else {
            int grown,count,rate,counter,rep;
            std::cin>>grown>>rate>>counter>>count>>succeeds>>rep;
            attempts=0;
            if(grown)SetBit(t.flags,TOWN_IS_GROWING);
            t.growth_rate=rate;t.grow_counter=counter;replacement_rate=rep;
            for(int i=0;i<count;i++) TownTickHandler(&t);
            std::cout<<t.growth_rate<<" "<<t.grow_counter<<" "<<attempts<<"\n";
        }
    }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local G=dofile(p.."town_growth.lua")
local H=dofile(p.."town_growth_houses.lua")
local B=dofile(p.."town_growth_build.lua")(G,H)
local catalog={}
for _,v in ipairs(H) do catalog[v[1]]=v end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  if a[1]==0 then
    local _,n,p,fund,city,custom,rate,counter,setting,u32,count,x,y=unpack(a)
    local t=G.new(0,256,256,{num_houses=n,population=p,fund_buildings_months=fund,
      larger_town=city==1,custom_growth=custom==1,growth_rate=rate,grow_counter=counter})
    for i=0,3 do t.goal[i]=a[14+2*i];t.received[i]={old_act=a[15+2*i]} end
    local st={}
    for i=0,count-1 do
      local x,y,l,u=unpack(a,22+i*4,25+i*4)
      st[i+1]={x=x+256,z=y+256,time_since_load=l,time_since_unload=u}
    end
    local samples=0
    G.update(t,st,setting,function() samples=samples+1;return u32 end)
    print(G.active_stations(t,st),G.zone(t,x+256,y+256),t.growth_rate,t.grow_counter,
      t.growing and 1 or 0,samples,unpack(t.radii))
  elseif a[1]==2 then
    local _,n,layout,roads,x,z,year,unique,blocked=unpack(a)
    local t=G.new(0,256,256,{num_houses=n,layout=({"original","better","grid2","grid3"})[layout+1]})
    t.unique={church=unique%2==1,stadium=math.floor(unique/2)%2==1}
    t.house_counts={[blocked]=65535}
    x,z=x+256,z+256
    local function kind(u,v)
      local dx,dz=u-x,v-z
      return math.abs(dx)<=1 and math.abs(dz)<=1 and a[10+(dz+1)*3+dx+1] or 1
    end
    local brd={tile=function(u,v)
      local id=kind(u,v)
      return {kind=id==1 and "water" or "clear",max_z=(id==2 or id==4) and 8 or 0,
        slope=id==3 and 17 or id==4 and 3 or 0,bridge_above=id==5}
    end,house_roadtypes=function(u,v)return kind(u,v)~=6 end}
    local samples=0
    local q=B.house(t,brd,x,z,{year=year,allow_roads=roads==1},function()
      samples=samples+1;return assert(a[19+samples]) end)
    if q then print(q.id,q.x-256,q.z-256,q.random_bits,samples)
    else print(-1,-1,-1,-1,samples) end
  elseif a[1]==3 then
    local h=catalog[a[2]]
    if h then print(unpack({h[1],h[2],h[3],h[4],h[5],h[6],h[7],({church=1,stadium=2})[h[8]] or 0,h[9]}))
    else print(-1) end
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
rng=random.Random(141)
rows=[]
edges=[0,1,4,49,50,51,89,91,92,93,95,96,999]
for _ in range(12000):
    n=rng.choice(edges+[rng.randrange(1000)])
    fund=rng.choice([0]*4+[1,2,3])
    setting=rng.randrange(5)
    old=rng.choice([0,69,1420,52000,65535,rng.randrange(65535)])
    counter=rng.randrange(old+1)
    c=rng.randrange(8)
    row=[0,n,rng.randrange(100000),fund,rng.randrange(2),rng.randrange(2),
         old,counter,setting,rng.randrange(2**32),c,rng.randrange(-15,16),rng.randrange(-15,16)]
    for i in range(4):
        row.extend([rng.choice([0,0,0,20,40]),rng.randrange(65)])
    for i in range(c):
        row.extend([rng.randrange(-20,21),rng.randrange(-20,21),
                    rng.choice([0,19,20,21,255]),rng.choice([0,19,20,21,255])])
    rows.append(row)
for _ in range(6500):
    rows.append([1,rng.randrange(2),rng.choice([0,1,69,70,71,400]),
                 rng.randrange(300),rng.randrange(300),rng.randrange(2),rng.randrange(350)])
for house in range(110):
    rows.append([3,house])
for _ in range(7000):
    u32=[rng.randrange(2**32) for _ in range(33)]
    board=[rng.choice([0]*12+[1,2,3,4,5,6]) for _ in range(9)]
    rows.append([2,rng.randrange(1,150),rng.randrange(4),rng.randrange(2),
                 rng.randrange(-8,9),rng.randrange(-8,9),rng.randrange(1900,2050),
                 rng.randrange(4),rng.choice([-1]*3+[rng.randrange(41)]),
                 *board,len(u32),*u32])
with tempfile.TemporaryDirectory(prefix="town-growth-upstream-") as work:
    d=Path(work)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run(["c++","-std=c++17","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
    ref=subprocess.check_output([d/"ref"],text=True,input=data).splitlines()
    lua=subprocess.check_output([exe,d/"test.lua"],text=True,input=data,cwd=root).splitlines()
    assert len(ref)==len(lua)==len(rows)
    for i,(a,b) in enumerate(zip(ref,lua)):
        assert list(map(int,a.split()))==list(map(int,b.split())),(i,rows[i],a,b)
print(f"PASS {len(rows)} pinned source radius/station gate/growth timer/house catalog and selector cases")
