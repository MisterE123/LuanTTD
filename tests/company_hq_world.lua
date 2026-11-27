local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Q=load("openttd/company_hq_rc1")
local H=load("company_hq_world")(Sim,Terrain,Q,load("openttd/owned_land")({}))
Sim.W,Sim.H=64,64
local s=Sim.new(1950)
s.tiles,s.sites={},{}
s.stock_generated_profile={width=64,depth=64}
s.stock_town_growth={towns={[1]={}}}
s.corner_grid=Terrain.new(64,64,function() return 1 end,{freeform_edges=true})
for id=1,64*64 do s.tiles[id]={terrain="grass",h=1,variant=0} end
local owner,rival="Builder","Neighbor"
local company=Sim.company(s,owner)
Sim.company(s,rival)
local stats={vehicles={},stations={},min_age=730}
local start=Sim.id(10,10)
local q=assert(H.quote(s,owner,start,stats))
assert(q.cost==80 and q.stage==0 and q.level==1 and #q.tiles==4)
assert(not H.quote(s,owner,start,stats,{[start]=true}))
s.bridge_above={[q.tiles[4].id]=7}
assert(not H.apply(s,owner,start,q,stats))
s.bridge_above=nil
local changed=assert(H.apply(s,owner,start,q,stats))
assert(#changed==4 and not H.quote(s,owner,start,stats) and not H.quote(s,rival,start,stats))
assert(s.stock_company_hqs[owner].stage==0 and company.stock_object_limit==(2048-1)*65536)
H.upgrade(s,owner,721)
H.upgrade(s,owner,0)
assert(s.stock_company_hqs[owner].stage==4 and s.tiles[start].stock_landmark.stage==4)
local nextsite=Sim.id(11,10)
local move=assert(H.quote(s,owner,nextsite,stats))
assert(move.cost==540,move.cost) -- 500 relocation + two grass clears.
changed=assert(H.apply(s,owner,nextsite,move,stats))
assert(#changed==6 and not s.tiles[start].owner and not s.tiles[start].stock_landmark)
assert(s.stock_company_hqs[owner].origin==nextsite and s.stock_company_hqs[owner].stage==0)
assert(s.tiles[Sim.id(12,11)].stock_landmark.part==4)
print("PASS four-tile company HQ purchase, owner checks, one-way stage growth and overlapping relocation")

do
  -- A source-tick finance panel sees provisional input, but must not
  -- replace the stable HQ accounting cache used by an authority edit.
  company.cash=company.loan+10000
  local first=assert(Sim.company_hq_status(s,owner)).value
  s.fleet[77]={owner=owner,engine="bus",bought=s.day,stock_purchase_value=19000}
  local live=assert(Sim.company_hq_status(s,owner,true)).value
  assert(live==first+28500)
  assert(Sim.company_hq_status(s,owner).value==first)
  s.authority_revision=(s.authority_revision or 0)+1
  assert(Sim.company_hq_status(s,owner).value==live)
  print("PASS finance reads between source ticks do not overwrite the HQ accounting cache")
end
