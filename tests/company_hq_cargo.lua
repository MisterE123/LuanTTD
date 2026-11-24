local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Rules=load("sim"),load("openttd/terrain"),load("openttd/company_hq_rc1")
local H,P,R=load("openttd/town_passengers"),load("openttd/passengers"),load("openttd/station_rating")
local Town=load("town_passenger_runtime")(Sim,H,P,{random_u32=function() return 0 end,advance=function()end})
local C=load("openttd/station_catchment")(P,R,function() return 0 end,function() return 0 end)
local Codec=load("packed_campaign")
local W=load("water_flood_world")(Sim,Terrain,load("openttd/water_flood"))
Sim.W,Sim.H=64,64
local s=Sim.new(1751)
s.tiles,s.sites={},{}
s.corner_grid=Terrain.new(64,64,function() return 0 end,{freeform_edges=true})
s.stock_generated_profile={width=64,depth=64}
s.stock_town_growth={towns={[1]={}}}
for i=1,64*64 do s.tiles[i]={terrain="grass",h=0,variant=0} end
local company=Sim.company(s,"HQ owner")
local A=load("campaign_authority_endpoint")(Sim,{world=s,landscape=load("campaign_landscape_commands")(Sim,s)})
local origin=Sim.id(18,19)
local view=A.terrain_quote("HQ owner",{operation="company_hq",first=origin})
assert(view.ok and view.value.cost==80 and #view.value.tiles==4 and company.cash==100000)
local done=A.command("HQ owner",{kind="terrain_commit",revision=view.revision,token=view.value.token})
assert(done.ok,done.why)
local hq=s.stock_company_hqs["HQ owner"]
assert(hq.stage==0 and hq.origin==origin and company.cash==99920 and A.company("HQ owner").value.hq.tile==origin)
-- Exhaust the true 256-landscape-tick cycle with controlled byte draws.
-- Each of the actual four registered parcels makes one stock cargo event.
s.road_mail=true
local observed={}
for i=1,4 do
  local function note(_,amount,x,z,record,tick)
    assert(amount==1 and record.source=="HQ owner" and record.source_type=="headquarters" and record.area==2)
    observed[#observed+1]={x=x,z=z,tick=tick}
  end
  Town.day(s,nil,{passenger=note,mail=note})
end
assert(#observed==8)
for j=1,#observed,2 do
  local a,b=observed[j],observed[j+1]
  assert(a.x==b.x and a.z==b.z and a.tick==b.tick)
  assert(Sim.hq_cargo_at(s,Sim.id(a.x+1,a.z+1)))
end
-- A station whose coverage touches the extra 2x2 source area is eligible,
-- even though it does not cover the original generating corner.
local coverage=C.build({id=1,tiles={{x=21,y=22,kind="bus"}}},64,64,true)
assert(not C.contains(coverage,17,18) and C.covers_area(coverage,17,18,2,2))
local goods={rating=175,last_speed=40}
assert(not C.offer({id=1},coverage,"passenger",17,18,function() return goods end))
assert(C.offer({id=1},coverage,"passenger",17,18,function() return goods end,{area=2}))
local dense=C.build({id=1,tiles={{x=18,y=19,kind="rail"}}},64,64,true)
local function acceptance(x,z)
  local mark=Sim.hq_cargo_at(s,Sim.id(x+1,z+1))
  if mark then
    return {hq_acceptance={passenger=Sim.hq_acceptance(mark,"passenger"),mail=Sim.hq_acceptance(mark,"mail")}}
  end
end
assert(C.acceptance(dense,"passenger",acceptance).eighths==4 and not C.acceptance(dense,"passenger",acceptance).accepts)
Sim.stock_economy_money(company,"rail_income",-100000)
Sim.stock_economy_delivered(company,"passenger",40000)
s.day=89 -- April 1 on the stock manual-fixture calendar
Sim.daily(s)
assert(hq.stage==3 and s.tiles[origin].stock_landmark.stage==3)
assert(C.acceptance(dense,"passenger",acceptance).eighths==16 and C.acceptance(dense,"mail",acceptance).eighths==8)
local p={units=3,source="HQ owner",source_type="headquarters"}
s.stations[1]={stock={passenger={p}}}
local sx,sz=Sim.xy(origin)
local sea=Sim.id(sx-1,sz)
s.tiles[sea].terrain="water";s.tiles[sea].water_class="sea"
assert(W.visit(s,sx-1,sz)>0)
assert(not s.stock_company_hqs["HQ owner"] and p.units==3 and not p.source)
for _,id in ipairs(hq.tiles) do assert(not s.tiles[id].stock_landmark and not s.tiles[id].owner) end
local saved=assert(Codec.decode(Codec.encode(s)))
assert(saved.companies["HQ owner"].stock_quarters[1].delivered.passenger==40000)
print("PASS real authority HQ, stock tick production, 2×2 cargo contest, quarter upgrade and full coastal teardown")
