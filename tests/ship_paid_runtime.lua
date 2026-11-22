-- SPDX-License-Identifier: GPL-2.0-only
-- Real stock world clocks, ship motion, house production, cash and restart.
local root="mods/bayline/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local Track=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local Water=dofile(src.."ship_follow.lua")(Track)
local Facilities=dofile(src.."ship_facilities.lua")(Track,Water)
local Network=dofile(root.."ship_network.lua")(Sim,Terrain,Water,Facilities)
local Y=dofile(src.."ship_yapf.lua")(Track,Water,dofile(src.."yapf_road_search.lua"))
local Motion=dofile(src.."ship_motion.lua")(Track,Water)
local Run=dofile(root.."ship_preview_run.lua")(Network,Track,Water,Y,Motion,
  dofile(src.."ship_regions.lua"),{width=Sim.W,height=Sim.H,x0=1,z0=1})
local via=arg[1]=="buoy" and Sim.id(19,12) or nil

local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t),"Do not map a transient pointer into paid ferry saves")
  local u={}
  for k,v in pairs(t) do u[k]=clone(v) end
  return u
end
local function fixture(paid)
  local s=Sim.new(1751)
  s.ship_paid_service=paid
  s.road_economy=true
  s.road_stock_clock=true
  s.road_stock_loading=true
  s.road_stock_house_supply=true
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x<9 and 1 or 0 end)
  for i,t in ipairs(s.tiles) do
    local x=Sim.xy(i)
    t.site=nil;t.owner=nil;t.wood=nil;t.house=nil;t.build=nil
    t.terrain=x>=9 and "water" or "grass"
  end
  for _,z in ipairs({5,6,7,8,9,17,18,19,20,21}) do
    local t=s.tiles[Sim.id(6,z)]
    t.house,t.parcel,t.variant=true,"shop",2
  end
  Sim.mount_paid_ferry(s,Run)
  local a=assert(Network.build(s,"Alice","dock",Sim.id(8,9)))
  local b=assert(Network.build(s,"Alice","dock",Sim.id(8,16)))
  local d=assert(Network.build(s,"Alice","depot",Sim.id(12,10),0))
  if via and paid then
    assert(Network.build(s,"Alice","buoy",via))
    local invalid,why=Run.quote(s,"Alice",d.id,a.id,b.id,Sim.id(18,12))
    assert(not invalid and why=="SELECT_BUOY")
  end
  local p=assert(Run.start(s,"Alice",d.id,a.id,b.id,paid and via or nil))
  return s,p,a,b,d
end

-- Existing empty pilot still advances on its own clock and never consumes
-- a single stock house event or ferry delivery account.
local empty,ep=fixture(false)
assert(not ep.paid_clock and not Sim.ferry_paid_status(empty))
Sim.daily(empty)
assert(ep.vehicle.tick==0 and not empty.stock_ship_commercial and not empty.stock_passenger_mux)
Run.tick(empty,74)
assert(ep.vehicle.tick==74)

