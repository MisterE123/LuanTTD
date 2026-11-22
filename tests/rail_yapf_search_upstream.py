"""Differential rail search against OpenTTD 14.1 YAPF, costs and heap.

python tests/rail_yapf_search_upstream.py SOURCE_TREE [lua5.1]
The fixture is an ordinary tile grid with two diagonal-direction travel axes.
"""
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from rail_yapf_cost_upstream import cpp as cost_cpp
from rail_track_upstream import ROOT, DIGEST, block, src

DIGEST.update({
    "pathfinder/yapf/yapf_base.hpp":"922aff0edf8f55dc71866f2728870d56bbd29763bc686b85472deb67a7870904",
    "misc/binaryheap.hpp":"0b024d3492a341fc940d82caf5a407323de6bb620cfcc1228f96a8369319e345",
    "pathfinder/yapf/yapf_common.hpp":"ec6efa9f0e4a6b69ad2484aac242125c9a79f41392f5a03d5bcb273423d06f97",
})


def cpp(source):
    r=cost_cpp(source).split("struct List {using Titem=Node;};",1)[0]
    r=r.replace("#include <iostream>","#include <iostream>\n#include <deque>\n#include <map>\n#include <utility>")
    r=r.replace("board[11]", "board[144]")
    r=r.replace("id>=5 && id<=9", "id>=0 && id<144")
    r=r.replace("return d==move_direction?1:-1;","static int delta[]={-1,12,1,-12};return delta[d];")
    r=re.sub(r"int TileX\(TileIndex i\)\{.*?\}\nint TileY\(TileIndex i\)\{.*?\}",
             "int TileX(TileIndex i){return i%12;}\nint TileY(TileIndex i){return i/12;}",r)
    r=r.replace("int speed=103;","int speed=103; int unitnumber=1;")
    r=r.replace("for(int i=5;i<=9;i++)if(Get(i).kind", "for(int i=0;i<144;i++)if(Get(i).kind")
    r=r.replace("struct Settings {","struct Settings {\n int max_search_nodes=10000;")
    r=r.replace("struct Node {",r"""
using YAPFSettings=Settings;
static int _debug_yapf_level=0;
#define Debug(...) ((void)0)
struct DumpTarget {
 template<class T> void WriteStructT(const char*,T*) const {}
 template<class T> void WriteValue(const char*,const T&) const {}
};
using UnitID=int;
template<class T> T *MallocT(size_t n) {return static_cast<T*>(std::malloc(n*sizeof(T)));}
template<class T> T *ReallocT(T *p,size_t n) {return static_cast<T*>(std::realloc(p,n*sizeof(T)));}
struct Node {""")
    r=r.replace(" void SetLastTileTrackdir(TileIndex t,Trackdir td){last_tile=t;last_td=td;}",
                r""" void SetLastTileTrackdir(TileIndex t,Trackdir td){last_tile=t;last_td=td;}
 void Set(Node *p,TileIndex t,Trackdir d,bool choice) {
  m_parent=p;m_key={t,d};last_tile=t;last_td=d;
  if(p){ m_num_signals_passed=p->m_num_signals_passed;flags_u=p->flags_u;
   m_last_red_signal_type=p->m_last_red_signal_type;m_last_signal_type=p->m_last_signal_type; }
  flags_u.flags_s.m_choice_seen|=choice;
 }
 const Key& GetKey()const{return m_key;}
 int GetCost()const{return m_cost;}
 int GetCostEstimate()const{return m_estimate;}
 bool operator<(const Node &o)const{return m_estimate<o.m_estimate;}
""")
    # Settings stub predates the declarations extracted from the pin; use
    # one separate backing value and replace only the shim's member access.
    heap=src(source,"misc/binaryheap.hpp")
    r+=heap[heap.index("#define BINARYHEAP_CHECK"):heap.rindex("#endif")]
    r+=r"""
struct List {
 using Titem=Node;using Key=std::pair<int,int>;
 std::deque<Node> nodes;
 std::map<Key,Node*> open,closed;
 CBinaryHeapT<Node> heap{2};
 static Key key(Node::Key k){return {k.m_tile,k.m_td};}
 Node *CreateNewNode(){nodes.emplace_back();return &nodes.back();}
 Node *FindOpenNode(Node::Key k){auto i=open.find(key(k));return i==open.end()?nullptr:i->second;}
 Node *FindClosedNode(Node::Key k){auto i=closed.find(key(k));return i==closed.end()?nullptr:i->second;}
 void InsertOpenNode(Node &n){open[key(n.GetKey())]=&n;heap.Include(&n);}
 void InsertClosedNode(Node &n){closed[key(n.GetKey())]=&n;}
 void PopOpenNode(Node::Key k){heap.Remove(heap.FindIndex(*open.at(key(k))));open.erase(key(k));}
 int OpenCount()const{return open.size();}
 int ClosedCount()const{return closed.size();}
 void FoundBestNode(Node&){}
 Node *GetBestOpenNode(){return heap.IsEmpty()?nullptr:heap.Begin();}
};
Settings search_settings;
"""
    base=src(source,"pathfinder/yapf/yapf_base.hpp")
    r+=block(base,r"^template <class Types>\s+class CYapfBaseT").replace("&_settings_game.pf.yapf","&search_settings")+";\n"
    origin=src(source,"pathfinder/yapf/yapf_common.hpp")
    r+="template<class Types>\n"+block(origin,r"^class CYapfOriginTileTwoWayT")+";\n"
    r+=r"""
template<bool allow90,bool mask,int target> struct Search;
template<bool allow90,bool mask,int target> struct SearchTypes {
 using Tpf=Search<allow90,mask,target>;
 using TrackFollower=CFollowTrackT<TRANSPORT_RAIL,Train,allow90,mask>;
 using NodeList=List;
 using VehicleType=Train;
};
template<class Ty,int target> using Dest=typename std::conditional<
 target==0,CYapfDestinationTileOrStationRailT<Ty>,typename std::conditional<
 target==1,CYapfDestinationAnyDepotRailT<Ty>,CYapfDestinationAnySafeTileRailT<Ty>>::type>::type;
template<bool a,bool m,int t> struct Search:
 CYapfBaseT<SearchTypes<a,m,t>>,CYapfCostRailT<SearchTypes<a,m,t>>,
 CYapfOriginTileTwoWayT<SearchTypes<a,m,t>>,Dest<SearchTypes<a,m,t>,t> {
 using Ty=SearchTypes<a,m,t>;
 bool PfNodeCacheFetch(Node&){return false;}
 void PfNodeCacheFlush(Node&){}
 void PfFollowNode(Node& n){
  typename Ty::TrackFollower f(this->GetVehicle());
  bool ok=f.Follow(n.last_tile,n.last_td);
  if(ok&&m)ok=f.MaskReservedTracks();
  std::cout<<n.m_key.m_tile<<":"<<int(n.m_key.m_td)<<" ";
  if(ok)this->AddMultipleNodes(&n,f);
 }
 char TransportTypeChar()const{return 't';}
};
template<bool a,bool m,int t> void run(Train &v,int origin,int td,int reverse,int rtd,int reverse_penalty,bool first,int max){
 Search<a,m,t> s;
 s.SetOrigin(origin,Trackdir(td),reverse,Trackdir(rtd),reverse_penalty,first);
 s.SetDestination(&v);
 s.SetMaxCost(max);
 bool ok=s.FindPath(&v);
 std::cout<<"| "<<ok<<" "<<s.m_nodes.ClosedCount()<<" "<<s.m_stopped_on_first_two_way_signal;
 const Node *n=s.GetBestNode();
 for(;n;n=n->m_parent){
  std::cout<<" "<<n->m_key.m_tile<<":"<<int(n->m_key.m_td)<<":"<<n->last_tile<<":"<<int(n->last_td)<<":"<<n->m_cost;
 }
 std::cout<<"\n";
}
template<bool a> void dispatch(Train &v,int d,int origin,int td,int reverse,int rtd,int pen,bool first,int max){
 if(d==3)run<a,false,1>(v,origin,td,reverse,rtd,pen,first,max);
 else if(d==4)run<a,true,2>(v,origin,td,reverse,rtd,pen,first,max);
 else run<a,false,0>(v,origin,td,reverse,rtd,pen,first,max);
}
int main(){
 int cap,forbid,origin,td,reverse,rtd,penalty,dest,target,first,max,complex;
 while(std::cin>>cap>>forbid>>origin>>td>>reverse>>rtd>>penalty>>dest>>target>>first>>max>>complex){
  for(auto &r:board)if(!(std::cin>>r.kind>>r.bits>>r.dir>>r.owner>>r.railtype>>r.station>>r.reserved
      >>r.reserved_bits>>r.slope>>r.present>>r.green>>r.upper>>r.lower))return 1;
  search_settings.max_search_nodes=cap;
  _settings_game.pf.forbid_90_deg=forbid;
  types[0]={0,0,3};types[1]={0,0,3};
  Waypoint::complex_waypoint=complex;
  Train v;v.owner=1;v.railtype=0;v.compatible_railtypes=3;v.tile=origin;
  v.current_order.kind=dest;v.current_order.dest=target;v.dest_tile=target;
  if(forbid)dispatch<false>(v,dest,origin,td,reverse,rtd,penalty,first,max);
  else dispatch<true>(v,dest,origin,td,reverse,rtd,penalty,first,max);
 }
}
"""
    return r

