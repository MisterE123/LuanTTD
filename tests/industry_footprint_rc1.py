#!/usr/bin/env python3
"""Compare the two stock footprint checks with pinned C++ source."""
from hashlib import sha256
from pathlib import Path
from random import Random
from tempfile import TemporaryDirectory
import subprocess
import sys
from rc1_rail_foundation_shim import source_block

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
assert sha256((src/"industry_cmd.cpp").read_bytes()).hexdigest()=="1e6bc18f0c26e56f2c50bad4c9e1039174ad2da7b404750ce688dcea2b10c752"
cpp=r"""
#include <cassert>
#include <initializer_list>
#include <iostream>
#include <vector>
using Slope=int;using IndustryGfx=int;using IndustryType=int;using TileIndex=int;
constexpr int GFX_WATERTILE_SPECIALCHECK=65535;
constexpr int SLOPE_FLAT=0,SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_STEEP=16;
constexpr int SLOPE_NW=9,SLOPE_NE=12,SLOPE_SW=3,SLOPE_SE=6;
bool IsSteepSlope(Slope s){return s&16;}
Slope ComplementSlope(Slope s){assert(s>=0&&s<16);return s^15;}
bool HasBit(int a,int b){return (a>>b)&1;}
struct CommandCost {int code=0;CommandCost()=default;CommandCost(int x):code(x){}bool Failed()const{return code!=0;}};
constexpr int STR_ERROR_SITE_UNSUITABLE=1,STR_ERROR_CAN_ONLY_BE_BUILT_IN_TOWNS=2;
constexpr int OWNER_COMPANY=0,OWNER_TOWN=1;
int _current_company=OWNER_COMPANY;
struct AutoRestoreBackup {int &a,b; AutoRestoreBackup(int &x,int y):a(x),b(x){a=y;}~AutoRestoreBackup(){a=b;}};
enum class IndustryBehaviour {BuiltOnWater,OnlyInTown,Town1200More,OnlyNearTown};
struct IndustryBehaviours {
  int flags;
  bool Test(IndustryBehaviour b)const{return flags&(1<<int(b));}
  bool Any(std::initializer_list<IndustryBehaviour> set)const{for(auto b:set)if(Test(b))return true;return false;}
};
struct IndustrySpec { IndustryBehaviours behaviour; } ispec;
struct IndustryTileSpec { int slopes_refused; } tspec;
const IndustrySpec* GetIndustrySpec(int){return &ispec;}
const IndustryTileSpec* GetIndustryTileSpec(int){return &tspec;}
int GetTranslatedIndustryTileID(int id){return id;}
struct IndustryTileLayoutTile {struct {int x,y;} ti; IndustryGfx gfx;};
using IndustryTileLayout=std::vector<IndustryTileLayoutTile>;
int ground;
TileIndex TileAddWrap(TileIndex t,int x,int y){return y*16+x+t;}
bool IsValidTile(TileIndex t){return (ground&1)&&t>=0&&t<256;}
enum class TileType{House};
bool IsTileType(int,TileType){return ground&64;}
bool IsWaterTile(int){return ground&2;}
bool IsTileFlat(int){return ground&4;}
bool HasTileWaterClass(int){return ground&8;}
bool IsTileOnWater(int){return ground&8;}
CommandCost EnsureNoVehicleOnGround(int){return ground&16?3:0;}
bool IsBridgeAbove(int){return ground&32;}
enum class DoCommandFlag{Auto,NoTestTownRating,NoModifyTownRating};
enum class Commands{LandscapeClear};
int clear_error,clear_call;
template<Commands C> struct Command {
  static CommandCost Do(std::initializer_list<DoCommandFlag> flags,int){
    assert((_current_company==OWNER_TOWN&&flags.size()==0)||(_current_company==OWNER_COMPANY&&flags.size()==3));
    clear_call=_current_company==OWNER_TOWN?1:2;return clear_error;
  }
};
"""
for pattern in (r"^bool IsSlopeRefused\(",r"^static CommandCost CheckIfIndustryTilesAreFree\("):
    cpp+=source_block(src,"industry_cmd.cpp",pattern)+"\n"
