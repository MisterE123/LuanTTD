#!/usr/bin/env python3
"""Differential-check stock RNG and packet truncation against OpenTTD 14.1."""
import argparse
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHIM = r"""
#include <algorithm>
#include <bit>
#include <cstdint>
#include <iostream>
#include <list>
#include <map>
struct Randomizer {
  uint32_t state[2];
  uint32_t Next();
  uint32_t Next(uint32_t limit);
  void SetSeed(uint32_t seed);
};
Randomizer rng;
uint32_t RandomRange(uint32_t n) { return rng.Next(n); }
struct CargoPacket {
  int first_station;
  uint count;
  void Reduce(uint n) { count -= n; }
};
using StationCargoAmountMap = std::map<int, uint>;
struct StationCargoList {
  using Iterator = std::list<CargoPacket *>::iterator;
  uint count=0;
  std::list<CargoPacket *> packets;
  void RemoveFromCache(CargoPacket *, uint amount) { count -= amount; }
  uint Truncate(uint max_move, StationCargoAmountMap *cargo_per_source);
};
"""
CPP = r"""
int main() {
  uint32_t seed, amount, n;
  while (std::cin >> seed >> amount >> n) {
    rng.SetSeed(seed);
    StationCargoList queue;
    for (uint i=0; i<n; i++) {
      auto p=new CargoPacket;
      std::cin >> p->first_station >> p->count;
      queue.count+=p->count;
      queue.packets.push_back(p);
    }
    StationCargoAmountMap count;
    queue.Truncate(amount,&count);
    for (auto p: queue.packets) {
      std::cout << p->first_station << ":" << p->count << ",";
      delete p;
    }
    std::cout << "|";
    for (auto [id,units]: count) if (id>=0) std::cout << id << ":" << units << ",";
    std::cout << "|" << rng.Next() << "|" << rng.Next(UINT32_MAX) << "\n";
  }
}
"""

LUA = """
local root="mods/luanttd_core/"
local R=dofile(root.."station_rating_runtime.lua")(nil,dofile(root.."openttd/station_rating.lua"))
for line in io.lines() do
  local words={}
  for n in line:gmatch("%S+") do words[#words+1]=tonumber(n) end
  local s={seed=words[1]}
  local function random() return R.random_u32(s) end
  local q,total={},0
  for i=4,#words,2 do
    q[#q+1]={origin_station=words[i]>=0 and words[i] or nil,units=words[i+1]}
    total=total+words[i+1]
  end
  local retained=R.truncate(q,total,words[2],random)
  local parts,ids,origins={},{},{}
  for _,p in ipairs(q) do table.insert(parts,(p.origin_station or -1)..":"..p.units..",") end
  for id in pairs(retained) do table.insert(ids,id) end
  table.sort(ids)
  for _,id in ipairs(ids) do table.insert(origins,id..":"..retained[id]..",") end
  local n=random()
  local range=R.random_range(random(),4294967295)
  print(table.concat(parts).."|"..table.concat(origins).."|"..n.."|"..range)
end
"""


def extract(source, name):
    start = source.index(name)
    return source[start:source.index("\n}", start) + 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="directory containing random_func.cpp and cargopacket.cpp")
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()
    random_cpp = (args.source / "random_func.cpp").read_text()
    cargo_cpp = (args.source / "cargopacket.cpp").read_text()
    port = "\n".join(extract(random_cpp, sig) for sig in (
        "uint32_t Randomizer::Next()",
        "uint32_t Randomizer::Next(uint32_t limit)",
        "void Randomizer::SetSeed(uint32_t seed)",
    ))
    port += "\n" + extract(cargo_cpp, "uint StationCargoList::Truncate(")

    rng = random.Random(11401)
    cases = []
    for i in range(2500):
        seed = rng.randrange(1 << 32)
        queue = [(rng.randrange(-1, 6), rng.randrange(1, (8 if i % 5 == 3 else 65536))) for _ in range(rng.randrange(1, 30))]
        waiting = sum(n for _, n in queue)
        cut = [0, waiting, waiting+100, 1, rng.randrange(waiting+1)][i % 5]
        cases.append(f"{seed} {cut} {len(queue)} " + " ".join(f"{o} {n}" for o, n in queue))
    data = ("\n".join(cases) + "\n").encode()

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "ref.cpp").write_text(SHIM + port + CPP)
        (tmp / "test.lua").write_text(LUA)
        subprocess.run(["c++", "-O2", "-std=c++20", "-Wall", "-Werror",
                        str(tmp / "ref.cpp"), "-o", str(tmp / "ref")], check=True)
        stock = subprocess.check_output([str(tmp / "ref")], input=data).splitlines()
        lua = subprocess.check_output([args.lua, str(tmp / "test.lua")], cwd=ROOT, input=data).splitlines()

    assert len(stock) == len(lua)
    for i, (a, b) in enumerate(zip(stock, lua)):
        if a != b:
            raise AssertionError(f"Case {i}: {cases[i]}\nOpenTTD: {a}\nLua: {b}")
    print(f"PASS: {len(cases)} OpenTTD-C++ matches for exact RNG state, cut packet sequence and remaining cargo by origin")


if __name__ == "__main__":
    main()
