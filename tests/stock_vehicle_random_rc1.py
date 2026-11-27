#!/usr/bin/env python3
"""Compare vanilla vehicle trigger state and entropy against compiled 16.0-RC1."""
import argparse
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CPP = r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <type_traits>
__TRIGGERS__
struct TriggerBits {
    uint8_t value;
    void Set(VehicleRandomTrigger t) { value |= 1 << static_cast<unsigned>(t); }
    void Reset(TriggerBits other) { value &= ~other.value; }
};
struct Vehicle {
    enum { engine_type=0 };
    TriggerBits waiting_random_triggers{0};
    uint16_t random_bits=0;
    Vehicle *First() { return this; }
    Vehicle *Next() { return nullptr; }
};
int calls=0;
uint32_t Random() { return ++calls * 0x1234567u; }
constexpr int CBID_RANDOM_TRIGGER=0;
struct VehicleResolverObject {
    enum WagonOverride { Cached };
    VehicleResolverObject(int, Vehicle *, WagonOverride, bool, int) {}
    void SetWaitingRandomTriggers(TriggerBits) {}
    void ResolveRerandomisation() {}
    TriggerBits GetUsedRandomTriggers() { return {0}; }
    uint32_t GetReseedSum() { return 0; }
};
__ORIGINAL__
int main() {
    int bits, pending, ops, op;
    while (std::scanf("%d%d%d", &bits,&pending,&ops)==3) {
        Vehicle v{TriggerBits{static_cast<uint8_t>(pending)},static_cast<uint16_t>(bits)};
        calls=0;
        for(int i=0;i<ops;i++) {
            assert(std::scanf("%d",&op)==1);
            if(op<0) v.random_bits=Random();
            else DoTriggerVehicleRandomisation(&v, static_cast<VehicleRandomTrigger>(op),0,true);
        }
        std::printf("%u,%u,%u\n",v.random_bits,v.waiting_random_triggers.value,calls);
    }
}
'''
LUA = r'''
local v=dofile("mods/luanttd_core/openttd/vehicle_random_trigger.lua")
local kinds={[0]="new_cargo","depot","empty",[4]="callback32"}
for line in io.lines() do
    local a={}
    for word in line:gmatch("-?%d+") do a[#a+1]=tonumber(word) end
    local part={stock_vehicle_random_bits=a[1],stock_waiting_random_triggers=a[2]}
    local calls=0
    local function rand() calls=calls+1;return (calls*0x1234567)%2^32 end
    for i=4,#a do
      if a[i]<0 then v.built(part,rand)
      else v.single(part,kinds[a[i]],rand) end
    end
    print(table.concat({part.stock_vehicle_random_bits,part.stock_waiting_random_triggers,calls},","))
end
'''

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    src=(a.source/"newgrf_engine.cpp").read_text()
    start=src.index("static void DoTriggerVehicleRandomisation(")
    finish=src.index("\n}",start)+2
    vehicle=(a.source/"vehicle_type.h").read_text()
    first=vehicle.index("enum class VehicleRandomTrigger : uint8_t")
    last=vehicle.index("\n};",first)+3
    original=CPP.replace("__TRIGGERS__",vehicle[first:last]).replace("__ORIGINAL__",src[start:finish])
    rng=random.Random(116)
    rows=[]
    for i in range(4200):
        ops=([rng.choice((0,0,1,2,4)) for _ in range(i%32)])
        rows.append([rng.randrange(65536),rng.randrange(256),len(ops)+1,-1,*ops])
    text="".join(" ".join(map(str,r))+"\n" for r in rows).encode()
    with tempfile.TemporaryDirectory() as d:
        work=Path(d)
        (work/"ref.cpp").write_text(original)
        (work/"port.lua").write_text(LUA)
        subprocess.run(["c++","-O2","-std=c++17",work/"ref.cpp","-o",work/"ref"],check=True)
        expected=subprocess.check_output([work/"ref"],input=text)
        actual=subprocess.check_output([a.lua,work/"port.lua"],input=text,cwd=ROOT)
    assert expected==actual
    print(f"PASS {len(rows):,} compiled stock vanilla vehicle trigger runs.")

if __name__=="__main__":
    main()
