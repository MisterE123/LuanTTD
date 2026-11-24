#!/usr/bin/env python3
"""Compare the RC1 clear-ground pass, including wet rocks and RNG cursor."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    "clear_cmd.cpp": "f7371b59b0ad26b5b0c7d24f9eff7fad5b5dc8d57500fdd2599e5e0af47cd7ae",
    "core/random_func.cpp": "1b8795fb038cb6c19eeea2d37a41dc12d5a83509eff857b5a5f9131fd7793f75",
}
CPP = r"""
#include <bit>
#include <cstdint>
#include <iostream>
#include <vector>
using uint = unsigned;
using TileIndex = int;
enum class TileType { Clear=0, Water=6, Void=7 };
enum class WaterTileType { Clear, Coast, ClearRocks, CoastRocks };
enum class ClearGround { Grass=0, Rough=1, Rocks=2, Desert=5 };
enum class DiagDirection { NE, SE, SW, NW, End };
enum class GenWorldProgress { RoughAndRocks };
struct Randomizer { uint32_t state[2]; uint32_t Next(); } rng;
std::vector<int> tiles;
int width, depth, rough, rocky;
uint32_t Random() { return rng.Next(); }
DiagDirection RandomRange(DiagDirection n) {
    return static_cast<DiagDirection>((uint64_t(Random()) * uint32_t(n)) >> 32);
}
uint32_t GB(uint32_t v, int start, int bits) { return (v >> start) & ((1U << bits) - 1); }
struct Map {
    static uint ScaleBySize(uint n) { return (n*width*depth+65535)/65536; }
};
TileType GetTileType(int i) { return static_cast<TileType>(tiles[i] & 15); }
bool IsTileType(int i, TileType t) { return GetTileType(i)==t; }
bool IsValidTile(int i) { return i>=0 && size_t(i)<tiles.size() && !IsTileType(i,TileType::Void); }
int GroundWater(int i) { return (tiles[i] >> 4) & 15; }
bool IsCoast(int i) { return GroundWater(i)==2; }
bool IsSea(int i) { return GroundWater(i)==1 && !(tiles[i] & 4096); }
bool IsRiver(int i) { return GroundWater(i)==3 && !(tiles[i] & 4096); }
bool IsClearGround(int i, ClearGround t) { return (tiles[i]>>8 & 15)==int(t); }
void SetClearGroundDensity(int i, ClearGround t, int) { tiles[i]=(tiles[i]&255)|int(t)<<8; }
void SetWaterTileType(int i, WaterTileType t) {
    tiles[i] = (tiles[i]&4095) | (t==WaterTileType::ClearRocks || t==WaterTileType::CoastRocks ? 4096 : 0);
}
int RandomTileSeed(uint32_t r) { return r % (width*depth); }
int TileOffsByDiagDir(DiagDirection d) {
    int offset[4] = {-1,width,1,-width};
    return offset[int(d)];
}
void MarkTileDirtyByTile(int) {}
void SetGeneratingWorldProgress(GenWorldProgress, int total) { rough=total; }
void IncreaseGeneratingWorldProgress(GenWorldProgress) {}
"""

LUA = r"""
local p=arg[1]
local C=dofile(p.."terragenesis_clear_rc1.lua")
local G=dofile(p.."terragenesis.lua")(dofile(p.."slope.lua"))
local n=io.read("*n")
for i=1,n do
  local w,h,a,b=io.read("*n","*n","*n","*n")
  local tiles={}
  for j=1,w*h do tiles[j]=io.read("*n") end
  local base={width=w,depth=h,seed=0,base_id="fixture",rng_after={a,b},
    tile=function(x,z) return tiles[(z-1)*w+x] end}
  local out=C.generate(base,G.next_random)
  local words={}
  for z=1,h do for x=1,w do
    local word=out.tile(x,z)
    local k,water,cover,rocks=C.describe(word)
    local before=tiles[(z-1)*w+x]
    assert(not rocks or k==6 and (water==1 or water==2))
    assert(before~=54 or word==before,"River overwritten")
    words[#words+1]=word
  end end
  print(string.format("%.0f %.0f %d",out.rng_after[1],out.rng_after[2],
    out.clear_attempts.rough+out.clear_attempts.rocky))
  io.write(table.concat(words," "),"\n")
end
"""

def extract(text, name):
    start = text.index(name)
    return text[start:text.index("\n}", start)+2]

def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    parser.add_argument("--kernel", type=Path, default=ROOT / "mods/luanttd_core/openttd")
    args = parser.parse_args()
    src = args.source / "src" if (args.source / "src").is_dir() else args.source
    data = {}
    for file, pin in PINS.items():
        raw = (src / file).read_bytes()
        assert sha256(raw).hexdigest() == pin, f"Wrong upstream source: {file}"
        data[file] = raw.decode()
    upstream = extract(data["core/random_func.cpp"],"uint32_t Randomizer::Next()")
    for name in ("static bool TileMayHaveRocks(", "static void TileMakeRocks(", "void GenerateRocks(",
                 "static bool TileMayHaveRough(", "static void GenerateRough(", "void GenerateClearTile("):
        upstream += "\n" + extract(data["clear_cmd.cpp"],name)
    runner = r"""
int main() {
    int maps;
    std::cin >> maps;
    while (maps--) {
        std::cin >> width >> depth >> rng.state[0] >> rng.state[1];
        tiles.resize(width*depth);
        for (auto &tile: tiles) std::cin >> tile;
        GenerateClearTile();
        std::cout << rng.state[0] << ' ' << rng.state[1] << ' ' << rough << '\n';
        for (size_t i=0; i < tiles.size(); i++)
            std::cout << tiles[i] << (i == tiles.size()-1 ? '\n' : ' ');
    }
}
"""
    fixtures = []
    for w,h in [(64,64),(64,128),(128,64),(256,256)]:
        for seed in [1,1947,0xFFFFFEDC]:
            header = f"{w} {h} {seed} {seed ^ 0x871F314C}"
            words = []
            for z in range(h):
                for x in range(w):
                    boundary = x in (0,w-1) or z in (0,h-1)
                    shift = (3*z + z//4 + seed)%5
                    # Alternating shore/sea/river on a mixed clear/void board.
                    band = (x+shift)%11
                    words.append(7 if boundary else
                                 {0:22,1:38,2:54,3:38,8:1280}.get(band,0))
            fixtures.extend([header," ".join(map(str,words))])
    work = f"{len(fixtures)//2}\n" + "\n".join(fixtures) + "\n"
    with tempfile.TemporaryDirectory(prefix="rc1-clear-") as name:
        tmp=Path(name)
        (tmp/"oracle.cpp").write_text(CPP + upstream + runner)
        subprocess.run(["g++","-std=c++20","-O2",str(tmp/"oracle.cpp"),"-o",str(tmp/"oracle")],
                       check=True)
        (tmp/"compare.lua").write_text(LUA)
        output=subprocess.run([str(tmp/"oracle")],input=work,text=True,check=True,capture_output=True).stdout
        got=subprocess.run([args.lua,str(tmp/"compare.lua"),str(args.kernel)+"/"],input=work,text=True,
                           check=True,capture_output=True).stdout
        assert output==got, "Native map or RNG cursor differs from the compiled 16.0-RC1 source"
        by_word = output.split()
        for word in (256,512,4118,4134,54,1280):
            assert str(word) in by_word,f"Missing differential coverage for map word {word}"
    print(f"RC1 clear pass: matched {len(fixtures)//2} full maps and RNG cursors, including coast/open-water rocks")

if __name__=="__main__":
    main()
