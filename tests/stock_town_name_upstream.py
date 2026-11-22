#!/usr/bin/env python3
"""Compile pinned OpenTTD 14.1 Original English name + guard functions and compare Lua."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PIN = {
    "townname.cpp": "0992a66928cc29a3026fae62bcc2fed2ccf2dc8c4a84f3c4d14e28ba4ca243d9",
    "table/townname.h": "d9fed95ced264224b61caac17eeb1e5c01639abc59f772d6906067044bd4c18d",
    "town_type.h": "1ca5326ef6fcb344b6a52cf314e673008677b0a83bc9c21c047b522223e1ca2e",
    "core/bitmath_func.hpp": "6d330e7c20beb6033437a5e770b6be1cc8d98fd53fdd67cee9d112be6eb7b298",
}
SHIM = r"""
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <unordered_set>
#include <vector>
using uint = unsigned;
using byte = uint8_t;
template<typename T, size_t N> constexpr size_t lengthof(const T (&)[N]) { return N; }
struct StringBuilder {
  std::string &out;
  size_t CurrentIndex() const { return out.size(); }
  char &operator[](size_t i) { return out[i]; }
  void operator+=(const char *s) { out += s; }
};
struct TownNameParams { explicit TownNameParams(int type) { assert(type == 0); } };
using TownNames = std::unordered_set<std::string>;
struct Town {
  std::string name;
  uint32_t parts;
  static std::vector<const Town *> by_id;
  static auto &Iterate() { return by_id; }
};
std::vector<const Town *> Town::by_id;
struct Randomizer {
  std::vector<uint32_t> words;
  size_t offset = 0;
  uint32_t Next() { assert(offset < words.size()); return words[offset++]; }
};
struct Layouter {
  static void ReduceLineCache() {} // UI cache, unrelated to generated names or random stream
};
struct { struct { int town_name=0; } game_creation; } _settings_game;
size_t Utf8StringLength(const std::string &s) {
  for (unsigned char c : s) assert(c < 128);
  return s.size(); // the exact UTF-8 count for these ASCII stock name parts
}
"""
BRIDGE = r"""
std::string GetTownName(const TownNameParams *, uint32_t seed) {
  // Original English language dispatch (the first stock table entry).
  std::string name;
  StringBuilder builder{name};
  MakeEnglishOriginalTownName(builder,seed);
  return name;
}
std::string GetTownName(const Town *t) { return GetTownName(nullptr,t->parts); }
"""
DRIVER = r"""
int main() {
  TownNames used;
  std::vector<Town> actual;
  char mode;
  while (std::cin >> mode) {
    uint32_t n;
    std::cin >> n;
    if (mode == 'D') {
      std::cout << GetTownName(nullptr,n) << "\n";
      continue;
    }
    Randomizer rng;
    rng.words.resize(n);
    for (uint32_t &seed : rng.words) std::cin >> seed;
    if (mode == 'S' || mode == 'A') {
      used.clear();
      if (mode == 'A') { actual.clear(); Town::by_id.clear(); }
      for (auto seed : rng.words) {
        std::string name = GetTownName(nullptr,seed);
        used.insert(name);
        // Alternate generated and custom-named Town records with the same
        // displayed string. Custom records carry irrelevant saved parts.
        if (mode == 'A') {
          bool custom = (actual.size() & 1) != 0;
          actual.push_back({custom ? name : "", custom ? uint32_t(~seed) : seed});
        }
      }
      if (mode == 'A') for (const auto &t : actual) Town::by_id.push_back(&t);
      std::cout << "-" << "\n";
      continue;
    }
    assert(mode == 'R' || mode == 'F');
    uint32_t parts=0xDEADFACE;
    bool ok=GenerateTownName(rng,&parts,mode == 'F' ? nullptr : &used);
    std::cout << rng.offset << "|";
    if (ok) std::cout << parts << "|" << GetTownName(nullptr,parts);
    else { assert(parts == 0xDEADFACE); std::cout << "-"; }
    std::cout << "\n";
  }
}
"""
LUA = r"""
local N=dofile("mods/luanttd_core/openttd/stock_town_name.lua")
local used,actual={},{}
for line in io.lines() do
  local a={}
  for part in line:gmatch("%S+") do a[#a+1]=tonumber(part) or part end
  local mode,n=a[1],a[2]
  if mode=="D" then
    print(N.display(n))
  elseif mode=="S" or mode=="A" then
    used={}
    if mode=="A" then actual={} end
    for i=1,n do
      local name=N.display(a[2+i])
      used[name]=true
      if mode=="A" then actual[name]=true end
    end
    print("-")
  else
    local candidates=used
    if mode=="F" then
      candidates={}
      for name in pairs(actual) do candidates[name]=true end
    end
    local calls=0
    local parts,name=N.generate(candidates,function()
      calls=calls+1
      return assert(a[2+calls],"too many draws")
    end)
    if parts then print(calls.."|"..string.format("%.0f",parts).."|"..name)
    else assert(name==nil);print(calls.."|-") end
  end
end
"""


def extract(source, signature):
    start = source.index(signature)
    end = re.search(r"^}", source[start:], re.M).end()
    return source[start:start + end]


def cpp(src):
    files = {}
    for rel, expected in PIN.items():
        raw = (src / rel).read_bytes()
        assert sha256(raw).hexdigest() == expected, f"not pinned OpenTTD 14.1: {rel}"
        files[rel] = raw.decode()
    gen = files["townname.cpp"]
    bit = files["core/bitmath_func.hpp"]
    get_bits = extract(bit, "template <typename T>\ndebug_inline constexpr static uint GB(").replace(
        "debug_inline constexpr", "constexpr")
    tables = [re.search(rf"^static const char [^\n]* _name_original_english_{i}\[\] = \{{.*?^\}};",
                        files["table/townname.h"], re.M | re.S).group(0)
              for i in range(1, 7)]
    length = re.search(r"^static const uint MAX_LENGTH_TOWN_NAME_CHARS.*$", files["town_type.h"], re.M).group(0)
    return "\n".join([SHIM, get_bits, length, *tables, *[extract(gen, fn) for fn in (
        "static inline uint32_t SeedChance(", "static inline int32_t SeedChanceBias(",
        "static void ReplaceWords(", "static void ReplaceEnglishWords(",
        "static void MakeEnglishOriginalTownName(")], BRIDGE,
        extract(gen, "bool VerifyTownName("), extract(gen, "bool GenerateTownName("), DRIVER])


def vectors():
    rng = random.Random(141)
    inputs = [f"D {n}" for n in [0, 1, 0x80000000, 0x7fffffff, 0xffffffff]]
    # All low-16 prefix fractions and a co-prime progression in the higher bits.
    inputs += [f"D {((n * 53377) << 16 | n) & 0xffffffff}" for n in range(65536)]
    inputs += [f"D {rng.getrandbits(32)}" for _ in range(65536)]
    names = len(inputs)

    def seq(mode, words):
        inputs.append(f"{mode} {len(words)}" + "".join(f" {seed}" for seed in words))

    # 0 and 2^31 have different encoded parts but the same dressed name;
    # the attempts after the first accepted candidate must not be consumed.
    seq("A", [0, 0xffffffff])
    seq("R", [0x80000000, 0x7fffffff, 234220, 7792])
    seq("R", [234220, 7792, 299993])
    # Demonstrate exactly 1,000 rejected draws and success on draw 1,000.
    seq("R", [0] * 1000 + [0x19872834])
    seq("R", [0] * 999 + [0x19872834, 14875])
    # A failed town placement left the last accepted name reserved in the
    # temporary set. Only the stock all-zero fallback may reuse it.
    seq("F", [0x7fffffff, 0x19872834, 0])
    seq("R", [0x19872834, 0x443fce9a, 0x4bd34989])
    seq("F", [0, 0xffffffff, 0x19872834])
    # Compare long batches of shared-stream retries, with artificial collisions
    # among actual existing towns and previous accepted attempts.
    for _ in range(15):
        blocked = [rng.getrandbits(32) for _ in range(22)]
        seq("S", blocked)
        for _ in range(64):
            replace = [rng.choice(blocked) ^ rng.choice([0, 0x80000000]) for _ in range(20)]
            seq("R", replace + [rng.getrandbits(32) for _ in range(20)])
    return "\n".join(inputs) + "\n", names, len(inputs) - names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path, help="pristine openttd-14.1/src directory")
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()
    inputs, n_names, n_sequences = vectors()
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        (tmp / "oracle.cpp").write_text(cpp(args.src))
        (tmp / "game.lua").write_text(LUA)
        subprocess.run(["c++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        str(tmp / "oracle.cpp"), "-o", str(tmp / "oracle")], check=True)
        stock = subprocess.run([str(tmp / "oracle")], text=True, capture_output=True, input=inputs)
        assert stock.returncode == 0, stock.stderr
        host = subprocess.run([args.lua, str(tmp / "game.lua")], cwd=ROOT, check=True, text=True,
                              capture_output=True, input=inputs)
    expected, got = stock.stdout.splitlines(), host.stdout.splitlines()
    assert len(got) == len(expected)
    assert expected[n_names + 1].startswith("3|234220|")   # encoded alias + existing custom name
    assert expected[n_names + 3] == "1000|-"
    assert expected[n_names + 4].startswith("1000|428288052|")
    assert expected[n_names + 5].startswith("2|428288052|") # abandoned name reusable in fallback
    assert expected[n_names + 6].startswith("2|1145032346|")
    assert expected[n_names + 7].startswith("3|428288052|")
    for i, (a, b) in enumerate(zip(expected, got), 1):
        assert a == b, f"input {i}: OpenTTD={a!r}; Lua={b!r}"
    print(f"{n_names:,} stock spellings and {n_sequences:,} stateful name-set operations match C++")


if __name__ == "__main__":
    main()
