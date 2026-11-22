local mod="mods/bayline/"
local Sim=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local s=Sim.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.road_regal_enabled,s.road_junction_clearance=true,true
dofile(mod.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(Sim,T,s)
local at=Sim.id
local a,b,d,e=at(9,12),at(18,12),at(10,13),at(17,13)
assert(Sim.build(s,"A","road",Sim.line(a,b)))
assert(Sim.build(s,"A","road_station",{a,b}))
assert(Sim.build(s,"A","road_depot",{d}))
assert(Sim.build(s,"A","road_depot",{e}))
local sa,sb=s.tiles[a].station,s.tiles[b].station
local i=assert(Sim.purchase(s,"A","bus","passenger",nil,d))
local v=s.fleet[i]
assert(not Sim.park_road_vehicle(s,"A",i))
assert(Sim.add_order(s,"A",i,sa))
assert(Sim.add_order(s,"A",i,sb))
assert(Sim.toggle(s,"A",i))
for j=1,300 do
  Sim.daily(s)
  if v.route and v.dest==sb and v.units>0 then break end
end
assert(v.route and v.dest==sb and v.units>0,"Test must stop after a real inbound passenger visit")
assert(Sim.toggle(s,"A",i))
for j=1,300 do
  Sim.daily(s)
  if not v.running then break end
end
assert(v.station==sb and not v.running and v.units==0 and v.revenue>0)
assert(Sim.road_can_park(s,"A",i))
local seen=v.last_road_arrival_tick
local fare=v.revenue
assert(not Sim.park_road_vehicle(s,"Other",i))
local ok,why=Sim.park_road_vehicle(s,"A",i)
assert(ok,why)
assert(v.road_return_depot==e and v.road_depot_resume==1 and not Sim.toggle(s,"A",i))
local route=v.road_motion_frames
assert(route[#route][4]==e and route[#route][15]==11)
assert(not Sim.build(s,"A","clear",{e}),"The active return plan must protect its depot")
local function copy(t)
  if type(t)~="table" then return t end
  local r={};for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
s=copy(s);v=s.fleet[i]
for j=1,70 do
  Sim.daily(s)
  if v.depot then break end
end
assert(v.depot==e and v.last_depot_entry_tick>seen and not v.running and not v.road_return_depot)
assert(v.revenue==fare and not v.road_stop_pose and not Sim.road_motion_frame(s,v))
assert(#v.orders==2 and v.orders[1].station==sa and v.orders[2].station==sb)
local latest=v.last_depot_entry_tick
s=copy(s);v=s.fleet[i]
assert(v.last_depot_entry_tick==latest and not Sim.road_motion_frame(s,v))
assert(Sim.toggle(s,"A",i))
for j=1,400 do
  Sim.daily(s)
  if v.revenue>fare then break end
end
assert(v.revenue>fare and v.last_road_arrival_tick>latest and not v.depot and v.last_depot_entry_tick==latest)
print(("PASS: real bus %d resumes paid route after nearest stock depot frame 11 at tile %d and two reloads"):format(i,e))
