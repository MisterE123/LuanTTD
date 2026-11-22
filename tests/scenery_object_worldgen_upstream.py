#!/usr/bin/env python3
"""Compare pinned OpenTTD 14.1 vanilla scenery placement against Lua.

Run: python3 tests/scenery_object_worldgen_upstream.py /path/to/OpenTTD-14.1 [lua5.1]
"""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("lua", nargs="?", default="lua5.1")
args = parser.parse_args()


def pinned(name, digest):
    candidates = [args.source/"src"/name, args.source/name, args.source/Path(name).name]
    path = next((p for p in candidates if p.is_file()), candidates[0])
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == digest, f"{path}: not pinned 14.1"
    return data.decode()


def block(source, pattern):
    p = re.search(pattern, source, re.M).start()
    i = source.index("{", p)
    level = 1
    while level:
        i += 1
        level += (source[i] == "{") - (source[i] == "}")
    return source[p:i+1]


cmd = pinned("object_cmd.cpp", "371dfbe51ccdcc6a9d8239d6d37656a90f41da4e7ff256bebf960242e7aad7ee")
objmap = pinned("object_map.h", "8f48316cbd63977df9f6a0fa1d1e472f93808887ea2ac6c214562ff7fb2e687d")
specs = pinned("table/object_land.h", "97a27ece10414ec8ca12085fde03f3103fbf5e8a5860080bbafd9344b5277f04")
types = pinned("object_type.h", "785337339db53849f66f1dcc69089349aa6d017640217f897c28e9070d2ca1e6")
mm = pinned("map.cpp", "386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378")
mf = pinned("map_func.h", "ea19473db84bf9e3c19c01b04ae732b123215a977b7d3961bbdbb8df3b7f9885")
tilemap = pinned("tile_map.cpp", "479ae6451fa7af6b430e0c98ea6cdefbfbf4d9f2d482ee6c7c4e4054fca93fb3")
newgrf = pinned("newgrf_object.cpp", "a6d091189eb0ec24bae06d39eb8f81b2d217c9b48ff0ba0c44a170d0e73d26cf")
newgrf_h = pinned("newgrf_object.h", "36e703a971b3e9528490ce257abacc3e32472196d4d7f6e2d7db423cfb2daa4e")
rng = pinned("core/random_func.cpp", "6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
gen = pinned("genworld.cpp", "787a30b5efc2a36306a30c678d69f0c13657ef6259957373fe0116d47d4cf920")
kd = pinned("core/kdtree.hpp", "9378733fc918a790d502bfda01d3f0e9c4c2486443bc60e7116b531f153150a6")
assert gen.index("\n\t\t\t\tGenerateIndustries();") < gen.index("\n\t\t\t\tGenerateObjects();") < gen.index("\n\t\t\t\tGenerateTrees();")

cpp = r'''
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>
using uint=unsigned;using byte=uint8_t;using TileIndex=uint32_t;
using ObjectType=uint16_t;using ObjectID=uint32_t;using TownID=uint16_t;
using CompanyID=uint8_t;using Owner=uint8_t;
constexpr TileIndex INVALID_TILE=0xffffffff;
enum {MP_CLEAR=0,MP_WATER=6,MP_VOID=7,MP_OBJECT=10};
enum {GM_NORMAL,GM_EDITOR, LT_TEMPERATE=0, GWP_OBJECT=0};
enum {WATER_CLASS_SEA=0,WATER_CLASS_CANAL=1,WATER_CLASS_INVALID=3};
using WaterClass=uint8_t;
enum {OWNER_NONE=16,OWNER_WATER=17,AXIS_X=0};
enum {CBM_OBJ_COLOUR=0,CBID_OBJECT_COLOUR,CALLBACK_FAILED=0xffff,OAT_BUILT=0};
enum {DC_EXEC=1,DC_AUTO=2,DC_NO_TEST_TOWN_RATING=4,DC_NO_MODIFY_TOWN_RATING=8};
enum DiagDirection {DIAGDIR_BEGIN, DIAGDIR_NE=0,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END};
void operator++(DiagDirection& d,int){d=(DiagDirection)((int)d+1);}
enum Direction{DIR_N,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW};
constexpr int _game_mode=GM_NORMAL;
constexpr bool _generating_world=true;
struct Settings {
 struct { bool freeform_edges; } construction;
 struct { int landscape=LT_TEMPERATE; } game_creation;
} _settings_game;
namespace TimerGameCalendar{uint date;}
namespace CalendarTime{constexpr uint MAX_DATE=5000000;}
template<class T=uint32_t> T GB(uint32_t r,int s,int n){return (r>>s)&((1u<<n)-1);}
bool HasBit(uint n,int bit){return n&(1u<<bit);}
template<class T> void SB(T& v,int s,int n,uint value){
 auto m=((1u<<n)-1)<<s; v=(v&~m)|(value<<s);
}
template<class T> T CeilDiv(T n,int d){return (n+d-1)/d;}
struct Randomizer {uint32_t state[2];uint32_t Next();uint32_t Next(uint32_t);} _random;
uint draws,limit,attempts[2],active;
uint Random(){draws++;return _random.Next();}
uint RandomRange(uint n){draws++;return _random.Next(n);}
struct Map{
 static inline uint w,h,lx,lz;
 static uint LogX(){return lx;} static uint LogY(){return lz;}
 static uint SizeX(){return w;} static uint SizeY(){return h;} static uint Size(){return w*h;}
 static uint MaxX(){return w-1;} static uint MaxY(){return h-1;}
 static TileIndex WrapToMap(TileIndex n){return n&(Size()-1);}
'''
cpp += "\n".join(block(mf,r"^\s*static inline uint ScaleBySize"+suffix+r"\(uint n\)")
                 for suffix in ("","1D")) + "\n};\n"
cpp += "\n".join(block(rng,pat) for pat in (r"^uint32_t Randomizer::Next\(\)",r"^uint32_t Randomizer::Next\(uint32_t")) + "\n"
cpp += block(newgrf_h,r"^enum ObjectFlags")+";\n"
cpp += "\n".join(re.findall(r"^static const ObjectType OBJECT_(?:TRANSMITTER|LIGHTHOUSE)[^;]*;",types,re.M))+"\n"
cpp += r'''
struct Cell{byte kind=0,height=0,bridge=0,owner=OWNER_NONE,water=WATER_CLASS_INVALID;
  byte object=255,m3=0,m4=0,m5=0,m6=0,m7=0;uint16_t m2=0;};
std::vector<Cell> cells;
struct Tile{
 TileIndex i;Tile(TileIndex i):i(i){}
 byte& m3(){return cells.at(i).m3;} byte& m4(){return cells.at(i).m4;}
 byte& m5(){return cells.at(i).m5;} byte& m6(){return cells.at(i).m6;}
 byte& m7(){return cells.at(i).m7;} uint16_t& m2(){return cells.at(i).m2;}
};
uint TileX(TileIndex i){return i%Map::w;}
uint TileY(TileIndex i){return i/Map::w;}
TileIndex TileXY(uint x,uint y){return x+y*Map::w;}
uint TileHeight(TileIndex t){return cells.at(t).height;}
bool IsTileType(TileIndex t,int kind){return cells.at(t).kind==kind;}
bool IsTileType(Tile t,int kind){return IsTileType(t.i,kind);}
bool IsValidTile(TileIndex t){return t<Map::Size()&&!IsTileType(t,MP_VOID);}
bool IsBridgeAbove(TileIndex t){return cells.at(t).bridge;}
bool IsObjectTypeTile(TileIndex t,ObjectType type){return IsTileType(t,MP_OBJECT)&&cells.at(t).object==type;}
bool IsWaterTile(TileIndex t){return IsTileType(t,MP_WATER);}
WaterClass GetWaterClass(TileIndex t){return cells.at(t).water;}
bool IsTileOwner(TileIndex t,Owner owner){return cells.at(t).owner==owner;}
void SetTileType(Tile t,int k){cells.at(t.i).kind=k;}
void SetTileOwner(Tile t,Owner owner){cells.at(t.i).owner=owner;}
void SetWaterClass(Tile t,WaterClass w){cells.at(t.i).water=w;}
bool IsDockingTile(TileIndex){return false;}
void RemoveDockingTile(TileIndex){}
void MarkTileDirtyByTile(TileIndex){}
void DirtyCompanyInfrastructureWindows(Owner){}
struct Livery{byte colour1,colour2;};
struct Company{
 struct{uint water;} infrastructure;Livery *livery;
 static Company *Get(CompanyID){std::abort();}
};
struct Town{TownID id;TileIndex xy;};
std::vector<Town> towns;
Town *CalcClosestTownFromTile(TileIndex i){
 Town* best=nullptr;
 uint limit=std::numeric_limits<uint>::max();
 for(auto& t:towns){
  uint d=std::abs(int(TileX(t.xy))-int(TileX(i)))+std::abs(int(TileY(t.xy))-int(TileY(i)));
  if(d<limit||(d==limit&&t.id<best->id)){limit=d;best=&t;}
 }
 return best;
}
struct TileArea : std::array<TileIndex,1> {
 TileArea(TileIndex i,uint w,uint h):std::array<TileIndex,1>{i}{assert(w==1&&h==1);}
 const TileIndex& tile()const{return at(0);}
 TileArea():std::array<TileIndex,1>{0}{}
};
template<int N>struct GRFFilePropsBase{struct {int grfid;}*grffile=nullptr;};
constexpr int INVALID_OBJECT_CLASS=255;
struct ObjectSpec{
 GRFFilePropsBase<2> grf_prop;
 std::array<int,4> animation;int cls_id,name;
 uint8_t climate,size,build_cost_multiplier,clear_cost_multiplier;
 uint introduction_date,end_of_life_date;
 uint flags;uint16_t callback_mask;uint8_t height,views,generate_amount;
 bool IsEnabled() const {return views>0;}
 bool IsEverAvailable() const;bool WasEverAvailable() const;uint Index()const;
 static size_t Count();
 static const std::vector<ObjectSpec>& Specs();
 static const ObjectSpec* Get(ObjectType type);
};
struct Object {
 ObjectType type;
 TileArea location;
 Town* town;
 uint build_date;
 byte view,colour;
 ObjectID index;
 static bool CanAllocateItem();
 static void IncTypeCount(ObjectType);
};
std::vector<Object*> objects;
bool Object::CanAllocateItem(){return objects.size()<limit;}
void Object::IncTypeCount(ObjectType type){
 Object* o=objects.back();
 assert(o->type==type);
 cells.at(o->location.at(0)).object=type;
}
uint16_t GetObjectCallback(int,byte,int,const ObjectSpec*,Object*,TileIndex){std::abort();}
void ErrorUnknownCallbackResult(int,int,uint16_t){std::abort();}
void TriggerObjectAnimation(Object*,int,const ObjectSpec*){std::abort();}
struct TileIndexDiffC{int x,y;};
using TestTileOnSearchProc=bool(*)(TileIndex,void*);
'''
# These declarations make newer C++ use the same core data and loops as the
# source excerpts; only unrelated service wiring is stubbed.
cpp += "\n".join(block(mm,pat)+";" for pat in (r"^extern const TileIndexDiffC _tileoffs_by_diagdir",r"^extern const TileIndexDiffC _tileoffs_by_dir"))+"\n"
cpp += r'''
int TileOffsByDiagDir(DiagDirection d){return _tileoffs_by_diagdir[d].x+_tileoffs_by_diagdir[d].y*(int)Map::w;}
TileIndex TileAddByDir(TileIndex i,Direction d){return Map::WrapToMap(i+_tileoffs_by_dir[d].x+_tileoffs_by_dir[d].y*(int)Map::w);}
int DiagDirToAxis(DiagDirection d){return d&1;}
bool CircularTileSearch(TileIndex*,uint,uint,uint,TestTileOnSearchProc,void*);
void BuildObject(ObjectType,TileIndex,CompanyID=OWNER_NONE,Town* =nullptr,uint8_t=0);
uint16_t ProgressIndex;
void SetGeneratingWorldProgress(int,uint count){assert(count==5);ProgressIndex=0;}
void IncreaseGeneratingWorldProgress(int){ProgressIndex++;}
struct Result{bool Succeeded()const{std::abort();}};
Result CmdBuildObject(uint,TileIndex,uint,uint8_t){std::abort();} // Only obsolete/custom; these stock specs never call it.
'''
# Use actual default table entries (including HQ's availability exclusion)
# rather than independently writing artificial generator quotas.
spec_lines=specs[specs.index("#define M(name"):specs.index("#undef M",specs.index("#define M(name"))]
# Symbolic display string IDs have no worldgen effect.
for n,k in enumerate(dict.fromkeys(re.findall(r"\bSTR_[A-Z0-9_]+",spec_lines))):
    cpp+=f"constexpr int {k}={n};\n"
# ObjectFlags is an enum bitmask; map the three lines to the original
# aggregate, using format only to compile the original table.
cpp += spec_lines + "\n#undef T\n#undef A\n#undef S\n#undef Y\n#undef M\n"
cpp += r'''
std::vector<ObjectSpec> _object_specs(std::begin(_original_objects),std::end(_original_objects));
size_t ObjectSpec::Count(){return _object_specs.size();}
const std::vector<ObjectSpec>& ObjectSpec::Specs(){return _object_specs;}
const ObjectSpec* ObjectSpec::Get(ObjectType t){return &_object_specs.at(t);}
'''
for src,pat in (
    (mf,r"^inline TileIndex RandomTileSeed"),(tilemap,r"^bool IsTileFlat"),
    (mm,r"^bool CircularTileSearch\(TileIndex \*tile, uint size"),
    (mm,r"^bool CircularTileSearch\(TileIndex \*tile, uint radius"),
    (newgrf,r"^bool ObjectSpec::IsEverAvailable"),(newgrf,r"^bool ObjectSpec::WasEverAvailable"),
    (newgrf,r"^uint ObjectSpec::Index"),(objmap,r"^inline void MakeObject"),
    (objmap,r"^inline byte GetObjectRandomBits")):
    cpp+=block(src,pat)+"\n"
cpp += "#define RandomTile() RandomTileSeed(Random())\n"
# Intercept allocation only to operate gate/counts in the lightweight map
# stand-in. Keep all placement, RNG, color, and tile-bit code unmodified.
cpp += r'''
Object* RecordObject(Object* o){
 o->index=objects.size();objects.push_back(o);return o;
}
'''
build=block(cmd,r"^void BuildObject\(")
assert build.count("new Object()")==1
cpp+=build.replace("new Object()", "RecordObject(new Object())")+"\n"
for pat in (r"^static bool HasTransmitter",r"^static bool TryBuildLightHouse",
            r"^static bool TryBuildTransmitter",r"^void GenerateObjects"):
    cpp+=block(cmd,pat)+"\n"
cpp+=r'''
int main(){
 uint flag,nt;
 while(std::cin>>Map::w>>Map::h>>flag>>TimerGameCalendar::date>>limit>>_random.state[0]>>_random.state[1]>>nt){
   Map::lx=std::countr_zero(Map::w);Map::lz=std::countr_zero(Map::h);
   _settings_game.construction.freeform_edges=flag;
   towns.clear();
   for(uint i=0;i<nt;i++){uint id,x,z;std::cin>>id>>x>>z;towns.push_back({(TownID)id,TileXY(x,z)});}
   assert(std::cin.get()=='\n');
   draws=0;
   cells.assign(Map::Size(),{});
   for(auto& c:cells){
     c.kind=std::cin.get();c.height=std::cin.get();c.bridge=std::cin.get();c.object=std::cin.get();
     assert(std::cin);
   }
   GenerateObjects();
   std::cout<<_random.state[0]<<" "<<_random.state[1]<<" "<<draws<<" "<<objects.size()<<"\n";
   for(auto* o:objects){
     auto i=o->location.at(0);
     assert(cells.at(i).kind==MP_OBJECT && cells.at(i).water==WATER_CLASS_INVALID);
     std::cout.put(i&255);std::cout.put((i>>8)&255);std::cout.put((i>>16)&255);
     std::cout.put(o->type);std::cout.put(o->colour);std::cout.put(GetObjectRandomBits(i));
     std::cout.put(o->town->id&255);std::cout.put(o->town->id>>8);
     delete o;
   }
   objects.clear();
 }
}
'''

lua = r'''
local p="mods/luanttd_core/"
local function load(n) return dofile(p..n..".lua") end
local Slope=load("openttd/slope")
local TG=load("openttd/terragenesis")(Slope)
local Cl=load("openttd/terragenesis_clear")
local O=load("openttd/scenery_object_worldgen")
local f=assert(io.open(arg[1],"wb"))
local expect=assert(io.open(arg[2],"wb"))
local fixtures=0
local totals={[0]=0,0}
local function run(board,north,start,date,capacity,tag)
  local w,h=board.width,board.depth
  local towns=board.towns
  f:write(("%d %d %d %d %d %.0f %.0f %d"):format(w,h,board.freeform and 1 or 0,date,capacity,start[1],start[2],#towns))
  for _,t in ipairs(towns) do f:write((" %d %d %d"):format(t.id,t.x-1,t.z-1)) end
  f:write("\n")
  for z=1,h do
    local row={}
    for x=1,w do
      local v=assert(board.tile(x,z))
      row[x]=string.char(v.class,north(x,z),v.bridge_above and 1 or 0,v.object_type or 255)
    end
    f:write(table.concat(row))
  end
  local a,b=start[1],start[2]
  local V=O.generate(board,start,TG.next_random,{date=date,capacity=capacity})
  assert(start[1]==a and start[2]==b,"source RNG was mutated")
  local s=V.stats
  local n=s.placed.transmitter+s.placed.lighthouse
  expect:write(("%.0f %.0f %d %d\n"):format(V.rng_after[1],V.rng_after[2],s.random_draws,n))
  local seen,count={},0
  V.each(function(x,z,v)
    local i=(z-1)*w+x-1
    assert(not seen[i] and v.class==10)
    assert(V.object(x,z).random_bits==v.random_bits)
    local before=board.tile(x,z)
    assert(before.class==0 and before.slope==0 and not before.bridge_above)
    assert(v.type==0 and v.height>=4 or v.type==1 and v.height<=2)
    expect:write(string.char(i%256,math.floor(i/256)%256,math.floor(i/65536),
      v.type,v.colour,v.random_bits,v.town%256,math.floor(v.town/256)))
    seen[i],count=true,count+1
    totals[v.type]=totals[v.type]+1
  end)
  assert(count==n and s.random_draws==s.attempts.transmitter+s.attempts.lighthouse+2*n)
  if tag=="no-water" then assert(s.targets.lighthouse==0 and s.attempts.lighthouse==0) end
  if tag=="no-space" then assert(count==0 and s.attempts.transmitter>0 and s.attempts.lighthouse>0) end
  if tag=="mix" and date>0 and capacity>1 then assert(s.placed.transmitter>0 and s.placed.lighthouse>0) end
  if date==0 or capacity==0 then assert(count==0 and s.random_draws==0) end
  fixtures=fixtures+1
end
local function wrapped(w,h,free,towns,corner,class,start,date,capacity,tag)
  local function at(x,z) return corner(math.min(w,x),math.min(h,z)) end
  local function tile(x,z)
    local k,b,o=class(x,z)
    local s,v=Slope.classify(at(x,z),at(x+1,z),at(x,z+1),at(x+1,z+1))
    return {class=k,slope=s,height=v,bridge_above=b,object_type=o}
  end
  run({width=w,depth=h,freeform=free,tile=tile,towns=towns},at,start,date,capacity,tag)
end
local function synthetic(w,h,free,seed,tag,date,capacity)
  local towns={{id=258,x=28,z=35},{id=7,x=36,z=35}}
  local function dist(x,z) return math.min(x-1,z-1,w-x,h-z) end
  local function corner(x,z)
    local d=dist(x,z)
    if tag=="no-water" then return 5 end
    if d<5 then return 0 end
    if d<15 then return 1+((x+z)%13==0 and 1 or 0) end
    return math.min(6,d-13)+((x%31==0 and z%9<4) and 1 or 0)
  end
  local function class(x,z)
    if x==w or z==h or free and (x==1 or z==1) then return 7 end
    if tag~="no-water" and dist(x,z)<4 then return 6 end
    if tag=="no-space" then return (x+z)%2==0 and 2 or 8 end
    if (x>=31 and x<=36 and z>=32 and z<=34) then return 3 end
    if (x>=18 and x<=22 and z>=20 and z<=26) then return 8 end
    if (x+z)%31==0 then return 10,false,1 end
    if (x==25 or x==38) and z==23 then return 10,false,0 end
    return 0,(x+z)%19==0
  end
  wrapped(w,h,free,towns,corner,class,TG.startup_rng(seed),date,capacity,tag)
end
for _,free in ipairs{true,false} do
  for _,seed in ipairs{1751,0,2^32-2} do
    for _,dimensions in ipairs{{64,64},{64,128},{256,128}} do
      synthetic(dimensions[1],dimensions[2],free,seed,"mix",1,0xFF0000)
    end
  end
  synthetic(64,64,free,1751,"mix",0,0xFF0000)
  synthetic(64,64,free,1751,"mix",1000,0)
  synthetic(64,64,free,1751,"mix",1000,1)
  synthetic(64,64,free,1751,"no-space",1000,0xFF0000)
end
synthetic(64,64,true,1751,"no-water",1000,0xFF0000)

for _,dims in ipairs{{64,64},{128,64},{256,128}} do
  local w,h=unpack(dims)
  for _,mode in ipairs{1,3,4} do
    local seed=1751
    local base=Cl.generate(TG.generate({width=w,depth=h,seed=seed,rng_state=TG.startup_rng(seed),terrain_type=mode}),TG.next_random)
    wrapped(w,h,true,{{id=4,x=21,z=25},{id=2,x=41,z=40}},base.corner,
      function(x,z) return (Cl.describe(base.tile(x,z))) end,base.rng_after,3000,0xFF0000)
  end
end

-- Live seed-1751 host board after source towns and the currently mounted
-- stock coal/power industry slice. No substituted placement or reseeding.
do
  local Sim,Terrain=load("sim"),load("openttd/terrain")
  local Gen={generate=function(a)return Cl.generate(TG.generate(a),TG.next_random) end,
    describe=Cl.describe,next_random=TG.next_random}
  local Cam,Names=load("generated_campaign"),load("openttd/stock_town_name")
  local G=load("openttd/town_growth")
  local Build=load("openttd/town_growth_build")(G,load("openttd/town_growth_houses"))
  local Worldgen=load("openttd/town_worldgen")(G,Build)
  local seed=1751
  local s=Cam.landscape(Sim,Terrain,Gen,{width=64,depth=64,seed=seed,rng_state=TG.startup_rng(seed),terrain_type=1})
  assert(Cam.towns(Sim,Terrain,s,Gen,Worldgen,Names,G,Build,{
    difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}).success)
  local P,R=load("openttd/passengers"),load("openttd/station_rating")
  local Cat=load("openttd/station_catchment")(P,R,function()return 0 end,function()return 0 end)
  local Coal=load("openttd/coal_industry")(P,R,Cat,load("openttd/income"))
  Cam.industries(Sim,Terrain,s,Gen,load("openttd/industry_worldgen")(Coal),load("coal_industry_world")(Sim,Terrain,Coal),4)
  local profile=s.stock_generated_profile
  local towns={}
  for _,site in ipairs(s.sites) do
    if site.kind=="town" then
      local x,z=Sim.xy(site.tile)
      towns[#towns+1]={id=site.id,x=x,z=z}
    end
  end
  local function class(x,z)
    local id=Sim.id(x,z)
    local t=s.tiles[id]
    if t.stock_void then return 7 end
    if t.stock_industry or t.site and s.sites[t.site] and s.sites[t.site].kind~="town" then return 8 end
    if t.house then return 3 end
    if t.build then return t.build=="road" and 2 or 10 end
    if t.terrain=="water" then return 6 end
    return 0
  end
  wrapped(64,64,true,towns,function(x,z)return Terrain.corner(s.corner_grid,x,z)end,class,
    profile.industry_rng,1,0xFF0000)
end

assert(totals[0]>10 and totals[1]>20)
f:close();expect:close()
print(fixtures)
'''

with tempfile.TemporaryDirectory(prefix="bayline-stock-objects-") as d:
    wd=Path(d)
    oracle,exe,run,inp,ref=[wd/n for n in ("oracle.cpp","oracle","run.lua","board","want")]
    oracle.write_text(cpp)
    run.write_text(lua)
    subprocess.run(["g++","-std=c++20","-O2","-fwrapv",oracle,"-o",exe],check=True)
    fixtures=int(subprocess.check_output([args.lua,run,inp,ref],cwd=root).strip())
    with inp.open("rb") as stream:
        result=subprocess.check_output([exe],stdin=stream)
    wanted=ref.read_bytes()
    if result!=wanted:
        n=next((n for n,(a,b) in enumerate(zip(result,wanted)) if a!=b),min(len(result),len(wanted)))
        raise AssertionError(f"first object difference at {n}: {result[n:n+30]} != {wanted[n:n+30]}")
i=draws=transmitters=lighthouses=0
for _ in range(fixtures):
    j=result.index(b"\n",i)
    a,b,r,n=map(int,result[i:j].split())
    draws+=r
    kinds=result[j+4:j+1+n*8:8]
    transmitters+=kinds.count(0)
    lighthouses+=kinds.count(1)
    i=j+1+n*8
assert i==len(result)
print(f"PASS {fixtures} pinned OpenTTD 14.1 object-generated boards: "
      f"{transmitters} transmitter(s), {lighthouses} lighthouse(s), {draws:,} stock draws")
