-- SPDX-License-Identifier: GPL-2.0-only
-- Real Sim construction against both CmdBuildAirport command boundaries
-- from pinned RC1 active bus/Wood/Goods save (seed 1751, tile 43,52).
local path="mods/luanttd_core/"
local function m(n) return dofile(path..n..".lua") end
local S,T,Codec=m("sim"),m("openttd/terrain"),m("packed_campaign")
local Air=m("airport_network")(S,T,m("openttd/airport_small"))
S.W,S.H=128,128
local s=S.new(1751)
local a,b,sign=S.id(44,53),S.id(48,94),S.id(44,48)
local owner="Company 0"
s.stock_pool_authority,s.stock_engine_startup_seed=true,1751
s.passenger_house_clock={counter=12601}
s.corner_grid=T.new(128,128,function() return 1 end)
for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=1} end
for n=0,4 do
  local i=n+10
  local tile=n==1 and sign or S.id(20+n,21)
  s.stations[i]={id=i,stock_station_id=n,mode="road",owner=owner,tile=tile}
  s.tiles[tile].station=i
end
local road=s.stations[11]
road.name,road.town,road.stock_random_bits="Original Road Sign",1,1234
road.passenger_rating_phase=36
road.time_since_load,road.time_since_unload=3,3
road.stock={passenger={{units=2}}}
S.company(s,owner)
-- The native command runs after town/landscape ticks, one draw after
-- the previous tick snapshot. This is the command-local entry state.
s.passenger_rating_rng={1125868558,1877327572}
assert(not Air.quote(s,owner,a,"country",false,{adjacent=true,station_id=99}))
assert(assert(Air.quote(s,owner,a,"country",false,{adjacent=true,station_id=1})).join_road==11)
assert(s.passenger_rating_rng[1]==1125868558 and s.passenger_rating_rng[2]==1877327572)
local p=assert(Air.build(s,owner,a,"country",false,{adjacent=true,station_id=1}))
assert(p.origin-1==43+128*52 and p.stock_station_id==1 and p.sign_tile-1==6059)
assert(p.name==road.name and p.town==road.town and p.stock_random_bits==1234)
assert(s.passenger_rating_rng[1]==1325208057 and s.passenger_rating_rng[2]==2856099540)
assert(road.passenger_rating_phase==36 and road.stock.passenger[1].units==2)
local group=s.stock_joined_stations[1]
assert(group.facilities==12 and group.members.road==11 and group.members.air==p.id)
local q=assert(Air.build(s,owner,b,"country",false,{adjacent=true,new_station=true}))
assert(q.stock_station_id==5)
assert(s.passenger_rating_rng[1]==1094152317 and s.passenger_rating_rng[2]==2134237113)
s=assert(Codec.decode(Codec.encode(s)))
p=Air.airport_for(s,a)
assert(S.stock_joined_station.resolve(s,1,"air",p.id,p).tile==sign)
local Views=m("town_station_services")(S)
s.stations[11].town_growth_service_clock=true
s.air_paid_service=true
s.stock_ship_commercial={service={stations={
  {host_mode="air",host_id=p.id,owner=owner,time_since_load=2,time_since_unload=4},
}}}
local views=Views.view(s,false)
assert(#views==1 and views[1].id==11 and views[1].mode=="road")
assert(views[1].x==44 and views[1].z==48 and views[1].time_since_load==2 and views[1].time_since_unload==3)
s.stock_ship_commercial=nil
assert(select(2,Air.quote(s,owner,S.id(49,53),"country",false,{adjacent=true,station_id=1}))=="TOO_CLOSE_TO_ANOTHER_AIRPORT")
assert(Air.remove(s,owner,a,false))
assert(not (s.retired_airports or {})[p.id] and s.stock_joined_stations[1].facilities==4)
assert(s.stations[11].stock.passenger[1].units==2)
assert(S.stock_station_slot(s)==6)
local joined_again=assert(Air.build(s,owner,a,"country",false,{adjacent=true,station_id=1}))
S.retire_road_station(s,11)
assert(not (s.retired_road_stations or {})[11] and s.stock_joined_stations[1].facilities==8)
assert(joined_again.stock_station_id==1 and joined_again.sign_tile==a)
assert(S.stock_station_slot(s)==6)
print("PASS RC1 joined airport command: exact physical ID, sign, no sign draw, split removal, and separate airport RNG")
