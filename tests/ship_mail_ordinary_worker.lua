-- SPDX-License-Identifier: GPL-2.0-only
-- Real housing produces the mail shipped to a different owned dock.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Endpoint,compose=m("campaign_authority_endpoint"),m("campaign_authority_runtime")
local cargo,expected_id,owner="mail",2,"Mail Shipping"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=Terrain.new(64,64,function(_,z)return z<20 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<20 and 1 or 0,variant=1,terrain=z<20 and "grass" or "water",
    water_class=z>=20 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.ship_paid_service,s.ship_coal_service=true,true
dofile("tests/stock_dry_mail_fixture.lua")(Sim,s)
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},ferry={[211]=true},air={}}
local A,rt
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap)
  A=Endpoint(Sim,rt)
end
mount()
local road_company="Local Post"
local van
if arg[1]=="shared" then
  local line={{8,13,46,13},{8,13,8,12},{8,12,14,12},{14,12,14,13},
    {39,13,39,12},{39,12,46,12},{46,12,46,13}}
  for _,r in ipairs(line) do assert(Sim.build(s,road_company,"road",Sim.line(Sim.id(r[1],r[2]),Sim.id(r[3],r[4])))) end
  local function stop(x)
    local t=Sim.id(x,13);assert(Sim.build_truck_stop(s,road_company,t));return s.tiles[t].station
  end
  local from,to=stop(10),stop(42)
  local depot=Sim.id(23,12)
  assert(Sim.build(s,road_company,"road_depot",{depot}))
  van=assert(Sim.purchase(s,road_company,"mail_van","mail",nil,depot))
  assert(Sim.add_order(s,road_company,van,from))
  assert(Sim.add_order(s,road_company,van,to))
  assert(Sim.toggle(s,road_company,van))
end
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
local source,sh=build("dock",10,19)
local sink,dh=build("dock",42,19)
local depot=build("depot",26,24)
local build_cost=s.companies[owner].expense
assert(commit({mode="ship",operation="buy",depot=depot,engine=211}).id=="coal")
local offer
local expected_refits={coal=true,mail=true,livestock=true,grain=true,wood=true,iron_ore=true,steel=true,valuables=true}
for _,o in ipairs(assert(rt.transport.depot(owner,"ship",depot)).offers) do
  if o.request.operation=="refit" then
    local target=o.request.cargo
    assert(expected_refits[target] and o.price==507,"unexpected default purchase refit")
    expected_refits[target]=nil
    if target==cargo then offer=o end
  end
end
assert(not next(expected_refits),"Stock refit catalog must not depend on local industry")
assert(offer and offer.price==507,"missing exact "..cargo.." refit")
local r=commit(offer.request)
assert(r.id=="coal" and s.stock_coal_ship.cargo==expected_id and rt.water.coal.status(s).capacity==160)
local depot_ui=assert(rt.transport.depot(owner,"ship",depot))
local Route=m("initial_vehicle_route")
local a,b=Route.targets("ship",depot_ui,depot_ui.vehicles[1])
assert(Route.find(a,source) and Route.find(b,sink) and Route.find(b,source))
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
    assert(saved and v.fare>0 and s.sites[2].received.mail>=160)
    if van then
      local road=s.fleet[van]
      assert(road.delivered>0 and s.companies[road_company].paid_units==road.delivered)
      assert(s.companies[road_company].revenue==road.revenue and road.revenue>0)
    else assert(s.sites[2].received.mail==160) end
    local service=s.stock_ship_commercial.service
    assert(service.mail_towns[2]==160 and not service.mail_towns[1] and not s.stock_goods_ship_service)
    assert(service.post_tick==s.passenger_house_clock.counter)
    assert(c.cash==100000+c.revenue-c.expense and c.paid_units==160 and c.revenue==v.fare)
    assert(c.expense==build_cost+32500+507+v.running_expense+interest)
    print(("PASS stock Yate %s refit: 160 units/$%d to a different town through packed mid-load reopen"):format(cargo,v.fare))
    return
  end
end
error("Stock Yate did not pay "..cargo)
