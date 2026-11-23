#!/usr/bin/env python3
"""Compare the depot command and GUI connection candidates with pinned 16.0-RC1."""
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "rail_cmd.cpp":"9b3cd08ec096514723554d288901b25b36f0a11891baea5019a440c1a510d041",
    "depot_func.h":"0063b5ea12a768b817306b19787a279467a0e1fed57c0574ed860aefd92b2b86",
    "depot_type.h":"9e39c419893c133aadfabafd568035d46efb0af9669f414a7b0dd9b02e2a5b36",
    "rail_gui.cpp":"5baf2f35401f35317a99d459a50db3c3878787aca8376bb1bedc901c4f9196dd",
    "table/pricebase.h":"8e0d8a31a7b08aa75fbb63d6b583e9a3edf9bae3c49493c5819d1de579ab1ec1",
    "rail.h":"f708f75d7a1643bb254ef0406534c5ebd707321f4bbce47f627c7dba638d6f88",
    "slope_func.h":"598a6193f39bc0721911ec1cfec07be463445b58d62abd9f392f28051f79cd69",
})
SHIM = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using Slope=int; using CommandFlag=int; using Money=int; using TileIndex=int; using Tile=int; using RailType=int;
using Train=int; using Owner=int;
enum DiagDirection:int {NE,SE,SW,NW,Invalid=255};
enum SlopeDir {SLOPE_FLAT=0,SLOPE_NE=12,SLOPE_SE=6,SLOPE_SW=3,SLOPE_NW=9};
enum Track:int {X,Y,Upper,Lower,Left,Right};
enum class RailTileType {Normal,Signals,Depot};
enum class TileType {Railway};
enum class Price {BuildRail, BuildDepotTrain, BuildFoundation};
enum class ExpensesType {Construction};
enum class DoCommandFlag {Execute};
enum class Commands {BuildRail,LandscapeClear};
enum {STR_ERROR_FLAT_LAND_REQUIRED=1,STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION,OWNER_DENIED,
 VEHICLE_IN_WAY,SURFACE_DENIED,STR_ERROR_BRIDGE_TOO_LOW_FOR_TRAIN_DEPOT,GENERIC};
