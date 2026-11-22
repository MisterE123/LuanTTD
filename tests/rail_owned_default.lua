-- Reproducible first purchased train on the untouched default generated
-- towns and corner grid. No injected house, grass or rail record.
local root="mods/bayline/"
local function m(f) return dofile(root..f..".lua") end
local function p(f,...) return m("openttd/"..f)(...) end
local Sim=m("sim")
local Terrain=m("openttd/terrain")
local Track=m("openttd/rail_track")
local Slope=m("openttd/slope")
local F=p("rail_follow",Track)
local C=p("rail_yapf_cost",Track,F)
local Search=p("rail_yapf_search",Track,F,C)
local Motion=p("rail_motion",Track)
local PBS=p("rail_reservation",Track,F,C)
local Life=p("rail_consist_reservation",Track,F,PBS)
local Signal=p("rail_signals",Track)
local Consist=p("rail_consist_motion",Track,Motion,F,Life)
local Dispatch=m("rail_consist_dispatch")(Consist,Life)
local Speed=p("rail_station_speed",Track,F)
local Reverse=p("rail_reverse",Track,Motion,Consist,Life,Signal,F,PBS)
local Roster=m("openttd/rail_roster")
local S=Sim.new(1751)
m("town_layout")(Sim,S)
S.corner_grid=m("terrain_preview")(Sim,Terrain,S)
S.road_economy,S.road_stock_clock,S.road_stock_house_supply=true,true,true
S.rail_owned_service,S.rail_paid_service=true,true
local function shape(tile)
  local x,z=Sim.xy(tile)
  return Terrain.tile(S.corner_grid,x,z)
end
local Lab=m("trackworks")(Sim,Track,F,Slope,C,Search,shape)
local Pilot=m("rail_dispatch_run")(Track,F,C,Search,PBS,Life,Signal,Consist,Dispatch,Speed,Lab,nil,Reverse,nil,nil,Roster)
local Owned=m("rail_owned_service")(m("rail_depot_fleet")(Sim,Lab,Roster),Roster,Pilot)
local sh=arg[1]=="sh_8p"
local manley=arg[1]=="manley"
local engine,start,price=manley and 11 or sh and 10 or 0,(manley or sh) and 1960 or 1950,
  manley and 17187 or sh and 36304 or 12866
local n="First Steam"
if sh or manley then Sim.mount_road_bus_market(S,m("openttd/stock_engine_calendar"),start,true) end
local function at(x) return Sim.id(x,5) end
local c=Sim.company(S,n)
local cleared,why,sites=Sim.build(S,n,"clear",{at(2),at(3),at(4)})
assert(cleared and #sites==3,why)
for x=2,4 do assert(not S.tiles[at(x)].wood) end
for x=2,23 do assert(Lab.change(S,n,at(x),0,false,shape(at(x)))) end
assert(Lab.depot(S,n,at(2),2))
assert(Lab.station(S,n,at(5),at(6)))
assert(Lab.station(S,n,at(21),at(23)))
assert(Pilot.place_signal(S,n,at(4),0,4))
assert(Owned.initialize(S,{starting_year=start,climate="temperate",
  generation_seed=1751,startup_random=(1751*1664525+1013904223)%4294967296}))
local selection=manley and {engine} or {engine,27}
if sh or manley then
  local absent,why=Owned.quote(S,n,at(2),selection)
  assert(not absent and why==(sh and "SH_8P_MODEL_NOT_AVAILABLE" or "RAIL_VEHICLE_NOT_MOUNTED"),why)
  assert(Pilot.mount_owned_model(engine))
end
local unit=assert(Owned.commit(S,n,assert(Owned.quote(S,n,at(2),selection))))
assert(unit.price==price)
Sim.mount_paid_rail(S,Pilot)
local a,b=S.tiles[at(21)].rail_station_id,S.tiles[at(5)].rail_station_id
assert(Owned.start(S,n,unit.id,a,b))
local settled
for _=1,200 do
  Sim.daily(S)
  local s=assert(Sim.rail_paid_status(S))
  assert(s.waiting[a].accepts and s.waiting[b].accepts)
  if c.revenue>0 then settled=s;break end
end
assert(settled and settled.fare==c.revenue and settled.delivered==c.paid_units)
print(("PASS default seed 1751 stock towns: row Z=5, depot X=2, platforms 5..6 and 21..23; %d seats paid $%d")
  :format(settled.delivered,settled.fare))
if sh then
  local run=assert(Pilot.current_paid(S))
  assert(run.stock_engine==10 and run.visual=="sh_8p" and run.max_track_speed==144 and run.stock_steps>100)
  assert(Owned.running(S,n,unit.id).running_year_fp==728000)
end
if manley then
  local run=assert(Pilot.current_paid(S))
  assert(run.stock_engine==11 and run.visual=="manley_morel" and run.max_track_speed==112 and run.stock_steps>100)
  assert(settled.capacity==76 and #settled.carrying_parts==2)
  assert(Owned.running(S,n,unit.id).running_year_fp==436800)
end
