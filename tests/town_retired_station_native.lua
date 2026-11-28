-- Real owner worker crosses two monthly stock ticks after road, rail and
-- air facilities are physically removed. Their signs live until big tick 8.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,T,G=m("sim"),m("openttd/terrain"),m("openttd/town_growth")
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
Sim.W,Sim.H=64,64
local s=Sim.new(4841)
local tile=Sim.id(18,20)
local verify_reopen=core.settings:get("luanttd_qa_municipal_kind")=="reopened"
local verify_rail=core.settings:get("luanttd_qa_municipal_kind")=="rail-reopened"
local verify_air=core.settings:get("luanttd_qa_municipal_kind")=="air-reopened"
local target=Sim.id(19,20)
local owner="Builder"
s.corner_grid=T.new(64,64,function()return 1 end)
s.stock_generated_profile={width=64,depth=64,map_height_limit=30,town_settings={growth_setting=2}}
s.road_stock_clock,s.road_economy,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.stock_pool_authority=true
Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),1950)
s.day=30
s.passenger_house_clock=m("openttd/town_passengers").new_clock(6,6,nil,1280+s.day*74)
for id in ipairs(s.tiles) do s.tiles[id]={terrain="grass",h=1,variant=1} end
s.sites={{id=1,kind="town",name="Clocktown",tile=tile,population=0,stock={},produced={},received={}}}
s.stock_town_growth={version=1,order={1},towns={G.new(1,18,20,{grow_counter=1000})}}
for x=15,21 do assert(Sim.town_road_piece(s,1,Sim.id(x,20),10,true)) end
Sim.company(s,owner)
local construction=m("campaign_road_construction")(Sim,s)
assert(construction.commit(owner,{tool="stock_terminal_auto",first=tile,kind="bus"},nil,true))
local id=assert(s.tiles[tile].station)
local st=s.stations[id]
st.time_since_load,st.time_since_unload,st.town_growth_service_clock=20,255,true
st.passenger_rating_phase=143
assert(construction.commit(owner,{tool="stock_stop_remove",first=tile},nil,true))
assert(not s.stations[id] and not s.tiles[tile].station)
local track=m("openttd/rail_track")
local Rail=m("trackworks")(Sim,track,nil,m("openttd/slope"))
local Air=m("airport_network")(Sim,T,m("openttd/airport_small"))
local rail_tile,airport_tile=Sim.id(19,19),Sim.id(18,21)
assert(Rail.commit_station(s,owner,{rail_tile},0))
local station=s.stock_rail_stations[assert(s.tiles[rail_tile].rail_station_id)]
local airport=assert(Air.build(s,owner,airport_tile,"country"))
-- Seed the real service ledger at the departure boundary. Starting a
-- complete flight/train route is outside this test's removal scope.
s.rail_paid_service,s.air_paid_service=true,true
s.stock_ship_commercial={service={stations={
  {host_mode="rail",host_id=station.id,owner=owner,time_since_load=20},
  {host_mode="air",host_id=airport.id,owner=owner,time_since_unload=20},
}}}
local function count()
  return G.active_stations(s.stock_town_growth.towns[1],m("town_station_services")(Sim).view(s))
end
assert(count()==3,"Expected three nearby live service records, got "..count())
assert(Air.remove(s,owner,airport_tile,true))
assert(not s.retired_airports and count()==3,"A removal quote must not retire a facility")
assert(Rail.remove_facility(s,owner,rail_tile))
assert(s.tiles[rail_tile].rail_tracks==1 and not s.tiles[rail_tile].rail_station_id)
assert(Air.remove(s,owner,airport_tile,false))
assert(not Air.airport_for(s,airport_tile) and count()==3)
assert(Sim.stock_station_slot(s)==3,"Retired stations still occupy their physical IDs")
s.stock_ship_commercial=nil
s.rail_paid_service,s.air_paid_service=verify_rail or nil,verify_air or nil
local cutoff=math.min(s.retired_road_stations[id].until_tick,
  s.retired_rail_stations[station.id].until_tick,s.retired_airports[airport.id].until_tick)
local file="retired-town-station.chk"
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
Checkpoint.write_state(s)
local cap={road={start_year=1950,breakdowns=1,service_interval=150},rail={engines={},ready={},split={}},
  ferry={},air={},oil_tanker=true}
local client=m("campaign_authority_client")(core,mod)
local thread,proof
local function resume(reply)
  local ok,next_query=coroutine.resume(thread,reply)
  assert(ok,next_query)
  if next_query then assert(client.query(next_query,resume)) end
end
local revision
local function ask(kind,params)
  local req=type(params)=="table" and params or {days=params}
  req.kind,req.player=kind,owner
  local reply=assert(coroutine.yield(req))
  assert(reply.ok,reply.why)
  revision=reply.revision or revision
  return reply.value
