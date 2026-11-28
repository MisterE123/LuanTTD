-- Build and fly a paid source-era route between the two ground rotor fields.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,T,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Bind=m("campaign_simulation_bindings")(Sim,mod)
local owner="Ground rotary QA"
local function fixture(year,ready)
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  s.air_owned_preview,s.air_fleet_preview=true,true
  s.corner_grid=T.new(64,64,function() return 1 end)
  for i=1,64*64 do s.tiles[i]={terrain="grass",h=1,variant=1} end
  for i,x0 in ipairs({11,47}) do
    local center=Sim.id(x0,23)
    s.sites[i]={id=i,tile=center,kind="town",name="Rotary town",population=260,service=0,stock={},produced={},received={}}
    s.tiles[center].site=i
    for x=x0-3,x0+4 do for z=21,24 do
      if x~=x0 or z~=23 then
        local h=s.tiles[Sim.id(x,z)]
        h.house,h.source_house=true,{id=4,town=i,completed=true}
      end
    end end
  end
  Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),year,false)
  local net,run,owned,roster=Bind.air(s,Slope,function(id) return id==253 or id==215 end,true,true,ready)
  return s,net,run,owned,roster
end
local ready={helidepot=true,helistation=true}
do
  local old,N=fixture(1975,ready)
  local q,w=N.quote(old,owner,Sim.id(47,26),"helidepot")
  assert(not q and w=="HELIDEPOT_NOT_INTRODUCED")
  old,N=fixture(1979,ready)
  q,w=N.quote(old,owner,Sim.id(47,26),"helistation")
  assert(not q and w=="HELISTATION_NOT_INTRODUCED")
  assert(N.quote(old,owner,Sim.id(47,26),"helidepot"))
  old,N=fixture(1980,{helidepot=true})
  q,w=N.quote(old,owner,Sim.id(47,26),"helistation")
  assert(not q and w=="AIRPORT_TYPE_NOT_AVAILABLE")
end
local s,N,R,O,A=fixture(1980,ready)
local h=m("hotbar")
h.enable_airfields(true,true,true,ready)
assert(h.menus.airfields[6][1]=="section_rotary_airfields")
assert(h.menus.rotary_airfields[2][1]=="heliport_build" and h.menus.rotary_airfields[3][1]=="helidepot_build"
  and h.menus.rotary_airfields[4][1]=="helistation_build" and h.menus.rotary_airfields[9][1]=="clear")
local C=m("campaign_transport_commands")(Sim,{world=s,air={network=N,run=R,owned=O,roster=A}})
for _,a in ipairs({{11,"helidepot",4},{47,"helistation",8}}) do
  local q=assert(C.quote(owner,{mode="air",operation="build",tile=Sim.id(a[1],26),layout=a[2]}))
  assert(q.price==a[3]*600 and #q.tiles==a[3])
  assert(C.commit(owner,q))
end
local source,destination=N.airport_for(s,Sim.id(12,26)),N.airport_for(s,Sim.id(47,26))
assert(source.id==1 and destination.id==2 and N.has_hangar(source) and N.has_hangar(destination))
local zones=m("passenger_waiting_zones")({s=s,Sim=Sim})
assert(zones.air(source.id)[1].x>22 and zones.air(source.id)[1].x<23)
assert(zones.air(destination.id)[1].x>96 and zones.air(destination.id)[1].x<97)
local nope,reason=O.quote(s,owner,source.id,215)
assert(not nope and reason=="LARGER_AIRFIELD_REQUIRED")
local aircraft=assert(O.commit(s,owner,assert(O.quote(s,owner,source.id,253))))
local flight=assert(O.start(s,owner,source.id,destination.id))
local first,last=0,0
local function advance(n)
  for _=1,n do
    Sim.daily(s)
    assert(flight.phase~="blocked",flight.failure)
    if flight.phase=="terminal" then
      assert(flight.vehicle.y==9 and flight.last_terminal_tile)
      if flight.last_airfield==source.id then first=first+1 else last=last+1 end
    end
  end
end
advance(100)
local stats=assert(Sim.air_paid_status(s,aircraft.id))
assert(stats.fare>0 and first>0 and last>0)
local arrivals=flight.arrivals
local Packed=m("packed_campaign")
s=assert(Packed.decode(Packed.encode(s)))
N,R=Bind.air(s,Slope,function(id) return id==253 end,true,true,ready)
flight=assert(R.current(s,aircraft.id))
assert(flight.arrivals==arrivals and Sim.air_paid_status(s,aircraft.id).fare==stats.fare)
advance(100)
assert(flight.arrivals>=arrivals+2 and Sim.air_paid_status(s,aircraft.id).fare>stats.fare)
print(("PASS RC1 ground rotor facilities: exact budgets, dated offers, %d terminals and $%d across save")
  :format(flight.arrivals,Sim.air_paid_status(s,aircraft.id).fare))

-- The first order is not a spawn point. RC1 starts from the owned
-- hangar and departs directly for the selected remote first stop.
local reversed,net,run,owned=fixture(1980,ready)
local home=assert(net.build(reversed,owner,Sim.id(11,26),"helidepot"))
local away=assert(net.build(reversed,owner,Sim.id(47,26),"helistation"))
local heli=assert(owned.commit(reversed,owner,assert(owned.quote(reversed,owner,home.id,253))))
local route=assert(owned.start(reversed,owner,away.id,home.id,heli.id))
assert(route.target==home.id and route.vehicle.hidden and route.vehicle.target==home.id)
assert(route.first==away.id and route.vehicle.order.id==away.id and route.second==home.id)
for day=1,50 do
  Sim.daily(reversed)
  assert(route.phase~="blocked",route.failure)
  if route.arrivals>0 then break end
end
assert(route.arrivals==1 and route.last_airfield==away.id)
print("PASS RC1 aircraft leaves its actual hangar for the remote first order")
