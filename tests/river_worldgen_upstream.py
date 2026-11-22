#!/usr/bin/env python3
"""Compare detached stock rivers to compiled OpenTTD 14.1 path functions.

Usage: python3 tests/river_worldgen_upstream.py OPEN_TTD_SRC [lua5.1] [NPF_SRC]
NPF_SRC is optional when the first path includes src/pathfinder/npf.
Compiles paths, widening, terraforming, reflood, and tile loops. Seeded maps
start from the independently verified TerraGenesis stage; shims isolate
the clear/water/void worldgen boundary. No game binary needed.
"""
from hashlib import sha256
from pathlib import Path
from struct import pack
import re
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
npf=Path(sys.argv[3]) if len(sys.argv)>3 else source


def read(path,digest,src=source):
    p=next(d for d in (src/"src"/path,src/path,src/Path(path).name) if d.is_file())
    raw=p.read_bytes()
    assert sha256(raw).hexdigest()==digest,f"{p} is not pinned OpenTTD 14.1."
    return raw.decode()


def extract(src,signature):
    i=re.search(signature,src,re.M).start()
    j=src.index("{",i)
    nesting=1
    while nesting:
        j+=1;nesting+=(src[j]=="{")-(src[j]=="}")
    return src[i:j+1]+"\n"


land=read("landscape.cpp","0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97")
maps=read("map.cpp","386c77cffb0b5c93faed092f33ea4a35aa2987fe6624034788d18d24e9371378")
rnd=read("core/random_func.cpp","6f640b0e7793467e801290d591b6fb67d1d8c8da19c6c187e0f9664871a660c3")
astar=read("pathfinder/npf/aystar.cpp","f05265cb57e23868426b4d4a2e686f45c3de32064de1e5193cd3061a7dbf9e39",npf)
ah=read("pathfinder/npf/aystar.h","ccdc4f35825caed9390c83131fc783ee5c955e86543e8fb1c92100224330edf3")
queue=read("pathfinder/npf/queue.cpp","9ae6ab4ad6d78f3e93251825fc80cb7f189aef77140ad95741e5cd59726fb147",npf)
slope=read("slope_func.h","1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a")
water=read("water_cmd.cpp","f6fc6a51c8fe5640bd46ae32c240dc327487f986af6dc76208ab85b86d736847")
void=read("void_cmd.cpp","8c528065ebd44a77188512ba14fdcc74d3e23baedf0d18e22884cec3a0b353a6",npf)
terra=read("terraform_cmd.cpp","1390a6fffa9ff9f4cec1b2845b3dc1ca465384d1a641a239744c558c51daa012")
clear=read("clear_cmd.cpp","97a79d03eb421cf5815c065b7a7dadbd97b362b650f48bda10fd28e85d0e2b68")
cpp=r'''
#include <algorithm>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <list>
#include <map>
#include <set>
#include <tuple>
#include <unordered_map>
#include <vector>
using uint=unsigned;using byte=uint8_t;using TileIndex=uint32_t;using Trackdir=int;using Slope=int;
enum {SLOPE_FLAT=0,SLOPE_NW=9,SLOPE_SW=3,SLOPE_SE=6,SLOPE_NE=12,INVALID_TRACKDIR=255,
    LT_TEMPERATE=0,LT_TROPIC,TROPICZONE_RAINFOREST,TROPICZONE_DESERT,LG_ORIGINAL,GWP_RIVER};
enum {AYSTAR_FOUND_END_NODE=1,AYSTAR_DONE,AYSTAR_INVALID_NODE=-1,AYSTAR_EMPTY_OPENLIST=-2,
    AYSTAR_LIMIT_REACHED=-3,AYSTAR_STILL_BUSY=0,AYSTAR_NO_PATH=-4};
template<typename T,size_t N> constexpr size_t lengthof(const T(&)[N]){return N;}
template<class T> T* MallocT(size_t n){return static_cast<T*>(malloc(sizeof(T)*n));}
#define GB(x,o,n) (((x)>>(o))&((1u<<(n))-1u))
struct Randomizer {uint32_t state[2];uint32_t Next();void SetSeed(uint32_t);}_random;
uint32_t Random(){return _random.Next();}
uint32_t RandomRange(uint n){return (uint64_t(Random())*n)>>32;}
struct Settings {
    struct {bool freeform_edges=true;int map_height_limit=30,max_bridge_height=12;} construction;
    struct {int landscape=LT_TEMPERATE,land_generator=LG_ORIGINAL;uint river_route_random=5,min_river_length=4,amount_of_rivers=2;} game_creation;
} _settings_game;
struct Map {
    static inline uint sx=64,sy=64;
    static uint SizeX(){return sx;}
    static uint SizeY(){return sy;}
    static uint MaxX(){return sx-1;}
    static uint MaxY(){return sy-1;}
    static uint Size(){return sx*sy;}
    static uint LogX(){return std::countr_zero(sx);}
    static uint LogY(){return std::countr_zero(sy);}
    static uint ScaleBySize(uint n){return (n*Size()+65535)/65536;}
    static uint WrapToMap(uint i){return i&(Size()-1);}
};
TileIndex RandomTile(){return Map::WrapToMap(Random());}
TileIndex TileXY(uint x,uint z){return x+z*Map::sx;}
uint TileX(TileIndex t){return t%Map::sx;}
uint TileY(TileIndex t){return t/Map::sx;}
uint Delta(uint a,uint b){return a>b?a-b:b-a;}
const TileIndex INVALID_TILE=-1;
enum DiagDirection {DIAGDIR_BEGIN=0,DIAGDIR_NE=0,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW,DIAGDIR_END,INVALID_DIAGDIR=255};
enum DiagDirDiff {DIAGDIRDIFF_BEGIN=0,DIAGDIRDIFF_SAME=0,DIAGDIRDIFF_90RIGHT,DIAGDIRDIFF_REVERSE,DIAGDIRDIFF_90LEFT,DIAGDIRDIFF_END};
DiagDirDiff operator++(DiagDirDiff &d,int){auto p=d;d=DiagDirDiff(d+1);return p;}
DiagDirection ChangeDiagDir(DiagDirection d,DiagDirDiff diff){return DiagDirection((int(d)+int(diff))%4);}
DiagDirection ReverseDiagDir(DiagDirection d){return ChangeDiagDir(d,DIAGDIRDIFF_REVERSE);}
DiagDirection operator++(DiagDirection &d,int){auto p=d;d=DiagDirection(d+1);return p;}
enum Direction {DIR_BEGIN=0,DIR_N=0,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW,DIR_END};
Direction operator++(Direction &d,int){auto p=d;d=Direction(d+1);return p;}
Direction ReverseDir(Direction d){return Direction((d+4)%8);}
struct TileIndexDiffC{int x,y;};
'''
for name in ("Next","SetSeed"):
    cpp+=extract(rnd,rf"^\w+ Randomizer::{name}\(")
