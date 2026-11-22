#!/usr/bin/env python3
"""Compare complete Original temperate height/coast maps to pinned C++.

Usage: TMPDIR=/path/to/qa_temp python3 tests/original_terrain_upstream.py
       /path/to/OpenTTD /path/to/local/ogfxi_logos.grf [lua5.1] [--large]
"""
# SPDX-License-Identifier: GPL-2.0-only
# Compiles selected OpenTTD contributor source under GPL-2.0.
import argparse
from hashlib import sha256
from pathlib import Path
import itertools
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
argp = argparse.ArgumentParser(description=__doc__)
argp.add_argument("source",type=Path)
argp.add_argument("grf",type=Path)
argp.add_argument("lua",nargs="?",default="lua5.1")
argp.add_argument("--large",action="store_true",help="also compare full stock-scale maps up to 4096²")
args=argp.parse_args()
src,grf,lua=args.source,args.grf,args.lua


def read(name, digest):
    paths = (src/"src"/name, src/name, src/Path(name).name)
    p = next((p for p in paths if p.is_file()), paths[0])
    b = p.read_bytes()
    assert sha256(b).hexdigest()==digest, f"{p} not pinned 14.1"
    return b.decode()


def block(data, pattern):
    p = re.search(pattern, data, re.M).start()
    begin = data.index("{", p)
    nesting, q = 1, begin
    while nesting:
        q += 1
        nesting += (data[q]=="{") - (data[q]=="}")
    return data[p:q+1]


