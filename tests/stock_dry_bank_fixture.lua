-- SPDX-License-Identifier: GPL-2.0-only
-- Two real Temperate banks founded into separate existing coastal towns.
local B={}
function B.houses(Sim,s,Growth)
  local id=Sim.id
  s.stock_generated_profile=s.stock_generated_profile or {width=64,depth=64}
  s.sites={{id=1,kind="town",name="Banktown",tile=id(8,15),population=1500,stock={},received={},produced={},service=0},
    {id=2,kind="town",name="Stationfield",tile=id(45,15),population=1500,stock={},received={},produced={},service=0}}
  s.stock_town_growth={version=1,order={},towns={}}
  for _,p in ipairs(s.sites) do
    local q=Growth.new(p.id,Sim.xy(p.tile))
    q.population,q.num_houses,q.house_counts=1500,2,{[0x06]=2}
    s.stock_town_growth.towns[p.id]=q
  end
  for _,p in ipairs({{10,15,1},{11,15,1},{42,15,2},{43,15,2}}) do
    local t=s.tiles[id(p[1],p[2])]
    t.house=true
    t.source_house={id=0x06,root=true,completed=true,town_growth=true,town=p[3],x=p[1],z=p[2]}
  end
end
function B.fund(Sim,s,A)
  local trust="Coastal Bank Trust"
  local c=Sim.company(s,trust)
  c.cash=3000000
  for _,x in ipairs({10,42}) do
    local p={tool="fund_bank",first=Sim.id(x,15)}
    local quote=A.road_quote(trust,p)
    assert(quote.ok,quote.why)
    local r=A.command(trust,{kind="road_commit",request=p,quote=quote.value,revision=quote.revision})
    assert(r.ok,r.why)
    assert(#r.value==2)
  end
  assert(c.expense==2*996093 and Sim.road_bank_active(s))
end
return B
