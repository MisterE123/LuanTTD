#!/usr/bin/env python3
"""Compare actual OpenTTD 14.1 CmdClearArea, fixed-point quota and iterators."""
from itertools import product
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "landscape.cpp": "0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97",
    "company_cmd.cpp": "1cf942041d5b8729e8eeba102c838b2ecb693ac68609aee5336dd538f16ed0d8",
    "tilearea_type.h": "8b759de3400fcfb2abc9fc89a83c86b8cff7dccf5c3bfa60fc6ac4c026785ada",
    "tilearea.cpp": "7a7071ad5c3e6a36e2abd4c10390398be914c139cf6f20ce31e5e3fe0e18484f",
    "table/settings/world_settings.ini": "4c08978820994e9a975a1a135b9d1ebcf01764772e49ecc2ad2c71c05e93642e",
})
SHIM = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <memory>
#include <tuple>
#include <vector>
using uint=unsigned; using TileIndex=uint; using Money=int64_t; using DoCommandFlag=uint;
constexpr TileIndex INVALID_TILE=~0U;
uint wid,dep,seed;
struct Map {
 static uint Size(){return wid*dep;}
 static uint SizeX(){return wid;}
 static uint SizeY(){return dep;}
};
uint TileX(TileIndex t){return t%wid;}
uint TileY(TileIndex t){return t/wid;}
TileIndex TileXY(uint x,uint y){return y*wid+x;}
int TileDiffXY(int x,int y){return y*int(wid)+x;}
TileIndex TILE_ADDXY(TileIndex tile,int x,int y){return tile+TileDiffXY(x,y);}
template<typename T> void Swap(T &a,T &b){std::swap(a,b);}
uint GB(uint value,uint s,uint n){return (value>>s)&((1u<<n)-1);}
enum {DC_EXEC=1,DC_AUTO=2,DC_BANKRUPT=4,DC_FORCE_CLEAR_TILE=8,DC_NO_WATER=16};
enum {PM_UNPAUSED,PM_PAUSED,EV_EXPLOSION_SMALL,EV_EXPLOSION_LARGE,TILE_SIZE=16};
constexpr int _pause_mode=PM_UNPAUSED;
void CreateEffectVehicleAbove(int,int,int,int){}
enum {EXPENSES_CONSTRUCTION,INVALID_PARAMETER,CLEARING_LIMIT_REACHED,DENIAL,NO_WATER,CANAL_FIRST};
struct CommandCost {
  int error=0; int64_t cost=0;
  explicit CommandCost(int e):error(e){}
  bool Failed()const{return error!=0;}
  Money GetCost()const{return cost;}
  void AddCost(Money n){cost+=n;}
  void AddCost(CommandCost x){cost+=x.cost;if(x.Failed())error=x.error;}
};
auto CMD_ERROR=CommandCost(INVALID_PARAMETER);
constexpr int STR_ERROR_CLEARING_LIMIT_REACHED=CLEARING_LIMIT_REACHED,
 STR_ERROR_MUST_DEMOLISH_CANAL_FIRST=CANAL_FIRST,STR_ERROR_CAN_T_BUILD_ON_WATER=NO_WATER;
