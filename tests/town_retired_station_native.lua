-- Real owner worker crosses two monthly stock ticks after the only
-- served bus stop is physically removed. Its sign lives until big tick 8.
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
local cutoff=s.retired_road_stations[id].until_tick
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
  assert(t.last_active==1 and t.reason=="serviced" and t.growing)
  assert(feb.retired_road_stations[id].row.time_since_load==20,"Inactive service clocks must not age")
  for _=1,7 do ask("advance",4) end
  ask("checkpoint")
  local mar=assert(Checkpoint.read())
  t=mar.stock_town_growth.towns[1]
  assert(mar.day==59 and mar.passenger_house_clock.counter>cutoff)
  assert(not mar.retired_road_stations[id] and t.last_active==0 and t.reason~="serviced")
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
    core.log("action","PASS NATIVE MUNICIPAL ROADS: removed bus stop counted in February and expired before March")
    core.request_shutdown("Retired station parity verified",false,0)
  end,file))
end)