cpp+=r"""
int main(){
  int mode,a,b,c,d,g;
  while(std::cin>>mode>>a>>b>>c>>d>>g){
    if(mode==0){std::cout<<IsSlopeRefused(a,b)<<'\n';continue;}
    ground=a; tspec.slopes_refused=b;ispec.behaviour.flags=c;clear_error=d;clear_call=0;
    auto res=CheckIfIndustryTilesAreFree(68,{{{0,0},g}},0);
    std::cout<<res.code<<' '<<clear_call<<'\n';
  }
}
"""
program=r"""
local p="mods/luanttd_core/openttd/"
local F=dofile(p.."industry_footprint_rc1.lua")
local L=dofile(p.."stock_industry_layouts_rc1.lua")
local bit=function(n,d)return math.floor(n/d)%2==1 end
local err={[1]="SITE_UNSUITABLE",[2]="CAN_ONLY_BE_BUILT_IN_TOWNS",[3]="VEHICLE_IN_THE_WAY",[4]="CLEAR"}
local by={}
for i,s in pairs(err) do by[s]=i end
for line in io.lines() do
  local q={}
  for n in line:gmatch("%d+") do q[#q+1]=tonumber(n) end
  local mode,a,b,c,d,g=unpack(q)
  if mode==0 then print(F.slope_refused(a,b) and 1 or 0)
  else
    local scenery={valid=bit(a,1),water=bit(a,2),slope=bit(a,4) and 0 or 1,on_water=bit(a,8),
      vehicle=bit(a,16),bridge_above=bit(a,32),house=bit(a,64)}
    local spec={built_on_water=bit(c,1),only_in_town=bit(c,2),town_1200=bit(c,4),only_near_town=bit(c,8)}
    local call=0
    local got,why=F.tiles_free({{0,0,g}},{[g]=b},4,4,spec,{
      tile=function(x,z)assert(x==4 and z==4);return scenery end,
      clear=function(x,z,t,who,auto,no_test,no_modify)
        call=who=="town" and 1 or 2
        assert(x==4 and z==4 and t==scenery and auto==(call==2) and no_test==auto and no_modify==auto)
        if d~=0 then return false,err[d] end
        return true
      end})
    if got then assert(#got==(g==65535 and 0 or 1)) end
    io.write(got and 0 or assert(by[why])," ",call,"\n")
  end
end
local n=0
for id=0,36 do
  for variant,plan in pairs(L[id]) do
    n=n+1
    local checks=0
    for _,t in ipairs(plan) do
      if t[3]~=F.WATER_CHECK then assert(L.slope_refused[t[3]]) else checks=checks+1 end
    end
    assert(id==5 and checks>0 or id~=5 and checks==0)
  end
end
assert(n==60)
"""
rng=Random(160013)
rows=[(0,s,m,0,0,0) for s in range(32) for m in range(64)]
rows.extend((1,rng.randrange(128),rng.randrange(64),rng.randrange(16),rng.choice((0,0,0,4)),rng.choice((120,65535)))
            for _ in range(6400))
inp="\n".join(" ".join(map(str,x)) for x in rows)+"\n"
with TemporaryDirectory(prefix="industry-footprint-rc1-") as d:
    p=Path(d)
    (p/"runner.cc").write_text(cpp)
    (p/"runner.lua").write_text(program)
    subprocess.run(["c++","-std=c++20","-O2",p/"runner.cc","-o",p/"runner"],check=True)
    ref=subprocess.check_output([p/"runner"],input=inp,text=True).splitlines()
    got=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"runner.lua"],input=inp,text=True,cwd=root).splitlines()
assert len(got)==len(ref)==len(rows)
for row,a,b in zip(rows,ref,got):
    assert a.split()==b.split(),(row,a,b)
print(f"PASS {len(rows)} RC1 slope and footprint checks, including town clear, water sentinels, and physical conflicts")
