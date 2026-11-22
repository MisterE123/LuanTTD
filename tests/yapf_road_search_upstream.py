#!/usr/bin/env python3
"""Compare YAPF controller and heap to OpenTTD 14.1 on seeded abstract graphs.

Usage: python3 tests/yapf_road_search_upstream.py /path/to/OpenTTD [lua5.1]
Track following, per-segment cost, and estimate are controlled test inputs.
"""
from hashlib import sha256
from pathlib import Path
import random
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
checkout = Path(sys.argv[1])

def read(rel, digest):
    file = next(p for p in [checkout / "src" / rel, checkout / rel, checkout / Path(rel).name]
                if p.is_file())
    raw = file.read_bytes()
    assert sha256(raw).hexdigest() == digest, f"{file}: not pinned OpenTTD 14.1"
    return raw.decode()

base = read("pathfinder/yapf/yapf_base.hpp",
            "922aff0edf8f55dc71866f2728870d56bbd29763bc686b85472deb67a7870904")
heap = read("misc/binaryheap.hpp",
            "0b024d3492a341fc940d82caf5a407323de6bb620cfcc1228f96a8369319e345")
cpp = r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <map>
#include <utility>
using uint=unsigned;
template<class T> T *MallocT(size_t n) {return static_cast<T*>(std::malloc(n*sizeof(T)));}
template<class T> T *ReallocT(T *p,size_t n) {return static_cast<T*>(std::realloc(p,n*sizeof(T)));}
using Trackdir=int;
using TrackdirBits=int;
constexpr int TRACKDIR_BIT_NONE=0, _debug_yapf_level=0;
struct YAPFSettings {int max_search_nodes;};
struct {struct {YAPFSettings yapf;} pf;} _settings_game;
struct DumpTarget {
    template<class T> void WriteStructT(const char*,T*) const {}
    template<class T> void WriteValue(const char*,const T&) const {}
};
using UnitID=int;
constexpr int ESRB_CHOICE_FOLLOWS=1; // Unused by the road specialization.
#define Debug(...) ((void)0)
#define NOT_REACHED() std::abort()
int KillFirstBit(int n){return n&(n-1);}
int FindFirstBit(int n){return __builtin_ctz(unsigned(n));}
int exitdir(int td){
    const int dirs[14]={0,1,0,1,2,1,0,0,2,3,3,2,3,0};
    return dirs[td];
}
bool full;
struct Node {
    using Key=std::pair<int,int>;
    Key m_key;
    Node *m_parent=nullptr;
    int tile,td,m_cost=0,m_estimate=0;
    bool choice;
    void Set(Node *p,int t,int d,bool c){
        m_parent=p; m_key={t,full?d:exitdir(d)}; tile=t; td=d; choice=c;
    }
    auto GetKey() const {return m_key;}
    auto GetCost() const {return m_cost;}
    auto GetCostEstimate() const {return m_estimate;}
    bool operator<(const Node &n) const {return m_estimate<n.m_estimate;}
};
"""
cpp += heap[heap.index("#define BINARYHEAP_CHECK"):heap.rindex("#endif")]
cpp += r"""
struct List {
    using Titem=Node;
    std::deque<Node> nodes;
    std::map<Node::Key,Node*> open,closed;
    CBinaryHeapT<Node> heap{2};
    Node *CreateNewNode(){ nodes.emplace_back(); return &nodes.back(); }
    Node *FindOpenNode(Node::Key k){ auto i=open.find(k); return i==open.end()?nullptr:i->second; }
    Node *FindClosedNode(Node::Key k){ auto i=closed.find(k); return i==closed.end()?nullptr:i->second; }
    void InsertOpenNode(Node &n){open[n.GetKey()]=&n;heap.Include(&n);}
    void InsertClosedNode(Node &n){closed[n.GetKey()]=&n;}
    void PopOpenNode(Node::Key k){heap.Remove(heap.FindIndex(*open.at(k)));open.erase(k);}
    int OpenCount() const {return open.size();}
    int ClosedCount() const {return closed.size();}
    void FoundBestNode(Node&) {}
    Node *GetBestOpenNode(){return heap.IsEmpty()?nullptr:heap.Begin();}
};
struct Follower{int m_new_tile,m_new_td_bits;};
struct Vehicle{int unitnumber;};
struct Run;
struct Types {using Tpf=Run; using TrackFollower=Follower; using NodeList=List; using VehicleType=Vehicle;};
"""
cpp += base[base.index("template <class Types>"):base.rindex("#endif")]
cpp += r"""
struct Row{int cost,next,bits;};
struct Run: CYapfBaseT<Types> {
    int dest,origin_bits;
    Row rows[32][14]{};
    bool PfNodeCacheFetch(Node&){return false;}
    void PfNodeCacheFlush(Node&){}
    bool PfCalcCost(Node& n,const Follower*) {
        auto cost=rows[n.tile][n.td].cost;
        n.m_cost=n.m_parent->m_cost+cost;return cost>=0;
    }
    bool PfCalcEstimate(Node& n) {n.m_estimate=n.m_cost;return true;}
    bool PfDetectDestination(Node& n){return n.tile==dest;}
    void PfSetStartupNodes(){
        for (int b=origin_bits;b;b=KillFirstBit(b)) {
            Node &n=CreateNewNode();n.Set(nullptr,0,FindFirstBit(b),KillFirstBit(origin_bits)!=0);
            AddStartupNode(n);
        }
    }
    void PfFollowNode(Node& n){
        std::cout<<n.tile<<':'<<n.td<<' ';
        auto t=rows[n.tile][n.td];
        if(t.next>=0){Follower f{t.next,t.bits};AddMultipleNodes(&n,f);}
    }
    char TransportTypeChar() const {return 'r';}
};
int main(){
    constexpr int tds[]={0,1,2,3,4,5,8,9,10,11,12,13};
    int n,d,org,cap;
    while(std::cin>>n>>d>>org>>cap>>full){
        _settings_game.pf.yapf.max_search_nodes=cap;
        Run r;r.dest=d;r.origin_bits=org;
        for(int i=0;i<n;i++)for(int t:tds){
            Row &row=r.rows[i][t];std::cin>>row.cost>>row.next>>row.bits;
        }
        Vehicle v{};
        bool ok=r.FindPath(&v);
        std::cout<<"| "<<ok<<' '<<r.m_nodes.ClosedCount();
        for(Node *node=r.GetBestNode();node;node=node->m_parent){
            std::cout<<' '<<node->tile<<':'<<node->td<<':'<<node->m_cost;
        }
        std::cout<<'\n';
    }
}
"""
lua = r"""
local F=dofile("mods/luanttd_core/openttd/yapf_road_follow.lua")
local C={}
local S=dofile("mods/luanttd_core/openttd/yapf_road_search.lua")(F,C)
local function r() return assert(io.read("*n")) end
local tds={0,1,2,3,4,5,8,9,10,11,12,13}
while true do
  local n=io.read("*n")
  if not n then break end
  local dest,org,cap,full=r(),r(),r(),r()
  local rows={}
  for i=0,n-1 do
    rows[i]={}
    for _,t in ipairs(tds) do rows[i][t]={cost=r(),tile=r(),trackdirs=r()} end
  end
  F.follow=function(_,_,tile,td)
    io.write(tile,":",td," ")
    local t=rows[tile][td]
    t.ok=t.tile>=0
    return t
  end
  C.calc=function(_,_,_,node)
    local cost=rows[node.tile][node.td].cost
    node.cost=node.parent.cost+cost
    return cost>=0
  end
  C.estimate=function(_,_,node) return node.cost end
  C.detect=function(_,d,tile) return d==tile end
  local ok,best,stats=S.find({}, {},0,org,dest,{max_search_nodes=cap,disable_node_optimization=full==1})
  io.write("| ",ok and 1 or 0," ",stats.closed_count)
  while best do
    io.write(" ",best.tile,":",best.td,":",best.cost)
    best=best.parent
  end
  io.write("\n")
