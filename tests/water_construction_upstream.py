"""Compare compiled, pinned 14.1 canal/lock commands and tile iterators."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "water_cmd.cpp":"f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847",
    "water_map.h":"1b3cf332d0a0f61957c109710e68bc0869dca2038c8c0d05aec39b44f6e422a8",
    "tilearea.cpp":"7a7071ad5c3e6a36e2abd4c10390398be914c139cf6f20ce31e5e3fe0e18484f",
    "tilearea_type.h":"8b759de3400fcfb2abc9fc89a83c86b8cff7dccf5c3bfa60fc6ac4c026785ada",
    "pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "economy_type.h":"3ceaeaae7a62363f3243a1b337f1e84c98c74d22a81c0dd71c74921955e6697b",
    "slope_func.h":"1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a",
}
def read(name):
    for d in ("","src","src/table"):
        p=SRC/d/name
        if p.is_file():
            b=p.read_bytes()
            assert sha256(b).hexdigest()==PINS[name],name
            return b.decode()
    raise FileNotFoundError(name)

def block(text,pattern):
    a=re.search(pattern,text,re.M).start()
    b=text.index("{",a);n=1
    while n:
        b+=1;n+=(text[b]=="{")-(text[b]=="}")
    return text[a:b+1]

wc=read("water_cmd.cpp")
area=read("tilearea.cpp")
iter_h=read("tilearea_type.h")
p_base=read("pricebase.h")
prices=[int(re.search(r"\{\s*(\d+),[^\n]+///< PR_"+k+r"\b",p_base).group(1))
        for k in ("BUILD_CANAL","BUILD_LOCK","CLEAR_CANAL","CLEAR_WATER")]
factor=re.search(r"^static const uint LOCK_DEPOT_TILE_FACTOR = .*?;",read("economy_type.h"),re.M).group(0)
slope_in=block(read("slope_func.h"),r"^inline DiagDirection GetInclinedSlopeDirection")
cpp=r"""
#include <array>
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <memory>
#include <algorithm>
#include <cstdlib>
#include <cstring>
using uint=unsigned;
using TileIndex=uint;
using Tile=TileIndex;
using DiagDirection=int;
using Slope=int;
using Owner=int;
using DoCommandFlag=int;
constexpr uint N=8;
constexpr TileIndex INVALID_TILE=UINT32_MAX;
struct Map {static uint SizeX(){return N;} static uint SizeY(){return N;}static uint Size(){return N*N;}};
uint TileX(TileIndex t){return t%N;}
uint TileY(TileIndex t){return t/N;}
uint TileXY(uint x,uint y){return y*N+x;}
int TileDiffXY(int x,int z){return z*N+x;}
#define TILE_ADDXY(t,x,y) ((t)+TileDiffXY((x),(y)))
template<class T> void Swap(T &a,T &b){std::swap(a,b);}
enum{DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,INVALID_DIAGDIR=255};
enum{SLOPE_FLAT=0,SLOPE_NE=12,SLOPE_SE=6,SLOPE_SW=3,SLOPE_NW=9};
enum WaterClass{WATER_CLASS_SEA,WATER_CLASS_CANAL,WATER_CLASS_RIVER,WATER_CLASS_INVALID};
enum{PR_BUILD_CANAL,PR_BUILD_LOCK,PR_CLEAR_CANAL,PR_CLEAR_WATER};
constexpr int _price[]={"""+",".join(map(str,prices))+r"""};
enum{OWNER_NONE=0,OWNER_WATER=1,OWNER_COMPANY=2,OWNER_OTHER=3};
enum{LOCK_PART_MIDDLE,LOCK_PART_LOWER,LOCK_PART_UPPER};
enum{DC_EXEC=1,GM_EDITOR=1,MP_WATER=1,EXPENSES_CONSTRUCTION=0,CMD_LANDSCAPE_CLEAR=1,
     STR_ERROR_FLAT_LAND_REQUIRED=2,STR_ERROR_ALREADY_BUILT=3,
     STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION=4,STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST=5};
