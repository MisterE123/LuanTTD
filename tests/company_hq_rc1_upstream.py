#!/usr/bin/env python3
"""Compile pinned headquarters level and cargo production expressions."""
from argparse import ArgumentParser
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
from terragenesis_clear_rc1_upstream import extract

p=ArgumentParser(description=__doc__)
p.add_argument("source",type=Path)
p.add_argument("--lua",default="lua5.1")
a=p.parse_args()
src=a.source/"src"
obj=(src/"object_cmd.cpp").read_text()
up=extract(obj,"void UpdateCompanyHQ(")
prod=obj[obj.index("static void TileLoop_Object("):]
tests=[(lo,prod[prod.index(lo):]) for lo in ("uint amt = GB(r, 0, 8)", "uint amt = GB(r, 8, 8)")]
p_amount,m_amount=(part[:part.index("/* Scale by cargo scale setting. */")] for _,part in tests)
cpp=r"""
#include <iostream>
#include <cstdint>
using TileIndex=int;
using uint=unsigned;
static uint8_t old;
constexpr TileIndex INVALID_TILE=-1;
uint8_t GetCompanyHQSize(TileIndex){return old;}
void IncreaseCompanyHQSize(TileIndex){++old;}
uint GB(uint n,uint start,uint len){return (n>>start)&((1<<len)-1);}
UPSTREAM
int main(){
for(int start=0;start<5;start++)for(int score=0;score<=1000;score++){
 old=start;UpdateCompanyHQ(1,score);std::cout.put(char(old));}
for(uint level=1;level<=5;level++) for(bool recession:{false,true}) for(uint r=0;r<65536;r++){
 auto EconomyIsInRecession=[&]{return recession;};
 uint p=0,m=0;
 if(GB(r,0,8)<(256/4/(6-level))){
P_AMOUNT
 p=amt;
 }
 if(GB(r,8,8)<(196/4/(6-level))){
M_AMOUNT
 m=amt;
 }
 std::cout.put(char(p+m*4));
}
}
""".replace("UPSTREAM",up).replace("P_AMOUNT",p_amount).replace("M_AMOUNT",m_amount)
lua=r"""
local Q=dofile("mods/luanttd_core/openttd/company_hq_rc1.lua")
for old=0,4 do for score=0,1000 do io.write(string.char(Q.stage(score,old))) end end
for level=0,4 do
 for recession=0,1 do
  for r=0,65535 do
   local p,m=Q.produce(level,r,recession==1)
   io.write(string.char(p+m*4))
  end
 end
end
"""
with TemporaryDirectory() as work:
    tmp=Path(work)
    (tmp/"hq.cpp").write_text(cpp)
    exe=tmp/"hq"
    subprocess.run(["g++","-std=c++20","-O2",str(tmp/"hq.cpp"),"-o",str(exe)],check=True)
    expected=subprocess.check_output([exe])
actual=subprocess.check_output([a.lua,"-e",lua])
assert actual==expected and len(actual)==5*1001+5*2*65536
print("PASS pinned company HQ stages and cargo production for all 65,536 random-byte pairs")
