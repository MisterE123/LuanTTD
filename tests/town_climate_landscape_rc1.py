#!/usr/bin/env python3
"""Compare the actual RC1 climate terrain kernels with a bounded board adapter.

Usage: python3 tests/town_climate_landscape_rc1.py /path/to/OpenTTD [lua5.1]
The interim scheduler visits all clear cells once after 256 stub calls.
Actual clear desert and Arctic snow transitions come from compiled RC1.
This isolates terrain kernels; it is not the complete generation loop.
"""
from hashlib import sha256
from pathlib import Path
import os
import random
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"

def read(name,digest):
    data=(src/name).read_bytes()
    assert sha256(data).hexdigest()==digest, f"not pinned RC1: {name}"
    return data.decode()

def fn(text,sig):
    i=text.index(sig)
    j=text.index("{",i)
    depth=1
    while depth:
        j+=1
        depth+=(text[j]=="{")-(text[j]=="}")
    return text[i:j+1]

land=read("landscape.cpp","c6166aa9c4ce20475d0f376d7b651dda40b5e6089f7382410da709f0d00ac2d6")
offset=read("table/genland.h","6ed0950b602283bc0b6ad2332f267898f4cbc76e134b1a0c3c62b0a5a56d5282")
clear=read("clear_cmd.cpp","f7371b59b0ad26b5b0c7d24f9eff7fad5b5dc8d57500fdd2599e5e0af47cd7ae")
cpp=r"""
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <numeric>
#include <vector>
using uint=unsigned;
using TileIndex=int;
constexpr int INVALID_TILE=-1, MAX_TILE_HEIGHT=255, TILE_UPDATE_FREQUENCY=256;
enum class TileType { Void=0, Clear=1, Water=2, Other=3 };
enum class TropicZone { Normal, Desert, Rainforest };
enum class ClearGround { Grass, Rough, Rocks, Desert };
enum class WaterClass { Sea, River };
enum class GenWorldProgress { Landscape };
enum class DiagDirection { NE, SE, SW, NW, End };
template<class T> auto EnumRange(T) { return std::array{T::NE,T::SE,T::SW,T::NW}; }
struct TileIndexDiffC {int x,y;};
int w,h,ticks;
struct Cell {
    uint height=0;
    int type=0;
    TropicZone zone=TropicZone::Normal;
    ClearGround ground=ClearGround::Grass;
    uint density=0;
    bool snow=false;
};
std::vector<Cell> board;
struct Map {
    static uint Size(){return w*h;}
    static std::vector<int> Iterate(){std::vector<int> v(Size());std::iota(v.begin(),v.end(),0);return v;}
};
TileIndexDiffC TileIndexDiffCByDiagDir(DiagDirection d){
    return std::array<TileIndexDiffC,4>{{{-1,0},{0,1},{1,0},{0,-1}}}[int(d)];
}
TileIndex AddTileIndexDiffCWrap(TileIndex t,TileIndexDiffC p){
    const int x=t%w+p.x,z=t/w+p.y;
    return x<0 || x>=w || z<0 || z>=h ? INVALID_TILE : z*w+x;
}
bool IsValidTile(TileIndex t){return t>=0 && t<w*h && board[t].type!=0;}
bool IsTileType(TileIndex t,TileType type){return board[t].type==int(type);}
uint TileHeight(TileIndex t){return board[t].height;}
bool IsClearGround(TileIndex t,ClearGround g){return board[t].ground==g;}
void SetTropicZone(TileIndex t,TropicZone z){board[t].zone=z;}
TropicZone GetTropicZone(TileIndex t){return board[t].zone;}
bool HasTileWaterClass(TileIndex t){return board[t].type==2;}
WaterClass GetWaterClass(TileIndex t){return (t&1)?WaterClass::Sea:WaterClass::River;}
int TileOffsByDiagDir(DiagDirection d){return std::array{-1,w,1,-w}[int(d)];}
ClearGround GetClearGround(TileIndex t){return board[t].ground;}
uint GetClearDensity(TileIndex t){return board[t].density;}
void SetClearGroundDensity(TileIndex t,ClearGround g,uint d){board[t].ground=g;board[t].density=d;}
void MarkTileDirtyByTile(TileIndex){}
void IncreaseGeneratingWorldProgress(GenWorldProgress){}
int GetTileZ(TileIndex t){return board[t].height/2;}
int GetSnowLine();
bool IsSnowTile(TileIndex t){return board[t].snow;}
void MakeSnow(TileIndex t,uint d){board[t].snow=true;board[t].density=d;}
void ClearSnow(TileIndex t){board[t].snow=false;board[t].density=0;}
void AddClearDensity(TileIndex t,int d){board[t].density+=d;}
void RunTileLoop();
struct {struct {int desert_coverage,snow_coverage,snow_line_height;} game_creation;} _settings_game;
"""
cpp+=offset+"\n"
for signature in ("static inline bool NeighbourIsNormal","static void TileLoopClearDesert","static void TileLoopClearAlps"):
    cpp+=fn(clear,signature)+"\n"
