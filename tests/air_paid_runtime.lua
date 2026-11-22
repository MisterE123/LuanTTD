-- SPDX-License-Identifier: GPL-2.0-only
-- Real Country Airfield FTA, shared stock world clock and passengers.
local root="mods/bayline/"
local function mod(p) return dofile(root..p..".lua") end
local Sim=mod("sim")
local Terrain=mod("openttd/terrain")
local Small=mod("openttd/airport_small")
local Net=mod("airport_network")(Sim,Terrain,Small)
local Air=mod("airport_preview_run")(Sim,Net,Small,mod("openttd/airport_motion")(Small),
  Terrain,mod("openttd/slope"))
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=clone(v) end
  return out
end
local function at(x,z) return Sim.id(x,z) end
local function fixture(opt_in)
  local s=Sim.new(1751)
  s.air_paid_service=opt_in
  s.road_economy=true;s.road_stock_loading=true;s.road_stock_clock=true;s.road_stock_house_supply=true
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return (x<=10 or x>=22) and 1 or 0 end)
  for _,tile in ipairs(s.tiles) do
    tile.terrain="grass";tile.wood=nil;tile.house=nil;tile.site=nil;tile.build=nil;tile.owner=nil
  end
  Sim.mount_paid_air(s,Air)
  local a=assert(Net.build(s,"A",at(2,6)))
  local b=assert(Net.build(s,"A",at(31,20)))
  -- East-edge shops lie beyond the radius of the origin tile and are only
  -- in catchment because the four-by-three geometry participates in full.
  for _,g in ipairs({{9,7},{9,8},{9,9},{8,8},{8,9},{8,10},
      {37,20},{37,21},{37,22},{38,21},{38,22},{36,19}}) do
    local t=s.tiles[at(g[1],g[2])]
    t.house,t.parcel,t.variant=true,"shop",2
  end
  local p=assert(Air.start(s,"A",a.id,b.id))
  return s,p,a,b
end
local old,empty=fixture(false)
Sim.daily(old)
assert((empty.vehicle.tick or 0)==0 and not empty.paid_clock and not Sim.air_paid_status(old))
Air.tick(old,74)
assert(empty.vehicle.tick==74 and not old.stock_ship_commercial)

local s,p,a,b=fixture(true)
assert(p.paid_clock and not Air.tick(s,74) and (p.vehicle.tick or 0)==0)
assert(Air.terrain_under(s,-47,6*16+40)==8)
local takeoff=select(1,Small.point(9,0,4,3))
assert(a.x+takeoff==-47,"Stock takeoff target may lie outside the map")
local seen_outside,boards,fare,paid,settles=false,0,0,0,0
local cash,expenses=Sim.company(s,"A").cash,Sim.company(s,"A").expense
local loading_save,fare_save
local before_platform={}
local function day(expect_motion)
  local old_tick=p.vehicle.tick or 0
  Sim.daily(s)
  local tick=s.passenger_house_clock.counter
  local svc=s.stock_ship_commercial.service
  assert(tick==s.day*74 and tick==s.stock_load_tick and tick==svc.tick and tick==svc.post_tick)
  assert(p.vehicle.tick==old_tick+(expect_motion and 74 or 0) and p.phase~="blocked",p.failure)
  local terminals={}
  for _,e in ipairs(Sim.air_paid_motion_events(s)) do
    assert(e.world_tick<=tick and e.world_tick>tick-74)
    if e.kind=="terminal" then terminals[e.world_tick]=e end
  end
  assert(#Sim.air_paid_motion_events(s)==0)
  for _,e in ipairs(Sim.air_loading_events(s)) do
    assert(e.owner=="A" and e.mode=="air" and e.tick<=tick and e.tick>tick-74)
    local field=e.station_local==a.id and a or b
    local marker=s.tiles[e.tile].airfield
    assert(marker and marker.airport==field.id and e.tile~=field.origin)
    if e.kind=="arrive" then
      local next=assert(terminals[e.tick])
      assert(next.cargo_tile==e.tile and next.airport==e.station_local)
      before_platform[e.visit]=e
    elseif e.kind=="board" then
      boards=boards+e.units
      assert(e.units>0 and e.units<=20 and before_platform[e.visit].tick<e.tick)
    elseif e.kind=="deliver" then
      assert(e.distance==43 and e.age>=0 and e.origin_station~=e.station)
    elseif e.kind=="leave" then
      local elapsed=e.tick-before_platform[e.visit].tick
      assert(elapsed>0 and elapsed~=Air.DWELL_TICKS)
    elseif e.kind=="fare" then
      paid,fare,settles=paid+e.units,fare+e.amount,settles+1
      assert(e.amount>0 and e.units>0 and e.units<=25)
    end
  end
  assert(#Sim.air_loading_events(s)==0)
  local company=Sim.company(s,"A")
  assert(company.cash==cash+fare-(company.expense-expenses) and company.paid_units==paid and company.revenue==fare)
  local status=assert(Sim.air_paid_status(s))
  assert(status.onboard>=0 and status.onboard<=25 and status.boarded==boards and status.delivered==paid and status.fare==fare)
  assert(status.waiting[a.id].accepts and status.waiting[b.id].accepts)
  local current=svc.stations[0xC000+a.id]
  assert(#current.tiles==12)
  if (p.arrivals or 0)>=2 then
    assert(current.passenger_rating_state.last_speed==36)
  end
  for i=0,74 do
    local pos=Sim.air_paid_pose(s,i/74)
    if pos and pos.x<-.5 then seen_outside=true end
  end
  return status
end
local function reload()
  s=clone(s);p=Air.current(s)
  Sim.mount_paid_air(s,Air)
  assert(#Sim.air_loading_events(s)==0 and #Sim.air_paid_motion_events(s)==0)
end
for _=1,400 do
  local status=day(true)
  if not loading_save and status.loading and status.onboard>0 then
    loading_save=status.onboard
    reload()
    assert(Sim.air_paid_status(s).onboard==loading_save)
  end
  if not fare_save and fare>0 then
    fare_save=fare
    reload()
    assert(Sim.air_paid_status(s).fare==fare_save)
  end
  if loading_save and fare_save and fare>fare_save and settles>=2 then break end
end
assert(seen_outside and loading_save and fare_save and fare>fare_save and paid>=26)
assert(s.stock_passenger_mux.consumed and not s.stock_passenger_mux.pending)
assert(s.stock_ship_commercial.service.companies.A.cash==fare)
local old=Sim.air_paid_status(s)
s.air_paid_service=false
-- No remaining commercial modes in this fixture, so the paid controller
-- and its exact position freeze while the existing road clock progresses.
local old_tick=p.vehicle.tick or 0
Sim.daily(s)
assert(Sim.air_paid_status(s).paused and p.vehicle.tick==old_tick and Sim.air_paid_status(s).fare==old.fare)
s.air_paid_service=true
day(true)
local serial=s.stock_ship_commercial.air_serial
assert(Air.clear(s,"A"))
Sim.daily(s)
assert(not Sim.air_paid_status(s) and not s.stock_ship_commercial.service.vehicles[serial])
print(string.format("PASS: actual stock terminals and signed off-map flight, one stock clock, reload-safe %d passengers/$%d",paid,fare))