local s,p,a,b,d=fixture(true)
assert(p.paid_clock and Sim.ferry_paid_status(s).onboard==0)
assert(Run.tick(s,74)==nil and p.vehicle.tick==0)
local cash,expense=Sim.company(s,"Alice").cash,Sim.company(s,"Alice").expense
local moved,units,payment,board_events,deliver_events=0,0,0,0,0
local loaded_save,dispatched_save
local waypoint_save,passes
local function daily()
  local before=p.vehicle.tick
  Sim.daily(s)
  local e=Sim.ferry_loading_events(s)
  assert(#Sim.ferry_loading_events(s)==0)
  assert(p.phase~="blocked",p.failure)
  assert(p.vehicle.tick==before+74,"Movement must use exactly one stock-day clock")
  local svc=s.stock_ship_commercial.service
  assert(s.passenger_house_clock.counter==s.stock_load_tick and s.stock_load_tick==svc.tick
    and svc.tick==svc.post_tick)
  for _,rec in ipairs(e) do
    assert(rec.owner=="Alice" and rec.tick<=svc.tick and rec.tick>svc.tick-74 and rec.day==s.day)
    local station=rec.station==a.id and a or b
    assert(rec.tile~=station.land and rec.tile~=station.water,
      "Service must use the stock in-water berth")
    if via then assert(rec.station~=p.via.id and rec.tile~=via,"A buoy adds no loading or fares") end
    if rec.kind=="arrive" then
      local found=false
      for _,water in ipairs(Network.board(s).station_dock_tiles(rec.station)) do
        if water==rec.tile then found=true end
      end
      assert(found)
    elseif rec.kind=="board" then
      moved=moved+rec.units;board_events=board_events+1
    elseif rec.kind=="deliver" then
      assert(rec.distance>0 and rec.age>=0 and rec.amount>=0 and rec.origin_station~=rec.station)
      deliver_events=deliver_events+1
    elseif rec.kind=="fare" then
      assert(rec.amount>0 and rec.units>0)
      payment=payment+rec.amount;units=units+rec.units
    end
  end
  local hud=assert(Sim.ferry_paid_status(s))
  if p.via then
    assert(p.via.passes>=math.max(0,p.arrivals-1) and p.via.passes<=p.arrivals)
    if p.via.passes>(passes or 0) then
      local record=p.last_buoy_pass
      assert(record.order_tile==via and record.tile~=via and record.distance==3 and record.speed>0)
      assert(record.next_dock==a.id or record.next_dock==b.id)
      passes=p.via.passes
    end
    if not waypoint_save and p.vehicle.order and p.vehicle.order.kind=="waypoint" then
      local elapsed,tx=p.vehicle.tick,s.topology
      s=clone(s);p=Run.current(s);Sim.mount_paid_ferry(s,Run)
      assert(p.vehicle.order.tile==via and s.topology==tx and p.vehicle.tick==elapsed)
      waypoint_save=true
    end
  end
  assert(hud.delivered==units and hud.fare==payment and hud.boarded==moved)
  assert(Sim.company(s,"Alice").cash==cash+payment-(Sim.company(s,"Alice").expense-expense))
  assert(Sim.company(s,"Alice").revenue==payment and Sim.company(s,"Alice").paid_units==units)
  local pos=Sim.ferry_paid_pose(s,.5)
  if p.arrivals>0 then assert(pos and pos.y==.5) end
  if not loaded_save and (hud.loading and hud.onboard>0) then
    loaded_save={tick=hud.tick,units=hud.onboard,arrivals=p.arrivals}
    s=clone(s);p=Run.current(s)
    Sim.mount_paid_ferry(s,Run)
    assert(#Sim.ferry_loading_events(s)==0)
    assert(Sim.ferry_paid_status(s).onboard==loaded_save.units)
  end
  return hud
end
for _=1,160 do
  local hud=daily()
  if not dispatched_save and hud.fare>0 then
    dispatched_save={tick=hud.tick,units=hud.delivered,fare=hud.fare}
    s=clone(s);p=Run.current(s)
    Sim.mount_paid_ferry(s,Run)
    assert(Sim.ferry_paid_status(s).fare==dispatched_save.fare)
  end
  if loaded_save and dispatched_save and payment>dispatched_save.fare and p.arrivals>=4 then break end
end
assert(loaded_save and dispatched_save and payment>dispatched_save.fare,"Repeated positive paid service must survive saves")
assert(board_events>=2 and deliver_events>=2 and p.last_berth)
assert(s.stock_passenger_mux.pending==nil and s.stock_passenger_mux.consumed)
assert(s.tiles[Sim.id(6,6)].source_house.id==0x0E)
if via then
  assert(waypoint_save and passes>=3,"Save in flight with unfinished buoy and repeat both directions")
  for _,company in ipairs({"Alice","Bob"}) do
    Sim.company(s,company)
    local unbuilt,why=Network.remove(s,company,via)
    assert(not unbuilt and why=="BUOY_IN_USE")
  end
end
local prior=p.vehicle.tick
s.ship_paid_service=false
Sim.daily(s)
assert(Sim.ferry_paid_status(s).paused and p.vehicle.tick==prior and not Run.tick(s,2))
s.ship_paid_service=true
daily()
assert(Sim.ferry_paid_status(s).tick==s.passenger_house_clock.counter)
local last=p.paid_clock
assert(Run.clear(s,"Alice"))
Sim.daily(s)
assert(not s.stock_ship_commercial.service.vehicles[last] and not Sim.ferry_paid_status(s))
if via then
  local dirty,cost=Network.remove(s,"Bob",via)
  assert(dirty[1]==via and cost==50 and Network.board(s).tile(via).kind=="sea")
  print(("PASS: %d physical buoy passes at Manhattan 3, saved active order, no waypoint commerce"):format(passes))
end
print(string.format("PASS: real paid ferry carried %d, settled %d passengers/$%d, exact clocks, two saves, pause/resume and old empty mode",
  moved,units,payment))
