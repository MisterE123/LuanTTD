#!/usr/bin/env python3
"""Compile the pinned stock industry's schedule and initial placement paths.

Usage: python3 tests/industry_worldgen_upstream.py /path/to/OpenTTD [lua5.1]
The C++ host shim deliberately restricts runtime art to stock layout 0
and disables actual leveling, as does the native Lua adapter.
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def read(name,sha):
    p=next(p for p in (source/"src"/name,source/name,source/Path(name).name) if p.is_file())
    b=p.read_bytes()
    assert sha256(b).hexdigest()==sha,f"{p} is not OpenTTD 14.1"
    return b.decode()


def chunk(src,pattern):
    start=re.search(pattern,src,re.M).start()
    end=src.index("{",start);depth=1
    while depth:
        end+=1;depth+=(src[end]=="{")-(src[end]=="}")
    return src[start:end+1]


ind=read("industry_cmd.cpp","0dfb1a169c42754a771093059948c51a62cd1ea378b42663ba8e9a9697f1a914")
tab=read("table/build_industry.h","4e13ea7b25aeba2c349801c8808f9802e200e7ade79bb624bd78f4e618e237db")
maps=read("map.cpp","386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378")
maps_h=read("map_func.h","ea19473db84bf9e3c19c01b04ae732b123215a977b7d3961bbdbb8df3b7f9885")
rnd_cpp=read("core/random_func.cpp","6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
spec_h=read("industry_type.h","c6ea36d87c02d32f8c7ad20d35883901c9438512b491350fc0192dbd9280b4fa")
pool_h=read("industry.h","a6ca3fbb9228f2f7fc85bc8bf785ecc133ede21bdeeb7c98d98ba57f71bb0f0c")
max_pool=int(re.search(r"typedef Pool<Industry, IndustryID, 64, (\d+)>",pool_h)[1])
# Read exact vanilla spec rows used by these four stock IDs. Check them
# against explicit independently expected climate weights, conflicts and
# initial rates before building the minimal source scheduler host.
names={name:int(value) for name,value in re.findall(r"^\s*IT_(\w+)\s*=\s*(\d+),",tab,re.M)}
names["INVALID"]=-1
catalog=[]
for key,weight,rate,conflicts,check,count in (
    ("coal_mine",8,15,(1,-1,-1),"CHECK_NOTHING",4),
    ("power_station",5,0,(0,-1,-1),"CHECK_NOTHING",3),
    ("sawmill",5,0,(3,-1,-1),"CHECK_NOTHING",2),
    ("forest",5,13,(2,14,-1),"CHECK_FOREST",2),
):
    row=re.search(rf"MI\(_tile_table_{key}\s*,[^\n]+\n\s*([^\n]+)\n\s*([^\n]+)\n\s*([^\n]+)",tab)
    first,second,third=([v.strip() for v in row[i].split(",")] for i in range(1,4))
    assert int(first[6])==weight and int(third[1])==rate
    assert tuple(names[v.removeprefix("IT_")] for v in second[:3])==conflicts and second[3]==check
    assert names[key.upper()]==len(catalog)
    catalog.append((key,weight,rate,conflicts,check,count))

cpp=r'''
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <climits>
#include <iostream>
#include <tuple>
#include <vector>
using uint=unsigned;using byte=uint8_t;using TileIndex=uint;using IndustryType=uint;
using IndustryAvailabilityCallType=int;using CompanyID=int;using Owner=int;using DoCommandFlag=int;
enum {ID_FUND_ONLY,ID_MINIMAL,ID_VERY_LOW,ID_LOW,ID_NORMAL,ID_HIGH,ID_CUSTOM,ID_END};
enum {GM_NORMAL,GM_EDITOR,MP_CLEAR,MP_TREES,MP_WATER,MP_HOUSE,MP_VOID,MP_INDUSTRY,
    CHECK_NOTHING,CHECK_REFINERY,CHECK_OIL_RIG,CHECK_FOREST,LT_ARCTIC=90,IACT_MAPGENERATION,OWNER_NONE,OWNER_TOWN,DC_EXEC=1,
    DC_NO_WATER=2,STR_ERROR_ONLY_ONE_ALLOWED_PER_TOWN=30,STR_ERROR_INDUSTRY_TOO_CLOSE,STR_ERROR_FOREST_CAN_ONLY_BE_PLANTED,SLOPE_N,
    CMD_TERRAFORM_LAND,GWP_INDUSTRY,INDUSTRYBEH_NOBUILT_MAPCREATION=1,GFX_WATERTILE_SPECIALCHECK=255};
#define FILE_LINE "reference"
#define GB(a,b,c) (((a)>>(b))&((1u<<(c))-1))
template<class T,size_t N> constexpr size_t lengthof(const T(&)[N]){return N;}
uint CeilDiv(uint n,uint d){return (n+d-1)/d;}
uint Delta(uint a,uint b){return (a>=b)?a-b:b-a;}
struct Settings {
    struct { bool freeform_edges=true; uint industry_platform=1; } construction;
    struct { uint industry_density=4; } difficulty;
    struct { uint custom_industry_number=5,landscape=0; } game_creation;
    struct { bool multiple_industry_per_town=false; } economy;
} _settings_game;
struct Randomizer {uint32_t state[2]; uint32_t Next(); void SetSeed(uint32_t); } _random;
uint32_t Random(){return _random.Next();}
uint32_t RandomRange(uint32_t n){return (uint64_t(Random())*n)>>32;}
struct Map {
    static inline uint sx=64,sy=64;
    static uint SizeX(){return sx;}
    static uint SizeY(){return sy;}
    static uint MaxX(){return sx-1;}
    static uint MaxY(){return sy-1;}
    static uint Size(){return sx*sy;}
    static uint LogX(){return std::countr_zero(sx);}
    static uint LogY(){return std::countr_zero(sy);}
    static TileIndex WrapToMap(TileIndex x){return x&(Size()-1);}
'''
for key in ("ScaleBySize","ScaleBySize1D"):
    cpp+=chunk(maps_h,rf"^\s*static inline uint {key}\(")+"\n"
cpp+="};\n"
for key in ("Next","SetSeed"):
    cpp+=chunk(rnd_cpp,rf"^\w+ Randomizer::{key}\(")+"\n"
cpp+=r'''
const TileIndex INVALID_TILE=-1;
TileIndex TileXY(uint x,uint z){return x+z*Map::sx;}
uint TileX(TileIndex t){return t%Map::sx;}
uint TileY(TileIndex t){return t/Map::sx;}
int TileDiffXY(int x,int z){return x+z*int(Map::sx);}
int _game_mode=GM_NORMAL,mode=0,type_mask=3;
bool smooth=false;
uint target=0,attempts=0,reset_count=0;
using LayoutPair=std::pair<IndustryType,bool>;
std::vector<LayoutPair> schedule;
struct CommandCost {
    int c=0; CommandCost(int s=0):c(s){}
    bool Failed()const{return c!=0;}
};
#define return_cmd_error(e) return CommandCost(e)
int _current_company=0;
template<typename T> struct Backup {
    T &var,old; Backup(T &v,T n,const char*):var(v),old(v){var=n;} void Restore(){var=old;}
};
struct TileArea {
    TileIndex tile;uint w,h;
    TileArea(TileIndex t,uint w,uint h):tile(t),w(w),h(h){}
    TileArea Expand(uint d)const{
        assert(false&&"Large-map optimization deliberately outside small-map fixtures");
        return *this;
    }
    struct Iter {
        TileIndex first;uint w,i;
        TileIndex operator*()const{return first+(i%w)+(i/w)*Map::sx;}
        bool operator!=(const Iter &o)const{return i!=o.i;}
        Iter& operator++(){++i;return *this;}
    };
    Iter begin()const{return {tile,w,0};}
    Iter end()const{return {tile,w,w*h};}
};
struct Offset{int x,y;};
struct IndustryTileLayoutTile{Offset ti;int gfx;};
using IndustryTileLayout=std::vector<IndustryTileLayoutTile>;
#define MK(x,y,gfx) {{x,y},gfx}
'''
for key,*_,count in catalog:
    for i in range(count):
        cpp+=chunk(tab,rf"^static const IndustryTileLayout _tile_table_{key}_{i}\s*\{{")+";\n"
cpp+=f"struct IndustryPool {{static constexpr uint MAX_SIZE={max_pool};}};\n"
for line in re.findall(r"^static const IndustryType NUM_INDUSTRYTYPES\s+.*",spec_h,re.M):
    cpp+=line+"\n"
cpp+=r'''
struct IndustrySpec {
    bool enabled; std::vector<IndustryTileLayout> layouts;
    int appear_creation[1],check_proc,behaviour,conflicting[3],rate;
};
IndustrySpec specs[5]={
'''
for key,weight,rate,conflict,check,count in catalog:
    layouts=",".join(f"_tile_table_{key}_{i}" for i in range(count))
    ids=",".join(map(str,conflict))
    cpp+=f"{{true,{{{layouts}}},{{{weight}}},{check},0,{{{ids}}},{rate}}},\n"
cpp+=r'''
  {false,{}, {0},CHECK_NOTHING,0,{-1,-1,-1},0}
};
const IndustrySpec* GetIndustrySpec(int t){return &specs[t<4?t:4];}
uint GetIndustryProbabilityCallback(uint,int,uint p){return p;}
struct Town {uint x,z,id;};
std::vector<Town> towns={{18,13,1},{38,26,2},{22,47,3}};
struct Industry {
    TileArea location;Town *town=nullptr;uint type=0,layout=0,seed=0,bits=0,colour=0,counter=0,prod=0;
    struct Cargo{int rate=0;};
    std::array<Cargo,16> produced;
    std::vector<uint> randoms;
    Industry(TileIndex t):location(t,1,1){}
    static std::vector<Industry*> entries;
    static uint GetNumItems(){return entries.size();}
    static Industry* GetByTile(TileIndex){return nullptr;}
    static auto &Iterate(){return entries;}
};
std::vector<Industry*> Industry::entries;
std::vector<bool> occupied;
Town* ClosestTownFromTile(TileIndex tile,uint){
    Town *best=nullptr;uint value=-1;
    for(auto& a:towns){
        uint d=Delta(TileX(tile),a.x)+Delta(TileY(tile),a.z);
        if(d<value||(d==value&&a.id<best->id)){value=d;best=&a;}
    }
    return best;
}
int GetTileType(TileIndex t){
    auto x=TileX(t),z=TileY(t);
    if(x>=Map::MaxX()||z>=Map::MaxY()||(_settings_game.construction.freeform_edges&&(x==0||z==0))) return MP_VOID;
    if(occupied[t])return MP_INDUSTRY;
    if(mode==2)return MP_WATER;
    if(mode==1 && (x<9 || z<7 || (x>26&&x<33&&z<25)))return MP_WATER;
    if((x*x+z*7)%73==0)return MP_HOUSE;
    return (x+z)%11==0?MP_TREES:MP_CLEAR;
}
uint TileHeight(TileIndex t){
    auto x=TileX(t),z=TileY(t);
    return mode==3?0:mode==1&&(x>=24&&x<=39&&z>=29&&z<=47)?2:1;
}
bool flat_cell(TileIndex t){
    auto h=TileHeight(t);
    return TileHeight(t+1)==h&&TileHeight(t+Map::sx)==h&&TileHeight(t+Map::sx+1)==h;
}
uint GetTileZ(TileIndex t){
  return std::min({TileHeight(t),TileHeight(t+1),TileHeight(t+Map::sx),TileHeight(t+Map::sx+1)});
}
uint HighestSnowLine(){return 1;}
template<int ID> struct Command {
    static auto Do(DoCommandFlag,TileIndex,int,bool){return std::tuple{CommandCost(1),0};}
};
'''
for key,src,pattern in (
    ("wrap",maps,r"^TileIndex TileAddWrap"),("dist",maps,r"^uint DistanceMax\("),
    ("rnd",maps_h,r"^inline TileIndex RandomTileSeed"),
    ("near",ind,r"^static CommandCost CheckIfFarEnoughFromConflictingIndustry"),
    ("town",ind,r"^static CommandCost FindTownForIndustry"),
    ("forest",ind,r"^static CommandCost CheckNewIndustry_Forest"),
    ("surround",ind,r"^static bool CheckCanTerraformSurroundingTiles"),
    ("platform",ind,r"^static bool CheckIfCanLevelIndustryPlatform")):
    cpp+=chunk(src,pattern)+"\n"
cpp+=r'''
#define RandomTile() RandomTileSeed(Random())
CommandCost CreateNewIndustryHelper(TileIndex t, uint type, int flags, const IndustrySpec *spec,
    size_t layout, uint32_t seed, uint16_t bits, int owner, int how, Industry **out){
    ++attempts;
    const auto &tiles=spec->layouts[layout];
    if(layout!=0||CheckIfFarEnoughFromConflictingIndustry(t,type).Failed())return 1;
    Town *town=nullptr;
    if(FindTownForIndustry(t,type,&town).Failed())return 2;
    if(spec->check_proc==CHECK_FOREST && CheckNewIndustry_Forest(t).Failed())return 5;
    for(auto &part:tiles){
        auto i=TileAddWrap(t,part.ti.x,part.ti.y);
        if(i==INVALID_TILE || (GetTileType(i)!=MP_CLEAR && GetTileType(i)!=MP_TREES) || !flat_cell(i))return 3;
    }
    if(!CheckIfCanLevelIndustryPlatform(t,DC_NO_WATER,tiles))return 4;
    auto i=new Industry(t);i->town=town;i->type=type;i->layout=layout;i->seed=seed;i->bits=bits;
    i->produced[0].rate=spec->rate;
'''
init=chunk(ind,r"^static void DoCreateNewIndustry\(")
cpp+=init[init.index("if (!indspec->UsesOriginalEconomy())"):init.index("i->was_cargo_delivered = false;")].replace(
    "!indspec->UsesOriginalEconomy()","smooth").replace("ClampTo<byte>((RandomRange(256) + 128) * p.rate >> 8)",
    "((RandomRange(256) + 128) * p.rate >> 8)").replace("i->random_colour = static_cast<Colours>(GB(r, 0, 4));","i->colour = GB(r, 0, 4);").replace("i->random = initial_random_bits;","").replace("i->owner = OWNER_NONE;","").replace("i->town = t;","")
cpp+=r'''
    for(const auto &part:tiles){
        auto tile=TileAddWrap(t,part.ti.x,part.ti.y);
        occupied[tile]=true;
        i->randoms.push_back(Random()%256);
    }
    i->prod=i->produced[0].rate;
    Industry::entries.push_back(i);*out=i;return 0;
}
void IncreaseGeneratingWorldProgress(int){}
void SetGeneratingWorldProgress(int,uint n){target=n;}
struct {void Reset(){reset_count=Industry::GetNumItems()*65536;}} _industry_builder;
'''
# Retain the source return/control branches while recording the exact
# selected industry and forced/weighted stage once per attempt group.
for name,type_ in (("CreateNewIndustry",r"Industry \*"),("GetScaledIndustryGenerationProbability","uint32_t "),
                   ("GetNumberOfIndustries","uint "),("PlaceIndustry",r"Industry \*"),
                   ("PlaceInitialIndustry","void ")):
    cpp+=chunk(ind,rf"^static {type_}{name}\(").replace(
        "PlaceIndustry(type, IACT_MAPGENERATION, try_hard);",
        "schedule.push_back({type,try_hard}); PlaceIndustry(type, IACT_MAPGENERATION, try_hard);")+"\n"
cpp+=chunk(ind,r"^void GenerateIndustries\(")+"\n"
cpp+=r'''
int main(){
    uint seed;int extra,multi,editor;
    while(std::cin>>seed>>mode>>Map::sx>>Map::sy>>_settings_game.difficulty.industry_density
     >>_settings_game.game_creation.custom_industry_number>>type_mask>>extra>>multi>>editor
     >>_settings_game.construction.industry_platform){
        _random.SetSeed(seed);
        occupied.assign(Map::Size(),false);schedule.clear();target=attempts=reset_count=0;
        smooth=extra;_game_mode=editor?GM_EDITOR:GM_NORMAL;_settings_game.economy.multiple_industry_per_town=multi;
        for(int id=0;id<4;++id)specs[id].enabled=type_mask&(1<<id);
        GenerateIndustries();
        std::cout<<target<<' '<<attempts<<' '<<reset_count<<' '<<_random.state[0]<<' '<<_random.state[1];
        for(auto p:schedule)std::cout<<" | "<<p.first<<' '<<p.second;
        for(auto i:Industry::entries){
            auto t=i->location.tile;
            std::cout<<" : "<<i->type<<' '<<TileX(t)<<' '<<TileY(t)<<' '<<i->town->id<<' '
                     <<i->seed<<' '<<i->bits<<' '<<i->colour<<' '<<i->counter<<' '<<i->prod;
            for(auto n:i->randoms)std::cout<<' '<<n;
            delete i;
        }
        Industry::entries.clear();std::cout<<'\n';
    }
}
'''
runner=r'''
local m="mods/bayline/openttd/"
local function load(n)return dofile(m..n..".lua")end
local P,Rate,Inc=load("passengers"),load("station_rating"),load("income")
local Coal=load("coal_industry")(P,Rate,load("station_catchment")(P,Rate),Inc)
local Timber=load("timber_industry")(P,load("station_catchment")(P,Rate),Rate,Inc,Coal,load("town_goods"))
local I=load("industry_worldgen")(Coal)
local Mixed=load("industry_worldgen")(Coal,Timber)
local O=load("original_terrain")(load("slope"))
for line in io.lines() do
  local v={}
  for n in line:gmatch("%d+") do v[#v+1]=tonumber(n) end
  local state={v[1],v[1]}
  local mode,w,h=v[2],v[3],v[4]
  local map={}
  local function height(x,z)
      return mode==3 and 0 or mode==1 and x>=24 and x<=39 and z>=29 and z<=47 and 2 or 1
  end
  local board={width=w,height=h,freeform=true,towns={{x=18,z=13,id=1},{x=38,z=26,id=2},{x=22,z=47,id=3}}}
  function board.tile(x,z)
    local kind="clear"
    if x==0 or x>=w-1 or z==0 or z>=h-1 then kind="void"
    elseif map[x+z*w] then kind="industry"
    elseif mode==2 or mode==1 and (x<9 or z<7 or x>26 and x<33 and z<25) then kind="water"
    elseif (x*x+z*7)%73==0 then kind="house"
    elseif (x+z)%11==0 then kind="trees" end
    local hh=height(x,z)
    local flat=(height(x+1,z)==hh and height(x,z+1)==hh and height(x+1,z+1)==hh)
    return {kind=kind,slope=flat and 0 or 1,base=hh,corner_height=hh}
  end
  local original=v[8]==0
  local function c(p)
    for _,tile in ipairs(p.cells) do map[tile.x+tile.z*w]=true end
    return true
  end
  local impl=v[7]>=4 and Mixed or I
  local enabled={}
  for id=0,3 do enabled[id]=math.floor(v[7]/2^id)%2==1 end
  local r=impl.generate(board,{random=function()return O.next_random(state)end,
    commit=c,density=v[5],custom_count=v[6],enabled=enabled,
    original=original,multiple_per_town=v[9]==1,editor=v[10]==1,platform=v[11]})
  local out=("%d %d %d %d %d"):format(r.target,r.attempted,r.wanted_inds or 0,state[1],state[2])
  for _,p in ipairs(r.choices) do out=out..(" | %d %d"):format(p.type,p.forced and 1 or 0) end
  for _,p in ipairs(r.placed) do
    local record=impl.record(p,0,{original=original})
    out=out..(" : %d %d %d %d %d %d %d %d %d"):format(p.type,p.x,p.z,p.town,
        p.seed,p.initial_random,p.random_colour,p.counter,record.produced and record.produced.rate or 0)
    for _,cell in ipairs(p.cells) do out=out.." "..cell.random_bits end
  end
  print(out)
end
'''
cases=[]
for i in range(20):
    cases.append(f"{1751+i*379} {i%2} {64*(1+i%2)} 64 {i%7} {i%5+2} {i%3+1} {i%2} {i%2} {int(i%8==7)} {i%5}")
cases.extend(["8951 2 64 64 1 3 1 0 0 0 1","448922 1 64 64 6 6 0 0 1 0 1",
              "88392 0 64 64 6 9 3 1 1 0 1","99814 0 64 64 4 5 3 0 0 0 1"])
# Keep the original 24 Coal-only cases as exact backward compatibility
# checks. Add all timber combinations, zero/low land, smooth mode with
# nonproducing sawmills, editor/weighted gaps, and both opposite map axes.
cases.extend([
 "1751 3 64 64 6 7 15 0 1 0 1","1751 3 64 64 6 7 15 1 1 0 1",
 "1751 0 64 64 4 5 12 0 0 0 1","89485 1 64 128 6 10 15 1 0 0 1",
 "351 0 128 64 5 8 11 0 0 0 1","27 3 64 64 4 8 4 1 0 0 1",
 "87 3 64 64 4 8 8 0 0 0 1","7968 1 64 128 5 7 10 1 1 1 1",
 "44887 2 64 64 6 1 8 0 1 0 1","18576 0 64 64 0 5 15 1 0 0 1",
 "9312346 1 64 64 1 5 15 0 1 0 1","913 0 64 64 2 5 15 0 1 1 0",
])
test_data="\n".join(cases)+"\n"
with tempfile.TemporaryDirectory(prefix="industry-worldgen-14.1-") as path:
    d=Path(path)
    (d/"oracle.cpp").write_text(cpp)
    (d/"runner.lua").write_text(runner)
    subprocess.run(["g++","-O2","-std=c++20",str(d/"oracle.cpp"),"-o",str(d/"oracle")],check=True)
    def run(argv):
        return subprocess.run(argv,input=test_data,cwd=root,check=True,text=True,stdout=subprocess.PIPE).stdout.splitlines()
    got=run([lua,str(d/"runner.lua")]);ref=run([str(d/"oracle")])
    assert len(got)==len(ref)==len(cases)
    for case,a,b in zip(cases,ref,got):
        assert a==b,(case,a,b)
assert any(" : 2 " in ln for ln in got) and any(" : 3 " in ln for ln in got)
print(f"STOCK_INDUSTRY_ORACLE_PASS: {len(cases)} pinned cases matched exact forced/weighted draws, retries, coordinates and RNG state.")
