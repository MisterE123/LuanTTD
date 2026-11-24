-- Stock RT4: construction, native authority, paid rotorcraft and checkpoint.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,T,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Bind=m("campaign_simulation_bindings")(Sim,mod)
local owner="Heliport QA"
local function fixture(year,media)
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  s.air_owned_preview,s.air_fleet_preview=true,true
  s.corner_grid=T.new(64,64,function() return 1 end)
  for i=1,64*64 do s.tiles[i]={terrain="grass",h=1,variant=1} end
  for i,x0 in ipairs({11,47}) do
    local center=Sim.id(x0,23)
    s.sites[i]={id=i,tile=center,kind="town",name="Heliport town",population=260,service=0,stock={},produced={},received={}}
    s.tiles[center].site=i
    for x=x0-3,x0+3 do for z=21,24 do
      if x~=x0 or z~=23 then
        local h=s.tiles[Sim.id(x,z)]
        h.house,h.source_house=true,{id=4,town=i,completed=true}
      end
    end end
  end
  Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),year,false)
  local net,run,owned,roster=Bind.air(s,Slope,function(id) return id==253 or id==215 end,true,media)
  return s,net,run,owned,roster
end
do
  local s,N=fixture(1962,true)
  local q,why=N.quote(s,owner,Sim.id(47,26),"heliport")
  assert(not q and why=="HELIPORT_NOT_INTRODUCED")
  s,N=fixture(1963,false)
  q,why=N.quote(s,owner,Sim.id(47,26),"heliport")
  assert(not q and why=="AIRPORT_TYPE_NOT_AVAILABLE")
end
local state,N,R,O,A=fixture(1963,true)
local first,last=Sim.id(11,26),Sim.id(47,26)
local hangar=assert(N.build(state,owner,first))
local C=m("campaign_transport_commands")(Sim,{world=state,air={network=N,run=R,owned=O,roster=A}})
local opening=Sim.company(state,owner).cash
local q=assert(C.quote(owner,{mode="air",operation="build",tile=last,layout="heliport"}))
assert(q.price==600 and q.tiles[1]==last and #q.tiles==1)
assert(not state.tiles[last].airfield and Sim.company(state,owner).cash==opening)
assert(C.commit(owner,q))
local heliport=assert(N.airport_for(state,last))
assert(heliport.layout=="heliport" and heliport.delta_z==60 and heliport.ground==8 and heliport.owner==owner)
assert(#heliport.tiles==1 and heliport.origin==last and not N.has_hangar(heliport))
assert(state.tiles[last].airfield.layout=="heliport" and state.tiles[last].airfield.owner==owner)
local waiting=m("passenger_waiting_zones")({s=state,Sim=Sim}).air(heliport.id)
local pad_x,pad_z=Sim.xy(last)
assert(#waiting==1 and waiting[1].x>pad_x*2 and waiting[1].x<pad_x*2+.7
  and waiting[1].z>pad_z*2+1.43 and waiting[1].z<pad_z*2+1.49 and waiting[1].y==1.537)
assert(Sim.company(state,owner).cash==opening-600)
local nope,why=O.quote(state,owner,heliport.id,253)
assert(not nope and why=="AIRPORT_HAS_NO_HANGAR")
nope,why=R.route_stop(state,heliport,215)
assert(not nope and why=="HELIPORT_HELICOPTERS_ONLY")
local unit=assert(O.commit(state,owner,assert(O.quote(state,owner,hangar.id,253))))
local depot=assert(C.depot(owner,"air",hangar.id))
local found
for _,offer in ipairs(depot.targets) do if offer.id==heliport.id then found=offer.label end end
assert(found and found:match("^Heliport "))
local flight=assert(O.start(state,owner,hangar.id,heliport.id))
local visited,descended={},false
local function advance(n)
  for _=1,n do
    Sim.daily(state)
    assert(flight.phase~="blocked",flight.failure)
    if flight.last_airfield then visited[flight.last_airfield]=true end
    if flight.last_airfield==heliport.id and flight.phase=="terminal" then
      descended=true
      assert(flight.last_terminal_tile==last and flight.vehicle.y==69)
    end
  end
end
advance(130)
local stats=assert(Sim.air_paid_status(state,unit.id))
assert(stats.fare>0 and visited[hangar.id] and visited[heliport.id] and descended)
local landings=flight.arrivals
local serial=unit.id
local packed=m("packed_campaign")
state=assert(packed.decode(packed.encode(state)))
N,R=Bind.air(state,Slope,function(id) return id==253 or id==215 end,true,true)
flight=assert(R.current(state,serial))
assert(N.airport_for(state,last).delta_z==60 and stats.fare==Sim.air_paid_status(state,serial).fare)
advance(100)
assert(flight.arrivals>landings and Sim.air_paid_status(state,serial).fare>stats.fare)
print(("PASS one-tile RC1 Heliport: Tricario landed at 60 px rooftop, %d terminal stops, $%d paid across restart")
  :format(flight.arrivals,Sim.air_paid_status(state,serial).fare))
