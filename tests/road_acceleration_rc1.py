#!/usr/bin/env python3
"""Compare the port against RC1's unmodified one-body ground-vehicle force methods."""
import argparse
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CPP = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <limits>

constexpr int GROUND_ACCELERATION = 9800;
enum class VehicleAccelerationModel { Normal, Maglev };
enum AccelStatus { AS_ACCEL, AS_BRAKE };
enum class VehState { Stopped };
enum class WindowClass { VehicleDetails, VehicleView };
const int WID_VV_START_STOP = 0;
void SetWindowDirty(WindowClass, int) {}
void SetWindowWidgetDirty(WindowClass, int, int) {}
template<typename T> T ClampTo(int64_t n) {
    return std::clamp<int64_t>(n, std::numeric_limits<T>::min(), std::numeric_limits<T>::max());
}

template<class T, int Type>
struct GroundVehicle {
    struct Cache { uint32_t cached_power, cached_max_te, cached_air_drag,
        cached_max_track_speed, cached_weight, cached_axle_resistance, cached_slope_resistance; } gcache{};
    struct ViewCache { uint16_t cached_max_speed; } vcache{};
    struct Flags { void Set(VehState) {} } vehstatus;
    int index = 0;
    GroundVehicle *First() { return this; }
    void PowerChanged();
    void CargoChanged();
    int GetAcceleration() const;
    int64_t GetSlopeResistance() const {
       return static_cast<int64_t>(gcache.cached_slope_resistance) *
           static_cast<const T *>(this)->slope;
    }
};

struct Bus : GroundVehicle<Bus,0> {
   int weight, hp, drag, effort, slope, steepness, speed, braking, freight_weight, units;
   static Bus *From(GroundVehicle *v) { return static_cast<Bus *>(v); }
   static const Bus *From(const GroundVehicle *v) { return static_cast<const Bus *>(v); }
   Bus *Next() { return nullptr; }
   const Bus *Next() const { return nullptr; }
   uint16_t GetWeight() const { return weight / 4 + freight_weight * units / 16; }
   uint16_t GetPower() const { return hp * 10; }
   uint16_t GetPoweredPartPower() const { return 0; }
   uint16_t GetMaxTrackSpeed() const { return 0; }
   uint16_t GetDisplayMaxSpeed() const { return vcache.cached_max_speed / 2; }
   uint8_t GetAirDrag() const { return drag; }
   uint8_t GetTractiveEffort() const { return effort; }
   uint32_t GetSlopeSteepness() const { return steepness; }
   int GetAirDragArea() const { return 6; }
   uint32_t GetRollingFriction() const { return 75 * (128 + GetCurrentSpeed()) / 128; }
   int GetCurrentSpeed() const { return speed / 2; }
   AccelStatus GetAccelerationStatus() const { return braking ? AS_BRAKE : AS_ACCEL; }
   VehicleAccelerationModel GetAccelerationType() const { return VehicleAccelerationModel::Normal; }
};

__ORIGINAL__

int main() {
   Bus v;
   int top, cargo;
   const int masses[] = {1,16,4,16,3,8,16,16,16,16,2};
   while (std::scanf("%d%d%d%d%d%d%d%d%d%d%d",&v.weight,&v.hp,&v.effort,&v.drag,&top,
          &v.speed,&cargo,&v.units,&v.slope,&v.steepness,&v.braking)==11) {
      v.vcache.cached_max_speed = top;
      v.freight_weight = masses[cargo];
      v.CargoChanged();
      std::printf("%d\n",v.GetAcceleration());
   }
}
"""
LUA = """local a=dofile("mods/luanttd_core/openttd/road_acceleration.lua")
local goods={[0]="passenger","coal","mail","oil","livestock","goods","grain","wood","iron_ore","steel","valuables"}
for line in io.lines() do
  local t={}
  for x in line:gmatch("-?%d+") do t[#t+1]=tonumber(x) end
  local v=a.vehicle({weight_quarters=t[1],power_tens_hp=t[2],tractive_effort=t[3],air_drag=t[4],source_speed=t[5]})
  print(a.force(v,t[6],goods[t[7]],t[8],t[9],t[10],t[11]~=0))
end
assert(a.limit(112,7,9)==112 and a.limit(112,6,9)==84)
assert(a.limit(112,7,14,90,70)==56)
assert(a.limit(112,6,9,62,70)==62 and a.limit(112,7,9,62,48)==48)
assert(a.inclination(8,12)==1 and a.inclination(13,12)==-1 and a.inclination(12,12)==0)
"""

def function(text, name):
    pos = text.index(f"GroundVehicle<T, Type>::{name}(")
    start = text.rindex("template <", 0, pos)
    end = text.index("\n}", pos)+2
    return text[start:end].replace("template <class T, VehicleType Type>", "template <class T, int Type>")

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--lua", default="lua5.1")
    opts = p.parse_args()
    assert (opts.source.parent/"version.cmake").exists() or (opts.source/"roadveh.h").exists()
    ref = (opts.source/"ground_vehicle.cpp").read_text()
    parts = "\n".join(function(ref,n) for n in ("PowerChanged","CargoChanged","GetAcceleration"))
    rng = random.Random(160)
    cases = []
    for i in range(12000):
        cases.append((rng.randrange(24,140),rng.randrange(5,45),rng.randrange(40,101),
                      rng.choice((0,0,1,2,15,28)),rng.randrange(30,256),rng.randrange(0,290),
                      i%11,rng.randrange(0,53),rng.randrange(-1,2),rng.randrange(0,11),int(i%10==0)))
    cases.extend((42,9,76,0,112,speed,0,load,slope,7,0)
                 for speed in range(113) for load in (0,15,16,31) for slope in (-1,0,1))
    inp = "".join(" ".join(map(str,t))+"\n" for t in cases).encode()
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        (tmp/"ref.cpp").write_text(CPP.replace("__ORIGINAL__", parts))
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",str(tmp/"ref.cpp"),"-o",str(tmp/"ref")],check=True)
        expected = subprocess.check_output([str(tmp/"ref")],input=inp).splitlines()
        actual = subprocess.check_output([opts.lua,str(tmp/"port.lua")],cwd=ROOT,input=inp).splitlines()
    assert len(expected)==len(actual)==len(cases)
    for case,a,b in zip(cases,expected,actual):
        assert int(a)==int(b), (case,a,b)
    print(f"PASS {len(cases):,} compiled RC1 realistic road force cases (load, incline, drag, braking).")

if __name__ == "__main__":
    main()
