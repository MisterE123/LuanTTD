"""Compare rail bridge and tunnel pricing/orchestration with OpenTTD 14.1.

python tests/rail_span_upstream.py SOURCE_TREE [lua5.1]
Compiles unmodified availability/length math and the rail portions of
CmdBuildBridge and CmdBuildTunnel. Uses in-memory fixtures for the map,
company, clearing and requested TerraformLand command; the independent
road_bridge_upstream test already covers the shared ramp foundation math.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_motion_upstream import cpp as motion_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "table/bridge_land.h":"95b5bc37b87fde7f85f736730150eac5a665356a081ba7f92270cde1b326b597",
    "table/pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "table/railtypes.h":"849641b9e16d2b5dcf6036caf1f939f3e8bc7b6425711fc6baea1ddfc02b3261",
    "slope_func.h":"1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a",
})

LUA=r"""
local p="mods/bayline/openttd/"
local T=dofile(p.."rail_track.lua")
local S=dofile(p.."slope.lua")
local Site=dofile(p.."rail_span_site.lua")
local Q=dofile(p.."rail_construction.lua")(T,dofile(p.."rail_signals.lua")(T))
local B=dofile(p.."rail_bridge.lua")(dofile(p.."road_bridge.lua")(S),Q,Site)
local U=dofile(p.."rail_tunnel.lua")(dofile(p.."road_tunnel.lua"),Q,Site,T)
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local slope={[0]=12,6,3,9}
local function id(x,z)return x+1024*z end
local function xy(i)return i%1024,math.floor(i/1024) end
for line in io.lines() do
  local n={}
  for v in line:gmatch("%-?%d+") do n[#n+1]=tonumber(v) end
  local m={}
  local board={tile=function(i)return m[i] end,xy=xy,id=id,max_x=1023}
  local a,c,extra,detail
  if n[1]==0 then
    local len,sty,yr,max_,flags,replace,old_style,old_type,old_owner,baseprice,entrance,exit=n[2],n[3],n[4],n[5],n[6],n[7],n[8],n[9],n[10],n[11],n[12],n[13]
    local from,to=id(10,10),id(11+len,10)
    for i=from,to do
      m[i]={kind="clear",base=3,slope=0,max_z=3,density=0}
    end
    m[from].clear_cost=entrance;m[to].clear_cost=exit
    if replace==1 then
      for _,i in ipairs({from,to}) do
        local t=m[i]
        t.kind="bridge";t.transport="rail";t.railtype=old_type;t.bridge_type=old_style;t.reserved=true
        t.other=i==from and to or from
        if old_owner~=0 then t.owner=old_owner==2 and "town" or old_owner end
      end
    end
    local function bit(i)return math.floor(flags/i)%2==1 end
    a,c=B.plan(board,from,to,sty,{owner=1,year=yr,max_length=max_,query=bit(1),ai=bit(2),local_company=bit(4),
      company=not bit(8),editor=bit(16),prices={bridge=baseprice}})
    if a then print(a.price,a.infrastructure_delta,a.preserve_reservation and 1 or 0)
    else print(c) end
  else
    local dir,len,price,flags,crossat,reach,exit_slope,terraform,entrance,exit=n[2],n[3],n[4],n[5],n[6],n[7],n[8],n[9],n[10],n[11]
    local tx,tz=512,510
    local from=id(tx,tz)
    local to=id(tx+dx[dir]*(len+1),tz+dz[dir]*(len+1))
    local function bit(i)return math.floor(flags/i)%2==1 end
    m[from]={kind=bit(1) and "water" or "clear",base=3,slope=slope[dir],density=0,clear_cost=entrance}
    for j=1,len do
      m[id(tx+dx[dir]*j,tz+dz[dir]*j)]={kind="clear",base=4,slope=0,density=0}
    end
    if not bit(4) then
      m[to]={kind=bit(2) and "water" or "clear",base=3,slope=exit_slope,density=0,clear_cost=exit}
    end
    board.tunnel_in_way=function(i,level,probe)
      assert(level==3 and probe==(dir%2==1 and T.NE or T.SE))
      return i==id(tx+dx[dir]*crossat,tz+dz[dir]*crossat)
    end
    board.clear_quote=function(i,t,role)
      if role=="entrance" and bit(8) then return nil,"CLEAR_REFUSED" end
      if role=="exit" and bit(16) then return nil,"CLEAR_REFUSED" end
      return t.clear_cost
    end
    board.terraform_quote=function(i,mask,up,cleared)
      assert(i==to and not up and cleared[from] and cleared[to] and mask~=0)
      if terraform<0 then return nil,"TERRAFORM_REFUSED" end
      return {cost=terraform}
    end
    a,c,extra=U.plan(board,from,{owner=1,max_length=reach,prices={tunnel=price},crossing_tunnels=bit(32)})
    if a then print(a.price,a["end"],a.excavation_mask)
    else print(c,extra or 0) end
  end
end
"""


def cpp(source):
    b=motion_cpp(source).split("int main(){",1)[0]
    b="#include <climits>\n#include <algorithm>\n#include <cstdlib>\n#include <tuple>\n"+b
    cmd=src(source,"tunnelbridge_cmd.cpp")
    b+=declarations(src(source,"slope_type.h"),[r"enum Corner\s*\{",r"enum Slope\s*:"])
    b+=r"""
using BridgeType=int;
using Price=int;
using DoCommandFlag=int;
using Money=int64_t;
using RailType=int;
using TransportType=int;
constexpr int EXPENSES_CONSTRUCTION=0,RAILTYPE_END=4,DC_QUERY_COST=1,TRANSPORT_RAIL=0,TRANSPORT_ROAD=1;
constexpr int GM_EDITOR=1,OWNER_TOWN=2,OWNER_NONE=0;
struct CommandCost {
 Money amount=0;const char *reason=nullptr;
 CommandCost(){}
 explicit CommandCost(int,Money n=0):amount(n){}
 explicit CommandCost(const char *r):reason(r){}
 bool Failed() const{return reason!=nullptr;}
 Money GetCost() const{return amount;}
 void AddCost(Money n){amount+=n;}
 void AddCost(CommandCost c){AddCost(c.amount);if(!reason)reason=c.reason;}
};
#define return_cmd_error(n) return CommandCost(n)
#define CMD_ERROR CommandCost("BRIDGE_UNAVAILABLE")
#define NOT_REACHED() std::abort()
constexpr const char *STR_ERROR_BRIDGE_TOO_LONG="BRIDGE_TOO_LONG";
constexpr const char *STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST="MUST_DEMOLISH_BRIDGE_FIRST";
constexpr const char *STR_ERROR_LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS="LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS";
constexpr const char *STR_ERROR_ALREADY_BUILT="ALREADY_BUILT";
constexpr const char *STR_ERROR_AREA_IS_OWNED_BY_ANOTHER="AREA_IS_OWNED_BY_ANOTHER";
constexpr const char *STR_ERROR_SITE_UNSUITABLE_FOR_TUNNEL="UNSUITABLE_TUNNEL_ENTRANCE";
constexpr const char *STR_ERROR_CAN_T_BUILD_ON_WATER="CANT_BUILD_ON_WATER";
constexpr const char *STR_ERROR_TUNNEL_THROUGH_MAP_BORDER="TUNNEL_THROUGH_MAP_BORDER";
constexpr const char *STR_ERROR_ANOTHER_TUNNEL_IN_THE_WAY="ANOTHER_TUNNEL_IN_THE_WAY";
constexpr const char *STR_ERROR_TUNNEL_TOO_LONG="TUNNEL_TOO_LONG";
constexpr const char *STR_ERROR_UNABLE_TO_EXCAVATE_LAND="UNABLE_TO_EXCAVATE_LAND";
struct {struct {uint max_bridge_length,max_tunnel_length;} construction;} _settings_game;
struct {struct {bool value;} crossing_tunnels;} _cheats;
struct TimerGameCalendar {static int year;};
int TimerGameCalendar::year;
struct BridgeSpec {int avail_year;uint min_length,max_length;int price,speed;};
#define MBR(y,mn,mx,p,s,...) {y,mn,mx,p,s}
"""
    b+=declarations(src(source,"table/bridge_land.h"),[r"const BridgeSpec _orig_bridge"])
    b+="constexpr int MAX_BRIDGES=sizeof(_orig_bridge)/sizeof(BridgeSpec);\n"
    b+="const BridgeSpec *GetBridgeSpec(BridgeType id){return &_orig_bridge[id];}\n"
    b+=block(cmd,r"^int CalcBridgeLenCostFactor")
    b+=block(cmd,r"^CommandCost CheckBridgeAvailability")
    price=src(source,"table/pricebase.h")
    keys=("PR_BUILD_BRIDGE","PR_CLEAR_BRIDGE","PR_BUILD_TUNNEL","PR_BUILD_RAIL","PR_CLEAR_RAIL")
    vals=[re.search(r"\{\s*(-?\d+),[^\n]*///< "+k+r"\b",price)[1] for k in keys]
    b+="enum {"+",".join(keys)+"};\nMoney _price[]={"+",".join(vals)+"};\n"
    ms=re.findall(r"/\* cost multiplier \*/\s*(\d+),",src(source,"table/railtypes.h"))
    b+="struct RTInfo{int cost_multiplier;};RTInfo rt_info[]={"+",".join("{"+x+"}" for x in ms)+"};\n"
    b+="RTInfo *GetRailTypeInfo(int i){return &rt_info[i];}\n"
    b+=block(src(source,"rail.h"),r"^inline Money RailBuildCost")
    b+=block(src(source,"rail.h"),r"^inline Money RailClearCost")
    b+=r"""
struct Company {bool is_ai;};
struct Town {int index;};
int _local_company,owner_id,old_type,old_style,_game_mode;
bool IsTileOwner(TileIndex,int x){return owner_id==x;}
RailType GetRailType(TileIndex){return old_type;}
BridgeType GetBridgeType(TileIndex){return old_style;}
Town *ClosestTownFromTile(TileIndex,uint){static Town t={1};return &t;}
void SetDParam(int,int){}
"""
    # Exact stock expressions for transport refund, normal-rail building,
    # bridge coefficient and assembly. Road-only conditions are replaced
    # with their rail short-circuit value.
    clear_line=next(x for x in cmd.splitlines() if "case TRANSPORT_RAIL: base_cost +=" in x)
    b+="Money TunnelBridgeClearCost(TileIndex tile,Price price){Money base_cost=_price[price];switch(TRANSPORT_RAIL){"+clear_line+"}return base_cost;}\n"
    rail_build=next(x for x in cmd.splitlines() if "case TRANSPORT_RAIL: cost.AddCost(bridge_len" in x)
    factor=next(x for x in cmd.splitlines() if "bridge_len = CalcBridgeLenCostFactor" in x)
    assemble=next(x for x in cmd.splitlines() if "GetBridgeSpec(bridge_type)->price >> 8" in x)
    bridge=block(cmd,r"^CommandCost CmdBuildBridge")
    a=bridge.index("/* If this is a railway bridge")
    town=bridge.index("/* Do not replace town bridges",a)
    end=bridge.index("owner = GetTileOwner(tile_start);",town)
    replacement=bridge[a:bridge.index("/* If this is a road bridge",a)]+bridge[town:end]
    replacement=replacement.replace("(transport_type != TRANSPORT_ROAD || road_rt == roadtype || tram_rt == roadtype)","true")
    b+=r"""
CommandCost bridge_ref(uint bridge_len,BridgeType bridge_type,DoCommandFlag flags,bool replacing,
                       Company *c,Money entrance,Money exit){
 auto ret=CheckBridgeAvailability(bridge_type,bridge_len,flags);
 if(ret.Failed())return ret;
 bridge_len+=2;
 const int company=1,transport_type=TRANSPORT_RAIL,railtype=0,tile_start=0;
 CommandCost cost(EXPENSES_CONSTRUCTION);
 if(replacing) {
"""+replacement+r"""
 } else cost.AddCost(entrance+exit);
 if (!(flags & DC_QUERY_COST) || (c != nullptr && c->is_ai && company != _local_company)) {
    switch(TRANSPORT_RAIL){"""+rail_build+"}\n"+factor+"\n"+assemble+r"""
 }
 return cost;
}
constexpr int AXIS_Y=1;
int TileX(TileIndex i){return i%1024;}
int TileY(TileIndex i){return i/1024;}
struct Map {static int MaxX(){return 1023;}};
int DiagDirToAxis(DiagDirection d){return d%2;}
using TileIndexDiff=int;
TileIndexDiff TileOffsByDiagDir(DiagDirection d){constexpr int f[]={-1,1024,1,-1024};return f[d];}
TileIndex _build_tunnel_endtile,terminal,begin_,crossing;
int test_flags,terminal_slope,terra_price,exc_mask;
Money clear_begin,clear_end;
bool IsValidTile(TileIndex t){
 int delta=abs(t-begin_),last=abs(terminal-begin_);
 return delta<=last && !(t==terminal&&(test_flags&4));
}
Slope GetTileSlope(TileIndex i,int *z){
 *z=i==begin_||i==terminal?3:4;
 static int entry_slope[]={12,6,3,9};
 if(i==begin_){for(int d=0;d<4;d++)if((terminal-begin_)*TileOffsByDiagDir(DiagDirection(d))>0 &&
   (abs(terminal-begin_)>=1024 ? d%2==1 : d%2==0))return Slope(entry_slope[d]);}
 return Slope(i==terminal?terminal_slope:0);
}
bool HasTileWaterGround(TileIndex i){return i==begin_?test_flags&1:test_flags&2;}
bool IsTunnelInWayDir(TileIndex i,int h,DiagDirection d){
 assert(h==3);
 assert(d==((abs(terminal-begin_)>=1024)?DIAGDIR_NE:DIAGDIR_SE));
 return i==crossing;
}
constexpr Slope operator&(Slope a,Slope b){return Slope(int(a)&int(b));}
constexpr Slope operator^(Slope a,Slope b){return Slope(int(a)^int(b));}
bool IsSteepSlope(Slope s){return s&SLOPE_STEEP;}
bool IsHalftileSlope(Slope s){return s&SLOPE_HALFTILE;}
enum CommandName{CMD_LANDSCAPE_CLEAR,CMD_TERRAFORM_LAND};
template<CommandName C> struct Command{
 static CommandCost Do(DoCommandFlag,TileIndex i){
  if(i==begin_)return (test_flags&8)?CommandCost("CLEAR_REFUSED"):CommandCost(0,clear_begin);
  return (test_flags&16)?CommandCost("CLEAR_REFUSED"):CommandCost(0,clear_end);
 }
 static auto Do(DoCommandFlag,TileIndex i,Slope mask,bool up){
  assert(!up&&i==terminal);exc_mask=int(mask);
  if(mask!=0 && terra_price<0)return std::make_tuple(CommandCost("TERRAFORM_REFUSED"));
  return std::make_tuple(CommandCost(0,mask==0?0:terra_price));
 }
};
"""
    for name in ("GetInclinedSlopeDirection","ComplementSlope"):
        b+=block(src(source,"slope_func.h"),rf"^inline \w+ {name}\(")
    tunnel=block(cmd,r"^CommandCost CmdBuildTunnel")
    a=tunnel.index("int start_z;")
    ex=tunnel.index("/* slope of end tile")
    incl=tunnel.index("if (end_tileh != ComplementSlope",ex)
    terraform=next(x for x in tunnel.splitlines() if "CMD_TERRAFORM_LAND>::Do" in x)
    b+="CommandCost tunnel_ref(TileIndex start_tile,DoCommandFlag flags){int railtype=0;\n"
    b+=tunnel[a:ex]+tunnel[incl:tunnel.index("{",incl)+1]+"\n"+terraform+r"""
  if(ret.Failed())return_cmd_error(STR_ERROR_UNABLE_TO_EXCAVATE_LAND);
  cost.AddCost(ret);
 }
 cost.AddCost(_price[PR_BUILD_TUNNEL]);
 switch(TRANSPORT_RAIL){"""+next(x for x in tunnel.splitlines() if "(tiles + 2) * RailBuildCost" in x)+r"""}
 return cost;
}
int main(){
 int mode;
 while(std::cin>>mode){
  if(mode==0){
   int len,sty,yr,max_,flags,r,newprice,entrance,exit;
   std::cin>>len>>sty>>yr>>max_>>flags>>r>>old_style>>old_type>>owner_id>>newprice>>entrance>>exit;
   _price[PR_BUILD_BRIDGE]=newprice;
   _settings_game.construction.max_bridge_length=max_;TimerGameCalendar::year=yr;
   Company c{bool(flags&2)};_local_company=bool(flags&4);_game_mode=(flags&16)?GM_EDITOR:0;
   auto q=bridge_ref(len,sty,flags&1,r,(flags&8)?nullptr:&c,entrance,exit);
   if(q.Failed())std::cout<<q.reason<<"\n";else {
    int delta= (!(flags&8)&&(!r||owner_id==0))?(len+2)*4:0;
    std::cout<<q.GetCost()<<"\t"<<delta<<"\t"<<r<<"\n";
   }
  } else {
   int dir,len,price,probe,reach;
   std::cin>>dir>>len>>price>>test_flags>>probe>>reach>>terminal_slope>>terra_price>>clear_begin>>clear_end;
   _price[PR_BUILD_TUNNEL]=price;_settings_game.construction.max_tunnel_length=reach;
   _cheats.crossing_tunnels.value=test_flags&32;
   int delta=TileOffsByDiagDir(DiagDirection(dir));
   begin_=512+510*1024;terminal=begin_+delta*(len+1);crossing=begin_+delta*probe;
   _build_tunnel_endtile=0;exc_mask=0;
   auto q=tunnel_ref(begin_,0);
   if(q.Failed())std::cout<<q.reason<<"\t"<<_build_tunnel_endtile<<"\n";
   else std::cout<<q.GetCost()<<"\t"<<_build_tunnel_endtile<<"\t"<<exc_mask<<"\n";
  }
 }
}
"""
    return b


def samples():
    r=random.Random(141380)
    data=[]
    for _ in range(11000):
        n=r.randrange(69)
        flags=r.choice([0,0,0,1,3,7,8,16])
        data.append([0,n,r.randrange(13 if flags==3 else 14),r.choice([1950,2005,1920]),r.choice([64,69,8]),
                     flags,r.randrange(2),r.randrange(13),r.choice([0,0,0,1]),r.randrange(4),
                     r.choice([1,275,501]),r.randrange(60),r.randrange(60)])
    for n in range(303):
        for d in range(4):
            for f in [0,0,0,0,r.randrange(64),32]:
                data.append([1,d,n,r.choice([17,450,1200]),f,r.randrange(n+2),r.choice([64,303,303,303]),
                             r.randrange(15),r.choice([-1,0,250,500]),r.randrange(41),r.randrange(60)])
    return data


def main():
    source=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    rows=samples()
    data="".join(" ".join(map(str,r))+"\n" for r in rows)
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)
        (p/"ref.cpp").write_text(cpp(source))
        (p/"lua.lua").write_text(LUA)
        subprocess.run(["g++","-O2","-std=c++17",str(p/"ref.cpp"),"-o",str(p/"ref")],check=True)
        stock=subprocess.check_output([p/"ref"],input=data,text=True,cwd=ROOT).splitlines()
        port=subprocess.check_output([lua,p/"lua.lua"],input=data,text=True,cwd=ROOT).splitlines()
    assert len(stock)==len(port)==len(rows)
    for i,(a,b) in enumerate(zip(stock,port)):
        if a!=b:raise AssertionError((rows[i],a,b))
    print(f"PASS: {len(rows)} stock rail bridge and tunnel quote, clearance precedence, and upgrade cases")


if __name__=="__main__":
    main()
