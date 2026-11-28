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

-- Inactive dock IDs cannot be orders or berths, but stock station
-- construction can reactivate one with the same name and owner.
do
  local s=Sim.new(2)
  s.passenger_house_clock={counter=350}
  s.corner_grid=T.new(Sim.W,Sim.H,function(x)return x<15 and 1 or 0 end)
  for i in ipairs(s.tiles) do
    local x=Sim.xy(i)
    s.tiles[i]={terrain=x>=15 and "water" or "grass",h=x<15 and 1 or 0,
      coastal_water=x==14 or nil,water_class=x>=15 and "sea" or nil}
  end
  local A,C=Sim.company(s,"A"),Sim.company(s,"B")
  local function site(z) return at(14,z) end
  local function build(z,opts,owner)
    return assert(N.build(s,owner or "A","dock",site(z),nil,opts))
  end
  local function quote(z,opts,owner)
    return N.quote(s,owner or "A","dock",site(z),nil,opts)
  end
  local function retire(p)
    local before=assert(s.stock_ship_stations[p.id])
    assert(N.remove(s,"A",p.water,nil,true))
    assert(s.stock_ship_stations[p.id]==before and not (s.retired_ship_stations or {})[p.id])
    assert(N.remove(s,"A",p.water))
    assert(not s.stock_ship_stations[p.id] and not s.tiles[p.water].ship)
    assert(#N.board(s).station_dock_tiles(p.id)==0)
    assert(not Water.ship_destination(N.board(s),p.approach,p.id))
  end
  local old=build(10)
  s.stock_ship_stations[old.id].name="Tidewater Wharf"
  local service=m("town_station_services")(Sim)
  s.ship_paid_service=true
  s.stock_ship_commercial={service={stations={
    {host_mode="ship",host_id=old.id,owner="A",time_since_load=4,time_since_unload=8},
  }}}
  retire(old)
  s.stock_ship_commercial=nil
  local served=assert(service.view(s)[1])
  assert(served.mode=="ship" and served.id==old.id and served.time_since_load==4 and served.time_since_unload==8)
  local record=s.retired_ship_stations[old.id]
  assert(record.until_tick==2249 and record.row.tile==old.land and record.row.land==nil)
  assert(quote(17).join==old.id and not quote(18).join,"Manhattan distance is strictly below eight")
  assert(not quote(11,nil,"B").join,"Do not reuse another company's station")
  assert(not quote(11,{adjacent=true}).join,"NEW_STATION bypasses reuse")
  local choices=assert(N.join_choices(s,"A",site(17))).choices
  assert(#choices==2 and choices[2].id==old.id and choices[2].name:find("Tidewater Wharf",1,true))
  local candidate=assert(N.join_choices(s,"B",site(17))).choices
  assert(#candidate==1)
  local none,why=quote(11,{join=old.id,adjacent=true},"B")
  assert(not none and why=="OWNED_BY")
  -- Round-trip the tombstone before moving the dock; active routing
  -- must not see it even after the durable campaign is reopened.
  local packed=m("packed_campaign")
  s=packed.decode(packed.encode(s))
  local next_=s.next_stock_ship_station
  local same=build(17)
  assert(same.id==old.id and s.next_stock_ship_station==next_ and not s.retired_ship_stations[old.id])
  local restored=s.stock_ship_stations[old.id]
  assert(restored.land==same.land and restored.sign_tile==same.land and #restored.docks==1
    and restored.name=="Tidewater Wharf")
  assert(Water.ship_destination(N.board(s),same.approach,old.id))
  local active=build(19,{adjacent=true})
  retire(same)
  assert(quote(18).join==active.id,"An adjoining active station wins over nearby inactive IDs")
  local reopened=build(9,{join=same.id,adjacent=true})
  assert(reopened.id==old.id)
  retire(reopened)
  local other=build(15,{adjacent=true})
  retire(other)
  assert(quote(12).join==old.id,"Lowest StationID breaks a tie")
  -- The adapter handles a lost loading berth on its next motion step.
  -- Do not reuse its former ID before that pending operation is settled.
  s.ship_pilot={dock_forced_leave=true,vehicle={last_station=old.id,tile=old.approach,loading=true}}
  assert(quote(12).join==other.id)
  s.ship_pilot=nil
  local cutoff=s.retired_ship_stations[old.id].until_tick
  s.passenger_house_clock.counter=cutoff-1
  assert(quote(9,{join=old.id,adjacent=true}).join==old.id)
  s.passenger_house_clock.counter=cutoff
  local expired,why=quote(9,{join=old.id,adjacent=true})
  assert(not expired and why=="INVALID_STATION_TO_JOIN")
  Sim.road_station_retirement().expire(s)
  assert(not s.retired_ship_stations[old.id])
  assert(build(9).id~=old.id)
end
print("PASS final dock retirement: owned and inactive, exact timeout, tie priority, separate build, named identity and save/reopen")
