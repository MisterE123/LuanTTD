-- Ordinary stock campaign worker endpoint, including depots, orders and
-- actual refinery fare across a checkpoint remount during loading.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local engine=tonumber(arg and arg[1]) or 204
local capacity=engine==204 and 220 or 350
local owner="Tanker works"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.ship_paid_service,s.road_oil=true,true
local W=assert(Sim.mount_oil_world(s,T,true))
assert(W.place(s,assert(W.plan(s,12,28,31,28))))
local offshore=arg and (arg[2]=="offshore" or arg[2]=="neutral_only")
local rig
if offshore then
  s.stock_serve_neutral_industries=arg[2]~="neutral_only"
  s.next_stock_oil_industry=W.BASE+2
  local center=Sim.id(9,14)
  s.sites[3]={id=3,name="North Reach",kind="town",tile=center,population=280,stock={},produced={},received={},service=0}
  s.tiles[center].site=3
  local builder=m("offshore_rig_world")(Sim,T,m("openttd/oil_rig"),Sim.oil_rules())
  local opts={economy_year=1965,name="North Reach Oil Rig",random=function() return 0 end,initial_random=122}
  rig=assert(builder.place(s,assert(builder.quote(s,Sim.id(12,47),opts)),opts))
  local complete={complete_rig=function(i,t) builder.complete(s,i,t,opts) end}
  for _=1,12 do Sim.oil_rules().tile_loop(rig,rig.tiles[1],complete,function()end) end
  assert(rig.neutral_station)
end
local compose=m("campaign_authority_runtime")
local Endpoint=m("campaign_authority_endpoint")
local cap={road={start_year=engine==204 and (offshore and 1965 or 1950) or 1980,foster=true,breakdowns=0,service_interval=0},ferry={[204]=true,[205]=true},
  air={},oil_tanker=true}
local rt,A
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap)
  A=Endpoint(Sim,rt)
end
mount()
Sim.company(s,owner)
local quote,revision
local function commit(rq)
  quote=A.transport_quote(owner,rq)
  assert(quote.ok,quote.why)
  local r=A.command(owner,{kind="transport_commit",token=quote.value.token,revision=quote.revision})
  assert(r.ok,r.why);revision=r.revision;return r.value
end
local a=rig and rig.neutral_station or commit({mode="ship",operation="build",kind="dock",tile=Sim.id(12,32)}).id
local b=commit({mode="ship",operation="build",kind="dock",tile=Sim.id(31,32)}).id
local d=commit({mode="ship",operation="build",kind="depot",tile=Sim.id(17,35),axis=0}).id
local q=assert(rt.transport.depot(owner,"ship",d))
local offer
for _,o in ipairs(q.offers) do if o.request.engine==engine then offer=o end end
assert(offer and offer.price==(engine==204 and 40625 or 44687))
if engine==204 then
  for _,o in ipairs(q.offers) do assert(o.request.engine~=205,"Later tanker is available too early") end
end
assert(commit(offer.request).id=="oil")
q=assert(rt.transport.depot(owner,"ship",d))
assert(q.vehicles[1].id=="oil" and q.vehicles[1].cargo=="oil")
assert(not A.command(owner,{kind="transport_start",mode="ship",vehicle="oil",cargo="oil",depot=d,first=b,second=a,
  revision=revision}).ok)
assert(A.command(owner,{kind="transport_start",mode="ship",vehicle="oil",cargo="oil",depot=d,first=a,second=b,
  revision=revision}).ok)
local orders=assert(rt.orders.ship.read(owner,"oil"))
assert(#orders.items==2 and orders.items[1].label:find(offshore and "Oil Rig" or "oil",1,true) and orders.items[2].label:find("refinery",1,true))
assert(not rt.orders.ship.read("Outsider","oil"))
if offshore then
  local found=false
  for _,item in ipairs(orders.targets) do
    if item.id==a then found=true; assert(item.label:find("Oil Rig",1,true)) end
  end
  assert(found,"Owner's tanker failed to list the unowned oil rig")
  local t=s.tiles[s.stock_neutral_stations[a].tile]
  local kind,id=m("campaign_order_target")("ship","oil",owner,t.site,t,function(reg,ref) return s[reg][ref] end)
  assert(kind==a and id=="North Reach Oil Rig","in-world selection does not match the list")
end
local function toggle(who)
  return A.command(who,{kind="ship_toggle",vehicle="oil",revision=s.authority_revision})
end
assert(not toggle("Outsider").ok)
assert(toggle(owner).ok and rt.water.tanker.status(s).stopped)
assert(toggle(owner).ok and not rt.water.tanker.status(s).stopped)

local truck
if arg and arg[2]=="mixed" then
  local from,to,dep=Sim.id(13,26),Sim.id(31,26),Sim.id(18,25)
  for _,r in ipairs({{11,26,34,26},{11,26,11,25},{11,25,15,25},{15,25,15,26},
      {29,26,29,25},{29,25,34,25},{34,25,34,26}}) do
    assert(Sim.build(s,owner,"road",Sim.line(Sim.id(r[1],r[2]),Sim.id(r[3],r[4]))))
  end
  assert(Sim.build_truck_stop(s,owner,from));assert(Sim.build_truck_stop(s,owner,to))
  assert(Sim.build(s,owner,"road_depot",{dep}))
  s.road_junction_clearance=true
  truck=assert(Sim.purchase(s,owner,"oil_tanker","oil",nil,dep))
  assert(Sim.add_order(s,owner,truck,s.tiles[from].station))
  assert(Sim.add_order(s,owner,truck,s.tiles[to].station))
  assert(Sim.toggle(s,owner,truck))
end
local saved,viewed=false,false
local function copy(t)
  if type(t)~="table" then return t end
  local x={};for k,v in pairs(t) do x[k]=copy(v) end;return x
end
for _=1,900 do
  rt.day()
  local status=rt.water.tanker.status(s)
  assert(not status.failure,status.failure)
  if not viewed and status.phase=="sailing" then
    assert(rt.company_fleet.vehicle(owner,"ship","oil").label==status.name)
    local pos=assert(rt.company_fleet.locate(owner,"ship","oil"))
    assert(type(pos.x)=="number")
    viewed=true
  end
  if not saved and status.onboard>0 and status.onboard<capacity then
    local t=s.stock_oil_ship_service.tick
    s=copy(s);mount()
    assert(s.stock_oil_ship_service.tick==t and rt.water.tanker.status(s).onboard==status.onboard)
    saved=true
  end
  local lorry=truck and s.fleet[truck]
  if status.delivered>=capacity and (not lorry or lorry.delivered>0) then
    local refinery=s.stock_oil_industries[W.BASE+1]
    local road_units=lorry and lorry.delivered or 0
    local road_fares=lorry and lorry.revenue or 0
    assert(saved and viewed and status.delivered==capacity and refinery.received.oil==capacity+road_units and refinery.was_cargo_delivered)
    assert(status.expense>0 and status.revenue>0 and status.revenue+road_fares==s.companies[owner].revenue)
    if lorry then print(("PASS shared refinery accepted exactly %d ship and %d road kL, no duplicate charge"):format(capacity,road_units)) end
    assert(s.stock_oil_ship_service.post==s.stock_load_tick and s.stock_load_tick==s.passenger_house_clock.counter)
    if offshore and engine==204 then assert(status.revenue==3510) end
    print(("PASS ordinary worker oil tanker #%d (%s): %d kL/$%d, typed controls, live model location and mid-load restore"):format(engine,offshore and "offshore" or "coastal",status.delivered,status.revenue))
    return
  end
end
error("Ordinary tanker never made a paid delivery.")
