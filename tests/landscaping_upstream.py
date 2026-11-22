#!/usr/bin/env python3
"""Compare Lua landscaping to compiled OpenTTD 14.1 commands and iterators."""
from pathlib import Path
import argparse
import hashlib
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHIM = r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <tuple>
#include <vector>
using TileIndex=uint32_t;
using Money=int64_t;
template <typename T> void Swap(T &a,T &b) { std::swap(a,b); }
constexpr TileIndex INVALID_TILE=UINT_MAX;
enum {
  STR_ERROR_ALREADY_AT_SEA_LEVEL=1,STR_ERROR_TOO_HIGH,STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP,
  STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST,STR_ERROR_BRIDGE_TOO_HIGH_AFTER_LOWER_LAND,
  STR_ERROR_EXCAVATION_WOULD_DAMAGE,STR_ERROR_TERRAFORM_LIMIT_REACHED,STR_ERROR_ALREADY_LEVELLED,
  STR_ERROR_PROTECTED_TILE,INVALID_STRING_ID,
  EXPENSES_CONSTRUCTION
};
struct CommandCost {
  int error=0;
  Money cost=0;
  CommandCost(int n=EXPENSES_CONSTRUCTION): error(n==EXPENSES_CONSTRUCTION?0:n) {}
  bool Failed() const { return error!=0; }
  bool Succeeded() const { return !Failed(); }
  int GetErrorMessage() const { return error; }
  Money GetCost() const { return cost; }
  void AddCost(Money n) { cost+=n; }
  void AddCost(CommandCost n) { cost+=n.cost; }
};
const CommandCost CMD_ERROR(INVALID_STRING_ID);
struct { struct { int map_height_limit,max_bridge_height; bool freeform_edges; } construction; } _settings_game;
constexpr int PR_TERRAFORM=0;
Money _price[1];
uint width,depth;
struct Map {
  static uint SizeX() { return width; }
  static uint SizeY() { return depth; }
  static uint MaxX() { return width-1; }
  static uint MaxY() { return depth-1; }
  static uint Size() { return width*depth; }
};
std::vector<int> levels;
int TileHeight(TileIndex t) { return levels.at(t); }
void SetTileHeight(TileIndex t,uint h) { levels.at(t)=h; }
uint TileX(TileIndex t) { return t%width; }
uint TileY(TileIndex t) { return t/width; }
TileIndex TileXY(int x,int y) { return y*width+x; }
uint Delta(uint a,uint b) { return a>b?a-b:b-a; }
int TileDiffXY(int x,int y) { return y*(int)width+x; }
struct TileIndexDiffC { int x,y; };
int ToTileIndexDiff(TileIndexDiffC d) { return TileDiffXY(d.x,d.y); }
template <typename T,size_t I> const T *endof(const T (&t)[I]) { return t+I; }
template <typename T> struct Backup {
  T &x,saved;
  Backup(T &x,int) : x(x),saved(x) {}
  void Change(T y) {x=y;}
  void Restore() {x=saved;}
};
constexpr int FILE_LINE=0,GM_EDITOR=1;
bool _generating_world=false;
int _game_mode=0;
using Slope=uint;
constexpr Slope SLOPE_FLAT=0,SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_STEEP=16;
using DoCommandFlag=uint;
constexpr uint DC_EXEC=1,DC_AUTO=2,DC_FORCE_CLEAR_TILE=4,DC_NO_MODIFY_TOWN_RATING=8;
enum LevelMode { LM_LEVEL, LM_RAISE, LM_LOWER };
constexpr int MP_VOID=1;
int GetTileType(TileIndex t) { return TileX(t)==Map::MaxX()||TileY(t)==Map::MaxY()?MP_VOID:0; }
bool IsTileType(TileIndex t,int type) { return GetTileType(t)==type; }
struct ClearedObjectArea { TileIndex first_tile; };
const ClearedObjectArea *FindClearedObject(TileIndex) { return nullptr; }
TileIndex blocker,bridge,tunnel;
int deck,tunnel_height;
bool IsBridgeAbove(TileIndex t) { return t==bridge; }
TileIndex GetSouthernBridgeEnd(TileIndex t) { return t; }
int GetBridgeHeight(TileIndex) { return deck; }
bool IsTunnelInWay(TileIndex t,int z) { return t==tunnel&&z<=tunnel_height; }
std::set<TileIndex> dirtied;
void MarkTileDirtyByTile(TileIndex t,int=0,int=0) { if (!IsTileType(t,MP_VOID)) dirtied.insert(t); }
int _current_company;
int64_t initial_quota;
struct Company {
  uint32_t terraform_limit;
  static Company *GetIfValid(int);
};
Company company;
Company *Company::GetIfValid(int) { return initial_quota<0?nullptr:&company; }
uint GB(uint32_t n,uint start,uint bits) { return (n>>start)&((1u<<bits)-1); }
Money cash;
Money GetAvailableMoneyForCommand() { return cash; }
CommandCost TileTerraform(TileIndex t,DoCommandFlag,int,Slope) {
  if (t==blocker) return CommandCost(STR_ERROR_PROTECTED_TILE);
  CommandCost c;
  c.AddCost((t%3)*10);
  return c;
}
struct { decltype(&TileTerraform) terraform_tile_proc; } procs={TileTerraform};
auto _tile_type_procs=std::array{&procs};
enum { CMD_LANDSCAPE_CLEAR, CMD_TERRAFORM_LAND };
template <int C> struct Command {
  static auto Do(DoCommandFlag,TileIndex,Slope,bool);
  static CommandCost Do(DoCommandFlag f,TileIndex t) { return TileTerraform(t,f,0,0); }
};
using TileIndexSet=std::set<TileIndex>;
using TileIndexToHeightMap=std::map<TileIndex,int>;
struct OrthogonalTileArea {
  TileIndex tile;
  uint w,h;
  OrthogonalTileArea(TileIndex,TileIndex);
};
struct DiagonalTileArea {
  TileIndex tile;
  int a,b;
  DiagonalTileArea(TileIndex,TileIndex);
};
struct TileIterator {
  TileIndex tile;
  TileIterator(TileIndex t): tile(t) {}
  virtual ~TileIterator()=default;
  operator TileIndex() const { return tile; }
  virtual TileIterator &operator++()=0;
  static std::unique_ptr<TileIterator> Create(TileIndex,TileIndex,bool);
};
struct OrthogonalTileIterator: TileIterator {
  int w,x,y;
  OrthogonalTileIterator(const OrthogonalTileArea &q):
    TileIterator(q.w==0||q.h==0?INVALID_TILE:q.tile),w(q.w),x(q.w),y(q.h) {}
  OrthogonalTileIterator(TileIndex a,TileIndex b):
    OrthogonalTileIterator(OrthogonalTileArea(a,b)) {}
  TileIterator &operator++() override;
};
struct DiagonalTileIterator: TileIterator {
  uint base_x,base_y;
  int a_cur,b_cur,a_max,b_max;
  DiagonalTileIterator(const DiagonalTileArea &q):
    TileIterator(q.tile),base_x(TileX(q.tile)),base_y(TileY(q.tile)),
    a_cur(0),b_cur(0),a_max(q.a),b_max(q.b) {}
  DiagonalTileIterator(TileIndex a,TileIndex b):
    DiagonalTileIterator(DiagonalTileArea(a,b)) {}
  TileIterator &operator++() override;
};
"""
DRIVER = r"""
int main() {
  char kind;
  while (std::cin >> kind) {
    if (kind=='Q') {
      uint32_t allowance,rate,burst,ticks;
      std::cin>>allowance>>rate>>burst>>ticks;
      for (uint32_t i=0;i<ticks;i++) UpdateLandscapingLimit(allowance,rate,burst);
      std::cout<<allowance<<"\n";
      continue;
    }
    int sx,sz,ex,ez,diagonal;
    std::cin>>width>>depth>>sx>>sz>>ex>>ez>>diagonal;
    TileIndex start=TileXY(sx,sz), end=TileXY(ex,ez);
    if (kind=='I') {
      auto i=TileIterator::Create(end,start,diagonal);
      for (;*i!=INVALID_TILE;++(*i)) std::cout<<*i<<",";
      std::cout<<"\n";
      continue;
    }
    int mode,exec,freeform;
    std::cin>>mode>>exec>>cash>>initial_quota>>_price[0]>>freeform>>_settings_game.construction.map_height_limit;
    std::cin>>blocker>>bridge>>deck>>tunnel>>tunnel_height;
    _settings_game.construction.freeform_edges=freeform;
    _settings_game.construction.max_bridge_height=12;
    company.terraform_limit=initial_quota;
    dirtied.clear();
    levels.resize(Map::Size());
    for (int &h: levels) std::cin>>h;
    const auto [c,required,error]=CmdLevelLand(exec?DC_EXEC:0,end,start,diagonal,LevelMode(mode));
    int64_t allowance=initial_quota<0?-1:int64_t(company.terraform_limit);
    std::cout<<c.GetErrorMessage()<<"|"<<c.GetCost()<<"|"<<required<<"|"<<error<<"|"<<allowance<<"|";
    for (const int v:levels) std::cout<<v<<",";
    std::cout<<"|";
    for (auto t:dirtied) std::cout<<t<<",";
    std::cout<<"\n";
  }
}
"""
LUA = r"""
local T=dofile("mods/luanttd_core/openttd/terrain.lua")
local L=dofile("mods/luanttd_core/openttd/landscaping.lua")(T)
local codes={ALREADY_AT_SEA_LEVEL=1,TOO_HIGH=2,TOO_CLOSE_TO_EDGE=3,MUST_DEMOLISH_BRIDGE_FIRST=4,
  BRIDGE_TOO_HIGH_AFTER_LOWER_LAND=5,EXCAVATION_WOULD_DAMAGE_TUNNEL=6,TERRAFORM_LIMIT_REACHED=7,
  ALREADY_LEVELLED=8,PROTECTED_TILE=9,INVALID_SELECTION=10,NO_EFFECT=10}
