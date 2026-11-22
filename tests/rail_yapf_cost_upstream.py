"""Differential test OpenTTD 14.1 rail YAPF local segment cost and waiting queries.

python tests/rail_yapf_cost_upstream.py SOURCE_TREE [lua5.1]
Uses unchanged C++ cost/destination templates and track follower. The shim
provides synthetic landscape, map state, and orders to those templates.
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_follow_upstream import cpp as follower_cpp
from rail_track_upstream import ROOT, DIGEST, block, declarations, src

DIGEST.update({
    "pathfinder/yapf/yapf_costrail.hpp":"324ca9fdd659eb9a7391ad6b5ad03d908b247156bc3310d4b4df9591a6c0df9c",
    "pathfinder/yapf/yapf_costbase.hpp":"a8599acc9256fd0968144fe37f336c5ee4093d4c0ff6d10995ba7ceb7e37da5f",
    "pathfinder/yapf/yapf_destrail.hpp":"566b321a13cf164b2ed6f2169f7a18722b03c220e5a74c9dcd430459a7ebeb8a",
    "pathfinder/yapf/yapf_type.hpp":"28c0aaad099d4e7e2265306daee7678ff6c5b4b1086d3a288307bad8906baf29",
    "signal_type.h":"c2eceb70a17d3bb0c4ae679394e07e75f6c9ad709e45ca03e2fc32459f895a29",
    "pbs.cpp":"65e7659b7291384e325a63be663a5b8f9a5ddb5e7acace4f5710153a1f616a5b",
})

PENALTIES = dict(
    rail_firstred_twoway_eol=1,rail_firstred_penalty=1000,rail_firstred_exit_penalty=10000,
    rail_lastred_penalty=1000,rail_lastred_exit_penalty=10000,rail_station_penalty=1000,
    rail_slope_penalty=200,rail_curve45_penalty=100,rail_curve90_penalty=600,
    rail_depot_reverse_penalty=5000,rail_crossing_penalty=300,rail_look_ahead_max_signals=10,
    rail_look_ahead_signal_p0=500,rail_look_ahead_signal_p1=-100,rail_look_ahead_signal_p2=5,
    rail_pbs_cross_penalty=300,rail_pbs_station_penalty=800,rail_pbs_signal_back_penalty=1500,
    rail_doubleslip_penalty=100,rail_longer_platform_penalty=800,rail_longer_platform_per_tile_penalty=0,
    rail_shorter_platform_penalty=4000,rail_shorter_platform_per_tile_penalty=0,
)


def cpp(source):
    r = follower_cpp(source).split("template<bool allow90> void run",1)[0]
    r = r.replace("bridge_speed=0,skip=0;", "bridge_speed=0,skip=0,slope=0,present=0,green=0,upper=0,lower=0;")
    r = r.replace("int GetPresentSignals(TileIndex){return 0;}", "int GetPresentSignals(TileIndex i){return Get(i).present;}")
    r = r.replace("int GetSignalStates(TileIndex){return 0;}", "int GetSignalStates(TileIndex i){return Get(i).green;}")
    r = r.replace("bool IsOnewaySignal(TileIndex,Track){return true;}", """int RawSignalType(TileIndex i,Track tr){return tr==TRACK_LOWER||tr==TRACK_RIGHT?Get(i).lower:Get(i).upper;}
bool IsOnewaySignal(TileIndex i,Track tr){return RawSignalType(i,tr)!=4;}""")
    r = r.replace("Slope GetTileSlope(TileIndex){return SLOPE_FLAT;}",
                  "Slope GetTileSlope(TileIndex i){return Get(i).slope;}")
    r = r.replace("int TileX(TileIndex){return 0;}\nint TileY(TileIndex){return 0;}",
                  """int TileX(TileIndex i){return move_direction==DIAGDIR_NE ? 17-i : move_direction==DIAGDIR_SW ? i : 6;}
int TileY(TileIndex i){return move_direction==DIAGDIR_NW ? 17-i : move_direction==DIAGDIR_SE ? i : 6;}""")
    r = r.replace("struct Train {", """using StationID=int;
