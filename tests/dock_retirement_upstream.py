#!/usr/bin/env python3
"""Compare retired station selection and lifetime to the pinned RC1 source."""
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

source = Path(sys.argv[1])
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
root = Path(__file__).resolve().parents[1]
cmd = (source / "src/station_cmd.cpp").read_text()


def body_after(marker):
    start = cmd.index("{", cmd.index(marker))
    depth = 0
    for i in range(start, len(cmd)):
        depth += (cmd[i] == "{") - (cmd[i] == "}")
        if depth == 0:
            return cmd[start:i + 1]
    raise AssertionError(marker)


nearest = body_after("static Station *GetClosestDeletedStation(")
# The unused branch returns before cargo/rating logic. Compile its original
# branch verbatim without importing unrelated station/render dependencies.
inactive = body_after("if (!st->IsInUse()) {\n\t\tif (++st->delete_ctr")
ticks_header = (source / "src/timer/timer_game_tick.h").read_text()
period = int(re.search(r"STATION_ACCEPTANCE_TICKS\s*=\s*(\d+)", ticks_header)[1])
cpp = r'''
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>
using uint = unsigned;
using TileIndex = unsigned;
struct Station {
  int owner;
  unsigned index, delete_ctr = 0;
  TileIndex xy;
  bool IsInUse() const { return false; }
};
static std::vector<Station *> records;
static int _current_company = 1;
uint DistanceManhattan(TileIndex a, TileIndex b) {
  return std::abs(int(a % 64) - int(b % 64)) + std::abs(int(a / 64) - int(b / 64));
}
template<class F> void ForAllStationsRadius(TileIndex at, uint radius, F visit) {
  for (auto *st : records) {
    if (DistanceManhattan(at, st->xy) <= radius) visit(st);
  }
}
static Station *GetClosestDeletedStation(TileIndex tile)
''' + nearest + r'''
static bool unused_big_tick(Station *st)
''' + inactive + r'''
int main() {
  unsigned from, now, count;
  while (std::cin >> from >> now >> count) {
    records.clear();
    for (unsigned k = 0; k < count; ++k) {
      int owner; unsigned id, at, removed;
      std::cin >> owner >> id >> at >> removed;
      auto *st = new Station{owner, id, 0, at};
      bool alive = true;
      for (unsigned tick = removed + 1; tick <= now; ++tick) {
        if ((tick + id) % PERIOD == 0) {
          const unsigned previous = st->delete_ctr;
          unused_big_tick(st);
          // The original branch deletes on its eighth check. Test the
          // observable result via the same counter before dereferencing.
          if (previous == 7) { alive = false; break; }
        }
      }
      if (alive) records.push_back(st);
    }
    auto *found = GetClosestDeletedStation(from);
    std::cout << (found ? int(found->index) : -1) << '\n';
    for (auto *st : records) delete st;
  }
}
'''.replace("PERIOD", str(period))
adapter = r'''
local function distance(a,b)
  return math.abs(a%64-b%64)+math.abs(math.floor(a/64)-math.floor(b/64))
end
local R=dofile("mods/luanttd_core/openttd/road_station_retirement.lua")({distance=distance})
while true do
  local from,now,n=io.read("*n","*n","*n")
  if not from then break end
  local s={passenger_house_clock={counter=0}}
  for i=1,n do
    local owner,id,tile,removed=io.read("*n","*n","*n","*n")
    s.passenger_house_clock.counter=removed
    R.retire(s,"dock",{tile=tile,id=id,owner=owner})
  end
  s.passenger_house_clock.counter=now
  local row=R.closest(s,"dock",1,from)
  print(row and row.id or -1)
end
'''
rng = random.Random(0x16)
cases = []
for _ in range(4096):
    x, z = rng.randrange(12, 52), rng.randrange(12, 52)
    now = rng.randrange(2500, 50000)
    count = rng.randrange(1, 13)
    row = [x + 64 * z, now, count]
    for id in rng.sample(range(1, 1024), count):
        u, v = x + rng.randrange(-12, 12), z + rng.randrange(-12, 12)
        owner = rng.choice((1, 1, 2))
        removed = now - rng.randrange(2500)
        row.extend((owner, id, u + 64 * v, removed))
    cases.append(row)
# Sweep every station phase with observable cases at both sides of the
# eight-tick-check cutoff, both sides of the radius, and another owner.
for id in range(1, period + 1):
    removed = 4321
    cutoff = removed + (period - (removed + id) % period) + 7 * period
    for delta in (-1, 0, 1):
        for dist in (7, 8):
            for owner in (1, 2):
                cases.append([1024, cutoff + delta, 1, owner, id, 1024 + dist, removed])
data = "\n".join(" ".join(map(str, row)) for row in cases) + "\n"
with tempfile.TemporaryDirectory() as folder:
    p = Path(folder)
    (p / "station.cpp").write_text(cpp)
    (p / "station.lua").write_text(adapter)
    subprocess.run(["g++", "-O2", str(p / "station.cpp"), "-o", str(p / "station")], check=True)
    expected = subprocess.check_output([p / "station"], input=data, text=True).splitlines()
    observed = subprocess.check_output([lua, p / "station.lua"], input=data, text=True, cwd=root).splitlines()
assert len(expected) == len(observed) == len(cases)
for row, before, after in zip(cases, expected, observed):
    assert before == after, (row, before, after)
print(f"PASS {len(cases):,} compiled RC1 inactive-dock lifetime and nearest same-owner station decisions")
