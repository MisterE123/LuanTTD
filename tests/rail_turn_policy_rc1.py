"""Compare the literal OpenTTD 16.0-RC1 rail-type turn selector with Lua."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
header = (source / "src/rail.h").read_text()
settings = (source / "src/table/settings/pathfinding_settings.ini").read_text()
assert re.search(r"var\s*=\s*pf\.forbid_90_deg\s+def\s*=\s*true.*?cat\s*=\s*SC_EXPERT", settings, re.S)
start = header.index("inline bool Rail90DegTurnDisallowed(")
opening = header.index("{", start)
depth, end = 1, opening + 1
while depth:
    depth += (header[end] == "{") - (header[end] == "}")
    end += 1
shim = r"""
#include <iostream>
using RailType = int;
const int INVALID_RAILTYPE = -1;
enum class RailTypeFlag { Allow90Deg = 1, Disallow90Deg = 2 };
struct Flags { int value; bool Test(RailTypeFlag f) const { return (value & int(f)) != 0; } };
struct RailTypeInfo { Flags flags; };
RailTypeInfo kinds[4]{{{0}},{{1}},{{2}},{{3}}};
RailTypeInfo *GetRailTypeInfo(int id) { return kinds + id; }
struct { struct { bool forbid_90_deg = true; } pf; } _settings_game;
""" + header[start:end] + r"""
int main() {
    if (!Rail90DegTurnDisallowed(0, 0)) return 2;
    for (int flag = 0; flag < 2; ++flag)
        for (int a = -1; a < 4; ++a)
            for (int b = -1; b < 4; ++b)
                std::cout << Rail90DegTurnDisallowed(a,b,flag != 0) << "\n";
}
"""
lua_code = r"""
local M="mods/luanttd_core/openttd/"
local T=dofile(M.."rail_track.lua")
local F=dofile(M.."rail_follow.lua")(T)
local board={railtype=function(n)
  return {allow_90=n%2==1,disallow_90=n>=2}
end}
local function valid(n) if n>=0 then return n end end
for d=0,1 do for a=-1,3 do for b=-1,3 do
  print(F.disallow_90(board,valid(a),valid(b),d==1) and 1 or 0)
end end end
"""
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)
    cpp, exe, script = path / "turn.cpp", path / "turn", path / "turn.lua"
    cpp.write_text(shim)
    script.write_text(lua_code)
    subprocess.run(["c++", "-std=c++20", str(cpp), "-o", str(exe)], check=True)
    upstream = subprocess.check_output([str(exe)], text=True).split()
    ported = subprocess.check_output([lua, str(script)], text=True).split()
assert len(upstream) == 50 and upstream == ported
print("PASS literal RC1 Rail90DegTurnDisallowed: 50 matches, Expert default on, explicit flags preserved")
