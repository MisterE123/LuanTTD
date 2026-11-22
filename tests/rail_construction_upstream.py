"""Differential stock normal-rail quote and eligibility checks (OpenTTD 14.1).

python tests/rail_construction_upstream.py SOURCE_TREE [lua5.1]
Compiles the quote-only command branches with a read-only map/pool shim.
NewGRF, roads, full station joining/town authority, and execution are out.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_height_upstream import cpp as rail_source
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "table/railtypes.h":"849641b9e16d2b5dcf6036caf1f939f3e8bc7b6425711fc6baea1ddfc02b3261",
    "table/pricebase.h":"17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "depot_func.h":"65f213680946622fb9f6c02e0e44d7f1047872affd2e5e5f44989450d28bae5c",
    "clear_cmd.cpp":"97a79d03eb421cf5815c065b7a7dadbd97b362b650f48bda10fd28e85d0e2b68",
    "signal_type.h":"186baccaa40e165325eaded4f37c44b798c03d080b6ffe6d8dbd16a3932d4793a",
})

LUA=r"""
local base="mods/luanttd_core/openttd/"
local T=dofile(base.."rail_track.lua")
local S=dofile(base.."rail_signals.lua")(T)
local Q=dofile(base.."rail_construction.lua")(T,S)
local kinds={[0]="clear","rail","signals","depot","station","water"}
local surfaces={[0]="grass","rough","rocks","fields","snow","desert"}
local function tile(n,i)
  local k,s,b,o,g,d,v,p,dir,present,uv,lv,station,flood=n[i],n[i+1],n[i+2],n[i+3],n[i+4],n[i+5],n[i+6],n[i+7],n[i+8],n[i+9],n[i+10],n[i+11],n[i+12],n[i+13]
  return {kind=kinds[k],slope=s,trackbits=b,owner=o,ground=surfaces[g],density=d,
    train_bits=v,occupied=v~=0,overhead=p~=0,dir=dir,axis=dir%2,present_signals=present,
    upper_variant=uv,lower_variant=lv,station=station,base_level=2,coast=k==5,flooding=flood~=0}
