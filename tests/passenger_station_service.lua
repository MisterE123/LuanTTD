-- SPDX-License-Identifier: GPL-2.0-only
local function mod(path) return dofile("mods/luanttd_core/"..path..".lua") end
local P=mod("openttd/passengers")
local Income=mod("openttd/income")
local Rating=mod("openttd/station_rating")
local Queue=mod("station_rating_runtime")(nil,Rating,P)
local Catchment=mod("openttd/station_catchment")(P,Rating,
  mod("road_station_service")().house_passenger_acceptance,mod("road_mail_runtime")().house_acceptance)
local S=mod("passenger_station_service")(Catchment,P,Income,Rating,Queue,
  mod("road_loading_runtime"),mod("openttd/loading_timing"))

local function clone(s)
  -- A literal save round trip: no aliased Lua objects survive; all ability
  -- to reconstruct state comes from ordinary table fields in the snapshot.
  local function literal(v)
    if type(v)=="table" then
      local fields={}
      for k,data in pairs(v) do fields[#fields+1]="["..literal(k).."]="..literal(data) end
      table.sort(fields)
      return "{"..table.concat(fields,",").."}"
    elseif type(v)=="string" then return string.format("%q",v)
    else return tostring(v) end
  end
  return assert(loadstring("return "..literal(s)))()
end

local w,h=64,16
local function at(x,y) return y*w+x end
local function block(x,y,kind) return {x=x,y=y,kind=kind} end
local sources={
  [at(4,4)]={id=0,town=101,completed=true},
  [at(24,4)]={id=0,town=202,completed=false},
  [at(53,4)]={id=0,town=303,completed=true},
}
local ctx={width=w,height=h,
  xy=function(i) return i%w,math.floor(i/w) end,
  year=function()return 1950 end,
  house_at=function(x,y) return sources[at(x,y)] end,
}
local state=S.new(10289)
S.station(state,{id=1,town=101,owner="A",tiles={block(4,5,"rail"),block(5,5,"rail")}},ctx)
S.station(state,{id=2,town=203,owner="A",tiles={
  block(24,5,"rail"),block(25,5,"rail"),block(26,5,"dock"),block(27,5,"dock"),
  block(24,6,"bus"),
}},ctx)
S.station(state,{id=3,town=303,owner="A",tiles={block(53,5,"dock"),block(54,5,"dock")}},ctx)
S.vehicle(state,{id=1,mode="rail",owner="A",speed=80,built=1940,length=16})
S.vehicle(state,{id=2,mode="ship",owner="A",speed=64,built=1937})
S.vehicle(state,{id=3,mode="rail",owner="A",speed=96,built=1947,length=16})

local t=0
local totals,boarded,order_times={}, {}, {}
local function track(events)
  for _,e in ipairs(events) do
    if e.kind=="deliver" then totals[#totals+1]=e
    elseif e.kind=="board" then
      boarded[e.vehicle]=(boarded[e.vehicle] or 0)+e.units
      order_times[e.vehicle]=order_times[e.vehicle] or {}
      table.insert(order_times[e.vehicle], e.tick)
    end
  end
end
local function step(fn)
  t=t+1
  local leave,events=S.pre_motion_tick(state,t,ctx)
  local again,events_again=S.pre_motion_tick(state,t,ctx)
  assert(#again==0 and #events_again==0)
  if fn then fn(leave,events) end
  for _,id in ipairs(leave) do
    local v=state.vehicles[id]
    assert(S.leave(state,id,v.visit,t,ctx,events))
    assert(not S.leave(state,id,v.visit,t,ctx,events))
  end
  track(events)
  assert(S.post_motion_tick(state,t))
  assert(not S.post_motion_tick(state,t))
end
local function begin(id,st,visit,tile,order,events)
  assert(S.begin(state,id,st,visit,tile,order,t,ctx,events))
  assert(S.begin(state,id,st,visit,tile,order,t,ctx,events))
end
local function wait_for(id)
  local limit=t+2000
  while state.vehicles[id].load_state do
    assert(t<limit,"Vehicle did not finish its operation")
    step()
  end
end

step(function(_,events)
  assert(S.produce(state,4,4,60,101,ctx)==0)
  begin(1,1,1,at(5,5),{full=true,platform_tiles=2},events)
end)
step()
assert(state.stations[1].passenger_rating_state.last_speed==80)
assert(state.stations[1].passenger_rating_state.last_age==10)
assert(state.vehicles[1].load_state and not state.vehicles[1].load_state.finished)
step(function()
  assert(S.produce(state,4,4,60,101,ctx)==41)
end)
for _=1,19 do step() end
local visible,available=S.waiting(state,1)
assert(t==22 and visible==36 and available==1) -- 5 board, 35 reserved
state=clone(state)
wait_for(1)
assert(boarded[1]==40 and state.vehicles[1].last_left==342 and S.waiting(state,1)==1)
for i=2,#order_times[1] do assert(order_times[1][i]-order_times[1][i-1]==40) end
assert(state.vehicles[1].batches[1].origin_tile==at(5,5))

for _=1,272 do step() end
step(function(_,events)
  begin(1,2,2,at(24,5),{transfer=true,no_load=true,platform_tiles=2},events)
  assert(state.vehicles[1].travel_ticks==273)
end)
step()
assert(S.waiting(state,2)==5 and state.vehicles[1].load_state.unload_units==35)
state=clone(state)
wait_for(1)
assert(S.waiting(state,2)==40 and state.vehicles[1].units==0)
assert(not state.companies.A and state.vehicles[1].visual_profit>0)
assert(state.stations[2].passenger_rating_state.has_rating)
assert(state.stations[2].passenger_rating_state.last_speed==0) -- transfer alone is not a loading attempt
step(function(_,events)
  local dup,why=S.begin(state,1,2,2,at(24,5),{platform_tiles=2},t,ctx,events)
  assert(not dup and why=="DUPLICATE_OR_STALE_VISIT")
  begin(2,2,1,at(28,5),{},events)
end)
step()
assert(S.waiting(state,2)==30 and state.vehicles[2].units==10)
assert(state.stations[2].passenger_rating_state.last_speed==64) -- not road speed/2
assert(state.stations[2].last_vehicle_type=="ship")
state=clone(state)
wait_for(2)
assert(boarded[2]==40 and S.waiting(state,2)==0)
for i=2,#order_times[2] do assert(order_times[2][i]-order_times[2][i-1]==10) end
assert(state.vehicles[2].batches[1].origin_station==1 and state.vehicles[2].batches[1].source==101)

for _=1,424 do step() end
step(function(_,events) begin(2,3,2,at(55,5),{},events) end)
step()
local ship=state.vehicles[2]
assert(ship.units==30 and ship.load_state.payment.delivered==10 and not state.companies.A)
state=clone(state) -- some passengers delivered, none paid at time of save
wait_for(2)
assert(state.vehicles[2].delivered==40 and state.towns[303]==40 and not state.towns[203])
local company=state.companies.A
assert(company.cash>0 and company.units==40 and company.revenue==company.cash)
local boat_cash=company.cash
local earned=0
for _,e in ipairs(totals) do
  assert(e.mode=="ship" and e.distance==46 and e.origin_station==1 and e.age>1)
  local expected=Income.regular(e.units,e.distance,e.age,unpack(Income.temperate.passenger))
  assert(e.amount==expected)
  earned=earned+expected
end
assert(earned==boat_cash)
step(function(_,events)
  assert(not S.begin(state,2,3,2,at(55,5),{},t,ctx,events))
end)
assert(state.companies.A.cash==boat_cash and state.companies.A.units==40)

-- The rail carriage also takes an ordinary paid route. The destination
-- contains a dock and bus stop but only one station-level queue and goods.
step(function(_,events)
  S.produce(state,4,4,30,101,ctx)
  begin(3,1,1,at(5,5),{platform_tiles=2},events)
end)
wait_for(3)
local count=state.vehicles[3].units
assert(count>0)
for _=1,230 do step() end
step(function(_,events) begin(3,2,2,at(24,5),{platform_tiles=2},events) end)
step()
assert(state.vehicles[3].load_state.payment.delivered>0)
state=clone(state)
wait_for(3)
assert(state.companies.A.cash>boat_cash and state.companies.A.units==40+count)
assert(state.vehicles[3].route_profit==state.companies.A.cash-boat_cash)
assert(state.towns[203]==count and state.towns[202]==nil)
local fare=state.companies.A.cash
step(function(_,events)
  assert(not S.begin(state,3,2,2,at(24,5),{platform_tiles=2},t,ctx,events))
end)
assert(state.companies.A.cash==fare)
print(string.format("PASS: shared passenger transfers and reload-safe stock fares: ferry %d/$%d, rail %d/$%d",
  40,boat_cash,count,fare-boat_cash))

-- Both modes compete for one physical passenger bucket at the same tick.
-- Arrival order, not transport mode or vehicle ID, owns the reservation.
state=S.new(444);t=0
S.station(state,{id=2,town=203,owner="A",tiles={
  block(24,5,"rail"),block(26,5,"dock"),block(27,5,"dock"),
}},ctx)
S.vehicle(state,{id=4,mode="ship",owner="A",speed=64,built=1937})
S.vehicle(state,{id=1,mode="rail",owner="A",speed=80,built=1940,length=24})
step(function(_,events)
  begin(4,2,1,at(28,5),{full=true},events)
  begin(1,2,1,at(24,5),{full=true,platform_tiles=1},events)
end)
step()
assert(state.vehicles[4].load_state.ticks==20)
assert(state.vehicles[1].load_state.ticks==80) -- full-load retry and 8-unit overhang
step(function()
  assert(S.produce(state,24,4,40,202,ctx)==27)
end)
for _=1,19 do step() end
assert(state.vehicles[4].units==10 and state.vehicles[1].units==0)
visible,available=S.waiting(state,2)
assert(visible==17 and available==0 and state.vehicles[4].load_state.reserved_units==17)
state=clone(state)
for _=1,60 do step() end
assert(state.vehicles[4].units==27 and state.vehicles[1].units==0)
assert(S.waiting(state,2)==0 and not state.companies.A)
print("PASS: simultaneous shared-platform FIFO reservation, overhang and no double boarding")

-- CmdSkipToOrder calls LeaveStation on an active loading order even
-- before it is ready. Settle that real visit and return its reserved
-- packets to the same queue; do not withdraw or recreate the train.
state=S.new(10289);t=0
S.station(state,{id=1,town=101,owner="A",tiles={block(4,5,"rail"),block(5,5,"rail")}},ctx)
S.vehicle(state,{id=1,mode="rail",owner="A",speed=80,built=1940,length=16})
step(function(_,events) begin(1,1,1,at(5,5),{full=true,platform_tiles=2},events) end)
step()
step(function() assert(S.produce(state,4,4,60,101,ctx)==41) end)
for _=1,19 do step() end
step(function(leave,events)
  local v=assert(state.vehicles[1])
  local old_visible,old_available=S.waiting(state,1)
  local aboard=v.units
  assert(#leave==0 and old_visible>old_available and aboard>0)
  assert(not S.leave(state,1,v.visit,t,ctx,events))
  assert(S.leave(state,1,v.visit,t,ctx,events,true))
  assert(not S.leave(state,1,v.visit,t,ctx,events,true))
  local new_visible,new_available=S.waiting(state,1)
  assert(new_visible==old_visible and new_available==new_visible)
  assert(state.vehicles[1]==v and v.units==aboard and not v.load_state)
  assert(#state.stations[1].loading_order==0)
end)
print("PASS: stock explicit skip ends real loading visit once, returns reserved packets, and preserves the train")
