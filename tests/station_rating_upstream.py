#!/usr/bin/env python3
"""Check the Lua rating kernel against pinned, unmodified OpenTTD 14.1 UpdateStationRating.

Run: python3 tests/station_rating_upstream.py /path/to/OpenTTD [lua5.1]
A directory containing the pinned files works in place of a checkout. The
reference compiles original functions with minimal station/queue/UI shims.
No cross-station packet feedback is applied by the pure kernel or C++ shim.
"""
from hashlib import sha256
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
upstream_root = Path(sys.argv[1])
def read_source(file, digest):
    candidates = [upstream_root / "src" / file, upstream_root / file, upstream_root / Path(file).name]
    path = next((candidate for candidate in candidates if candidate.is_file()), candidates[0])
    data = path.read_bytes()
    assert sha256(data).hexdigest() == digest, f"{path}: not pinned OpenTTD 14.1 content"
    return data.decode()

station = read_source("station_cmd.cpp", "7f8ab7f9eba82461749c7356b722917a58fe8e202acc8fc453cb68e5652adbc5")
base_header = read_source("station_base.h", "397bf6bfd7fe7194f265eb674b47899aaa156af0927800228eea30f938ed8c3b")
timer = read_source("timer/timer_game_tick.h", "be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1")

def block(pattern):
    start = re.search(pattern, station, re.MULTILINE).start()
    cursor = station.index("{", start)
    depth = 1
    while depth:
        cursor += 1
        depth += (station[cursor] == "{") - (station[cursor] == "}")
    return station[start:cursor + 1]

