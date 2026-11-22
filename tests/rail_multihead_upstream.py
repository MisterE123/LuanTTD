"""Compile OpenTTD 14.1's actual dual-head constructor and normalizer.

python3 tests/rail_multihead_upstream.py /path/to/source [lua5.1]
"""
from pathlib import Path
import random
import subprocess
import sys
import tempfile
from rail_roster_upstream import ROOT, block, src

CPP = r"""
#include <cstdint>
#include <cassert>
#include <iostream>
#include <vector>
enum {TRACK_BIT_DEPOT=1, VS_STOPPED=2, SPR_IMG_QUERY=3, VRF_REVERSE_DIRECTION=4};
enum class BuildProbabilityType { Reversed };
unsigned Random() { return 123; }
template<class T> void SetBit(T &x,unsigned b) {x|=1<<b;}
struct Train {
    int64_t value=0;
    int direction=0,owner=0,tile=0,x_pos=0,y_pos=0,z_pos=0,track=0,vehstatus=0,
        spritenum=0,cargo_type=0,cargo_subtype=0,cargo_cap=0,refit_cap=0,railtype=0,
        engine_type=0,date_of_last_service=0,date_of_last_service_newgrf=0,build_year=0,
        random_bits=0,flags=0,cargo_count=0;
    struct { struct {void Set(int) {}} sprite_seq; } sprite_cache;
    Train *next=nullptr,*previous=nullptr,*other_multiheaded_part=nullptr;
    bool multi=false,engine=false;
    void SetMultiheaded() {multi=true;}
    void SetNext(Train *u) { if(next && next->previous==this) next->previous=nullptr; next=u; if(u) u->previous=this; }
    void UpdatePosition() {}
    bool IsEngine() const {return engine;}
    bool IsMultiheaded() const {return multi;}
    bool IsArticulatedPart() const {return false;}
    Train *Next() const {return next;}
    Train *Previous() const {return previous;}
    Train *GetNextVehicle() const {return next;}
    Train *GetLastEnginePart() {return this;}
    Train *Last() {return next?next->Last():this;}
};
bool TestVehicleBuildProbability(Train*,int,BuildProbabilityType) {return false;}
"""

MAIN = r"""
int main() {
    int n;
    while (std::cin>>n) {
        Train *head=nullptr,*tail=nullptr;
        for (int i=0;i<n;++i) {
            int id,cargo,rear;std::cin>>id>>cargo>>rear;
            auto *v=new Train;
            v->engine_type=id;v->engine=id<27;v->cargo_count=cargo;
            if (id==11) {
                v->value=17187;v->owner=3;v->tile=4;v->vehstatus=VS_STOPPED;v->spritenum=8;v->cargo_cap=38;
                AddRearEngineToMultiheadedTrain(v);
                auto *u=v->other_multiheaded_part;
                assert(u && u->other_multiheaded_part==v && u->Previous()==v && u->owner==3 && u->tile==4);
                assert(!u->IsEngine() && !(u->vehstatus&VS_STOPPED) && u->track==TRACK_BIT_DEPOT);
                u->cargo_count=rear;
            }
            // Live construction initially links the rear directly. Attach
            // the user's following wagon after it, then run the actual
            // source normalizer to obtain the legal final order.
            if (tail) tail->SetNext(v); else head=v;
            tail=v->Last();
        }
        NormaliseDualHeads(head);
        std::vector<Train*> list;
        for (Train *p=head;p;p=p->Next()) list.push_back(p);
        for (Train *p : list) {
            int mate=0;
            if (p->multi) {
                while (list[mate]!=p->other_multiheaded_part) ++mate;
                mate++;
            }
            std::cout<<p->engine_type<<":"<<(p->multi?(p->engine?1:2):0)<<":"<<mate<<":"<<p->cargo_count;
            if (p->multi) std::cout<<":"<<p->value<<":"<<p->spritenum<<":"<<p->cargo_cap;
            std::cout<<" ";
        }
        std::cout<<"\n";
        for (auto *p : list) delete p;
    }
}
"""

LUA = r"""
local R=dofile("mods/luanttd_core/openttd/rail_roster.lua")
for line in io.lines() do
  local n={}
  for s in line:gmatch("%d+") do n[#n+1]=tonumber(s) end
  local parts={}
  for i=1,n[1] do
    local a=2+(i-1)*3
    parts[i]={stock_id=n[a],cargo_count=n[a+1]}
    if n[a]==11 then parts[i].rear_cargo_count=n[a+2] end
  end
  local s=assert(R.stats(parts))
  local out={}
  for i,p in ipairs(s.parts) do
    local half=p.role=="front" and 1 or p.role=="rear" and 2 or 0
    local v={p.stock_id,half,p.mate or 0,p.cargo_count}
    if half>0 then v[#v+1],v[#v+2],v[#v+3]=p.price,p.image_index,p.capacity end
    out[#out+1]=table.concat(v,":")
  end
  io.write(table.concat(out," ").." \n")
end
"""


def main():
    base = Path(sys.argv[1])
    lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
    source = src(base, "train_cmd.cpp")
    names = ("AddRearEngineToMultiheadedTrain", "RemoveFromConsist", "InsertInConsist", "NormaliseDualHeads")
    implementation = CPP + "".join(block(source, rf"^static void {name}\(") for name in names) + MAIN
    rng = random.Random(14111)
    capacity = {0: 0, 8: 0, 11: 38, 15: 0, 27: 40, 29: 30, 30: 30}
    cases = [[11], [11, 27], [11, 29, 11, 27, 30, 0, 11], [0, 27, 11, 11]]
    cases.extend([11, *rng.choices(sorted(capacity), k=rng.randint(0, 24))] for _ in range(3000))
    lines = []
    for case in cases:
        fields = [len(case)]
        for i in case:
            fields += [i, rng.randint(0, capacity[i]), rng.randint(0, 38) if i == 11 else 0]
        lines.append(" ".join(map(str, fields)))
    data = "\n".join(lines) + "\n"
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        (p / "ref.cpp").write_text(implementation)
        (p / "port.lua").write_text(LUA)
        subprocess.run(["g++", "-O2", "-std=c++20", p / "ref.cpp", "-o", p / "ref"], check=True)
        expected = subprocess.check_output([p / "ref"], cwd=ROOT, input=data, text=True).splitlines()
        actual = subprocess.check_output([lua, p / "port.lua"], cwd=ROOT, input=data, text=True).splitlines()
    assert len(actual) == len(expected) == len(cases)
    for case, expect, got in zip(cases, expected, actual):
        assert expect == got, (case, expect, got)
    print(f"PASS: {len(cases)} exact constructor/normalized reciprocal chain comparisons")


if __name__ == "__main__":
    main()
