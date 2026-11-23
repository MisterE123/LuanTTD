local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
dofile(root.."town_layout.lua")(S,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
s.road_economy=true;s.road_stock_clock=true;s.road_stock_house_supply=true;s.road_mail=true
local mode=arg and arg[1]
local engine=mode or "mail_van"
local market={mail_mps={1950,126,22},mail_reynard={1985,127,28},mail_perry={2025,128,30}}
local chosen=market[engine]
if chosen then
  s.road_stock_loading=true
  local E=dofile(root.."openttd/stock_engine_calendar.lua")
  S.mount_road_bus_market(s,E,chosen[1],true,true,{[engine]=true})
  assert(S.vehicle_available(s,engine))
  S.mount_road_bus_market(s,E,chosen[1],true,true,{})
  assert(not S.vehicle_available(s,engine),"Missing model must not be for sale")
  S.mount_road_bus_market(s,E,chosen[1],true,true,{[engine]=true})
  assert(S.vehicle_offer(s,engine).stock_engine_id==chosen[2])
end
local name="Postal Test"
local a,b,d=S.id(11,12),S.id(17,12),S.id(12,13)
assert(S.build(s,name,"road",S.line(a,b)))
assert(S.build_truck_stop(s,name,a))
assert(S.build_truck_stop(s,name,b))
assert(S.build(s,name,"road_depot",{d}))
local aa,bb=s.tiles[a].station,s.tiles[b].station
local id=assert(S.purchase(s,name,engine,"mail",nil,d))
if not mode then local bus=assert(S.purchase(s,name,"bus","passenger",nil,d));assert(not S.add_order(s,name,bus,aa)) end
assert(S.add_order(s,name,id,aa) and S.add_order(s,name,id,bb) and S.toggle(s,name,id))
local v=s.fleet[id]
for _=1,260 do S.daily(s); if v.delivered>0 then break end end
assert(v.delivered>0 and v.last_fare.amount>0 and v.units<=(chosen and chosen[3] or 22))
assert(s.stations[aa].mail_rating_state and not s.stations[aa].passenger_service_day)
local wait,accepts=S.mail_stop_status(s,s.stations[aa])
assert(wait and accepts)
assert(s.companies[name].paid_units==v.delivered)
if chosen then
  assert(S.vehicle_capacity(v)==chosen[3] and v.expense>0)
  local before=v.delivered
  local function copy(t)
    if type(t)~="table" then return t end
    local o={};for k,y in pairs(t) do o[k]=copy(y) end;return o
  end
  s=copy(s);v=s.fleet[id]
  local E=dofile(root.."openttd/stock_engine_calendar.lua")
  S.mount_road_bus_market(s,E,chosen[1],true,true,{[engine]=true})
  for _=1,260 do S.daily(s);if v.delivered>before then break end end
  assert(v.delivered>before and v.expense>0)
end
print(("PASS: depot-bought mail van actually routed stock-priced house mail, %d bags on first paid trip."):format(v.delivered))
