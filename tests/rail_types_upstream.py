"""Run hash-pinned OpenTTD 14.1 railtype checks against the detached Lua port.

python tests/rail_types_upstream.py SOURCE_TREE [lua5.1]
The real command executes against an inert ownership/map/reservation shim.
Area geometry is supplied as stock iterator output; this checks the loop,
pricing and actions rather than inventing a second drag geometry adapter.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "elrail_func.h": "f0d6f817d4e3dca480148c2c9abd3af61659e83c3efb96ad775d773270a954aa",
    "elrail.cpp": "17b29789a00c26720bd350d3c5c596083210bb7866dd9d07c0fcc97735086027",
    "train.h": "35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d",
    "train_cmd.cpp": "206171b133fc9bed8c3fe21ccb3a9134317461597b0120fa77340f0b0cdbc059",
    "rail.h": "c35b8b5a3de670a526567960c1fec17799291b0431babdd952634285522342aa",
    "rail.cpp": "1d990c0a35ef14c1fc072ace3952734bac087f7981d18943932a96de8e1f0887",
    "rail_cmd.cpp": "09c9ddedb7d94af9f21bcb2f71859f93b96bf9dbaab9d5eb1da51de11d9972d9",
    "rail_map.h": "13855adaa34c4184bc32bf8f74f0e3610ffc1da3081636de27a0d628a5911b6b",
    "table/railtypes.h": "849641b9e16d2b5dcf6036caf1f939f3e8bc7b6425711fc6baea1ddfc02b3261",
    "table/engines.h": "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "table/pricebase.h": "17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "economy_type.h": "3ceaeaae7a62363f3243a1b337f1e84c98c74d22a81c0dd71c74921955e6697b",
})

LUA=r'''
local R=dofile("mods/luanttd_core/openttd/rail_types.lua")
local kinds={[0]="clear","rail","signals","depot","station","crossing","bridge","tunnel","station","waypoint"}
local function yn(v) return v and 1 or 0 end
for line in io.lines() do
  local a={}
  for value in line:gmatch("%-?%d+") do a[#a+1]=tonumber(value) end
  local cmd=a[1]
  local out={}
  local function emit(...) for _,v in ipairs({...}) do out[#out+1]=v end end
  if cmd==0 then
    local m8,r=a[2],a[3]
    emit(R.tile_type(m8),R.set_tile_type(m8,r))
  elseif cmd==1 then
    local f,t=a[2],a[3]
    local opts={rail=a[4],clear_rail=a[5]}
    local info=R.entry(f)
    emit(yn(R.is_compatible(f,t)),yn(R.has_power(f,t)),R.build_cost(f,opts),R.clear_cost(f,opts),
       R.convert_cost(f,t,opts),info.powered,info.compatible,info.cost,info.maintenance,info.fallback,
       info.bridge,info.curves,info.acceleration,info.sort,yn(info.catenary))
  elseif cmd==2 then
    local owner,climate,date,hidden,disabled=a[2],a[3],a[4],a[5],a[6]==1
    local input={}
    for i=7,#a,5 do
      input[#input+1]={intended_railtype=a[i],kind=a[i+1]==1 and "wagon" or "engine",
       climates=a[i+2],intro_date=a[i+3],company_avail=a[i+4]}
    end
    local mask=R.company_types(input,owner,climate,date,disabled)
    emit(mask)
    for i=0,3 do emit(yn(R.available(i,mask,hidden))) end
  elseif cmd==3 then
    local target,available,hidden,disabled,mask=a[2],a[3],a[4],a[5]==1,a[6]
    local rec,ids={},{}
    local b={size=16,tile=function(i) return rec[i] end}
    function b.reservations(id)
      local t=rec[id]
      return t.res>=0 and {{train=id,railtype=t.res,track=0}} or {}
    end
    for i=0,15 do
      local j=7+i*8
      rec[i]={kind=kinds[a[j]],railtype=a[j+1],owner=a[j+2],trackbits=a[j+3],blocked=a[j+4]==1,
        other=a[j+5],length=a[j+6],res=a[j+7],has_station_rail=a[j]~=8}
      if math.floor(mask/2^i)%2==1 then ids[#ids+1]=i end
    end
    if #ids==0 then ids[1]=0 end
    local q,why=R.quote_convert(b,ids,target,{owner=1,available=available,hidden=hidden,disable_elrails=disabled})
    local changed,freed={},{}
    if q then
      for _,u in ipairs(q.updates) do changed[u.id]=u.to end
      for _,r in ipairs(q.free_reservations) do freed[r.train]=true end
    end
    emit(q and q.cost or why)
    emit(q and q.infra[0] or 0,q and q.infra[1] or 0)
    for id=0,15 do emit(changed[id] or rec[id].railtype,yn(freed[id])) end
  elseif cmd==4 then
    local e=R.electric_engine(a[2])
    emit(e.image_index,e.cost_factor,e.speed,e.hp,e.tare,e.running_factor,e.base_intro,e.decay_speed,
        e.vehicle_life,e.model_life,e.climates,e.capacity,yn(e.multiheaded),e.railtype,e.running_base)
  elseif cmd==5 then
    local input={}
    for j=4,#a,6 do
      input[#input+1]={intended_railtype=a[j],hp=a[j+1],legacy_normal=a[j+2]==1,
        multiheaded=a[j+3]==1,articulated=a[j+4]==1,track=a[j+5]}
    end
    local r=R.consist(input,false)
    local function change(disabled)
      for i,u in ipairs(input) do u.legacy_normal=R.flag_existing(r.units[i],disabled) end
      r=R.consist(input,disabled)
      emit(r.route_mask)
      for i,u in ipairs(r.units) do
        emit(u.railtype,yn(u.legacy_normal),R.unit_power(u,input[i].track))
      end
    end
    change(a[2]==1);change(a[3]==1)
  elseif cmd==6 then
    emit(yn(R.catenary_drawn(a[2],a[3]==1,a[4]==1)))
  end
  print(table.concat(out," "))
end
'''

CPP = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
using byte = unsigned char;
using uint = unsigned int;
using Money = int64_t;
using RailType = int;
using RailTypes = uint64_t;
using Track = int;
using TrackBits = unsigned;
using TileIndex = unsigned;
using TileType = int;
using CompanyID = unsigned;
using DoCommandFlag = int;
constexpr int DC_EXEC=1, EXPENSES_CONSTRUCTION=0, TRANSPORT_RAIL=1, INVALID_TRACK=-1, TRACK_BIT_NONE=0;
constexpr RailType RAILTYPE_RAIL=0,RAILTYPE_ELECTRIC=1,RAILTYPE_BEGIN=0,RAILTYPE_END=4;
constexpr RailTypes RAILTYPES_NONE=0,RAILTYPES_RAIL=1;
constexpr TileIndex INVALID_TILE=~0U;
constexpr int RTF_NO_LEVEL_CROSSING=0, RTF_CATENARY=1, TO_CATENARY=1;
bool invisibility=false;
bool IsInvisibilitySet(int){return invisibility;}
constexpr int MP_RAILWAY=1,MP_STATION=4,MP_ROAD=5,MP_TUNNELBRIDGE=6,RAIL_TILE_DEPOT=3;
constexpr int RAILVEH_WAGON=1,VEH_TRAIN=0;
constexpr auto STR_ERROR_NO_SUITABLE_RAILROAD_TRACK="NO_SUITABLE_RAILROAD_TRACK";
constexpr auto STR_ERROR_CROSSING_DISALLOWED_RAIL="CROSSING_DISALLOWED_RAIL";
constexpr auto CMD_ERROR="INVALID_PARAMETER";

template<typename T> bool HasBit(T a, unsigned b) {return (a>>b)&1;}
template<typename T> void SetBit(T &a, unsigned b) {a |= T(1)<<b;}
template<typename T> bool IsInsideMM(T a,T b,T c) {return b<=a && a<c;}
template<typename T> T GB(T a,unsigned b,unsigned n){ return (a>>b)&((1<<n)-1); }
template<typename T> void SB(T &a,unsigned b,unsigned n,unsigned value){ T mask=((1<<n)-1)<<b;a=(a&~mask)|((value<<b)&mask); }
constexpr uint CountBits(uint n){return __builtin_popcount(n);}
bool TracksOverlap(TrackBits b){return CountBits(b)>1 && b!=12 && b!=48;}
Track RemoveFirstTrack(TrackBits *p){auto &b=*p;if(!b)return INVALID_TRACK; auto i=__builtin_ctz(b);b&=b-1;return i;}
struct DateBase { int val; int base() const{return val;} };
namespace CalendarTime { constexpr int DAYS_IN_YEAR=365; constexpr DateBase MAX_DATE{1826212865}; }
struct TimerGameCalendar { using Date=int; static int date; };
int TimerGameCalendar::date;
struct RailTypeInfo {
 RailTypes powered_railtypes,compatible_railtypes; int cost_multiplier,maintenance_multiplier,fallback_railtype,bridge_offset,
   curve_speed,acceleration,sort_order,flags,label=1,introduction_date=-1; RailTypes introduction_required_railtypes=0,introduces_railtypes=0;
};
extern RailTypeInfo _railtypes[4];
struct Company {
 struct { int rail[4]={0,0,0,0}; } infrastructure;
 int index=1;
 RailTypes avail_railtypes=0;
 static Company *Get(CompanyID) {static Company c; return &c;}
 static std::vector<Company *> Iterate(){return {Get(1)};}
};
RailTypes _railtypes_hidden_mask;
CompanyID _current_company;
struct {struct{ bool disable_elrails=false; } vehicle; struct{int landscape;} game_creation;} _settings_game;
struct EngineInfo { unsigned climates; };
struct RailVehicleInfo { int railtype, railveh_type; int intended_railtype=0; uint16_t power=0; };
struct Engine {
 EngineInfo info;
 struct { RailVehicleInfo rail; } u;
 unsigned company_avail;
 int intro_date;
 static std::vector<Engine> engines;
 static std::vector<Engine *> IterateType(int){std::vector<Engine *> p;for(auto &e:engines)p.push_back(&e);return p;}
};
std::vector<Engine> Engine::engines;
const RailVehicleInfo *RailVehInfo(int engine){return &Engine::engines[engine].u.rail;}
struct Train {
 RailType railtype=0; int id=-1; int engine_type=0;
 unsigned flags=0,tile=0;
 RailTypes compatible_railtypes=0;
 bool articulated=false,multiheaded=false;
 Train *next=nullptr;
 Train *Next(){return next;}
 bool IsFrontEngine()const{return engine_type==0;}
 bool IsArticulatedPart()const{return articulated;}
 bool IsMultiheaded()const{return multiheaded;}
 uint16_t GetPower()const;
 void ConsistChanged(int);
 static std::vector<Train *> Iterate();
};
std::vector<Train> train_units;
std::vector<Train *> Train::Iterate(){std::vector<Train *> out;for(auto &u:train_units)out.push_back(&u);return out;}
constexpr int VRF_EL_ENGINE_ALLOWED_NORMAL_RAIL=0,PROP_TRAIN_POWER=0;
uint16_t GetVehicleProperty(const Train *,int,uint16_t power){return power;}
RailTypes GetCompanyRailTypes(CompanyID,bool introduces=true);
void ReinitGuiAfterToggleElrail(bool){}
constexpr int CCF_TRACK=0;
using TrainList=std::vector<Train*>;
struct CommandCost {
 Money value=0; const char *error=nullptr;
 CommandCost(const char *err):error(err){}
 CommandCost(int,Money v=0):value(v){}
 bool Failed() const{return error;}
 void MakeError(const char *s){error=s;}
 void AddCost(Money cost){value+=cost;}
};
struct TileRecord { int kind,type,owner,bits,blocked; TileIndex other; int length,res;
 unsigned char m8; Train reserved; };
struct Map { static TileIndex Size(){return 16;} };
TileRecord map[16];
struct Tile { TileIndex id; Tile(TileIndex i):id(i){} unsigned char &m8() const {return map[id].m8;} };
std::vector<TileIndex> selection;
struct OrthogonalTileArea {
 OrthogonalTileArea(TileIndex,TileIndex){}
 bool Contains(TileIndex t)const{return std::find(selection.begin(),selection.end(),t)!=selection.end();}
};
using DiagonalTileArea=OrthogonalTileArea;
struct TileIterator {
 size_t index=0;
 static std::unique_ptr<TileIterator> Create(TileIndex,TileIndex,bool){return std::make_unique<TileIterator>();}
 operator TileIndex()const{return index<selection.size()?selection[index]:INVALID_TILE;}
 void operator++(){++index;}
};
std::vector<int> free_log;
TileType GetTileType(TileIndex t){
 int k=map[t].kind;return (k>=1 && k<=3)? MP_RAILWAY:(k==6 || k==7)? MP_TUNNELBRIDGE:(k==8 || k==9)?MP_STATION:k;
}
bool HasStationRail(TileIndex t){return map[t].kind==4 || map[t].kind==9;}
bool IsLevelCrossing(TileIndex t){return map[t].kind==5;}
bool IsLevelCrossingTile(TileIndex t){return IsLevelCrossing(t);}
int GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_RAIL;}
int GetRailTileType(TileIndex t){return map[t].kind;}
unsigned GetTileOwner(TileIndex t){return map[t].owner;}
CommandCost CheckTileOwnership(TileIndex t){return map[t].owner==1?CommandCost(0):CommandCost("OWNED_BY_ANOTHER");}
bool IsPlainRailTile(TileIndex t){return map[t].kind==1 || map[t].kind==2;}
TrackBits GetTrackBits(TileIndex t){return map[t].bits;}
CommandCost EnsureNoTrainOnTrackBits(TileIndex,TrackBits){assert(false);return CMD_ERROR;}
CommandCost EnsureNoVehicleOnGround(TileIndex){assert(false);return CMD_ERROR;}
CommandCost TunnelBridgeIsFree(TileIndex,TileIndex){assert(false);return CMD_ERROR;}
TrackBits GetReservedTrackbits(TileIndex t){return map[t].res>=0?1:0;}
Train *GetTrainForReservation(TileIndex t, Track){return map[t].res>=0?&map[t].reserved:nullptr;}
void FreeTrainTrackReservation(Train *t){free_log.push_back(t->id);map[t->id].res=-1;}
void TryPathReserve(Train *,bool){}
bool IsRailStationTile(TileIndex t){return map[t].kind==4;}
bool IsStationTileBlocked(TileIndex t){return map[t].blocked;}
void DirtyCompanyInfrastructureWindows(int){}
void MarkTileDirtyByTile(TileIndex){}
void UpdateTrainPowerProc(){}
void FindVehicleOnPos(TileIndex,TrainList *,void(*)()){}
void YapfNotifyTrackLayoutChange(TileIndex,Track){}
constexpr int WC_VEHICLE_DEPOT=1,WC_BUILD_VEHICLE=2;
void InvalidateWindowData(int,TileIndex){}
Track GetRailDepotTrack(TileIndex){return 0;}
TileIndex GetOtherTunnelBridgeEnd(TileIndex t){return map[t].other;}
bool HasTunnelBridgeReservation(TileIndex t){return map[t].res>=0;}
unsigned GetTunnelBridgeLength(TileIndex t, TileIndex){return map[t].length;}
int GetTunnelBridgeDirection(TileIndex){return 0;}
Track DiagDirToDiagTrack(int d){return d;}
bool IsBridge(TileIndex t){return map[t].kind==6;}
void MarkBridgeDirty(TileIndex){}
Track GetRailStationTrack(TileIndex){return 0;}
Track GetCrossingRailTrack(TileIndex){return 0;}
enum {PR_BUILD_RAIL,PR_CLEAR_RAIL};
Money _price[2]={100,-70};
'''

MAIN = r'''
int main(){
 int cmd;
 while(std::cin>>cmd) {
   if(cmd==0){int m8,r;std::cin>>m8>>r;map[0].m8=m8;std::cout<<GetRailType(Tile{0})<<" ";
     SetRailType(Tile{0},r);std::cout<<int(map[0].m8)<<"\n";}
   if(cmd==1){int f,t;std::cin>>f>>t>>_price[0]>>_price[1];
     auto &i=_railtypes[f];
     std::cout<<IsCompatibleRail(f,t)<<" "<<HasPowerOnRail(f,t)<<" "<<RailBuildCost(f)<<" "<<RailClearCost(f)<<" "
       <<RailConvertCost(f,t)<<" "<<i.powered_railtypes<<" "<<i.compatible_railtypes<<" "<<i.cost_multiplier<<" "
       <<i.maintenance_multiplier<<" "<<i.fallback_railtype<<" "<<i.bridge_offset<<" "<<i.curve_speed<<" "<<i.acceleration<<" "
       <<i.sort_order<<" "<<HasBit(i.flags,RTF_CATENARY)<<"\n";}
   if(cmd==2){
     int hidden,dis,kind,clim,intro,avail,rt;
     std::cin>>_current_company>>_settings_game.game_creation.landscape>>TimerGameCalendar::date>>hidden>>dis;
     _railtypes_hidden_mask=hidden;
     Engine::engines.clear();
     for(int i=0;i<7;++i){
       std::cin>>rt>>kind>>clim>>intro>>avail;
       Engine::engines.push_back({{unsigned(clim)},{{dis && rt==1?0:rt,kind}},unsigned(avail),intro});
     }
     auto types=GetCompanyRailTypes(_current_company,true);
     Company::Get(_current_company)->avail_railtypes=types;
     std::cout<<types;
     for(int i=0;i<4;++i)std::cout<<" "<<ValParamRailType(i);
     std::cout<<"\n";
   }
   if(cmd==3){
     int target,avail,hidden,dis,selected;std::cin>>target>>avail>>hidden>>dis>>selected;
     _current_company=1;_railtypes_hidden_mask=hidden;_settings_game.vehicle.disable_elrails=dis;
     auto *company=Company::Get(1);company->avail_railtypes=avail;
     std::fill(company->infrastructure.rail,company->infrastructure.rail+4,0);
     free_log.clear();selection.clear();_price[0]=100;_price[1]=-70;
     for(int i=0;i<16;++i){
       auto &t=map[i];std::cin>>t.kind>>t.type>>t.owner>>t.bits>>t.blocked>>t.other>>t.length>>t.res;
       t.reserved={t.res,i};t.m8=192|t.type;
       if(HasBit(selected,i))selection.push_back(i);
     }
     if(selection.empty())selection.push_back(0);
     CommandCost q=CmdConvertRail(0,selection.back(),selection.front(),target,false);
     auto a=CmdConvertRail(DC_EXEC,selection.back(),selection.front(),target,false);
     assert(q.error==a.error && q.value==a.value);
     if(q.Failed())std::cout<<q.error;else std::cout<<q.value;
     std::cout<<" "<<company->infrastructure.rail[0]<<" "<<company->infrastructure.rail[1];
     for(int i=0;i<16;++i){
       assert((map[i].m8&192)==192);
       std::cout<<" "<<GetRailType(Tile{unsigned(i)})<<" "<<(std::find(free_log.begin(),free_log.end(),i)!=free_log.end());
     }
     std::cout<<"\n";
   }
   if(cmd==4){int id;std::cin>>id; auto &e=electric[id-23];
     for(int i=0;i<15;++i)std::cout<<(i?" ":"")<<e[i];
     std::cout<<"\n";}
   if(cmd==5){
     int d1,d2;std::cin>>d1>>d2;
     Engine::engines.clear();train_units.resize(4);
     for(int j=0;j<4;++j){
       int rt,power,legacy,mh,art,track;
       std::cin>>rt>>power>>legacy>>mh>>art>>track;
       RailVehicleInfo v{rt,0,rt,uint16_t(power)};
       Engine::engines.push_back({{1},{v},0,42});
       auto &u=train_units[j];u=Train{};
       u.engine_type=j;u.tile=j;map[j].m8=track;u.multiheaded=mh;u.articulated=art;
       if(legacy)SetBit(u.flags,VRF_EL_ENGINE_ALLOWED_NORMAL_RAIL);
       if(j<3)u.next=&train_units[j+1];
     }
     train_units[0].ConsistChanged(CCF_TRACK);
     for(auto disabled:{d1,d2}){
       _settings_game.vehicle.disable_elrails=disabled;
       SettingsDisableElrail(disabled);
       std::cout<<train_units[0].compatible_railtypes;
       for(auto &u:train_units)std::cout<<" "<<u.railtype<<" "<<HasBit(u.flags,VRF_EL_ENGINE_ALLOWED_NORMAL_RAIL)<<" "<<u.GetPower();
       std::cout<<" ";
     }
     std::cout<<"\n";
   }
   if(cmd==6){
     int track,dis,invisible;std::cin>>track>>dis>>invisible;
     _settings_game.vehicle.disable_elrails=dis;invisibility=invisible;
     std::cout<<HasRailCatenaryDrawn(track)<<"\n";
   }
 }
}
'''


def cpp(source):
    rail=src(source,"rail.h")
    map_=src(source,"rail_map.h")
    rt=src(source,"table/railtypes.h")
    railcpp=src(source,"rail.cpp")
    cmds=src(source,"rail_cmd.cpp")
    rows=[]
    def integer(value):
        return int(value, 0)
    for section in re.split(r"\t/\*\* (?:Railway|Electrified railway|Monorail|Maglev) \*/",rt)[1:]:
        def read(key):
            return re.search(r"/\* "+key+r" \*/\s*([^\n]+),",section)[1].strip()
        def mask(key):
            return sum(1<<["RAIL","ELECTRIC","MONO","MAGLEV"].index(k) for k in re.findall(r"RAILTYPES_(\w+)",read(key)))
        def val(k):
            return integer(read(k))
        row=[mask("Powered railtypes"),mask("Compatible [Rr]ailtypes"),val("cost multiplier"),
             val("maintenance cost multiplier"),val("fallback_railtype"),val("bridge offset"),
             val(r"curve speed advantage \(multiplier\)"),val("acceleration type"),(len(rows)<<4)|7,
             2 if read("flags")=="RTFB_CATENARY" else 0,1,-1,0,1<<len(rows)]
        assert read("sort order")==f"{len(rows)} << 4 | 7"
        rows.append("{"+",".join(map(str,row))+"}")
    assert len(rows)==4
    b=CPP+"\nRailTypeInfo _railtypes[4]={"+",".join(rows)+"};\n"
    for name in ("LEVELCROSSING_TRACKBIT_FACTOR","TUNNELBRIDGE_TRACKBIT_FACTOR"):
        b+=re.search(r"static const uint "+name+r" = \d+;",src(source,"economy_type.h"))[0]+"\n"
    for name in ("GetRailType","SetRailType"):
        b+=block(map_,r"^inline .*\b"+name+r"\(")
    for name in ("GetRailTypeInfo","IsCompatibleRail","HasPowerOnRail","RailNoLevelCrossings",
                 "RailBuildCost","RailClearCost","RailConvertCost"):
        b+=block(rail,r"^inline .*\b"+name+r"\(")
    for name in ("HasRailTypeAvail","ValParamRailType","AddDateIntroducedRailTypes","GetCompanyRailTypes"):
        b+=block(railcpp,r"^\w+ "+name+r"\(")
    b+=block(cmds,r"^CommandCost CmdConvertRail\(")
    train_cmd=src(source,"train_cmd.cpp")
    a=train_cmd.index("\t\tif (!u->IsArticulatedPart()) {")
    end=train_cmd.index("\t\t\t/* max speed",a)
    b+=r"""