for name in ("_tileoffs_by_diagdir","_tileoffs_by_dir"):
    cpp+=extract(maps,rf"^extern const TileIndexDiffC {name}")+";\n"
for name in ("TileAddWrap","DistanceManhattan"):
    cpp+=extract(maps,rf"^\w+ {name}\(")
cpp+=r'''
TileIndex TileAddByDir(TileIndex t,Direction d){
    return Map::WrapToMap(t+_tileoffs_by_dir[d].x+_tileoffs_by_dir[d].y*Map::sx);
}
int TileOffsByDiagDir(DiagDirection d){return _tileoffs_by_diagdir[d].x+_tileoffs_by_diagdir[d].y*int(Map::sx);}
TileIndex TileAddByDiagDir(TileIndex t,DiagDirection d){return t+TileOffsByDiagDir(d);}
int TileDiffXY(int x,int y){return x+y*int(Map::sx);}
int ToTileIndexDiff(TileIndexDiffC t){return TileDiffXY(t.x,t.y);}
using TestTileOnSearchProc=bool(*)(TileIndex,void*);
bool CircularTileSearch(TileIndex*,uint,uint,uint,TestTileOnSearchProc,void*);
'''
for signature in (r"^bool CircularTileSearch\(TileIndex \*tile, uint size,",r"^bool CircularTileSearch\(TileIndex \*tile, uint radius,"):
    cpp+=extract(maps,signature)
cpp+=extract(slope,r"^inline bool IsInclinedSlope\(")
cpp+=r'''
int mode=0;
std::vector<int> packed_height,packed_word,packed_bits;
bool staged=false;
int terrain_y(int x,int z){
    if(staged)return packed_height.at(TileXY(x,z));
    if(mode==0)return 2;
    if(mode==1)return std::max(0,std::min(7,(z-7)/4));
    if(mode==2)return std::max(0,std::min(8,(x-6)/5));
    if(mode==3) return std::max(0,8-(std::abs(x-30)+std::abs(z-32))/5);
    if(mode==4){
        if(x>=29&&x<=30&&z>=31&&z<=32)return 4;
        if(z>=29&&z<=34&&x>=27&&x<=32)return 5;
        return 4;
    }
    return std::max(0,3-(std::abs(x-31)+std::abs(z-28))/13);
}
int TileHeight(TileIndex t){return terrain_y(TileX(t),TileY(t));}
bool IsValidTile(TileIndex t){
    if(t>=Map::Size())return false;
    auto x=TileX(t),z=TileY(t);
    return x<Map::MaxX()&&z<Map::MaxY()&&(!_settings_game.construction.freeform_edges||(x!=0&&z!=0));
}
Slope GetTileSlope(TileIndex t,int *base=nullptr){
    auto x=TileX(t),z=TileY(t),u=std::min(Map::MaxX(),x+1),v=std::min(Map::MaxY(),z+1);
    int N=terrain_y(x,z),W=terrain_y(u,z),E=terrain_y(x,v),S=terrain_y(u,v),q=std::min({N,W,E,S}),hi=std::max({N,W,E,S});
    if(base)*base=q;
    return (N>q?8:0)+(W>q?1:0)+(E>q?4:0)+(S>q?2:0)+(hi-q==2?16:0);
}
int GetTileZ(TileIndex t){int b;GetTileSlope(t,&b);return b;}
int GetTileMaxZ(TileIndex t){
    auto x=TileX(t),z=TileY(t),u=std::min(Map::MaxX(),x+1),v=std::min(Map::MaxY(),z+1);
    return std::max({terrain_y(x,z),terrain_y(u,z),terrain_y(x,v),terrain_y(u,v)});
}
bool IsTileFlat(TileIndex t,int *b=nullptr){return GetTileSlope(t,b)==0;}
std::vector<bool> wet;
std::vector<std::pair<TileIndex,uint>> writes;
bool IsWaterTile(TileIndex t){
    if(staged)return t<Map::Size()&&(packed_word[t]==22||packed_word[t]==54);
    return IsValidTile(t)&&(wet[t]||(GetTileZ(t)==0&&IsTileFlat(t)));
}
int GetTropicZone(TileIndex){return 0;}
void MakeRiverAndModifyDesertZoneAround(TileIndex t){
    uint bits=Random()%256;
    writes.push_back({t,bits});wet[t]=true;
    if(staged){packed_word.at(t)=54;packed_bits.at(t)=bits;}
}
uint TileHash(uint x,uint z){return ((x>>4)^(x>>6)^(z>>4))-(z>>6);}
struct BinaryHeapNode{void* item;int priority;};
struct BinaryHeap{
    static const int BINARY_HEAP_BLOCKSIZE_BITS=10,BINARY_HEAP_BLOCKSIZE=1024,BINARY_HEAP_BLOCKSIZE_MASK=1023;
    uint size=0,max_size=102400,blocks=0;
    std::vector<BinaryHeapNode*> elements=std::vector<BinaryHeapNode*>(110,nullptr);
    BinaryHeapNode& GetElement(uint i){return elements[(i-1)>>10][(i-1)&1023];}
    ~BinaryHeap(){for(auto s:elements)free(s);}
    bool Push(void*,int);
    bool Delete(void*,int);
    void* Pop();
};
'''
for name,typ in (("Push","bool"),("Delete","bool"),("Pop",r"void \*")):
    cpp+=extract(queue,rf"^{typ} ?BinaryHeap::{name}\(")