end
for line in io.lines() do
  local n={}
  for v in line:gmatch("%-?%d+") do n[#n+1]=tonumber(v) end
  local tag=n[1]
  local opts={owner=1,build_on_slopes=n[2]==1,auto_remove_signals=n[3]==1}
  local p,err
  if tag<=2 then
    local t=tile(n,13)
    if tag==0 then p,err=Q.piece(t,n[4],opts)
    elseif tag==1 then
      opts.depot_pool_full=n[3]==1
      p,err=Q.depot(t,n[4],opts)
    else
      p,err=Q.signal(t,n[4],{kind=n[5],variant=n[6],convert=n[7]==1,skip=n[8]==1,
        ctrl=n[9]==1,cycle_start=n[10],cycle_stop=n[11],copy_mask=n[12]},opts)
    end
  else
    local tiles={}
    for i=13,#n,14 do tiles[#tiles+1]=tile(n,i) end
    p,err=Q.station(tiles,n[4],n[5],n[6],opts)
  end
  print(p and p.cost or err)
end
"""


def section(src_,begin,end):
    a=src_.index(begin)
    return src_[a:src_.index(end,a)]


def cpp(source):
    b=rail_source(source).split("Slope raw;",1)[0]
    r=src(source,"rail_cmd.cpp")
    s=src(source,"station_cmd.cpp")
    b+=r"""
using RailType=int;
using Axis=int;
using DoCommandFlag=int;
using Money=int64_t;
using StationID=int;
using StationClassID=int;
using SignalType=int;
using SignalVariant=int;
constexpr int DC_EXEC=1;
constexpr int INVALID_RAILTYPE=-1,INVALID_STATION=-1,RAILTYPE_END=4;
constexpr int SIGTYPE_LAST=5,SIG_SEMAPHORE=1;
constexpr int EXPENSES_CONSTRUCTION=0,FLOOD_NONE=0,MP_WATER=5,MP_STATION=4;
constexpr int CBM_STATION_SLOPE_CHECK=0;
"""
    mapping={
        "STR_ERROR_CAN_T_BUILD_ON_WATER":"CANT_BUILD_ON_WATER",
        "STR_ERROR_LAND_SLOPED_IN_WRONG_DIRECTION":"LAND_SLOPED_IN_WRONG_DIRECTION",
        "STR_ERROR_ALREADY_BUILT":"ALREADY_BUILT",
        "STR_ERROR_IMPOSSIBLE_TRACK_COMBINATION":"IMPOSSIBLE_TRACK_COMBINATION",
        "STR_ERROR_MUST_REMOVE_SIGNALS_FIRST":"MUST_REMOVE_SIGNALS_FIRST",
        "STR_ERROR_FLAT_LAND_REQUIRED":"FLAT_LAND_REQUIRED",
        "STR_ERROR_MUST_DEMOLISH_BRIDGE_FIRST":"MUST_DEMOLISH_BRIDGE_FIRST",
        "STR_ERROR_THERE_IS_NO_RAILROAD_TRACK":"THERE_IS_NO_RAILROAD_TRACK",
        "STR_ERROR_NO_SUITABLE_RAILROAD_TRACK":"NO_SUITABLE_RAILROAD_TRACK",
        "STR_ERROR_THERE_ARE_NO_SIGNALS":"THERE_ARE_NO_SIGNALS",
        "STR_ERROR_ADJOINS_MORE_THAN_ONE_EXISTING":"ADJOINS_MORE_THAN_ONE_EXISTING",
    }
    for m,n in mapping.items(): b+=f'constexpr const char *{m}="{n}";\n'
    b+=r"""
struct CommandCost {
 Money value=0;
 const char *err=nullptr;
 CommandCost(){}
 explicit CommandCost(const char *s):err(s){}
 explicit CommandCost(int e,Money n=0):value(n){}
 bool Failed() const{return err!=nullptr;}
 bool Succeeded() const{return err==nullptr;}
 void AddCost(Money n){value+=n;}
 void AddCost(CommandCost q){if(!err)err=q.err;value+=q.value;}
};
#define return_cmd_error(name) return CommandCost(name)
#define CMD_ERROR CommandCost("INVALID_PARAMETER")
"""
    prices=src(source,"table/pricebase.h")
    keys=["PR_BUILD_RAIL","PR_CLEAR_RAIL","PR_BUILD_FOUNDATION","PR_BUILD_DEPOT_TRAIN","PR_BUILD_SIGNALS",
          "PR_CLEAR_SIGNALS","PR_BUILD_STATION_RAIL","PR_BUILD_STATION_RAIL_LENGTH","PR_CLEAR_WATER",
          "PR_CLEAR_GRASS","PR_CLEAR_ROUGH","PR_CLEAR_ROCKS","PR_CLEAR_FIELDS"]
    values={k:re.search(r"\{\s*(-?\d+),[^\n]*///< "+k+r"\b",prices)[1] for k in keys}
    b+="enum Price {"+",".join(keys)+"};\n"
    b+="Money _price[]={"+",".join(values[k] for k in keys)+"};\n"
    railtypes=src(source,"table/railtypes.h")
    ms=re.findall(r"/\* cost multiplier \*/\s*(\d+),",railtypes)
    b+="struct RTInfo{int cost_multiplier;};RTInfo rt_info[]={"+",".join("{"+m+"}" for m in ms)+"};\n"
    b+=r"""
RTInfo *GetRailTypeInfo(int i){return &rt_info[i];}
struct Tile {
 int kind,slope,bits,owner,ground,density,train,bridge,dir,signals,upper,lower,station,flood;
};
std::vector<Tile> map;
bool full;
struct {struct {bool build_on_slopes;} construction;} _settings_game;
bool IsTileType(TileIndex i,int k){return map[i].kind==k;}
bool IsPlainRail(TileIndex i){return map[i].kind==1||map[i].kind==2;}
bool IsPlainRailTile(TileIndex i){return IsPlainRail(i);}
bool IsRailDepotTile(TileIndex i){return map[i].kind==3;}
bool IsRailStationTile(TileIndex i){return map[i].kind==4;}
bool IsRailStation(TileIndex i){return IsRailStationTile(i);}
bool IsBridgeAbove(TileIndex i){return map[i].bridge;}
int GetFloodingBehaviour(TileIndex i){return map[i].flood;}
RailType GetRailType(TileIndex){return 0;}
DiagDirection GetRailDepotDirection(TileIndex i){return DiagDirection(map[i].dir);}
StationID GetStationIndex(TileIndex i){return map[i].station;}
Axis GetRailStationAxis(TileIndex i){return map[i].dir%2;}
bool IsCompatibleRail(RailType a,RailType b){return a==b;}
bool HasPowerOnRail(RailType a,RailType b){return a==b;}
TrackBits GetTrackBits(TileIndex i){return TrackBits(map[i].bits);}
TrackBits GetRailReservationTrackBits(TileIndex){return TRACK_BIT_NONE;}
Slope GetTileSlope(TileIndex i,int *z=nullptr){if(z)*z=2;return Slope(map[i].slope);}
CommandCost CheckTileOwnership(TileIndex i){return map[i].owner==1?CommandCost():CommandCost("OWNED_BY_ANOTHER");}
CommandCost EnsureNoVehicleOnGround(TileIndex i){return map[i].train?CommandCost("VEHICLE_IN_THE_WAY"):CommandCost();}
bool IsValidTrack(Track t){return unsigned(t)<6;}
bool IsValidDiagDirection(DiagDirection d){return unsigned(d)<4;}
bool ValParamRailType(RailType r){return r==0;}
TrackBits TrackToTrackBits(Track t){return TrackBits(1<<t);}
bool HasTrack(TileIndex i,Track t){return HasBit(GetTrackBits(i),t);}
bool HasSignals(TileIndex i){return map[i].kind==2;}
DiagDirection operator++(DiagDirection &x,int){auto old=x;x=DiagDirection(x+1);return old;}
Track &operator++(Track &x,int){ x=Track(x+1);return x;}
const byte packed[]={12,12,12,3,12,3};
byte SignalOnTrack(Track t){return packed[t];}
bool HasSignalOnTrack(TileIndex i,Track t){return HasSignals(i)&&(map[i].signals&packed[t]);}
SignalVariant GetSignalVariant(TileIndex i,Track t){return t==TRACK_LOWER||t==TRACK_RIGHT?map[i].lower:map[i].upper;}
bool IsClearGround(TileIndex i,int g){return map[i].ground==g;}
int GetClearGround(TileIndex i){return map[i].ground;}
int GetClearDensity(TileIndex i){return map[i].density;}
void DoClearSquare(TileIndex){}
constexpr int CLEAR_GRASS=0;
struct Depot {static bool CanAllocateItem(){return !full;}};
"""
    rail_h=src(source,"rail.h")
    b+=block(rail_h,r"^inline Money RailBuildCost")
    b+=block(rail_h,r"^inline Money RailClearCost")
    b+=block(src(source,"clear_cmd.cpp"),r"^static CommandCost ClearTile_Clear")
    b+=r"""
enum CommandName {CMD_LANDSCAPE_CLEAR,CMD_REMOVE_SINGLE_SIGNAL,CMD_CONVERT_RAIL,CMD_REMOVE_SINGLE_RAIL};
CommandCost LandscapeClear(DoCommandFlag flags,TileIndex tile){
 switch(map[tile].kind){
  case 0:return ClearTile_Clear(tile,flags);
  case 1:case 2:case 3:
    if(map[tile].owner!=1)return CommandCost("OWNED_BY_ANOTHER");
    return CommandCost(map[tile].kind==3?"BUILDING_MUST_BE_DEMOLISHED":"MUST_REMOVE_RAILROAD_TRACK");
  case 5:
    if(map[tile].train)return CommandCost("VEHICLE_IN_THE_WAY");
    return CommandCost(EXPENSES_CONSTRUCTION,_price[IsSlopeWithOneCornerRaised(GetTileSlope(tile))?PR_CLEAR_WATER:PR_CLEAR_ROUGH]);
  default:return CommandCost("BUILDING_MUST_BE_DEMOLISHED");
 }
}
template <CommandName C> struct Command {
 static CommandCost Do(DoCommandFlag flags,TileIndex tile){
   static_assert(C==CMD_LANDSCAPE_CLEAR);return LandscapeClear(flags,tile);
 }
 static CommandCost Do(DoCommandFlag,TileIndex tile,Track track){
    if(C==CMD_REMOVE_SINGLE_SIGNAL)return CommandCost(EXPENSES_CONSTRUCTION,_price[PR_CLEAR_SIGNALS]);
    if(C==CMD_REMOVE_SINGLE_RAIL){
      if(map[tile].owner!=1)return CommandCost("OWNED_BY_ANOTHER");
      return CommandCost(EXPENSES_CONSTRUCTION,RailClearCost(0));
    }
    return CMD_ERROR;
 }
 static CommandCost Do(DoCommandFlag,TileIndex,TileIndex,RailType,bool){return CMD_ERROR;}
};
struct VehicleBase {int type;};
using VehicleProbe=VehicleBase;
constexpr int VEH_TRAIN=0;
struct Train:VehicleProbe {
 TrackBits track;static Train *From(VehicleProbe *v){return static_cast<Train *>(v);}
};
"""
    occ=block(src(source,"vehicle.cpp"),r"^static Vehicle \*EnsureNoTrainOnTrackProc").replace("Vehicle *","VehicleProbe *")
    b+=occ
    b+=r"""
CommandCost EnsureNoTrainOnTrackBits(TileIndex tile,TrackBits bits) {
 for(int t=0;t<6;t++)if(HasBit(map[tile].train,t)){
   Train train;train.type=VEH_TRAIN;train.track=TrackBits(1<<t);
   if(EnsureNoTrainOnTrackProc(&train,&bits))return CommandCost("VEHICLE_IN_THE_WAY");
 }
 return CommandCost();
}
"""
    for sig in [r"^static CommandCost EnsureNoTrainOnTrack\(",r"^static CommandCost CheckTrackCombination",
                r"^static CommandCost CheckRailSlope",r"^static inline bool ValParamTrackOrientation"]:
        b+=block(r,sig)
    choose=block(r,r"^CommandCost CmdBuildSingleRail")
    b+=section(choose,"CommandCost CmdBuildSingleRail", "switch (GetTileType(tile)) {")
    b+="if (IsPlainRail(tile)||IsRailDepotTile(tile)) {\n"
    b+=section(choose,"CommandCost ret = CheckTileOwnership(tile);","\n\t\t\tif (flags & DC_EXEC)")
    b+="\n} else {\n"+section(choose,"/* Will there be flat water on the lower halftile? */","\n\t\t\tif (flags & DC_EXEC) {\n\t\t\t\tMakeRailNormal")
    b+="\n}\n"+choose[choose.rindex("cost.AddCost(RailBuildCost(railtype));"):]
    b+=block(src(source,"slope_func.h"),r"^inline Slope InclinedSlope")
    b+=block(src(source,"depot_func.h"),r"^inline bool CanBuildDepotByTileh")
    depot=block(r,r"^CommandCost CmdBuildTrainDepot")
    b+=depot[:depot.index("if (flags & DC_EXEC)")]+"\n"+depot[depot.rindex("cost.AddCost(_price[PR_BUILD_DEPOT_TRAIN]);"):]
    signal=block(r,r"^CommandCost CmdBuildSingleSignal")
    b+=signal[:signal.index("if (flags & DC_EXEC)")]+"return cost;\n}\n"
    b+=r"""
using TileArea=std::vector<int>;
struct StockArea:TileArea {TileIndex tile=0;};
struct StationSpec {int callback_mask;};
struct StationClass {
 static StationClass *Get(int){static StationClass k;return &k;}
 const StationSpec *GetSpec(int){return nullptr;}
};
CommandCost PerformStationTileSlopeCheck(TileIndex,TileIndex,const StationSpec*,Axis,int,int){std::abort();}
CommandCost ClearTile_Station(TileIndex,DoCommandFlag){return CommandCost("BUILDING_MUST_BE_DEMOLISHED");}
constexpr int DC_AUTO=2;
Train *GetTrainForReservation(TileIndex,Track){return nullptr;}
Track RemoveFirstTrack(TrackBits *p){int a=FindFirstBit(*p);*p=TrackBits(*p&(*p-1));return Track(a);}
"""
    b+=block(s,r"^CommandCost CheckBuildableTile")
    b+=block(s,r"^static CommandCost CheckFlatLandRailStation")
    b+=block(s,r"^static CommandCost CalculateRailStationCost").replace("(TileArea tile_area,","(StockArea tile_area,")
    b+=r"""
int main(){
 int mode,slopes,auto_rm,track,typ,var,convert,skip,ctrl,cs,ce,copied;
 while(std::cin>>mode>>slopes>>auto_rm>>track>>typ>>var>>convert>>skip>>ctrl>>cs>>ce>>copied){
   _settings_game.construction.build_on_slopes=slopes;
   full=auto_rm;
   size_t count=mode<3?1:typ*var;
   map.assign(count,Tile{});
   for(auto &t:map)std::cin>>t.kind>>t.slope>>t.bits>>t.owner>>t.ground>>t.density>>t.train>>t.bridge
      >>t.dir>>t.signals>>t.upper>>t.lower>>t.station>>t.flood;
   CommandCost q;
   if(mode==0)q=CmdBuildSingleRail(0,0,0,Track(track),auto_rm);
   if(mode==1){q=CmdBuildTrainDepot(0,0,0,DiagDirection(track));if(q.Failed()&&full&&!map[0].bridge&&map[0].kind!=3&&std::string(q.err)=="INVALID_PARAMETER")q=CommandCost("DEPOT_POOL_FULL");}
   if(mode==2)q=CmdBuildSingleSignal(0,0,Track(track),typ,var,convert,skip,ctrl,cs,ce,0,copied);
   if(mode==3){
     std::vector<Train*> affected;
     StationID existing=INVALID_STATION;
     StockArea area;
     for(size_t i=0;i<count;i++)area.push_back(i);
     q=CalculateRailStationCost(area,0,track,&existing,0,affected,0,0,var,typ);
     if(q.Succeeded())for(auto &t:map)if(t.kind==4&&t.owner!=1){q=CommandCost("OWNED_BY_ANOTHER");break;}
   }
   if(q.Failed())std::cout<<q.err<<"\n";else std::cout<<q.value<<"\n";
 }
}
"""
    return b


def fixtures():
    r=random.Random(14147)
    shapes=list(range(15))+[23,27,29,30]
    def tile(k=0,s=0,b=1,o=1,g=0,d=0,v=0,p=0,di=0,sg=0,u=0,l=0,st=1,f=0):
        return [k,s,b,o,g,d,v,p,di,sg,u,l,st,f]
    def mask(bits): return (12,3,48)[bits%3]%16
    rows=[]
    for s in shapes:
        for track in range(6):
            for b in range(1,64):
                for slope in (0,1):
                    rows.append([0,slope,b%2,track]+[0]*8+tile(k=1,s=s,b=b,o=0 if b%5==0 else 1,v=(b//2 if b%7==0 else 0),f=b%11==0))
            for sc in range(35):
                k=r.choice((0,0,0,2,3,5))
                rows.append([0,sc%2,sc%2,track]+[0]*8+tile(k=k,s=s,b=r.choice((1,2,4,8,12,16,32,48)),
                    o=r.randrange(2),g=r.randrange(6),d=r.randrange(4),v=r.choice((0,0,1)),sg=r.randrange(1,16),f=k==5))
        for di in range(4):
            for k in (0,1,2,3,4,5):
                for opt in range(16):
                    rows.append([1,opt//8,opt%2,di]+[0]*8+tile(k=k,s=s,o=1 if opt%4 else 0,g=opt%6,
                        d=opt%4,v=opt%3==0,p=opt%6==0,di=opt%4,f=k==5))
    for _ in range(13000):
        b=r.choice((1,2,3,4,8,12,16,32,48))
        rows.append([2,1,0,r.randrange(6),r.randrange(7),r.randrange(3),r.randrange(2),r.randrange(2),r.randrange(2),
            r.randrange(7),r.randrange(7),r.randrange(16)]+
            tile(k=r.choice((0,1,2,2,2,3,4)),b=b,o=r.choice((0,1,1)),sg=mask(b),u=r.randrange(2),l=r.randrange(2)))
    # Valid signal geometry, deterministic variants, and all successful
    # station price branches, not just uncommon rejection permutations.
    for v in range(2):
        for cur in range(2):
            for track in range(6):
                for k in (1,2):
                    for ctrl in range(2):
                        for conv in range(2):
                            for skip in range(2):
                                for side in (0,1,2,4,8,15):
                                    rows.append([2,1,0,track,4,v,conv,skip,ctrl,0,5,side]+
                                      tile(k=k,b=1<<track,sg=15,u=cur,l=cur))
    for ix in range(3500):
        axis,ns,length=r.randrange(2),r.randrange(1,5),r.randrange(1,8)
        cells=[]
        for i in range(ns*length):
            k=r.choice((0,0,1,1,4,4))
            s=r.choice(shapes) if ix%4==0 else 0
            cells+=tile(k=k,s=s,b=2**axis if ix%3 else 2**(1-axis),o=0 if ix%13==0 else 1,
               g=i%6,d=i%4,v=1 if ix%17==0 else 0,p=ix%31==0,di=axis if i%3 else 1-axis,st=1 if ix%7 else 1+i%2)
        rows.append([3,ix%5!=0,0,axis,ns,length]+[0]*6+cells)
        if ix%2==0:
            cells=[]
            for i in range(ns*length):
                k=r.choice((0,1,4))
                cells+=tile(k=k,b=2**axis,g=i%6,d=i%4,di=axis if i%3 else 1-axis)
            rows.append([3,1,0,axis,ns,length]+[0]*6+cells)
    return [[int(x) for x in row] for row in rows]


def main():
    source=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    rows=fixtures()
    data="".join(" ".join(map(str,row))+"\n" for row in rows)
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/"stock.cpp").write_text(cpp(source))
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(tmp/"stock.cpp"),"-o",str(tmp/"stock")],check=True)
        stock=subprocess.check_output([str(tmp/"stock")],input=data,text=True,cwd=ROOT).splitlines()
        port=subprocess.check_output([lua,str(tmp/"port.lua")],input=data,text=True,cwd=ROOT).splitlines()
    assert len(stock)==len(port)==len(rows)
    for i,(a,b) in enumerate(zip(stock,port)):
        if a!=b: raise AssertionError((rows[i],a,b))
    legal=sum(x.lstrip("-").isdigit() for x in stock)
    assert legal>5000,legal
    print(f"PASS: {len(rows)} exact stock track, depot, signal, and station quote/safety cases ({legal} legal)")

if __name__=="__main__":
    main()