LUA = r"""
local T=dofile("mods/bayline/openttd/rail_track.lua")
local F=dofile("mods/bayline/openttd/rail_follow.lua")(T)
local C=dofile("mods/bayline/openttd/rail_yapf_cost.lua")(T,F)
local S=dofile("mods/bayline/openttd/rail_yapf_search.lua")(T,F,C)
local kinds={[0]="void","rail","signals","crossing","depot","station","waypoint"}
local dx={[0]=-1,12,1,-12}
local types={[0]={compatible={[0]=true,[1]=true}}, {compatible={[0]=true,[1]=true}}}
for line in io.lines() do
  local q={}
  for n in line:gmatch("-?%d+") do q[#q+1]=tonumber(n) end
  local tiles={}
  for i=0,143 do
    local j=13+i*13
    if q[j]~=0 then
      tiles[i]={kind=kinds[q[j]],trackbits=q[j+1],dir=q[j+2],axis=q[j+2]%2,
        owner=q[j+3],railtype=q[j+4],station=q[j+5],reserved=q[j+6]==1,
        reserved_bits=q[j+7],slope=q[j+8],present_signals=q[j+9],green_signals=q[j+10],
        upper_signal_type=q[j+11],lower_signal_type=q[j+12]}
    end
  end
  local board={tile=function(i) return tiles[i] end,adjacent=function(i,side) return i+dx[side] end,
    xy=function(i) return i%12,math.floor(i/12) end,railtype=function(i) return types[i] end}
  function board.station_area(station,kind)
    for i=0,143 do local t=tiles[i];if t and t.station==station and t.kind==kind then return nil,i end end
    return nil,9
  end
  local vehicle={owner=1,railtype=0,compatible=types[0].compatible,tile=q[3],max_speed=103,length=32}
  local dest=C.destination(board,vehicle,{kind=({[0]="tile","station","waypoint","any_depot","safe"})[q[8]],
    tile=q[9],station=q[9],complex=q[12]==1})
  local opts={reverse_origin=q[5]~=-1 and {tile=q[5],td=q[6]} or nil,reverse_penalty=q[7],
    treat_first_red=q[10]==1,max_cost=q[11],visit=function(n) io.write(n.tile,":",n.td," ") end}
  local found,n,stats=S.find(board,vehicle,{tile=q[3],td=q[4]},dest,{max_search_nodes=q[1],forbid_90=q[2]==1},opts)
  io.write("| ",found and 1 or 0," ",stats.closed_count," ",stats.stopped_on_first_two_way and 1 or 0)
  while n do
    io.write(" ",n.tile,":",n.td,":",n.last_tile,":",n.last_td,":",n.cost)
    n=n.parent
  end
  io.write("\n")
end
"""


