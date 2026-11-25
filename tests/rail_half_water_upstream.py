#!/usr/bin/env python3
"""Compile the 16.0-RC1 half-tile flood routine and its source foundations."""
from pathlib import Path
import argparse
import subprocess
import tempfile
from rc1_rail_foundation_shim import rail_foundation_shim, source_block

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"


def block(file, pattern):
    return source_block(src, file, pattern)


shim = rail_foundation_shim(src)
shim += r"""
static Slope raw;
static TrackBits bits;
static RailGroundType ground;
static bool coast;
static int removed,allowed,tries;
bool IsPlainRailTile(TileIndex){return true;}
RailGroundType GetRailGroundType(TileIndex){return ground;}
void SetRailGroundType(TileIndex,RailGroundType g){ground=g;}
Slope GetTileSlope(TileIndex){return raw;}
TrackBits GetTrackBits(TileIndex){return bits;}
Track FindFirstTrack(TrackBits t){for(int i=0;i<6;i++)if(t.n&(1<<i))return Track(i);std::abort();}
enum class DoCommandFlag{Execute};
enum class Commands{RemoveRail};
int _current_company;
constexpr int OWNER_WATER=0;
struct AutoRestoreBackup{AutoRestoreBackup(int,int){}};
struct Result{bool Succeeded()const{return allowed;}};
template<Commands C> struct Command{
 static Result Do(DoCommandFlag,TileIndex,Track t){++tries;if(allowed){removed=1<<int(t);bits.Reset(t);}return {};}
};
void MakeShore(TileIndex){coast=true;}
void MarkTileDirtyByTile(TileIndex){}
"""
shim += block("rail_cmd.cpp",r"^bool FloodHalftile\(")
main = r"""
int main(){
  for(int shape: {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30})
    for(int mask=1;mask<64;mask++)
      if(GetRailFoundation(Slope(shape),mask)!=Foundation::Invalid)
        for(int g:{0,1,13})for(allowed=0;allowed<2;allowed++){
          raw=Slope(shape);bits=mask;ground=RailGroundType(g);coast=false;removed=0;tries=0;
          bool changed=FloodHalftile(0);
          std::cout<<shape<<" "<<mask<<" "<<g<<" "<<allowed<<" "<<changed<<" "<<coast<<" "
                   <<bits.n<<" "<<int(ground)<<" "<<removed<<" "<<tries<<"\n";
        }
}
"""
lua = r"""
local m="mods/luanttd_core/openttd/"
local W=dofile(m.."rail_half_water.lua")(dofile(m.."rail_track.lua"),dofile(m.."slope.lua"))
local cases=0
for row in io.lines() do
 local v={};for n in row:gmatch("%d+") do v[#v+1]=tonumber(n)end
 local shape,in_bits,in_ground,allow,changed,coast,bits,ground,removed,tries=unpack(v)
 local attempts=0
 local q=W.flood(shape,in_bits,in_ground,function()
   attempts=attempts+1
   return allow==1
 end)
 assert(attempts==tries and (not not q)==(changed==1),row)
 if q then
   assert((q.kind=="coast")==(coast==1) and (q.tracks or 0)==bits
      and (q.ground or in_ground)==ground and (q.removed or 0)==removed,row)
 end
 cases=cases+1
end
assert(cases>1700)
print(("PASS %d compiled RC1 FloodHalftile transitions, including foundation legality and denied removal"):format(cases))
"""
with tempfile.TemporaryDirectory() as td:
    cpp, exe = Path(td) / "rail.cpp", Path(td) / "rail"
    cpp.write_text(shim + main)
    subprocess.run(["g++", "-O2", "-std=c++20", str(cpp), "-o", str(exe)], check=True)
    fixture = subprocess.check_output([exe])
    script = Path(td) / "verify.lua"
    script.write_text(lua)
    subprocess.run([a.lua, script], input=fixture, check=True)
