-- SPDX-License-Identifier: GPL-2.0-only
-- One stock map with a paid bus route, actual coupled shuttle and ferry.
-- Pass 'air' to add two genuine airfields and verify all modes settle on
-- the same world clock with independent ownership and catchments.
local root=(core and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local args=type((...))=="table" and (...) or arg
local function stock(file,...) return dofile(root.."openttd/"..file..".lua")(...) end
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local T=dofile(root.."openttd/rail_track.lua")
local F=stock("rail_follow",T)
local C=stock("rail_yapf_cost",T,F)
local Search=stock("rail_yapf_search",T,F,C)
local M=stock("rail_motion",T)
local PBS=stock("rail_reservation",T,F,C)
local Life=stock("rail_consist_reservation",T,F,PBS)
local Signal=stock("rail_signals",T)
local Consist=stock("rail_consist_motion",T,M,F,Life)
local D=dofile(root.."rail_consist_dispatch.lua")(Consist,Life)
local Speed=stock("rail_station_speed",T,F)
local Reverse=stock("rail_reverse",T,M,Consist,Life,Signal,F,PBS)
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,{},C,Search)
local Rail=dofile(root.."rail_dispatch_run.lua")(T,F,C,Search,PBS,Life,Signal,Consist,D,Speed,Lab,nil,Reverse)
local W=stock("ship_follow",T)
local Network=dofile(root.."ship_network.lua")(Sim,Terrain,W,stock("ship_facilities",T,W))
local Roster=dofile(root.."openttd/passenger_ship_roster.lua")
local Calendar=dofile(root.."openttd/stock_engine_calendar.lua")
local ship_model=args and tonumber(args[1])
local Ship=dofile(root.."ship_preview_run.lua")(Network,T,W,stock("ship_yapf",T,W,dofile(root.."openttd/yapf_road_search.lua")),
  stock("ship_motion",T,W),dofile(root.."openttd/ship_regions.lua"),{width=Sim.W,height=Sim.H,x0=1,z0=1},
  {engine=Roster.model(206),engine_for=Roster.model,validate_both=ship_model~=nil})
local Depot=dofile(root.."passenger_ship_depot.lua")(Sim,Roster,Calendar,Ship,function() return true end)
if ship_model then Ship.settle_owned_day,Ship.count_owned_tick,Ship.paid_art_ready=Depot.settle,Depot.count_tick,Depot.ready end

local authority=args and args[1]=="authority"
local with_air=authority or args and args[1]=="air"
local mount_authority=authority and dofile(root.."campaign_authority_runtime.lua")
local caps={road={start_year=1950,foster=true,craighead=true,breakdowns=0,service_interval=150},
  air={[215]=true},ferry={[206]=true,[207]=true},rail={engines={},ready={},split={}}}
local Air,AirNet
if with_air then
  local Small=dofile(root.."openttd/airport_small.lua")
  AirNet=dofile(root.."airport_network.lua")(Sim,Terrain,Small)
  Air=dofile(root.."airport_preview_run.lua")(Sim,AirNet,Small,stock("airport_motion",Small),
    Terrain,dofile(root.."openttd/slope.lua"))
end

local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t),"Do not save a transient mount, frame or hook")
  local new={}
  for k,v in pairs(t) do new[k]=clone(v) end
  return new
end
local function mount(s)
  if mount_authority then
    local mounted=mount_authority(Sim,root:sub(1,-2),s,caps)
    Rail,Ship,Air=mounted.rail.run,mounted.water.run,mounted.air.run
    Network,AirNet,Lab=mounted.water.network,mounted.air.network,mounted.network.lab
    return
  end
  Sim.mount_paid_ferry(s,Ship)
  Sim.mount_paid_rail(s,Rail)
  if Air then Sim.mount_paid_air(s,Air) end
end
local s=Sim.new(1751)
if ship_model then Sim.mount_road_bus_market(s,Calendar,ship_model==207 and 1980 or 1950,true) end
if authority then Sim.mount_road_bus_market(s,Calendar,1950,true,true) end
s.rail_paid_service=true;s.ship_paid_service=true;s.air_paid_service=with_air
s.road_economy=true;s.road_stock_clock=true;s.road_stock_loading=true;s.road_stock_house_supply=true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x<19 and 1 or 0 end)
for i,t in ipairs(s.tiles) do
  local x=Sim.xy(i)
  t.site=nil;t.owner=nil;t.wood=nil;t.house=nil;t.build=nil
  t.terrain=x>=19 and "water" or "grass"
