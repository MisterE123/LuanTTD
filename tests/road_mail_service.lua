local root="mods/bayline/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
dofile(root.."town_layout.lua")(S,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
s.road_economy=true;s.road_stock_clock=true;s.road_stock_house_supply=true;s.road_mail=true
local name="Postal Test"
local a,b,d=S.id(11,12),S.id(17,12),S.id(12,13)
assert(S.build(s,name,"road",S.line(a,b)))
assert(S.build_truck_stop(s,name,a))
assert(S.build_truck_stop(s,name,b))
assert(S.build(s,name,"road_depot",{d}))
local aa,bb=s.tiles[a].station,s.tiles[b].station
local id=assert(S.purchase(s,name,"mail_van","mail",nil,d))
local bus=assert(S.purchase(s,name,"bus","passenger",nil,d))
assert(not S.add_order(s,name,bus,aa))
assert(S.add_order(s,name,id,aa) and S.add_order(s,name,id,bb) and S.toggle(s,name,id))
local v=s.fleet[id]
for _=1,260 do S.daily(s); if v.delivered>0 then break end end
assert(v.delivered>0 and v.last_fare.amount>0 and v.units<=22)
assert(s.stations[aa].mail_rating_state and not s.stations[aa].passenger_service_day)
local wait,accepts=S.mail_stop_status(s,s.stations[aa])
assert(wait and accepts)
assert(s.companies[name].paid_units==v.delivered)
print(("PASS: depot-bought mail van actually routed stock-priced house mail, %d bags on first paid trip."):format(v.delivered))