local invalid=4294967295
for line in io.lines() do
  local a={}
  for word in line:gmatch("%S+") do a[#a+1]=tonumber(word) or word end
  if a[1]=="Q" then
    print(("%.0f"):format(L.replenish(a[2],a[5],a[3],a[4])))
  else
    local w,d,sx,sz,ex,ez,diagonal=a[2],a[3],a[4]+1,a[5]+1,a[6]+1,a[7]+1,a[8]==1
    local function index(x,z) return x and ((z-1)*w+x-1) or invalid end
    if a[1]=="I" then
      local g=T.new(w-1,d-1)
      local out={}
      for x,z in L.points(g,ex,ez,sx,sz,diagonal) do out[#out+1]=index(x,z).."," end
      print(table.concat(out))
    else
      local mode=({[0]="level","raise","lower"})[a[9]]
      local exec=a[10]==1
      local g=T.new(w-1,d-1,function(x,z) return a[21+index(x,z)] end,
        {freeform_edges=a[14]==1,max_height=a[15]})
      local p,err,mark_x,mark_z=L.level(g,sx,sz,ex,ez,mode,diagonal,{
        stock_test=not exec,cash=a[11],allowance=a[12]>=0 and a[12] or nil,unit_cost=a[13],
        validate_tile=function(pass,x,z)
          local n=index(x,z)
          if n==a[16] then return nil,"PROTECTED_TILE" end
          return (n%3)*10
        end,
        bridge_height=function(x,z) if index(x,z)==a[17] then return a[18] end end,
        tunnel_in_way=function(x,z,h) return index(x,z)==a[19] and h<=a[20] end
      })
      local code=p and 0 or assert(codes[err],err)
      local cost,require_money,allowance=0,0,a[12]
      local error_tile=index(mark_x,mark_z)
      if p then
        cost,require_money,allowance=p.cost,p.required_money or 0,p.allowance_after or allowance
        error_tile=index(p.error_x,p.error_z)
        if exec then assert(L.apply(g,p)) end
      end
      local out,dirty={},{}
      for _,v in ipairs(g.levels) do out[#out+1]=v.."," end
      if p then for _,q in ipairs(p.dirty) do dirty[#dirty+1]=index(q.x,q.z).."," end end
      print(table.concat({code,cost,require_money,error_tile,allowance,table.concat(out),table.concat(dirty)},"|"))
    end
  end
end
"""

def block(pattern, source):
    m = re.search(pattern, source, re.M)
    start = source.index("{", m.start())
    n, end = 1, start
    while n:
        end += 1
        n += (source[end]=="{") - (source[end]=="}")
    return source[m.start():end+1]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    def read(name):
        p=a.source/name
        return p.read_text() if p.exists() else (a.source/"src"/name).read_text()
    terra=read("terraform_cmd.cpp")
    assert hashlib.sha256(terra.encode()).hexdigest()=="1390a6fffa9ff9f4cec1b2845b3dc1ca465384d1a641a239744c558c51daa012"
    bodies=[]
    for sig in (
        r"^struct TerraformerState", r"^static int TerraformGetHeightOfTile", r"^static void TerraformSetHeightOfTile",
        r"^static void TerraformAddDirtyTile\(", r"^static void TerraformAddDirtyTileAround",
        r"^static std::tuple<CommandCost, TileIndex> TerraformTileHeight",r"^std::tuple<CommandCost, Money, TileIndex> CmdTerraformLand",
    ):
        bodies.append(block(sig,terra)+(";" if sig.startswith("^struct") else ""))
    bodies.append("template <int C> auto Command<C>::Do(DoCommandFlag f, TileIndex t, Slope s, bool up)"
                  "{ return CmdTerraformLand(f,t,s,up); }")
    bodies.append(block(r"^std::tuple<CommandCost, Money, TileIndex> CmdLevelLand",terra))
    areas,headers=read("tilearea.cpp"),read("tilearea_type.h")
    for pat in (r"^OrthogonalTileArea::OrthogonalTileArea\(TileIndex", r"^DiagonalTileArea::DiagonalTileArea\(",
                r"^TileIterator &DiagonalTileIterator::operator\+\+",r"^/\* static \*/ std::unique_ptr<TileIterator> TileIterator::Create"):
        bodies.append(block(pat,areas))
    bodies.append(block(r"^\s*inline TileIterator& operator \+\+\(\) override", headers)
                  .replace("inline TileIterator& operator ++() override", "TileIterator& OrthogonalTileIterator::operator ++()"))
    bodies.append(block(r"^static constexpr void UpdateLandscapingLimit",read("company_cmd.cpp")))

    rng=random.Random(141)
    lines=[]
    for i in range(13000):
        w,d=rng.randint(5,12),rng.randint(5,12)
        sx,sz,ex,ez=rng.randrange(w),rng.randrange(d),rng.randrange(w),rng.randrange(d)
        diagonal=i%2
        lines.append(f"I {w} {d} {sx} {sz} {ex} {ez} {diagonal}")
        if i<3000:
            summits=[(rng.randrange(w),rng.randrange(d),rng.randrange(8)) for _ in range(3)]
            h=lambda x,z: max(0,*(p-abs(x-u)-abs(z-v) for u,v,p in summits))
            freeform=i%7!=0
            price=[1,20,50,250][i%4]
            maxh=8
            cost=[0,250,500,750,1200,5000,50000][i%7]
            allowance=[-1,0,65536,131072,5*65536+76,20*65536,4096*65536][i%7]
            obstacle=4294967295 if i%4 else rng.randrange(w*d)
            bridge=4294967295 if i%5 else rng.randrange(w*d)
            tunnel=4294967295 if i%6 else rng.randrange(w*d)
            deck,th=rng.randrange(9),rng.randrange(6)
            heights=" ".join(str(h(x,z)) for z in range(d) for x in range(w))
            lines.append(f"T {w} {d} {sx} {sz} {ex} {ez} {diagonal} {i%3} {int(i%6!=1)} {cost} "
                         f"{allowance} {price} {int(freeform)} {maxh} {obstacle} {bridge} {deck} {tunnel} {th} {heights}")
    for _ in range(300):
        lines.append(f"Q {rng.randrange(1<<31)} {rng.randrange(1<<30)} {rng.randint(1,32768)} {rng.randint(1,100)}")
    fixture=("\n".join(lines)+"\n").encode()
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/"ref.cpp").write_text(SHIM+"\n"+"\n".join(bodies)+"\n"+DRIVER)
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++20","-O2",str(tmp/"ref.cpp"),"-o",str(tmp/"ref")],check=True)
        stock=subprocess.check_output([str(tmp/"ref")],input=fixture).splitlines()
        lua=subprocess.check_output([a.lua,str(tmp/"port.lua")],cwd=ROOT,input=fixture).splitlines()
    assert len(stock)==len(lua)==len(lines)
    for i,(x,y) in enumerate(zip(stock,lua)):
        if x!=y: raise AssertionError(f"{lines[i]}: stock {x!r} != Lua {y!r}")
    print("PASS: 13,000 stock rectangle/diagonal orders, 3,000 command results and 300 company quota cases")

if __name__=="__main__":
    main()