cpp+=r"""
void RunTileLoop(){
    if(++ticks==TILE_UPDATE_FREQUENCY) for(int t=0;t<w*h;++t) {
        if(IsTileType(t,TileType::Clear)) TileLoopClearDesert(t);
    }
}
int GetSnowLine(){return _settings_game.game_creation.snow_line_height;}
"""
for signature in ("static uint CalculateCoverageLine", "static void CalculateSnowLine",
                  "static uint8_t CalculateDesertLine", "static void CreateDesertOrRainForest"):
    cpp+=fn(land,signature)+"\n"
cpp+=r"""
int main(){
    int cover;
    while(std::cin>>w>>h>>cover){
        board.assign(w*h,{});
        for(auto &c:board){
            int word;
            std::cin>>c.height>>c.type>>word;
            c.ground=ClearGround(word/4);
            c.density=word%4;
        }
        ticks=0;
        auto &p=_settings_game.game_creation;
        p.snow_coverage=p.desert_coverage=cover;
        CalculateSnowLine();
        auto desert=CalculateDesertLine();
        CreateDesertOrRainForest(desert);
        std::cout<<p.snow_line_height<<" "<<int(desert)<<" "<<ticks<<" ";
        for(auto &c:board) std::cout<<int(c.zone);
        std::cout<<" ";
        for(auto &c:board) std::cout<<"0123456789abcdef"[4*int(c.ground)+c.density];
        std::cout<<" ";
        for(int t=0;t<w*h;++t){
            auto &c=board[t];c.snow=t%2==0;
            TileLoopClearAlps(t);
            std::cout<<((c.snow?4:0)+c.density);
        }
        std::cout<<"\n";
    }
}
"""
program=r"""
local C=dofile("mods/luanttd_core/openttd/town_climate_landscape_rc1.lua")
do
  -- Use the separately source-checked spiral. All desert sites in the
  -- clipped footprint change and a rainforest site does not.
  local w,d,x,z=8,10,0,1
  local rainforest=1
  local changed={}
  local stage=0
  local board={width=w,depth=d,height=function(i,j) return i+j end,
    zone=function(i,j) return i+j*w==rainforest and C.RAINFOREST or
      changed[i+j*w] or C.DESERT end,
    set_zone=function(i,j,v)
      assert(stage==3)
      assert(v==C.NORMAL and changed[i+j*w]==nil)
      changed[i+j*w]=v
    end}
  local snow=4
  local read=C.town_lookup(board,function() return snow end)
  assert(read(x,z).is_desert and read(x,z).tile_height==1 and read(x,z).snowline==4)
  C.river_tile(board,x+z*w,function()
    assert(stage==0);stage=1;return 198514
  end,function(t,r)
    assert(stage==1 and t==8 and r==198514);stage=2
  end,function(t)
    assert(stage==2 and t==8);stage=3
  end)
  for j=0,d-1 do for i=0,w-1 do
    local n=i+j*w
    assert((changed[n]==C.NORMAL)==(i<=2 and j<=3 and n~=rainforest))
  end end
  snow=5
  assert(not read(x,z).is_desert and read(x,z).snowline==5)
  assert(board.zone(1,0)==C.RAINFOREST)
end
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  local w,d,coverage=a[1],a[2],a[3]
  local function id(x,z) return z*w+x+1 end
  local function input(x,z,k) return a[3*id(x,z)+k] end
  local zones,ground,code={},{},{}
  local names={"grass","rough","rocks","desert"}
  local counts={}
  for i,g in ipairs(names) do code[g]=i-1 end
  for i=1,w*d do
    local word=a[3*i+3]
    ground[i],counts[i]=names[math.floor(word/4)+1],word%4
  end
  local ticks=0
  local board={
    width=w,depth=d,valid=function(x,z) return input(x,z,2)~=0 end,
    height=function(x,z) return input(x,z,1) end,
    is_water=function(x,z) return input(x,z,2)==2 end,
    is_clear_desert=function(x,z)
      return input(x,z,2)==1 and ground[id(x,z)]=="desert"
    end,
    set_zone=function(x,z,v) zones[id(x,z)]=v end,
  }
  local snow,desert=C.snow_line(board,coverage),C.desert_line(board,coverage)
  C.classify_tropic(board,desert,function()
    ticks=ticks+1
    if ticks==256 then for i=1,w*d do
      if a[3*i+2]==1 then
        local g,n=C.clear_desert(ground[i],counts[i],zones[i],function()
          return C.normal_neighbor(w,i,function(q) return q>=1 and q<=w*d and a[3*q+2]~=0 end,
            function(q) return zones[q]==C.DESERT end,function(q) return a[3*q+2]==2 and q%2==0 end)
        end)
        if g then ground[i],counts[i]=g,n end
      end
    end end
  end)
  local dry,alp={},{}
  for i=1,w*d do
    zones[i]=zones[i] or C.NORMAL
    dry[i]=string.format("%x",4*code[ground[i]]+counts[i])
    local sn,den=i%2==1,counts[i]
    local op,next_density=C.clear_snow(math.floor(a[3*i+1]/2),snow,sn,den)
    if op=="make" then sn,den=true,next_density
    elseif op=="clear" then sn,den=false,0
    elseif op=="density" then den=next_density end
    alp[i]=(sn and 4 or 0)+den
  end
  io.write(snow," ",desert," ",ticks," ",table.concat(zones)," ",table.concat(dry)," ",table.concat(alp),"\n")
end
"""
rng=random.Random(16022)
rows=[]
for geometry in range(12):
    w,d=16+geometry%3*4,14+geometry%4*5
    cells=[]
    for z in range(d):
        for x in range(w):
            if geometry==0:
                height,tile=0,2
            elif geometry==1:
                height,tile=1,1
            elif geometry==2:
                height,tile=255,1
            else:
                height=(x//4+z//5+geometry)%11
                tile=2 if x//4==geometry%5 and z>2 else 1
                if geometry%4==0 and rng.random()<.08:
                    height,tile=0,2
                if geometry%5==0 and rng.random()<.16:
                    tile=3
            if x==w-1 or z==d-1 or (geometry%2 and (x==0 or z==0)):
                tile=0
            ground=(rng.randrange(1,4) if geometry in (6,9,11) and rng.random()<.20 else 0)
            cells.extend([height,tile,4*ground+rng.randrange(4)])
    for coverage in [0,1,20,40,50,73,98,99,100]:
        rows.append([w,d,coverage]+cells)
data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
with tempfile.TemporaryDirectory(prefix="luanttd-rc1-climate-") as tmp:
    p=Path(tmp)
    (p/"reference.cc").write_text(cpp)
    (p/"test.lua").write_text(program)
    subprocess.run([os.environ.get("CXX","c++"),"-std=c++20","-O2",p/"reference.cc","-o",p/"reference"],check=True)
    reference=subprocess.check_output([p/"reference"],text=True,input=data).splitlines()
    actual=subprocess.check_output([lua,p/"test.lua"],cwd=root,text=True,input=data).splitlines()
assert len(reference)==len(actual)==len(rows)
for i,(a,b) in enumerate(zip(reference,actual)):
    assert a==b,(i,rows[i][:3],a,b)
counts=[sum(line.split()[3].count(str(zone)) for line in reference) for zone in range(3)]
assert all(counts)
print(f"PASS {len(rows)} RC1 climate thresholds and zone boards; {sum(counts)} exact climate tiles (normal/desert/rainforest {counts})")
