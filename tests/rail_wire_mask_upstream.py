#!/usr/bin/env python3
"""Compare pinned RC1's actual MaskWireBits selection with the Lua port."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
src = pathlib.Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
assert subprocess.check_output(["git", "-C", src, "rev-parse", "HEAD"], text=True).strip() == "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
raw = (src/"src/elrail.cpp").read_text()
start = raw.index("\t/* If the tracks from either a diagonal crossing")
end = raw.index("\n}", start)
stock = raw[start:end]
shim = r"""
#include <bit>
#include <iostream>
enum class Track { X,Y };
enum class Trackdir { X_NE=0,Y_SE=1,X_SW=8,Y_NW=9 };
struct TrackBits {
  unsigned n;
  TrackBits(unsigned data=0): n(data&63) {}
  unsigned base() const {return n;}
  bool Any(TrackBits b) const {return (n & b.n)!=0;}
  TrackBits Flip(TrackBits b) { return {n^b.n}; }
  void Set(Track t) {n|=(1u<<static_cast<int>(t));}
  auto operator<=>(const TrackBits &) const = default;
  TrackBits operator&(TrackBits b) const {return {n&b.n};}
};
struct TrackdirBits {
  unsigned n;
  unsigned base() const {return n;}
  bool Test(Trackdir d) const {return (n & (1u<<static_cast<int>(d)))!=0;}
};
const TrackBits TRACK_BIT_ALL{63};
const TrackBits TRACK_BIT_CROSS{3};
TrackBits TrackdirBitsToTrackBits(TrackdirBits b) {return {b.n|(b.n>>8)};}
bool TracksOverlap(TrackBits b) {return std::popcount(b.n)>1 && b.n!=12 && b.n!=48;}
TrackBits extract(TrackBits tracks, TrackdirBits neighbour_tdb) {
  if (std::popcount(tracks.n)<=1) return tracks;
"""
cpp = shim+stock+r"""
}
int main() {
  unsigned b,td;
  while(std::cin >> b >> td) std::cout << extract(b,{td}).n << '\n';
}
"""
adapter = """
local t=dofile('mods/luanttd_core/openttd/rail_track.lua')
local a=dofile('mods/luanttd_core/openttd/rail_wire_mask.lua')(t)
for l in io.lines() do local b,d=l:match('(%d+) (%d+)');print(a.select(tonumber(b),tonumber(d),true)) end
"""
# Every possible directed-end combination, including unreachable
# combinations, checks deterministic fallback from the source function.
rows = "\n".join(f"{b} {d+(e<<8)}" for b in range(64) for d in range(64) for e in range(64))+"\n"
with tempfile.TemporaryDirectory() as td:
    p = pathlib.Path(td)
    (p/"check.cpp").write_text(cpp)
    (p/"check.lua").write_text(adapter)
    subprocess.run(["g++","-std=c++20","-O2",p/"check.cpp","-o",p/"check"],check=True)
    expected = subprocess.check_output([p/"check"],input=rows,text=True).splitlines()
    actual = subprocess.check_output([lua,p/"check.lua"],input=rows,text=True,cwd=root).splitlines()
assert len(expected)==len(actual)==262144
for i,(e,a) in enumerate(zip(expected,actual)):
    assert e==a,(i,e,a)
print("PASS 262,144 exact RC1 MaskWireBits decisions against original C++")
