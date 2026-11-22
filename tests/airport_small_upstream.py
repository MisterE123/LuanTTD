"""Compile pinned OpenTTD 14.1 Small Airport data and controller primitives."""
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SRC=Path(sys.argv[1])
PINS={
    "airport_movement.h":"409e11aa02c4da14273d732bb7ba2c8d3208b793dc715aa9ab3628d42de572a4",
    "airport.h":"0974935317ba5dab84726db1bda1fde0f850111d7ce26a41ceae732bd4a5b448",
    "airport.cpp":"84da932ded4cbe319dc04b37e3bdf6d26e7dc486d17ad7ea216c1f1402d3d722",
    "aircraft_cmd.cpp":"2cbab20d910072dfc2dd490de9032fd9873224c890b7e8160e6cfe1514f96056",
    "aircraft.h":"dcddab039810812ae3a6221b263ebe3dd45284a10296bf7dd3a4e4f8c25fb4ef",
    "vehicle_base.h":"98b6c85830d272fd06d8d760c01f019db84748caab8363c6c121450623e6132e",
}
def read(name):
    for d in ("","src","src/table"):
        p=SRC/d/name
        if p.is_file():
            b=p.read_bytes()
            assert not PINS[name] or sha256(b).hexdigest()==PINS[name],name
            return b.decode()
    raise FileNotFoundError(name)

def block(t,p):
    a=re.search(p,t,re.M).start()
    b=t.index("{",a);d=1
    while d:
        b+=1;d+=(t[b]=="{")-(t[b]=="}")
    return t[a:b+1]

movement=read("airport_movement.h");ap=read("airport.h");airport=read("airport.cpp");cmd=read("aircraft_cmd.cpp")
ac=read("aircraft.h")
tables=[block(movement,p)+";\n" for p in (
    r"^struct AirportFTAbuildup",r"^static const AirportMovingData _airport_moving_data_country",
    r"^static const HangarTileTable _airport_depots_country",r"^static const byte _airport_terminal_country",
    r"^static const byte _airport_entries_country",r"^static const AirportFTAbuildup _airport_fta_country")]
