#!/usr/bin/env python3
"""Compare native Temperate RC1 lighthouse halo, placement and RNG to C++."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import subprocess
import tempfile

from terragenesis_clear_rc1_upstream import CPP as ROCK_MAP, PINS as ROCK_PINS, extract

ROOT=Path(__file__).resolve().parents[1]
PINS=ROCK_PINS | {
    "object_cmd.cpp": "be158351d96632987dddc24fe8cc9e1c32cd55c54c2cd9b065c904c171ccdf5f",
    "tilearea_spiral.h": "9174d414578fe1f8cffce93174b897d9030cd6a85451da08734d22bfbfd1ba31",
    "tilearea_spiral.cpp": "762270e0f4e8d3b1a71aa821b11c2dccdbd0a12d2d02b97756c8e0244b436f0e",
    "newgrf_object.cpp": "212dc594756dcf3833ef7c401332c96062595a711c8dbf4cd63d1839363244ac",
}
CPP=ROCK_MAP.replace("#include <bit>", "#include <bit>\n#include <cassert>\n#include <cmath>\n#include <array>\n#include <iterator>").replace(
    "Void=7", "Void=7, Object=10").replace(
    "NW, End", "NW, End, Begin=NE, Invalid=255").replace(
    "{ RoughAndRocks }","{ RoughAndRocks, Objects }").replace(
    "struct Map {", """struct Map {
    static uint MaxX() { return width-1; }
    static uint MaxY() { return depth-1; }
    static uint SizeX() { return width; }
    static uint SizeY() { return depth; }
    static uint ScaleBySize1D(uint n) { return (n*(width+depth)+511)/512; }
""") + r"""
template<class T> struct DiagDirectionIndexArray {
    T values[4];
    void fill(T v) { for (auto &entry:values) entry=v; }
    T &operator[](DiagDirection d) { return values[int(d)]; }
};
struct TileIndexDiffC { int x,y; };
enum class Direction { W };
TileIndexDiffC TileIndexDiffCByDir(Direction) { return {1,-1}; }
TileIndexDiffC TileIndexDiffCByDiagDir(DiagDirection d) {
    const TileIndexDiffC offsets[4] = {{-1,0},{0,1},{1,0},{0,-1}};
    return offsets[int(d)];
}
void operator++(DiagDirection &d) { d=DiagDirection(int(d)+1); }
void operator++(DiagDirection &d,int) { ++d; }
enum class Axis { X,Y };
Axis DiagDirToAxis(DiagDirection d) { return Axis(int(d)%2); }
uint TileX(TileIndex t) { return t % width; }
uint TileY(TileIndex t) { return t / width; }
TileIndex TileXY(uint x,uint y) { return y*width+x; }
struct { struct { bool freeform_edges; } construction; } _settings_game;
constexpr TileIndex INVALID_TILE=-1;
TileIndex TileAddWrap(TileIndex tile,int dx,int dy) {
    uint x=TileX(tile)+dx,y=TileY(tile)+dy;
    if ((x==0 || y==0) && _settings_game.construction.freeform_edges) return INVALID_TILE;
    if (x>=Map::MaxX() || y>=Map::MaxY()) return INVALID_TILE;
    return TileXY(x,y);
}
uint RandomRange(uint limit) { return (uint64_t(Random()) * limit) >> 32; }
TileIndex RandomTile() { return RandomTileSeed(Random()); }
bool IsCoastTile(TileIndex t) { return IsTileType(t,TileType::Water) && IsCoast(t); }
WaterTileType GetWaterTileType(TileIndex t) {
    if (IsCoast(t)) return tiles[t]&4096 ? WaterTileType::CoastRocks : WaterTileType::Coast;
    return tiles[t]&4096 ? WaterTileType::ClearRocks : WaterTileType::Clear;
}
std::vector<int> terrain; // low 5 bits slope, next 8 height, bit 13 bridge overhead
bool IsTileFlat(TileIndex t,int *height=nullptr) {
    if (height) *height=(terrain[t] >> 5) & 255;
    return (terrain[t] & 31)==0;
}
int GetTileZ(TileIndex t) { return (terrain[t] >> 5) & 255; }
bool IsBridgeAbove(TileIndex t) { return terrain[t] & 8192; }
enum class HouseZone { TownEdge };
uint to_underlying(HouseZone h) { return uint(h); }
struct Town {
    int xy;
    struct { uint squared_town_zone_radius[1]; } cache;
    static std::vector<Town*> Iterate();
};
std::vector<Town> towns;
std::vector<Town*> Town::Iterate() {
    std::vector<Town*> out;
    for (auto &t:towns) out.push_back(&t);
    return out;
}
constexpr int OBJECT_TRANSMITTER=0,OBJECT_LIGHTHOUSE=1;
int capacity;
std::vector<std::array<int,4>> objects;
std::vector<int> object_ids;
struct Object { static bool CanAllocateItem() { return capacity>0; } };
bool IsObjectTypeTile(TileIndex t,int type) {
    return IsTileType(t,TileType::Object) && object_ids[t]==type;
}
void BuildObject(int type,TileIndex tile) {
    --capacity;
    object_ids[tile]=type;
    tiles[tile]=10;
    objects.push_back({tile,type,int(Random()&15),int(Random()&255)});
}
namespace TimerGameCalendar { int date; }
enum class ObjectFlag { ScaleByWater };
struct ObjectSpec {
    int type;
    uint generate_amount;
    int introduction_date;
    uint views;
    struct { bool scale; bool Test(ObjectFlag) const { return scale; } } flags;
    int Index() const { return type; }
    bool IsEverAvailable() const { return true; } // stock Temperate world creation only
    bool WasEverAvailable() const;
    static uint Count() { return 2; }
    static std::array<ObjectSpec,2> Specs() {
        return {{{0,15,701265,1,{false}}, {1,8,0,1,{true}}}};
    }
};
enum class DoCommandFlag { Execute, Auto, NoTestTownRating, NoModifyTownRating };
struct CommandResult { bool Succeeded() { assert(false); return false; } };
CommandResult CmdBuildObject(std::initializer_list<DoCommandFlag>,int,int,int) { return {}; }
"""
LUA=r"""
local mods=arg[1]
local g=arg[2]
local function m(n) return dofile(mods..n..".lua") end
local TG=m("openttd/terragenesis")(m("openttd/slope"))
local Clear=dofile(g)
local Calendar=m("openttd/stock_engine_calendar")
assert(Calendar.BASE_DATE==701265)
local O=m("openttd/scenery_object_rc1")(Clear,Calendar)
local maps=io.read("*n")
for fixture=1,maps do
  local w,h,a,b,free,date,cap,n=io.read("*n","*n","*n","*n","*n","*n","*n","*n")
  local towns,tiles,geo={},{},{}
  for j=1,n do
    local id,left=io.read("*n","*n")
    towns[j]={id=j,x=id%w+1,z=math.floor(id/w)+1,edge_radius_squared=left}
  end
  for j=1,w*h do tiles[j]=io.read("*n") end
  for j=1,w*h do geo[j]=io.read("*n") end
  local lookup={[1]="sea",[2]="coast",[3]="river"}
  local function tile(x,z)
    local j=(z-1)*w+x
    local k,water,ground,rocky=Clear.describe(tiles[j])
    local a=geo[j]
    return {class=k,water=lookup[water],ground=ground,rocky=rocky,slope=a%32,
      height=math.floor(a/32)%256,bridge_above=a>=8192}
  end
  local result=O.generate({width=w,depth=h,freeform=free==1,towns=towns,tile=tile},{a,b},TG.next_random,
    {date=date,capacity=cap})
  local rows={}
  result.each(function(x,z,r)
    local idx=(z-1)*w+x
    tiles[idx]=10
    rows[#rows+1]=string.format("%d,%d,%d,%d",idx-1,r.type,r.colour,r.random_bits)
  end)
  result.each_rock(function(x,z,ground,wet)
    local idx=(z-1)*w+x
    tiles[idx]=tiles[idx]%256+(ground or 0)*256+(wet and 4096 or 0)
  end)
  print(string.format("%.0f %.0f",result.rng_after[1],result.rng_after[2]))
  print(table.concat(rows," "))
  print(table.concat(tiles," "))
end
"""
RUNNER=r"""
int main() {
    int maps,free,n;
    std::cin>>maps;
    while (maps--) {
        std::cin>>width>>depth>>rng.state[0]>>rng.state[1]>>free>>TimerGameCalendar::date>>capacity>>n;
        _settings_game.construction.freeform_edges=free!=0;
        towns.resize(n);
        for (auto &t:towns) std::cin>>t.xy>>t.cache.squared_town_zone_radius[0];
        tiles.resize(width*depth);
        terrain.resize(width*depth);
        for (auto &v:tiles) std::cin>>v;
        for (auto &v:terrain) std::cin>>v;
        objects.clear();
        object_ids.assign(width*depth,-1);
        GenerateObjects();
        std::cout<<rng.state[0]<<' '<<rng.state[1]<<'\n';
        for (size_t i=0;i<objects.size();i++) {
            auto object = objects[i];
            if (i) std::cout<<' ';
            std::cout<<object[0]<<','<<object[1]<<','<<object[2]<<','<<object[3];
        }
        std::cout<<'\n';
        for (size_t i=0;i<tiles.size();i++) std::cout<<tiles[i]<<(i+1==tiles.size()?'\n':' ');
    }
}
"""

def fixture(w,h,seed,free,date,cap):
    towns=[(8,8,16),(31,h//2,36),(w-7,h-10,64),(w//2,17,100),(2,2,121)]
    seam=lambda z: w//2+((z//7+seed)%5)-2
    tiles=[]
    geo=[]
    for z in range(h):
        for x in range(w):
            ocean=x<=8 or x>=w-7 or x==seam(z)
            coast=x in (9,10,w-8,w-9,seam(z)-1,seam(z)+1)
            void=x==w-1 or z==h-1 or free and (x==0 or z==0)
            rocky=(x+19*z+seed)%133==0
            word=7 if void else 38+4096*rocky if coast else 22+4096*rocky if ocean else 0
            if word==0 and (x+9*z+seed)%29==0: word=54 # rock may hop but not paint river
            if word==0 and (x+7*z+seed)%37==0: word=8 # industry barrier
            if word==0 and (x+11*z+seed)%13==0: word=768 # field is still clear ground
            height=0 if ocean or coast else 1 if x<13 or x>w-11 or abs(x-seam(z))<6 else 4+(x%4)
            slope=1 if coast else 0
            over=(x+3*z+seed)%101==0
            tiles.append(word)
            geo.append(height*32+slope+8192*over)
    for x,z,_ in towns: tiles[x+z*w]=3
    return [
        f"{w} {h} {seed} {seed ^ 0x871F314C} {int(free)} {date} {cap} {len(towns)}",
        " ".join(f"{x+z*w} {r}" for x,z,r in towns),
        " ".join(map(str,tiles)), " ".join(map(str,geo)),
    ]

def main():
    p=ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    p.add_argument("--clear",type=Path,default=ROOT/"mods/luanttd_core/openttd/terragenesis_clear_rc1.lua")
    a=p.parse_args()
    src=a.source/"src" if (a.source/"src").is_dir() else a.source
    data={}
    for file,pin in PINS.items():
        raw=(src/file).read_bytes()
        assert sha256(raw).hexdigest()==pin, f"Wrong upstream source: {file}"
        data[file]=raw.decode()
    up=extract(data["core/random_func.cpp"],"uint32_t Randomizer::Next()")
    up+="\n"+extract(data["newgrf_object.cpp"],"bool ObjectSpec::WasEverAvailable() const")
    for f in ("static bool TileMayHaveRocks(", "static void TileMakeRocks(", "void GenerateRocks("):
        up+="\n"+extract(data["clear_cmd.cpp"],f)
    header=data["tilearea_spiral.h"]
    up+="\n"+header[header.index("class SpiralTileIterator"):header.rindex("#endif")]
    spiral=data["tilearea_spiral.cpp"]
    up+="\n"+spiral[spiral.index("SpiralTileIterator::SpiralTileIterator"):]
    for f in ("static bool TryBuildLighthouseNearTile(", "static void TryBuildTownLighthouse(",
              "static void BuildTownLighthouses(", "static bool TryBuildCoastLighthouse(",
              "static void BuildCoastLighthouses(", "static bool TryBuildTransmitter(", "void GenerateObjects("):
        up+="\n"+extract(data["object_cmd.cpp"],f)
    fixtures=[]
    for w,h in [(64,64),(128,64),(64,128)]:
        for date,cap,seed,free in [(0,100,1,True),(701264,100,1947,False),(701265,100,0xFEDE1234,True),
                                   (710000,0,71,True),(710000,1,73,False),(720000,100,471,False)]:
            fixtures.extend(fixture(w,h,seed,free,date,cap))
    work=f"{len(fixtures)//4}\n"+"\n".join(fixtures)+"\n"
    with tempfile.TemporaryDirectory(prefix="rc1-scenery-") as d:
        tmp=Path(d)
        (tmp/"oracle.cpp").write_text(CPP+up+RUNNER)
        subprocess.run(["g++","-std=c++20","-O2",str(tmp/"oracle.cpp"),"-o",str(tmp/"oracle")],check=True)
        (tmp/"runner.lua").write_text(LUA)
        oracle=subprocess.run([str(tmp/"oracle")],input=work,text=True,capture_output=True,check=True).stdout
        try:
            result=subprocess.run([a.lua,str(tmp/"runner.lua"),str(ROOT/"mods/luanttd_core")+"/",str(a.clear)],
                                  input=work,text=True,capture_output=True,check=True).stdout
        except subprocess.CalledProcessError as e:
            raise RuntimeError(e.stderr) from e
        expected=oracle.splitlines()
        have=result.splitlines()
        for i,(left,right) in enumerate(zip(expected,have,strict=True)):
            assert left==right,(f"Case {i//3+1}, row {i%3+1} differs: "
                                f"source {left[:160]!r}, native {right[:160]!r}")
        assert any(",0," in r for r in expected[1::3]) and any(",1," in r for r in expected[1::3])
        before=work.splitlines()[3::4]
        before_counts=[sum(m.split().count(str(v)) for m in before) for v in (4118,4134)]
        after_counts=[sum(m.split().count(str(v)) for m in expected[2::3]) for v in (4118,4134)]
        assert all(y>x for x,y in zip(before_counts,after_counts)), (before_counts,after_counts)
    print(f"RC1 scenery: matched {len(fixtures)//4} native/source boards, all placements, water rocks and RNG handoffs")

if __name__=="__main__":
    main()
