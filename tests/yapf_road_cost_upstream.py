#!/usr/bin/env python3
"""Compile unmodified OpenTTD 14.1 road cost methods over identical inputs.

Usage: python3 tests/yapf_road_cost_upstream.py /path/to/OpenTTD [lua5.1]
The fixture supplies track-follower results; the road follow differential
and pure Lua road cost test exercise the actual follower separately.
"""
from hashlib import sha256
from pathlib import Path
import random
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
checkout = Path(sys.argv[1])
relpath = Path("src/pathfinder/yapf/yapf_road.cpp")
path = next(p for p in [checkout / relpath, checkout / relpath.name] if p.is_file())
data = path.read_bytes()
assert sha256(data).hexdigest() == "063ce636d861505b3824977f8544ceab4846aed23f02b1b9a99913eb1a157b15"
source = data.decode()
cost = source[source.index("template <class Types>"):source.index("template <class Types>\nclass CYapfDestinationAnyDepotRoadT")]
shim = r"""
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <iostream>
using uint = unsigned;
using Trackdir = int;
using TileIndex = int;
using DiagDirection = int;
constexpr int YAPF_TILE_LENGTH=100, YAPF_TILE_CORNER_LENGTH=71;
constexpr int TILE_SIZE=16, MAX_MAP_SIZE=4096, TRACKDIR_BIT_NONE=0;
enum {MP_ROAD,MP_STATION};
struct TestTile {
    int kind, z, td, continuation, occupied, length, baymask, skip, next, bits, speed, dir;
} ts[9];
struct Settings {
    int road_slope_penalty, road_curve_penalty, road_crossing_penalty;
    int road_stop_penalty, road_stop_occupied_penalty, road_stop_bay_occupied_penalty;
};
bool IsDiagonalTrackdir(int td) { return (td&7)<2; }
int TrackdirToExitdir(int td) {
    constexpr int ds[14]={0,1,0,1,2,1,0,0,2,3,3,2,3,0};
    return ds[td];
}
int ReverseDiagDir(int d) { return (d+2)%4; }
int DiagDirToDiagTrackdir(int d) { return (d/2)*8+(d%2); }
int TileX(int t) { return t; }
int TileY(int) { return 0; }
int GetSlopePixelZ(int x,int,bool) { return ts[x/16].z; }
int GetTileType(int t) { return ts[t].kind>=2 && ts[t].kind<=3 ? MP_STATION : MP_ROAD; }
bool IsLevelCrossing(int t) { return ts[t].kind==1; }
bool IsDriveThroughStopTile(int t) { return ts[t].kind==2; }
int GetRoadStopType(int) { return 0; }
int TileOffsByDiagDir(int) { return 1; }
bool IsRoadDepotTile(int t) { return ts[t].kind==4; }
int GetRoadDepotDirection(int t) { return ts[t].dir; }
int KillFirstBit(int bits) { return bits & (bits-1); }
int FindFirstBit(int bits) { return __builtin_ctz(unsigned(bits)); }
struct RoadStop {
    struct Entry {
        int tile;
        int GetLength() const { return ts[tile].length; }
        int GetOccupied() const { return ts[tile].occupied; }
    };
    int tile;
    static const RoadStop *GetByTile(int tile,int) { static RoadStop rs; rs.tile=tile; return &rs; }
    static bool IsDriveThroughRoadStopContinuation(int a,int) { return ts[a].continuation==1; }
    const Entry *GetEntry(int) const { static Entry entry; entry.tile=this->tile; return &entry; }
    bool IsFreeBay(int bay) const { return !(ts[this->tile].baymask & (1<<bay)); }
};
struct RoadVehicle {
    int speed;
    struct { int speed; int GetMaxSpeed() const {return speed;} } current_order;
    int GetDisplayMaxSpeed() const { return this->speed; }
};
struct Follower {
    int m_new_tile, m_new_td_bits, m_tiles_skipped, old;
    Follower(const RoadVehicle *) {}
    bool Follow(int tile,int) {
        old=tile; m_new_tile=ts[tile].next; m_new_td_bits=ts[tile].bits;
        m_tiles_skipped=ts[tile].skip;
        return m_new_tile>=0;
    }
    int GetSpeedLimit(int *lo) const { *lo=0; return ts[old].speed; }
};
struct Node {
    struct Key { int m_tile,m_td; } m_key;
    Node *m_parent=nullptr;
    int m_cost=-1,m_segment_last_tile=-1,m_segment_last_td=-1;
};
struct Run;
struct Types {
    using Tpf=Run;
    using TrackFollower=Follower;
    struct NodeList { using Titem=Node; };
};
"""
driver = r"""
struct Run : CYapfCostRoadT<Types> {
    using CYapfCostRoadT<Types>::OneTileCost;
    Settings settings;
    RoadVehicle v;
    int dest, dest_td;
    const Settings &PfGetSettings() const { return settings; }
    const RoadVehicle *GetVehicle() const { return &v; }
    bool PfDetectDestinationTile(int tile, int td) const {
        return tile==dest && td==dest_td;
    }
};
int main() {
    Run r;
    int n,d,limit,tile,td,cost;
    while (std::cin>>n>>d>>r.dest_td>>limit>>tile>>td>>cost>>r.v.speed>>r.v.current_order.speed
        >>r.settings.road_slope_penalty>>r.settings.road_curve_penalty>>r.settings.road_crossing_penalty
        >>r.settings.road_stop_penalty>>r.settings.road_stop_occupied_penalty>>r.settings.road_stop_bay_occupied_penalty) {
        for (int i=0;i<n;i++) {
            auto &t=ts[i];
            std::cin>>t.kind>>t.z>>t.continuation>>t.occupied>>t.length>>t.baymask
                >>t.skip>>t.next>>t.bits>>t.speed>>t.dir;
        }
        r.dest=d; r.SetMaxCost(limit);
        Node p{{0,0}}; p.m_cost=cost;
        Node node{{tile,td}}; node.m_parent=cost>=0?&p:nullptr;
        bool ok=r.PfCalcCost(node,nullptr);
        std::cout<<r.OneTileCost(tile,td)<<' '<<ok<<' '<<node.m_segment_last_tile
            <<' '<<node.m_segment_last_td<<' '<<node.m_cost<<'\n';
    }
}
"""
lua = r"""
local F=dofile("mods/luanttd_core/openttd/yapf_road_follow.lua")
local C=dofile("mods/luanttd_core/openttd/yapf_road_cost.lua")(F)
local function read() return assert(io.read("*n")) end
local kd={[0]="road","crossing","drive_stop","bay_stop","depot"}
while true do
  local n=io.read("*n")
  if not n then break end
  local destination,dt,limit,tile,td,parent=read(),read(),read(),read(),read(),read()
  local v={display_max_speed=read(),order_max_speed=read()}
  local settings={}
  for _,k in ipairs({"road_slope_penalty","road_curve_penalty","road_crossing_penalty",
      "road_stop_penalty","road_stop_occupied_penalty","road_stop_bay_occupied_penalty"}) do
    settings[k]=read()
  end
  local tiles={}
  for i=0,n-1 do
    tiles[i]={kind=kd[read()],z=read(),continuation=read(),occupied=read(),length=read(),
      baymask=read(),skip=read(),next=read(),bits=read(),road_speed=read(),dir=read()}
  end
  local board={tile=function(i) return tiles[i] end,
    adjacent=function(i) return i-1 end,
    center_z=function(i) return tiles[i].z end,
    stop_continues=function(i) return tiles[i].continuation==1 end,
    stop_entry=function(i) return tiles[i].occupied,tiles[i].length end,
    bay_free=function(i,b) return not F.has_trackdir(tiles[i].baymask,b) end}
  F.follow=function(_,_,i)
    local t=tiles[i]
    return {ok=t.next>=0,tile=t.next,skip=t.skip,trackdirs=t.bits}
  end
  local node={tile=tile,td=td,parent=parent>=0 and {cost=parent} or nil}
  local d={kind="tile",tile=destination,trackdirs=2^dt}
  local ok=C.calc(board,v,d,node,settings,limit)
  print(C.one_tile(board,tile,td,settings),ok and 1 or 0,
      node.last_tile or -1,node.last_td or -1,node.cost or -1)
end
"""
rng = random.Random(141)
trackdirs = [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13]
cases = []
for _ in range(24000):
    n = rng.randint(2, 9)
    dest_td = rng.choice(trackdirs)
    tile_data = []
    for tile in range(n):
        kind = rng.randrange(5)
        targets = [-1, -1, 0] if tile == n - 1 else [tile + 1]*7 + [-1, 0]
        next_tile = rng.choice(targets)
        td = rng.choice(trackdirs)
        bits = 1 << td
        if rng.randrange(8) == 0:
            bits |= 1 << rng.choice(trackdirs)
        length = rng.randint(8, 96)
        tile_data.extend([kind, rng.choice([0, 1, 2, 4, 8]), rng.randrange(2),
                          rng.randrange(length + 1), length, rng.randrange(4),
                          rng.choice([0, 0, 0, 1, 3, 10]), next_tile, bits,
                          rng.choice([2**31 - 1, 30, 61, 75, 110, 250]), rng.randrange(4)])
    # Inject additional valid-choice simple loops and exact-reach destinations.
    tile = rng.randrange(n)
    td = rng.choice(trackdirs)
    terrain_and_limits = [n, rng.choice([-1, -1, tile, n-1]), dest_td,
                          rng.choice([0, 0, 0, 1, 250, 1100, 2500]),
                          tile, td, rng.choice([-1, 0, 90, 600]),
                          rng.randint(26, 250), rng.choice([65535, 30, 38, 66])]
    settings = [200, 100, 300, 800, 800, 1500]
    if rng.randrange(4) == 0:
        settings = [rng.randrange(2100) for _ in settings]
    cases.append(" ".join(map(str, terrain_and_limits + settings + tile_data)))
payload = ("\n".join(cases)+"\n").encode()
with tempfile.TemporaryDirectory() as work:
    w = Path(work)
    (w / "oracle.cpp").write_text(shim+cost+driver)
    (w / "run.lua").write_text(lua)
    subprocess.run(["c++", "-std=c++17", "-O2", str(w/"oracle.cpp"), "-o", str(w/"oracle")], check=True)
    def run(args):
        return subprocess.check_output(args, input=payload, cwd=root).decode().splitlines()
    expected = run([w / "oracle"])
    actual = run([sys.argv[2] if len(sys.argv)>2 else "lua5.1", w / "run.lua"])
    assert len(expected) == len(actual) == len(cases)
    for case, want, got in zip(cases, expected, actual):
        assert want.split() == got.split(), (case,want,got)
    print(f"PASS: {len(cases):,} pinned OpenTTD 14.1 OneTileCost and PfCalcCost cases")
