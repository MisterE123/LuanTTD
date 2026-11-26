local root="mods/luanttd_core/"
local function m(n)return dofile(root..n..".lua")end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local Water=m("openttd/ship_follow")(Track)
local F=m("openttd/ship_facilities")(Track,Water)
local N=m("ship_network")(Sim,T,Water,F)
local Members=m("dock_station_members")
local at=Sim.id
local s=Sim.new(2)
s.corner_grid=T.new(Sim.W,Sim.H,function(x)return x<15 and 1 or 0 end)
for i in ipairs(s.tiles) do
  local x=Sim.xy(i)
  s.tiles[i]={terrain=x>=15 and "water" or "grass",h=x<15 and 1 or 0,
    coastal_water=x==14 or nil,water_class=x>=15 and "sea" or nil}
end
local company=Sim.company(s,"A")
local start=company.cash
local function build(z,req,owner)
  local p,e=N.build(s,owner or "A","dock",at(14,z),nil,req)
  assert(p,e)
  return p
end
local first=build(10)
local second=build(11)
assert(second.id==first.id and s.next_stock_ship_station==first.id+1)
local separate=build(13,{adjacent=true})
assert(separate.id~=first.id)
local none,why=N.quote(s,"A","dock",at(14,12))
assert(not none and why=="ADJOINS_MULTIPLE_STATIONS")
local foreign=build(14,nil,"B")
local pick=assert(N.join_choices(s,"A",at(14,12)))
assert(#pick.choices==3 and not pick.choices[1].id)
for _,r in ipairs(pick.choices) do assert(r.id~=foreign.id) end
none,why=N.quote(s,"A","dock",at(14,12),nil,{join=foreign.id,adjacent=true})
assert(not none and why=="OWNED_BY")
assert(company.cash==start-3*390)
s.ship_pilot={vehicle={tile=at(15,20)}}
none,why=N.quote(s,"A","dock",at(14,20),nil,{join=first.id,adjacent=true})
assert(not none and why=="VEHICLE_IN_THE_WAY")
s.ship_pilot=nil
local distant=build(20,{join=first.id,adjacent=true})
assert(distant.id==first.id)
none,why=N.quote(s,"A","dock",at(14,23),nil,{join=first.id,adjacent=true})
assert(not none and why=="STATION_SPREAD")
local station=s.stock_ship_stations[first.id]
local cells=Members.footprint(station,Sim.xy)
assert(#cells==6 and station.spread.w==2 and station.spread.h==11)
local B=N.board(s)
local from=at(20,16)
assert(B.closest_station_tile(first.id,from)==at(16,16))
local berths=B.station_dock_tiles(first.id)
local seen={}
for _,id in ipairs(berths) do
  assert(not seen[id] and Water.ship_destination(B,id,first.id))
  seen[id]=true
end
assert(seen[at(16,10)] and seen[at(16,11)] and seen[at(16,20)])
s.stock_distant_join_stations=false
none,why=N.quote(s,"A","dock",at(14,18),nil,{join=first.id,adjacent=true})
assert(not none and why=="INVALID_STATION_TO_JOIN")
s.stock_distant_join_stations=nil
local zones=m("passenger_waiting_zones")({s=s,Sim=Sim,terrain={
  tile=function(id)return T.tile(s.corner_grid,Sim.xy(id)) end}})
assert(#zones.ship(first.id)==3,"One native queue area per joined pier")
local tiles,cost=N.remove(s,"A",first.water,nil,true)
assert(#tiles==2 and tiles[1]==first.land and tiles[2]==first.water and cost==55)
assert(N.active_partial_remove(s,first.water))
s.ship_pilot={last_dock=first.id,vehicle={tile=at(16,10),loading=true,last_station=first.id}}
s.stock_coal_ship_run={last_dock=first.id,vehicle={tile=at(16,11),loading=true,last_station=first.id}}
s.stock_oil_ship_route={last_dock=foreign.id,vehicle={tile=at(16,14),loading=true,last_station=foreign.id}}
assert(N.remove(s,"A",first.water))
assert(s.ship_pilot.dock_forced_leave and not s.stock_coal_ship_run.dock_forced_leave and
  not s.stock_oil_ship_route.dock_forced_leave,"Only the invalidated visit should leave")
assert(s.stock_ship_stations[first.id]==station and station.land==second.land and station.sign_tile==second.land)
assert(s.tiles[first.land].coastal_water and not s.tiles[first.land].ship and not s.tiles[first.water].ship)
assert(s.tiles[second.water].ship.station==first.id and s.tiles[distant.water].ship.station==first.id)
assert(not Water.ship_destination(B,at(16,10),first.id) and Water.ship_destination(B,at(16,20),first.id))
cells=Members.footprint(station,Sim.xy)
assert(#cells==4 and station.spread.h==10 and #zones.ship(first.id)==2)
print("PASS default and explicit dock joining, conflicts, foreign ownership, 12-tile spread, union catchment/berths, stock destination clamp and physical partial demolition")
