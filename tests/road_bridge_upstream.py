#!/usr/bin/env python3
"""Check stock 14.1 bridge math, availability, ramp geometry and price constants.

Usage: python3 tests/road_bridge_upstream.py /path/to/OpenTTD [lua5.1]
Extracts unmodified C++ kernel functions and stock data from hash-pinned
files. The tile and economy shims provide fixtures, not a running game.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[1]
checkout = Path(sys.argv[1])

def src(name, checksum):
    candidates = [checkout / "src" / name, checkout / name, checkout / Path(name).name]
    p = next((p for p in candidates if p.is_file()), candidates[0])
    data = p.read_bytes()
    assert sha256(data).hexdigest() == checksum, f"{p}: not pinned OpenTTD 14.1"
    return data.decode()

def block(source, pattern):
    start = re.search(pattern, source, re.MULTILINE).start()
    at = source.index("{", start)
    depth = 1
    while depth:
        at += 1
        depth += (source[at] == "{") - (source[at] == "}")
    return source[start:at + 1]

bridge = src("tunnelbridge_cmd.cpp", "48b5401e1262964cb961b266a4dd0cf81d171a7f60e264597be8e4f138fad305")
catalog = src("table/bridge_land.h", "95b5bc37b87fde7f85f736730150eac5a665356a081ba7f92270cde1b326b597")
slope = src("slope_type.h", "3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9")
func = src("slope_func.h", "1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a")
land = src("landscape.cpp", "0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97")
settings = src("table/world_settings.ini", "4c08978820994e9a975a1a135b9d1ebcf01764772e49ecc2ad2c71c05e93642e")
prices = src("table/pricebase.h", "17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356")
roads = src("road_type.h", "ad06673a815b4dd3418f3353e990a25a64ba59b38b132d195c09e5ef55e4f7f0")

cpp = r"""
#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <iostream>
using byte=uint8_t;
using uint=unsigned;
using TileIndex=int;
using BridgeType=int;
using DoCommandFlag=uint;
using RoadTypeLabel=uint32_t;
constexpr int TILE_HEIGHT=8;
constexpr int TILE_SIZE=16;
enum Axis {AXIS_X,AXIS_Y};
enum DiagDirection {DIAGDIR_NE, DIAGDIR_SE, DIAGDIR_SW, DIAGDIR_NW};
enum BridgePieces {BRIDGE_PIECE_NORTH,BRIDGE_PIECE_SOUTH};
constexpr int EXPENSES_CONSTRUCTION=1, PR_BUILD_FOUNDATION=0;
constexpr uint DC_QUERY_COST=1;
constexpr int STR_ERROR_BRIDGE_TOO_LONG=2;
int _price[1];
struct CommandCost {
 int error=0,amount=0;
 CommandCost()=default;
 CommandCost(int kind,int price):amount(price){}
 static CommandCost Error(int why){CommandCost c;c.error=why;return c;}
};
const auto CMD_ERROR=CommandCost::Error(1);
#define return_cmd_error(code) return CommandCost::Error(code)
#define NOT_REACHED() std::abort()
struct BridgeSpec {int avail_year,min_length,max_length,price,speed;};
#define MBR(y,mn,mx,p,s,...) {y,mn,mx,p,s}
struct TimerGameCalendar {static int year;};
int TimerGameCalendar::year;
struct {struct {int max_bridge_length;} construction;} _settings_game;
"""
cpp += block(catalog, r"^const BridgeSpec _orig_bridge") + ";\n"
cpp += r"""
constexpr int MAX_BRIDGES=sizeof(_orig_bridge)/sizeof(BridgeSpec);
const BridgeSpec *GetBridgeSpec(int id){return &_orig_bridge[id];}
"""
for rx in (r"^enum Corner", r"^enum Slope", r"^enum Foundation"):
    cpp+=block(slope,rx)+";\n"
cpp+=r"""
constexpr Slope operator|(Slope a,Slope b){return Slope(int(a)|int(b));}
constexpr Slope operator&(Slope a,Slope b){return Slope(int(a)&int(b));}
constexpr Slope operator~(Slope a){return Slope(~int(a));}
template<class A,class Z,class C> bool IsInsideMM(A a,Z z,C c){return a>=z&&a<c;}
constexpr bool IsValidCorner(Corner c){return int(c)>=0 && int(c)<4;}
bool IsSteepSlope(Slope s){return (s&SLOPE_STEEP)!=0;}
int GetSlopeMaxPixelZ(Slope s){return (IsSteepSlope(s)?2:s==SLOPE_FLAT?0:1)*TILE_HEIGHT;}
Corner OppositeCorner(Corner c){return Corner((c+2)%4);}
Slope SlopeWithThreeCornersRaised(Corner c){return Slope(15 ^ (1<<c));}
"""
for function in ("IsHalftileSlope", "RemoveHalftileSlope", "IsSlopeWithOneCornerRaised", "SlopeWithOneCornerRaised",
                 "HasSlopeHighestCorner", "GetHighestSlopeCorner", "GetHalftileSlopeCorner", "HalftileSlope",
                 "IsFoundation","IsLeveledFoundation","IsNonContinuousFoundation","GetHalftileFoundationCorner",
                 "IsSpecialRailFoundation","GetRailFoundationCorner","FlatteningFoundation","InclinedFoundation"):
    cpp+=block(func, r"^(?:static constexpr )?inline \w+ "+function+r"\(")+"\n"
for rx in (r"^uint ApplyFoundationToSlope", r"^uint GetPartialPixelZ"):
    cpp += block(land,rx)+"\n"
cpp += r"""
Slope mock_tileh;
DiagDirection mock_dir;
int mock_base;
bool IsTunnel(TileIndex){return false;}
DiagDirection GetTunnelBridgeDirection(TileIndex){return mock_dir;}
Axis DiagDirToAxis(DiagDirection d){return Axis(d%2);}
Slope GetTilePixelSlope(TileIndex,int *h){*h=mock_base*8;return mock_tileh;}
int ApplyPixelFoundationToSlope(Foundation f,Slope *s){return 8*ApplyFoundationToSlope(f,s);}
"""
for rx in (r"^int CalcBridgeLenCostFactor", r"^Foundation GetBridgeFoundation", r"^bool HasBridgeFlatRamp",
           r"^static CommandCost CheckBridgeSlope", r"^CommandCost CheckBridgeAvailability", r"^static int GetSlopePixelZ_TunnelBridge"):
    cpp+=block(bridge,rx)+"\n"
cpp += block(roads,r"^enum RoadType\s*:")+";\n"
defaults = {}
for k in ("max_bridge_length","max_bridge_height"):
    defaults[k] = int(re.search(r"var\s*=\s*construction\."+k+r"[\s\S]*?def\s*=\s*(\d+)",settings)[1])
for k in ("PR_BUILD_ROAD","PR_CLEAR_ROAD","PR_BUILD_BRIDGE","PR_CLEAR_BRIDGE","PR_BUILD_FOUNDATION"):
    defaults[k]=int(re.search(r"{\s*(\d+),[^\n]+///< "+k+r"\s*$",prices,re.MULTILINE)[1])
cpp+=r"""
int main(){
 std::cout<<"#CONSTANTS# "<<int(ROADTYPE_ROAD)<<" "<<int(ROADTYPE_TRAM)<<"\n";
 for(int i=0;i<MAX_BRIDGES;i++){const auto &b=_orig_bridge[i];
  std::cout<<i<<" "<<b.avail_year<<" "<<b.min_length<<" "<<b.max_length<<" "<<b.price<<" "<<b.speed<<"\n";}
 char mode;
 while(std::cin>>mode){
  int a,b,c,d,e,f,g;
  if(mode=='h'){
   std::cin>>a>>b>>c>>d>>e>>f>>g;
   auto axis=Axis(b); auto piece=BridgePieces(c);
   mock_tileh=Slope(a);mock_base=d;mock_dir=DiagDirection(c?(b?3:0):(b?1:2));
   auto s=mock_tileh;_price[0]=e;
   auto orig=GetBridgeFoundation(s,axis);
   auto result=CheckBridgeSlope(piece,axis,&s,&d);
   std::cout<<int(orig)<<" "<<int(s)<<" "<<d<<" "<<result.error<<" "<<result.amount<<" "
    <<int(HasBridgeFlatRamp(mock_tileh,axis))<<" "<<GetSlopePixelZ_TunnelBridge(0,f,g,true)<<"\n";
  } else if(mode=='a'){
   std::cin>>a>>b>>c>>d>>e;
   TimerGameCalendar::year=c;_settings_game.construction.max_bridge_length=d;
   std::cout<<CheckBridgeAvailability(a,b,e?DC_QUERY_COST:0).error<<"\n";
  } else {
   std::cin>>a;std::cout<<CalcBridgeLenCostFactor(a)<<"\n";
  }
 }
}
""".replace("#CONSTANTS#"," ".join(str(v) for v in defaults.values()))
lua = r"""
local B=dofile('mods/bayline/openttd/road_bridge.lua')(dofile('mods/bayline/openttd/slope.lua'))
local bv=B.base_prices
print(table.concat({B.default_max_length,B.default_max_height,bv.road,bv.clear_road,bv.bridge,
  bv.clear_bridge,bv.foundation,B.roadtypes[0].id,B.roadtypes[1].id},' '))
