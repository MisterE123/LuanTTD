#!/usr/bin/env python3
"""Differential check for the six bridge middles and native pillar masks."""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

from openttd_content_timeline import PIN

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("--lua", default="lua5.1")
parser.add_argument("--cxx", default="c++")
args = parser.parse_args()
src = args.source.resolve() / "src"
assert subprocess.check_output(
    ["git", "-C", src, "rev-parse", "HEAD"], text=True).strip() == PIN
kernel = (src / "tunnelbridge_cmd.cpp").read_text().split(
    "static BridgePieces CalcBridgePiece(uint north, uint south)\n", 1)[1].split("\n}\n", 1)[0]
enums = (src / "bridge_type.h").read_text()
table = (src / "table" / "bridge_land.h").read_text().split(
    "static constexpr BridgePillarFlags BRIDGEPILLARFLAGS_ALL_CORNERS", 1)[1]
table, orig = table.split("const BridgeSpec _orig_bridge[]", 1)
rows = re.findall(r"(ALL_PILLARS|SUSPENSION_PILLARS|CANTILEVER_PILLARS)\s*\},",
                  orig.split("};", 1)[0])
assert len(rows) == 13
program = """#include <array>
#include <cstdint>
#include <iostream>
using uint = unsigned;
""" + re.search(r"enum BridgePieces : uint8_t \{.*?\};", enums, re.S)[0] + "\n" + re.search(
    r"enum class BridgePillarFlag : uint8_t \{.*?\};", enums, re.S)[0] + """
struct BridgePillarFlags {
    uint bits;
    template<typename... Args>
    constexpr BridgePillarFlags(Args... items) : bits((0u | ... | (1u << uint(items)))) {}
};
using BridgeMiddlePillarFlags = std::array<std::array<BridgePillarFlags, 2>, 6>;
static constexpr BridgePillarFlags BRIDGEPILLARFLAGS_ALL_CORNERS""" + table + """
static BridgePieces CalcBridgePiece(uint north, uint south)
""" + kernel + """
}
int main() {
    constexpr std::array<BridgeMiddlePillarFlags, 13> styles = { """ + ", ".join(rows) + """ };
    for (uint axis = 0; axis < 2; ++axis) {
        for (uint style = 0; style < styles.size(); ++style) {
            for (uint length = 1; length <= 64; ++length) {
                for (uint n = 1; n <= length; ++n) {
                    auto p = CalcBridgePiece(n, length + 1 - n);
                    std::cout << unsigned(p) << ' ' << styles[style][p][axis].bits << '\\n';
                }
            }
        }
    }
}
"""
lua = r'''
local open="mods/luanttd_core/openttd/"
local B=dofile(open.."road_bridge.lua")(dofile(open.."slope.lua"))
local stride=109
local function xy(id) return id%stride,math.floor(id/stride) end
for axis=0,1 do
  local d=axis==0 and 1 or stride
  for style=0,12 do
    for length=1,64 do
      local plan={start=3+7*stride,axis=axis,middle_length=length,bridge_type=style,
        middle_by_tile={}}
      plan["end"]=plan.start+(length+1)*d
      for n=1,length do
        local id=plan.start+n*d
        plan.middle_by_tile[id]=true
        local piece,mask=B.middle_layout(plan,id,xy)
        assert(piece~=nil and mask~=nil)
        print(piece.." "..mask)
      end
      assert(B.middle_layout(plan,plan.start,xy)==nil)
      assert(B.middle_layout(plan,plan["end"],xy)==nil)
      plan.transport="water"
      assert(B.middle_layout(plan,plan.start+d,xy)==nil)
    end
  end
end
'''
with tempfile.TemporaryDirectory(prefix="stock-bridge-pieces-") as tmp:
    target = Path(tmp) / "check"
    subprocess.run([args.cxx, "-std=c++17", "-x", "c++", "-", "-o", target],
                   text=True, input=program, check=True)
    expected = subprocess.check_output([target], text=True).splitlines()
actual = subprocess.check_output([args.lua, "-"], text=True, input=lua, cwd=ROOT).splitlines()
assert len(expected) == len(actual) == 54_080
for i, (want, got) in enumerate(zip(expected, actual)):
    assert want == got, (i, want, got)
print(f"PASS {len(actual):,} native middle-piece and pillar-mask combinations against pinned C++")
