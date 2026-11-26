"""Compare before/after tick phase against pinned RC1 RunTileLoop."""
from pathlib import Path
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parent.parent
source=Path(sys.argv[1]).resolve()
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
assert subprocess.check_output(["git","-C",source,"rev-parse","HEAD"],text=True).strip()=="07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
raw=(source/"src/landscape.cpp").read_text()
start=raw.index("void RunTileLoop()")
loop=raw[start:raw.index("\n}",start)+2]
shim=r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <iostream>
using uint=unsigned;
using std::size_t;
constexpr int MIN_MAP_SIZE_BITS=6,MAX_MAP_SIZE_BITS=12,TILE_UPDATE_FREQUENCY_LOG=8,TILE_UPDATE_FREQUENCY=256;
enum class PerformanceElement {GameLoopLandscape};
template<typename T,size_t N> constexpr size_t lengthof(const T (&)[N]){return N;}
struct TileIndex {
  unsigned i=0;
  unsigned base() const{return i;}
  bool operator!=(unsigned n) const{return i!=n;}
};
TileIndex _cur_tileloop_tile;
struct PerformanceAccumulator {PerformanceAccumulator(PerformanceElement){}};
struct TimerGameTick {static uint64_t counter;};
uint64_t TimerGameTick::counter;
unsigned lx,lz;
struct Map {static unsigned LogX(){return lx;} static unsigned LogY(){return lz;}};
int GetTileType(TileIndex){return 0;} int GetTileType(int){return 0;}
unsigned a,b,n,zeros;
void Visit(TileIndex t) {
  a=(a*257ull+t.base())%16777213;
  b=(b*271ull+TimerGameTick::counter)%16777213;
  n++;zeros+=t.base()==0;
}
struct {void(*tile_loop_proc)(TileIndex);} slot{Visit};
auto _tile_type_procs=std::array{&slot};
"""
driver=r"""
int main(){
  unsigned ticks,before;
  while(std::cin>>lx>>lz>>_cur_tileloop_tile.i>>TimerGameTick::counter>>ticks>>before){
    a=b=n=zeros=0;
    for(unsigned i=0;i<ticks;i++){
      if(before) ++TimerGameTick::counter;
      RunTileLoop();
      if(!before) ++TimerGameTick::counter;
    }
    std::cout<<a<<" "<<b<<" "<<n<<" "<<zeros<<" "<<_cur_tileloop_tile.i<<" "<<TimerGameTick::counter<<"\n";
  }
}
"""
adapter=r"""
local H=dofile('mods/luanttd_core/openttd/town_passengers.lua')
for line in io.lines() do
  local x,z,head,clock,ticks,before=line:match('(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)')
  local state=H.new_clock(tonumber(x),tonumber(z),tonumber(head),tonumber(clock))
  local a,b,n,zeros=0,0,0,0
  local step=before=='1' and H.advance or H.advance_initial
  step(state,tonumber(ticks),function(at,tick)
    a,b=(a*257+at)%16777213,(b*271+tick)%16777213
    n=n+1;if at==0 then zeros=zeros+1 end
  end)
  print(table.concat({a,b,n,zeros,state.head,state.counter},' '))
end
"""
rows=[]
for i,(x,z) in enumerate(((6,6),(6,7),(8,6),(8,8),(11,7),(12,12))):
    for j,(tick,count) in enumerate(((0,1),(0,1280 if x+z<=14 else 3),(253,8),(255,2),(256,5),(1024,12))):
        for before in (0,1):
            rows.append(f"{x} {z} {1+i*13+j*17} {tick} {count} {before}")
data="\n".join(rows)+"\n"
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"fixture.cpp").write_text(shim+loop+driver)
    (p/"fixture.lua").write_text(adapter)
    subprocess.run(["g++","-O2","-std=c++20",p/"fixture.cpp","-o",p/"stock"],check=True)
    expected=subprocess.check_output([p/"stock"],input=data,text=True).splitlines()
    actual=subprocess.check_output([lua,p/"fixture.lua"],input=data,text=True,cwd=root).splitlines()
assert len(expected)==len(rows)==len(actual)
for row,x,y in zip(rows,expected,actual):
    assert x==y,(row,x,y)
print(f"PASS {len(rows)} exact RC1 tile-loop schedules including tick zero, rectangular and 4096×4096 maps")
