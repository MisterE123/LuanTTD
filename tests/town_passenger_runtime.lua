local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local H=dofile(root.."openttd/town_passengers.lua")
local P=dofile(root.."openttd/passengers.lua")
local R=dofile(root.."station_rating_runtime.lua")(Sim,dofile(root.."openttd/station_rating.lua"),P)
local T=dofile(root.."town_passenger_runtime.lua")(Sim,H,P,R)
local s=Sim.new(1751)
for _,tile in ipairs(s.tiles) do tile.house=nil end
local house=Sim.id(10,10)
s.tiles[house].house=true
s.tiles[house].variant=2
local function terminal(id,x,z)
  local st={id=id,tile=Sim.id(x,z),mode="road",stock={},last_service={}}
  s.stations[id]=st
  return st
end
local inside=terminal(1,13,13)
local outside=terminal(2,14,10)
local no_service=terminal(3,10,10)
local v={engine="bus",cargo="passenger",bought=0}
for day=1,220 do
  s.day=day
  R.observe_loading(s,inside,v,30)
  R.observe_loading(s,outside,v,30)
  T.day(s)
end
assert(s.tiles[house].source_house.id==0x1A)
assert(P.waiting(inside)>0 and P.waiting(outside)==0 and P.waiting(no_service)==0)
for _,p in ipairs(inside.stock.passenger) do
  assert(p.source==s.tiles[house].source_house.town and p.origin_station==inside.id and p.age==0)
end
assert(s.passenger_house_clock.counter==220*74)
print("PASS: authored house mapping on stock cadence; actual three-tile diagonal catchment, packet source and selective service")
