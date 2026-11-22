"""Differential test pinned OpenTTD 14.1 rail track tables and foundations.

python tests/rail_track_upstream.py SOURCE_TREE [lua5.1]
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIGEST = {
    "rail.cpp":"1d990c0a35ef14c1fc072ace3952734bac087f7981d18943932a96de8e1f0887",
    "rail_cmd.cpp":"09c9ddedb7d94af9f21bcb2f71859f93b96bf9dbaab9d5eb1da51de11d9972d9",
    "rail.h":"c35b8b5a3de670a526567960c1fec17799291b0431babdd952634285522342aa",
    "slope_type.h":"3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9",
    "track_type.h":"db919468ff6a319383fe936d081933048c8c23d97ea95c869b269e404059b9e8",
    "track_func.h":"1b49b94fe0f759fba9cc80b79f52f58c9c35cffaf42e0fe14b92b9b893453ca5",
    "direction_type.h":"d1cdad0afebbf6dce3d73d742ea352129ab05f0b5af30a5ba216b7030e6a085c",
    "pathfinder/follow_track.hpp":"9c2c48e093c73f3cdf2c669757e5669543433a6b040eda36945b4960365fd39f",
    "pathfinder/pathfinder_func.h":"d375de0d34da01f97a9dcebaae049df204072370220213df1d667ca401094835",
    "road_type.h":"ad06673a815b4dd3418f3353e990a25a64ba59b38b132d195c09e5ef55e4f7f0",
    "road_cmd.cpp":"a693439b151a675b79ffff11d97d481931524872a02e8b4818ce6dd20430b2e3",
    "station_cmd.cpp":"7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5",
    "tunnelbridge_cmd.cpp":"48b5401e1262964cb961b266a4dd0cf81d171a7f60e264597be8e4f138fad305",
    "station_map.h":"6807df99dc7f0d320fdefb32b5c2536b54fe8f9141f35d17a624a17bcd2af671",
    "station.cpp":"0c4d82f845fcf2ddb246668415e78dfbaa17ab5d939f702c6c0209bf5feaab42",
}


def src(source, path):
    options = (source / "src" / path, source / path, source / Path(path).name)
    actual = next((p for p in options if p.is_file()), options[0])
    content = actual.read_bytes()
    assert sha256(content).hexdigest() == DIGEST[path], f"{actual}: not OpenTTD 14.1"
    return content.decode()


def block(source, pattern):
    start = re.search(pattern, source, re.MULTILINE).start()
    i = source.index("{", start)
    depth = 1
    while depth:
        i += 1
        depth += (source[i] == "{") - (source[i] == "}")
    return source[start:i+1] + "\n"


def declarations(source, patterns):
    return "".join(block(source, r"^" + p) + ";\n" for p in patterns)


def main():
    source = Path(sys.argv[1])
    rail, cmd = (src(source,p) for p in ("rail.cpp","rail_cmd.cpp"))
    bits, funcs, direction, slope = (src(source,p) for p in
        ("track_type.h","track_func.h","direction_type.h","slope_type.h"))
    cpp = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
using byte=unsigned char;
using uint=unsigned;
using TileIndex=int;
using TrackStatus=uint32_t;
#define NOT_REACHED() std::abort()
"""
    cpp += declarations(direction, [r"enum Direction\s*:", r"enum DiagDirection\s*:"])
    cpp += declarations(slope, [r"enum Corner\s*\{", r"enum Slope\s*:", r"enum Foundation\s*\{"])
    cpp += declarations(bits, [r"enum Track\s*:",r"enum TrackBits",r"enum Trackdir\s*:",r"enum TrackdirBits"])
    cpp += r"""
#define BITOPS(T) \
 T operator|(T a,T b) {return T(int(a)|int(b));} \
 T operator&(T a,T b) {return T(int(a)&int(b));} \
 T operator~(T a) {return T(~int(a));} \
 T& operator|=(T &a,T b) {return a=a|b;} \
 T& operator&=(T &a,T b) {return a=a&b;}
BITOPS(TrackBits)
BITOPS(TrackdirBits)
"""
    cpp += declarations(rail, [r"extern const .* "+name for name in (
        "_trackdir_to_exitdir","_track_exitdir_to_trackdir","_track_enterdir_to_trackdir",
        "_track_direction_to_trackdir","_track_crosses_trackdirs","_exitdir_reaches_trackdirs",
        "_next_trackdir","_dir_to_diag_trackdir","_uphill_trackdirs","_signal_on_track",
        "_signal_along_trackdir","_signal_against_trackdir","_corner_to_trackbits")])
    cpp += r"""
constexpr TrackBits KillFirstBit(TrackBits b){ return TrackBits(b & (b-1)); }
bool IsSteepSlope(Slope s){return s & SLOPE_STEEP;}
bool IsHalftileSlope(Slope s){return s & SLOPE_HALFTILE;}
Slope RemoveHalftileSlope(Slope s){return Slope(s & ~SLOPE_HALFTILE_MASK);}
bool IsValidCorner(Corner c){return c>=0 && c<CORNER_END;}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
Slope SlopeWithOneCornerRaised(Corner c){return Slope(1<<c);}
Slope ComplementSlope(Slope s){return Slope(s^15);}
TrackBits CornerToTrackBits(Corner c){return _corner_to_trackbits[c];}
TrackBits DiagDirToDiagTrackBits(DiagDirection d){return TrackBits(1<<(d&1));}
TrackdirBits TrackBitsToTrackdirBits(TrackBits b){return TrackdirBits(b*257);}
TrackStatus CombineTrackStatus(TrackdirBits b,TrackdirBits red){return unsigned(b)|(unsigned(red)<<16);}
"""
    cpp += block(funcs,r"^inline bool TracksOverlap")
    sf = (source / "src" / "slope_func.h")
    if not sf.is_file(): sf=source/"slope_func.h"
    raw = sf.read_bytes()
    assert sha256(raw).hexdigest()=="1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a"
    for kind, name in (("Corner","GetHighestSlopeCorner"),("Corner","OppositeCorner"),
                       ("bool","IsSlopeWithThreeCornersRaised"),("Slope","SlopeWithThreeCornersRaised"),
                       ("Foundation","HalftileFoundation"),("Foundation","SpecialRailFoundation")):
        cpp+=block(raw.decode(),rf"^inline {kind} {name}\(")
    cpp += declarations(cmd,[r"static const TrackBits _valid_tracks_without_foundation",
                              r"static const TrackBits _valid_tracks_on_leveled_foundation"])
    cpp += block(cmd,r"^Foundation GetRailFoundation")
    cpp += r"""
constexpr int FLOOD_NONE=0, EXPENSES_CONSTRUCTION=0, PR_BUILD_FOUNDATION=0;
constexpr int STR_ERROR_CAN_T_BUILD_ON_WATER=-2, STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION=-3;
using Money=int;
struct CommandCost {int value; CommandCost(int, int value):value(value){}};
#define return_cmd_error(v) return CommandCost(0,v)
const int _price[]={1};
struct {struct {bool build_on_slopes;} construction;} _settings_game;
int GetFloodingBehaviour(TileIndex tile){return tile;}
enum TransportType {TRANSPORT_RAIL,TRANSPORT_ROAD,TRANSPORT_WATER};
enum {RAIL_TILE_NORMAL,RAIL_TILE_SIGNALS,RAIL_TILE_DEPOT};
int bits_or_axis,present_sigs,green_sigs,upper_pbs,lower_pbs;
bool IsPlainRail(TileIndex){return true;}
constexpr int RAIL_GROUND_WATER=0;
int GetRailGroundType(TileIndex){return -1;}
Slope GetTileSlope(TileIndex){return SLOPE_FLAT;}
int GetRailTileType(TileIndex id){return id;}
TrackBits GetTrackBits(TileIndex){return TrackBits(bits_or_axis);}
byte GetPresentSignals(TileIndex){return present_sigs;}
uint GetSignalStates(TileIndex){return green_sigs;}
bool IsOnewaySignal(TileIndex,Track tr){return !(tr==TRACK_UPPER?upper_pbs:lower_pbs);}
byte SignalOnTrack(Track tr){return _signal_on_track[tr];}
DiagDirection GetRailDepotDirection(TileIndex){return DiagDirection(bits_or_axis);}
"""
    cpp += block(cmd,r"^static CommandCost CheckRailSlope")
    cpp += block(cmd,r"^static TrackStatus GetTileTrackStatus_Track")
    cpp += r"""
int main(){
 for(int t=0;t<6;++t)for(int d=0;d<4;++d){
  std::cout<<"D "<<t<<" "<<d<<" "<<int(_track_exitdir_to_trackdir[t][d])<<" "
           <<int(_track_enterdir_to_trackdir[t][d])<<" "<<_exitdir_reaches_trackdirs[d]<<" "
           <<int(_dir_to_diag_trackdir[d])<<"\n";
 }
 for(int t=0;t<14;++t)if(t%8<6)
  std::cout<<"T "<<t<<" "<<int(_trackdir_to_exitdir[t])<<" "<<int(_next_trackdir[t])<<" "
           <<_track_crosses_trackdirs[t%8]<<" "<<int(_signal_along_trackdir[t])
           <<" "<<int(_signal_against_trackdir[t])<<"\n";
 for(int s=0;s<31;++s){
  std::cout<<"U "<<s<<" "<<_uphill_trackdirs[s]<<"\n";
  if(s==15 || (s>=16 && s!=23 && s!=27 && s!=29 && s!=30))continue;
  for(int b=0;b<64;++b){
   std::cout<<"F "<<s<<" "<<b<<" "<<GetRailFoundation(Slope(s),TrackBits(b))<<"\n";
   for(int e=0;e<64;++e)for(int on=0;on<2;++on)for(int flood=0;flood<2;++flood){
    _settings_game.construction.build_on_slopes=on;
    std::cout<<"B "<<s<<" "<<b<<" "<<e<<" "<<on<<" "<<flood<<" "
             <<CheckRailSlope(Slope(s),TrackBits(b),TrackBits(e),flood).value<<"\n";
   }
  }
 }
 for(int present=0;present<16;++present)for(int green=0;green<16;++green)
 for(int upper=0;upper<2;++upper)for(int lower=0;lower<2;++lower){
   present_sigs=present;green_sigs=green;upper_pbs=upper;lower_pbs=lower;bits_or_axis=63;
   auto out=GetTileTrackStatus_Track(RAIL_TILE_SIGNALS,TRANSPORT_RAIL,0,INVALID_DIAGDIR);
   std::cout<<"S "<<present<<" "<<green<<" "<<upper<<" "<<lower<<" "<<(out&65535)<<" "<<(out>>16)<<"\n";
 }
}
"""
    lua = r"""
local R=dofile("mods/luanttd_core/openttd/rail_track.lua")
local f={[0]="none","leveled","x","y","steep_lower","steep_both"}
local counts={}
for line in io.lines() do
  local cmd=line:sub(1,1)
  local q={}
  for x in line:gmatch("-?%d+") do q[#q+1]=tonumber(x) end
  if cmd=="D" then
    assert((R.trackdir_for_exit(q[1],q[2]) or 255)==q[3],line)
    assert((R.trackdir_for_entry(q[1],q[2]) or 255)==q[4],line)
    assert(R.reachable(q[2])==q[5] and R.diagonal_trackdir(q[2])==q[6],line)
    if q[4]~=255 then assert(R.entry_side(q[4])==R.reverse_side(q[2]),line) end
  elseif cmd=="T" then
    assert(R.exit_side(q[1])==q[2] and R.next_trackdir(q[1])==q[3],line)
    assert(R.crossing_trackdirs(q[1])==q[4] and R.signal_along(q[1])==q[5] and R.signal_against(q[1])==q[6],line)
  elseif cmd=="U" then
    assert(R.uphill_trackdirs(q[1])==q[2],line)
  elseif cmd=="F" then
    local k,c=R.foundation(q[1],q[2])
    local code=q[3]
    local expect=code==255 and "invalid" or f[code] or (code>=10 and "rail" or "half")
    assert(k==expect and c==(code>=6 and code<14 and (code-6)%4 or nil),line)
  elseif cmd=="B" then
    local ok,a,_,charge=R.build_slope(q[1],q[2],q[3],q[5]==1,q[4]==1)
    local n=ok and (charge and 1 or 0) or (a=="water" and -2 or -3)
    assert(n==q[6],line)
  elseif cmd=="S" then
    local b,r=R.status{kind="signals",trackbits=63,present_signals=q[1],green_signals=q[2],
                       upper_pbs=q[3]==1,lower_pbs=q[4]==1}
    assert(b==q[5] and r==q[6],line)
  else error(line) end
  counts[cmd]=(counts[cmd] or 0)+1
end
assert(counts.D==24 and counts.T==12 and counts.F==1216 and counts.B==311296 and counts.S==1024 and counts.U==31)
print(("PASS: %d track/status/slope cases against pinned OpenTTD 14.1"):format(
  counts.D+counts.T+counts.U+counts.F+counts.B+counts.S))
"""
    with tempfile.TemporaryDirectory() as where:
        p = Path(where)
        (p/"ref.cpp").write_text(cpp)
        (p/"verify.lua").write_text(lua)
        subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
        with subprocess.Popen([p/"ref"],stdout=subprocess.PIPE) as ref:
            subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],cwd=ROOT,stdin=ref.stdout,check=True)
            assert ref.wait()==0


if __name__ == "__main__":
    main()