end
"""
rng = random.Random(931)
tds = [0,1,2,3,4,5,8,9,10,11,12,13]
cases = []
for i in range(10000):
    n = rng.randint(3,30)
    def choices(high):
        return sum(1 << t for t in rng.sample(tds, rng.randint(1,high)))
    case = [n, rng.choice([-1,n-1,n-1,n-1]), choices(6),
            rng.choice([0,1,1,5,12,10000,10000,10000]), i % 2]
    for t in range(n):
        for td in tds:
            nxt = -1 if t == n-1 or rng.randrange(12)==0 else min(t+rng.randint(1,4),n-1)
            # Small range deliberately exercises ties and replacement of open nodes.
            case += [rng.randint(-1,4)*10, nxt, choices(5)]
    cases.append(" ".join(map(str,case)))
payload = ("\n".join(cases)+"\n").encode()
with tempfile.TemporaryDirectory() as tmp:
    w = Path(tmp)
    (w / "main.cpp").write_text(cpp)
    (w / "main.lua").write_text(lua)
    subprocess.run(["c++", "-std=c++17", "-O2", str(w/"main.cpp"), "-o", str(w/"oracle")], check=True)
    def run(args):
        return subprocess.check_output(args, input=payload, cwd=root).decode().splitlines()
    oracle = run([w / "oracle"])
    port = run([sys.argv[2] if len(sys.argv)>2 else "lua5.1", w / "main.lua"])
    assert len(oracle) == len(port) == len(cases)
    for i,(expected,actual) in enumerate(zip(oracle,port)):
        assert expected==actual, (i,expected,actual)
    print(f"PASS: {len(cases):,} pinned YAPF search/heap expansion and best-path comparisons")
