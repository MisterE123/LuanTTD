#!/usr/bin/env python3
"""Compile the 16.0-RC1 half-tile flood routine and its source foundations."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"


def block(file, pattern):
    raw = (src / file).read_text()
    begin = re.search(pattern, raw, re.M).start()
    opening = raw.index("{", begin)
    level = 1
    i = opening + 1
    while level:
        level += (raw[i] == "{") - (raw[i] == "}")
        i += 1
    return raw[begin:i] + (";" if raw[i:i+1] == ";" else "") + "\n"


shim = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <iostream>
#include <type_traits>
using uint=unsigned;
using TileIndex=int;
template<typename E> constexpr auto to_underlying(E e){return static_cast<std::underlying_type_t<E>>(e);}
#define NOT_REACHED() std::abort()
template<typename E> constexpr bool IsInsideMM(E i,E a,E b){return a<=i && i<b;}
constexpr uint TILE_HEIGHT=8;
"""
for pattern in (r"^enum class Corner :",r"^enum Slope :",r"^enum class Foundation :"):
    shim += block("slope_type.h",pattern)
shim += r"""
constexpr Slope operator~(Slope s){return Slope(~int(s));}
constexpr Slope operator&(Slope a,Slope b){return Slope(int(a)&int(b));}
constexpr Slope operator|(Slope a,Slope b){return Slope(int(a)|int(b));}
constexpr Slope operator^(Slope a,Slope b){return Slope(int(a)^int(b));}
enum class Track {X,Y,Upper,Lower,Left,Right};
struct TrackBits {
 int n=0;
 constexpr TrackBits()=default;
 constexpr TrackBits(int n):n(n){}
 constexpr TrackBits(Track t):n(1<<int(t)){}
 constexpr TrackBits(std::initializer_list<Track> ts){for(Track t:ts)n|=1<<int(t);}
 constexpr bool None() const{return n==0;}
 constexpr bool Any() const{return n!=0;}
 constexpr bool Any(TrackBits t)const{return (n&t.n)!=0;}
 constexpr TrackBits& Reset(TrackBits t){n&=~t.n;return *this;}
 constexpr int base()const{return n;}
};
constexpr TrackBits operator&(TrackBits a,TrackBits b){return a.n&b.n;}
constexpr TrackBits operator|(TrackBits a,TrackBits b){return a.n|b.n;}
constexpr bool operator==(TrackBits a,TrackBits b){return a.n==b.n;}
constexpr TrackBits TRACK_BIT_ALL=63, TRACK_BIT_HORZ=12, TRACK_BIT_VERT=48;
constexpr bool TracksOverlap(TrackBits t) {
  return t.Any() && (t.n & (t.n-1)) && t.n!=12 && t.n!=48;
}
constexpr TrackBits CornerToTrackBits(Corner c) {return std::array{16,8,32,4}[to_underlying(c)];}
template<class T> using NonSteepSlopeIndexArray=std::array<T,15>;
"""
for name in ("IsValidCorner", "IsSteepSlope", "IsHalftileSlope", "RemoveHalftileSlope",
             "ComplementSlope", "IsSlopeWithOneCornerRaised", "SlopeWithOneCornerRaised",
             "GetHighestSlopeCorner", "OppositeCorner", "IsSlopeWithThreeCornersRaised",
             "SlopeWithThreeCornersRaised", "HalftileSlope", "IsFoundation", "IsLeveledFoundation",
             "IsNonContinuousFoundation", "GetHalftileFoundationCorner", "IsSpecialRailFoundation",
             "GetRailFoundationCorner", "HalftileFoundation", "SpecialRailFoundation"):
    shim += block("slope_func.h",r"^(?:static constexpr |inline )\w+ " + name + r"\(")