constexpr int TILE_HEIGHT_STEP=8,RAILTYPE_END=4,SND_20_CONSTRUCTION_RAIL=0,_current_company=1,_cur_railtype=0;
#define NOT_REACHED() __builtin_unreachable()
template<class T> using DiagDirectionIndexArray=std::array<T,4>;
struct CommandCost {
 int cost=0,error=0,height=0;
 CommandCost()=default;
 explicit CommandCost(ExpensesType){}
 explicit CommandCost(int e):error(e){}
 bool Failed()const{return error!=0;}
 void AddCost(int c){cost+=c;}
 void AddCost(CommandCost c){if(c.Failed()) error=c.error;cost+=c.cost;}
};
CommandCost CommandCostWithParam(int e,int height){CommandCost c(e);c.height=height;return c;}
const CommandCost CMD_ERROR(GENERIC);
struct DoCommandFlags {bool Test(DoCommandFlag)const{return false;}};
struct RailTypeInfo {int cost_multiplier;};
const RailTypeInfo *GetRailTypeInfo(int p){static const RailTypeInfo m[]={{8},{12},{16},{24}};return &m[p];}
struct {int raw,old_dir,type,selected,depot,owner,occupied,overhead,deck,full,clear; int on_bridge()const{return deck;}} t;
struct {struct {bool build_on_slopes;} construction;} _settings_game;
struct {struct {bool confirm;} sound;struct {bool persistent_buildingtools,auto_remove_signals;} gui;} _settings_client;
bool IsSteepSlope(Slope s){return s&16;}
bool IsValidDiagDirection(DiagDirection d){return d>=0&&d<4;}
bool ValParamRailType(RailType r){return r==0||r==1;}
Slope GetTileSlope(TileIndex){return t.raw;}
int GetTileMaxZ(TileIndex){return 4+(t.raw>=16?2:t.raw!=0);}
int GetRailType(TileIndex){return t.type;}
RailTileType GetRailTileType(TileIndex);
bool connect_test=false;
bool IsRailDepotTile(TileIndex tile){return connect_test?GetRailTileType(tile)==RailTileType::Depot:t.depot;}
bool IsBridgeAbove(TileIndex){return t.overhead;}
int GetSouthernBridgeEnd(TileIndex tile){return tile;}
int GetBridgeHeight(TileIndex){return t.deck;}
CommandCost CheckTileOwnership(TileIndex){return CommandCost(t.owner==1?0:OWNER_DENIED);}
CommandCost EnsureNoVehicleOnGround(TileIndex){return CommandCost(t.occupied?VEHICLE_IN_WAY:0);}
DiagDirection GetRailDepotDirection(TileIndex){return DiagDirection(t.old_dir);}
bool HasDepotReservation(TileIndex){return false;}
Train *GetTrainForReservation(TileIndex,Track){return nullptr;}
Track DiagDirToDiagTrack(DiagDirection d){return Track(d%2);}
void FreeTrainTrackReservation(Train*){}
void SetDepotReservation(TileIndex,bool){}
void SetRailDepotExitDirection(TileIndex,DiagDirection){}
struct Depot {int index=0; static Depot *Create(int){return nullptr;} static bool CanAllocateItem(){return !t.full;}};
void MakeRailDepot(int,int,int,DiagDirection,RailType){}
void MakeDefaultName(Depot*){}
struct Company {struct {std::array<int,4> rail;} infrastructure;static Company *Get(int){return nullptr;}};
void DirtyCompanyInfrastructureWindows(int){}
void MarkTileDirtyByTile(int){}
void AddSideToSignalBuffer(int,DiagDirection,int){}
void YapfNotifyTrackLayoutChange(int,Track){}
void TryPathReserve(Train*,bool){}
void SndPlayTileFx(int,int){}
void ResetObjectToPlace(){}
int TileOffsByDiagDir(DiagDirection){return 1;}
bool IsValidTile(Tile tile){return tile>=0&&tile<3;}
struct {int kind,bits,across,blocked,calls;} g;
struct TrackBits {int value; bool Any(TrackBits b)const{return (value&b.value)!=0;}};
TrackBits GetTrackBits(Tile tile){assert(tile==1);return {g.bits};}
TrackBits DiagdirReachesTracks(DiagDirection d){
  constexpr int reach[]={1+8+16,2+4+16,1+4+32,2+8+32};return {reach[d]};
}
bool IsTileType(Tile tile,TileType){return tile==1&&g.kind!=0;}
RailTileType GetRailTileType(Tile tile){
  if(tile==2)return g.across?RailTileType::Depot:RailTileType::Normal;
  return g.kind==2?RailTileType::Signals:g.kind==3?RailTileType::Depot:RailTileType::Normal;
}
template<Commands> struct Command {
 static CommandCost Do(DoCommandFlags,TileIndex){
   if(t.clear<0)return CommandCost(SURFACE_DENIED);
   CommandCost c;c.cost=t.clear;return c;
 }
 static void Post(TileIndex tile,RailType,Track track,bool){
   assert(tile==1);g.calls=g.calls*10+track+1;
   if(!(g.blocked&(1<<track)))g.bits|=1<<track;
 }
};
"""
MAIN = r"""
int main(){
 int mode,d,slopes,autorm;
 while(std::cin>>mode>>d){
   if(mode==0){
     std::cin>>t.raw>>slopes>>t.selected>>t.depot>>t.type>>t.old_dir>>t.owner>>t.occupied>>t.overhead>>t.deck>>t.full>>t.clear;
     _settings_game.construction.build_on_slopes=slopes;
     const auto q=CmdBuildTrainDepot({},0,t.selected,DiagDirection(d));
     std::cout<<q.error<<" "<<(q.Failed()?0:q.cost)<<" "<<q.height<<"\n";
   }else{
     std::cin>>g.kind>>g.bits>>g.across>>autorm>>g.blocked;
     g.calls=0; connect_test=true; _settings_client.gui.auto_remove_signals=autorm;
     CcRailDepot(Commands::BuildRail,{},0,0,DiagDirection(d));
     connect_test=false;
     std::cout<<g.calls<<" "<<g.bits<<"\n";
   }
 }
}
"""
LUA = r"""
local p="mods/luanttd_core/openttd/"
local T=dofile(p.."rail_track.lua")
local Q=dofile(p.."rail_construction.lua")(T)
local D=dofile(p.."rail_depot_construction.lua")(T,Q)
local errors={FLAT_LAND_REQUIRED=1,LAND_SLOPED_IN_WRONG_DIRECTION=2,OWNED_BY_ANOTHER=3,
  VEHICLE_IN_THE_WAY=4,SURFACE_DENIED=5,BRIDGE_TOO_LOW_FOR_TRAIN_DEPOT=6,DEPOT_POOL_FULL=7,INVALID_PARAMETER=7}