cpp = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>
using uint = unsigned int;
using byte = uint8_t;
using StationID = uint16_t;
constexpr int VEH_INVALID=-1, VEH_ROAD=1, VEH_SHIP=2;
constexpr int CBM_CARGO_STATION_RATING_CALC=0, CBID_CARGO_STATION_RATING_CALC=0;
constexpr int CALLBACK_FAILED=65535, WC_STATION_VIEW=0, WID_SV_ACCEPT_RATING_LIST=0;
template<typename T,typename U> T ClampTo(U u) {
    return std::clamp((int)u,(int)std::numeric_limits<T>::min(), (int)std::numeric_limits<T>::max());
}
int Clamp(int value,int lo,int hi) {return std::clamp(value,lo,hi);}
template <class T> bool HasBit(T x,int off) {return (x & (1u<<off))!=0;}
void ClrBit(byte &bits,int bit) {bits &= ~(1u<<bit);}
uint GB(uint a,uint off,uint n) {return (a>>off) & ((1u<<n)-1);}
struct Company {static bool IsValidID(int id) {return id>=0 && id<15;}};
struct Town {uint statues=0;};
struct Cargo {uint units=0, destinations=0;
    uint AvailableCount() const {return units;}
    const Cargo *Packets() const {return this;}
    uint MapSize() const {return destinations;}
};
struct GoodsEntry {
    enum {GES_RATING=0};
    Cargo cargo;
    byte status=0,rating=175,time_since_pickup=255,last_speed=0,last_age=255;
    uint max_waiting_cargo=0;
    bool HasRating() const {return HasBit(status,GES_RATING);}
    bool HasVehicleEverTriedLoading() const {return last_speed!=0;}
};
struct Station {int last_vehicle_type=VEH_ROAD, owner=0; Town *town;
    byte time_since_load=0,time_since_unload=0;
    GoodsEntry goods[1]; StationID index=0;
};
struct CargoSpec {
    uint callback_mask=0;
    uint Index() const {return 0;}
    static CargoSpec cargo;
    static std::vector<const CargoSpec *> Iterate() {return {&cargo};}
};
CargoSpec CargoSpec::cargo;
uint16_t callback=CALLBACK_FAILED;
uint16_t GetCargoCallback(int id,uint a,uint b,const CargoSpec *cs) {return callback;}
uint randoms[2];int rng_i=0;
uint Random(){assert(rng_i<2);return randoms[rng_i++];}
struct {struct {bool value;} station_rating;} _cheats;
struct {struct {bool selectgoods;} order;} _settings_game;
bool dirty=false;
void SetWindowDirty(int wc,StationID id){dirty=true;}
void SetWindowWidgetDirty(int wc,StationID id,int widget) {}
void TruncateCargo(const CargoSpec *cs,GoodsEntry *ge,uint amount=UINT32_MAX) {
    ge->cargo.units -= std::min(amount,ge->cargo.units);
}
"""
cpp += "\n".join(re.findall(r"^static const uint8_t (?:INITIAL|MAX)_STATION_RATING.*$", base_header, re.MULTILINE))
cpp += "\n" + block(r"^static inline void byte_inc_sat") + "\n" + block(r"^static void UpdateStationRating")
cpp += r"""
int main(){
    int rating,has,time,speed,age,maxwaiting,waiting,dest,select,ship,statue,cheat,cb,vehicle,tl,tu;
    uint one,two;
    std::cout<<"175 255\n";
    while (std::cin>>rating>>has>>time>>speed>>age>>maxwaiting>>waiting>>dest>>select>>ship>>statue>>cheat>>cb>>vehicle>>tl>>tu>>one>>two) {
        Town town; town.statues=statue?1u:0u;
        Station st; st.town=&town; st.owner=statue==2 ? -1 : 0;
        st.last_vehicle_type=ship?VEH_SHIP:vehicle?VEH_ROAD:VEH_INVALID;
        st.time_since_load=tl; st.time_since_unload=tu;
        auto &g=st.goods[0];
        g.rating=rating; g.status=has; g.time_since_pickup=time;g.last_speed=speed;g.last_age=age;
        g.max_waiting_cargo=maxwaiting;g.cargo.units=waiting;g.cargo.destinations=dest;
        _settings_game.order.selectgoods=select;_cheats.station_rating.value=cheat;
        CargoSpec::cargo.callback_mask=cb>=0;callback=cb>=0?cb:CALLBACK_FAILED;
        randoms[0]=one;randoms[1]=two;rng_i=0;dirty=false;
        UpdateStationRating(&st);
        std::cout<<(int)g.rating<<" "<<(int)g.status<<" "<<(int)g.time_since_pickup<<" "<<(int)g.last_speed<<" "
          <<(int)g.last_age<<" "<<g.max_waiting_cargo<<" "<<g.cargo.units<<" "<<(waiting-g.cargo.units)<<" "
          <<(has&&!g.status)<<" "<<dirty<<" "<<rng_i<<" "<<(int)st.time_since_load<<" "<<(int)st.time_since_unload<<"\n";
    }
}
"""
cpp=cpp.replace('std::cout<<"175 255\\n";', 'std::cout<<(int)INITIAL_STATION_RATING<<" "<<(int)MAX_STATION_RATING'
    '<<" "<<' + re.search(r"DAY_TICKS\s*=\s*(\d+)",timer)[1]
    + '<<" "<<' + re.search(r"STATION_RATING_TICKS\s*=\s*(\d+)",timer)[1] + '<<"\\n";')

lua = r"""
local R=dofile('mods/bayline/openttd/station_rating.lua')
local function bit(b) return b and 1 or 0 end
print(table.concat({R.initial,R.maximum,R.day_ticks,R.rating_ticks},' '))
for line in io.lines() do
  local n={}
  for a in line:gmatch('-?%d+') do n[#n+1]=tonumber(a) end
  local g={rating=n[1],has_rating=n[2]==1,time_since_pickup=n[3],last_speed=n[4],last_age=n[5],max_waiting_cargo=n[6]}
  local opts={waiting=n[7],destinations=n[8],select_goods=n[9]==1,ship=n[10]==1,statue=n[11]==1,cheat=n[12]==1}
  opts.callback_rating=n[13]>=0 and n[13] or nil
  local st={time_since_load=n[15],time_since_unload=n[16]}
  R.increment_station_timers(st)
  local i=16
  opts.random_u32=function() i=i+1;assert(n[i]);return n[i] end
  local r=R.step(g,opts)
  print(table.concat({r.rating,bit(r.has_rating),r.time_since_pickup,r.last_speed,r.last_age,r.max_waiting_cargo,
    r.waiting,r.drop,bit(r.expire),bit(r.waiting_changed),r.rng_calls,st.time_since_load,st.time_since_unload},' '))
end
"""

rng = random.Random(141192)
samples = []
for _ in range(28000):
    waiting = rng.choice([0,1,99,100,199,200,399,400,4095,4096,4097,4160,32768,1<<24,rng.randrange(66000)])
    dest = rng.randrange(1, 9) if waiting else 0
    items = [rng.choice([0,1,62,63,64,65,125,126,127,128,129,174,175,176,253,254,255,rng.randrange(256)]),
             rng.randrange(2),rng.choice([0,1,2,3,5,6,11,12,20,21,254,255,rng.randrange(256)]),
             rng.choice([0,84,85,86,87,88,255,rng.randrange(256)]),rng.choice([0,1,2,3,254,255,rng.randrange(256)]),
             rng.choice([0,100,101,300,301,600,601,1000,1001,1500,1501,rng.randrange(2000)]),
             waiting,dest,rng.randrange(2),rng.randrange(2),rng.randrange(3),rng.randrange(9)==0,
             rng.choice([-1,-1,-1,-1,-1,0,1,0x3fff,0x4000,0x7fff,0xffff,rng.randrange(65536)]),
             rng.randrange(2),rng.choice([0,254,255,rng.randrange(256)]),rng.choice([0,254,255,rng.randrange(256)]),
             rng.getrandbits(32),rng.getrandbits(32)]
    samples.append(" ".join(str(int(n)) for n in items))
data = ("\n".join(samples)+"\n").encode()
with tempfile.TemporaryDirectory() as temp:
    t = Path(temp)
    (t/"source.cpp").write_text(cpp)
    (t/"adapter.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",str(t/"source.cpp"),"-o",str(t/"original")],check=True)
    ref = subprocess.run([str(t/"original")],input=data,capture_output=True,check=True).stdout.decode().splitlines()
    lua_bin=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    got = subprocess.run([lua_bin,str(t/"adapter.lua")],input=data,capture_output=True,check=True,cwd=root).stdout.decode().splitlines()
    assert len(ref)==len(got)==len(samples)+1
    for i,(expected,actual) in enumerate(zip(ref,got)):
        assert expected==actual, ("constants" if i==0 else samples[i-1],expected,actual)
    print(f"PASS: {len(samples)} OpenTTD 14.1 station rating cases and 4 source constants")
