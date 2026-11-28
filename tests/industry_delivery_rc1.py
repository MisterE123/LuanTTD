#!/usr/bin/env python3
"""Compile RC1 DeliverGoodsToIndustry and compare ordered receiving, caps and rights."""
from hashlib import sha256
from pathlib import Path
from random import Random
import subprocess
import sys
from tempfile import TemporaryDirectory

from rc1_rail_foundation_shim import source_block

root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1])/"src"
lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
assert sha256((src/"economy.cpp").read_bytes()).hexdigest()=="e9a41c922184f446fbb25099fb4213b3c50683030d5834c3db7b65af91ab1b6c"
cpp=r"""
#include <algorithm>
#include <array>
#include <iostream>
#include <vector>
using uint=unsigned;
using CargoType=int;
using IndustryID=int;
using CompanyID=int;
constexpr int INVALID_OWNER=-1, THIS_MONTH=0;
enum class SourceType{Industry};
struct Source{int id;SourceType type;};
struct TimerGameEconomy{static constexpr int date=7349;};
struct History{int accepted=0;};
struct Cargo {
    int label;
    unsigned waiting;
    int last_accepted=0;
    std::array<History,1> h{};
    auto &GetOrCreateHistory(){return h;}
};
struct Industry{
    int index,exclusive_supplier,refuses;
    std::array<Cargo,1> accepted;
    auto GetCargoAccepted(int cargo){return accepted[0].label==cargo?accepted.begin():accepted.end();}
};
struct Row {Industry *industry;};
struct Station {int owner; std::array<Row,3> industries_near;};
std::vector<Industry *> _cargo_delivery_destinations;
std::vector<std::pair<int,unsigned>> audit;
void include(std::vector<Industry*>& a,Industry *i){if(std::find(a.begin(),a.end(),i)==a.end())a.push_back(i);}
bool IndustryTemporarilyRefusesCargo(Industry *i,int){return i->refuses;}
void AddCargoDelivery(int type,int company,unsigned amount,Source src,const Station *s,int id){
    if(type!=2 || company!=42 || src.type!=SourceType::Industry || s==nullptr)std::abort();
    audit.emplace_back(id,amount);
}
"""
cpp+=source_block(src,"economy.cpp",r"^static uint DeliverGoodsToIndustry\([^;\n]*\)\n")
cpp+=r"""
int main(){
    int owner,source,always;
    unsigned quantity;
    while(std::cin>>owner>>source>>always>>quantity){
        Industry inds[3]{};
        Station s{owner,{}};
        for(int i=0;i<3;++i){
            auto &ind=inds[i];
            ind.index=i;
            std::cin>>ind.exclusive_supplier>>ind.refuses>>ind.accepted[0].label>>ind.accepted[0].waiting;
        }
        for(auto &r:s.industries_near){int i;std::cin>>i;r.industry=inds+i;}
        _cargo_delivery_destinations.clear();audit.clear();
        auto total=DeliverGoodsToIndustry(&s,2,quantity,source,42);
        std::cout<<total<<" "<<(always?quantity:total)<<" "<<(always?quantity-total:0)<<" ";
        for(auto &i:inds)std::cout<<i.accepted[0].waiting<<" "<<i.accepted[0].last_accepted<<" "<<i.accepted[0].h[0].accepted<<" ";
        for(auto &r:audit)std::cout<<r.first<<" "<<r.second<<" ";
        std::cout<<"-1 ";
        for(auto *i:_cargo_delivery_destinations)std::cout<<i->index<<" ";
        std::cout<<"\n";
    }
}
"""
program=r"""
local D=dofile("mods/luanttd_core/openttd/industry_delivery_rc1.lua")
for line in io.lines() do
  local a={}
  for n in line:gmatch("%S+") do a[#a+1]=tonumber(n) end
  local st={owner=a[1]}
  local inds={}
  for i=0,2 do
    local o,j=a[5+4*i],6+4*i
    inds[i]={id=i,exclusive_supplier=o>=0 and o or nil,refuses=a[j]==1,
      input={cargo=a[j+1],waiting=a[j+2],last_accepted=0,h=0}}
  end
  local destinations,audit={},{}
  local supply,toured=D.to_industries(st,2,a[4],a[2],{{id=a[17]},{id=a[18]},{id=a[19]}},
    function(i)return inds[i] end,function(i,c)if i.input.cargo==c then return i.input end end,
    {economy_date=7349,refuses=function(i)return i.refuses end,
      enqueue=function(i)destinations[#destinations+1]=i.id end,
      history=function(a,v)a.h=a.h+v end,
      monitor=function(s,i,c,v)assert(c==2 and s==st);audit[#audit+1]=i.id;audit[#audit+1]=v end})
  local total,house=D.acceptance_split(a[4],supply,a[3]==1)
  local out={supply,total,house}
  for i=0,2 do local x=inds[i].input;for _,v in ipairs{x.waiting,x.last_accepted,x.h} do out[#out+1]=v end end
  for j,v in ipairs(audit) do out[#out+1]=v end
  for j,r in ipairs(toured) do assert(r.id==audit[2*j-1] and r.units==audit[2*j]) end
  out[#out+1]=-1
  for _,v in ipairs(destinations) do out[#out+1]=v end
  print(table.concat(out," "))
end
"""
rng=Random(16021)
rows=[]
for _ in range(8200):
    row=[rng.randrange(2),rng.randrange(-1,3),rng.randrange(2),rng.choice([0,1,20,32768,65535])]
    for i in range(3):
        row.extend([rng.randrange(-1,2),rng.randrange(2),rng.choice([1,2,2,2]),
                    rng.choice([0,1,32000,65534,65535])])
    row.extend(rng.sample(range(3),3))
    rows.append(row)
data="\n".join(" ".join(map(str,row)) for row in rows)+"\n"
with TemporaryDirectory(prefix="lttd-delivery-rc1-") as tmp:
    d=Path(tmp)
    (d/"ref.cc").write_text(cpp);(d/"test.lua").write_text(program)
    subprocess.run(["c++","-std=c++20","-O2",d/"ref.cc","-o",d/"ref"],check=True)
    a=subprocess.check_output([d/"ref"],text=True,input=data).splitlines()
    b=subprocess.check_output([lua,d/"test.lua"],cwd=root,text=True,input=data).splitlines()
assert len(a)==len(b)==len(rows)
for i,(x,y) in enumerate(zip(a,b)):
    assert x.split()==y.split(),(i,rows[i],x,y)
print(f"PASS {len(rows)} exact RC1 industry delivery, capacity, permission and town/industry split cases")