struct CommandCost {
    int c;
    CommandCost(int=EXPENSES_CONSTRUCTION,int v=0):c(v){}
    bool Failed()const{return c<0;}
    bool Succeeded()const{return c>=0;}
    int GetCost()const{return c;}
    void AddCost(CommandCost r){c+=r.c;}
    void AddCost(int r){c+=r;}
};
CommandCost CMD_ERROR(0,-1);
#define return_cmd_error(e) return CommandCost(0,-(e))
int _game_mode=0;
constexpr Owner _current_company=OWNER_COMPANY;
struct Rec {int kind=0;int cls=3;int owner=0;int slope=0;int base=0;int occupied=0;int overhead=0;int part=-1;int dir=-1;};
std::array<Rec,N*N> m;
int TileOffsByDiagDir(int d){const int dirs[]={-1,int(N),1,-int(N)};return dirs[d];}
using TileIndexDiff=int;
Slope GetTileSlope(Tile t){return m[t].slope;}
bool IsTileFlat(Tile t){return m[t].slope==0;}
uint TileHeight(Tile t){return m[t].base;}
bool IsValidWaterClass(WaterClass c){return c<WATER_CLASS_INVALID;}
bool IsWaterTile(Tile t){return m[t].kind==1;}
bool IsTileType(Tile t,int type){return m[t].kind==type;}
bool IsCanal(Tile t){return IsWaterTile(t)&&m[t].cls==WATER_CLASS_CANAL;}
bool IsTileOwner(Tile t,Owner owner){return m[t].owner==owner;}
bool HasTileWaterGround(Tile t){return IsWaterTile(t);}
WaterClass GetWaterClass(Tile t){return WaterClass(m[t].cls);}
Owner GetTileOwner(Tile t){return m[t].owner;}
bool IsBridgeAbove(Tile t){return m[t].overhead;}
uint Random(){return 0;}
void MarkTileDirtyByTile(Tile){}
void MarkCanalsAndRiversAroundDirty(Tile){}
void CheckForDockingTile(Tile){}
void InvalidateWaterRegion(Tile){}
constexpr int RIVER_OFFSET_DESERT_DISTANCE=5;
bool RiverModifyDesertZone(Tile){return false;}
void CircularTileSearch(Tile*,int,bool(*)(Tile),void*){}
struct Company {
    struct{int water=0;} infrastructure;
    static bool IsValidID(Owner o){return o==2||o==3;}
    static Company *Get(Owner o){static Company a[4];return &a[o];}
    static Company *GetIfValid(Owner o){return IsValidID(o)?Get(o):nullptr;}
};
void DirtyCompanyInfrastructureWindows(Owner){}
CommandCost EnsureNoVehicleOnGround(Tile t){return CommandCost(0,m[t].occupied?-6:0);}
template<int>struct Command{
    static CommandCost Do(DoCommandFlag flags,Tile id){
      const Rec t=m[id];
      if(t.occupied)return CommandCost(0,-6);
      if(t.kind==3)return CommandCost(0,-8); // protected structure
      if(t.kind==1&&t.owner==OWNER_OTHER)return CommandCost(0,-7);
      int pay=t.kind==1?_price[t.cls==WATER_CLASS_CANAL?PR_CLEAR_CANAL:PR_CLEAR_WATER]:
          t.kind==2?(t.slope==1||t.slope==2||t.slope==4||t.slope==8?10000:40):20;
      if(flags&DC_EXEC) {
        if(t.kind==1&&t.cls==WATER_CLASS_CANAL&&Company::IsValidID(t.owner))
          Company::Get(t.owner)->infrastructure.water--;
        m[id]={0,3,0,t.slope,t.base,0,t.overhead,-1,-1};
      }
      return CommandCost(0,pay);
    }
};
void MakeCanal(Tile t,Owner o,[[maybe_unused]] uint r){m[t].kind=1;m[t].owner=o;m[t].cls=WATER_CLASS_CANAL;}
void MakeRiver(Tile t,[[maybe_unused]] uint r){m[t].kind=1;m[t].owner=OWNER_WATER;m[t].cls=WATER_CLASS_RIVER;}
void MakeSea(Tile t){m[t].kind=1;m[t].owner=OWNER_WATER;m[t].cls=WATER_CLASS_SEA;}
void MakeLockTile(Tile t,Owner o,int part,DiagDirection dir,WaterClass c){
  m[t].kind=4;m[t].owner=o;m[t].cls=c;m[t].part=part;m[t].dir=dir;
}
"""+factor+"\n"+slope_in+r"""
bool IsInclinedSlope(Slope s){return GetInclinedSlopeDirection(s)!=INVALID_DIAGDIR;}
class OrthogonalTileIterator;
"""+ ";\n".join(block(iter_h,p) for p in (r"^struct OrthogonalTileArea \{",r"^struct DiagonalTileArea \{",
        r"^class TileIterator \{",r"^class OrthogonalTileIterator : ",r"^class DiagonalTileIterator : "))+";\n"+ "\n".join(
    block(area,p) for p in (r"^OrthogonalTileArea::OrthogonalTileArea\(",r"^DiagonalTileArea::DiagonalTileArea\(",
        r"^TileIterator &DiagonalTileIterator::operator\+\+",r"^/\* static \*/ std::unique_ptr<TileIterator> TileIterator::Create"))+"\n"+block(
        read("water_map.h"),r"^inline void MakeLock\(")+"\n"+ "\n".join(block(wc,p) for p in (
        r"^static CommandCost DoBuildLock",r"^CommandCost CmdBuildLock",r"^CommandCost CmdBuildCanal"))+r"""