constexpr StationID INVALID_STATION=-1;
enum {OT_GOTO_TILE,OT_GOTO_STATION,OT_GOTO_WAYPOINT,OT_GOTO_DEPOT,ODATFB_NEAREST_DEPOT=1};
struct Order {
 int kind=OT_GOTO_TILE,dest=0,max_speed=65535;
 bool nearest=false;
 bool IsType(int k)const{return kind==k;}
 int GetType()const{return kind;}
 int GetDestination()const{return dest;}
 int GetMaxSpeed()const{return max_speed;}
 int GetDepotActionType()const{return nearest?ODATFB_NEAREST_DEPOT:0;}
};
struct Train {
 TileIndex tile=5,dest_tile=9;
 RailType railtype=0;
 Order current_order;
 int speed=103;
 int GetDisplayMaxSpeed()const{return speed;}
 struct {int cached_total_length=32;} gcache;""")
    r += declarations(src(source,"signal_type.h"),[r"enum SignalType\s*:",r"enum SignalState\s*\{"])
    r += declarations(src(source,"pathfinder/yapf/yapf_type.hpp"),
                      [r"enum EndSegmentReason\s*\{",r"enum EndSegmentReasonBits\s*\{"])
    r += declarations(src(source,"rail.cpp"),[r"extern const .* "+name for name in (
        "_signal_along_trackdir","_signal_against_trackdir","_next_trackdir","_uphill_trackdirs")])
    r += "struct Settings {\n"+"".join(f" int {name}={val};\n" for name,val in PENALTIES.items())+"};\n"
    r += r"""
BITOPS(EndSegmentReasonBits)
constexpr int YAPF_TILE_LENGTH=100,YAPF_TILE_CORNER_LENGTH=71,TILE_SIZE=16;
constexpr int MP_VOID=MP_CLEAR;
using TileType=int;
bool HasTrackdir(TrackdirBits bits,Trackdir td){return HasBit(bits,td);}
bool IsValidTrackdir(Trackdir td){return td<14&&td%8<6;}
Track TrackdirToTrack(Trackdir td){return Track(td%8);}
bool IsDiagonalTrackdir(Trackdir td){return td%8<2;}
Trackdir NextTrackdir(Trackdir td){return _next_trackdir[td];}
TrackBits DiagdirReachesTracks(DiagDirection d){return TrackdirBitsToTrackBits(DiagdirReachesTrackdirs(d));}
TrackdirBits KillFirstBit(TrackdirBits b){return TrackdirBits(b&(b-1));}
int FindFirstBit(TrackdirBits b){assert(b);return __builtin_ctz(unsigned(b));}
Trackdir FindFirstTrackdir(TrackdirBits b){return Trackdir(FindFirstBit(b));}
Trackdir RemoveFirstTrackdir(TrackdirBits *b) {auto out=FindFirstTrackdir(*b);*b=KillFirstBit(*b);return out;}
bool IsRailDepot(TileIndex i){return Get(i).kind==K_DEPOT;}
bool IsRailDepotTile(TileIndex i){return IsRailDepot(i);}
bool IsRailWaypoint(TileIndex i){return Get(i).kind==K_WAYPOINT;}
bool IsTunnelTile(TileIndex i){return Get(i).kind==K_TUNNEL;}
bool HasTrack(TrackBits bits,Track tr){return HasBit(bits,tr);}
bool HasReservedTracks(TileIndex i,TrackBits bits){return (GetReservedTrackbits(i)&bits)!=0;}
bool HasSignalOnTrackdir(TileIndex i,Trackdir td){
 return Get(i).kind==K_SIGNAL && (Get(i).present & _signal_along_trackdir[td]);
}
SignalType GetSignalType(TileIndex i,Track t){return SignalType(RawSignalType(i,t));}
bool IsPbsSignal(SignalType ty){return ty==SIGTYPE_PBS||ty==SIGTYPE_PBS_ONEWAY;}
SignalState GetSignalStateByTrackdir(TileIndex i,Trackdir td){
 return (Get(i).green & _signal_along_trackdir[td])?SIGNAL_STATE_GREEN:SIGNAL_STATE_RED;
}
bool HasPbsSignalOnTrackdir(TileIndex i,Trackdir td){
 return HasSignalOnTrackdir(i,td)&&IsPbsSignal(GetSignalType(i,TrackdirToTrack(td)));
}
bool HasOnewaySignalBlockingTrackdir(TileIndex i,Trackdir td){
 return HasSignalOnTrackdir(i,ReverseTrackdir(td))&&!HasSignalOnTrackdir(i,td)&&
  IsOnewaySignal(i,TrackdirToTrack(td));
}
bool IsUphillTrackdir(Slope s,Trackdir td){return HasBit(_uphill_trackdirs[s%32],td);}
bool HasBridgeFlatRamp(Slope s,Axis a){
 // A shim for the landscape foundation boundary, allowing true ramp
 // states on legal raw slopes. The unmodified uphill test still drives this.
 return ((s==1||s==2||s==4||s==8||s>=16) ||
   (a==0&&(s==3||s==12)) || (a==1&&(s==6||s==9)));
}
int CeilDiv(int n,int d){return (n+d-1)/d;}
struct Waypoint {
 static Waypoint* Get(StationID){static Waypoint a;return &a;}
 bool IsSingleTile()const{return !complex_waypoint;}
 static bool complex_waypoint;
};
bool Waypoint::complex_waypoint=false;
enum {STATION_RAIL,STATION_WAYPOINT};
TileIndex CalcClosestStationTile(StationID id,TileIndex, int k){
 // Make the station sign the heuristic point on this linear test board.
 for(int i=5;i<=9;i++)if(Get(i).kind==(k==STATION_RAIL?K_STATION:K_WAYPOINT)&&Get(i).station==id)return i;
 return 9;
}
using CFollowTrackRail=CFollowTrackT<TRANSPORT_RAIL,Train,true,false>;
"""
    r += block(src(source,"track_func.h"),r"^inline bool TrackOverlapsTracks")
    for name in ("IsSafeWaitingPosition","IsWaitingPositionFree"):
        r += block(src(source,"pbs.cpp"),rf"^bool {name}\(")
    r += block(src(source,"pathfinder/yapf/yapf_costbase.hpp"),r"^struct CYapfCostBase")+";\n"
    dest=src(source,"pathfinder/yapf/yapf_destrail.hpp")
    r += declarations(dest,[r"class CYapfDestinationRailBase"])
    for name in ("AnyDepot","AnySafeTile","TileOrStation"):
        # Include the original template declaration on the previous line.
        i=dest.index(f"class CYapfDestination{name}RailT")
        r += "template<class Types>\n"+block(dest[i:],rf"^class CYapfDestination{name}RailT")+";\n"
    cost=src(source,"pathfinder/yapf/yapf_costrail.hpp")
    r += "template<class Types>\n"+block(cost,r"^class CYapfCostRailT")+";\n"
    r += r"""
struct Node {
 struct Key {TileIndex m_tile=5;Trackdir m_td=TRACKDIR_X_NE;} m_key;
 struct CachedData{
  int m_cost=-1;
  TileIndex m_last_signal_tile=INVALID_TILE;
  Trackdir m_last_signal_td=INVALID_TRACKDIR;
  EndSegmentReasonBits m_end_segment_reason=ESRB_NONE;
 } data;
 CachedData *m_segment=&data;
 Node *m_parent=nullptr;
 int m_cost=0,m_estimate=0;
 int m_num_signals_passed=0;
 struct {struct {bool m_last_signal_was_red=false,m_choice_seen=false,m_targed_seen=false;}flags_s;}flags_u;
 SignalType m_last_red_signal_type=SIGTYPE_BLOCK,m_last_signal_type=SIGTYPE_PBS;
 TileIndex last_tile=5;
 Trackdir last_td=TRACKDIR_X_NE;
 TileIndex GetLastTile()const{return last_tile;}
 Trackdir GetLastTrackdir()const{return last_td;}
 void SetLastTileTrackdir(TileIndex t,Trackdir td){last_tile=t;last_td=td;}
};
struct List {using Titem=Node;};
template<bool allow90,bool mask,int target> struct Solver;
template<bool allow90,bool mask,int target> struct Types {
 using Tpf=Solver<allow90,mask,target>;
 using TrackFollower=CFollowTrackT<TRANSPORT_RAIL,Train,allow90,mask>;
 using NodeList=List;
};
template<class Ty,int target> using Dest=typename std::conditional<
 target==0,CYapfDestinationTileOrStationRailT<Ty>,typename std::conditional<
 target==1,CYapfDestinationAnyDepotRailT<Ty>,CYapfDestinationAnySafeTileRailT<Ty>>::type>::type;
template<bool allow90,bool mask,int target> struct Solver:
 CYapfCostRailT<Types<allow90,mask,target>>,Dest<Types<allow90,mask,target>,target> {
 using Type=Types<allow90,mask,target>;
 using C=CYapfCostRailT<Type>;
 const Train *train;
 bool pruned=false,treat=true;
 static Settings settings;
 Solver(const Train *t):train(t){this->m_stopped_on_first_two_way_signal=false;}
 const Train* GetVehicle()const{return train;}
 Settings& PfGetSettings(){return settings;}
 bool TreatFirstRedTwoWaySignalAsEOL(){return treat&&settings.rail_firstred_twoway_eol;}
 void PruneIntermediateNodeBranch(Node*){pruned=true;}
};
template<bool a,bool m,int t> Settings Solver<a,m,t>::settings;
template<bool allow90,bool mask,int target> void evaluate(Train &v,Node &parent,int max_cost,bool treat,int choice){
 using Type=Types<allow90,mask,target>;
 typename Type::TrackFollower f(&v);
 bool follow=f.Follow(5,parent.last_td);
 if (mask && follow) follow=f.MaskReservedTracks();
 std::cout<<IsSafeWaitingPosition(&v,5,parent.last_td,true,!allow90)<<" "
          <<IsWaitingPositionFree(&v,5,parent.last_td,!allow90)<<" ";
 if(!follow){std::cout<<"no-child\n";return;}
 Trackdir td=FindFirstTrackdir(f.m_new_td_bits);
 if(choice&&KillFirstBit(f.m_new_td_bits))td=FindFirstTrackdir(KillFirstBit(f.m_new_td_bits));
 Node n;
 n.m_parent=&parent;
 n.m_key={f.m_new_tile,td};n.last_tile=f.m_new_tile;n.last_td=td;
 n.m_num_signals_passed=parent.m_num_signals_passed;
 n.m_last_signal_type=parent.m_last_signal_type;n.m_last_red_signal_type=parent.m_last_red_signal_type;
 n.flags_u=parent.flags_u;
 n.flags_u.flags_s.m_choice_seen|=KillFirstBit(f.m_new_td_bits)!=TRACKDIR_BIT_NONE;
 Solver<allow90,mask,target> p(&v);p.treat=treat;p.SetMaxCost(max_cost);
 p.SetDestination(&v);
 bool ok=p.PfCalcCost(n,&f);
 if (ok) p.PfCalcEstimate(n);
 std::cout<<int(td)<<" "<<ok<<" "<<n.m_cost<<" "<<n.m_estimate<<" "<<n.last_tile<<" "<<int(n.last_td)
  <<" "<<n.data.m_cost<<" "<<n.data.m_end_segment_reason<<" "<<n.data.m_last_signal_tile<<" "<<int(n.data.m_last_signal_td)
  <<" "<<n.m_num_signals_passed<<" "<<int(n.m_last_signal_type)<<" "<<n.flags_u.flags_s.m_last_signal_was_red
  <<" "<<int(n.m_last_red_signal_type)<<" "<<n.flags_u.flags_s.m_targed_seen<<" "<<p.m_stopped_on_first_two_way_signal<<"\n";
}
template<bool a> void dispatch(Train &v,Node &p,int max,bool treat,int choice,int dest) {
 if(dest==3) evaluate<a,false,1>(v,p,max,treat,choice);
 else if(dest==4) evaluate<a,true,2>(v,p,max,treat,choice);
 else evaluate<a,false,0>(v,p,max,treat,choice);
}
int main(){
 int forbid,origin,choice,dest,target_id,max_cost,treat,num,signal,red,was_red,has_choice;
 while(std::cin>>forbid>>origin>>choice>>dest>>target_id>>max_cost>>treat>>num>>signal>>red>>was_red>>has_choice){
  Train v;v.owner=1;v.railtype=0;v.compatible_railtypes=3;
  std::cin>>v.gcache.cached_total_length>>v.speed>>v.current_order.max_speed>>Waypoint::complex_waypoint;
  v.current_order.kind=dest;
  v.current_order.dest=target_id;v.dest_tile=target_id;
  _settings_game.pf.forbid_90_deg=forbid;
  types[0]={0,70,3};types[1]={0,140,3};types[2]={32,50,4};types[3]={16,77,8};
  for(int i=5;i<=9;i++) if(!Read(board[i])||!(std::cin>>board[i].slope>>board[i].present>>board[i].green>>board[i].upper>>board[i].lower))return 2;
  Node p;
  p.last_td=Trackdir(origin);p.m_cost=31;
  p.m_num_signals_passed=num;p.m_last_signal_type=SignalType(signal);p.m_last_red_signal_type=SignalType(red);
  p.flags_u.flags_s.m_last_signal_was_red=was_red;p.flags_u.flags_s.m_choice_seen=has_choice;
  move_direction=TrackdirToExitdir(Trackdir(origin));
  if(forbid)dispatch<false>(v,p,max_cost,treat,choice,dest);else dispatch<true>(v,p,max_cost,treat,choice,dest);
 }
}
"""
    return r

LUA = r"""
local T=dofile("mods/luanttd_core/openttd/rail_track.lua")
local F=dofile("mods/luanttd_core/openttd/rail_follow.lua")(T)
local C=dofile("mods/luanttd_core/openttd/rail_yapf_cost.lua")(T,F)
local names={[0]="void","rail","signals","crossing","depot","station","waypoint","bridge","tunnel"}
local types={[0]={max_speed=70,compatible={[0]=true,[1]=true}},
 {max_speed=140,compatible={[0]=true,[1]=true}},
 {max_speed=50,compatible={[2]=true},disallow_90=true},
 {max_speed=77,compatible={[3]=true},allow_90=true}}
local function yn(b) return b and 1 or 0 end
for line in io.lines() do
  local q={}
  for s in line:gmatch("-?%d+") do q[#q+1]=tonumber(s) end
  local side=T.exit_side(q[2])
  local board={}
  local tiles={}
  for i=0,4 do
    local j=17+i*16
    tiles[5+i]={kind=names[q[j]],trackbits=q[j+1],dir=q[j+2],axis=q[j+2]%2,
      owner=q[j+3],railtype=q[j+4],station=q[j+5],blocked=q[j+6]==1,
      reserved=q[j+7]==1,reserved_bits=q[j+8],bridge_speed=q[j+9],other=9,skip=q[j+10],
      slope=q[j+11],present_signals=q[j+12],green_signals=q[j+13],
      upper_signal_type=q[j+14],lower_signal_type=q[j+15]}
  end
  function board.tile(i) return tiles[i] end
  function board.railtype(i) return types[i] end
  function board.adjacent(i,d) return i+(d==side and 1 or -1) end
  function board.xy(i)
    return side==0 and 17-i or side==2 and i or 6,side==3 and 17-i or side==1 and i or 6
  end
  function board.station_area(id,k)
    for i=5,9 do if tiles[i].kind==k and tiles[i].station==id then return nil,i end end
    return nil,9
  end
  local v={owner=1,railtype=0,compatible={[0]=true,[1]=true},
    length=q[13],max_speed=q[14],order_max_speed=q[15],tile=5}
  local d=C.destination(board,v,{kind=({[0]="tile","station","waypoint","any_depot","safe"})[q[4]],
    tile=q[5],station=q[5],complex=q[16]==1})
  local s={forbid_90=q[1]==1}
  local o={max_cost=q[6],treat_first_red=q[7]==1,mask_reserved=q[4]==4}
  local p=C.node(nil,5,q[2],q[12]==1)
  p.cost,p.signals,p.last_type,p.last_red_type,p.last_red=31,q[8],q[9],q[10],q[11]==1
  local f=F.follow(board,v,5,q[2],s)
  if f.ok and o.mask_reserved then f=F.mask_reserved(board,f) end
  local out={yn(C.safe_waiting(board,v,5,q[2],true,s)),yn(C.waiting_free(board,v,5,q[2],s))}
  if not f.ok then out[#out+1]="no-child"
  else
    local dirs={}
    for td=0,13 do if T.has(f.trackdirs,td) then dirs[#dirs+1]=td end end
    local td=(q[3]==1 and dirs[2]) or dirs[1]
    local n=C.node(p,f.tile,td,#dirs>1)
    local ok=C.calc(board,v,d,n,f,s,o)
    if ok then n.estimate=C.estimate(board,d,n,s) end
    for _,x in ipairs({td,yn(ok),n.cost,n.estimate,n.last_tile,n.last_td,n.segment_cost or -1,n.reason,
      n.last_signal_tile or -1,n.last_signal_td or 255,n.signals,n.last_type,yn(n.last_red),n.last_red_type,
      yn(n.target),yn(n.stopped_on_first_two_way)}) do out[#out+1]=x end
  end
  print(table.concat(out," "))
end
"""


def samples():
    r=random.Random(14183)
    for i in range(12000):
        origin=r.choice([0,1,8,9])
        axis=origin%2
        travel={0:0,1:1,8:2,9:3}[origin]
        signal_group=12
        def t(k=1,sp=None):
            bit=1<<axis
            station=0
            owner=1
            typ=r.choice([0]*8+[1,2])
            reserved=r.randrange(8)==0
            res_bits=0 if r.randrange(6) else bit
            slope=sp if sp is not None else r.choice((0,0,0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30))
            return [k,bit,travel,owner,typ,station,0,int(reserved),res_bits,100,0,slope,
                    r.choice([0,4,8,signal_group]),r.randrange(16),r.randrange(6),r.randrange(6)]
        old=t(1)
        targets=[t(r.choice([1,1,1,2,2,3,5,6,0])) for _ in range(4)]
        dest=r.randrange(5)
        dest_id=9
        if dest==1 or dest==2:
            dest_id=7
            targets[3]=t(5 if dest==1 else 6)
            targets[3][5]=dest_id
            if dest==1 and i%13==3:
                targets[2]=targets[3][:]
        if dest==3:
            targets[3]=t(4)
            targets[3][2]=(travel+2)%4
        count=r.choices([0,1,2,3,4,5,6,7,8,9,10,11,12],[7,1,1,1,1,1,1,1,1,1,1,1,1])[0]
        if i%15==2:
            # A span as the incoming follower move, with a bridge speed cap.
            old=t(7 if i%2 else 8)
            old[10]=3
            targets[3]=old[:]
            targets[3][2]=(travel+2)%4
        if i%17==5:
            # First red two-way at a seen junction: trace prunes branch.
            old=t(1,0);old[4]=0
            targets[0]=t(2,0);targets[0][4]=0
            targets[0][12],targets[0][13],targets[0][14]=12,0,r.randrange(4)
            count=0
        if i%19==7:
            # Forced reversal with the old vehicle facing into its depot.
            old=t(4,0)
            old[2]=(travel+2)%4
        forbid=r.randrange(2)
        if i%29==11:
            # Force a real curve or a 90-degree trigger from the initial
            # oriented half-tile; then end the segment at the next rail fork.
            origin=2
            old=t(1,0);old[1],old[4]=4,0
            targets[0]=t(1,0);targets[0][1],targets[0][4]=16+1,0
            targets[1]=t(1,0);targets[1][1],targets[1][4]=63,0
            forbid=0
        values=[forbid,origin,r.randrange(2),dest,dest_id,r.choice([0]*8+[150,250,600]),
            int(i%17==5 or r.randrange(2)),count,r.randrange(6),r.randrange(6),r.randrange(2),
            int(i%17==5 or r.randrange(2)),r.randrange(5,114),r.randrange(90,150),r.choice([70,80,100,65535]),
            r.randrange(2)]
        yield " ".join(map(str,values+old+sum(targets,[])))


def main():
    inputs=list(samples())
    data=("\n".join(inputs)+"\n").encode()
    with tempfile.TemporaryDirectory() as directory:
        t=Path(directory)
        (t/"ref.cpp").write_text(cpp(Path(sys.argv[1])))
        (t/"compare.lua").write_text(LUA)
        subprocess.run(["c++","-std=c++17","-O2",t/"ref.cpp","-o",t/"ref"],check=True)
        reference=subprocess.run([t/"ref"],input=data,capture_output=True)
        if reference.returncode:
            raise AssertionError((reference.stderr,reference.stdout.count(b"\n")))
        actual=subprocess.run([sys.argv[2] if len(sys.argv)>2 else "lua5.1",t/"compare.lua"],
                              cwd=ROOT,input=data,capture_output=True)
        if actual.returncode:
            raise AssertionError((actual.stderr,actual.stdout.count(b"\n")))
        want,got=reference.stdout.splitlines(),actual.stdout.splitlines()
        assert len(want)==len(got)==len(inputs)
        for i,(a,b) in enumerate(zip(want,got)):
            assert a==b,(i,inputs[i],a,b)
    cases=[tuple(map(int,line.split())) for line in want if not line.endswith(b"no-child")]
    accepted=sum(row[3] for row in cases)
    pruned=sum(row[17] for row in cases)
    targets=sum(row[16] for row in cases)
    assert len(cases)>6000 and accepted>3500 and pruned>50 and targets>300
    print(f"PASS: {len(cases):,} rail YAPF segments across {len(inputs):,} maps, "
          f"{accepted:,} accepted, {targets:,} targets, {pruned:,} first-red branch prunes")


if __name__=="__main__":
    main()