cpp+=r'''
struct AyStarNode{TileIndex tile;Trackdir direction;uint user_data[2];};
struct PathNode{AyStarNode node;PathNode* parent;};
struct OpenListNode{int g;PathNode path;};
bool CheckIgnoreFirstTile(const PathNode*){return false;} // distinct endpoints only
struct Hash{
    std::unordered_map<TileIndex,void*> hash;
    void Set(TileIndex p,Trackdir,void *v){hash[p]=v;}
    void* Get(TileIndex p,Trackdir){auto it=hash.find(p);return it!=hash.end()?it->second:nullptr;}
    void DeleteValue(TileIndex p,Trackdir){hash.erase(p);}
    uint GetSize(){return hash.size();}
    void Clear(){for(auto p:hash)free(p.second);hash.clear();}
};
using Hash_HashProc=uint(*)(TileIndex,Trackdir);
'''
cpp+=re.search(r"^static const int AYSTAR_DEF_MAX_SEARCH_NODES[^\n]+",ah,re.M)[0]+"\n"
cpp+=r'''
struct AyStar {
    int32_t (*CalculateG)(AyStar*,AyStarNode*,OpenListNode*);
    int32_t (*CalculateH)(AyStar*,AyStarNode*,OpenListNode*);
    void (*GetNeighbours)(AyStar*,OpenListNode*);
    int32_t (*EndNodeCheck)(const AyStar*,const OpenListNode*);
    void (*FoundEndNode)(AyStar*,OpenListNode*);
    void *user_target=nullptr,*user_data=nullptr;
    uint num_neighbours=0,max_path_cost=0,max_search_nodes=AYSTAR_DEF_MAX_SEARCH_NODES;
    AyStarNode neighbours[12]{};
    Hash openlist_hash,closedlist_hash;BinaryHeap openlist_queue;
    PathNode *ClosedListIsInList(const AyStarNode*);
    void ClosedListAdd(const PathNode*);
    OpenListNode *OpenListIsInList(const AyStarNode*);
    OpenListNode *OpenListPop();
    void OpenListAdd(PathNode*,const AyStarNode*,int,int);
    void CheckTile(AyStarNode*,OpenListNode*);
    int Loop();
    void AddStartNode(AyStarNode*,uint);
    void Init(Hash_HashProc,uint){}
    void Free(){openlist_hash.Clear();closedlist_hash.Clear();}
    void Main(){while(Loop()==AYSTAR_STILL_BUSY) {}}
};
'''
for name in ("ClosedListIsInList","ClosedListAdd","OpenListIsInList","OpenListPop","OpenListAdd","CheckTile","Loop","AddStartNode"):
    cpp+=extract(astar,rf"^\w+ [*]?AyStar::{name}\(")
cpp+=r'''
uint progress=0,floods=0,ticks=0;
void SetGeneratingWorldProgress(int,uint n){progress=n;}
void IncreaseGeneratingWorldProgress(int){}
enum {MP_CLEAR=0,MP_RAILWAY=1,MP_TREES=4,MP_STATION=5,MP_WATER=6,MP_VOID=7,MP_INDUSTRY=8,MP_OBJECT=10};
enum {WATER_CLASS_SEA=0,WATER_CLASS_RIVER=2,TREE_GROUND_SHORE=1,RAIL_GROUND_WATER=8,
      SLOPE_W=1,SLOPE_S=2,SLOPE_E=4,SLOPE_N=8,SLOPE_ELEVATED=15,SLOPE_STEEP=16,SLOPE_HALFTILE=32,SLOPE_HALFTILE_MASK=0xe0};
enum FloodingBehaviour {FLOOD_NONE,FLOOD_DRYUP,FLOOD_ACTIVE,FLOOD_PASSIVE};
int GetTileType(TileIndex t){return packed_word.at(t)%16;}
bool IsTileType(TileIndex t,int k){return GetTileType(t)==k;}
bool IsCoast(TileIndex t){return packed_word.at(t)==38;}
int GetWaterClass(TileIndex t){return packed_word.at(t)==22?WATER_CLASS_SEA:WATER_CLASS_RIVER;}
int GetRailGroundType(TileIndex){abort();}
int GetTreeGround(TileIndex){abort();}
Slope GetFoundationSlope(TileIndex t,int*z=nullptr){return GetTileSlope(t,z);}
void AmbientSoundEffect(TileIndex){}
bool HasBit(uint m,uint i){return (m>>i)&1u;}
std::vector<uint> SetBitIterator(uint m){
    std::vector<uint> d;for(uint i=0;i<8;i++)if(HasBit(m,i))d.push_back(i);return d;
}
int TileOffsByDir(Direction d){return _tileoffs_by_dir[d].x+_tileoffs_by_dir[d].y*int(Map::sx);}
void MakeSea(TileIndex t){packed_word.at(t)=22;}
void MakeShore(TileIndex t){packed_word.at(t)=38;}
void DoFloodTile(TileIndex t){
    assert(IsTileType(t,MP_CLEAR));
    if(IsTileFlat(t))MakeSea(t);else MakeShore(t);
}
void DoDryUp(TileIndex t){assert(IsCoast(t));packed_word.at(t)=0;}
TileIndex _cur_tileloop_tile=1;
constexpr int MAX_MAP_SIZE_BITS=12,MIN_MAP_SIZE_BITS=6,PFE_GL_LANDSCAPE=0;
struct PerformanceAccumulator {PerformanceAccumulator(int){}};
struct TimerGameTick {static constexpr int counter=0;};
'''
for sig in (r"^inline bool IsSlopeWithOneCornerRaised",r"^static constexpr inline bool IsSteepSlope",r"^static constexpr inline bool IsHalftileSlope",
            r"^inline Slope ComplementSlope",r"^inline bool IsSlopeWithThreeCornersRaised",r"^inline DiagDirection GetInclinedSlopeDirection"):
    cpp+=extract(slope,sig)