int main(){
    for(uint s=0;s<Map::Size();s++)for(uint e=0;e<Map::Size();e++)for(int diag=0;diag<2;diag++){
        auto it=TileIterator::Create(e,s,diag);
        std::printf("a %u %u %d",s,e,diag);
        for(;*it!=INVALID_TILE;++(*it))std::printf(" %u",**it);
        std::puts("");
    }
    auto dump=[](Tile i){const auto t=m[i];std::printf(" %d %d %d %d %d",t.kind,t.cls,t.owner,t.part,t.dir);};
    const Tile center=TileXY(3,3);
    int slopes[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30};
    for(int ed=0;ed<2;ed++)for(int wc=0;wc<4;wc++)for(int slope:slopes)for(int h=0;h<2;h++)
    for(int k=0;k<4;k++)for(int cls=0;cls<3;cls++)for(int owner=0;owner<4;owner++)for(int oc=0;oc<2;oc++){
        _game_mode=ed;
        m[center]={k,cls,owner,slope,h,oc,0,-1,-1};
        auto before=m[center];
        auto q=CmdBuildCanal(0,center,center,WaterClass(wc),false);
        assert(std::memcmp(&before,&m[center],sizeof(Rec))==0);
        int result=q.Failed()?0:CmdBuildCanal(DC_EXEC,center,center,WaterClass(wc),false).c;
        std::printf("c %d %d %d %d %d %d %d %d %d %d",ed,wc,slope,h,k,cls,owner,oc,q.c,result);
        dump(center);std::puts("");
    }
    std::srand(141);
    for (int j=0;j<4500;j++){
        int slope=slopes[std::rand()%19];
        int dir=GetInclinedSlopeDirection(slope);
        int k=dir==INVALID_DIAGDIR?DIAGDIR_SW:dir;
        Tile low=center-TileOffsByDiagDir(k),high=center+TileOffsByDiagDir(k);
        m.fill({});
        for(Tile i:{center,low,high}){
            m[i]={std::rand()%4,std::rand()%3,std::rand()%4,
                std::rand()%10==0?1:0,i==high?1:0,std::rand()%8==0,std::rand()%8==0,-1,-1};
        }
        m[center].slope=slope;
        auto before=m;
        auto q=CmdBuildLock(0,center);
        assert(std::memcmp(before.data(),m.data(),sizeof(m))==0);
        int result=q.Failed()?0:CmdBuildLock(DC_EXEC,center).c;
        std::printf("l %d %d %d %d",slope,k,q.c,result);
        for(Tile i:{center,low,high}){
            const auto t=before[i];std::printf(" %d %d %d %d %d %d %d",t.kind,t.cls,t.owner,t.slope,t.base,t.occupied,t.overhead);
        }
        for(Tile i:{center,low,high})dump(i);
        std::puts("");
    }
}
"""
lua=r"""
local path="mods/bayline/openttd/"
local T=dofile(path.."rail_track.lua")
local W=dofile(path.."ship_follow.lua")(T)
local C=dofile(path.."water_construction.lua")(T,W)
local records={}
local function id(x,z) if x>=0 and z>=0 and x<8 and z<8 then return z*8+x end end
local function xy(i) return i%8,math.floor(i/8) end
local d={[0]={-1,0},{0,1},{1,0},{0,-1}}
local B={tile_at=id,xy=xy,tile=function(t) return records[t] or {kind="clear"} end}
function B.adjacent(i,dir)
  local x,z=xy(i);return id(x+d[dir][1],z+d[dir][2])
