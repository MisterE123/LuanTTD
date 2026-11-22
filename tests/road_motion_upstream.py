#!/usr/bin/env python3
"""Compare the motion kernel with pinned OpenTTD input and heading functions."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHIM = '''#include <cstdio>
using byte = unsigned char;
using uint = unsigned int;
enum Direction { DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW, INVALID_DIR=255 };
enum { DIAGDIR_NE, DIAGDIR_SE, DIAGDIR_SW, DIAGDIR_NW };
enum DirDiff { DIRDIFF_45RIGHT=1, DIRDIFF_REVERSE=4, DIRDIFF_45LEFT=7 };
enum { RDE_NEXT_TILE=128, RDE_TURNED=64 };
struct RoadDriveEntry { byte x, y; };
struct RoadVehicle { int x_pos, y_pos; Direction direction; };
inline bool IsValidDirection(Direction d) { return d < INVALID_DIR; }
#include <cassert>
#include "roadveh_movement.h"
'''
DRIVER = r'''
int main() {
  for (int side=0; side<2; ++side) for (int over=0; over<2; ++over) {
    for (int state=0; state<80; ++state) {
      if (state>=48 && state<64) continue;
      int index=((state>=64 ? state & 9 : state) + side*16) ^ (over*16);
      auto row=_road_road_drive_data[index];
      for (int f=0;; ++f) {
        auto r=row[f];
        if (r.x & RDE_NEXT_TILE) { std::printf("next_tile,%d\n",r.x & 3); break; }
        if (r.x & RDE_TURNED) { std::printf("turned,%d\n",r.x & 3); break; }
        std::printf("position,%d,%d\n",r.x,r.y);
        // Use a non-origin tile; the step uses tile-relative low bits.
        for (int h=0; h<8; ++h) for (int dx=-2; dx<=2; ++dx) for (int dy=-2; dy<=2; ++dy) {
          RoadVehicle v={48+r.x+dx,80+r.y+dy,Direction(h)};
          int x=(v.x_pos & ~15) + (r.x & 15), y=(v.y_pos & ~15) + (r.y & 15);
          auto d=RoadVehGetSlidingDirection(&v,x,y);
          if (d!=v.direction) std::printf("rotate,%d,%d,%d,%d\n",v.x_pos,v.y_pos,d,f-1);
          else std::printf("move,%d,%d,%d,%d\n",x,y,d,f);
          x=48+r.x; y=80+r.y;
          d=RoadVehGetSlidingDirection(&v,x,y);
          std::printf("enter,%d,%d,%d,%d\n",x,y,d,f);
        }
      }
    }
  }
}
'''
LUA = '''
local M=dofile("mods/bayline/openttd/road_motion.lua")(dofile("mods/bayline/openttd/road_motion_data.lua"))
local function line(...) print(table.concat({...},",")) end
for side=0,1 do for over=0,1 do for state=0,79 do
  if state<48 or state>=64 then
  for f=0,64 do
    local kind,x,y=M.sample(state,side,f,over==1)
    assert(kind)
    line(kind,x,y)
    if kind~="position" then break end
    for h=0,7 do for dx=-2,2 do for dy=-2,2 do
      local v={x=48+x+dx,y=80+y+dy,direction=h,state=state,frame=f-1}
      line(M.step(v,side,over==1))
      line(M.enter(v,3,5,state,side,f,over==1))
    end end end
  end
  end
end end end
'''


def extract(src, signature):
    start = src.index(signature)
    return src[start:src.index("\n}", start)+2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path, help="folder with roadveh_cmd.cpp, direction_func.h and roadveh_movement.h")
    p.add_argument("--lua", default="lua5.1")
    a = p.parse_args()
    subprocess.run(["python3", "tools/import_road_motion.py", str(a.source/"roadveh_movement.h"),
                    "--check"], cwd=ROOT, check=True)
    cmds = (a.source/"roadveh_cmd.cpp").read_text()
    dirs = (a.source/"direction_func.h").read_text()
    body = "\n".join(extract(dirs,s) for s in ("inline DirDiff DirDifference(Direction",
                                                "inline Direction ChangeDir(Direction"))
    body += "\n" + "\n".join(extract(cmds,s) for s in ("static Direction RoadVehGetNewDirection(",
                                                       "static Direction RoadVehGetSlidingDirection("))
    with tempfile.TemporaryDirectory() as directory:
        t = Path(directory)
        (t/"dump.cpp").write_text(SHIM+body+DRIVER)
        (t/"trace.lua").write_text(LUA)
        subprocess.run(["c++","-O2","-std=c++17","-I",str(a.source.resolve()),str(t/"dump.cpp"),
                        "-o",str(t/"dump")],check=True)
        cpp=subprocess.check_output([str(t/"dump")])
        lua=subprocess.check_output([a.lua,str(t/"trace.lua")],cwd=ROOT)
        if cpp!=lua:
            for i,(a,b) in enumerate(zip(cpp.splitlines(),lua.splitlines()),1):
                if a!=b: raise AssertionError(f"line {i}: OpenTTD {a!r} != Lua {b!r}")
            raise AssertionError("output lengths differ")
    print(f"PASS: {cpp.count(bytes([10])):,} source trace rows covering motion samples, headings and frame commits")


if __name__ == "__main__":
    main()