cpp+=extract(water,r"^static const uint8_t _flood_from_dirs")+ ";\n"
for sig in (r"^FloodingBehaviour GetFloodingBehaviour",r"^void TileLoop_Water",
            r"^void ConvertGroundTilesIntoWaterTiles"):
    code=extract(water,sig)
    if "Convert" in sig:
        code=code.replace("ConvertGroundTilesIntoWaterTiles", "SourceReflood")
    cpp+=code
cpp+=extract(void,r"^static void TileLoop_Void")
cpp+=r'''
using DoCommandFlag=uint;
using Money=int;
using Price=int;
enum {DC_EXEC=0x001,DC_AUTO=0x002,DC_NO_WATER=0x008,DC_BANKRUPT=0x040,DC_NO_MODIFY_TOWN_RATING=0x400,DC_FORCE_CLEAR_TILE=0x800};
enum {EXPENSES_CONSTRUCTION=0,STR_ERROR_ALREADY_AT_SEA_LEVEL=100,STR_ERROR_TOO_HIGH,STR_ERROR_TOO_CLOSE_TO_EDGE_OF_MAP,
  STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST,STR_ERROR_BRIDGE_TOO_HIGH_AFTER_LOWER_LAND,STR_ERROR_EXCAVATION_WOULD_DAMAGE,
  STR_ERROR_TERRAFORM_LIMIT_REACHED,STR_ERROR_MUST_DEMOLISH_CANAL_FIRST,STR_ERROR_CAN_T_BUILD_ON_WATER,STR_ERROR_CLEARING_LIMIT_REACHED};
enum {PR_CLEAR_GRASS=0,PR_CLEAR_ROUGH,PR_CLEAR_ROCKS,PR_CLEAR_FIELDS,PR_TERRAFORM,PR_CLEAR_CANAL,PR_CLEAR_WATER};
int _price[]={10,40,40,40,30,100,100};
struct CommandCost {
    bool fail=false;
    explicit CommandCost(int code=0,int money=0):fail(code!=0){}
    bool Failed() const{return fail;}
    bool Succeeded() const{return !fail;}
    void AddCost(CommandCost other){fail|=other.fail;}
    void AddCost(Money){}
};
constexpr int CMD_LANDSCAPE_CLEAR=1,CMD_TERRAFORM_LAND=2;
const CommandCost CMD_ERROR{1};
#define return_cmd_error(X) return CommandCost(X)
enum {WATER_TILE_CLEAR=0,WATER_TILE_COAST,OWNER_WATER=0,OWNER_NONE=1,CLEAR_GRASS=0,GM_EDITOR=1,WATER_CLASS_CANAL=1};
uint _current_company=99,_game_mode=0;
bool _generating_world=true;
struct Company{
    uint terraform_limit=0,clear_limit=0,index=0;
    struct {uint water=0;} infrastructure;
    static Company* GetIfValid(uint){return nullptr;}
    static bool IsValidID(uint){return false;}
    static Company* Get(uint){abort();}
};
using Owner=int;
struct ClearedObjectArea{TileIndex first_tile;};
const ClearedObjectArea *FindClearedObject(TileIndex){return nullptr;}
bool IsBridgeAbove(TileIndex){return false;}
TileIndex GetSouthernBridgeEnd(TileIndex){abort();}
int GetBridgeHeight(TileIndex){abort();}
bool IsTunnelInWay(TileIndex,int){return false;}
template<class T> struct Backup {
    T&r,old;
    Backup(T&r_,int):r(r_),old(r_){}
    void Change(T a){r=a;}
    void Restore(){r=old;}
};
#define FILE_LINE 0
int GetWaterTileType(TileIndex t){return IsCoast(t)?WATER_TILE_COAST:WATER_TILE_CLEAR;}
bool IsRiver(TileIndex t){return packed_word[t]==54;}
bool IsCanal(TileIndex){return false;}
bool HasTileWaterClass(TileIndex t){return IsTileType(t,MP_WATER);}
bool IsTileOnWater(TileIndex t){return IsTileType(t,MP_WATER);}
bool IsCoastTile(TileIndex t){return IsCoast(t);}
template<class T,class A,class B> bool IsInsideMM(T x,A a,B b){return x>=a&&x<b;}
CommandCost EnsureNoVehicleOnGround(TileIndex){return CommandCost();}
CommandCost CheckTileOwnership(TileIndex){abort();}
Owner GetTileOwner(TileIndex){return OWNER_WATER;}
void DirtyCompanyInfrastructureWindows(uint){abort();}
void MarkCanalsAndRiversAroundDirty(TileIndex){}
void MarkTileDirtyByTile(TileIndex,int=0,int=0){}
bool IsClearGround(TileIndex,int){return true;}
int GetClearGround(TileIndex){return CLEAR_GRASS;}
int GetClearDensity(TileIndex){return 3;}
uint terra_rw=0,tera_erased=0,terraform_trace_scope=0;
std::vector<std::tuple<TileIndex,int,bool,bool,uint,uint>> cmdtrace;
void DoClearSquare(TileIndex t){
    if(IsTileType(t,MP_WATER))tera_erased++;
    packed_word[t]=packed_bits[t]=0;
}
void SetTileHeight(TileIndex t,uint h){assert(packed_height[t]!=h);terra_rw++;packed_height[t]=h;}
CommandCost CmdLandscapeClear(DoCommandFlag,TileIndex);
std::tuple<CommandCost,Money,TileIndex> CmdTerraformLand(DoCommandFlag,TileIndex,Slope,bool);
template<int N> struct Command {
    static CommandCost Do(DoCommandFlag flags,TileIndex t){
        static_assert(N==CMD_LANDSCAPE_CLEAR);
        assert(terraform_trace_scope>0);
        assert((flags & (DC_AUTO|DC_FORCE_CLEAR_TILE))==(DC_AUTO|DC_FORCE_CLEAR_TILE));
        assert((flags & ~(DC_EXEC|DC_AUTO|DC_FORCE_CLEAR_TILE|DC_NO_MODIFY_TOWN_RATING))==0);
        const auto base_flags=DC_AUTO|DC_FORCE_CLEAR_TILE;
        if(terraform_trace_scope==1)assert(flags==base_flags || flags==(base_flags|DC_NO_MODIFY_TOWN_RATING));
        else assert(flags==(base_flags|DC_EXEC) || flags==(base_flags|DC_NO_MODIFY_TOWN_RATING));
        return CmdLandscapeClear(flags,t);
    }
    static std::tuple<CommandCost,Money,TileIndex> Do(DoCommandFlag flags,TileIndex t,Slope s,bool up){
        static_assert(N==CMD_TERRAFORM_LAND);
        assert(flags==(DC_EXEC|DC_AUTO)); // the stock RiverMakeWider callsite
        terraform_trace_scope=1;
        terra_rw=tera_erased=0;
        auto result=CmdTerraformLand(flags & ~DC_EXEC,t,s,up); // top-level test call
        assert(terra_rw==0&&tera_erased==0);
        if(std::get<0>(result).Succeeded()){
            terraform_trace_scope=2;
            result=CmdTerraformLand(flags,t,s,up);
        }
        cmdtrace.emplace_back(t,s,up,std::get<0>(result).Succeeded(),terra_rw,tera_erased);
        terraform_trace_scope=0;
        return result;
    }
};
void TileLoop_ClearStable(TileIndex){}
static CommandCost ClearTile_Clear(TileIndex,DoCommandFlag);
static CommandCost ClearTile_Water(TileIndex,DoCommandFlag);
static CommandCost TerraformTile_Clear(TileIndex,DoCommandFlag,int,Slope);
static CommandCost TerraformTile_Water(TileIndex,DoCommandFlag,int,Slope);
struct TileProc {
    void (*tile_loop_proc)(TileIndex);
    CommandCost (*clear_tile_proc)(TileIndex,DoCommandFlag);
    CommandCost (*terraform_tile_proc)(TileIndex,DoCommandFlag,int,Slope);
};
TileProc clear_proc{TileLoop_ClearStable,ClearTile_Clear,TerraformTile_Clear},
    void_proc{TileLoop_Void,nullptr,nullptr}, water_proc{TileLoop_Water,ClearTile_Water,TerraformTile_Water};
TileProc* _tile_type_procs[]={&clear_proc,nullptr,nullptr,nullptr,nullptr,nullptr,&water_proc,&void_proc};
'''
cpp+=extract(land,r"^CommandCost CmdLandscapeClear")
cpp+=extract(water,r"^static CommandCost ClearTile_Water").split("case WATER_TILE_LOCK:")[0]+"default: abort();} }\n"
cpp+=extract(water,r"^static CommandCost TerraformTile_Water")
cpp+=extract(clear,r"^static CommandCost ClearTile_Clear")
cpp+=extract(clear,r"^static CommandCost TerraformTile_Clear")
cpp+="using TileIndexSet=std::set<TileIndex>;using TileIndexToHeightMap=std::map<TileIndex,int>;\n"
cpp+=extract(terra,r"^struct TerraformerState")+";\n"
for sig in (r"^static int TerraformGetHeightOfTile",r"^static void TerraformSetHeightOfTile",
            r"^static void TerraformAddDirtyTile\(",r"^static void TerraformAddDirtyTileAround",
            r"^static std::tuple<CommandCost, TileIndex> TerraformTileHeight",
            r"^std::tuple<CommandCost, Money, TileIndex> CmdTerraformLand"):
    cpp+=extract(terra,sig).replace("endof(_terraform_tilepos)", "std::end(_terraform_tilepos)")