void Train::ConsistChanged(int){
 this->compatible_railtypes=RAILTYPES_NONE;
 for(Train *u=this;u;u=u->Next())u->railtype=RailVehInfo(u->engine_type)->railtype;
 for(Train *u=this;u;u=u->Next()){
   const RailVehicleInfo *rvi_u=RailVehInfo(u->engine_type);
""" + train_cmd[a:end] + "}}}\n"
    b+=block(src(source,"train.h"),r"^\s*inline uint16_t GetPower\(").replace(
        "inline uint16_t GetPower(", "uint16_t Train::GetPower(")
    b+=block(src(source,"elrail.cpp"),r"^void SettingsDisableElrail\(")
    for name in ("HasRailCatenary", "HasRailCatenaryDrawn"):
        b+=block(src(source,"elrail_func.h"),r"^inline bool "+name+r"\(")
    engines=src(source,"table/engines.h")
    price=src(source,"table/pricebase.h")
    running=int(re.search(r"{\s*(\d+),[^\n]*///< PR_RUNNING_TRAIN_ELECTRIC\b",price)[1])
    rows=[]
    for id in range(23,27):
        info=re.search(fr"^\s*(MT|MM)\(([^)]*)\), //\s+{id} ",engines,re.M)
        intro,decay,life,model,_cargo,climate=map(str.strip,info[2].split(","))
        assert climate=="T"
        row=re.search(fr"^\s*RVI\(([^)]*)\), //\s+{id} ",engines,re.M)
        image,kind,cost,speed,hp,tare,rf,rc,cap,rail,ec=map(str.strip,row[1].split(","))
        assert (rail,rc,ec)==("C","RC_E","E") and (kind=="M")== (info[1]=="MM")
        rows.append("{"+",".join(map(str,[image,cost,speed,hp,tare,rf,intro,decay,life,model,1,cap,int(kind=="M"),1,running]))+"}")
    return b+"\nconst int electric[4][15]={"+",".join(rows)+"};\n"+MAIN


def fixtures():
    rng=random.Random(0x454C524C)
    out=[[0,a,b] for a in range(256) for b in range(64)]
    for rail in (1,7,50,99,100,181,1234,69696):
        for clear in (-1000,-70,-25,-1,0,19):
            out.extend([1,f,t,rail,clear] for f in range(4) for t in range(4))
    for _ in range(1600):
        rec=[[rng.randrange(4),rng.randrange(2),rng.randrange(1,16),rng.randrange(2000),rng.randrange(1<<15)] for _ in range(7)]
        out.append([2,rng.randrange(15),rng.randrange(4),rng.randrange(2000),rng.randrange(16),rng.randrange(2),
                    *(x for row in rec for x in row)])
    for _ in range(3200):
        rec=[]
        for id in range(16):
            kind=rng.choice([0,1,2,3,4,5,8,9])
            rec.append([kind,rng.randrange(2),rng.choices([1,2],[3,1])[0],rng.randrange(1,64),rng.randrange(2),0,0,rng.randrange(-1,2)])
        for a,b in [(3,6),(7,13)]:
            kind=rng.randrange(6,8)
            typ,owner,n=rng.randrange(2),rng.randrange(1,3),rng.randrange(1,8)
            rec[a]=[kind,typ,owner,1,0,b,n,rng.randrange(-1,2)]
            rec[b]=[kind,typ,owner,1,0,a,n,rng.randrange(-1,2)]
        out.append([3,rng.randrange(2),rng.randrange(4),rng.choices([0,1,2,3],[7,1,1,1])[0],
                    rng.randrange(2),rng.randrange(1<<16),*(x for row in rec for x in row)])
    out.extend([4,i] for i in range(23,27))
    for _ in range(1800):
        units=[[rng.randrange(4),rng.randrange(65536),rng.randrange(2),rng.randrange(2),rng.randrange(2),rng.randrange(4)]
               for _ in range(4)]
        out.append([5,rng.randrange(2),rng.randrange(2),*(v for u in units for v in u)])
    out.extend([6,r,d,i] for r in range(4) for d in range(2) for i in range(2))
    return out


if __name__=="__main__":
    source=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    cases=fixtures()
    exchange="\n".join(" ".join(map(str,line)) for line in cases)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)
        (path/"source.cpp").write_text(cpp(source))
        (path/"adapter.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(path/"source.cpp"),"-o",str(path/"source")],check=True)
        ref=subprocess.check_output([str(path/"source")],input=exchange,text=True).splitlines()
        got=subprocess.check_output([lua,str(path/"adapter.lua")],cwd=ROOT,input=exchange,text=True).splitlines()
    assert len(got)==len(ref)==len(cases)
    for case,a,b in zip(cases,ref,got):
        assert a.rstrip()==b,(case,a,b)
    print(f"PASS {len(cases)} pinned stock railtype port cases: m8, masks, prices, engines, conversion quote/exec, power and elrail settings")
