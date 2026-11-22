"""Compare extracted OpenTTD 14.1 WaterRegion and region-cost methods to Lua.

The C++ shim supplies a seeded ship-follower tile model. It compiles the
unmodified DFS/edge/neighbor methods themselves, not a second port of
region labeling. The Lua fixture uses the production ship follower.
"""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import random

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "water_regions.cpp":"92436e8be020086159a27d16c270df29434d1086d7c641a39c7aef562f286780",
    "yapf_ship_regions.cpp":"d543b0877789f27a2413bac5c7dcdf7637edb831740cfe4379264669945ce628",
}
def read(name):
    for d in ("","src","src/pathfinder","src/pathfinder/yapf"):
        p=SRC/d/name
        if p.is_file():
            b=p.read_bytes()
            assert sha256(b).hexdigest()==PINS[name], name
            return b.decode()
    raise FileNotFoundError(name)

def block(text,pattern):
    a=re.search(pattern,text,re.M).start()
    b=text.index("{",a);n=1
    while n:
        b+=1;n+=(text[b]=="{")-(text[b]=="}")
    return text[a:b+1]

src=read("water_regions.cpp")
high=read("yapf_ship_regions.cpp")
labeler=src[src.index("class WaterRegion\n"):src.index("\n\tvoid PrintDebugInfo()")]
cpp=r"""
#include <array>
#include <vector>
#include <cstdint>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <functional>
#include <memory>
using byte=uint8_t;
using uint=unsigned int;
using TileIndex=int;
using TrackBits=int;
using TrackdirBits=int;
using Trackdir=int;
using TWaterRegionPatchLabel=uint8_t;
using TWaterRegionTraversabilityBits=uint16_t;
using TWaterRegionIndex=uint;
using DiagDirection=int;
using DiagDirDiff=int;
constexpr int DIAGDIR_BEGIN=0,DIAGDIR_NE=0,DIAGDIR_SE=1,DIAGDIR_SW=2,DIAGDIR_NW=3,
  DIAGDIR_END=4,INVALID_DIAGDIR=255,AXIS_X=0,DIAGDIRDIFF_90RIGHT=1,DIAGDIRDIFF_90LEFT=3;
constexpr int WATER_REGION_EDGE_LENGTH=16,WATER_REGION_NUMBER_OF_TILES=256;
constexpr int INVALID_WATER_REGION_PATCH=0,FIRST_REGION_LABEL=1,DIRECT_NEIGHBOR_COST=100;
constexpr int TRACKDIR_BIT_NONE=0;
constexpr int N=64;
const int dx[]={-1,0,1,0},dz[]={0,1,0,-1};
int DiagDirToAxis(int d){return d%2;}
int ReverseDiagDir(int d){return (d+2)%4;}
int DiagDirDifference(int a,int b){return (a-b)&3;}
struct TileIndexDiffC {int x,y;};
TileIndexDiffC TileIndexDiffCByDiagDir(int d){return {dx[d],dz[d]};}
struct Map {static int SizeX(){return N;}static int SizeY(){return N;}};
int TileX(int id){return id%N;}
int TileY(int id){return id/N;}
bool valid(int x,int z){return x>=0&&z>=0&&x<N&&z<N;}
int TileXY(int x,int z){return valid(x,z)?z*N+x:-1;}
int TileAddByDiagDir(int id,int d){return TileXY(TileX(id)+dx[d],TileY(id)+dz[d]);}
bool IsValidTile(int id){return id>=0&&id<N*N;}
int DistanceManhattan(int a,int b){return std::abs(TileX(a)-TileX(b))+std::abs(TileY(a)-TileY(b));}
int DiagdirBetweenTiles(int a,int b){for(int d=0;d<4;d++)if(TileAddByDiagDir(a,d)==b)return d;return 255;}
template<typename T> void SetBit(T &bits,int p){bits|=(1<<p);}
bool HasBit(int bits,int p){return (bits>>p)&1;}
void Debug(...){}
#define NOT_REACHED() std::abort()
using TWaterRegionPatchLabelArray=std::array<byte,256>;
struct WaterRegionPatchDesc {
    int x,y,label;
    bool operator==(const WaterRegionPatchDesc &o)const{return x==o.x&&y==o.y&&label==o.label;}
};
using TVisitWaterRegionPatchCallBack=std::function<void(const WaterRegionPatchDesc&)>;
struct OrthogonalTileIterator {
    int id,w,at;
    int operator*()const{return id+at%w+at/w*N;}
    void operator++(){at++;}
    bool operator!=(const OrthogonalTileIterator&o)const{return at!=o.at;}
};
struct OrthogonalTileArea {
    int tile,w,h;
    OrthogonalTileArea(int t,int w_,int h_):tile(t),w(w_),h(h_){}
    bool Contains(int t)const{
      return IsValidTile(t)&&TileX(t)>=TileX(tile)&&TileY(t)>=TileY(tile)&&TileX(t)<TileX(tile)+w&&TileY(t)<TileY(tile)+h;
    }
    OrthogonalTileIterator begin()const{return {tile,w,0};}
    OrthogonalTileIterator end()const{return {tile,w,w*h};}
};
TrackdirBits TrackBitsToTrackdirBits(int bits){return bits*257;}
std::vector<int> SetTrackdirBitIterator(int n){
    std::vector<int> out;
    for(int d=0;d<14;d++)if(HasBit(n,d))out.push_back(d);
    return out;
}
struct Rec {int kind,dir,slope,other;};
std::array<Rec,N*N> map;
bool IsAqueductTile(int t){return IsValidTile(t)&&map[t].kind==4;}
int GetOtherBridgeEnd(int t){return map[t].other;}
int GetWaterTracks(int t){
    if(!IsValidTile(t))return 0;
    const auto q=map[t];
    int tracks=0;
    if(q.kind==1) tracks=q.slope==0?63:0;
    else if(q.kind==2) tracks=q.slope==1?32:q.slope==2?4:q.slope==4?16:q.slope==8?8:0;
    else if(q.kind==3||q.kind==4) tracks=1<<(q.dir%2);
    if(q.kind!=4&&TileX(t)==0)tracks &= ~(1|4|32);
    if(q.kind!=4&&TileY(t)==0)tracks &= ~(2|16|4);
    return tracks;
}
struct CFollowTrackWater {
    int m_new_tile;
    bool m_is_bridge;
    bool Follow(int t,int td){
        static int side[]={0,1,0,1,2,1,-1,-1,2,3,3,2,3,0};
        static int mask[]={1+8+4096,2+16+4,256+1024+32,512+8192+2048};
        const int d=side[td];
        m_is_bridge=IsAqueductTile(t)&&map[t].dir==d;
        m_new_tile=m_is_bridge?GetOtherBridgeEnd(t):TileAddByDiagDir(t,d);
        if(!(TrackBitsToTrackdirBits(GetWaterTracks(m_new_tile))&mask[d]))return false;
        return !IsAqueductTile(m_new_tile)||m_is_bridge||map[m_new_tile].dir==d;
    }
};
"""+ "\n".join(
    re.search(p,src,re.M).group(0) for p in (
    r"^static inline int GetWaterRegionX.*$",r"^static inline int GetWaterRegionY.*$",
    r"^static inline int GetWaterRegionMapSizeX.*$",r"^static inline int GetWaterRegionMapSizeY.*$",
    r"^static inline TWaterRegionIndex GetWaterRegionIndex\(int.*$",
    r"^static inline TWaterRegionIndex GetWaterRegionIndex\(TileIndex.*$"))+"\n"+labeler+"\n};\n"+r"""
std::vector<WaterRegion> _water_regions;
"""+ "\n".join(block(src,p) for p in (
    r"^TileIndex GetTileIndexFromLocalCoordinate",r"^TileIndex GetEdgeTileCoordinate",
    r"^WaterRegion &GetUpdatedWaterRegion\(uint",r"^WaterRegion &GetUpdatedWaterRegion\(TileIndex",
    r"^WaterRegionPatchDesc GetWaterRegionPatchInfo",r"^static inline void VisitAdjacentWaterRegionPatchNeighbors",
    r"^void VisitWaterRegionPatchNeighbors",r"^void AllocateWaterRegions"))+r"""
struct CYapfRegionPatchNodeKey {WaterRegionPatchDesc m_water_region_patch;};
"""+block(high,r"^inline uint ManhattanDistance")+"\n"+r"""
struct Node {
    Node *m_parent=nullptr;
    CYapfRegionPatchNodeKey m_key;
    int m_cost=0;
"""+block(high,r"^\s*DiagDirection GetDiagDirFromParent\(\) const")+r"""
};
using TrackFollower=int;
"""+block(high,r"^\s*inline bool PfCalcCost")+"\n"+r"""
int main(){
    int cases,n;
    if(std::scanf("%d",&cases)!=1)return 1;
    for(int i=0;i<cases;i++){
        map.fill({0,0,0,0});
        std::scanf("%d",&n);std::printf("m %d\n",i);
        for(int j=0;j<n;j++){
            int id,k,d,s,o;
            std::scanf("%d %d %d %d %d",&id,&k,&d,&s,&o);
            map[id]={k,d,s,o};
            std::printf("t %d %d %d %d %d\n",id,k,d,s,o);
        }
        AllocateWaterRegions();
        for(int z=0;z<4;z++)for(int x=0;x<4;x++){
            auto &r=GetUpdatedWaterRegion((uint16_t)x,(uint16_t)z);
            std::printf("r %d %d %d %d",x,z,r.NumberOfPatches(),r.HasCrossRegionAqueducts());
            for(int d=0;d<4;d++)std::printf(" %d",r.GetEdgeTraversabilityBits(d));
            std::puts("");
            for(int l=1;l<=r.NumberOfPatches();l++){
                std::printf("g %d %d %d",x,z,l);
                TVisitWaterRegionPatchCallBack out=[](const WaterRegionPatchDesc&p){std::printf(" %d %d %d",p.x,p.y,p.label);};
                VisitWaterRegionPatchNeighbors({x,z,l},out);
                std::puts("");
            }
        }
        for(int t=0;t<N*N;t++)std::printf("l %d %d\n",t,GetWaterRegionPatchInfo(t).label);
    }
    for(int i=0;i<4;i++)for(int j=0;j<4;j++)for(int a=1;a<5;a++)for(int b=1;b<5;b++){
        Node g,p,n;p.m_parent=&g;n.m_parent=&p;p.m_cost=200;
        g.m_key={{6,6,1}};
        p.m_key={{6+a*dx[i],6+a*dz[i],1}};
        n.m_key={{p.m_key.m_water_region_patch.x+b*dx[j],p.m_key.m_water_region_patch.y+b*dz[j],1}};
        PfCalcCost(n,nullptr);
        auto q=p.m_key.m_water_region_patch,r=n.m_key.m_water_region_patch;
        std::printf("c %d %d %d %d %d\n",q.x,q.y,r.x,r.y,n.m_cost-200);
    }
}
"""
rng=random.Random(141)
worlds=[]
for _ in range(14):
    density=rng.uniform(.18,.62)
    cells={}
    for z in range(64):
        for x in range(64):
            if rng.random()>density:
                continue
            k=rng.choices((1,2,3),(6,2,1))[0]
            s=rng.choice((1,2,4,8)) if k==2 else 0
            cells[z*64+x]=(k,rng.randrange(4),s,0)
    for i in range(10):
        x,z=rng.randrange(2,62),rng.randrange(2,62)
        y=rng.randrange(x+1,64)
        t,u=z*64+x,z*64+y
        if (cells.get(t,(0,))[0],cells.get(u,(0,))[0]).count(4)==0:
            cells[t]=(4,2,0,u);cells[u]=(4,0,0,t)
    worlds.append(cells)
