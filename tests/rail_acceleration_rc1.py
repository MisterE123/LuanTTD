#!/usr/bin/env python3
"""Compare train force against the pinned RC1 GroundVehicle::GetAcceleration."""
import argparse
from pathlib import Path
import random
import subprocess
import tempfile

from road_acceleration_rc1 import ROOT, function

SHIM = r"""
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <limits>

enum class VehicleAccelerationModel { Normal, Maglev };
enum AccelStatus { AS_ACCEL, AS_BRAKE };
template<typename T> T ClampTo(int64_t n)
{
    return std::clamp<int64_t>(n, std::numeric_limits<T>::min(), std::numeric_limits<T>::max());
}

template<class T, int Type>
struct GroundVehicle {
    struct Cache {
        uint32_t cached_weight, cached_power, cached_max_te, cached_air_drag, cached_axle_resistance;
    } gcache{};
    int GetAcceleration() const;
    int64_t GetSlopeResistance() const { return static_cast<const T *>(this)->slope; }
};
struct Train : GroundVehicle<Train, 0> {
    int speed, brake, maglev, tunnel;
    int64_t slope;
    static const Train *From(const GroundVehicle *v) { return static_cast<const Train *>(v); }
    int GetCurrentSpeed() const { return speed; }
    int GetAirDragArea() const { return tunnel ? 28 : 14; }
    uint32_t GetRollingFriction() const { return 15 * (512 + speed) / 512; }
    AccelStatus GetAccelerationStatus() const { return brake ? AS_BRAKE : AS_ACCEL; }
    VehicleAccelerationModel GetAccelerationType() const
    {
        return maglev ? VehicleAccelerationModel::Maglev : VehicleAccelerationModel::Normal;
    }
};

__ORIGINAL__

int main()
{
    Train v;
    long long slope;
    while (std::scanf("%u%u%u%u%u%d%d%d%d%lld", &v.gcache.cached_weight, &v.gcache.cached_power,
           &v.gcache.cached_max_te, &v.gcache.cached_air_drag, &v.gcache.cached_axle_resistance,
           &v.speed, &v.brake, &v.maglev, &v.tunnel, &slope) == 10) {
        v.slope = slope;
        std::printf("%d\n", v.GetAcceleration());
    }
}
"""
LUA = r"""
local K=dofile("mods/luanttd_core/openttd/rail_acceleration_rc1.lua")
for line in io.lines() do
  local t={}
  for x in line:gmatch("-?%d+") do t[#t+1]=tonumber(x) end
  print(K.force({weight=t[1],power=t[2],tractive_effort=t[3],air_drag=t[4],axle_resistance=t[5]},
    t[6],t[7]~=0,t[8]~=0,t[9]~=0,t[10]))
end
"""

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()
    src = (args.source / "ground_vehicle.cpp").read_text()
    rng = random.Random(1601)
    cases = [(rng.randrange(1, 2500), rng.randrange(0, 80000),
              rng.randrange(0, 30000000), rng.randrange(0, 6000),
              rng.randrange(0, 250000), rng.choice((0, 1, 65535, rng.randrange(0, 1100))),
              i & 1, (i >> 1) & 1, (i >> 2) & 1, rng.randrange(-2500000, 2500000))
             for i in range(12000)]
    cases += [(weight, 300, 64000, 100, 1000, speed, brake, 0, tunnel, grade * weight * 100)
              for weight in (72, 73, 75, 81) for speed in range(65) for brake in range(2)
              for tunnel in range(2) for grade in (-3, 0, 3)]
    inp = "".join(" ".join(map(str, c)) + "\n" for c in cases).encode()
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        (tmp / "ref.cpp").write_text(SHIM.replace("__ORIGINAL__", function(src, "GetAcceleration")))
        (tmp / "port.lua").write_text(LUA)
        subprocess.run(["c++", "-std=c++17", "-O2", str(tmp / "ref.cpp"), "-o", str(tmp / "ref")], check=True)
        expected = subprocess.check_output([str(tmp / "ref")], input=inp).splitlines()
        actual = subprocess.check_output([args.lua, str(tmp / "port.lua")], cwd=ROOT, input=inp).splitlines()
    assert len(expected) == len(actual) == len(cases)
    for case, a, b in zip(cases, expected, actual):
        assert int(a) == int(b), (case, a, b)
    print(f"PASS {len(cases):,} compiled RC1 train force cases (physical mass, grades, tunnel drag, magnetic rails, braking).")

if __name__ == "__main__":
    main()
