#!/usr/bin/env python3
"""Compile actual pinned 14.1 world-town placement, C++ shim against Lua.

Usage: python3 tests/town_worldgen_upstream.py /path/to/OpenTTD [lua5.1]
The C++ fixture supplies a terrain board, fake name catalog, and a deliberately
controlled GrowTown result; genuine gameplay art/terrain is covered separately.
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

repo=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"


def read(name,checksum):
    candidates=(source/"src"/name,source/name,source/Path(name).name)
    path=next(f for f in candidates if f.is_file())
    data=path.read_bytes()
    assert sha256(data).hexdigest()==checksum,f"{path} isn't OpenTTD 14.1"
    return data.decode()


def block(src,pattern):
    start=re.search(pattern,src,re.M).start()
    end=src.index("{",start)
    n=1
    while n:
        end+=1
        n+=(src[end]=="{")-(src[end]=="}")
    return src[start:end+1]


town=read("town_cmd.cpp","2fb473e5f77d374974348f12a9d9082dcf614de6983b886a91ef1b389f002a48")
maps=read("map.cpp","386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378")
maps_h=read("map_func.h","ea19473db84bf9e3c19c01b04ae732b123215a977b7d3961bbdbb8df3b7f9885")
random_h=read("core/random_func.hpp","b96b21eb2dd1d038e43971fffd2011feda93d669896aaa7f2aaa5369963b55ef")
random_src=read("core/random_func.cpp","6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
tile_h=read("tile_map.h","6fc763d92b4c66f20dd9fce6935492a815305ba150df5d1d1fbb11af884cb5b3")
town_h=read("town.h","463e216ab5f8e0fe791b61865edab029cf9788feafe3b785eaaaaff4e3150b04")
cpp=r'''
#include <algorithm>
#include <bit>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <set>
#include <string>
#include <vector>
using uint=unsigned; using byte=uint8_t; using TileIndex=uint32_t;
using TownNames=std::set<std::string>;
enum TownLayout {TL_ORIGINAL=0,TL_BETTER_ROADS,TL_2X2_GRID,TL_3X3_GRID,TL_RANDOM,NUM_TLS};
enum TownSize {TSZ_SMALL,TSZ_MEDIUM,TSZ_LARGE,TSZ_RANDOM};
enum {MP_CLEAR,MP_TREES,MP_WATER,MP_HOUSE,MP_VOID,GM_NORMAL,GM_EDITOR,
      EXPENSES_OTHER,STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP_SUB,STR_ERROR_TOO_CLOSE_TO_ANOTHER_TOWN,
      STR_ERROR_SITE_UNSUITABLE,GWP_TOWN,STR_ERROR_COULD_NOT_CREATE_TOWN,INVALID_STRING_ID,WL_CRITICAL,
      OWNER_TOWN,DC_EXEC,CMD_DELETE_TOWN};
using CompanyID=int;
CompanyID _current_company=0;
template<class T> struct Backup {
    T &ref,old;
    Backup(T &p,T next,const char*): ref(p),old(p){ref=next;}
    void Restore(){ref=old;}
};
#define FILE_LINE "test"

int _game_mode=GM_NORMAL,world_type=0;
bool _generating_world=true;
struct Settings{
    struct { bool freeform_edges=true; } construction;
    struct { uint number_towns=2; } difficulty;
    struct { uint custom_town_number=4; } game_creation;
    struct { uint larger_towns=4,initial_city_size=2; } economy;
} _settings_game;
struct Randomizer{
    uint32_t state[2];
    uint32_t Next();
    void SetSeed(uint32_t);
} _random;
uint32_t Random(){return _random.Next();}
uint CeilDiv(uint n,uint d){return (n+d-1)/d;}
'''
cpp+=block(random_src,r"^uint32_t Randomizer::Next\(\)")+"\n"
cpp+=block(random_src,r"^void Randomizer::SetSeed") +"\n"
cpp+=block(random_h,r"^inline bool Chance16I")+"\n"
cpp+=block(random_h,r"^inline bool Chance16\(")+"\n"
cpp+=r'''
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
cpp+=block(maps_h,r"^\s*static inline uint ScaleBySize\(")+"\n};\n"
cpp+=r'''
const TileIndex INVALID_TILE=-1;
TileIndex TileXY(uint x,uint z){return x+z*Map::sx;}
uint TileX(TileIndex t){return t%Map::sx;}
uint TileY(TileIndex t){return t/Map::sx;}
bool IsInsideMM(int x,int a,int b){return x>=a&&x<b;}
enum DiagDirection {DIAGDIR_BEGIN=0,DIAGDIR_NE=0,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END};
enum Direction {DIR_N=0,DIR_W=6};
DiagDirection operator++(DiagDirection &d,int){auto old=d;d=DiagDirection(int(d)+1);return old;}
struct TileIndexDiffC{int x,y;};
'''
for symbol in ("_tileoffs_by_diagdir","_tileoffs_by_dir"):
    cpp+=block(maps,rf"^extern const TileIndexDiffC {symbol}")+";\n"
cpp+=r'''
TileIndex TileAddByDir(TileIndex t,Direction d){
    return Map::WrapToMap(t+_tileoffs_by_dir[d].x+_tileoffs_by_dir[d].y*Map::sx);
}
uint Delta(uint a,uint b){return a>b?a-b:b-a;}
'''
cpp+=block(maps,r"^uint DistanceManhattan\(")+"\n"
cpp+=block(maps,r"^uint DistanceFromEdge\(")+"\n"
cpp+=block(maps_h,r"^inline TileIndex RandomTileSeed")+"\n#define RandomTile() RandomTileSeed(Random())\n"
cpp+=block(tile_h,r"^inline uint TileHash\(")+"\n"
cpp+=r'''
int ground(TileIndex t){
    auto x=TileX(t),z=TileY(t);
    if(x==Map::MaxX()||z==Map::MaxY()||(_settings_game.construction.freeform_edges&&(x==0||z==0)))return MP_VOID;
    if(world_type==3)return x==24&&z==24?MP_CLEAR:MP_WATER;
    if(world_type==4)return MP_WATER;
    if(world_type==1)return x<=19?MP_WATER:MP_CLEAR;
    if(world_type==2&&(x<15||z<11||(x>22&&x<30&&z>22)))return MP_WATER;
    return (x+z)%11==0?MP_TREES:MP_CLEAR;
}
bool IsTileType(TileIndex t,int k){return ground(t)==k;}
bool IsTileFlat(TileIndex t){
    return world_type==1?TileY(t)!=26 : world_type==3||((TileX(t)*3+TileY(t)*7)%19)!=0;
}
bool HasTileWaterGround(TileIndex t){return ground(t)==MP_WATER;}
using TestTileOnSearchProc=bool(*)(TileIndex,void*);
bool CircularTileSearch(TileIndex*,uint,uint,uint,TestTileOnSearchProc,void*);
'''
cpp+=block(maps,r"^bool CircularTileSearch\(TileIndex \*tile, uint size,")+"\n"
cpp+=block(maps,r"^bool CircularTileSearch\(TileIndex \*tile, uint radius,")+"\n"
cpp+=block(maps,r"^uint GetClosestWaterDistance\(")+"\n"
cpp+=r'''
struct CommandCost {
    int code;
    explicit CommandCost(int c):code(c){}
    bool Failed() const{return code!=EXPENSES_OTHER;}
    bool Succeeded() const{return !Failed();}
};
#define return_cmd_error(e) return CommandCost(e)
struct TownPool{static constexpr uint MAX_SIZE=64000;};
struct Town {
    static std::vector<Town*> world;
    TileIndex xy;
    uint32_t nameparts=0;
    int index;
    TownLayout layout;
    bool is_city=false;
    uint cycles=0,first_mass=0;
    struct {uint num_houses=0,population=0;} cache;
    explicit Town(TileIndex p):xy(p),index(world.size()){world.push_back(this);}
    static bool CanAllocateItem(){return world.size()<TownPool::MAX_SIZE;}
    static uint GetNumItems(){return world.size();}
    static auto &Iterate(){ return world; }
    static Town* Get(int index){return world[index];}
    std::string GetCachedName() const{return std::to_string(nameparts%19);}
    void InitializeLayout(TownLayout);
};
std::vector<Town*> Town::world;
struct KDTree {
    uint Count(){return Town::world.size();}
    int FindNearest(uint x,uint z){
        int got=0;uint best=-1;
        for(auto t:Town::world){
            uint d=DistanceManhattan(TileXY(x,z),t->xy);
            if(d<best){best=d;got=t->index;}
        }
        return got;
    }
} _town_kdtree;
template<int CMD> struct Command {
    static CommandCost Do(int,int index){
        assert(index+1==int(Town::world.size()));
        delete Town::world.back();Town::world.pop_back();return CommandCost(EXPENSES_OTHER);
    }
};
uint zero_growth=0,create_calls=0,name_calls=0,index_calls=0,progress=0;
void SetGeneratingWorldProgress(int,uint n){progress=n;}
void IncreaseGeneratingWorldProgress(int){}
void RebuildTownKdtree(){++index_calls;}
void ShowErrorMessage(int,int,int){}
bool GenerateTownName(Randomizer &r,uint32_t *parts,TownNames *used=nullptr){
    ++name_calls;
    TownNames existing;
    if(!used){ for(auto t:Town::world)existing.insert(t->GetCachedName());used=&existing;}
    for(int i=0;i<1000;++i){
        uint32_t q=r.Next();
        if(used->insert(std::to_string(q%19)).second){*parts=q;return true;}
    }
    return false;
}
void UpdateTownRadius(Town*){}
void GrowTown(Town *t){
    uint32_t r=Random();
    if(t->cycles++==0){
        t->first_mass=t->cache.num_houses;
        if((r%5)!=0&&world_type!=5)t->cache.population=r%250+1;
    }
}
'''
cpp+=block(town,r"^void Town::InitializeLayout")+"\n"
cpp+=block(town,r"^static bool IsCloseToTown\(")+"\n"
cpp+=block(town,r"^static CommandCost TownCanBePlacedHere")+"\n"
for fn,pattern in (
        ("AlignTileToGrid","static TileIndex"),("IsTileAlignedToGrid","static bool"),
        ("FindFurthestFromWater","static bool"),("FindNearestEmptyLand","static bool"),
        ("FindNearestGoodCoastalTownSpot","static TileIndex")):
    if fn=="FindFurthestFromWater":
        cpp+=block(town,r"^struct SpotData")+";\n"
    cpp+=block(town,rf"^{pattern} {fn}\(")+"\n"
cpp+=r'''
static void DoCreateTown(Town *t, TileIndex tile, uint32_t townnameparts, TownSize size, bool city, TownLayout layout, bool manual){
    t->nameparts=townnameparts;
    t->InitializeLayout(layout);
    t->is_city=city;
    ++create_calls;
'''
body=block(town,r"^static void DoCreateTown\(Town \*t")
cpp+=body[body.index("int x = (int)size"):body.index("UpdateTownGrowthRate(t);")]
cpp+=r'''
    if(!t->cache.population)++zero_growth;
}
'''
cpp+=block(town,r"^static Town \*CreateRandomTown\(uint attempts[^;]+\)\s*\n\{")+"\n"
cpp+=re.search(r"^static const byte _num_initial_towns[^\n]+",town,re.M)[0]+"\n"
cpp+=re.search(r"^static const uint CUSTOM_TOWN_NUMBER_DIFFICULTY[^\n]+",town_h,re.M)[0]+"\n"
cpp+=block(town,r"^bool GenerateTowns\(")+"\n"
cpp+=r'''
const int TOWN_HOUSE_COMPLETED=3;
#define GB(a,b,c) (((a)>>(b))&((1u<<(c))-1u))
void ChangePopulation(Town *t,int n){t->cache.population+=n;}
struct Spec { int population=20; };
void house_seed(){
    Spec spec;auto hs=&spec; Town tmp(0);Town *t=&tmp;
'''
cpp+=town[town.index("\t\tbyte construction_counter = 0;",town.index("byte random_bits = Random()")):
          town.index("\n\t\tMakeTownHouse(tile, t, construction_counter",town.index("byte random_bits = Random()"))]
cpp+=r'''
    std::cout<<"H "<<unsigned(construction_stage)<<' '<<unsigned(construction_counter)<<' '<<t->cache.population<<' '
             <<_random.state[0]<<' '<<_random.state[1]<<'\n';
    Town::world.pop_back();
}
int main(){
    char kind;
    while (std::cin>>kind) {
        if(kind=='H'){
            uint seed;std::cin>>seed;_random.SetSeed(seed);house_seed();continue;
        }
        if(kind=='C'){
            int x,z,ll,f;std::cin>>world_type>>Map::sx>>Map::sy>>f>>x>>z>>ll;
            _settings_game.construction.freeform_edges=f;
            auto k=FindNearestGoodCoastalTownSpot(TileXY(x,z),TownLayout(ll));
            std::cout<<"C "<<(k==INVALID_TILE?-1:int(TileX(k)))<<' '<<(k==INVALID_TILE?-1:int(TileY(k)))<<' '
                     <<GetClosestWaterDistance(TileXY(x,z),true)<<'\n';
            continue;
        }
        uint seed;int l,editor,existing;
        auto &s=_settings_game;
        std::cin>>seed>>world_type>>Map::sx>>Map::sy>>s.difficulty.number_towns>>s.game_creation.custom_town_number
            >>s.economy.larger_towns>>s.economy.initial_city_size>>l>>editor>>existing;
        _game_mode=editor?GM_EDITOR:GM_NORMAL;
        s.construction.freeform_edges=true;
        if(existing){auto t=new Town(TileXY(13,13));t->nameparts=2;}
        _random.SetSeed(seed);zero_growth=create_calls=name_calls=index_calls=progress=0;
        bool ok=GenerateTowns(TownLayout(l));
        std::cout<<"G "<<ok<<' '<<progress<<' '<<zero_growth<<' '<<name_calls<<' '<<index_calls<<' '
                 <<_random.state[0]<<' '<<_random.state[1];
        for(auto t:Town::world){
            if(t->cache.population>0) std::cout<<" : "<<TileX(t->xy)<<' '<<TileY(t->xy)<<' '
               <<t->layout<<' '<<t->is_city<<' '<<t->nameparts<<' '<<t->first_mass<<' '<<t->cache.population;
            delete t;
        }
        Town::world.clear();std::cout<<'\n';
    }
}
'''

runner=r'''
local mod="mods/bayline/openttd/"
local function load(n)return dofile(mod..n..".lua")end
local G=load("town_growth")
local W=load("town_worldgen")(G,nil)
local Ori=load("original_terrain")(load("slope"))
local idx={original=0,better=1,grid2=2,grid3=3,random=4}
local function map(type_,w,h,free)
  return { width=w,height=h,freeform=free,tile=function(x,z)
    local kind="clear"
    if x==w-1 or z==h-1 or free and (x==0 or z==0) then kind="void"
    elseif type_==3 then kind=x==24 and z==24 and "clear" or "water"
    elseif type_==4 then kind="water"
    elseif type_==1 then kind=x<=19 and "water" or "clear"
    elseif type_==2 and (x<15 or z<11 or x>22 and x<30 and z>22) then kind="water"
    elseif (x+z)%11==0 then kind="trees" end
    return {kind=kind,slope=((type_==1 and z~=26) or (type_~=1 and (type_==3 or (x*3+z*7)%19~=0))) and 0 or 1}
  end}
end
for line in io.lines() do
    local kind=line:sub(1,1)
    local v={}
    for n in line:gmatch("%d+") do v[#v+1]=tonumber(n) end
    if kind=="H" then
      local seed={v[1],v[1]}
      local p={root_population=20,parts={{}}}
      local pop=W.house_stage(p,function()return Ori.next_random(seed)end)
      print(("H %d %d %d %d %d"):format(p.stage,p.counter,pop,seed[1],seed[2]))
    elseif kind=="C" then
      local board=map(v[1],v[2],v[3],v[4]==1)
      local x,z=W.coast(board,v[5],v[6],v[7])
      print(("C %d %d %d"):format(x or -1,z or -1,W.water_distance(board,v[5],v[6])))
    else
      local seed={v[1],v[1]}
      local random=function()return Ori.next_random(seed)end
      local board=map(v[2],v[3],v[4],true)
      if v[11]==1 then board.towns={{x=13,z=13,name="2"}} end
      local opts={difficulty=v[5],custom_count=v[6],larger_towns=v[7],layout=v[9],editor=v[10]==1,random=random}
      local nc,ic=0,0
      function opts.rebuild_index()ic=ic+1 end
      function opts.name(used,rand)
        nc=nc+1
        for _=1,1000 do
          local r=rand();local name=tostring(r%19)
          if not used[name] then return r,name end
        end
      end
      function opts.create(c,r)
        local mass=W.initial_mass(c.size,c.city,v[8],false,opts.editor,r)
        local pop=0
        for i=1,mass*4 do
          local n=r()
          if i==1 and n%5~=0 and v[2]~=5 then pop=n%250+1 end
        end
        return {x=c.x,z=c.z,layout=c.layout,city=c.city,parts=c.nameparts,mass=mass,population=pop}
      end
      local r=W.generate(board,opts)
      local out=("G %d %d %d %d %d %d %d"):format(r.success and 1 or 0,r.target,r.failed_growth,nc,ic,seed[1],seed[2])
      for _,t in ipairs(r.towns) do
        out=out..(" : %d %d %d %d %d %d %d"):format(t.x,t.z,idx[t.layout],t.city and 1 or 0,t.parts,t.mass,t.population)
      end
      print(out)
    end
end
'''

cases=[]
for i in range(64):
    cases.append(f"H {(223456789*i)%4294967296}")
for layout in range(5):
    for mode in (1,2,3,4):
        for a,b in ((16,21),(31,45),(62,40),(0,0),(42,20)):
            cases.append(f"C {mode} 64 64 1 {a} {b} {layout}")
for i in range(30):
    layout,editor=i%5,i%13==6
    cases.append(f"G {1751+i*191} {i%3} {128 if i%4!=0 else 64} 64 {i%5} {i%6+1} {i%5} {i%3+1} {layout} {int(editor)} {i%2}")
cases += ["G 1751 3 64 64 4 1 0 2 0 0 0","G 9911 4 64 64 4 1 4 2 0 1 0",
          "G 45919 1 64 64 4 20 4 2 3 0 0"]
test_data="\n".join(cases)+"\n"
with tempfile.TemporaryDirectory(prefix="town-worldgen-14.1-") as d:
    directory=Path(d)
    (directory/"oracle.cpp").write_text(cpp)
    (directory/"runner.lua").write_text(runner)
    subprocess.run(["g++","-std=c++20","-O2",str(directory/"oracle.cpp"),"-o",str(directory/"oracle")],check=True)
    def run(argv):
        return subprocess.run(argv,input=test_data,text=True,stdout=subprocess.PIPE,check=True,cwd=repo).stdout.splitlines()
    reference=run([str(directory/"oracle")])
    got=run([lua,str(directory/"runner.lua")])
    assert len(got)==len(reference)==len(cases)
    for test,a,b in zip(cases,reference,got):
        assert a==b,(test,a,b)
print(f"STOCK_TOWN_WORLDGEN_ORACLE_PASS: {len(cases)} pinned compiled cases; exact coast ranking, accepted/rejected towns, target counts, draw order and house stages.")
