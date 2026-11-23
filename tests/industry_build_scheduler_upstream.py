#!/usr/bin/env python3
"""Compile RC1 industry builder functions and compare full state and RNG usage."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import sys

root=Path(sys.argv[1]).resolve()
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
game=Path(__file__).resolve().parents[1]
src=(root/"src/industry_cmd.cpp").read_text()
economy=(root/"src/economy.cpp").read_text()
def function(text,marker):
    a=text.index(marker); i=text.index("{",a); end=i+1; balance=1
    while balance:
        balance+=(text[end]=="{")-(text[end]=="}")
        end+=1
    return text[a:end]

cpp = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint=unsigned int;
constexpr int NUM_INDUSTRYTYPES=7;
using IndustryType=int;
unsigned width,height;
struct Map {
 static uint ScaleBySize(uint n) { return (uint64_t(n)*width*height+65535)/65536; }
 static uint LogX() {return __builtin_ctz(width);}
 static uint LogY() {return __builtin_ctz(height);}
};
enum IndustryDensity { FundedOnly,Normal };
struct {struct {IndustryDensity industry_density=Normal;} difficulty;} _settings_game;
struct {uint32_t industry_daily_increment,industry_daily_change_counter;} _economy;
int counts[NUM_INDUSTRYTYPES];
int year,attempt,chosen,placed,notices;
uint32_t rng,draws;
bool recession;
struct Industry {
 static uint GetIndustryTypeCount(int it) {return counts[it];}
};
enum class IndustryAvailabilityCallType {RandomCreation};
uint GetCurrentTotalNumberOfIndustries() { uint n=0;for(int c:counts)n+=c;return n; }
uint32_t Random() {draws++;return rng=1664525u*rng+1013904223u;}
uint32_t RandomRange(uint32_t n) {return (uint64_t(Random())*n)>>32;}
uint16_t GetIndustryGamePlayProbability(IndustryType it, uint8_t *min) {
 *min=0;
 if (_settings_game.difficulty.industry_density==FundedOnly || it==5 && year<1960 || it==1 && year>1950) return 0;
 *min=it==0 || it==3;
 const uint16_t w[]={3,2,5,4,2,6,1};
 return w[it];
}
const Industry *PlaceIndustry(IndustryType it,IndustryAvailabilityCallType,bool) {
 static Industry ind; chosen=it;
 if (RandomRange(17)<unsigned((it+attempt)%8+3)) {counts[it]++;placed=it;return &ind;}
 return nullptr;
}
void AdvertiseIndustryOpening(const Industry *) {notices++;}
bool EconomyIsInRecession() { return recession; }
struct IndustryTypeBuildData {
 uint32_t probability;
 uint8_t min_number;
 uint16_t target_count,max_wait,wait_count;
 void Reset();
 bool GetIndustryTypeData(IndustryType);
};
struct IndustryBuildData {
 IndustryTypeBuildData builddata[NUM_INDUSTRYTYPES];
 uint32_t wanted_inds;
 void Reset(); void EconomyMonthlyLoop(); void SetupTargetCount(); void TryBuildNewIndustry();
};
"""
for name in ("void IndustryTypeBuildData::Reset()","void IndustryBuildData::Reset()",
        "void IndustryBuildData::EconomyMonthlyLoop()","bool IndustryTypeBuildData::GetIndustryTypeData(",
        "void IndustryBuildData::SetupTargetCount()","void IndustryBuildData::TryBuildNewIndustry()"):
    cpp+=function(src,name)+"\n"
