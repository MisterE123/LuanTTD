-- Real stock hull, water route, berth loading, industry land loop and
-- receiver ledger. No cargo or company revenue is injected.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,T,P,R,I=m("sim"),m("openttd/terrain"),m("openttd/passengers"),
  m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local St=m("station_rating_runtime")(Sim,R,P)
local Coal=m("openttd/coal_industry")(P,R,C,I)
local Timber=m("openttd/timber_industry")(P,C,R,I,Coal,m("openttd/town_goods"))
local Rules=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),P,C,R,I,Coal,Timber)
local Road=m("road_farm_service")(Sim,Rules,m("oil_industry_runtime")(Rules,m("timber_industry_runtime"),C),
  P,I,R,St,{tag="oil",label="Oil chain",storage="stock_oil_industries",
    vehicles={oil="oil_tanker",goods="goods_truck"},cargo={"oil","goods"}})
local track=m("openttd/rail_track")
local flow=m("openttd/ship_follow")(track)
local network=m("ship_network")(Sim,T,flow,m("openttd/ship_facilities")(track,flow))
local roster=m("openttd/oil_ship_roster")
local Run=m("ship_preview_run")(network,track,flow,m("openttd/ship_yapf")(track,flow,m("openttd/yapf_road_search")),
  m("openttd/ship_motion")(track,flow),m("openttd/ship_regions"),{width=64,height=64,x0=1,z0=1},
  {engine=roster.model(204),engine_for=roster.model,validate_both=true,key="oil_test_route",paid=function()return true end})
local Service=m("ship_oil_service")(Sim,roster,P,R,m("road_loading_runtime"),m("openttd/loading_timing"))
local H=m("openttd/town_passengers")
local engine=tonumber(arg and arg[1]) or 204
local hull=assert(roster.quote(engine))
local s=Sim.new(1751)
s.road_stock_house_supply=true
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
for z=1,64 do for x=1,64 do
  s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
local owner="Stock tanker"
local W=m("oil_industry_world")(Sim,T,Rules)
assert(W.place(s,assert(W.plan(s,12,28,31,28))))
local a=assert(network.build(s,owner,"dock",Sim.id(12,32)))
local b=assert(network.build(s,owner,"dock",Sim.id(31,32)))
local d=assert(network.build(s,owner,"depot",Sim.id(17,35),0))
assert(Run.start(s,owner,d.id,a.id,b.id,nil,engine))
local company=Sim.company(s,owner);company.cash=company.cash-hull.price
s.oil_test_service=Service.new({id=1,engine=engine,built=1950,owner=owner})
s.oil_test_time=H.new_clock(6,6)
local function copy(v)
  if type(v)~="table" then return v end
  local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local state,pipe,service,position
local function bind()
  local map=network.board(s)
  state=s.oil_test_service
  local list,berths=Service.bind_stations(s,state,map)
  assert(#list==2)
  pipe=Road.bind(s,{ship_stations=list})
  service=Service.bind(state,pipe,state.stations,berths,map,{
    charge_fixed=function(who,fixed)
      local c=Sim.company(s,who)
      local old=c.stock_money_fraction or 0
      local rem=(old-fixed%256)%256;c.stock_money_fraction=rem
      local cost=math.floor(fixed/256)+(rem>old and 1 or 0)
      c.cash,c.expense=c.cash-cost,c.expense+cost
    end,
  })
  assert(#service.report(a.id).sources==1 and not service.report(a.id).accepts)
  assert(service.report(b.id).accepts and #service.report(b.id).sources==0)
  position=assert(Run.current(s))
end
bind()
local reloaded,exact_berth=false,false
for _=1,1200 do
  s.day=s.day+1
  service.settle(s.day)
  local function stock_tick(tick)
    assert(service.loading(tick))
    Run.advance_paid(s,{
      arrive=function(run)
        local source=run.last_dock==a.id
        assert(run.last_berth~=s.stock_ship_stations[run.last_dock].water)
        exact_berth=true
        return service.arrive(run.last_dock,run.arrivals,tick,run.last_berth,source and "full" or "no_load")
      end,
      leave=function(run,force) return service.leave(run.arrivals,tick,force) end,
    })
    assert(not position.failure,position.failure)
    assert(service.after(tick));service.rating(tick)
    pipe.after_vehicle_tick(tick)
  end
  local visits=0
  H.advance(s.oil_test_time,74,function(tile,tick)
    pipe.tile_visit(tile%64,math.floor(tile/64),tick)
    visits=(visits+1)%16
    if visits==0 then stock_tick(tick) end
  end)
  if not reloaded and state.vehicle.load_state and state.vehicle.units>0 and state.vehicle.units<hull.capacity then
    local n=state.vehicle.units
    s=copy(s);bind()
    assert(state.vehicle.load_state.slice==10 and state.vehicle.units==n)
    reloaded=true
  end
  if state.vehicle.delivered>=hull.capacity then
    local v,c=state.vehicle,Sim.company(s,owner)
    local refinery=s.stock_oil_industries[W.BASE+1]
    assert(reloaded and exact_berth and v.delivered==hull.capacity)
    assert(refinery.was_cargo_delivered and refinery.received.oil==v.delivered and refinery.accepted[1].waiting==0)
    assert(v.revenue>0 and v.running_fixed>0 and c.cash==100000-hull.price+c.revenue-c.expense)
    assert(c.paid_units==v.delivered and c.revenue==v.revenue)
    print(("PASS oil service contract: #%d sailed stock path and delivered %d kL/$%d after partial-load save"):format(engine,v.delivered,v.revenue))
    return
  end
end
error(("Stock tanker didn't pay: phase=%s aboard=%d delivered=%d day=%d"):format(position.phase,state.vehicle.units,state.vehicle.delivered,s.day))