end
local function run()
  ask("advance",1)
  ask("checkpoint")
  local feb=assert(Checkpoint.read())
  local t=feb.stock_town_growth.towns[1]
  assert(feb.day==31 and feb.passenger_house_clock.counter<cutoff)
  assert(t.last_active==3 and t.reason=="serviced" and t.growing)
  assert(feb.retired_road_stations[id].row.time_since_load==20,"Inactive service clocks must not age")
  assert(feb.retired_rail_stations[station.id].row.time_since_load==20)
  assert(feb.retired_airports[airport.id].row.time_since_unload==20)
  if verify_reopen then
    for _=1,4 do ask("advance",4) end
    ask("checkpoint")
    local before=assert(Checkpoint.read())
    local dead=before.retired_road_stations[id]
    assert(before.day==47 and dead.row.passenger_rating_phase==143)
    local request={tool="stock_terminal_auto",first=target,kind="bus"}
    local quote=ask("road_quote",{request=request})
    ask("command",{command={kind="road_commit",revision=revision,request=request,quote=quote}})
    ask("checkpoint")
    local reopened=assert(Checkpoint.read())
    local live=assert(reopened.stations[id])
    assert(reopened.tiles[target].station==id and live.tile==target and live.stock_station_id==0)
    local phase=7-math.floor((dead.until_tick-1-reopened.passenger_house_clock.counter)/250)
    assert(phase>=4 and phase<=6 and live.passenger_rating_phase==phase and live.time_since_load==20)
    ask("advance",2)
    ask("checkpoint")
    live=assert(Checkpoint.read().stations[id])
    assert(live.passenger_rating_phase==phase+148 and live.time_since_load==20)
    ask("advance",1)
    ask("checkpoint")
    live=assert(Checkpoint.read().stations[id])
    assert(live.passenger_rating_phase==phase+222-185 and live.time_since_load==21)
    ask("advance",4);ask("advance",4);ask("advance",1)
  elseif verify_rail or verify_air then
    for _=1,4 do ask("advance",4) end
    ask("checkpoint")
    local before=assert(Checkpoint.read())
    local facility=verify_rail and station or airport
    local retired=verify_rail and "retired_rail_stations" or "retired_airports"
    local current=verify_rail and "stock_rail_stations" or "stock_small_airports"
    local dead=before[retired][facility.id]
    assert(before.day==47 and dead)
    local destination=verify_rail and Sim.id(18,19) or Sim.id(19,21)
    local request=verify_rail and {tool="station",first=destination,last=destination,axis=0,length=1,tracks=1,drag=true}
      or {mode="air",operation="build",tile=destination,layout="country"}
    local quote=assert(ask(verify_rail and "rail_quote" or "transport_quote",{request=request}))
    ask("command",{command={kind=verify_rail and "rail_commit" or "transport_commit",revision=revision,token=quote.token}})
    ask("checkpoint")
    local reopened=assert(Checkpoint.read())
    local p=assert(reopened[current][facility.id])
    assert(p.stock_station_id==facility.stock_station_id and (p.sign_tile or p.origin)==destination)
    local tile=reopened.tiles[destination]
    assert((verify_rail and tile.rail_station_id or tile.airfield.airport)==facility.id)
    local phase=7-math.floor((dead.until_tick-1-reopened.passenger_house_clock.counter)/250)
    local View=m("town_station_services")(Sim)
    local function ages(snapshot,want_phase,want_age)
      local load,unload,c=View.reactivated_clocks(snapshot,snapshot[current][facility.id])
      assert(load==(verify_rail and want_age or 255) and unload==(verify_air and want_age or 255) and c==want_phase)
    end
    ages(reopened,phase,20)
    assert(G.active_stations(t,View.view(reopened))==3)
    ask("advance",3)
    ask("checkpoint")
    local loaded=assert(Checkpoint.read())
    ages(loaded,phase+222-185,21)
    assert(G.active_stations(t,View.view(loaded))==2)
    ask("advance",4);ask("advance",4);ask("advance",1)
  else
    for _=1,7 do ask("advance",4) end
  end
  ask("checkpoint")
  local mar=assert(Checkpoint.read())
  t=mar.stock_town_growth.towns[1]
  assert(mar.day==59 and mar.passenger_house_clock.counter>cutoff)
  assert(not mar.retired_road_stations[id] and t.last_active==0 and t.reason~="serviced")
  assert(not mar.retired_rail_stations[station.id] and not mar.retired_airports[airport.id])
  assert(Sim.stock_station_slot(mar)==(verify_reopen and 1 or 0),"Only expired physical IDs become available")
  proof=true
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(run)
  assert(client.start(cap,function(reply)
    assert(reply.ready and reply.day==30)
    resume(reply)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,tostring(detail or reason))
    core.log("action",verify_air and
      "PASS NATIVE MUNICIPAL ROADS: airfield reused its ID and aged out of town growth on the stock phase" or verify_rail and
      "PASS NATIVE MUNICIPAL ROADS: rail station reused its ID and aged out of town growth on the stock phase" or verify_reopen and
      "PASS NATIVE MUNICIPAL ROADS: road stop relocated under its stock physical ID and resumed the exact rating phase" or
      "PASS NATIVE MUNICIPAL ROADS: removed road, rail and air facilities counted in February and expired before March")
    core.request_shutdown("Retired station parity verified",false,0)
  end,file))
end)