end
local function id(x,z) return Sim.id(x,z) end
for x=2,14 do
  local t=s.tiles[id(x,5)]
  t.owner="Rail";t.rail_tracks=1;t.build="stock_rail"
end
local first,second=id(4,5),id(12,5)
assert(Lab.depot(s,"Rail",id(2,5),T.SW))
assert(Lab.station(s,"Rail",first,id(6,5)))
assert(Lab.station(s,"Rail",second,id(14,5)))
assert(Rail.place_signal(s,"Rail",id(3,5),0,Signal.PBS))
local dock_a=assert(Network.build(s,"Ferry","dock",id(18,8)))
local dock_b=assert(Network.build(s,"Ferry","dock",id(18,16)))
local ship_depot=assert(Network.build(s,"Ferry","depot",id(22,10),0))
local road_a,road_b,road_depot=id(13,8),id(13,14),id(12,11)
s.sites[1].tile=id(11,11);s.sites[2].tile=id(16,13)
assert(Sim.build(s,"Coach","road",Sim.line(road_a,road_b)))
assert(Sim.build(s,"Coach","road_station",{road_a,road_b}))
assert(Sim.build(s,"Coach","road_depot",{road_depot}))
local bus=assert(Sim.purchase(s,"Coach",ship_model==207 and "leopard_bus" or "bus","passenger",nil,road_depot))
assert(Sim.add_order(s,"Coach",bus,s.tiles[road_a].station))
assert(Sim.add_order(s,"Coach",bus,s.tiles[road_b].station))
assert(Sim.toggle(s,"Coach",bus))
local shop={{4,7},{5,7},{6,7},{4,8},{5,8},{6,8},
  {14,7},{14,8},{14,9},{15,8},{14,10}, -- genuinely shared bus, rail and dock catchment
  {16,15},{16,16},{16,17},{17,17},{16,18},{17,18},
  {11,9},{11,13},{12,13},{14,13}}
