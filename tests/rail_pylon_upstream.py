#!/usr/bin/env python3
"""Compile RC1's actual catenary support-selection statements against the Lua mount."""
import pathlib
import random
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = pathlib.Path(sys.argv[1]).resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
# Verify the generator byte-for-byte against the pinned C++ source before
# loading the same unmodified tables into the symbol-only C++ shim.
gen = root/"tools/port_rail_pylon_tables.py"
generated = subprocess.check_output([sys.executable,gen,source],text=True)
assert generated == (root/"mods/luanttd_core/openttd/rail_pylon_tables.lua").read_text()
raw = (source/"src/elrail.cpp").read_text()
start = raw.index("/* We cycle through all the existing tracks")
line = raw[raw.index("for (uint k",start):raw.index("/* Deactivate all PPPs",start)]
start=raw.index("if (tileh[TileSource::Home] == tileh[TileSource::Neighbour]",start)
prune = raw[start:raw.index("if (IsBridgeAbove(ti->tile))",start)]
start=raw.index("const auto &ppp_orders =",start)
pick = raw[start:raw.index("AddSortableSpriteToDraw(pylon_base +",start)]
shim = r"""
#include <iostream>
#include <array>
#include <initializer_list>
using uint = unsigned;
enum DiagDirection {NE=0,SE=1,SW=2,NW=3};
enum Direction {A0,A1,A2,A3,A4,A5,A6,A7,End};
enum TileSource {Home,Neighbour};
DiagDirection ReverseDiagDir(DiagDirection d) {return static_cast<DiagDirection>((d+2)%4);}
const auto EnumRange(Direction) {return std::array<Direction,8>{A0,A1,A2,A3,A4,A5,A6,A7};}
struct Bits {
  unsigned n;
  Bits(unsigned x=0):n(x) {}
  bool Any(Bits b=0x7fff) const {return (b.n&n)!=0;}
  bool Test(unsigned i) const {return (n&(1u<<i))!=0;}
  void Set(unsigned i) {n|=(1u<<i);}
  void Reset(unsigned i) {n&=~(1u<<i);}
  void Reset(Bits b) {n&=~b.n;}
  void operator&=(Bits b) {n&=b.n;}
  bool operator==(Bits b) const {return n==b.n;}
};
"""
def initializer(name):
    start=generated.index("  "+name+"=")+len(name)+3
    return generated[start:generated.index(",\n",start)]

def directions(init):
    # Only the final preference measurement uses a typed Direction array.
    import re
    return re.sub(r"\b[0-7]\b",lambda m:"A"+m[0],init)

