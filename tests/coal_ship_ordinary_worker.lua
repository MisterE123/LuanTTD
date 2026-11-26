-- Actual worker-owned ordinary purchases/refits, native track controllers,
-- mine acceptance and running cash; no injected cargo or fares.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local engine=tonumber(arg and arg[1]) or 211
local capacity=engine==211 and 160 or 190
local partial=arg[2]=="partial"
local owner="Coal dock shipping"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.ship_coal_service,s.ship_paid_service,s.road_coal=true,true,true
local P,R,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local Coal=m("openttd/coal_industry")(P,R,C,I)
local W=m("coal_industry_world")(Sim,T,Coal)
local ids=assert(W.seed(s,Sim.id(12,28),Sim.id(31,28)))
local compose,Endpoint=m("campaign_authority_runtime"),m("campaign_authority_endpoint")
local cap={road={start_year=engine==211 and 1950 or 1985,foster=true,breakdowns=0,service_interval=0},
  ferry={[211]=true,[212]=true},air={}}
local rt,A
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap);A=Endpoint(Sim,rt)
end
mount()
local company=Sim.company(s,owner)
local function commit(rq)
  local quote=A.transport_quote(owner,rq)
  assert(quote.ok,quote.why)
  local r=A.command(owner,{kind="transport_commit",token=quote.value.token,revision=quote.revision})
  assert(r.ok,r.why);return r.value
end
local a=commit({mode="ship",operation="build",kind="dock",tile=Sim.id(12,32)}).id
if partial then assert(commit({mode="ship",operation="build",kind="dock",tile=Sim.id(9,32),adjacent=true,join=a}).id==a) end
local b=commit({mode="ship",operation="build",kind="dock",tile=Sim.id(31,32)}).id
local d=commit({mode="ship",operation="build",kind="depot",tile=Sim.id(17,35),axis=0}).id
local q=assert(rt.transport.depot(owner,"ship",d))
local offer
for _,o in ipairs(q.offers) do if o.request.engine==engine then offer=o end end
assert(offer and offer.price==(engine==211 and 32500 or 36562))
assert(commit(offer.request).id=="coal" and s.stock_coal_ship.cargo==5)
q=assert(rt.transport.depot(owner,"ship",d))
assert(q.vehicles[1].id=="coal" and q.vehicles[1].cargo=="goods")
local refit
for _,o in ipairs(q.offers) do if o.request.operation=="refit" then refit=o end end
assert(refit and refit.price==507)
assert(commit(refit.request).id=="coal" and s.stock_coal_ship.cargo==1)
q=assert(rt.transport.depot(owner,"ship",d))
assert(q.vehicles[1].cargo=="coal")
local start=A.command(owner,{kind="transport_start",mode="ship",cargo="coal",depot=d,vehicle="coal",
  first=a,second=b,revision=s.authority_revision})
assert(start.ok,start.why)
local orders=assert(rt.orders.ship.read(owner,"coal"))
assert(#orders.items==2 and orders.items[1].label:find("mine",1,true))
local function toggle(name)
  return A.command(name,{kind="ship_toggle",vehicle="coal",revision=s.authority_revision})
end
assert(not toggle("Outsider").ok)
assert(toggle(owner).ok and rt.water.coal.status(s).stopped)
assert(toggle(owner).ok and not rt.water.coal.status(s).stopped)

local function copy(t)
  if type(t)~="table" then return t end
  local r={};for k,y in pairs(t) do r[k]=copy(y) end;return r
end
local saved,removed_units
for _=1,850 do
  rt.day()
  local v=rt.water.coal.status(s)
  assert(not v.failure,v.failure)
  if not saved and v.loading and v.onboard>0 and v.onboard<capacity then
    if partial then
      dofile("tests/worker_joined_dock_removal_case.lua")(Sim,A,s,owner,s.stock_coal_ship_run,a)
      removed_units=v.onboard
    end
    s=copy(s);mount()
    assert(rt.water.coal.status(s).onboard==v.onboard)
    saved=true
  end
  if partial and removed_units and v.delivered>0 then
    assert(v.delivered==removed_units and not s.stock_coal_ship_run.dock_forced_leave and v.fare>0)
    print(("PASS coal ship #%d left a removed joined pier after reload and paid exactly %d carried tons"):format(engine,removed_units))
    return
  end
  if v.delivered>=capacity then
    local plant=s.stock_coal_industries[ids.power]
    local c=Sim.company(s,owner)
    assert(saved and v.engine==engine and v.fare>0 and v.running_expense>0 and c.revenue==v.fare)
    assert(s.sites[plant.site].received.coal==capacity and v.delivered==capacity)
    print(("PASS stock cargo ship #%d: real worker depot bought/refitted/sailed %d tons/$%d and restored a partial load"):format(engine,capacity,v.fare))
    return
  end
end
error("Ordinary coal ship never completed a delivery.")
