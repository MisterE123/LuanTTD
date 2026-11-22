local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local B,Host,Service=m("openttd/road_breakdowns"),m("road_faults_runtime"),m("openttd/road_depot_service")
local calendar=m("openttd/stock_engine_calendar")
local s=Sim.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.road_junction_clearance=true
m("town_layout")(Sim,s)
s.corner_grid=m("terrain_preview")(Sim,T,s)
Sim.mount_road_bus_market(s,calendar,1995,true)
local function mount(w)
  Sim.mount_road_bus_market(w,calendar,1995,true)
  Sim.mount_road_faults(w,B,Host,2,{kernel=Service,interval=150,percent=false})
end
mount(s)
local at=Sim.id
local A,Z,D,E=at(9,12),at(18,12),at(10,13),at(17,13)
assert(Sim.build(s,"A","road",Sim.line(A,Z)))
assert(Sim.build(s,"A","road_station",{A,Z}))
assert(Sim.build(s,"A","road_depot",{D}))
assert(Sim.build(s,"A","road_depot",{E}))
local a,z=s.tiles[A].station,s.tiles[Z].station
local id=assert(Sim.purchase(s,"A","foster_bus","passenger",nil,D))
local v=s.fleet[id]
assert(Sim.add_order(s,"A",id,a))
assert(Sim.add_order(s,"A",id,z))
assert(Sim.toggle(s,"A",id))
local function copy(t)
  if type(t)~="table" then return t end
  local r={};for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
for _=1,300 do
  Sim.daily(s)
  local f=Sim.road_motion_frame(s,v)
  if f and v.dest==z and v.units>0 and select(1,Sim.xy(f[4]))>=12 and s.tiles[f[4]].build=="road" then break end
end
assert(v.dest==z and v.units>0 and not v.road_auto_service)
-- Advance the stock age since last service while trusting real routing,
-- eligible funds flags, vehicle pose, stock threshold and departure.
local old=v.road_fault.date_of_last_service
v.road_fault.date_of_last_service=s.stock_bus_market.epoch+s.day-151
local old_fare=v.revenue
local carried=v.units
for _=1,20 do
  Sim.daily(s)
  if v.last_auto_depot then break end
end
assert(v.last_auto_depot and v.last_auto_depot.tile==E and v.last_auto_depot.station==z)
assert(v.last_auto_depot.cost<=Service.DEFAULT_DEPOT_PENALTY and v.units==carried)
assert(v.orders[1].station==a and v.orders[2].station==z)
local applied=v.last_auto_depot.tick
local saved=v.road_auto_service~=nil
s=copy(s);mount(s);v=s.fleet[id]
for _=1,210 do
  Sim.daily(s)
  if v.revenue>old_fare then break end
end
assert(v.last_depot_entry_tick>applied and v.road_fault.last_service_tick>=v.last_depot_entry_tick)
assert(v.last_fare.tile==Z and v.revenue>old_fare and v.last_fare.units==carried)
assert(v.road_fault.date_of_last_service>old and v.orders[1].station==a and v.orders[2].station==z)
print(("PASS: exact automatic service depot %d without snapping, original order paid %d riders, in-detour snapshot %s"):
 format(E,v.last_fare.units,tostring(saved)))
