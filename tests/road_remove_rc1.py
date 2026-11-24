"""Compile the unmodified normal-road removal statements from 16.0-RC1."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

src = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[1]
assert subprocess.check_output(["git", "-C", str(src), "rev-parse", "HEAD"], text=True).strip() == \
    "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
code = (src / "src/road_cmd.cpp").read_text()
table = code[code.index("static const std::array<NonSteepSlopeIndexArray<RoadBits>"):]
table = table[:table.index(";", table.index("}};"))+1]
foundation = code[code.index("static Foundation GetRoadFoundation(Slope tileh, RoadBits bits)\n{"):]
foundation = foundation[:foundation.index("\n}")+2]
remove = code[code.index("static CommandCost RemoveRoad("):]
remove = remove[remove.index("case RoadTileType::Normal: {"):]
mark = remove.index("/* Steep slopes behave")
body = remove[mark:remove.index("if (flags.Test(DoCommandFlag::Execute)) {", mark)]
# Only replace unavailable mapping/engine expressions; C++ conditionals remain verbatim.
assert "present.Flip(pieces)" in body and "RoadWorks" in body
body = body.replace("RoadBits present = GetRoadBits(tile, rtt);", "RoadBits present = old;")
body = body.replace("const RoadBits other = GetRoadBits(tile, OtherRoadTramType(rtt));", "")
body = body.replace("if (HasRoadWorks(tile) && _current_company != OWNER_WATER) return CommandCost(STR_ERROR_ROAD_WORKS_IN_PROGRESS);", "")
body, n = re.subn(r"return CommandCost\(\(rtt == .*?\);", "return {-1,0,0};", body)
assert n == 1
body = body.replace("return CMD_ERROR;", "return {-2,0,0};")
stub = """
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
enum RoadBit {NW,SW,SE,NE};
struct RoadBits {
 int b{0};
 RoadBits()=default;
 explicit RoadBits(int n):b(n){}
 RoadBits(RoadBit k):b(1<<k){}
 RoadBits(std::initializer_list<RoadBit> v){for(auto k:v)b|=1<<k;}
 bool Any() const{return b!=0;}
 bool Any(RoadBits other) const{return (b&other.b)!=0;}
 bool All(RoadBits other) const{return (b&other.b)==other.b;}
 bool None()const{return b==0;}
 void Set(RoadBits v){b|=v.b;}
 void Flip(RoadBits v){b^=v.b;}
 RoadBits& operator&=(RoadBits o){b&=o.b;return *this;}
 bool operator==(RoadBits o)const{return b==o.b;}
};
enum Slope {SLOPE_FLAT=0,SLOPE_ELEVATED=15};
int operator&(Slope a,Slope b){return ((int)a)&((int)b);}
enum class Foundation {None,Leveled,InclinedX,InclinedY};
template<typename T> struct NonSteepSlopeIndexArray {
 std::array<T,15> a;
 const T& operator[](int i)const{return a.at(i);}
};
const RoadBits ROAD_X(10), ROAD_Y(5), ROAD_ALL(15);
bool IsSlopeWithOneCornerRaised(Slope s){return s==1||s==2||s==4||s==8;}
bool IsSteepSlope(Slope s){return s&16;}
int GetHighestSlopeCorner(Slope s){
 switch((int)s){case 23:return 1;case 27:return 0;case 29:return 3;case 30:return 2;default:std::abort();}
}
Slope SlopeWithOneCornerRaised(int c){return static_cast<Slope>(1<<c);}
RoadBits MirrorRoadBits(RoadBits b){return RoadBits(((b.b&3)<<2) | (b.b>>2));}
bool IsStraightRoad(RoadBits b){return b==ROAD_X||b==ROAD_Y;}
struct {struct {bool build_on_slopes;} construction;} _settings_game;
struct Result{int remove,remain,pay;};
"""
main = """
return {pieces.b,present.b,f==Foundation::None && GetRoadFoundation(tileh,present)!=Foundation::None};
}
int main(){
 for(int s=0;s<=30;s++){
  if(s>=15&&s!=23&&s!=27&&s!=29&&s!=30)continue;
  for(int on=0;on<2;on++){
   _settings_game.construction.build_on_slopes=on!=0;
   for(int exists=0;exists<16;exists++)for(int other=0;other<16;other++)for(int add=1;add<16;add++){
    auto r=Check(static_cast<Slope>(s),RoadBits(add),RoadBits(exists),RoadBits(other));
    printf("%d %d %d %d %d %d %d %d\\n",s,on,add,exists,other,r.remove,r.remain,r.pay);
   }
  }
 }
}
"""
lua = """
local S=dofile('mods/luanttd_core/openttd/road_slope.lua')
local n=0
for row in io.lines(arg[1]) do
  local d={}
  for field in row:gmatch('%-?%d+') do d[#d+1]=tonumber(field) end
  local got,why=S.remove(d[1],d[3],d[4],d[5],d[2]==1)
  if d[6]<0 then
    assert(not got and why==(d[6]==-1 and 'NO_ROAD_PIECES' or 'WRONG_SLOPE'),row)
  else
    assert(got and got.removed==d[6] and got.road_bits==d[7] and got.foundation==(d[8]==1),row)
  end
  n=n+1
end
assert(n==145920)
print('PASS '..n..' stock RC1 normal-road removal geometry, surviving road bits and foundation decisions')
"""
with tempfile.TemporaryDirectory() as td:
    p = Path(td)
    cpp = p / "road_remove.cpp"
    cpp.write_text(stub + table + foundation +
                   "Result Check(Slope tileh,RoadBits pieces,RoadBits old,RoadBits other){\n" + body + main)
    exe, csv, script = p/"run", p/"rows", p/"check.lua"
    subprocess.run(["g++","-std=c++20","-O2",str(cpp),"-o",str(exe)],check=True)
    with csv.open("wb") as output: subprocess.run([str(exe)],stdout=output,check=True)
    script.write_text(lua)
    subprocess.run([os.environ.get("LUA","lua5.1"),str(script),str(csv)],cwd=root,check=True)