cpp=r"""
#include <cstdint>
#include <cstdio>
#include <cassert>
#include <cstdlib>
#include <algorithm>
using byte=uint8_t;
using uint=unsigned;
using TileIndex=int;
using DirDiff=int;
enum Direction {DIR_N,DIR_NE,DIR_E,DIR_SE,DIR_S,DIR_SW,DIR_W,DIR_NW};
enum DiagDirection {DIAGDIR_NE,DIAGDIR_SE,DIAGDIR_SW,DIAGDIR_NW};
enum {TILE_SIZE=16,XSIZE=64,INVALID_TILE=-1,WC_VEHICLE_VIEW,WID_VV_START_STOP,VS_AIRCRAFT_BROKEN=8,
    VAF_IN_MIN_HEIGHT_CORRECTION=0,VAF_IN_MAX_HEIGHT_CORRECTION,VEH_AIRCRAFT,AIR_HELICOPTER};
#define NOT_REACHED() std::abort()
#define AMD(x,y,flag,dir) {x,y,flag,dir}
#define SETBITS(var,bits) ((var)|=(bits))
#define CLRBITS(var,bits) ((var)&=~(bits))
template<class T> T *MallocT(uint n){return static_cast<T*>(std::malloc(sizeof(T)*n));}
Direction ChangeDir(Direction d,DirDiff diff){return Direction((d+diff)&7);}
DiagDirection ChangeDiagDir(DiagDirection d,int diff){return DiagDirection((d+diff)&3);}
int DiagDirDifference(DiagDirection d1,DiagDirection d2){return (d1-d2)&3;}
DiagDirection DirToDiagDir(Direction d){return DiagDirection(d/2);}
int TileX(int t){return t%XSIZE;}
int TileY(int t){return t/XSIZE;}
void SetWindowWidgetDirty(int,int,int){}
bool HasBit(int v,int b){return v&(1<<b);}
void SetBit(int &v,int b){v|=(1<<b);}
void ClrBit(int &v,int b){v&=~(1<<b);}
struct HangarTileTable{struct{int x,y;}t;Direction d;int id;};
"""+ block(ap,r"^enum AirportMovingDataFlags")+";\n"+block(ap,r"^enum AirportMovementStates")+";\n"+ap[
    ap.index("static const uint64_t\n\tTERM1_block"):ap.index("/** A single location on an airport")]+r"""
constexpr int MAX_ELEMENTS=255;
"""+block(ap,r"^struct AirportMovingData \{")+";\n"+block(ap,r"^struct AirportFTA \{")+";\n"+"\n".join(tables)+r"""
struct AirportFTAClass{AirportFTA *layout;const byte *terminals=_airport_terminal_country;const byte *entry_points=_airport_entries_country;};
struct Station{
   struct {TileIndex tile=134;uint64_t flags=0;} airport;
   TileIndex xy=134;
   static Station *Get(int){static Station s;return &s;}
   static Station *GetIfValid(int i){return Get(i);}
};
struct Vehicle {
  uint16_t cur_speed=0;
  uint progress=0,acceleration=0;
  byte subspeed=0,pos=0,previous_pos=0,state=HANGAR;
  Direction direction=DIR_N;
  int targetairport=0,x_pos=0,y_pos=0,z_pos=0,index=0,vehstatus=0,type=VEH_AIRCRAFT,subtype=255,flags=0;
  struct{int cached_max_speed=320;} vcache;
"""+block(read("vehicle_base.h"),r"^\s*inline uint GetOldAdvanceSpeed\(")+r"""
  static const Vehicle *From(const Vehicle *v){return v;}
};
using Aircraft=Vehicle;
int land=0;
int GetTileHeightBelowAircraft(const Vehicle*){return land;}
struct {struct {int plane_speed=4;} vehicle;} _settings_game;
"""+block(ac,r"^enum AircraftFlyingAltitude")+";\n"+block(cmd,r"^enum AircraftSpeedLimits")+";\n"+ "\n".join(
    block(airport,p) for p in (r"^AirportMovingData RotateAirportMovingData",
        r"^static uint16_t AirportGetNofElements\([^;]*\)\n\{",
        r"^static AirportFTA \*AirportBuildAutomata\([^;]*\)\n\{"))+"\n"+ "\n".join(
    block(cmd,p) for p in (r"^static byte AircraftGetEntryPoint",r"^static int UpdateAircraftSpeed",
        r"^void GetAircraftFlightLevelBounds",
        r"^template <class T>\nint GetAircraftFlightLevel",
        r"^static void AirportClearBlock\([^;]*\)\n\{",
        r"^static bool AirportHasBlock\([^;]*\)\n\{",
        r"^static bool AirportSetBlocks\([^;]*\)\n\{"))+r"""
int main(){
  auto n=AirportGetNofElements(_airport_fta_country);
  auto l=AirportBuildAutomata(n,_airport_fta_country);
  auto a=AirportFTAClass{l};
  auto &flags=Station::Get(0)->airport.flags;
  std::printf("m %d %d %d %d %d\n",n,_airport_depots_country[0].t.x,_airport_depots_country[0].t.y,
          _airport_depots_country[0].d,_airport_terminal_country[1]);
  for(int i=0;i<n;i++){
    for(int r=0;r<8;r+=2){
      auto d=RotateAirportMovingData(&_airport_moving_data_country[i],Direction(r),r%4?3:4,r%4?4:3);
      std::printf("p %d %d %d %d %u %d\n",i,r,d.x,d.y,d.flag,d.direction);
    }
    int row=0;
    for(auto *q=&l[i];q!=nullptr;q=q->next){
      std::printf("t %d %d %d %llu %d\n",i,++row,q->heading,(unsigned long long)q->block,q->next_position);
      for(int b=0;b<16;b++){
        uint64_t value=(b&3)|((b&4)?AIRPORT_BUSY_block:0)|((b&8)?NOTHING_block:0);
        Aircraft v;v.pos=i;v.cur_speed=123;v.subspeed=12;
        flags=value;
        bool has=AirportHasBlock(&v,q,&a);
        unsigned expect_speed=v.cur_speed,expect_sub=v.subspeed;
        v.cur_speed=123;v.subspeed=12;
        bool set=AirportSetBlocks(&v,q,&a);
        std::printf("b %d %d %llu %d %u %u %d %llu %u %u\n",i,row,(unsigned long long)value,has,
            expect_speed,expect_sub,set,(unsigned long long)flags,v.cur_speed,v.subspeed);
      }
    }
    for(int j=0;j<n;j++)for(int b=0;b<16;b++){
      flags=(b&3)|((b&4)?AIRPORT_BUSY_block:0)|((b&8)?NOTHING_block:0);
      Aircraft v;v.previous_pos=i;v.pos=j;
      auto initial=flags;
      AirportClearBlock(&v,&a);
      std::printf("c %d %d %llu %llu\n",i,j,(unsigned long long)initial,(unsigned long long)flags);
    }
  }
  for(int x=-50;x<=50;x+=5)for(int y=-50;y<=50;y+=5)for(int r=0;r<8;r+=2){
      Aircraft v;v.x_pos=6*16+x;v.y_pos=2*16+y;
      std::printf("e %d %d %d %u\n",x,y,r,AircraftGetEntryPoint(&v,&a,Direction(r)));
  }
  for(int d=0;d<8;d++)for(int v=0;v<1600;v+=151)
  for(int sp=1;sp<=4;sp++)for(int accl:{1,12,50})for(int hard=0;hard<2;hard++)
  for(int lim:{50,230,65535})for(int broken=0;broken<2;broken++){
      Aircraft p;p.cur_speed=v;p.subspeed=205;p.progress=122;p.acceleration=accl;p.direction=Direction(d);
      p.vcache.cached_max_speed=651;p.vehstatus=broken?VS_AIRCRAFT_BROKEN:0;
      _settings_game.vehicle.plane_speed=sp;
      auto steps=UpdateAircraftSpeed(&p,lim,hard);
      std::printf("s %d %d %d %d %d %d %d %u %u %u %d\n",d,v,sp,accl,hard,lim,broken,
            p.cur_speed,p.subspeed,p.progress,steps);
  }
  for(land=0;land<150;land+=51)for(int d=0;d<8;d++)for(int y=0;y<=560;y+=17)
  for(int take=0;take<2;take++)for(int f=0;f<4;f++){
      Aircraft p;p.z_pos=y;p.direction=Direction(d);p.flags=f;p.vcache.cached_max_speed=623;
      auto h=GetAircraftFlightLevel(&p,take);
      std::printf("h %d %d %d %d %d %d %d\n",land,d,y,take,f,h,p.flags);
  }
}
"""
lua=r"""
local path="mods/bayline/openttd/"
local A=dofile(path.."airport_small.lua")
local Move=dofile(path.."airport_motion.lua")(A)
local n={m=0,p=0,t=0,b=0,c=0,e=0,s=0,h=0}
for line in io.lines() do
  local op=line:sub(1,1)
  local a={}
  for s in line:gmatch("-?%d+") do a[#a+1]=tonumber(s) end
  n[op]=n[op]+1
  if op=="m" then
    assert(a[1]==#A.points+1 and A.hangar.x==a[2] and A.hangar.z==a[3] and A.hangar.dir==a[4] and a[5]==2,line)
  elseif op=="p" then
    local x,z,flags,d=A.point(a[1],a[2])
    assert(x==a[3] and z==a[4] and flags==a[5] and d==a[6],line)
  elseif op=="t" then
    local q=A.layout[a[1]][a[2]]
    assert(q and q[1]==a[3] and q[2]==a[4] and q[3]==a[5],line)
  elseif op=="b" then
    local v,world={pos=a[1],speed=123,subspeed=12},{flags=a[3]}
    assert(A.has_block(world,v,a[1],a[2])==(a[4]==1) and v.speed==a[5] and v.subspeed==a[6],line)
    v.speed,v.subspeed=123,12
    assert(A.set_blocks(world,v,a[1],a[2])==(a[7]==1) and world.flags==a[8] and v.speed==a[9] and v.subspeed==a[10],line)
  elseif op=="c" then
    local w={flags=a[3]};A.clear_block(w,{previous_pos=a[1],pos=a[2]})
    assert(w.flags==a[4],line)
  elseif op=="e" then
    assert(A.entry(a[1],a[2],0,0,a[3])==a[4],line)
  elseif op=="s" then
    local v={direction=a[1],speed=a[2],acceleration=a[4],subspeed=205,progress=122,max_speed=651,broken=a[7]==1}
    local steps=Move.speed(v,a[6],a[5]==1,a[3])
    assert(v.speed==a[8] and v.subspeed==a[9] and v.progress==a[10] and steps==a[11],line)
  elseif op=="h" then
    local v={direction=a[2],y=a[3],max_speed=623,correct_min=a[5]%2==1,correct_max=a[5]>=2}
    local height=Move.flight_height(v,a[1],a[4]==1)
    local f=(v.correct_min and 1 or 0)+(v.correct_max and 2 or 0)
    assert(height==a[6] and f==a[7],line)
  end
end
assert(n.m==1 and n.p==88 and n.t>30 and n.b==n.t*16 and n.c==7744 and n.e==1764 and n.s==12672 and n.h==6336)
print(("PASS: stock AirportFTA rows %d, coordinates %d, blocks %d, entry points %d, speed/flight states %d"):format(n.t,n.p,n.b+n.c,n.e,n.s+n.h))
"""
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/"reference.cpp").write_text(cpp)
    (p/"verify.lua").write_text(lua)
    subprocess.run(["c++","-std=c++17","-O2",p/"reference.cpp","-o",p/"reference"],check=True)
    expected=subprocess.check_output([p/"reference"])
    subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",p/"verify.lua"],cwd=ROOT,input=expected,check=True)

