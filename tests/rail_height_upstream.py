"""Verify stock rail altitude and original acceleration against OpenTTD 14.1.

python tests/rail_height_upstream.py SOURCE_TREE [lua5.1]
Uses unmodified rail height/landscape and GroundVehicle inclination bodies.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
from rail_motion_upstream import cpp as motion_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "landscape.cpp":"0ce068ec5750cf45e1cde2154e9760ec39457da76e0551ad4d6f678880b73d97",
    "slope_func.h":"1fc1187e08e85436ad1b86eaee862fcac907d1f36ced1002e5ae9f7cb0a7795a",
    "ground_vehicle.hpp":"689d301a97c85d16dc37e1761c6352e238363c31cff724c923b8a38745b6d617",
    "train.h":"35ff4a32f95d24f6264ed0cfad0288ce9c8498df472201fb2e47155fea5b1c7d",
})

LUA=r"""
local r="mods/bayline/openttd/"
local T=dofile(r.."rail_track.lua")
local F=dofile(r.."rail_follow.lua")(T)
local H=dofile(r.."rail_height.lua")(T,dofile(r.."slope.lua"))
local Speed=dofile(r.."rail_station_speed.lua")(T,F)
local kinds={[0]="rail","depot","station","crossing","waypoint","signals"}
local count,pixels,steps,revs=0,0,0,0
local profile,previous,old
for line in io.lines() do
  local q={}
  for n in line:gmatch("%-?%d+") do q[#q+1]=tonumber(n) end
  local marker=line:sub(1,1)
  if marker=="p" then
    local kind,shape,trackbits,base,x,y,z=unpack(q)
    local axis=trackbits%2==1 and 0 or 1
    local p=assert(H.profile({kind=kinds[kind],slope=shape,trackbits=trackbits,axis=axis,dir=axis},base))
    assert(H.pixel(p,x,y)==z and H.pixel(p,x+48,y+64)==z,line)
    pixels=pixels+1
  elseif marker=="i" then
    local shape,bits,base,td,direction,x,y,z,up,down=unpack(q)
    profile=assert(H.profile({kind="rail",slope=shape,trackbits=bits},base))
    local pos={td=td,direction=direction,x=x,y=y}
    previous=H.enter(profile,pos)
    assert(previous.z==z and previous.up==(up==1) and previous.down==(down==1),line)
    steps=steps+1
  else
    local td,direction,x,y,z,up,down,prevz,start_speed,max_speed,new_speed=unpack(q)
    local pos={td=td,direction=direction,x=x,y=y}
    local current,old=H.advance(profile,pos,marker=="r" and H.reverse(previous) or previous,false)
    assert(current and current.z==z and current.up==(up==1) and current.down==(down==1) and old==prevz,line)
    local v={speed=start_speed,max_track_speed=max_speed}
    Speed.after_grade(v,old,current.z)
    assert(v.speed==new_speed,line)
    if marker=="r" then revs=revs+1 else previous=current;steps=steps+1 end
  end
end
assert(pixels>150000 and steps>10000 and revs>10000)
print(("PASS: %d height pixels, %d inclinations, %d reversed incline/speed samples matched stock"):format(pixels,steps,revs))
"""


def cpp(source):
    b=motion_cpp(source).split("int main(){",1)[0]
    b="#include <algorithm>\n#include <cstdlib>\n"+b
    types=src(source,"slope_type.h")
    sf=src(source,"slope_func.h")
    cmd=src(source,"rail_cmd.cpp")
    train=src(source,"train_cmd.cpp")
    land=src(source,"landscape.cpp")
    b+=declarations(types,[r"enum Corner\s*\{", r"enum Slope\s*:", r"enum Foundation\s*\{"])
    b+=r"""
#define NOT_REACHED() std::abort()
constexpr int TILE_SIZE=16,TILE_UNIT_MASK=15,TILE_HEIGHT=8,AXIS_X=0;
constexpr inline bool IsInsideMM(int n,int a,int b){return a<=n&&n<b;}
constexpr TrackBits operator|(TrackBits a,TrackBits b){return TrackBits(int(a)|int(b));}
constexpr TrackBits operator&(TrackBits a,TrackBits b){return TrackBits(int(a)&int(b));}
constexpr TrackBits KillFirstBit(TrackBits b){return TrackBits(b & (b-1));}
constexpr TrackBits operator~(TrackBits b){return TrackBits(~int(b));}
constexpr Slope operator^(Slope a,Slope b){return Slope(int(a)^int(b));}
constexpr Slope operator&(Slope a,Slope b){return Slope(int(a)&int(b));}
constexpr Slope operator~(Slope a){return Slope(~int(a));}
template <class T> bool HasBit(T x,int n){return x&(1<<n);}
void SetBit(uint16_t &x,int n){x|=(1<<n);}
void ClrBit(uint16_t &x,int n){x&=~(1<<n);}
DiagDirection DirToDiagDir(Direction d){return DiagDirection(d>>1);}
int DiagDirToAxis(DiagDirection d){return d&1;}
"""
    b+=block(src(source,"track_func.h"),r"^inline bool TracksOverlap")
    names=("IsValidCorner","IsSteepSlope","IsHalftileSlope","RemoveHalftileSlope",
        "ComplementSlope","IsSlopeWithOneCornerRaised","SlopeWithOneCornerRaised","GetHighestSlopeCorner",
        "GetSlopeMaxZ","GetSlopeMaxPixelZ","OppositeCorner","GetHalftileSlopeCorner","IsSlopeWithThreeCornersRaised",
        "SlopeWithThreeCornersRaised","HalftileSlope","IsFoundation","IsLeveledFoundation",
        "IsNonContinuousFoundation","GetHalftileFoundationCorner","IsSpecialRailFoundation",
        "GetRailFoundationCorner","HalftileFoundation","SpecialRailFoundation")
    for n in names:
        b+=block(sf,rf"^(?:static constexpr )?inline \w+ {n}\(")
    b+=declarations(src(source,"rail.cpp"),[r"extern const .* _corner_to_trackbits"])
    b+="TrackBits CornerToTrackBits(Corner c){return _corner_to_trackbits[c];}\n"
    b+=declarations(cmd,[r"static const TrackBits _valid_tracks_without_foundation",
                         r"static const TrackBits _valid_tracks_on_leveled_foundation"])
    b+=block(cmd,r"^Foundation GetRailFoundation")
    b+=block(land,r"^uint ApplyFoundationToSlope")
    b+=block(land,r"^uint GetPartialPixelZ")
    b+=r"""
Slope raw;
int base,kind;
TrackBits trackbits;
Slope GetTilePixelSlope(TileIndex,int *z){*z=base*8;return raw;}
int GetTileMaxPixelZ(TileIndex){return base*8+GetSlopeMaxPixelZ(raw);}
bool IsPlainRail(TileIndex){return kind==0||kind==5;}
bool IsNormalRoad(TileIndex){return false;}
Foundation GetRoadFoundation(Slope,TrackBits){std::abort();}
TrackBits GetAllRoadBits(TileIndex){std::abort();}
TrackBits GetTrackBits(TileIndex){return trackbits;}
uint ApplyPixelFoundationToSlope(Foundation f,Slope *s){return ApplyFoundationToSlope(f,s)*TILE_HEIGHT;}
"""
    b+=block(cmd,r"^static int GetSlopePixelZ_Track")
    b+=block(src(source,"station_cmd.cpp"),r"^static int GetSlopePixelZ_Station")
    b+=block(src(source,"road_cmd.cpp"),r"^static int GetSlopePixelZ_Road")
    b+=r"""
int GetSlopePixelZ(int x,int y,bool ground){
  auto t=TileVirtXY(x,y);
  if(kind==2||kind==4)return GetSlopePixelZ_Station(t,x,y,ground);
  if(kind==3)return GetSlopePixelZ_Road(t,x,y,ground);
  return GetSlopePixelZ_Track(t,x,y,ground);
}
constexpr int GVF_GOINGUP_BIT=0,GVF_GOINGDOWN_BIT=1;
constexpr int AM_ORIGINAL=0;
struct {struct {int train_acceleration_model=AM_ORIGINAL;} vehicle;} _settings_game;
struct {int acceleration_type=0;} _rail_info;
auto *GetRailTypeInfo(int){return &_rail_info;}
template <typename T> struct GroundVehicle : Vehicle {
 int z_pos=0;
 uint16_t gv_flags=0;
 void UpdateViewport(bool,bool){}
"""
    for n in ("UpdateZPositionAndInclination","UpdateZPosition","UpdateInclination"):
        b+=block(src(source,"ground_vehicle.hpp"),rf"^\s*inline \w+ {n}\(")
    b+=r"""
};
struct Train : GroundVehicle<Train> {
 TrackBits track;
 uint16_t cur_speed=0;
 int railtype;
 struct {int cached_max_track_speed=0;} gcache;
 static Train *From(GroundVehicle *v){return static_cast<Train*>(v);}
"""
    b+=block(src(source,"train.h"),r"^\s*inline bool TileMayHaveSlopedTrack")
    b+=block(src(source,"train.h"),r"^\s*inline bool HasToUseGetSlopePixelZ")
    b+="};\n"
    b+=block(train,r"^struct AccelerationSlowdownParams")+";\n"
    b+=declarations(train,[r"static const AccelerationSlowdownParams _accel_slowdown"])
    b+=block(train,r"^static inline void AffectSpeedByZChange")
    b+=r"""
void move_one(char mode,Train &v,GetNewVehiclePosResult next,int td,int seq){
 int initial=(seq*109+int(raw)*17+td*7)%65536;
 int maxspd=(seq*43+int(trackbits)*61)%65536;
 v.cur_speed=initial;v.gcache.cached_max_track_speed=maxspd;
 v.x_pos=next.x;v.y_pos=next.y;
 int old=v.UpdateInclination(false,false);
 AffectSpeedByZChange(&v,old);
 std::cout<<mode<<" "<<td<<" "<<int(v.direction)<<" "<<v.x_pos<<" "<<v.y_pos<<" "<<v.z_pos<<" "
  <<HasBit(v.gv_flags,0)<<" "<<HasBit(v.gv_flags,1)<<" "<<old<<" "<<initial<<" "<<maxspd<<" "<<v.cur_speed<<"\n";
}
int main(){
 int shapes[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30};
 for(int shape:shapes){
  raw=Slope(shape);
  for(int bits=1;bits<64;bits++){
   trackbits=TrackBits(bits);
   base=(shape+bits)%7;
   if(GetRailFoundation(raw,trackbits)==FOUNDATION_INVALID)continue;
   kind=bits%2==0?0:5;
   for(int x=0;x<16;x++)for(int y=0;y<16;y++)
    std::cout<<"p "<<kind<<" "<<shape<<" "<<bits<<" "<<base<<" "<<x<<" "<<y<<" "<<GetSlopePixelZ(x,y,true)<<"\n";
   for(int track=0;track<6;track++){
    if(!(bits&(1<<track)))continue;
    for(int entry=0;entry<4;entry++){
     auto td=_track_enterdir_to_trackdir[track][entry];
     if(td==INVALID_TRACKDIR)continue;
     Train v;v.track=TrackBits(1<<track);v.tile=60+WIDTH*61;v.railtype=0;
     GetNewVehiclePosResult gp{60*16,61*16,v.tile,v.tile};
     v.direction=apply_entry(gp,v.track,DiagDirection(entry));
     v.x_pos=gp.x;v.y_pos=gp.y;
     v.UpdateInclination(true,false);
     std::cout<<"i "<<shape<<" "<<bits<<" "<<base<<" "<<int(td)<<" "<<int(v.direction)<<" "
      <<v.x_pos<<" "<<v.y_pos<<" "<<v.z_pos<<" "<<HasBit(v.gv_flags,0)<<" "<<HasBit(v.gv_flags,1)<<"\n";
     for(int seq=0;;seq++){
      auto reverse=v;
      reverse.direction=Direction((v.direction+4)%8);
      reverse.gv_flags=((v.gv_flags&1)<<1)|((v.gv_flags&2)>>1);
      auto back=GetNewVehiclePos(&reverse);
      if(back.old_tile==back.new_tile)move_one('r',reverse,back,(td+8)%16,seq);
      auto next=GetNewVehiclePos(&v);
      if(next.old_tile!=next.new_tile)break;
      move_one('m',v,next,td,seq);
     }
    }
   }
  }
  base=3;
  for(kind=1;kind<=4;kind++) for(int bits:{1,2}) for(int x=0;x<16;x++)for(int y=0;y<16;y++)
   std::cout<<"p "<<kind<<" "<<shape<<" "<<bits<<" "<<base<<" "<<x<<" "<<y<<" "<<GetSlopePixelZ(x,y,true)<<"\n";
 }
}
"""
    return b


def main():
    source=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/"stock.cpp").write_text(cpp(source))
        (tmp/"port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(tmp/"stock.cpp"),"-o",str(tmp/"stock")],check=True)
        rows=subprocess.check_output([str(tmp/"stock")],cwd=ROOT)
        subprocess.run([lua,str(tmp/"port.lua")],input=rows,check=True,cwd=ROOT)

if __name__=="__main__":
    main()
