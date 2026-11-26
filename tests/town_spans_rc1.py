"""Compile the exact original RC1 municipal continuation and span search budgets."""
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
from rc1_rail_foundation_shim import source_block

tree = Path(sys.argv[1])
sha = "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
assert subprocess.check_output(["git", "-C", tree, "rev-parse", "HEAD"], text=True).strip() == sha
src = tree / "src"
cpp = r"""
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <vector>
using uint=unsigned;
using TileIndex=int;
using TileIndexDiff=int;
using RoadType=int;
using Slope=int;
constexpr int SLOPE_FLAT=0,MAX_BRIDGES=13;
constexpr int INVALID_RAILTYPE=-1;
enum class DiagDirection {West,South,East,North,End};
enum class TransportType {Road,Rail};
enum class TileType {Void,Clear,Water,Railway,Road,Station,TunnelBridge,Object};
enum class DoCommandFlag {Auto,NoWater,Execute};
struct DoCommandFlags {
  DoCommandFlags(std::initializer_list<DoCommandFlag> f={}) {for (auto x:f) Set(x);}
  DoCommandFlags &Set(DoCommandFlag x) {if (x==DoCommandFlag::Execute) execute=true;return *this;}
  bool execute=false;
};
enum class Commands{BuildRoad,BuildBridge,BuildTunnel};
struct CommandCost { bool ok;bool Failed()const{return !ok;}bool Succeeded()const{return ok;} };
enum class Axis{X,Y};
struct RoadBits {
  int b;
  bool Any() const {return b!=0;}
  bool Any(RoadBits v) const {return b&v.b;}
};
struct Town {int index=1;struct {uint population=0;} cache;};
struct Record {int k=1,slope=0,height=2,roadbits=0,dir=0;};
constexpr int center=32*64+32;
std::array<Record,64*64> rows;
std::vector<int> peaks;
const int shifts[]={-1,64,1,-64};
const int grades[]={12,6,3,9};
const int bits[]={8,4,2,1};
int chosen,bridge_draws,road_in_request,style_ok,proposal_target,tunnel_gate;
bool roadpass,manual_quote;
uint32_t word;
struct {struct {bool allow_town_level_crossings;} economy;} _settings_game;
int Dir(DiagDirection d){return int(d);}
int InclinedSlope(DiagDirection d){return grades[Dir(d)];}
DiagDirection ReverseDiagDir(DiagDirection d){return DiagDirection((Dir(d)+2)%4);}
Axis DiagDirToAxis(DiagDirection d){return Axis(Dir(d)%2);}
RoadBits DiagDirToRoadBits(DiagDirection d){return {bits[Dir(d)]};}
TileIndexDiff TileOffsByDiagDir(DiagDirection d){return shifts[Dir(d)];}
TileIndex TileAddByDiagDir(TileIndex t,DiagDirection d){return t+TileOffsByDiagDir(d);}
bool IsValidTile(int t){return t>=0 && t<int(rows.size()) && rows[t].k!=0;}
int GetTileSlope(int t){return rows[t].slope;}
int GetTileZ(int t){return rows[t].height;}
bool IsSteepSlope(Slope s){return s>=16;}
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
RoadBits GetTownRoadBits(int t){return {rows[t].roadbits};}
bool IsWaterTile(int t){return rows[t].k==2||rows[t].k==3;}
bool IsSea(int t){return rows[t].k==3;}
bool IsPlainRailTile(int t){return rows[t].k==6;}
bool IsNormalRoadTile(int t){return rows[t].k==7||rows[t].k==8;}
RoadBits GetDisallowedRoadDirections(int t){return {rows[t].k==8?1:0};}
bool IsBridgeTile(int t){return rows[t].k==9||rows[t].k==14;}
TransportType GetTunnelBridgeTransportType(int t){return rows[t].k==14?TransportType::Rail:TransportType::Road;}
DiagDirection GetTunnelBridgeDirection(int t){return DiagDirection(rows[t].dir);}
bool IsDriveThroughStopTile(int t){return rows[t].k==11;}
bool IsBayRoadStopTile(int t){return rows[t].k==12;}
Axis GetDriveThroughStopAxis(int t){return Axis(rows[t].dir%2);}
DiagDirection GetBayRoadStopDir(int t){return DiagDirection(rows[t].dir);}
bool IsRoadDepot(int t){return rows[t].k==13;}
DiagDirection GetRoadDepotDirection(int t){return DiagDirection(rows[t].dir);}
bool IsTileType(int t,TileType type) {
 const int k=rows[t].k;
 switch (type) {
  case TileType::Road:return k==7||k==8||k==13;
  case TileType::Railway:return k==6;
  case TileType::Station:return k>=11&&k<=12;
  case TileType::TunnelBridge:return k==9||k==10||k==14;
  default:return false;
 }
}
const std::vector<int>& SpiralTileSequence(int,uint,int,int){return peaks;}
RoadType GetTownRoadType(){return 0;}
uint8_t RandomRange(uint n){++bridge_draws;word=word*1664525u+1013904223u;return (uint64_t(word)*n)>>32;}
template<Commands C>int GetCommandFlags(){return 0;}
DoCommandFlags CommandFlagsToDCFlags(int){return {};}
template<Commands C>struct Command {
 static CommandCost Do(DoCommandFlags,int tile,RoadBits back,RoadType,RoadBits,int){
   const int k=rows[tile].k; road_in_request=back.b;
   return {roadpass&&(k==1||k==4||k==6)};
 }
 static CommandCost Do(DoCommandFlags f,int,int end,TransportType,int style,int,RoadType){
   if (style!=style_ok) return {false};
   if (f.execute) {chosen=style;proposal_target=end;}
   return {true};
 }
 static CommandCost Do(DoCommandFlags f,int start,TransportType,int,RoadType){
   if (!tunnel_gate) return {false};
   if (f.execute) {
     chosen=1;const int d=std::find(grades,grades+4,rows[start].slope)-grades;
     int i=start;
     do {i+=shifts[d];}while (rows[i].height!=rows[start].height);
     proposal_target=i;
   }
   return {true};
 }
};
#define assert(x) do {if (!(x)) std::abort();} while (0)
"""
for name in ("CanRoadContinueIntoNextTile", "GrowTownWithBridge", "GrowTownWithTunnel"):
    cpp += source_block(src, "town_cmd.cpp", r"^static bool " + name)