land = read("landscape.cpp","0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97")
height = read("heightmap.cpp","6e5599836b0a325c5031e0e860b1e16de6217a2111ebdc7b00461707fd4a20fd")
water = read("water_cmd.cpp","f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847")
slope = read("tile_map.cpp","479ae6451fa7af6b430e0c98ea6cdefbfbf4d9f2d482ee6c7c4e4054fca93fb3")
maps = read("map_func.h","ea19473db84bf9e3c19c01b04ae732b123215a977b7d3961bbdbb8df3b7f9885")
random = read("core/random_func.cpp","6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
if args.large:
    map_type=read("map_type.h","f049e01aaf8dd361714d3edaebcc3eaaf2e1449e892a5bbbec55845ed9d7772d")
    allocation=block(read("map.cpp","386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378"),
                     r"^/\* static \*/ void Map::Allocate")
    for axis in "xy":
        assert f"IsInsideMM(size_{axis}, MIN_MAP_SIZE, MAX_MAP_SIZE + 1)" in allocation
        assert f"(size_{axis} & (size_{axis} - 1))" in allocation

    settings=read("table/settings/world_settings.ini","4c08978820994e9a975a1a135b9d1ebcf01764772e49ecc2ad2c71c05e93642e")
    assert re.search(r"MIN_MAP_SIZE_BITS\s*=\s*6;",map_type)
    assert re.search(r"MAX_MAP_SIZE_BITS\s*=\s*12;",map_type)
    for axis in "xy":
        stanza=settings.split("var      = game_creation.map_"+axis,1)[1].split("[SDT_",1)[0]
        assert "MIN_MAP_SIZE_BITS" in stanza and "MAX_MAP_SIZE_BITS" in stanza

cpp = r"""
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>
using uint=unsigned;using byte=uint8_t;using TileIndex=int;using Slope=int;
constexpr int MAX_TILE_HEIGHT=255,SPR_MAPGEN_BEGIN=4845,CUSTOM_SEA_LEVEL_NUMBER_DIFFICULTY=4;
constexpr int SLOPE_FLAT=0,SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_STEEP=16;
enum {DIR_N,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW};
enum DiagDirection{DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW};
enum{AXIS_X,AXIS_Y,MP_CLEAR=0,MP_WATER=6,MP_VOID=7};
enum class SpriteType{MapGen};
int DiagDirToAxis(DiagDirection d) {return d%2;}
int GB(uint32_t n,int start,int count){return (n>>start)&((1u<<count)-1);}
template <class T> auto Clamp(T x,T lo,T hi){return std::clamp(x,lo,hi);}
template <class T> void Swap(T&a,T&b){std::swap(a,b);}
template <class T> auto CeilDiv(T n,int d){return (n+d-1)/d;}
[[noreturn]] void UserError(const char*){std::abort();}
#define NOT_REACHED() std::abort()
struct Settings{
  struct {int terrain_type=1;int quantity_sea_lakes=1;} difficulty;
  struct {bool freeform_edges=false;} construction;
} _settings_game;
struct Randomizer {
 uint32_t state[2];uint32_t Next();void SetSeed(uint32_t seed);
} _random;
uint32_t Random(){return _random.Next();}
struct Map {
  static inline uint w,h,lx,lz;
  static uint SizeX(){return w;} static uint SizeY(){return h;}
  static uint LogX(){return lx;} static uint LogY(){return lz;}
  static uint Size(){return w*h;}
  static uint MaxX(){return w-1;} static uint MaxY(){return h-1;}
"""
cpp += block(maps,r"^\s*static inline uint ScaleBySize\(uint n\)")+"\n};\n"
for pattern in [r"^uint32_t Randomizer::Next\(\)",r"^void Randomizer::SetSeed"]:
    cpp += block(random,pattern)+"\n"
cpp += r"""
struct Sprite {byte width, height;const byte *data;};
std::array<Sprite,37> templates;
std::array<std::vector<byte>,37> samples;
const Sprite *GetSprite(int id,SpriteType){return &(templates.at(id-SPR_MAPGEN_BEGIN));}
std::vector<byte> corners,tiles;
int TileX(TileIndex tile){return tile%Map::w;}
int TileY(TileIndex tile){return tile/Map::w;}
TileIndex TileXY(int x,int y){return x+y*Map::w;}
int TileDiffXY(int x,int y){return (int)x+y*(int)Map::w;}
int TileHeight(TileIndex tile){return corners.at(tile);}
void SetTileHeight(TileIndex tile,int d){corners.at(tile)=d;}
bool IsTileType(TileIndex tile,int kind){return tiles.at(tile)%16==kind;}
void MakeVoid(TileIndex tile){tiles.at(tile)=MP_VOID;}
void MakeSea(TileIndex tile){tiles.at(tile)=MP_WATER+16;}
void MakeShore(TileIndex tile){tiles.at(tile)=MP_WATER+32;}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
using Direction=int;
Slope GetTileSlope(TileIndex tile,int *h=nullptr);
int TileAddByDir(int tile,Direction d){
  static constexpr int dx[]={-1,-1,-1,0,1,1,1,0},dy[]={-1,0,1,1,1,0,-1,-1};
  return tile+TileDiffXY(dx[d],dy[d]);
}
std::vector<int> SetBitIterator(int bits){
  std::vector<int> indices;
  for(int d=0;d<8;d++)if((bits>>d)&1)indices.push_back(d);
  return indices;
}
"""
for i in (1,2):
    cpp += re.search(r"^static const byte _genterrain_tbl_"+str(i)+r".*$",land,re.M)[0]+"\n"
for source, pattern in [(land,r"^static void GenerateTerrain"), (height,r"^void FixSlopes"),
                        (slope,r"^static Slope GetTileSlopeGivenHeight"),(slope,r"^Slope GetTileSlope\("),
                        (water,r"^static const uint8_t _flood_from_dirs"),(water,r"^void ConvertGroundTilesIntoWaterTiles")]:
    cpp += block(source,pattern)+(";" if "flood_from_dirs" in pattern else "")+"\n"
start=land.index("bool GenerateLandscape(byte mode)")
src_land=land[start:]
freeform = block(src_land,r"^\s*if \(_settings_game.construction.freeform_edges\)")
# Extract the complete default block, including its internal for-loop.
temperate=block(src_land, r"^\s*default: \{(?=\s*uint32_t r = Random\(\);\s*assert\()")
temperate=temperate[temperate.index("{")+1:temperate.rindex("}")].rsplit("break;",1)[0]
cpp += """
void OriginalOnce(){
    for(uint x=0;x<Map::w;x++)MakeVoid(TileXY(x,Map::MaxY()));
    for(uint y=0;y<Map::h;y++)MakeVoid(TileXY(Map::MaxX(),y));
"""+freeform+temperate+"""
  FixSlopes();
  ConvertGroundTilesIntoWaterTiles();
}
"""
cpp += r"""
int main(int argc,char **argv){
  assert(argc==2);std::ifstream in(argv[1],std::ios::binary);
  char magic[8];in.read(magic,8);
  assert(std::string(magic,8)=="OTMAPGEN");
  for(int i=0;i<37;i++){
    byte w=in.get(),h=in.get();
    samples[i].resize(w*h);
    in.read(reinterpret_cast<char*>(samples[i].data()),w*h);
    assert(in);
    templates[i]={w,h,samples[i].data()};
  }
  uint seed,w,h,t,s;bool f;
  while(std::cin>>seed>>w>>h>>t>>s>>f){
    Map::w=w;Map::h=h;Map::lx=std::countr_zero(w);Map::lz=std::countr_zero(h);
    _settings_game.difficulty.terrain_type=t;
    _settings_game.difficulty.quantity_sea_lakes=s;
    _settings_game.construction.freeform_edges=f;
    corners.assign(w*h,0);tiles.assign(w*h,0);_random.SetSeed(seed);
    OriginalOnce();
    std::cout<<_random.state[0]<<" "<<_random.state[1]<<"\n";
    for(uint i=0;i<w*h;i++){
      std::cout.put(corners[i]);
      std::cout.put(tiles[i]);
    }
  }
}
"""
program=r"""
local p="mods/bayline/openttd/"
local G=dofile(p.."original_terrain.lua")(dofile(p.."slope.lua"))
local file=assert(io.open(arg[1],"rb"))
local bank=assert(G.read_masks(file:read("*a")));file:close()
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  local seed,w,h,t,s,f=unpack(a)
  local time=os.clock()
  local v=G.generate({width=w,depth=h,seed=seed,terrain_type=t,quantity_sea_lakes=s,freeform_edges=f==1},bank)
  if w>256 or h>256 then
    local duration=os.clock()-time
    collectgarbage("collect")
    local footprint=v.generation_footprint()
    assert(footprint.height_bytes==w*h and footprint.stamp_mutable_cells<=16*w and footprint.sweep_mutable_cells==w)
    local mem=io.open("/proc/self/status","r")
    local rss=mem and mem:read("*a"):match("VmHWM:%s*(%d+)") or "unavailable"
    if mem then mem:close() end
    io.stderr:write(("%dx%d seed %.0f: generation %.2fs CPU; Lua retained %.1f KiB; process peak %s KiB; mutable band %d cells\n")
      :format(w,h,seed,duration,collectgarbage("count"),rss,footprint.stamp_mutable_cells))
  end
  io.write(("%.0f %.0f\n"):format(unpack(v.rng_after)))
  for z=1,h do
    local row={}
    for x=1,w do row[x]=string.char(v.corner(x,z),v.tile(x,z)) end
    io.write(table.concat(row))
  end
end
"""

cases = [(1751,w,h,t,s,f) for (w,h),t,s,f in itertools.product(
    list(itertools.product((64,128,256),repeat=2)),range(4),range(4),(0,1))]
cases += [(seed,256,256,3,0,1) for seed in (0,1,2,4294967295,305419896,9876321)]
if args.large:
    cases += [(39166,512,2048,2,1,0),(305419896,4096,1024,3,2,1),
              (1751,4096,4096,3,0,1)]
with tempfile.TemporaryDirectory(prefix="original-terrain-upstream-") as work:
    d=Path(work)
    (d/"ref.cpp").write_text(cpp)
    (d/"test.lua").write_text(program)
    subprocess.run(["c++","-std=c++20","-O2",d/"ref.cpp","-o",d/"ref"],check=True)
    subprocess.run([sys.executable,root/"tools/extract_original_terrain_masks.py",grf,d/"local.bin"],check=True)
    assert sha256((d/"local.bin").read_bytes()).hexdigest()=="7ff877ad58ebcdc15cb49824c5c2bab434b2c19d7e48319b38ad94434003f432"
    data="\n".join(" ".join(map(str,row)) for row in cases).encode()+b"\n"
    # Spill the independent outputs to private temp files, then compare
    # one row at a time. No Python RAM copy of either full terrain.
    with (d/"ref.bin").open("wb") as out:
        subprocess.run([d/"ref",d/"local.bin"],input=data,stdout=out,check=True)
    with (d/"lua.bin").open("wb") as out:
        subprocess.run([lua,d/"test.lua",d/"local.bin"],input=data,stdout=out,cwd=root,check=True)
    counts={n:0 for n in (0,7,22,38)}
    with (d/"ref.bin").open("rb") as ref,(d/"lua.bin").open("rb") as result:
        for case in cases:
            a,b=ref.readline(),result.readline()
            assert a and a==b,(case,"RNG",a,b)
            w,h=case[1:3]
            for z in range(h):
                left=ref.read(2*w);right=result.read(2*w)
                assert len(left)==len(right)==2*w
                if left!=right:
                    x=next(x for x in range(w) if left[2*x:2*x+2]!=right[2*x:2*x+2])
                    raise AssertionError((case,(x,z),list(left[2*x:2*x+2]),list(right[2*x:2*x+2])))
                for n in counts:
                    counts[n]+=left[1::2].count(n)
        assert not ref.read(1) and not result.read(1) and all(counts.values()),counts
print(f"PASS {len(cases)} complete Original maps, {sum(counts.values()):,} heights and classes; includes {counts[38]:,} coast tiles")