#define return_cmd_error(e) return CommandCost(e)
struct Company {
  uint32_t clear_limit;
  static Company* GetIfValid(int);
} co;
Company *Company::GetIfValid(int who){return who==0?&co:nullptr;}
int _current_company=0;
struct ClearedObjectArea { TileIndex first_tile; };
const ClearedObjectArea *FindClearedObject(TileIndex){return nullptr;}
std::vector<TileIndex> consulted,applied,force_cleared;
Money available;
Money GetAvailableMoneyForCommand(){return available;}
int kind(TileIndex t){return (t*2609u+seed)%11;}
enum {WATER_CLASS_CANAL,WATER_CLASS_SEA,PR_CLEAR_CANAL=0,PR_CLEAR_WATER=1};
int _price[]={5000,10000};
bool HasTileWaterClass(TileIndex t){return kind(t)==4||kind(t)==5||kind(t)==6;}
bool IsTileOnWater(TileIndex t){return HasTileWaterClass(t);}
bool IsWaterTile(TileIndex t){return kind(t)==6;}
bool IsCoastTile(TileIndex){return false;}
int GetWaterClass(TileIndex t){return kind(t)==4?WATER_CLASS_CANAL:WATER_CLASS_SEA;}
void DoClearSquare(TileIndex t){force_cleared.push_back(t);}
int GetTileType(TileIndex){return 0;}
struct Procedures {
  static CommandCost clear_tile_proc(TileIndex t,DoCommandFlag flags){
    if (kind(t)==0||kind(t)==8) return CommandCost(DENIAL);
    if (flags & DC_EXEC) applied.push_back(t+1);
    int m=kind(t);
    CommandCost c(EXPENSES_CONSTRUCTION);
    c.AddCost(m==1 || m==6 ? 0 : m==3 ? -40 : m*63);
    return c;
  }
};
Procedures procs;
auto _tile_type_procs=std::vector{&procs};
CommandCost CmdLandscapeClear(DoCommandFlag,TileIndex);
enum {CMD_LANDSCAPE_CLEAR};
template<int cmd> struct Command {
  static CommandCost Do(DoCommandFlag flags,TileIndex t){
    if (!(flags&DC_EXEC)) consulted.push_back(t+1);
    return CmdLandscapeClear(flags,t);
  }
};
"""
DRIVER = r"""
int main() {
  int test_case;
  while(std::cin>>test_case) {
    if (test_case==1) {
      uint32_t quota,frames;
      std::cin>>quota>>frames;
      for(uint32_t i=0;i<frames;++i) UpdateLandscapingLimit(quota,StockClearRate,StockClearBurst);
      std::cout<<quota<<"\n";
      continue;
    }
    uint a,b,diag,exec,flags;
    std::cin>>wid>>dep>>a>>b>>diag>>exec>>available>>co.clear_limit>>seed>>flags;
    a--;b--; consulted.clear();applied.clear();force_cleared.clear();
    auto [r,extra]=CmdClearArea(flags|(exec?DC_EXEC:0),b,a,diag);
    std::cout<<r.error<<" "<<r.cost<<" "<<extra<<" "<<co.clear_limit<<" ";
    for(auto t:consulted) std::cout<<t<<",";
    std::cout<<" ";
    for(auto t:applied) std::cout<<t<<",";
    std::cout<<"\n";
  }
}
"""
LUA = r"""
local C=dofile("mods/bayline/openttd/clear_area.lua")
for line in io.lines() do
  local a={}
  for v in line:gmatch("%-?%d+") do a[#a+1]=tonumber(v) end
  if a[1]==1 then
    print(C.replenish(a[2],a[3]))
  else
    local _,w,d,first,last,di,exe,cash,quota,seed,flags=unpack(a)
    local raw_quota=quota
    local visits,applied={},{}
    local function log(tab,id) tab[#tab+1]=id.."," end
    local function bit(n,i) return math.floor(n/2^i)%2==1 end
    local auto_or_bankrupt=bit(flags,1) or bit(flags,2)
    if auto_or_bankrupt then quota=nil end
    local ctx={}
    function ctx.quote(id,force)
      log(visits,id)
      local m=((id-1)*2609+seed)%11
      if m==0 or m==8 then return nil,3 end
      local c=(m==1 or m==6) and 0 or m==3 and -40 or m*63
      if force and (m==4 or m==5) then
        if m==4 and bit(flags,1) then return nil,5 end
        c=c+(m==4 and 5000 or 10000)
      end
      return c
    end
    function ctx.apply(id) log(applied,id) end
    local q,why,failed=C.run(w,d,first,last,di==1,ctx,{execute=exe==1,money=cash,limit=quota})
    -- The source attempts CmdLandscapeClear once when entering the tile with
    -- an empty quota, but its host clear callback is not invoked.
    if (quota~=nil and ((q and q.quota or quota)<C.UNIT)) and (q or why=="CLEARING_LIMIT_REACHED") then
      local n=q and q.attempted or failed.attempted
      if n>#visits then
        local i=0
        for tile in C.each(w,d,first,last,di==1) do
          i=i+1
          if i==n then log(visits,tile);break end
        end
      end
    end
    local err=not q and ({INVALID_PARAMETER=1,CLEARING_LIMIT_REACHED=2})[why] or 0
    if not q and err==0 then err=why end
    print(table.concat({err,q and q.cost or 0,q and q.extra or 0,q and q.quota or raw_quota,
      table.concat(visits),table.concat(applied)}," "))
  end
end
"""


def oracle(source):
    areas = src(source, "tilearea.cpp")
    header = src(source, "tilearea_type.h")
    land = src(source, "landscape.cpp")
    company = src(source, "company_cmd.cpp")
    settings = src(source, "table/settings/world_settings.ini")
    definitions = header[header.index("class OrthogonalTileIterator;"):header.index("#endif")]
    methods = [block(areas, n) for n in [
        r"^OrthogonalTileArea::OrthogonalTileArea\(", r"^DiagonalTileArea::DiagonalTileArea\(",
        r"^TileIterator &DiagonalTileIterator::operator\+\+\(", r"^/\* static \*/ std::unique_ptr<TileIterator> TileIterator::Create\("]]
    cap = re.search(r"construction\.clear_frame_burst.*?\ndef\s*= ([0-9]+)", settings, re.S)[1]
    rate = re.search(r"construction\.clear_per_64k_frames.*?\ndef\s*= ([^\n]+)", settings, re.S)[1]
    return SHIM + definitions + "".join(methods) + block(company,r"^static constexpr void UpdateLandscapingLimit\(") + (
        f"constexpr uint StockClearRate={rate},StockClearBurst={cap};\n"
        + block(land,r"^CommandCost CmdLandscapeClear\(")
        + block(land,r"^std::tuple<CommandCost, Money> CmdClearArea\(")+DRIVER)


def vectors():
    r = random.Random(141)
    # All endpoint pairs/orders on a non-square clipped map plus concentrated
    # flags/cash/quota coverage. Costs include refunds, zero, denials and FX.
    base = [[0,5,4,a,b,d,1,999999,(4096<<16)+17,7,0]
            for a,b,d in product(range(1,21),range(1,21),range(2))]
    base += [[0,6,9,5,47,d,e,c,q,r.randrange(200),f]
             for d,e,c,q,f in product(range(2),range(2),[-4,0,65,255,569,1500,30000],
                [0,1000,65535,65536,65536+100,3<<16,6<<16,4096<<16],[0,2,4])]
    for _ in range(6000):
        w,d=r.randrange(3,22),r.randrange(3,22)
        base.append([0,w,d,r.randint(1,w*d),r.randint(1,w*d),r.randrange(2),r.randrange(2),
                    r.randrange(-1000,30000),r.randrange(0,44<<16),r.randrange(2000),r.choice([0,0,0,2,4])])
    base += [[1,r.randrange(0,1<<30),r.randrange(0,75)] for _ in range(100)]
    return base


def main():
    inputs=vectors()
    data="\n".join(" ".join(map(str,i)) for i in inputs)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        cpp, lua_file, executable=(Path(tmp)/n for n in ("ref.cpp","adapter.lua","ref"))
        cpp.write_text(oracle(Path(sys.argv[1])))
        lua_file.write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",str(cpp),"-o",str(executable)],check=True)
        ref=subprocess.check_output([str(executable)],input=data,text=True).splitlines()
        actual=subprocess.check_output([sys.argv[2] if len(sys.argv)>2 else "lua5.1",str(lua_file)],
            cwd=ROOT,input=data,text=True).splitlines()
    assert len(ref)==len(actual)==len(inputs)
    for i,a,b in zip(inputs,ref,actual):
        assert a==b,(i,a,b)
    print(f"PASS {len(inputs):,} stock ClearArea cases: ordered selection, budget, quote/exec, bit quota, skip and refill")


if __name__=="__main__":
    main()