cpp += r"""
int main() {
 for (int kind=0;kind<3;++kind) for(int d=0;d<4;++d)
 for(int obstruction=0;obstruction<=14;++obstruction) for(int length=1;length<=9;++length)
 for(int variant=0;variant<16;++variant) {
  for(auto &r:rows) r=Record{};
  int start=center,step=shifts[d];
  auto dir=DiagDirection(d);
  Town town{1,{uint((variant>>1)*1400)}};
  peaks.clear();bridge_draws=0;road_in_request=0;chosen=-1;proposal_target=0;
  style_ok=variant%4==0?12:7;
  roadpass=(variant&1)!=0;
  _settings_game.economy.allow_town_level_crossings=(variant&4)!=0;
  tunnel_gate=(variant&2)!=0;
  uint32_t seed=variant*47389271u+uint(length*438374+obstruction*48749+d*9274384+kind*9187494);
  word=seed;
  rows[start-step].roadbits=(variant%5!=0)?bits[d]:0;
  if(kind==0) {
   rows[start+step]={obstruction,0,2,0,(variant>>2)%4};
  } else if(kind==1) {
   rows[start].slope=variant%3==0?0:variant%3==1?grades[Dir(ReverseDiagDir(dir))]:1;
   for(int i=1;i<length;++i) rows[start+step*i].k=obstruction;
   rows[start+step*(length+1)]={1,0,2,0,0};
   if((variant&8)!=0) {rows[start+1+64]={9,grades[Dir(ReverseDiagDir(dir))],2,0,d};peaks.push_back(start+1+64);}
  } else {
   rows[start].slope=grades[d];
   for(int i=1;i<length;++i) {
    rows[start+step*i]={i==1?obstruction:1, i==2&&variant%3==0?7:grades[d],3,0,0};
   }
   rows[start+step*(length+1)]={1,0,2,0,0};
  }
  bool success=kind==0?CanRoadContinueIntoNextTile(&town,start,dir):
    kind==1?GrowTownWithBridge(&town,start,dir):GrowTownWithTunnel(&town,start,dir);
  int delta=success&&kind?(proposal_target-start)/step:0;
  std::cout<<kind<<' '<<d<<' '<<obstruction<<' '<<length<<' '<<variant<<' '<<seed<<' '
    <<success<<' '<<chosen<<' '<<delta<<' '<<bridge_draws<<' '<<road_in_request<<"\n";
 }
}
"""
lua = r"""
local root="mods/luanttd_core/openttd/"
local G=dofile(root.."town_growth.lua")
local S=dofile(root.."town_spans.lua")(G)
local kinds={[0]="void","clear","water","water","water","water","rail","road","road","bridge","tunnel","drive_stop","bay_stop","depot","rail_bridge"}
local slopes={[0]=12,6,3,9}
local bits={[0]=8,4,2,1}
local x={[0]=-1,0,1,0}
local z={[0]=0,1,0,-1}
local count,successes=0,0
for row in io.lines() do
  local a={}
  for n in row:gmatch("%-?%d+") do a[#a+1]=tonumber(n) end
  local k,d,obs,len,v,seed,answer,style,landing,draws,request=unpack(a)
  local q,seen_request,n={},0,0
  local t={id=1,population=math.floor(v/2)*1400}
  local function read(i,kind,slope,base,bits,dir)
    q[i]={kind=kinds[kind],slope=slope or 0,base=base or 2,road_bits=bits or 0,
      road_disallowed=kind==8 and 1 or 0,sea=kind==3,coast=kind==4,water_rocks=kind==5,
      inside=dir or 0,axis=(dir or 0)%2,entrance=dir or 0}
  end
  local function linearize(u,w) return u*x[d]+w*z[d] end
  local rev=(d+2)%4
  read(-1,7,0,2,v%5~=0 and bits[d] or 0)
  if k==0 then read(1,obs,0,2,0,math.floor(v/4)%4)
  elseif k==1 then
    read(0,1,v%3==0 and 0 or v%3==1 and slopes[rev] or 1)
    for i=1,len-1 do read(i,obs) end
  else
    read(0,1,slopes[d])
    for i=1,len-1 do read(i,i==1 and obs or 1,i==2 and v%3==0 and 7 or slopes[d],3) end
  end
  local board={town_level_crossings=math.floor(v/4)%2~=0}
  function board.tile(u,w) return q[linearize(u,w)] or {kind="clear",slope=0,base=2} end
  function board.road_quote(_,u,w,piece)
    seen_request=piece
    local a=board.tile(u,w)
    return v%2==1 and (a.kind=="clear" or a.coast or a.kind=="rail")
  end
  function board.parallel_bridge() return v>=8 end
  function board.bridge_quote(_,_,_,_,_,try) return try==(v%4==0 and 12 or 7) or nil end
  function board.tunnel_quote() return math.floor(v/2)%2~=0 end
  local function random()
    n=n+1
    seed=(seed*1664525+1013904223)%4294967296
    return seed
  end
  local result
  if k==0 then result=S.continues(t,board,0,0,d)
  elseif k==1 then result=S.bridge(t,board,0,0,d,random)
  else result=S.tunnel(t,board,0,0,d) end
  assert((result and 1 or 0)==answer,row)
  assert(n==draws and seen_request==request,row)
  if result and k~=0 then
    assert(linearize(result.u,result.v)==landing and (k~=1 or result.style==style),row)
    successes=successes+1
  end
  count=count+1
end
assert(count==25920 and successes>0)
print(("PASS %d compiled RC1 town continuation, bridge and tunnel decisions (%d spans); exact style draws and endpoints")
  :format(count,successes))
"""
with TemporaryDirectory() as temp:
    cc, program, driver = (Path(temp) / f for f in ("town.cpp", "town", "town.lua"))
    cc.write_text(cpp)
    driver.write_text(lua)
    subprocess.run(["g++", "-O2", "-std=c++20", cc, "-o", program], check=True)
    subprocess.run([sys.argv[2] if len(sys.argv) > 2 else "lua5.1", driver],
                   input=subprocess.check_output([program]), check=True)