decls = (
    ("Bits","_allowed_ppp_on_pcp[4]","allowed"),
    ("Bits","_owned_ppp_on_pcp[4]","owned"),
    ("Bits","_preferred_ppp_of_track_at_pcp[6][4]","preferred"),
    ("Bits","_disallowed_ppp_of_track_at_pcp[6][4]","blocked"),
    ("Bits","_ignored_pcp[3][4][4]","ignored"),
    ("uint","_tracks_at_pcp[4][6]","tracks"),
    ("uint","_track_source_tile[4][6]","source"),
    ("Direction","_ppp_order[4][4][8]","order"),
    ("int","_x_pcp_offsets[4]","pcp_x"),
    ("int","_y_pcp_offsets[4]","pcp_z"),
    ("int","_x_ppp_offsets[8]","ppp_x"),
    ("int","_y_ppp_offsets[8]","ppp_z"),
)
tables="\n".join(f"const {typ} {cpp}={directions(initializer(key)) if key=='order' else initializer(key)};" for typ,cpp,key in decls)
wrapper=r"""
const unsigned NUM_TRACKS_AT_PCP=6,NUM_IGNORE_GROUPS=3;
struct Dummy {int tile,x=0,y=0;};
int GetTileLocationGroup(int v) {return v;}
int bridge_dir;
bool IsBridgeTile(int) {return bridge_dir>=0;}
int GetTunnelBridgeDirection(int) {return bridge_dir;}
int choose(unsigned edge,unsigned tlg,unsigned ht,unsigned hw,unsigned nt,unsigned nw,
           int g1,int g2,int z1,int z2,int bridge,bool mask,bool override,bool station) {
  auto i = static_cast<DiagDirection>(edge);
  bridge_dir=bridge;
  int neighbour=1;
  Dummy token{int(tlg)}; Dummy *ti=&token;
  Bits pcp_status{},ppp_preferred[4]{},ppp_allowed[4]{};
  if (z1!=z2 || mask) nt=nw=0;
  Bits track_config[]{ht,nt},wire_config[]{hw,nw};
  int tileh[]{g1,g2};
  bool is_flat[]{ht>=4,nt>=4};
  ppp_preferred[i]=255;
  ppp_allowed[i]=_allowed_ppp_on_pcp[i];
"""
cpp = shim+tables+wrapper+line+"\nif (!pcp_status.Test(i)) return -1;\n"+prune+"\nif (!ppp_allowed[i].Any() || !pcp_status.Test(i) || override || station) return -1;\n"+pick+r"""
return temp+8*(x+32*y);
}
}
return -1;
}
int main() {
  unsigned e,l,ht,hw,nt,nw;
  int g1,g2,z1,z2,br,mask,ov,st;
  while(std::cin >> e >> l >> ht >> hw >> nt >> nw >> g1 >> g2 >> z1 >> z2 >> br >> mask >> ov >> st)
    std::cout << choose(e,l,ht,hw,nt,nw,g1,g2,z1,z2,br,mask,ov,st) << '\n';
}
"""
adapter = """
local r='mods/luanttd_core/openttd/'
local T=dofile(r..'rail_track.lua')
local P=dofile(r..'rail_pylon.lua')(T,dofile(r..'rail_pylon_tables.lua'))
for line in io.lines() do
  local a={}
  for x in line:gmatch('%-?%d+') do a[#a+1]=tonumber(x) end
  local h={tracks=a[3],wires=a[4],grade=a[7],z=a[9],no_pylons=a[14]==1}
  local n={tracks=a[5],wires=a[6],grade=a[8],z=a[10],bridge_inside=a[11],mask_hidden=a[12]==1}
  local d=P.choose(a[1],a[2],h,n,a[13]==1)
  if d==nil then print(-1) else
    local x,z=P.position(a[1],d)
    print(d+8*(x+32*z))
  end
end
"""
rng=random.Random(0x16)
rows=[]
for loc in range(4):
    for edge in range(4):
        for b in range(64):
            for n in range(64):
                rows.append((edge,loc,b,b,n,n,0,0,0,0,-1,0,0,0))
for _ in range(32768):
    ht,nt=rng.randrange(64),rng.randrange(64)
    rows.append((rng.randrange(4),rng.randrange(4),ht,rng.randrange(64)&ht,nt,rng.randrange(64)&nt,
                 rng.randrange(15),rng.randrange(15),4*rng.randrange(2),4*rng.randrange(2),
                 rng.randrange(-1,4),int(rng.random()<.15),int(rng.random()<.15),int(rng.random()<.15)))
data = "\n".join(" ".join(map(str,row)) for row in rows)+"\n"
with tempfile.TemporaryDirectory() as temp:
    p=pathlib.Path(temp)
    (p/"fixture.cpp").write_text(cpp)
    (p/"fixture.lua").write_text(adapter)
    subprocess.run(["g++","-std=c++20","-O2",p/"fixture.cpp","-o",p/"fixture"],check=True)
    expected=subprocess.check_output([p/"fixture"],input=data,text=True).splitlines()
    observed=subprocess.check_output([lua,p/"fixture.lua"],input=data,text=True,cwd=root).splitlines()
assert len(expected)==len(observed)==len(rows)
for row,e,o in zip(rows,expected,observed):
    assert e==o,(row,e,o)
print(f"PASS {len(rows):,} exact RC1 pylon decisions ({sum(x!='-1' for x in expected):,} pylons)")
