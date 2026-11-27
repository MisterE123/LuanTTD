-- RC1 objects share slots by physical entity, not UI domain or row ID.
local mod="mods/luanttd_core/"
local P=dofile(mod.."openttd/object_pool_rc1.lua")
local S=dofile(mod.."sim.lua")
local used={}
for _,id in ipairs({0,2,4}) do P.occupy(used,id,7) end
local free=assert(P.reserve(used,4,7))
assert(table.concat(free,",")=="1,3,5,6")
assert(not P.reserve(used,5,7) and not used[1])
assert(not pcall(P.occupy,used,4,7))
local ship={id=2,neutral=true,stock_station_id=1}
local air={id=2,neutral=true,stock_station_id=1}
local lease={id=4,stock_station_id=3}
local state={stock_pool_authority=true,day=0,passenger_house_clock={counter=1280},
 stations={[1]={stock_station_id=0}},stock_neutral_stations={[2]={stock_station_id=1}},
 stock_rail_stations={[1]={stock_station_id=2}}, stock_ship_stations={[2]=ship},
 stock_small_airports={[2]=air},retired_ship_stations={[4]={row=lease,until_tick=1281}}}
assert(S.stock_station_slot(state)==4)
state.passenger_house_clock.counter=1281
assert(S.stock_station_slot(state)==3)
state.stock_rail_stations[1]=nil
assert(S.stock_station_slot(state)==2)
local fleet={fleet={[5]={stock_pool_id=1}},stock_rail_fleet={
  units={[1]={parts={{stock_pool_id=0},{stock_pool_id=2}}}},
  loose={[1]={parts={{stock_pool_id=3}}}}}}
assert(table.concat(S.stock_vehicle_slots(fleet,2),",")=="4,5")
fleet.fleet[5]=nil
assert(S.stock_vehicle_slots(fleet,1)[1]==1)
print("PASS shared station/waypoint, neutral aliases, retired leases, and physical vehicle slot reuse")