# Replay the two installed Sampsons' actual movement-point journal. This
# uses the *same persistent reference station words* across rows/actors,
# not resetting an independent mask at each expected event.
if "--pair" in sys.argv[3:]:
    pair_cpp=cpp.split("\nint main(){",1)[0]
    pair_cpp=pair_cpp.replace("struct Station{","struct Station{\n   int owner=1;")
    pair_cpp=pair_cpp.replace("static Station *Get(int){static Station s;return &s;}",
                             "static Station *Get(int id){static Station s[4];assert(id>0 && id<4);return &s[id];}")
    pair_cpp=pair_cpp.replace("int targetairport=0,x_pos","int owner=1,targetairport=0,x_pos")
    pair_cpp=pair_cpp.replace("const byte *entry_points=_airport_entries_country;};",
        "const byte *entry_points=_airport_entries_country;unsigned nofelements=22;};")
    pair_cpp+=r"""
constexpr int OWNER_NONE=-1,VAF_HELI_DIRECT_DESCENT=4;
bool CanVehicleUseStation(const Aircraft*,const Station*){return true;}
void UpdateAircraftCache(Aircraft *){}
#define Debug(...) ((void)0)
#define lengthof(x) (sizeof(x)/sizeof((x)[0]))
using Handler=void(*)(Aircraft *,const AirportFTAClass *);
static Handler _aircraft_state_handlers[256]={};
"""
    pair_cpp+="\n"+"\n".join(block(cmd,p)+(";" if p.startswith(("^struct ","^static const Movement")) else "")
        for p in (
            r"^struct MovementTerminalMapping",r"^static const MovementTerminalMapping _airport_terminal_mapping",
            r"^static bool FreeTerminal\(",r"^static uint GetNumTerminals\(",
            r"^static bool AirportFindFreeTerminal\([^;]*\)\n\{",
            r"^static void AircraftEventHandler_Flying\(",
            r"^static bool AirportMove\([^;]*\)\n\{",
        ))
    pair_cpp+=r"""
int main(){
  auto n=AirportGetNofElements(_airport_fta_country);
  auto l=AirportBuildAutomata(n,_airport_fta_country);
  AirportFTAClass table{l};
  assert(n==22);
  int tick,actor,pass,field,event,pos,prev,state,x,z,y,speed,sub,after_pos,after_state,after_speed,after_sub;
  unsigned long long flags,after_flags;
  int approaches=0,holds=0,stand_assignments=0,arrival_releases=0,rows=0;
  while(std::scanf("%d %d %d %d %d %d %d %d %llu %d %d %d %d %d %llu %d %d %d %d",
          &tick,&actor,&pass,&field,&event,&pos,&prev,&state,&flags,&x,&z,&y,&speed,&sub,
          &after_flags,&after_pos,&after_state,&after_speed,&after_sub)==19){
    auto &mask=Station::Get(field)->airport.flags;
    assert(mask==flags);
    Aircraft v;
    v.targetairport=field;v.pos=pos;v.previous_pos=prev;v.state=state;
    v.cur_speed=speed;v.subspeed=sub;v.x_pos=x;v.y_pos=z;v.z_pos=y;
    AirportClearBlock(&v,&table);
    auto next=[&](){assert(v.state!=l[v.pos].heading);AirportMove(&v,&table);};
    int reference;
    switch(l[v.pos].heading==v.state?v.state:-1){
      case FLYING:
        AircraftEventHandler_Flying(&v,&table);
        reference=v.state==LANDING?8:7;
        if(reference==8)approaches++;else holds++;
        break;
      case ENDLANDING:
        if(AirportHasBlock(&v,&l[v.pos],&table))reference=2;
        else if(AirportFindFreeTerminal(&v,&table)){reference=9;stand_assignments++;}
        else{v.state=HANGAR;reference=10;}
        break;
      case HANGAR:
        if(prev!=pos){v.cur_speed=0;v.subspeed=0;reference=5;break;}
        if(AirportHasBlock(&v,&l[v.pos],&table)){reference=2;break;}
        v.state=TAKEOFF;v.cur_speed=0;v.subspeed=0;next();
        reference=v.pos!=pos?1:2;
        break;
      case TERM1:
      case TERM2:
        if(prev!=pos){reference=6;arrival_releases++;break;}
        if(AirportHasBlock(&v,&l[v.pos],&table)){reference=2;break;}
        v.state=TAKEOFF;next();reference=v.pos!=pos?1:2;break;
      case TAKEOFF: v.state=STARTTAKEOFF;reference=11;break;
      case STARTTAKEOFF: v.state=ENDTAKEOFF;reference=12;break;
      case ENDTAKEOFF:
        v.state=FLYING;reference=13;
        // The already proven GetEntryPoint uses the new field's geometry.
        // Do not compare this source replay before a target switch.
        v.pos=after_pos;
        break;
      case LANDING: v.state=ENDLANDING;reference=14;break;
      default: next();reference=v.pos!=pos?1:2;break;
    }
    if(reference!=event || mask!=after_flags || v.pos!=after_pos || v.state!=after_state ||
       v.cur_speed!=after_speed || v.subspeed!=after_sub){
      std::fprintf(stderr,"Paired mismatch tick %d actor %d pass %d pos %d state %d flags %llu\n"
        "  source %d %llu %u %u %u %u ; port %d %llu %d %d %d %d\n",
        tick,actor,pass,pos,state,flags,reference,(unsigned long long)mask,v.pos,v.state,v.cur_speed,v.subspeed,
        event,after_flags,after_pos,after_state,after_speed,after_sub);
      return 1;
    }
    rows++;
  }
  assert(rows>600 && approaches==4 && holds>0 && stand_assignments==4 && arrival_releases==4);
  assert(Station::Get(1)->airport.flags==TERM1_block && Station::Get(2)->airport.flags==TERM1_block &&
         Station::Get(3)->airport.flags==0);
  std::printf("PASS: %d actual two-aircraft movement-point transitions compiled against 14.1, %d approaches, %d held visits, %d stock terminal releases\n",
    rows,approaches,holds,arrival_releases);
}
"""
    with tempfile.TemporaryDirectory() as d:
        p=Path(d)
        (p/"pair.cpp").write_text(pair_cpp)
        subprocess.run(["c++","-std=c++17","-O2",p/"pair.cpp","-o",p/"pair"],check=True)
        journal=subprocess.check_output([sys.argv[2],"tests/airport_ground_pair.lua","--trace"],cwd=ROOT)
        subprocess.run([p/"pair"],input=journal,check=True)