if Air then
  for _,p in ipairs({{4,12},{5,12},{6,12},{5,11},{4,13},{12,16},{11,17},{12,18}}) do
    shop[#shop+1]=p
  end
end
for _,p in ipairs(shop) do
  local t=s.tiles[id(p[1],p[2])]
  t.house,t.parcel,t.variant=true,"shop",2
end
mount(s)
local ok,msg,run=Rail.start_shuttle(s,"Rail",id(2,5),s.tiles[second].rail_station_id,s.tiles[first].rail_station_id)
assert(ok and run.paid_clock,msg)
local ferry
if ship_model then
  assert(not Depot.start(s,"Ferry",ship_depot.id,dock_a.id,dock_b.id))
  assert(not Depot.buy(s,"Coach",ship_depot.id,ship_model))
  local c=Sim.company(s,"Ferry")
  local start_cash=c.cash
  local u=assert(Depot.buy(s,"Ferry",ship_depot.id,ship_model))
  local price=ship_model==207 and 28437 or 24375
  assert(u.price==price and c.cash==start_cash-price)
  assert(not Depot.buy(s,"Ferry",ship_depot.id,ship_model) and not Network.remove(s,"Ferry",ship_depot.tiles[1]))
  assert(not Depot.start(s,"Ferry",ship_depot.id,dock_a.id,dock_a.id))
  ferry=assert(Depot.start(s,"Ferry",ship_depot.id,dock_a.id,dock_b.id))
  assert(ferry.engine_id==ship_model and ferry.vehicle.max_speed==(ship_model==207 and 128 or 64))
  assert(not Ship.clear(s,"Ferry") and not Depot.stop(s,"Coach",true))
else ferry=assert(Ship.start(s,"Ferry",ship_depot.id,dock_a.id,dock_b.id)) end
assert(ferry.paid_clock)
local aircraft
if Air then
  local ap=assert(AirNet.build(s,"Air",id(2,14)))
  local aq=assert(AirNet.build(s,"Air",id(13,19)))
  aircraft=assert(Air.start(s,"Air",ap.id,aq.id))
  assert(aircraft.paid_clock and not Air.tick(s,222))
end
assert(#Rail.tick(s,222)==0 and not Ship.tick(s,222))
assert(Rail.current(s).ticks==0 and ferry.vehicle.tick==0)
local fares={Rail=0,Ferry=0,Coach=0}
local counts={Rail=0,Ferry=0,Coach=0}
if Air then fares.Air,counts.Air=0,0 end
local arrival,boarded_first,leaves={},nil,0
local saved_load,saved_fare,first_paid,verified_pose=false,false,false,false
local function daily(expect_rail)
  local oldrail,oldship=Rail.current(s).ticks,ferry.vehicle.tick
  local oldair=aircraft and (aircraft.vehicle.tick or 0)
  Sim.daily(s)
  local clock=s.passenger_house_clock.counter
  local svc=s.stock_ship_commercial.service
  assert(clock==s.stock_load_tick and clock==svc.tick and clock==svc.post_tick)
  assert(clock==s.day*74)
  assert(Rail.current(s).ticks==oldrail+(expect_rail and 74 or 0))
  assert(ferry.vehicle.tick==oldship+74 and run.phase~="blocked" and ferry.phase~="blocked",
    Rail.current(s).failure or ferry.failure)
  local arrivals_this_tick={}
  for _,ev in ipairs(Sim.rail_paid_motion_events(s)) do
    if ev.kind=="arrived" then
      assert(ev.world_tick<=clock and ev.world_tick>clock-74)
      arrivals_this_tick[ev.world_tick]=ev
    end
  end
  assert(#Sim.rail_paid_motion_events(s)==0)
  for _,e in ipairs(Sim.rail_loading_events(s)) do
    assert(e.owner=="Rail" and e.mode=="rail" and e.tick<=clock and e.tick>clock-74)
    if e.kind=="arrive" then
      local station=svc.stations[e.station]
      local rail_tile=s.tiles[e.tile]
      assert(e.station_local==station.host_id and rail_tile.rail_station_id==station.host_id)
      local capture=assert(arrivals_this_tick[e.tick])
      assert(capture.cargo_tile==e.tile and capture.platform_tiles==3)
      arrival[e.visit]=e
    elseif e.kind=="board" then
      assert(e.units<=5 and e.tick>arrival[e.visit].tick)
      if not boarded_first then boarded_first=e end
    elseif e.kind=="deliver" then
      -- Economy uses actual wagon tile x14 to x4 (or vice versa), not
      -- the sign/first platform tiles x12 and x4, which are 8 apart.
      assert(e.distance==10 and e.age>=0 and e.origin_station~=e.station)
    elseif e.kind=="leave" then
      local dwell=e.tick-arrival[e.visit].tick
      assert(dwell~=Rail.SHUTTLE_DWELL_TICKS and dwell>0)
      leaves=leaves+1
    elseif e.kind=="fare" then
      assert(e.amount>0)
      fares.Rail,counts.Rail=fares.Rail+e.amount,counts.Rail+e.units
    end
  end
  for _,e in ipairs(Sim.ferry_loading_events(s)) do
    if e.kind=="fare" then fares.Ferry,counts.Ferry=fares.Ferry+e.amount,counts.Ferry+e.units end
  end
  if Air then
    assert(aircraft.vehicle.tick==oldair+74 and aircraft.phase~="blocked",aircraft.failure)
    for _,e in ipairs(Sim.air_loading_events(s)) do
      assert(e.owner=="Air" and e.mode=="air" and e.tick<=clock and e.tick>clock-74)
      if e.kind=="fare" then fares.Air,counts.Air=fares.Air+e.amount,counts.Air+e.units end
    end
    assert(#Sim.air_loading_events(s)==0)
    local ap=assert(Sim.air_paid_status(s))
    assert(ap.fare==fares.Air and ap.delivered==counts.Air and ap.capacity==25)
    if ap.terminal_tile then
      assert(s.tiles[ap.terminal_tile].airfield.airport==ap.last_airfield)
    end
  end
  for _,effect in ipairs(Sim.road_loading_events(s)) do
    if effect.kind=="fare" then
      fares.Coach,counts.Coach=fares.Coach+effect.data.amount,counts.Coach+effect.data.units
    end
  end
  assert(#Sim.rail_loading_events(s)==0 and #Sim.ferry_loading_events(s)==0)
  for owner,fare in pairs(fares) do
    local company=Sim.company(s,owner)
    assert(company.revenue==fare and company.paid_units==counts[owner])
  end
  local status=assert(Sim.rail_paid_status(s))
  assert(status.fare==fares.Rail and status.delivered==counts.Rail and status.capacity==40)
  if status.loading then assert(status.platform_tiles==3 and status.cargo_tile) end
  if expect_rail and run.phase~="depot" then
    local tile,td,progress,reversed=Sim.rail_paid_pose(s,2,1)
    local now_id,now_td,now_f=Rail.sample(run,2)
    assert(tile==now_id and td==now_td and progress==now_f)
    assert(not not reversed==not not run.consist.reversed)
    verified_pose=true
  end
  return status
end
local function reload()
  s=clone(s);mount(s)
  run=Rail.current_paid(s);ferry=Ship.current(s)
  if Air then aircraft=Air.current(s);assert(#Sim.air_loading_events(s)==0) end
  assert(#Sim.rail_loading_events(s)==0 and #Sim.ferry_loading_events(s)==0)
end
for _=1,Air and 200 or 120 do
  local status=daily(true)
  if not saved_load and status.loading and status.onboard>0 then
    saved_load={onboard=status.onboard,last_platform=status.last_platform}
    reload()
    local restored=Sim.rail_paid_status(s)
    assert(restored.onboard==saved_load.onboard and restored.last_platform==saved_load.last_platform)
  end
  if not saved_fare and fares.Rail>0 then
    saved_fare={rail=fares.Rail,ferry=fares.Ferry,air=fares.Air}
    reload()
    assert(Sim.rail_paid_status(s).fare==saved_fare.rail and Sim.ferry_paid_status(s).fare==saved_fare.ferry)
    if Air then assert(Sim.air_paid_status(s).fare==saved_fare.air) end
  end
  if saved_load and saved_fare and fares.Rail>saved_fare.rail and fares.Ferry>saved_fare.ferry and fares.Coach>0 and (not Air or fares.Air>saved_fare.air) then break end
end
assert(saved_load and saved_fare and boarded_first and leaves>2 and verified_pose and fares.Coach>0
  and fares.Rail>saved_fare.rail and fares.Ferry>saved_fare.ferry)
assert(s.stock_passenger_mux.consumed and not s.stock_passenger_mux.pending)
assert(s.stock_ship_commercial.service.companies.Rail.cash==fares.Rail)
assert(s.stock_ship_commercial.service.companies.Ferry.cash==fares.Ferry)
assert(s.fleet[bus].delivered==counts.Coach)
local paused=Sim.rail_paid_status(s)
s.rail_paid_service=false
daily(false)
local still=Sim.rail_paid_status(s)
assert(still.paused and still.onboard==paused.onboard and still.fare==paused.fare)
s.rail_paid_service=true
daily(true)
assert(not Sim.rail_paid_status(s).paused)
local rail_id=s.stock_ship_commercial.rail_serial
assert(Rail.clear(s,"Rail"))
Sim.daily(s)
assert(not s.stock_ship_commercial.service.vehicles[rail_id] and not Sim.rail_paid_status(s))
assert(Sim.ferry_paid_status(s).onboard>=0)
if Air then
  assert(fares.Air>saved_fare.air and counts.Air>0)
  assert(Sim.air_paid_status(s).fare>=fares.Air and s.stock_ship_commercial.service.companies.Air.cash>=fares.Air)
  print(("PASS: fourth mode shared the same 74-tick clock: %d passengers/$%d by air after stock resumes")
    :format(counts.Air,fares.Air))
end
print(("PASS: one world/house clock, reload-safe road %d/$%d, rail %d/$%d, ferry %d/$%d, real carriage and source dwell")
  :format(counts.Coach,fares.Coach,counts.Rail,fares.Rail,counts.Ferry,fares.Ferry))

local fake_engine=not core
if fake_engine then core={get_modpath=function() return root:sub(1,-2) end} end
local tutorial=dofile(root.."business_tutorials.lua")({s=s,Sim=Sim})
local road_goal,road_total=tutorial.progress("Coach","road")
local boat_goal,boat_total=tutorial.progress("Ferry","boat")
assert(road_goal==6 and road_total>=fares.Coach)
assert(boat_goal==6 and boat_total>=fares.Ferry)
assert(tutorial.progress("Stranger","boat")==1)
print("PASS real paid bus and ferry complete only the correct company's lesson")
if fake_engine then core=nil end

if ship_model then
  local u=assert(s.stock_owned_ferry)
  assert(Sim.ferry_paid_status(s).capacity==(ship_model==207 and 130 or 100))
  assert(u.running_ticks>0 and u.charged_ticks>0 and u.expense>0)
  assert(Depot.stop(s,"Ferry",true))
  local ticks=u.running_ticks
  Sim.daily(s);Sim.daily(s)
  assert(u.running_ticks==ticks and u.charged_ticks==ticks)
  assert(Depot.stop(s,"Ferry",false));Sim.daily(s)
  assert(u.running_ticks>ticks)
  print(("PASS owned ferry %d; correct purchase, cargo, route restore, running costs and stop/resume"):format(ship_model))
end

return fares