rows=[str(len(worlds))]
for cells in worlds:
    rows.append(str(len(cells)))
    rows.extend(f"{t} {k} {d} {s} {o}" for t,(k,d,s,o) in cells.items())

lua=r"""
local base="mods/luanttd_core/openttd/"
local T=dofile(base.."rail_track.lua")
local W=dofile(base.."ship_follow.lua")(T)
local Rfn=dofile(base.."ship_regions.lua")
local R,tiles
local n={m=0,t=0,r=0,g=0,l=0,c=0}
local function id(x,z) if x>=0 and z>=0 and x<64 and z<64 then return z*64+x end end
local function xy(i) return i%64,math.floor(i/64) end
local dxy={[0]={-1,0},{0,1},{1,0},{0,-1}}
local B={tile_at=id,xy=xy,tile=function(i)return tiles[i] end}
function B.adjacent(i,d)
    local x,z=xy(i)
    return id(x+dxy[d][1],z+dxy[d][2])
end
for line in io.lines() do
    local op=line:sub(1,1)
    n[op]=n[op]+1
    local a={}
    for v in line:gmatch("-?%d+") do a[#a+1]=tonumber(v) end
    if op=="m" then
        tiles={}
        R=Rfn(T,W,B,{width=64,height=64})
    elseif op=="t" then
        tiles[a[1]]={kind=({"sea","coast","lock","aqueduct"})[a[2]],dir=a[3],
            slope=a[4],other=a[5],water_class="sea"}
    elseif op=="r" then
        local r=R.info(a[1],a[2])
        assert(r.count==a[3] and r.cross_aqueduct==(a[4]==1),line)
        for j=0,3 do assert(r.edge[j]==a[5+j],line) end
    elseif op=="g" then
        local neighbors=R.neighbors({x=a[1],z=a[2],label=a[3],region=a[2]*4+a[1]})
        assert(#neighbors==(#a-3)/3,line)
        for j,q in ipairs(neighbors) do
            assert(q.x==a[3*j+1] and q.z==a[3*j+2] and q.label==a[3*j+3],line)
        end
    elseif op=="l" then
        assert(R.region_patch(a[1])==a[2],line)
    elseif op=="c" then
        assert(R.cost({x=6,z=6},{x=a[1],z=a[2]},{x=a[3],z=a[4]})==a[5],line)
    end
end
assert(n.m==14 and n.r==224 and n.l==57344 and n.c==256 and n.g>50)
print(("PASS: stock region C++ compared %d patches edge/neighbor lists, %d tile labels and %d cost chains"):format(n.g,n.l,n.c))
"""
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"reference.cpp").write_text(cpp)
    (p/"verify.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",p/"reference.cpp","-o",p/"reference"],check=True)
    truth=subprocess.check_output([p/"reference"],input="\n".join(rows).encode())
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],cwd=ROOT,input=truth,check=True)
