#!/usr/bin/env python3
"""Differential test for the Temperate suffix of OpenTTD RC1 TileLoop_Rail."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"
raw = (src / "rail_cmd.cpp").read_text()
begin = raw.index("static void TileLoop_Rail(TileIndex tile)")
begin = raw.index("\tnew_ground = RailGroundType::Grass;", begin)
end = raw.index("\nset_ground:", begin)
algorithm = raw[begin:end]
ground_decl = re.search(r"enum class RailGroundType\s*:\s*uint8_t\s*\{.*?\n\};",
                        (src / "rail_map.h").read_text(), re.S)[0]
defs = "\n".join(re.findall(r"static constexpr TrackBits TRACK_BIT_3WAY_\w+ = \{.*?\};",
                           (src / "track_type.h").read_text()))
assert len(defs.splitlines()) == 4 and "OBJECT_OWNED_LAND" in algorithm
shim = r"""
#include <array>
#include <cstdint>
#include <initializer_list>
#include <iostream>
enum class Track { X,Y,Upper,Lower,Left,Right };
struct TrackBits {
  int n;
  constexpr TrackBits(int n): n(n) {}
  constexpr TrackBits(std::initializer_list<Track> bits): n(0) {
    for (auto b: bits) n |= 1 << int(b);
  }
  constexpr bool Any(TrackBits m) const { return (n&m.n)!=0; }
};
enum class DiagDirection { NE,SE,SW,NW,End };
struct DiagDirections {
  int n=0;
  constexpr DiagDirections() {}
  constexpr DiagDirections(std::initializer_list<DiagDirection> ds) { for(auto d: ds) Set(d); }
  constexpr void Set(DiagDirection d) { n |= 1<<int(d); }
  constexpr int base() const { return n; }
};
template<class T> struct DiagDirectionIndexArray {
  std::array<T,4> rows;
  constexpr DiagDirectionIndexArray(T a,T b,T c,T d): rows{a,b,c,d} {}
  constexpr const T &operator[](DiagDirection d) const { return rows[int(d)]; }
};
constexpr auto EnumRange(DiagDirection) { return std::array{DiagDirection::NE,DiagDirection::SE,DiagDirection::SW,DiagDirection::NW}; }
using TileIndex = int;
using Owner = int;
enum class TileType { Clear, House, Industry, Road, Object, TunnelBridge, Railway };
constexpr int OBJECT_OWNED_LAND=1;
struct Cell { TileType type; Owner owner; bool valid=true; bool land=false; };
constexpr std::array<Cell,8> choices{{
  {TileType::Railway,1}, {TileType::Railway,2}, {TileType::Clear,0,false},
  {TileType::House,1}, {TileType::Industry,1}, {TileType::Road,1},
  {TileType::Object,1,true,true}, {TileType::TunnelBridge,1}
}};
static std::array<Cell,5> board;
static int tracks;
static bool IsPlainRail(TileIndex) {return true;}
static TrackBits GetTrackBits(TileIndex) {return tracks;}
static Owner GetTileOwner(TileIndex t) {return board[t].owner;}
static int TileOffsByDiagDir(DiagDirection d) {return int(d)+1;}
static bool IsValidTile(TileIndex t) {return board[t].valid;}
static bool IsTileType(TileIndex t,TileType ty) {return board[t].type==ty;}
static bool IsObjectType(TileIndex t,int) {return board[t].land;}
static bool IsTileOwner(TileIndex t,Owner o) {return GetTileOwner(t)==o;}
[[noreturn]] static void NOT_REACHED(){throw 1;}
"""
main = r"""
static RailGroundType rule(){
  auto old_ground=RailGroundType::Grass;
  RailGroundType new_ground;
  constexpr TileIndex tile=0;
  """ + algorithm + """
  return new_ground;
}
int main() {
  board[0]=choices[0];
  for(tracks=1;tracks<64;tracks++) for(int combination=0;combination<4096;combination++){
    int v=combination;
    for(int d=0;d<4;d++,v/=8) board[d+1]=choices[v%8];
    std::cout.put(char(rule()));
  }
}
"""
lua = r"""
local base="mods/luanttd_core/openttd/"
local rules=dofile(base.."rail_ground_temperate.lua")(dofile(base.."rail_track.lua"))
local options={[0]={kind="rail",owner=1},{kind="rail",owner=2},false,
  {kind="house",owner=1},{kind="industry",owner=1},{kind="road",owner=1},
  {kind="object",owner=1,owned_land=true},{kind="tunnelbridge",owner=1}}
local here={owner=1,plain=true,ground=1}
local out={}
local n
local function neighbor(d) return options[math.floor(n/8^d)%8] end
for bits=1,63 do
  here.tracks=bits
  for value=0,4095 do n=value;out[#out+1]=string.char((rules.visit(here,neighbor))) end
end
io.write(table.concat(out))
"""
with tempfile.TemporaryDirectory() as td:
    source = Path(td) / "oracle.cpp"
    exe = Path(td) / "oracle"
    source.write_text(shim + "\n" + ground_decl + "\n" + defs + "\n" + main)
    subprocess.run(["g++", "-std=c++20", "-O2", str(source), "-o", str(exe)], check=True)
    native = subprocess.check_output([exe])
actual = subprocess.run([a.lua, "-"], input=lua.encode(), stdout=subprocess.PIPE, check=True).stdout
assert len(native) == len(actual) == 63 * 4096
assert native == actual, "Temperate plain rail ground diverges from compiled OpenTTD"
print(f"PASS {len(native):,} compiled RC1 Temperate rail representations and edge/neighbor combinations")
