#!/usr/bin/env python3
"""Run extracted RC1 allocation/scheduling functions against the Lua port."""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rc1_rail_foundation_shim import source_block

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
def read(name,checksum):
    b=(src/name).read_bytes()
    assert sha256(b).hexdigest()==checksum,name
    return b.decode()

industry=read("industry_cmd.cpp","1e6bc18f0c26e56f2c50bad4c9e1039174ad2da7b404750ce688dcea2b10c752")
data=read("table/build_industry.h","eb7938fd37dd37854927253f2f3beeed3c6cafa7425d959035cefef149b66056")
rows=[]
for m in re.finditer(r"MI\(_tile_table_(\w+)\s*,[^\n]+\n([^\n]+)\n([^\n]+)(.*?)(?=\n\s*MI\(_tile_table_|\n\};)",data,re.S):
    key,line,check,flags=m.groups()
    weights=','.join(v.strip() for v in line.split(',')[6:10])
    assert "IndustryBehaviour::NoBuildMapCreation" not in flags
    coastal="Refinery" if "::Refinery" in check else "OilRig" if "::OilRig" in check else "None"
    water=int("IndustryBehaviour::BuiltOnWater" in flags)
    rows.append(f'{{{{{weights}}},IndustryCheck::{coastal},{water},true,{{1}}}},')
assert len(rows)==37
head=r"""
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <optional>
#include <vector>
using uint=unsigned;
using IndustryType=uint;
template<class T> constexpr auto to_underlying(T a){return static_cast<unsigned>(a);}
template<class T,size_t N> constexpr size_t lengthof(const T(&)[N]){return N;}
constexpr uint NUM_INDUSTRYTYPES=37;
enum class IndustryDensity : uint {FundedOnly,Minimal,VeryLow,Low,Normal,High,Custom,End};
enum class GameMode {Normal,Editor};
enum class IndustryAvailabilityCallType {MapGeneration};
enum class IndustryCheck {None,Refinery,OilRig};
enum class IndustryBehaviour {BuiltOnWater,NoBuildMapCreation};
enum class GenWorldProgress {LandIndustries,WaterIndustries};
struct Flags {
  bool water;
  bool Test(IndustryBehaviour b) const {return b==IndustryBehaviour::BuiltOnWater && water;}
};
struct IndustrySpec {
  uint appear_creation[4];
  IndustryCheck check_proc;
  Flags behaviour;
  bool enabled;
  std::vector<int> layouts;
};
struct IndustryPool {static constexpr uint MAX_SIZE=64000;};
struct Map {
  static inline uint width,height,initial_land_count;
  static uint ScaleBySize(uint n){return (uint64_t(n)*width*height+65535)/65536;}
  static uint ScaleBySize1D(uint n){return (uint64_t(n)*(width+height)+511)/512;}
  static uint ScaleByLandProportion(uint n){return uint64_t(n)*initial_land_count/(width*height);}
};
struct Settings {
  struct { uint landscape,custom_industry_number; } game_creation;
  struct { IndustryDensity industry_density; } difficulty;
} _settings_game;
GameMode _game_mode;
uint32_t state;
uint32_t raw() {return state=1664525u*state+1013904223u;}
uint32_t RandomRange(uint32_t n){return (uint64_t(n)*raw())>>32;}
uint32_t GetIndustryProbabilityCallback(IndustryType,IndustryAvailabilityCallType,uint32_t n){return n;}
void PlaceInitialIndustry(IndustryType it,bool water,bool forced) {
  std::cout<<'p'<<it<<','<<water<<','<<forced<<';';
  for(unsigned i=0;i<(it%5)+1;i++) raw();
}
void SetGeneratingWorldProgress(GenWorldProgress stage,uint count) {
  std::cout<<'s'<<(stage==GenWorldProgress::WaterIndustries)<<','<<count<<';';
}
struct {void Reset(){std::cout<<'r';}} _industry_builder;
"""
code=head+"IndustrySpec specs[]={\n"+"\n".join(rows)+"};\n"
code+="const IndustrySpec *GetIndustrySpec(IndustryType it){return &specs[it];}\n"
for sig in (r"^static uint32_t GetScaledIndustryGenerationProbability\(",r"^static uint GetNumberOfIndustries\(",
            r"^struct IndustryGenerationProbabilities \{",r"^static IndustryGenerationProbabilities GetScaledProbabilities\(",
            r"^void GenerateIndustries\("):
    code+=source_block(src,"industry_cmd.cpp",sig)+";\n"
