#!/usr/bin/env python3
"""Compare the Lua integer port against source from an OpenTTD 14.1 checkout.

Usage: python3 tests/slope_upstream.py /path/to/OpenTTD lua5.1
Accepts either the Git source directory or the verified file download directory.
The harness extracts the two named C++ functions and the enums, unmodified.
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

def source(part, digest):
    root = Path(sys.argv[1])
    path = root / "src" / part
    if not path.exists():
        path = root / part
    original = path.read_bytes()
    assert sha256(original).hexdigest() == digest, f"Not the pinned OpenTTD source: {path}"
    return original.decode()

def block(text, pattern):
    start = re.search(pattern, text, re.MULTILINE).start()
    at = text.index("{", start)
    depth = 1
    while depth:
        at += 1
        depth += (text[at] == "{") - (text[at] == "}")
    return text[start:at+1]

land = source("landscape.cpp", "0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97")
tile = source("tile_map.cpp", "479ae6451fa7af6b430e0c98ea6cdefbfbf4d9f2d482ee6c7c4e4054fca93fb3")
enums = source("slope_type.h", "3e148047939fd2a84ab8c480df4237504005408c2f9a7a64d43795c64e2672b9")
cpp = """
#include <algorithm>
#include <cstdio>
#include <cstdlib>
using byte = unsigned char;
using uint = unsigned int;
constexpr int TILE_SIZE = 16, TILE_HEIGHT = 8;
#define NOT_REACHED() std::abort()
""" + block(enums, r"^enum Corner \{") + ";\n" + block(enums, r"^enum Slope : byte \{") + ";\n" + """
Slope &operator|=(Slope &s, Slope b) {return s = static_cast<Slope>(s|b);}
bool IsHalftileSlope(Slope s) {return s & SLOPE_HALFTILE;}
Corner GetHalftileSlopeCorner(Slope s) {return static_cast<Corner>(s >> 6);}
Slope RemoveHalftileSlope(Slope s) {return static_cast<Slope>(s & ~SLOPE_HALFTILE_MASK);}
int GetSlopeMaxPixelZ(Slope s) {return s & SLOPE_STEEP ? 16 : s ? 8 : 0;}
""" + block(tile, r"^static Slope GetTileSlopeGivenHeight") + "\n" + block(land, r"^uint GetPartialPixelZ") + """
int main(){
  for(int n=0;n<4;n++)for(int w=0;w<4;w++)for(int e=0;e<4;e++)for(int s=0;s<4;s++){
    if(abs(n-w)>1||abs(n-e)>1||abs(s-w)>1||abs(s-e)>1)continue;
    int base;
    int mask=GetTileSlopeGivenHeight(n,w,e,s,&base);
    printf("c %d %d %d %d %d %d\\n",n,w,e,s,mask,base);
  }
  for(int a=0;a<5;a++)for(int s=0;s<=30;s++){
    if(s>=16 && s!=23 && s!=27 && s!=29 && s!=30) continue;
    int code=s+(a ? 32+64*(a-1) : 0);
    for(int x=0;x<16;x++)for(int y=0;y<16;y++)
      printf("p %d %d %d %u\\n",x,y,code,GetPartialPixelZ(x,y,static_cast<Slope>(code)));
  }
}
"""
lua = r"""
local T=dofile('mods/bayline/openttd/slope.lua')
local n=0
for line in io.lines() do
  local parts={}
  for field in line:gmatch('%d+') do parts[#parts+1]=tonumber(field) end
  if line:sub(1,1)=='c' then
    local a,b=T.classify(unpack(parts,1,4))
    assert(a==parts[5] and b==parts[6],line)
    for i,point in ipairs({{0,0},{1,0},{0,1},{1,1}}) do
      assert(T.surface(point[1],point[2],a)+b==parts[i],line)
    end
  else
    assert(T.pixel(parts[1],parts[2],parts[3])==parts[4],line)
  end
  n=n+1
end
assert(n>24000)
local s,h=T.foundation(29,'leveled')
assert(s==0 and h==2)
s,h=T.foundation(29,'x')
assert(s==12 and h==1)
s,h=T.foundation(29,'steep_both')
assert(s==232 and h==1)
print('PASS: '..n..' C++/Lua samples, continuous corner checks, and three foundation fixtures')
"""
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    (tmp / "ref.cpp").write_text(cpp)
    subprocess.run(["c++", "-O2", str(tmp / "ref.cpp"), "-o", str(tmp / "ref")], check=True)
    samples = subprocess.check_output([tmp / "ref"])
    (tmp / "verify.lua").write_text(lua)
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1", tmp / "verify.lua"], input=samples, check=True,
                   cwd=Path(__file__).resolve().parents[1])
