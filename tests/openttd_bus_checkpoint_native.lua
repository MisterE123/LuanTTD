local path=core.get_modpath(core.get_current_modname())
local function lua(name) return dofile(path.."/"..name..".lua") end
local function json(name)
  local file=assert(io.open(path.."/"..(name or "checkpoint")..".json","rb"))
  local text=file:read("*a");file:close()
  return assert(core.parse_json(text))
end
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local W,S=lua("world_storage"),lua("slope")
local Sparse=lua("openttd_sparse")(W,lua("openttd_map"),core.sha256)
local Motion=lua("road_motion")(lua("road_motion_data"))
local F=lua("yapf_road_follow")
local Cost=lua("yapf_road_cost")(F)
local Yapf=lua("yapf_road_search")(F,Cost)
local Unpack=lua("openttd_bus_checkpoint")(Sparse,S,lua("road_slope"),Motion,F,Cost,Yapf)
local original=json()
local state=Unpack.prepare(original)
local view=state.checkpoint()
assert(view.paused and state.paused and not state.can_resume_in_luanti)
assert(not state.board.commit and not state.board.apply_job and state.board.stats().chunks==0)
local b=view.vehicle
local src=original.bus_state
local cursor=b.cursor
local trace=b.route_trace
assert(b.timers.tick_counter==209 and b.timers.last_loading_tick==2130 and b.timers.running_ticks==74)
assert(b.id==4 and b.owner==0 and cursor.side==1 and b.engine==116)
assert(b.tile.source_id==44389 and b.tile.logical_id~=b.tile.source_id and b.dest.source_id==44392)
assert(cursor.state==8 and cursor.frame==1 and cursor.direction==5 and cursor.progress==69)
assert(cursor.speed==112 and cursor.subspeed==126 and cursor.age_countdown==63)
assert(cursor.x16==1617 and cursor.z16==2773 and cursor.y8==8)
assert(cursor.native.x==203.625 and cursor.native.y==1.5 and cursor.native.z==348.125)
assert(view.clock.tick_counter=="2541" and view.clock.date==712240 and view.clock.date_fract==3)
assert(view.clock.economy_date==712240 and view.clock.economy_date_fract==3 and view.clock.calendar_sub_date_fract==0)
assert(view.companies[0].money=="92643" and view.companies[0].loan=="100000"
  and view.companies[0].max_loan=="-9223372036854775808" and view.companies[0].money_fraction==230)
assert(view.stations[1].stop.kind=="drive_stop" and view.stations[0].stop.kind=="bay_stop")
assert(view.stations[1].tile.source_id==44387 and view.stations[0].stop.id==0)
assert(view.depots[0].tile.source_id==44128 and view.towns[25].id==25)
assert(b.order_list_id==0 and b.orders[1].id==0 and b.orders[1].next_id==1 and not b.orders[2].next_id)
assert(b.current_order_id==1 and b.order_index==1 and b.orders[2].station==0)
assert(b.onboard==5 and b.packets[1].periods_in_transit==2 and b.packets[1].packet_id==0)
assert(b.packets[1].source==1 and b.packets[1].source_id==25 and b.packets[1].feeder_share=="0")
local wanted={44389,44390,44391,44392}
assert(#trace==#wanted)
for i,step in ipairs(trace) do assert(step.tile==wanted[i] and step.position.source_id==wanted[i]) end

local reference=json("reference")
if reference.fare then
  assert(reference.source_sha256==view.source.sha256 and reference.source_sha_unchanged
    and reference.luanttd_resumed==false and tostring(reference.starting_tick)==view.clock.tick_counter)
  assert(reference.destination_source_tile==b.dest.source_id and reference.delivered==b.onboard)
  assert(reference.fare_observed_by_tick>=reference.delivery_observed_by_tick and reference.settlement_recheck_tick>reference.fare_observed_by_tick)
  local I=lua("income")
  local spec=I.temperate.passenger
  local x,z=state.board.source_xy(b.dest.source_id)
  local fare=0
  for _,p in ipairs(b.packets) do
    local ox,oz=state.board.source_xy(p.source_xy)
    local dist=math.min(math.abs((x-1)-p["travelled.x"])+math.abs((z-1)-p["travelled.y"]),
      math.abs(x-ox)+math.abs(z-oz))
    fare=fare+I.regular(p.count,dist,reference.pre_delivery_age,unpack(spec))
  end
  assert(fare==reference.fare,"LuanTTD pinned payment kernel disagrees with native stock fare")
  core.log("action","LUANTTD STOCK FARE DIFFERENTIAL PASS: measured "..fare.." for "..b.onboard
    .." passengers; snapshot stays paused")
end

-- No mutation can change another read of the accepted state.
view.companies[0].money="0"
b.packets[1].count=99
src.road_vehicles["4"]["current_order.dest"]=99
assert(state.checkpoint().companies[0].money=="92643")
assert(state.checkpoint().vehicle.onboard==5 and state.checkpoint().vehicle.packets[1].count==5)
assert(not pcall(Unpack.prepare,original))

-- Raw metadata can cross IEEE-754's exact domain, and must remain strings.
local new=json()
new.bus_state.game_clock.tick_counter="18446744073709551615"
new.bus_state.company_balances["0"].money="9007199254740993"
local decimal=Unpack.prepare(new).checkpoint()
assert(decimal.clock.tick_counter=="18446744073709551615" and decimal.companies[0].money=="9007199254740993")

local damage={
  function(c) c.bus_state.source.sha256=("0"):rep(64) end,
  function(c) c.bus_state.game_clock.pause_mode=0 end,
  function(c) c.bus_state.game_clock.tick_counter="18446744073709551616" end,
  function(c) c.bus_state.company_balances["0"].money=92643 end,
  function(c) c.bus_state.company_balances["0"].loan="-1" end,
  function(c) c.bus_state.road_vehicles["4"].motion.frame=2 end,
  function(c) c.bus_state.road_vehicles["4"].z_pos=9 end,
  function(c) c.bus_state.road_vehicles["4"].owner=1 end,
  function(c) c.bus_state.road_vehicles["4"].orders[2]["next"]=1 end,
  function(c) c.bus_state.road_vehicles["4"].packets[1].source=0 end,
  function(c) c.bus_state.road_vehicles["4"].packets[1].periods_in_transit=0 end,
  function(c) c.bus_state.road_vehicles["4"]["cargo.action_counts"][3]=6 end,
  function(c) c.bus_state.stations["0"].road_stops[1].status=0 end,
  function(c) c.bus_state.stations["0"].road_stops[1].road_stop_id=1 end,
  function(c) c.map.road_tiles["44390"].road_bits=5 end,
}
for i,clobber in ipairs(damage) do
  local damaged=json()
  clobber(damaged)
  assert(not pcall(Unpack.prepare,damaged),"accepted malformed checkpoint variant "..i)
end
core.log("action","LUANTTD PAUSED STOCK BUS CHECKPOINT PASS: exact clock, finance, motion, five aged riders, four traversed route tiles")
core.after(0,function() core.request_shutdown("Bus checkpoint assertions finished",false,0) end)