for n=0,12 do
 local s=B.catalog[n]
 print(table.concat({s.id,s.year,s.min_length,s.max_length,s.multiplier,s.speed},' '))
end
local codes={none=0,leveled=1,x=2,y=3}
local function bool(b) return b and 1 or 0 end
for line in io.lines() do
 local n={}
 for a in line:gmatch('%d+') do n[#n+1]=tonumber(a) end
 local mode=line:sub(1,1)
 if mode=='h' then
  local h=B.head(n[1],n[4],n[2],n[3]==0,n[5])
  print(table.concat({codes[h.foundation],h.foundation_slope,h.base,bool(not h.valid),
   h.foundation_cost,bool(h.flat_ramp),B.head_pixel_height(h,n[6],n[7])},' '))
 elseif mode=='a' then
  local ok,why=B.available(n[1],n[2],{year=n[3],max_length=n[4],query=n[5]~=0})
  print(ok and 0 or why=='BRIDGE_TOO_LONG' and 2 or 1)
 else
  print(B.length_factor(n[1]))
 end
end
"""
rng=random.Random(141)
samples=[]
for m in (*range(15),23,27,29,30):
    for axis in (0,1):
        for side in (0,1):
            for x in range(16):
                for z in range(16):
                    samples.append(f"h {m} {axis} {side} {rng.randrange(250)} {rng.randrange(500)} {x} {z}")
for _ in range(2000):
    values=[rng.randrange(17),rng.choice([0,1,2,3,5,7,8,10,64,1024]),rng.randrange(1910,2030),rng.randrange(1,70),rng.randrange(2)]
    samples.append("a "+" ".join(map(str,values)))
samples.extend(f"l {n}" for n in range(0,4097))
data=("\n".join(samples)+"\n").encode()
with tempfile.TemporaryDirectory() as temp:
    t=Path(temp)
    (t/"ref.cpp").write_text(cpp)
    (t/"adapter.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",str(t/"ref.cpp"),"-o",str(t/"ref")],check=True)
    cpp_output=subprocess.run([str(t/"ref")],input=data,capture_output=True,check=True).stdout.decode().splitlines()
    got=subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(t/"adapter.lua")],input=data,
                       capture_output=True,check=True,cwd=root).stdout.decode().splitlines()
    assert len(got)==len(cpp_output)==len(samples)+14
    for i,(a,b) in enumerate(zip(cpp_output,got)):
        assert a==b, (samples[i-14] if i>=14 else "catalog/constants",a,b)
    print(f"PASS: {len(samples)} stock OpenTTD 14.1 bridge cases, 13 styles and price/limit defaults")
