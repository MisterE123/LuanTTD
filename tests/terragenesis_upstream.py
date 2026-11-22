#!/usr/bin/env python3
"""Compile pinned OpenTTD 14.1 tgp.cpp and compare all tile/corner bytes and RNG.

Usage: python3 tests/terragenesis_upstream.py /path/to/OpenTTD [lua5.1] [--large]
"""
# SPDX-License-Identifier: GPL-2.0-only
# The generated C++ harness compiles OpenTTD contributors' unmodified functions.
import argparse
from hashlib import sha256
import itertools
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("lua", nargs="?", default="lua5.1")
parser.add_argument("--large", action="store_true")
args = parser.parse_args()


def read(name, digest):
    source = args.source
    candidates = [source / "src" / name, source / name, source / Path(name).name]
    path = next((p for p in candidates if p.is_file()), candidates[0])
    data = path.read_bytes()
    assert sha256(data).hexdigest() == digest, f"{path}: not pinned 14.1 source"
    return data.decode()


def block(data, pattern):
    p = re.search(pattern, data, re.M).start()
    q = data.index("{", p)
    nesting = 1
    while nesting:
        q += 1
        nesting += (data[q] == "{") - (data[q] == "}")
    return data[p:q+1]


tgp = read("tgp.cpp", "ed4093483d1528d1814a0f8292f7e0d9c9239e88a2291f116b26902bc9f0c231")
random = read("core/random_func.cpp", "6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
height = read("heightmap.cpp", "6e5599836b0a325c5031e0e860b1e16de6217a2111ebdc7b00461707fd4a20fd")
slope = read("tile_map.cpp", "479ae6451fa7af6b430e0c98ea6cdefbfbf4d9f2d482ee6c7c4e4054fca93fb3")
water = read("water_cmd.cpp", "f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847")
clear = read("clear_cmd.cpp", "97a79d03eb421cf5815c065b7a7dadbd97b362b650f48bda10fd28e85d0e2b68")
maps = read("map_func.h", "ea19473db84bf9e3c19c01b04ae732b123215a977b7d3961bbdbb8df3b7f9885")
map_cpp = read("map.cpp", "386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378")
economy = read("economy.cpp", "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb")
genworld = read("genworld.cpp", "787a30b5efc2a36306a30c678d69f0c13657ef6259957373fe0116d47d4cf920")
assert genworld.index("_random.SetSeed(")<genworld.index("StartupEconomy();",genworld.index("_random.SetSeed("))<genworld.index("landscape_generated = GenerateLandscape(")
assert genworld.index("landscape_generated = GenerateLandscape(")<genworld.index("GenerateClearTile();",genworld.index("landscape_generated = GenerateLandscape("))<genworld.index("if (!GenerateTowns(")
fluct = re.search(r"_economy.fluct = GB\(Random\(\), 0, 8\) \+ 168;", economy)[0]

header = r'''
#include <algorithm>
#include <bit>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <type_traits>
#include <vector>
// Full upstream transitive headers expose the double overload to tgp.cpp.
// In a pared-down harness <cmath> alone would silently pick ::abs(int).
using std::abs;
static_assert(std::is_same_v<decltype(abs(0.5)),double>);
static_assert(std::is_same_v<decltype(sqrt(0.5f)),double>);
using uint=unsigned;using byte=uint8_t;using TileIndex=int;using Slope=int;using Direction=int;
enum{LT_TEMPERATE, LT_ARCTIC, LT_TROPIC, LT_TOYLAND};
enum{BORDER_NE, BORDER_SE, BORDER_SW, BORDER_NW, BORDERS_RANDOM=16};
enum{GWP_LANDSCAPE,GWP_ROUGH_ROCKY};
constexpr int MAX_TILE_HEIGHT=255,MIN_MAP_SIZE_BITS=6,MAX_MAP_SIZE_BITS=12;
constexpr int CUSTOM_TERRAIN_TYPE_NUMBER_DIFFICULTY=5,CUSTOM_SEA_LEVEL_NUMBER_DIFFICULTY=4;
constexpr int SLOPE_FLAT=0,SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_STEEP=16;
enum{DIR_N,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW};
enum{MP_CLEAR=0,MP_WATER=6,MP_VOID=7};
enum{CLEAR_GRASS=0,CLEAR_ROUGH=1,CLEAR_ROCKS=2,CLEAR_DESERT=5};
int GB(uint32_t n,int start,int count){return (n>>start)&((1u<<count)-1);}
bool HasBit(uint n,int bit){return n&(1u<<bit);}
template<class T,size_t N> constexpr size_t lengthof(const T (&)[N]){return N;}
template<class T> T CeilDiv(T n,int d){return (n+d-1)/d;}
template<class T> T Clamp(T n,T lo,T hi){return std::clamp(n,lo,hi);}
template<class T> T* CallocT(size_t n){return static_cast<T*>(calloc(n,sizeof(T)));}
template<class T> void MemSetT(T* p,int v,size_t n){memset(p,v,n*sizeof(T));}
#define NOT_REACHED() std::abort()
#define WITH_ASSERT 1
struct Settings{
  struct {int terrain_type,quantity_sea_lakes;} difficulty;
  struct {bool freeform_edges;uint map_height_limit;} construction;
  struct {int custom_terrain_type,tgen_smoothness,landscape,variety,custom_sea_level;
    uint8_t water_borders; int map_x,map_y; uint32_t generation_seed;} game_creation;
} _settings_game;
struct Randomizer {
 uint32_t state[2];uint32_t Next();uint32_t Next(uint32_t);void SetSeed(uint32_t);
} _random;
uint32_t Random(){return _random.Next();}
uint32_t RandomRange(uint32_t n){return _random.Next(n);}
struct Map{
 static inline uint w,h,lx,lz;
 static uint SizeX(){return w;} static uint SizeY(){return h;}
 static uint LogX(){return lx;} static uint LogY(){return lz;}
 static uint Size(){return w*h;}
 static uint MaxX(){return w-1;} static uint MaxY(){return h-1;}
 static TileIndex WrapToMap(uint32_t i){return i&(w*h-1);}
''' + block(maps,r"^\s*static inline uint ScaleBySize\(uint n\)") + r'''
};
std::vector<byte> corners,tiles,cover;
uint TileX(TileIndex i){return i%Map::w;}
uint TileY(TileIndex i){return i/Map::w;}
TileIndex TileXY(int x,int y){return x+y*Map::w;}
int TileHeight(TileIndex tile){return corners.at(tile);}
void SetTileHeight(TileIndex tile,int d){corners.at(tile)=d;}
bool IsTileType(TileIndex tile,int kind){return tiles.at(tile)%16==kind;}
void MakeVoid(TileIndex tile){tiles.at(tile)=MP_VOID;}
void MakeClear(TileIndex tile,int,int){tiles.at(tile)=MP_CLEAR;}
bool IsClearGround(TileIndex tile,int ground){return cover.at(tile)==ground;}
void SetClearGroundDensity(TileIndex tile,int ground,int density){assert(density==3);cover.at(tile)=ground;}
void MarkTileDirtyByTile(TileIndex){}
void SetGeneratingWorldProgress(int,uint){}
enum DiagDirection{DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW};
struct TileIndexDiffC{int x,y;};
''' + block(map_cpp,r"^extern const TileIndexDiffC _tileoffs_by_diagdir") + r''';
int TileOffsByDiagDir(DiagDirection d){
 return _tileoffs_by_diagdir[d].x + _tileoffs_by_diagdir[d].y*(int)Map::w;
}
void MakeSea(TileIndex tile){tiles.at(tile)=MP_WATER+16;}
void MakeShore(TileIndex tile){tiles.at(tile)=MP_WATER+32;}
bool IsInnerTile(TileIndex i){
 uint x=TileX(i), y=TileY(i);
 return x<Map::MaxX() && y<Map::MaxY() && ((x>0&&y>0) || !_settings_game.construction.freeform_edges);
}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
Slope GetTileSlope(TileIndex tile,int *h=nullptr);
TileIndex TileAddByDir(TileIndex tile,Direction d){
  static constexpr int dx[]={-1,-1,-1,0,1,1,1,0},dy[]={-1,0,1,1,1,0,-1,-1};
  return (tile+dx[d]+dy[d]*(int)Map::w)&(Map::Size()-1);
}
std::vector<int> SetBitIterator(int bits){
  std::vector<int> indices;
  for(int d=0;d<8;d++)if((bits>>d)&1)indices.push_back(d);
  return indices;
}
void GenerateWorldSetAbortCallback(void (*)()){}
void IncreaseGeneratingWorldProgress(int){}
'''
cpp = header + "\n".join(block(random, pat) for pat in (
    r"^uint32_t Randomizer::Next\(\)", r"^uint32_t Randomizer::Next\(uint32_t", r"^void Randomizer::SetSeed"))
cpp += "\n" + tgp[tgp.index("/** Fixed point type for heights */"):] + "\n"
for src, pat in ((height, r"^void FixSlopes"),
                 (slope,r"^static Slope GetTileSlopeGivenHeight"), (slope,r"^Slope GetTileSlope\("),
                 (water,r"^static const uint8_t _flood_from_dirs"),
                 (water,r"^void ConvertGroundTilesIntoWaterTiles"),
                 (maps,r"^inline TileIndex RandomTileSeed")):
    cpp += block(src,pat) + (";" if "_flood_from_dirs" in pat else "") + "\n"

cpp += "\n#define RandomTile() RandomTileSeed(Random())\n"
cpp += block(clear,r"^void GenerateClearTile") + "\n"
cpp += "void StartupEconomyPrelude(){struct {int fluct;} _economy; " + fluct + "}\n"
cpp += r'''
int main() {
 uint32_t seed;
 uint w,h,t,sea,smooth,border,variety,limit,ct,cs;
 bool freeform,newgame;
 while(std::cin>>seed>>w>>h>>t>>sea>>smooth>>freeform>>border>>variety>>limit>>ct>>cs>>newgame){
   Map::w=w;Map::h=h;Map::lx=std::countr_zero(w);Map::lz=std::countr_zero(h);
   _settings_game.difficulty={(int)t,(int)sea};
   _settings_game.construction={freeform,limit};
   _settings_game.game_creation={(int)ct,(int)smooth,LT_TEMPERATE,(int)variety,(int)cs,
     (byte)border,(int)Map::lx,(int)Map::lz,seed};
   corners.assign(w*h,0);tiles.assign(w*h,0);cover.assign(w*h,0);
   for(uint x=0;x<w;x++)MakeVoid(TileXY(x,h-1));
   for(uint y=0;y<h;y++)MakeVoid(TileXY(w-1,y));
   _random.SetSeed(seed);
   if(newgame) StartupEconomyPrelude();
   GenerateTerrainPerlin();
   FixSlopes();
   ConvertGroundTilesIntoWaterTiles();
   std::cout<<_random.state[0]<<" "<<_random.state[1]<<" "<<GetEstimationTGPMapHeight();
   if(newgame) GenerateClearTile();
   std::cout<<" "<<_random.state[0]<<" "<<_random.state[1]<<"\n";
   for(uint i=0;i<w*h;i++){std::cout.put(corners[i]);std::cout.put(tiles[i]);std::cout.put(cover[i]);}
 }
}
'''

lua_program=r'''
local path="mods/bayline/openttd/"
local Slope=dofile(path.."slope.lua")
local G=dofile(path.."terragenesis.lua")(Slope)
local C=dofile(path.."terragenesis_clear.lua")
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  local seed,w,h,t,sea,smooth,freeform,border,variety,limit,ct,cs,newgame=unpack(a)
  assert(newgame==0 or newgame==1)
  local clock=os.clock()
  local v=G.generate({seed=seed,width=w,depth=h,terrain_type=t,quantity_sea_lakes=sea,
    tgen_smoothness=smooth,freeform_edges=freeform==1,water_borders=border,variety=variety,
    map_height_limit=limit,custom_terrain_type=ct,custom_sea_level=cs,
    rng_state=newgame==1 and G.startup_rng(seed) or nil})
  local after_landscape=v.rng_after
  if newgame==1 then v=C.generate(v,G.next_random) end
  local mem=v.generation_footprint()
  assert(mem.height_bytes==w*h and mem.octave_scratch_rows==3)
  if w>=512 or h>=512 then
    collectgarbage("collect")
    io.stderr:write(("Lua %dx%d seed %.0f generation %.2fs CPU; retained %.1f KiB\n")
      :format(w,h,seed,os.clock()-clock,collectgarbage("count")))
  end
  io.write(("%.0f %.0f %d %.0f %.0f\n"):format(after_landscape[1],after_landscape[2],
    v.estimated_max_height,v.rng_after[1],v.rng_after[2]))
  for z=1,h do
    local row={}
    for x=1,w do
      local t=v.tile(x,z)
      row[x]=string.char(v.corner(x,z),t%256,math.floor(t/256))
    end
    io.write(table.concat(row))
  end
end
'''

# 64²: every roughness/terrain/sea preset; several independent edge and variety
# settings, custom minimum/maximum heights and sea percentages, varied seeds
# including high-bit values (coast polynomial) and zero (PRNG).
fixtures=[
    (1751,64,64,t,sea,smooth,(t+sea)%2,(3*t+sea+smooth)%17,0,0,15,1)
    for t,sea,smooth in itertools.product(range(5),range(4),range(4))
]
fixtures += [(seed,64,64,3,0,1,1,16,0,0,15,1)
             for seed in (0,1,2,99,1751,2**31,2**32-2,2**32-1)]
fixtures += [(1751,64,64,3,1,1,1,border,(border%5)+1,0,15,1) for border in range(17)]
fixtures += [(1751,w,h,5,4,2,1,15,variety,0,ct,cs)
             for (w,h),ct,cs,variety in itertools.product(
                 ((64,64),(128,64),(64,128)), (1,15,255), (1,90), (0,3))]
fixtures += [(1751,256,128,4,0,3,1,16,5,15,15,1),(3327817,128,256,2,2,0,1,1,4,0,15,1)]
fixtures = [(*f,0) for f in fixtures] + [(*f,1) for f in fixtures[::4]]
fixtures += [(1751,64,64,3,0,1,1,15,0,0,15,1,1)]
if args.large:
    fixtures += [
        (1751,1024,512,3,0,3,1,16,3,0,15,1,1),
        (3327817,4096,64,3,0,1,1,0,2,0,15,1,1),
        (2814928308,512,2048,5,4,0,1,7,0,0,255,6,1),
        (1751,1024,1024,4,0,3,1,15,2,0,15,1,1),
    ]

def check_full_header_math(wd):
    # When given the whole source tree, verify that the stubs above do not
    # accidentally change overload resolution. Use only placeholder IDs for
    # the generated language table; no game state depends on these values.
    src=args.source/"src"
    if not (src/"tgp.cpp").is_file():
        return
    header_root=wd/"source-headers"
    (header_root/"table").mkdir(parents=True)
    (header_root/"widgets").mkdir()
    english=(src/"lang"/"english.txt").read_text()
    names=dict.fromkeys(re.findall(r"^(STR_[A-Z0-9_]+)\s*:",english,re.M))
    (header_root/"table"/"strings.h").write_text(
        '#pragma once\n#include "strings_type.h"\n' +
        ''.join(f"constexpr StringID {name} = {i};\n" for i,name in enumerate(names)))
    math_probe=wd/"actual_upstream_tgp.cpp"
    math_probe.write_text(tgp.replace('#include "safeguards.h"', '#include "safeguards.h"\n'
        'static_assert(std::is_same_v<decltype(abs(0.5)),double>);\n'
        'static_assert(std::is_same_v<decltype(sqrt(0.5f)),double>);'))
    subprocess.run(["g++","-std=c++20","-fsyntax-only","-Wno-multichar",
                    "-DTTD_ENDIAN=TTD_LITTLE_ENDIAN","-I",src,"-I",src/"3rdparty"/"fmt",
                    "-I",header_root,"-I",header_root/"widgets",math_probe],check=True)


with tempfile.TemporaryDirectory(prefix="bayline-terragenesis-") as d:
    wd=Path(d)
    check_full_header_math(wd)
    sr,exe,lp=wd/"oracle.cpp",wd/"oracle",wd/"lua_runner.lua"
    sr.write_text(cpp)
    lp.write_text(lua_program)
    subprocess.run(["g++","-std=c++20","-O2","-fwrapv","-ffp-contract=off",sr,"-o",exe],check=True)
    data="".join(" ".join(map(str,f))+"\n" for f in fixtures).encode()
    a=subprocess.run([exe],input=data,stdout=subprocess.PIPE,check=True).stdout
    b=subprocess.run([args.lua,lp],input=data,stdout=subprocess.PIPE,cwd=ROOT,check=True).stdout

i=j=cells=0
for f in fixtures:
    ei,ej=a.index(b'\n',i),b.index(b'\n',j)
    assert a[i:ei]==b[j:ej], f"RNG/max height differs for {f}: {a[i:ei]} != {b[j:ej]}"
    i,j=ei+1,ej+1
    n=f[1]*f[2]*3
    x,y=a[i:i+n],b[j:j+n]
    if x!=y:
        k=next(k for k,(u,v) in enumerate(zip(x,y)) if u!=v)
        cell=k//3
        u,v=cell%f[1],cell//f[1]
        raise AssertionError(f"{f}: stock ({u},{v}) height,class,clear {tuple(x[3*cell:3*cell+3])} != Lua {tuple(y[3*cell:3*cell+3])}")
    i,j,cells=i+n,j+n,cells+n//3
assert i==len(a) and j==len(b)
print(f"PASS {len(fixtures)} complete pinned OpenTTD 14.1 TerraGenesis maps ({cells:,} corner/tile pairs, {sum(f[-1] for f in fixtures)} pre-town clear-ground passes, and RNG checkpoints)")