for l in io.lines() do
  local a={}
  for n in l:gmatch("%-?%d+") do a[#a+1]=tonumber(n) end
  if a[1]==0 then
    local q,why,height=D.quote({kind=a[6]==1 and "depot" or "clear",slope=a[3],base_level=4,railtype=a[7],
      dir=a[8],owner=a[9],occupied=a[10]==1,overhead=a[11]==1,deck=a[12]},a[2],{
      railtype=a[5],available=a[5]<2,owner=1,build_on_slopes=a[4]==1,pool_full=a[13]==1,
      clear=function() if a[14]<0 then return nil,"SURFACE_DENIED" end return a[14] end})
    print(("%d %d %d"):format(q and 0 or assert(errors[why]),q and q.cost or 0,height or 0))
  else
    local kinds={[0]="clear","rail","signals","depot"}
    local map={[1]={kind=kinds[a[3]],trackbits=a[4]},[2]={kind=a[5]==1 and "depot" or "clear"}}
    local calls=0
    D.connect({tile=function(i)return map[i] end,adjacent=function(i)return i+1 end},0,a[2],
      {auto_remove_signals=a[6]==1},function(id,track)
        calls=calls*10+track+1
        if T.has(a[7],track) then return false end
        map[id].trackbits=T.union(map[id].trackbits,2^track)
        return true
      end)
    print(("%d %d"):format(calls,map[1].trackbits))
  end
end
"""


def main():
    where=Path(sys.argv[1])
    rail_cmd=src(where,"rail_cmd.cpp")
    gui=src(where,"rail_gui.cpp")
    p=src(where,"table/pricebase.h")
    raw=[int(re.search(fr"PriceBaseSpec\((-?\d+),[^\n]+// Price::{k}\s*$",p,re.M)[1]) for k in
         ("BuildRail","BuildDepotTrain","BuildFoundation")]
    prices="struct {int operator[](Price p)const {constexpr int a[]={%s};return a[int(p)];}} _price;\n"%(",".join(map(str,raw)))
    const=re.search(r"^static constexpr uint8_t MINIMAL_DEPOT_BRIDGE_HEIGHT[^;]+;",src(where,"depot_type.h"),re.M)[0]
    arrays="".join(block(gui,fr"^static constexpr std::array<[^\n]+> {k}")+";\n" for k in
                   ("_place_depot_extra_track","_place_depot_extra_dir"))
    cpp="\n".join((SHIM,prices,const,block(src(where,"slope_func.h"),r"^inline Slope InclinedSlope\("),
        block(src(where,"depot_func.h"),r"^inline bool CanBuildDepotByTileh\("),block(src(where,"rail.h"),r"^inline Money RailBuildCost\("),
        block(rail_cmd,r"^CommandCost CmdBuildTrainDepot\("),block(gui,r"^static void PlaceExtraDepotRail\("),arrays,
        block(gui,r"^void CcRailDepot\("),MAIN))
    commands=[(0,*a) for a in product(range(-1,5),[*range(15),23,27,29,30],range(2),range(3),range(2),range(2),
        (0,2),(1,2),range(2),range(2),(6,7,8,9),range(2),(-1,0,20))]
    connections=[(1,*a) for a in product(range(4),range(4),range(64),range(2),range(2),(0,1,4,63))]
    cases=commands+connections
    data="\n".join(" ".join(map(str,c)) for c in cases)+"\n"
    with tempfile.TemporaryDirectory() as td:
        c,l,exe=(Path(td)/p for p in ("stock.cpp","port.lua","stock"))
        c.write_text(cpp);l.write_text(LUA)
        subprocess.run(["c++","-std=c++20","-O2",str(c),"-o",str(exe)],check=True)
        expected=subprocess.check_output([str(exe)],input=data,text=True).splitlines()
        actual=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(l)],cwd=ROOT,input=data,text=True).splitlines()
    assert len(actual)==len(cases)==len(expected)
    for row,a,b in zip(cases,expected,actual):
        assert a==b,(row,a,b)
    print(f"PASS {len(commands):,} stock depot quotes and {len(connections):,} stock auto-attachment cases")


if __name__=="__main__":
    main()