code+=r"""
int main(){
  uint mode,dens;
  uint64_t mask;
  while(std::cin>>Map::width>>Map::height>>Map::initial_land_count
         >>_settings_game.game_creation.landscape>>dens>>mode
         >>_settings_game.game_creation.custom_industry_number>>mask>>state){
    _settings_game.difficulty.industry_density=IndustryDensity(dens);
    _game_mode=mode?GameMode::Editor:GameMode::Normal;
    for(unsigned i=0;i<NUM_INDUSTRYTYPES;i++) specs[i].enabled=(mask>>i)&1;
    std::cout<<GetNumberOfIndustries()<<':';
    for (int phase=-1;phase<=1;phase++) {
      for(unsigned i=0;i<NUM_INDUSTRYTYPES;i++) {
        bool forced=false;
        auto w=GetScaledIndustryGenerationProbability(i,phase<0?std::nullopt:std::optional<bool>(phase),&forced);
        std::cout<<w<<','<<forced<<';';
      }
    }
    GenerateIndustries();
    std::cout<<':'<<state<<'\n';
  }
}
"""
program=r"""
local I=dofile("mods/luanttd_core/openttd/industry_generation_schedule_rc1.lua")
local floor=math.floor
for line in io.lines() do
  local a={}
  for n in line:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local w,h,n,climate,density,editor,custom,mask,state=unpack(a)
  local board={width=w,height=h,initial_land_count=n}
  local settings={landscape=({"temperate","arctic","tropic","toyland"})[climate+1],density=density,
    editor=editor==1,custom_count=custom,enabled={}}
  for id=0,I.LAST_ID do settings.enabled[id]=floor(mask/2^id)%2==1 end
  local function raw() state=(1664525*state+1013904223)%4294967296;return state end
  local out={tostring(I.count(board,settings)),":"}
  for phase=-1,1 do
    local water
    if phase>=0 then water=phase==1 end
    for id=0,I.LAST_ID do
      local p,f=I.probability(board,id,settings,water)
      out[#out+1]=p..","..(f and 1 or 0)..";"
    end
  end
  I.generate(board,settings,raw,function(id,water,force)
    out[#out+1]="p"..id..","..(water and 1 or 0)..","..(force and 1 or 0)..";"
    for _=1,id%5+1 do raw() end
  end,function(water,n)out[#out+1]="s"..(water and 1 or 0)..","..n..";" end,
    function()out[#out+1]="r" end)
  out[#out+1]=(":%.0f"):format(state)
  print(table.concat(out))
end
"""
rng=random.Random(160013)
cases=[]
for climate in range(4):
    for d in range(7):
        for i in range(12):
            w,h=rng.choice((64,128,256,512,1024,2048,4096)),rng.choice((64,128,256,512,1024,2048,4096))
            n=rng.choice((0,1,w*h,rng.randrange(w*h)))
            mask=rng.choice((0,1<<5,(1<<37)-1,rng.getrandbits(37)))
            cases.append((w,h,n,climate,d,i%3==0,rng.randrange(1,900),mask,rng.getrandbits(32)))
inputs="\n".join(" ".join(str(int(v)) for v in a) for a in cases)+"\n"
with tempfile.TemporaryDirectory(prefix="industry-schedule-rc1-") as tmp:
    p=Path(tmp)
    (p/"native.cc").write_text(code)
    (p/"lua.lua").write_text(program)
    subprocess.run(["c++","-std=c++20","-O2",p/"native.cc","-o",p/"native"],check=True)
    native=subprocess.check_output([p/"native"],input=inputs,text=True).splitlines()
    translated=subprocess.check_output([lua,p/"lua.lua"],cwd=root,input=inputs,text=True).splitlines()
assert len(native)==len(translated)==len(cases)
for i,(a,b) in enumerate(zip(native,translated)):
    if a!=b:
        j=next((j for j,(x,y) in enumerate(zip(a,b)) if x!=y),min(len(a),len(b)))
        raise AssertionError((cases[i],j,a[max(0,j-20):j+50],b[max(0,j-20):j+50]))
print(f"PASS {len(cases)} full 37-type RC1 generation schedules: four climates, land and water stages, forced rows and shared RNG")
