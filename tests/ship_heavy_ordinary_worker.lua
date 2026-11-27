-- SPDX-License-Identifier: GPL-2.0-only
-- Stock coastal heavy chain: the Yate carries Iron Ore to a Steel Mill,
-- or carries live steel produced from a separate company’s paid Ore road service.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Endpoint,compose=m("campaign_authority_endpoint"),m("campaign_authority_runtime")
local cargo=assert(arg[1])
assert(cargo=="iron_ore" or cargo=="steel")
local expected_id,owner=cargo=="iron_ore" and 8 or 9,"Heavy Shipping"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=Terrain.new(64,64,function(_,z)return z<20 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<20 and 1 or 0,variant=1,terrain=z<20 and "grass" or "water",
    water_class=z>=20 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
local fixture=dofile("tests/stock_dry_heavy_fixture.lua")
local fixture_ids=fixture.place(Sim,Terrain,s)
local mill_id,factory_id=fixture_ids.mill,fixture_ids.factory
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0,extra={iron_mps=true}},
  ferry={[211]=true},air={},oil_tanker=true}
local A,rt
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap)
  A=Endpoint(Sim,rt)
end
mount()
Sim.company(s,owner)
local function commit(req)
  local q=A.transport_quote(owner,req)
  assert(q.ok,q.why)
  local r=A.command(owner,{kind="transport_commit",token=q.value.token,revision=q.revision})
  assert(r.ok,r.why)
  return r.value,q.value.price
end
local function build(k,x,z)
  local at=Sim.id(x,z)
  local p=commit({mode="ship",operation="build",kind=k,tile=at,axis=k=="depot" and 0 or nil})
  return p.id,at
end
local supply=cargo=="steel" and fixture.supply(Sim,s)
local source,sh=build("dock",cargo=="iron_ore" and 11 or 27,19)
local sink,dh=build("dock",cargo=="iron_ore" and 27 or 46,19)
local depot=build("depot",cargo=="iron_ore" and 20 or 35,24)
local build_cost=s.companies[owner].expense
assert(commit({mode="ship",operation="buy",depot=depot,engine=211}).id=="coal")
local offer
for _,o in ipairs(assert(rt.transport.depot(owner,"ship",depot)).offers) do
  if o.request.operation=="refit" and o.request.cargo==cargo then offer=o;break end
end
assert(offer and offer.price==507,"missing exact "..cargo.." refit")
local r=commit(offer.request)
assert(r.id=="coal" and s.stock_coal_ship.cargo==expected_id and rt.water.coal.status(s).capacity==160)
local depot_ui=assert(rt.transport.depot(owner,"ship",depot))
local Route=m("initial_vehicle_route")
local a,b=Route.targets("ship",depot_ui,depot_ui.vehicles[1])
assert(Route.find(a,source) and Route.find(b,sink) and not Route.find(b,source))
local started=A.command(owner,{kind="transport_start",mode="ship",vehicle="coal",cargo=cargo,depot=depot,
  first=source,second=sink,first_tile=sh,second_tile=dh,revision=s.authority_revision})
assert(started.ok,started.why)
local packing=m("packed_campaign")
local saved=false
local interest=0
for _=1,1200 do
  rt.day()
  if select(3,Sim.date(s))==1 then interest=interest+200 end
  local v=rt.water.coal.status(s)
  assert(not v.failure,v.failure)
  if not saved and v.loading and v.onboard>0 and v.onboard<160 then
    s=assert(packing.decode(assert(packing.encode(s))))
    mount()
    assert(rt.water.coal.status(s).onboard==v.onboard)
    saved=true
  end
  if v.delivered==160 then
    local c=s.companies[owner]
    assert(saved and v.fare>0)
    local receiver=cargo=="iron_ore" and s.stock_heavy_industries[mill_id] or s.stock_farm_industries[factory_id]
    assert(receiver.received[cargo]==160)
    local input=receiver.produced[1]
    assert(input.waiting+input.current.production+input.last.production>0)
    if supply then assert(s.fleet[supply].delivered>0 and s.stock_heavy_industries[mill_id].received.iron_ore>0) end
    assert(c.cash==100000+c.revenue-c.expense and c.paid_units==160 and c.revenue==v.fare)
    assert(c.expense==build_cost+32500+507+v.running_expense+interest)
    print(("PASS stock Yate %s refit: 160 units/$%d to a stock processor through packed mid-load reopen"):format(cargo,v.fare))
    return
  end
end
error("Stock Yate did not pay "..cargo)