def maps():
    rng=random.Random(14789)
    def idx(x,y): return y*12+x
    for i in range(1500):
        board=[[0]*13 for _ in range(144)]
        def place(x,y,track=1,kind=1,dir_=0,station=0):
            board[idx(x,y)]=[kind,track,dir_,1,0,station,0,0,0,0,0,0,0]
            return board[idx(x,y)]
        # Two branches, with an exact 45-degree transition on each
        # half-tile and a merge ahead. Space is true 2D stock trackdirs.
        place(2,5);place(3,5,1+32);place(4,5)
        place(3,6,16);place(4,6);place(5,6,4)
        place(5,5,1+8);place(6,5);place(7,5)
        target=idx(8,5)
        mode=rng.choice([1,1,1,2,3,4])
        if mode in (1,2):
            place(8,5,1,5 if mode==1 else 6,0,1)
            target=1
            if mode==1 and i%4==0: place(9,5,1,5,0,1)
        elif mode==3:
            place(8,5,1,4,0)
        else:
            # Next signal marks a good PBS wait immediately before it.
            t=place(8,5,1,2)
            t[9]=4;t[10]=4;t[11]=4
        if i%7 in (1,2,3):
            t=place(4,5,1,2)
            t[9],t[10],t[11]=rng.choice([4,8,12]),rng.choice([0,4,8,12]),rng.randrange(6)
        if i%9==2:
            t=board[idx(4,6)];t[6],t[7]=1,1
        if i%5==3:
            t=board[idx(4,5)];t[4],t[8]=1,rng.choice([3,12])
        if i%4==2:
            place(4,5,1,3)
        # Optional reversed origin has its own nearby alternative depot.
        place(1,5,1,4,2)
        reverse=idx(2,5) if i%3!=0 else -1
        setup=[rng.choice([0,1,2,4,8,10000,10000]),rng.randrange(2),idx(2,5),8,reverse,0,
               rng.randrange(0,900),mode,target,rng.randrange(2),rng.choice([0,0,0,520,2200]),i%2]
        if i%10==7:
            t=place(4,5,1,2)
            t[9],t[10],t[11]=12,0,0
            setup[0],setup[9],setup[10]=10000,1,0
        yield " ".join(map(str,setup+sum(board,[])))


def main():
    inputs=list(maps())
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
            assert a==b,(i,a,b)
    found=sum(line.split(b"|",1)[1].split()[0]==b"1" for line in want)
    stopped=sum(line.split(b"|",1)[1].split()[2]==b"1" for line in want)
    assert found>400 and stopped>20,(found,stopped)
    print(f"PASS: {len(inputs):,} rail YAPF grid searches matched upstream expansion and paths;"
          f" {found:,} found, {stopped:,} first-red states")


if __name__=="__main__":
    main()
