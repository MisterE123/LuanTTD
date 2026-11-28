-- Real owner worker crosses two monthly stock ticks after road, rail and
-- air facilities are physically removed. Their signs live until big tick 8.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,T,G=m("sim"),m("openttd/terrain"),m("openttd/town_growth")
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
Sim.W,Sim.H=64,64
local s=Sim.new(4841)
local tile=Sim.id(18,20)
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
s.rail_paid_service,s.air_paid_service=nil,nil
local cutoff=math.min(s.retired_road_stations[id].until_tick,
  s.retired_rail_stations[station.id].until_tick,s.retired_airports[airport.id].until_tick)
local file="retired-town-station.chk"
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
Checkpoint.write_state(s)
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
local client=m("campaign_authority_client")(core,mod)
local thread,proof
local function resume(reply)
  local ok,next_query=coroutine.resume(thread,reply)
  assert(ok,next_query)
  if next_query then assert(client.query(next_query,resume)) end
end
local function ask(kind,days)
  local reply=assert(coroutine.yield({kind=kind,days=days,player=owner}))
  assert(reply.ok,reply.why)
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
  for _=1,7 do ask("advance",4) end
  ask("checkpoint")
  local mar=assert(Checkpoint.read())
  t=mar.stock_town_growth.towns[1]
  assert(mar.day==59 and mar.passenger_house_clock.counter>cutoff)
  assert(not mar.retired_road_stations[id] and t.last_active==0 and t.reason~="serviced")
  assert(not mar.retired_rail_stations[station.id] and not mar.retired_airports[airport.id])
  assert(Sim.stock_station_slot(mar)==0,"The physical IDs become available after deletion")
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
    core.log("action","PASS NATIVE MUNICIPAL ROADS: removed road, rail and air facilities counted in February and expired before March")
    core.request_shutdown("Retired station parity verified",false,0)
  end,file))
end)
