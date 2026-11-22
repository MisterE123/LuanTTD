#!/usr/bin/env python3
"""Pin the #29 coal wagon and compile the original rail loading wait from 14.1."""
import argparse
import hashlib
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHA = {
    "economy.cpp": "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "engines.h": "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "cargo_const.h": "3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "station.cpp": "0c4d82f845fcf2ddb246668415e78dfbaa17ab5d939f702c6c0209bf5feaab42",
    "station_cmd.cpp": "7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5",
    "cargopacket.h": "2dbab6aecb20006c54c2ba43affe707f712bda135b9b881bf5951a19bd235b4e",
    "cargoaction.cpp": "bac5313df38eda0502df1b88ad2d269ee93350193abbf9b231982954bdb9642b",
    "timer_game_tick.h": "be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
}


def find(root, name):
    for folder in (".", "src", "src/table", "src/timer"):
        path = root / folder / name
        if path.exists():
            data = path.read_bytes()
            assert hashlib.sha256(data).hexdigest() == SHA[name], f"Wrong 14.1 digest: {name}"
            return data.decode()
    raise FileNotFoundError(name)


def fields(source, pattern):
    return [s.strip() for s in re.search(pattern, source)[1].split(",")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    parser.add_argument("--compiler", default=os.getenv("CXX", "g++"))
    args = parser.parse_args()
    eco, eng, commodities, status, cmd, packet, action, timer = (find(args.source, p) for p in SHA)
    rvi = fields(eng, r"RVI\((.*)\), //\s*29 Coal Truck")
    mw = fields(eng, r"MW\((.*)\), //\s*29 Coal Truck")
    mw_macro = fields(eng, r"#define MW\(.*\) \{(.*)\}")
    waits = fields(eco, r"gradual_loading_wait_time\[\] = \{(.*)\};")
    cargo = fields(commodities, r"MK\((.*CT_COAL.*)\),")
    assert mw[4] == "CT_COAL" and rvi[1] == "W"
    assert "Ticks::CARGO_AGING_TICKS" in mw_macro
    aging, rating, acceptance = (
        re.search(rf"{name}\s*=\s*(\d+)", timer)[1]
        for name in ("CARGO_AGING_TICKS", "STATION_RATING_TICKS", "STATION_ACCEPTANCE_TICKS")
    )
    assert "case STATION_RAIL:    return CA_TRAIN;" in status
    assert "case STATION_TRUCK:   return CA_TRUCK;" in status
    assert "amount += ge.amount_fract;" in cmd and "GB(amount, 0, 8)" in cmd
    assert "new CargoPacket(st->index, amount, source_type, source_id)" in cmd
    assert "UpdateLoadingTile" in packet and "UpdateUnloadingTile" in packet
    assert "PayFinalDelivery(cp, remove, this->current_tile)" in action
    assert "GetPlatformLength(front->tile)" in eco and "payment, v->GetCargoTile()" in eco

    f = re.search(r"static void UpdateLoadUnloadTicks\(Vehicle \*front, const Station \*st, int ticks\)\n\{.*?\n\}", eco, re.S)[0]
    prefix = """
#include <algorithm>
#include <iostream>
constexpr int VEH_TRAIN = 0, TILE_SIZE = 16;
struct { struct { bool station_length_loading_penalty{true}; } order; } _settings_game;
struct Vehicle {
  int type{VEH_TRAIN}, tile{5}, load_unload_ticks{};
  struct { int cached_total_length{}; } cache;
  const decltype(cache)* GetGroundVehicleCache() const { return &cache; }
};
struct Station { int length; int GetPlatformLength(int actual) const { return actual == 5 ? length : 0; } };
"""
    suffix = f"""
int main() {{
  int length, tiles, loaded, unloaded, gradual, retry, penalty;
  while(std::cin >> length >> tiles >> loaded >> unloaded >> gradual >> retry >> penalty) {{
    Vehicle v; v.cache.cached_total_length = length;
    Station s{{tiles}};
    _settings_game.order.station_length_loading_penalty=penalty;
    int wait = loaded + unloaded;
    if (wait || retry) {{
      if (gradual) wait = {waits[0]};
    }} else wait = 20;
    UpdateLoadUnloadTicks(&v, &s, wait);
    std::cout << v.load_unload_ticks << '\\n';
  }}
}}
"""
    lua = """
local root="mods/luanttd_core/"
local function m(name) return dofile(root..name..".lua") end
local Roster,Timing=m("openttd/rail_roster"),m("openttd/loading_timing")
local Coal=m("openttd/coal_industry")()
local Rail=m("rail_coal_service")(nil,Coal,nil,Roster,nil,nil,nil,nil,nil,Timing)
local w=Rail.wagon
local cargo=Rail.cargo
local C=m("openttd/station_catchment")()
local Rating=m("openttd/station_rating")
print(table.concat({w.stock_id,w.capacity,w.tare,w.load_amount,w.cargo_age_ticks,Roster.GRADUAL_WAIT,
  cargo.id,cargo.payment,cargo.days1,cargo.days2,Rating.rating_ticks},","))
assert(C.radius("rail")==4 and C.radius("truck")==3)
for row in io.lines() do
  local v={}
  for n in row:gmatch("%d+") do v[#v+1]=tonumber(n) end
  local delay=Rail.loading_pulse({
    loaded=v[3],unloaded=v[4],gradual=v[5]==1,retry_unload=v[6]==1,reservations=0,
    full=false,cargo_not_full=true,elapsed=1,wait=0,lateness=0
  },v[1],v[2],v[7]==1)
  print(delay)
end
"""
    rng = random.Random(29)
    cases = []
    for i in range(4000):
        length, tiles = rng.randint(1, 112), rng.randint(1, 12)
        mode = rng.randrange(4)
        loaded = rng.randint(1, 30) if mode == 0 else 0
        unloaded = rng.randint(1, 30) if mode == 1 else 0
        retry = int(mode == 2)
        cases.append((length, tiles, loaded, unloaded, rng.randrange(2), retry, rng.randrange(2)))
    rows = "".join(" ".join(map(str, x)) + "\n" for x in cases)
    with tempfile.TemporaryDirectory(prefix="rail-coal-diff-") as tmp:
        tmp = Path(tmp)
        cpp = tmp / "wait.cpp"
        out = tmp / "wait"
        luafile = tmp / "wait.lua"
        cpp.write_text(prefix + f + suffix)
        luafile.write_text(lua)
        subprocess.run([args.compiler, "-std=c++17", "-O2", str(cpp), "-o", str(out)], check=True)
        expected = subprocess.check_output([str(out)], input=rows, text=True).splitlines()
        actual = subprocess.check_output([args.lua, str(luafile)], cwd=ROOT, input=rows, text=True).splitlines()
    stat = ",".join(("29", rvi[8], rvi[5], mw_macro[4], aging, waits[0],
                     cargo[0], cargo[5], cargo[6], cargo[7], rating))
    assert acceptance == "250" and actual[0] == stat, (actual[0], stat)
    assert len(actual[1:]) == len(expected)
    for idx, (got, want) in enumerate(zip(actual[1:], expected)):
        assert got == want, (cases[idx], got, want)
    print("PASS: pinned #29 wagon/cargo/actual cargo tile and 4,000 compiled stock train loading delays")


if __name__ == "__main__":
    main()
