"""Run the pinned RC1 noise, capacity and council admission code against Lua."""
import itertools as it
import re
import subprocess as sp
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

source = Path(sys.argv[1])
assert sp.check_output(["git", "-C", source, "rev-parse", "HEAD"], text=True).strip() == (
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
)
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
station = (source / "src/station_cmd.cpp").read_text()
noise = re.search(r"uint8_t GetAirportNoiseLevelForDistance\(.*?\n}", station, re.S)[0]
limit = re.search(r"inline uint16_t MaxTownNoise\(\) const.*?\n\t}", (source / "src/town.h").read_text(), re.S)[0]
admit = re.search(r"if \(\(nearest->noise_reached \+ newnoise_level\) > nearest->MaxTownNoise\(\)\)", station)[0]
numbers = (source / "src/table/settings/economy_settings.ini").read_text()
divisors = [int(d) for d in re.findall(r"town_noise_population\[\d+]\n(?:[^\n]+\n)*?def\s*=\s*(\d+)", numbers)]
assert len(divisors) == 4
specs = (source / "src/table/airport_defaults.h").read_text().split("const AirportSpec _origin_airport_specs[]", 1)[1]
levels = {name: int(level) for name, level in re.findall(
    r"AS(?:_ND)?\((\w+),\s*\d+,\s*\d+,\s*\d+,\s*[^,]+,\s*\d+,\s*(\d+),", specs
)}
assert len(levels) == 9
cpp = """
#include <algorithm>
#include <cstdint>
#include <iostream>
#include <limits>
template<typename T, typename U> T ClampTo(U value) { return std::min<U>(std::numeric_limits<T>::max(), value); }
struct AirportSpec { unsigned noise_level; };
struct { struct { unsigned town_council_tolerance; } difficulty;
   struct { unsigned town_noise_population[4] = {DIVISORS}; } economy;
} _settings_game;
NOISE
struct Town {
  uint16_t noise_reached;
  struct { unsigned population; } cache;
  CAPACITY
};
int main() {
  unsigned level, dist, tol, pop, used;
  while(std::cin >> level >> dist >> tol >> pop >> used) {
    _settings_game.difficulty.town_council_tolerance=tol;
    AirportSpec as{level};
    Town town{static_cast<uint16_t>(used),{pop}};
    auto *nearest=&town;
    unsigned newnoise_level=GetAirportNoiseLevelForDistance(&as,dist);
    bool refusal=false;
    ADMIT refusal=true;
    std::cout << newnoise_level << ' ' << town.MaxTownNoise() << ' ' << refusal << '\\n';
  }
}
""".replace("DIVISORS", ",".join(map(str, divisors))).replace("NOISE", noise).replace("CAPACITY", limit).replace("ADMIT", admit)
runner = """
local A=dofile("mods/luanttd_core/openttd/airport_noise.lua")
for line in io.lines() do
  local l,d,t,p,u=line:match("^(%d+) (%d+) (%d+) (%d+) (%d+)$")
  l,d,t,p,u=tonumber(l),tonumber(d),tonumber(t),tonumber(p),tonumber(u)
  local n=A.for_distance(l,d,t)
  local cap=A.town_capacity(p,A.population_divisor[t])
  print(("%d %d %d"):format(n,cap,u+n>cap and 1 or 0))
end
"""
for field, level in levels.items():
    assert int(sp.check_output([lua, "-e", f'print(dofile("mods/luanttd_core/openttd/airport_noise.lua").level.{field})'], text=True)) == level
rows = list(it.product(
    (0, 1, 2, 3, 4, 5, 8, 17, 25), (0, 7, 8, 11, 12, 15, 16, 19, 20, 64, 255, 4096), range(4),
    (0, 1, 399, 400, 799, 800, 1999, 2000, 3999, 4000, 10000, 100000000), (0, 1, 2, 3, 5, 25, 65535),
))
data = "".join(" ".join(map(str, row)) + "\n" for row in rows)
with TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p / "oracle.cpp").write_text(cpp)
    (p / "check.lua").write_text(runner)
    sp.run(["c++", "-std=c++17", "-O2", p / "oracle.cpp", "-o", p / "oracle"], check=True)
    expected = sp.check_output([p / "oracle"], input=data, text=True).splitlines()
    got = sp.check_output([lua, p / "check.lua"], input=data, text=True).splitlines()
assert len(expected) == len(got) == len(rows)
for r, a, b in zip(rows, expected, got):
    assert a == b, (r, "RC1", a, "Lua", b)
print(f"PASS {len(rows):,} pinned RC1 airport noise, population limits and authority decisions")
