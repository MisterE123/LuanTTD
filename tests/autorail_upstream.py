#!/usr/bin/env python3
"""Differential against the pinned 14.1 C++ automatic-rail viewport and track command.
Usage: tests/autorail_upstream.py PATH_TO_OPENTTD_SRC [lua5.1]
"""
import random
import re
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
viewport = (root / "viewport.cpp").read_text()
table = (root / "table/autorail.h").read_text()
rail = (root / "rail_cmd.cpp").read_text()
piece = re.search(r"static const HighLightStyle _autorail_piece.*?\n};", table, re.S).group()
two = viewport.split("static HighLightStyle Check2x1AutoRail", 1)[1].split("/**", 1)[0]
draw = viewport.split("static void CalcRaildirsDrawstyle", 1)[1].split("if (_settings_client.gui.measure_tooltip)", 1)[0]
draw = draw.split("if (method & ~(VPM_RAILDIRS | VPM_SIGNALDIRS))", 1)
assert len(draw) == 2
draw = draw[0] + "if (false) {} else if (TileVirtXY" + draw[1].split("} else if (TileVirtXY", 1)[1]
valid = rail.split("static const TileIndexDiffC _trackdelta[]", 1)[1].split("/**", 1)[0]
cpp = r'''
#include <cstdio>
#include <cstdlib>
#include <cstdint>
using uint = unsigned int;
using HighLightStyle=int; using Trackdir=int; using TileIndex=unsigned;
using CommandCost=int;
struct Point {int x,y;};
using TileIndexDiffC=Point;
struct {Point selstart,selend;} _thd;
Point _tile_fract_coords;
constexpr int HT_DIR_X=0,HT_DIR_Y=1,HT_DIR_HU=2,HT_DIR_HL=3,HT_DIR_VL=4,HT_DIR_VR=5;
constexpr int HT_LINE=8,HT_RAIL=16,HT_RECT=32,VPM_RAILDIRS=1,TILE_SIZE=16,TILE_UNIT_MASK=15,CMD_ERROR=1;
int TileVirtXY(int x,int y){return (y >> 4)*256+(x >> 4);}
int TileX(TileIndex i){return i%256;} int TileY(TileIndex i){return i/256;}
bool ValParamTrackOrientation(int i){return i>=0 && i<6;}
int TrackdirToTrack(int d){return d%8;}
bool IsDiagonalTrackdir(int d){return d%8<2;}
bool HasBit(int a,int b){return (a&(1<<b))!=0;}
void SetBit(int &a,int b){a|=1<<b;}
void NOT_REACHED(){std::abort();}
''' + piece + r'''
static int GetAutorailHT(int x,int y){return HT_RAIL | _autorail_piece[x&15][y&15];}
static HighLightStyle Check2x1AutoRail''' + two + '''
static void CalcRaildirsDrawstyle''' + draw + r'''
printf("%d %d %d",b&7,x,y);
int td=b&7;
int start=TileVirtXY(_thd.selstart.x,_thd.selstart.y),end=TileVirtXY(x,y);
print_trace(td,start,end);
}
'''
decl='static void print_trace(int td,TileIndex start,TileIndex end);\n'
cpp = decl.replace('TileIndex','unsigned') + cpp + '\nstatic const TileIndexDiffC _trackdelta[]' + valid + r'''
static void print_trace(int td,TileIndex start,TileIndex end){
  if (ValidateAutoDrag(&td,start,end)==0) {
    for(unsigned tile=start; ; ){
      printf(" %d,%d,%d",TileX(tile),TileY(tile),TrackdirToTrack(td));
      if(tile==end) break;
      tile+=_trackdelta[td].x+256*_trackdelta[td].y;
      if(!IsDiagonalTrackdir(td)) td^=1;
    }
  }
  puts("");
}
int main() {
  int sx,sy,x,y;
  while(scanf("%d%d%d%d",&sx,&sy,&x,&y)==4){
    _tile_fract_coords={sx&15,sy&15}; _thd.selstart={sx&~15,sy&~15};
    _thd.selend={x,y}; CalcRaildirsDrawstyle(x,y,VPM_RAILDIRS);
  }
}
'''
rng=random.Random(1751)
cases=[(648,328,640+x,320+y) for x in range(16) for y in range(16)]
for dx in range(-10,11):
    for dy in range(-10,11):
        for _ in range(17):
            cases.append((640+rng.randrange(16),320+rng.randrange(16),640+16*dx+rng.randrange(16),320+16*dy+rng.randrange(16)))
data=''.join('%d %d %d %d\n'%v for v in cases)
code='''local base="mods/luanttd_core/openttd/"
local T=dofile(base.."rail_track.lua")
local A=dofile(base.."autorail.lua")(T)
for line in io.lines() do
 local a,b,c,d=line:match("(%d+) (%d+) (%d+) (%d+)")
 a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
 local t,x,z,px,pz=A.snap(a,b,c,d)
 io.write(("%d %d %d"):format(t,px,pz))
 for _,p in ipairs(A.trace(math.floor(a/16),math.floor(b/16),x,z,t) or {}) do
   io.write((" %d,%d,%d"):format(p.x,p.z,p.track))
 end
 io.write("\\n")
end
'''
with tempfile.TemporaryDirectory() as d:
    p=Path(d); (p/'up.cpp').write_text(cpp); (p/'compare.lua').write_text(code)
    subprocess.run(['g++','-O2','-std=c++17',str(p/'up.cpp'),'-o',str(p/'up')],check=True)
    source=subprocess.check_output([str(p/'up')],input=data,text=True).splitlines()
    our=subprocess.check_output([lua,str(p/'compare.lua')],input=data,text=True).splitlines()
assert len(source)==len(our)==len(cases)
for cell,a,b in zip(cases,source,our):
    assert a == b, (cell, a, b)
print(f"PASS: {len(cases):,} exact pinned C++ snap and piece traces, including all in-tile pixels and the two-tile special cases.")
