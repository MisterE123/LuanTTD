"""Compare the Lua payment port with the pinned C++ default payment branch."""
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
def input_source(name):
    return (source / name if (source / name).exists() else source / "src" / name).read_text()

s = input_source("economy.cpp")
expected = "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb"
assert sha256(s.encode()).hexdigest() == expected, "Expected OpenTTD 14.1 src/economy.cpp"
start = s.index("static const int MIN_TIME_FACTOR = 31;", s.index("Money GetTransportedGoodsIncome("))
end = s.index("\n}",start)
algo = s[start:end]
cpp = """
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <initializer_list>
using uint = unsigned;
using Money = int64_t;
struct CargoSpec { int current_payment; int transit_periods[2]; };
int64_t BigMulS(int64_t a,int64_t b,int shift){return (a*b)>>shift;}
Money get(uint num_pieces,uint dist,uint16_t transit_periods,const CargoSpec *cs) {
""" + algo + """
}
int main() {
  constexpr CargoSpec specs[]={{3185,{0,24}},{5916,{7,255}},{4550,{20,90}},
    {6144,{5,28}},{4778,{4,40}},{5688,{7,255}}};
  for(int i=0;i<6;i++)for(int n : {1,30,520,1000})for(int d : {0,1,9,180,8190}) {
    for(int age=0;age<480;age++) {
      printf("%d %d %d %d %lld\\n",i+1,n,d,age,(long long)get(n,d,age,&specs[i]));
    }
  }
}
"""
lua=r"""
local I=dofile("mods/luanttd_core/openttd/income.lua")
local names={"passenger","coal","mail","goods","grain","steel"}
local count=0
for line in io.lines() do
 local i,n,d,age,want=line:match("(%d+) (%d+) (%d+) (%d+) (%d+)")
 local got=I.regular(tonumber(n),tonumber(d),tonumber(age),unpack(I.temperate[names[tonumber(i)]]))
 assert(got==tonumber(want),line.." Lua = "..got)
 count=count+1
end
assert(count==57600)
print("PASS: "..count.." OpenTTD 14.1 C++/Lua default cargo payment cases")
"""
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)
    (p/"ref.cpp").write_text(cpp)
    (p/"test.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",p/"ref.cpp","-o",p/"ref"],check=True)
    truth=subprocess.check_output([p/"ref"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"test.lua"],cwd=root,input=truth,check=True)