end
local classes={[0]="sea","canal","river"}
local owners={[0]="none","water","company","other"}
local errors={[-1]="INVALID_PARAMETER",[-2]="FLAT_LAND_REQUIRED",[-3]="ALREADY_BUILT",
  [-4]="LAND_SLOPED_IN_WRONG_DIRECTION",[-5]="MUST_DEMOLISH_BRIDGE_FIRST",[-6]="VEHICLE_IN_THE_WAY",
  [-7]="OWNED_BY_ANOTHER",[-8]="LANDSCAPE_CLEAR_REQUIRED"}
local function rec(k,c,o,s,h,busy,bridge)
  local kinds={[0]="clear","water","coast","protected"}
  return {kind=kinds[k],water_class=classes[c],owner=owners[o],slope=s,base=h,occupied=busy==1,overhead=bridge==1,
      clear_cost=k==0 and 20 or nil}
end
local function result(p,why,quote,exec,line)
  if quote<0 then assert(not p and why==errors[quote],line.." -> "..tostring(why))
  else assert(p and p.cost==quote and p.cost==exec,line.." -> "..tostring(p and p.cost).." "..tostring(why)) end
end
local center=id(3,3)
local n={a=0,c=0,l=0}
for line in io.lines() do
  local mode=line:sub(1,1)
  local a={}
  for q in line:gmatch("-?%d+") do a[#a+1]=tonumber(q) end
  n[mode]=n[mode]+1
  if mode=="a" then
    local list=C.area(B,a[1],a[2],a[3]==1)
    assert(#list==#a-3,line)
    for i,k in ipairs(list) do assert(k==a[i+3],line) end
  elseif mode=="c" then
    records[center]=rec(a[5],a[6],a[7],a[3],a[4],a[8],0)
    local p,why=C.canal(B,center,center,classes[a[2]],{owner="company",editor=a[1]==1})
    result(p,why,a[9],a[10],line)
    if p then
      local r=p.records[center]
      assert(a[11]==1 and r.water_class==classes[a[12]] and r.owner==owners[a[13]],line)
    end
  else
    local lo,hi=B.adjacent(center,(a[2]+2)%4),B.adjacent(center,a[2])
    local cells={center,lo,hi}
    for j,i in ipairs(cells) do
      local k=4+(j-1)*7
      records[i]=rec(a[k+1],a[k+2],a[k+3],a[k+4],a[k+5],a[k+6],a[k+7])
    end
    local p,why=C.lock(B,center,{owner="company"})
    result(p,why,a[3],a[4],line)
    if p then for j,i in ipairs(cells) do
      local r=p.records[i]
      local k=25+(j-1)*5
      assert(r.kind=="lock" and a[k+1]==4 and r.water_class==classes[a[k+2]] and
        r.owner==owners[a[k+3]] and r.part==({"middle","lower","upper"})[a[k+4]+1] and r.dir==a[k+5],line)
    end end
  end
end
assert(n.a==8192 and n.c==29184 and n.l==4500)
print(("PASS: stock C++ %d exact drag selections and %d canal + %d lock query/execute cases"):format(n.a,n.c,n.l))
"""
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"reference.cpp").write_text(cpp)
    (p/"verify.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",p/"reference.cpp","-o",p/"reference"],check=True)
    truth=subprocess.check_output([p/"reference"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],cwd=ROOT,input=truth,check=True)