cpp+=function(economy,"void StartupIndustryDailyChanges(")
cpp+=r"""
int main() {
 for (auto xy: {std::pair{64,64},std::pair{256,512},std::pair{4096,4096}}) {
  width=xy.first;height=xy.second;
  StartupIndustryDailyChanges(true);
  for (int &x:counts) x=0;
  counts[0]=2;counts[1]=3;counts[2]=5;
  IndustryBuildData s{};s.Reset();rng=0xc10392b2u;draws=notices=0;
  for(attempt=0;attempt<568;attempt++) {
   year=1947+attempt/26;
   _settings_game.difficulty.industry_density=(attempt%83==0)?FundedOnly:Normal;
   recession=attempt%11<2;chosen=placed=-1;
   if (attempt%15==13 && counts[0]>0) counts[0]--;
   if (attempt%19==16 && counts[2]>0) counts[2]--;
   if (attempt%2==0 || attempt>87 && attempt<262) s.EconomyMonthlyLoop();
   s.TryBuildNewIndustry();
   std::cout<<width<<' '<<attempt<<' '<<s.wanted_inds<<' '<<draws<<' '<<rng<<' '
        <<chosen<<' '<<placed<<' '<<notices;
   for(int i=0;i<NUM_INDUSTRYTYPES;i++) {
    const auto &b=s.builddata[i];
    std::cout<<' '<<b.probability<<' '<<+b.min_number<<' '<<b.target_count
        <<' '<<b.max_wait<<' '<<b.wait_count<<' '<<counts[i];
   }
   std::cout<<'\n';
  }
  std::cout<<"increment "<<_economy.industry_daily_increment<<"\n";
 }
}
"""
luascript=r"""
local S=dofile("mods/luanttd_core/openttd/industry_build_scheduler.lua")
local floor=math.floor
for _,dim in ipairs({{64,64},{256,512},{4096,4096}}) do
  local w,h=dim[1],dim[2]
  local counts={[0]=2,3,5,0,0,0,0}
  local s=S.reset(7,10)
  local seed,draws,notices=0xc10392b2,0,0
  local year,attempt,chosen,placed
  local ctx={width=w,height=h,
     random=function() draws=draws+1;seed=(1664525*seed+1013904223)%4294967296;return seed end,
     total=function()
       local n=0;for i=0,6 do n=n+counts[i] end;return n
     end,
     count=function(i) return counts[i] end}
  function ctx.available(i)
    if ctx.funded_only or i==5 and year<1960 or i==1 and year>1950 then return 0,0 end
    return ({[0]=3,2,5,4,2,6,1})[i],(i==0 or i==3) and 1 or 0
  end
  function ctx.place(i)
    chosen=i
    if floor(ctx.random()*17/4294967296)<(i+attempt)%8+3 then
      counts[i]=counts[i]+1;placed=i;return true
    end
  end
  function ctx.advertise() notices=notices+1 end
  for step=0,567 do
    attempt=step
    year=1947+floor(attempt/26)
    ctx.funded_only=attempt%83==0
    ctx.recession=attempt%11<2;chosen,placed=-1,-1
    if attempt%15==13 and counts[0]>0 then counts[0]=counts[0]-1 end
    if attempt%19==16 and counts[2]>0 then counts[2]=counts[2]-1 end
    if attempt%2==0 or attempt>87 and attempt<262 then S.month(s,ctx) end
    S.try_build(s,ctx)
    local a={w,attempt,s.wanted_inds,draws,seed,chosen,placed,notices}
    for i=0,6 do
      local b=s.builddata[i]
      for _,v in ipairs({b.probability,b.min_number,b.target_count,b.max_wait,b.wait_count,counts[i]}) do
        a[#a+1]=v
      end
    end
    print(table.concat(a," "))
  end
  local total=0
  ctx.change_random_industry=function() end
  ctx.random=function() return 65535 end
  for i=1,31 do total=total+S.day(s,ctx) end
  print("increment "..(total*65536+s.daily_counter)/31)
end
-- Check bounded, non-committing placement attempts and exact RNG order.
local n=0
local ctx={width=64,height=128,layout_count=function(i) assert(i==5);return 1 end}
function ctx.random() n=n+1;return 0xa020d24e+n*32121 end
function ctx.create(id,x,z,v,s,b)
  assert(id==5 and v==0 and x<64 and z<128)
  assert(s==0xa020d24e+(n-2)*32121 and b==(0xa020d24e+(n-1)*32121)%65536)
  if n==24 then return 5 end
end
assert(S.place_attempts(ctx,5)==5 and n==24)
ctx.create=function() end
assert(S.place_attempts(ctx,5)==nil and n==8024)
"""
with TemporaryDirectory() as work:
    work = Path(work)
    (work/"ref.cpp").write_text(cpp)
    (work/"port.lua").write_text(luascript)
    subprocess.run(["c++","-O2","-std=c++17",str(work/"ref.cpp"),"-o",str(work/"ref")],check=True)
    official=subprocess.check_output([work/"ref"],text=True).splitlines()
    port=subprocess.check_output([lua,work/"port.lua"],cwd=game,text=True).splitlines()
    assert len(official)==len(port)
    for i,(a,b) in enumerate(zip(official,port)):
        if a!=b:
            raise AssertionError((i,a,b))
print("PASS compiled RC1 industry builder: 1,704 complete checkpoints, all RNG draws, fail/backoff and monthly ceilings; 3 map sizes")