cpp+=extract(land,r"^static bool RiverMakeWider")
cpp+=extract(land,r"^void RunTileLoop").replace("RunTileLoop", "SourceTileLoop").replace(".base()", "")
cpp+=r'''
void ConvertGroundTilesIntoWaterTiles(){floods++;if(staged)SourceReflood();}
void RunTileLoop(){ticks++;if(staged)SourceTileLoop();}
'''
for sig in (r"^static bool FindSpring",r"^static bool MakeLake",r"^static bool FlowsDown",
            r"^struct River_UserData",r"^static int32_t River_EndNodeCheck",r"^static int32_t River_CalculateG",
            r"^static int32_t River_CalculateH",r"^static void River_GetNeighbours",
            r"^static void River_FoundEndNode",r"^static uint River_Hash",r"^static void BuildRiver",
            r"^static std::tuple<bool, bool> FlowRiver",r"^static void CreateRivers"):
    if "River_Hash" in sig:cpp+="static const int RIVER_HASH_SIZE=8;\n"
    cpp+=extract(land,sig)
    if sig==r"^struct River_UserData":cpp+=";\n"
cpp+=r'''
std::vector<TileIndex> trace;
void Trace(AyStar*,OpenListNode *p){
    for(auto path=&p->path;path;path=path->parent)trace.push_back(path->node.tile);
}
int main(){
    char cmd;uint seed,x,z,u,v,p;
    while(std::cin>>cmd>>mode>>Map::sx>>Map::sy>>seed>>x>>z>>u>>v>>p){
        _random.SetSeed(seed);wet.assign(Map::Size(),false);writes.clear();trace.clear();
        ticks=floods=progress=0;
        staged=cmd=='T'||cmd=='W'||cmd=='D';
        cmdtrace.clear();
        _settings_game.game_creation.land_generator=cmd=='W'?1:LG_ORIGINAL;
        _cur_tileloop_tile=1;
        _settings_game.construction.freeform_edges=true;
        if(staged){
            _settings_game.construction.freeform_edges=u;
            std::cin>>_random.state[0]>>_random.state[1]>>_settings_game.construction.map_height_limit;
            packed_height.resize(Map::Size());packed_word.resize(Map::Size());packed_bits.assign(Map::Size(),0);
            for(auto &i:packed_height)std::cin>>i;
            for(auto &i:packed_word)std::cin>>i;
        }
        _settings_game.game_creation.river_route_random=p;
        auto begin=TileXY(x,z),end=TileXY(u,v);
        std::cout<<cmd;
        if(cmd=='S')std::cout<<' '<<FindSpring(begin,nullptr);
        else if(cmd=='P'){
            AyStar finder={};
            finder.CalculateG=River_CalculateG;finder.CalculateH=River_CalculateH;
            finder.GetNeighbours=River_GetNeighbours;finder.EndNodeCheck=River_EndNodeCheck;
            finder.FoundEndNode=Trace;finder.user_target=&end;
            finder.Init(River_Hash,256);
            AyStarNode start{};start.tile=begin;start.direction=INVALID_TRACKDIR;
            finder.AddStartNode(&start,0);finder.Main();finder.Free();
            for(auto i:trace)std::cout<<' '<<i;
        } else if(cmd=='F'){
            auto [success,main]=FlowRiver(begin,end,p);
            std::cout<<' '<<success<<' '<<main;
        } else if(cmd=='D'){
            uint n,t,s,up;
            std::cin>>n;
            while(n--){
                std::cin>>t>>s>>up;
                Command<CMD_TERRAFORM_LAND>::Do(DC_EXEC|DC_AUTO,t,s,up);
            }
            std::cout<<" 0 0 0";
        } else if(cmd=='G'||staged){
            _settings_game.game_creation.amount_of_rivers=x;
            _settings_game.game_creation.min_river_length=z;
            CreateRivers();std::cout<<' '<<progress<<' '<<floods<<' '<<ticks;
        }
        if(staged){
            std::cout<<" / "<<_cur_tileloop_tile;
            for(uint i=0;i<Map::Size();i++)std::cout<<' '<<packed_word[i]+256*packed_bits[i];
            if(cmd!='T'){
                std::cout<<" /";
                for(int h:packed_height)std::cout<<' '<<h;
                std::cout<<" / ";
                for(auto [t,s,up,ok,n,e]:cmdtrace)std::cout<<t<<','<<s<<','<<up<<','<<ok<<','<<n<<','<<e<<';';
                if(cmdtrace.empty())std::cout<<'-';
            }
        } else for(auto [i,v]:writes)std::cout<<" | "<<i<<' '<<v;
        std::cout<<" : "<<_random.state[0]<<' '<<_random.state[1]<<'\n';
    }
}'''
runner=r'''
local root="mods/bayline/openttd/"
local function m(n)return dofile(root..n..".lua")end
local Slope=m("slope");local R=m("river_worldgen")(Slope);local TG=m("terragenesis")(Slope)
local abs,floor,min,max=math.abs,math.floor,math.min,math.max
for input in io.lines() do
  local cmd=input:sub(1,1);local a={}
  for n in input:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local mode,w,h,seed,x,z,u,v,p=unpack(a)
  local function terrain(x,z)
    if mode==0 then return 2 end
    if mode==1 then return max(0,min(7,math.ceil((z-7)/4-.75))) end
    if mode==2 then return max(0,min(8,math.ceil((x-6)/5-.8))) end
    if mode==3 then return max(0,8-floor((abs(x-30)+abs(z-32))/5)) end
    if mode==4 then
      if x>=29 and x<=30 and z>=31 and z<=32 then return 4 end
      if z>=29 and z<=34 and x>=27 and x<=32 then return 5 end
      return 4
    end
    return max(0,3-floor((abs(x-31)+abs(z-28))/13))
  end
  local state={seed,seed};local function random()return TG.next_random(state)end
  local wet,writes={},{}
  local B={width=w,height=h,freeform=true}
  function B.tile(i)
    local x,z=i%w,floor(i/w)
    local u,v=min(w-1,x+1),min(h-1,z+1)
    local a,b,c,d=terrain(x,z),terrain(u,z),terrain(x,v),terrain(u,v)
    local shape,minz=Slope.classify(a,b,c,d)
    local water=wet[i] or minz==0 and shape==0
    local kind=(x==0 or z==0 or x>=w-1 or z>=h-1) and "void" or water and "water" or "clear"
    return {corner_height=a,slope=shape,base=minz,top=max(a,b,c,d),kind=kind,class=wet[i] and "river" or "sea"}
  end
  function B.make_river(i,bits)wet[i]=true;writes[#writes+1]={i,bits} end
  local function make(i)B.make_river(i,random()%256)end
  local prog,floods,ticks=0,0,0
  function B.reflood() floods=floods+1 end
  function B.run_tile_loop() ticks=ticks+1 end
  local begin,finish=x+z*w,u+v*w
  local out=cmd
  if cmd=="S" then
    out=out.." "..(R.find_spring(B,begin) and 1 or 0)
  elseif cmd=="P" then
    local path=R.route(B,begin,finish,random,p)
    for _,i in ipairs(path or {}) do out=out.." "..i end
  elseif cmd=="F" then
    local yes,main=R.flow(B,begin,finish,p,random,make,{river_route_random=p,original=true})
    out=out..(" %d %d"):format(yes and 1 or 0,main and 1 or 0)
  elseif cmd=="G" then
    local opts={amount_of_rivers=x,min_river_length=z,river_route_random=p,original=true,
      progress=function(_,n)prog=n end}
    R.create(B,random,opts);out=out..(" %d %d %d"):format(prog,floods,ticks)
  end
  for _,q in ipairs(writes) do out=out..(" | %d %d"):format(q[1],q[2]) end
  print(out..(" : %d %d"):format(state[1],state[2]))
end
'''
cases=[]
for i in range(40):
    mode=i%6
    x,z=21+i%19,23+i%18
    cases.append(f"P {mode} 64 64 {1751+i*373} {x} {z} {32+i%19} {12+i%17} {i%12+1}")
