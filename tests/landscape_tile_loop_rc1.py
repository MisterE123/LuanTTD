#!/usr/bin/env python3
"""Compare the Lua landscape cursor with the compiled 16.0-RC1 RunTileLoop."""
import argparse
import hashlib
from pathlib import Path
import random
import subprocess
import tempfile

from road_loading_upstream import extract

ROOT = Path(__file__).resolve().parents[1]
HASH = "c6166aa9c4ce20475d0f376d7b651dda40b5e6089f7382410da709f0d00ac2d6"
SHIM = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
using uint = unsigned;
struct TileIndex {
    uint32_t value;
    TileIndex(uint32_t value=0) : value(value) {}
    uint32_t base() const { return value; }
    operator uint32_t() const { return value; }
};
static uint32_t log_x, log_y;
struct Map {
    static uint32_t LogX() { return log_x; }
    static uint32_t LogY() { return log_y; }
};
constexpr int MIN_MAP_SIZE_BITS=6, MAX_MAP_SIZE_BITS=12;
constexpr int TILE_UPDATE_FREQUENCY_LOG=8, TILE_UPDATE_FREQUENCY=256;
template<class T, size_t N> constexpr size_t lengthof(const T(&)[N]) { return N; }
enum class PerformanceElement { GameLoopLandscape };
struct PerformanceAccumulator { PerformanceAccumulator(PerformanceElement) {} };
struct TimerGameTick { static inline uint64_t counter=0; };
TileIndex _cur_tileloop_tile;
void Write24(uint32_t x) {
    const char b[] = {char(x), char(x >> 8), char(x >> 16)};
    std::cout.write(b, sizeof(b));
}
void Visit(TileIndex tile) { Write24(tile.base()); }
uint GetTileType(TileIndex) { return 0; }
struct { void (*tile_loop_proc)(TileIndex); } procs{Visit};
auto _tile_type_procs=std::array{&procs};
"""
DRIVER = r"""
int main() {
    std::ios::sync_with_stdio(false);
    uint32_t head, ticks, initial;
    uint64_t epoch;
    while (std::cin >> log_x >> log_y >> head >> epoch >> ticks >> initial) {
        _cur_tileloop_tile=head;
        TimerGameTick::counter=epoch;
        for (uint i=0;i<ticks;i++) {
            if (!initial) ++TimerGameTick::counter;
            RunTileLoop();
            if (initial) ++TimerGameTick::counter;
        }
        Write24(_cur_tileloop_tile.base());
        Write24(TimerGameTick::counter);
    }
}
"""
LUA = r"""
local H=dofile("mods/luanttd_core/openttd/town_passengers.lua")
local floor=math.floor
local function write24(i) io.write(string.char(i%256,floor(i/256)%256,floor(i/65536))) end
for line in io.lines() do
  local a,b,head,counter,n,initial=line:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)$")
  local clock=H.new_clock(tonumber(a),tonumber(b),tonumber(head),tonumber(counter))
  local advance=initial=="1" and H.advance_initial or H.advance
  advance(clock,tonumber(n),write24)
  write24(clock.head)
  write24(clock.counter)
end
"""

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="OpenTTD 16.0-RC1 checkout or landscape.cpp")
    parser.add_argument("--lua", default="lua5.1")
    opts = parser.parse_args()
    source = opts.source / "src/landscape.cpp" if opts.source.is_dir() else opts.source
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != HASH:
        raise SystemExit("The landscape source is not pinned OpenTTD 16.0-RC1")
    seed = random.Random(1751)
    cases = [(6, 6, 1, 0, 512, 0), (6, 6, 1, 0, 256, 1)]
    for log_x in range(6, 13):
        for log_y in range(6, 13):
            limit = 1 << (log_x + log_y)
            cases.append((log_x, log_y, seed.randrange(1, limit), 254, 4, 0))
            cases.append((log_x, log_y, seed.randrange(1, limit), 510, 4, 1))
    stdin = "".join(" ".join(map(str, case)) + "\n" for case in cases)
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-tile-clock-") as tmp:
        cpp, lua, binary = (Path(tmp) / name for name in ("oracle.cpp", "fixture.lua", "oracle"))
        cpp.write_text(SHIM + extract(data.decode(), "void RunTileLoop()") + DRIVER)
        lua.write_text(LUA)
        subprocess.run(["c++", "-std=c++17", "-O2", str(cpp), "-o", str(binary)], check=True)
        cpp_output = subprocess.run([str(binary)], input=stdin.encode(), check=True, capture_output=True).stdout
        lua_output = subprocess.run([opts.lua, str(lua)], input=stdin.encode(), check=True,
                                    capture_output=True, cwd=ROOT).stdout
    start = 0
    for case in cases:
        x, y, _, _, ticks, _ = case
        stop = start + 3 * ((1 << (x+y-8)) * ticks + 2)
        assert cpp_output[start:stop] == lua_output[start:stop], f"Stock clock mismatch in dimensions/epoch/head {case}"
        start = stop
    assert start == len(cpp_output) == len(lua_output)
    tiles = sum((1 << (x+y-8)) * ticks for x,y,_,_,ticks,_ in cases)
    print(f"PASS compiled RC1 tile loop: {len(cases)} cases, {tiles:,} ordered visits, all supported axes and tile-zero boundaries")

if __name__ == "__main__":
    main()