shim += block("rail_cmd.cpp",r"^static constexpr NonSteepSlopeIndexArray<TrackBits> _valid_tracks_without_foundation")
shim += block("rail_cmd.cpp",r"^static constexpr NonSteepSlopeIndexArray<TrackBits> _valid_tracks_on_leveled_foundation").replace("{{{","{{").replace("}}}","}}")
shim += block("rail_cmd.cpp",r"^Foundation GetRailFoundation")
shim += block("landscape.cpp",r"^uint ApplyFoundationToSlope")
shim += block("rail_map.h",r"^enum class RailGroundType :")
shim += r"""
static Slope raw;
static TrackBits bits;
static RailGroundType ground;
static bool coast;
static int removed,allowed,tries;
bool IsPlainRailTile(TileIndex){return true;}
RailGroundType GetRailGroundType(TileIndex){return ground;}
void SetRailGroundType(TileIndex,RailGroundType g){ground=g;}
Slope GetTileSlope(TileIndex){return raw;}
TrackBits GetTrackBits(TileIndex){return bits;}
Track FindFirstTrack(TrackBits t){for(int i=0;i<6;i++)if(t.n&(1<<i))return Track(i);std::abort();}
enum class DoCommandFlag{Execute};
enum class Commands{RemoveRail};
int _current_company;
constexpr int OWNER_WATER=0;
struct AutoRestoreBackup{AutoRestoreBackup(int,int){}};
struct Result{bool Succeeded()const{return allowed;}};
template<Commands C> struct Command{
 static Result Do(DoCommandFlag,TileIndex,Track t){++tries;if(allowed){removed=1<<int(t);bits.Reset(t);}return {};}
};
void MakeShore(TileIndex){coast=true;}
void MarkTileDirtyByTile(TileIndex){}
"""
shim += block("rail_cmd.cpp",r"^bool FloodHalftile\(")
main = r"""
int main(){
  for(int shape: {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30})
    for(int mask=1;mask<64;mask++)
      if(GetRailFoundation(Slope(shape),mask)!=Foundation::Invalid)
        for(int g:{0,1,13})for(allowed=0;allowed<2;allowed++){
          raw=Slope(shape);bits=mask;ground=RailGroundType(g);coast=false;removed=0;tries=0;
          bool changed=FloodHalftile(0);
          std::cout<<shape<<" "<<mask<<" "<<g<<" "<<allowed<<" "<<changed<<" "<<coast<<" "
                   <<bits.n<<" "<<int(ground)<<" "<<removed<<" "<<tries<<"\n";
        }
}
"""
lua = r"""
local m="mods/luanttd_core/openttd/"
local W=dofile(m.."rail_half_water.lua")(dofile(m.."rail_track.lua"),dofile(m.."slope.lua"))
local cases=0
for row in io.lines() do
 local v={};for n in row:gmatch("%d+") do v[#v+1]=tonumber(n)end
 local shape,in_bits,in_ground,allow,changed,coast,bits,ground,removed,tries=unpack(v)
 local attempts=0
 local q=W.flood(shape,in_bits,in_ground,function()
   attempts=attempts+1
   return allow==1
 end)
 assert(attempts==tries and (not not q)==(changed==1),row)
 if q then
   assert((q.kind=="coast")==(coast==1) and (q.tracks or 0)==bits
      and (q.ground or in_ground)==ground and (q.removed or 0)==removed,row)
 end
 cases=cases+1
end
assert(cases>1700)
print(("PASS %d compiled RC1 FloodHalftile transitions, including foundation legality and denied removal"):format(cases))
"""
with tempfile.TemporaryDirectory() as td:
    cpp, exe = Path(td) / "rail.cpp", Path(td) / "rail"
    cpp.write_text(shim + main)
    subprocess.run(["g++", "-O2", "-std=c++20", str(cpp), "-o", str(exe)], check=True)
    fixture = subprocess.check_output([exe])
    script = Path(td) / "verify.lua"
    script.write_text(lua)
    subprocess.run([a.lua, script], input=fixture, check=True)