for i in range(14):
    for mode in (0,1,2,3,4,5):
        x,z=19+i,25+i
        cases.append(f"S {mode} 64 64 {i*37+1} {x} {z} 0 0 1")
for i in range(16):
    mode=i%6
    cases.append(f"F {mode} 64 64 {1751+i*693} {37+i%8} {44+i%7} {22+i%7} {28+i%7} {i%9+2}")
for mode in (0,3,4,5):
    for amount in (0,1,3):
        cases.append(f"G {mode} 64 64 {1751+12*mode} {amount} 3 0 0 5")
# Equal-score streets, larger-than-10k route and very small basin limits.
cases += ["P 0 128 128 1751 1 1 126 126 1","P 1 128 128 1751 2 2 126 125 255",
          "F 0 64 64 2484 59 59 5 8 3","F 0 64 64 79318 12 12 55 55 2"]
stdin="\n".join(cases)+"\n"
with tempfile.TemporaryDirectory(prefix="river-worldgen-source-") as folder:
    d=Path(folder)
    (d/"test.cpp").write_text(cpp)
    (d/"test.lua").write_text(runner)
    subprocess.run(["g++","-std=c++20","-O2",str(d/"test.cpp"),"-o",str(d/"test")],check=True)
    def run(args):
        return subprocess.run(args,input=stdin,text=True,stdout=subprocess.PIPE,check=True,cwd=root).stdout.splitlines()
    actual,expected=run([lua,str(d/"test.lua")]),run([str(d/"test")])
    assert len(actual)==len(expected)==len(cases)
    for case,a,b in zip(cases,actual,expected):
        assert a==b,(case,a[:250],b[:250],len(a),len(b))
    cases_seeded=[
        (64,64,1751,2,16,1,1,5), (64,64,1751,3,2,1,1,5),
        (128,128,1751,3,4,1,1,5), (256,256,1751,3,16,1,1,5),
        (128,256,812362,2,6,1,2,12), (128,128,29,0,4,0,1,9),
        (64,64,101,1,16,1,99,5), (128,64,73,1,6,0,1,5),
    ]
    cases_seeded=[(*c,0,0) for c in cases_seeded] + [
        (64,64,1751,3,2,1,1,5,1,0), (128,128,1751,3,4,1,1,5,1,0),
        (128,128,1751,1,16,1,3,5,1,0),  # exact detached river-stream/native worker fixture
        (256,256,1751,3,16,1,1,5,1,0), (128,256,812362,2,6,1,2,12,1,0),
        (128,64,73,1,6,0,1,5,1,0), (128,128,199,3,5,1,3,1,1,15),
        (64,64,101,0,16,0,98,5,2,15),
    ]
    (d/"stage.lua").write_text(r'''
local root="mods/bayline/openttd/"
local function m(n)return dofile(root..n..".lua")end
local Slope=m("slope");local R=m("river_worldgen")(Slope);local TG=m("terragenesis")(Slope)
for input in io.lines() do
  local a={}
  for n in input:gmatch("%d+") do a[#a+1]=tonumber(n) end
  local w,h,seed,amount,minlen,freeform,terrain,spread,wide,cap=unpack(a)
  local base=TG.generate{width=w,depth=h,seed=seed,freeform_edges=freeform==1,terrain_type=terrain>=98 and 1 or terrain,
    quantity_sea_lakes=0,rng_state=TG.startup_rng(seed),map_height_limit=cap}
  local flag=wide==2 and "D" or wide==1 and "W" or "T"
  local direct={
    {1+64,8,0}, {12+12*64,8,0}, {40+40*64,8,1}, {20+20*64,8,1}, {21+21*64,0,1},
    {20+20*64,8,0},
  }
  if terrain==98 then
    function base.corner(x,z)
      if (x==13 and z==13) or (x==12 and z==12) then return 0 end
      local ramp=math.max(0,14-math.abs(x-41)-math.abs(z-41))
      return x==21 and z==21 and 2 or 1+ramp
    end
    function base.tile(x,z)
      if x==w or z==h then return 7 end
      if x==21 and z==21 then return 54 end
      if x==20 and z==21 then return 22 end
      if x==21 and z==20 then return 38 end
      return 0
    end
  end
  if terrain==99 then
    -- Stable corner fixture: a broad basin rains into sea, while one
    -- isolated lowered corner has no active water and dries after reflood.
    function base.corner(x,z)
      if x==12 and z==12 or x>=32 and x<=39 and z>=32 and z<=39 then return 0 end
      return 1
    end
    function base.tile(x,z)
      if x==1 or z==1 or x==w or z==h then return 7 end
      if (x==11 or x==12) and (z==11 or z==12) then return 38 end
      return 0
    end
  end
  if arg[1]=="original-input" then
    local active=cap==0 and math.max(30,math.min(255,15+base.estimated_max_height)) or cap
    local out={flag,0,w,h,seed,amount,minlen,freeform,terrain,spread,base.rng_after[1],base.rng_after[2],active}
    for z=1,h do for x=1,w do out[#out+1]=base.corner(x,z) end end
    for z=1,h do for x=1,w do out[#out+1]=base.tile(x,z) end end
    if wide==2 then
      out[#out+1]=#direct
      for _,a in ipairs(direct) do for _,v in ipairs(a) do out[#out+1]=v end end
    end
    print(table.concat(out," "))
  elseif wide==2 then
    local changes, words, trace={},{},{}
    local B={width=w,height=h,freeform=false}
    function B.corner(x,z)return changes[x+z*w] or base.corner(x+1,z+1) end
    function B.tile(i)
      local word=words[i] or base.tile(i%w+1,math.floor(i/w)+1)
      return {kind=word==7 and "void" or word%16==6 and "water" or "clear",
        class=word==54 and "river" or word==22 and "sea" or word==38 and "coast" or nil}
    end
    local run=R.terraform_boundary(B,{word=function(i,v)words[i]=v end,
      corner=function(x,z,v)changes[x+z*w]=v end},m("terrain"),cap,function(i,mask,up,ok,n,e)
      trace[#trace+1]=table.concat({i,mask,up and 1 or 0,ok and 1 or 0,n,e},",")..";"
    end)
    for _,cmd in ipairs(direct) do run(cmd[1],cmd[2],cmd[3]==1) end
    local cells={flag,0,0,0,"/",1}
    for i=0,w*h-1 do cells[#cells+1]=words[i] or base.tile(i%w+1,math.floor(i/w)+1) end
    cells[#cells+1]="/"
    for i=0,w*h-1 do cells[#cells+1]=B.corner(i%w,math.floor(i/w)) end
    cells[#cells+1]="/"
    cells[#cells+1]=table.concat(trace)
    cells[#cells+1]=":"
    cells[#cells+1]=base.rng_after[1]
    cells[#cells+1]=base.rng_after[2]
    print(table.concat(cells," "))
  else
    local progress, trace=0,{}
    local out,s=R.generate(base,TG.next_random,{original=wide==0,terrain=m("terrain"),map_height_limit=cap,
      amount_of_rivers=amount,min_river_length=minlen,river_route_random=spread,
      terraform_trace=function(i,mask,up,ok,n,e)
        trace[#trace+1]=table.concat({i,mask,up and 1 or 0,ok and 1 or 0,n,e},",")..";"
      end,
      progress=function(_,n)progress=n end})
    local cells={flag,progress,amount>0 and 1 or 0,amount>0 and 256 or 0,"/",out.river_tileloop_cursor or 1}
    for z=1,h do for x=1,w do
      if wide==0 then assert(out.corner(x,z)==base.corner(x,z)) end
      cells[#cells+1]=out.tile(x,z)+256*(out.river_bits and out.river_bits(x,z) or 0)
    end end
    if wide==1 then
      cells[#cells+1]="/"
      for z=1,h do for x=1,w do cells[#cells+1]=out.corner(x,z) end end
      cells[#cells+1]="/"
      cells[#cells+1]=#trace>0 and table.concat(trace) or "-"
      assert(s.terraform_commands==#trace)
    end
    cells[#cells+1]=":"
    cells[#cells+1]=out.rng_after[1]
    cells[#cells+1]=out.rng_after[2]
    print(table.concat(cells," "))
  end
end
''')
    raw="".join(" ".join(map(str,c))+"\n" for c in cases_seeded)
    def seeded_run(args,data):
        return subprocess.run(args,input=data,text=True,stdout=subprocess.PIPE,check=True,cwd=root).stdout
    supply=seeded_run([lua,str(d/"stage.lua"),"original-input"],raw)
    actual=seeded_run([lua,str(d/"stage.lua")],raw).splitlines()
    expected=seeded_run([str(d/"test")],supply).splitlines()
    assert len(actual)==len(expected)==len(cases_seeded)
    positive=shore=wide_positive=0
    for case,map_in,a,b in zip(cases_seeded,supply.splitlines(),actual,expected):
        if a!=b:
            diff=next((i,v,u) for i,(v,u) in enumerate(zip(a.split(),b.split())) if v!=u)
            raise AssertionError((case,diff,a[:100],b[:100]))
        cells,rng=a.split(" : ")
        parts=cells.split(" / ")
        words=list(map(int,parts[1].split()[1:]))
        assert len(words)==case[0]*case[1]
        orig=list(map(int,map_in.split()[13+len(words):13+2*len(words)]))
        if case[8]:
            initial=list(map(int,map_in.split()[13:13+len(words)]))
            heights=list(map(int,parts[2].split()))
            delta=sum(u!=v for u,v in zip(initial,heights,strict=True))
            commands=[list(map(int,t.split(","))) for t in parts[3].strip("-;").split(";") if t]
            commits=sum(t[3] for t in commands)
            clears=sum(t[5] for t in commands)
            assert delta==0 or any(t[4]>0 for t in commands)
            if case[8]==2:
                assert len(commands)==6 and commits==3 and clears==3
                assert [t[3] for t in commands]==[0,0,0,1,1,1]
                assert commands[3][4]==5 and commands[4][4]==0
            else:
                wide_positive+=delta>0
            print(f"Stock TerraGenesis river commands {case}: commands={len(commands)} success={commits} height_delta={delta} cleared_water={clears} hsha256={sha256(bytes(heights)).hexdigest()[:16]}")
        sig=sha256(pack(f"<{len(words)}H",*words)).hexdigest()[:16]
        nriver=sum(w%256==54 for w in words)
        nshore=sum(w%256!=54 and w!=v for w,v in zip(words,orig))
        positive+=nriver>0;shore+=nshore
        if case[6]==99:
            def word(x,z):return words[x-1+(z-1)*case[0]]
            assert word(36,36)==22, "Reflood must restore sea in the broad basin."
            assert word(11,12)==word(12,11)==word(12,12)==0, "Visited isolated shore slopes must dry."
            assert word(11,11)==38, "The LFSR has not visited this fourth shore yet."
            assert nshore>0
        print(f"Stock post-river snapshot {case}: cursor={a.split()[5]} rivers={nriver} shore_changes={nshore} sha256={sig} rng={rng}")
    assert positive>=2 and shore>0 and wide_positive>=2,(positive,shore,wide_positive)
print(f"STOCK_RIVER_WORLDGEN_ORACLE_PASS: {len(cases)} synthetic paths/writes plus {len(cases_seeded)} full boards matched source routes, lake/well writes, terrain commands, post-flood snapshots, loop cursor and final RNG.")
