"""Compare Lua tunnel costs and visibility against pinned OpenTTD source."""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

source = Path(sys.argv[1]).read_text()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
root = Path(__file__).resolve().parents[1]
cmd = source[source.index("CommandCost CmdBuildTunnel"):source.index("static const byte TUNNEL_SOUND_FRAME")]
step = re.search(r"\s*tiles\+\+;\s*if \(tiles == tiles_bump\).*?cost.AddCost\(cost.GetCost\(\) >> tiles_coef\);",
                 cmd, re.S).group(0)
consts = "\n".join(re.search(r"int " + v + r" = \d+;", cmd).group(0)
                   for v in ("tiles_coef", "tiles", "tiles_bump"))
vis = re.search(r"_tunnel_visibility_frame\[DIAGDIR_END\] = (\{[^}]+\});", source).group(1)
c = f'''
#include <iostream>
struct Cost {{ long long n=0; void AddCost(long long d) {{ n+=d; }} long long GetCost() {{ return n; }} }};
int main() {{
  int middle,price,road,a,b;
  while(std::cin>>middle>>price>>road>>a>>b) {{
    enum {{ PR_BUILD_TUNNEL=0 }}; int _price[]={{price}};
    Cost cost;
    {consts}
    for(int i=0;i<middle;++i) {{ {step} }}
    cost.AddCost(_price[PR_BUILD_TUNNEL]); cost.AddCost(a);
    cost.AddCost(b); cost.AddCost(_price[PR_BUILD_TUNNEL]);
    cost.AddCost((tiles+2)*road*2);
    int f[4]={vis};
    std::cout<<cost.n;for(int n:f)std::cout<<" "<<n;std::cout<<"\\n";
  }}
}}
'''
lua_src = """
local T=dofile("mods/bayline/openttd/road_tunnel.lua")
local W=dofile("mods/bayline/road_bridge_motion.lua")
local function frame(d,f)
  local p=(d==0 or d==3) and 15-f or f
  return d%2==0 and p or 0,d%2==1 and p or 0
end
for line in io.lines() do
  local a,b,c,d,e=line:match("(%d+) (%d+) (%d+) (%d+) (%d+)")
  local r={T.construction_cost(tonumber(a),tonumber(d),tonumber(e),tonumber(b),tonumber(c))}
  for dir=0,3 do
    local n=0
    for f=0,15 do
      local x,z=frame(dir,f)
      if W.enters({kind="tunnel",dir=dir},2*dir+1,x,z) then n=n+1;r[#r+1]=f end
    end
    assert(n==1)
  end
  print(table.concat(r," "))
end
"""
samples = "".join(f"{a} {b} {c} {a%33} {(b+c)%57}\n"
                  for a in range(302) for b in (0, 1, 17, 450, 1200) for c in (0, 95, 190)).encode()
with tempfile.TemporaryDirectory() as d:
    p = Path(d)
    (p/"r.cpp").write_text(c)
    (p/"r.lua").write_text(lua_src)
    subprocess.run(["c++","-O2","-std=c++17",str(p/"r.cpp"),"-o",str(p/"ref")],check=True)
    reference=subprocess.check_output([p/"ref"],input=samples)
    actual=subprocess.check_output([lua,p/"r.lua"],cwd=root,input=samples)
assert reference==actual
print(f"PASS: {len(reference.splitlines()):,} source tunnel cost and four visibility frame comparisons")
