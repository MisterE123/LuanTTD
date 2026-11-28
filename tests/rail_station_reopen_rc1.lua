-- Stock 16.0-RC1 regular commands, captured from an already running
-- Temperate campaign with bus, wood and Goods services. Numerical fields
-- are physical station identity, actual sign, station counter and ages.
local base="mods/luanttd_core/"
local function m(n) return dofile(base..n..".lua") end
local Sim,Track,G,Codec=m("sim"),m("openttd/rail_track"),m("openttd/town_growth"),m("packed_campaign")
local Lib=m("trackworks")(Sim,Track,nil,m("openttd/slope"))
local Retired,Views=Sim.road_station_retirement(),m("town_station_services")(Sim)
Sim.W,Sim.H=128,128
local s=Sim.new(1751)
local a,b=Sim.id(69,64),Sim.id(70,64)
local owner="Source comparison"
s.stock_pool_authority,s.stock_engine_startup_seed=true,1751
s.passenger_house_clock={counter=12600}
for i=0,4 do s.stations[100+i]={id=100+i,stock_station_id=i,mode="road",owner=owner,tile=Sim.id(20+i,21)} end
s.passenger_rating_rng={3411287708,1941530451}
assert(Lib.commit_station(s,owner,{a},0))
local p=s.stock_rail_stations[1]
assert(p.stock_station_id==5 and p.sign_tile-1==8132 and p.stock_random_bits==33746)
assert(s.tiles[a].stock_station_random_bits==14)
assert(s.passenger_rating_rng[1]==2133718699 and s.passenger_rating_rng[2]==3833784094)
p.name="Rail Way"
-- A station's carrier age can be 20 at removal even when the inactive
-- station is no longer an order target. The fixture seeds that field.
s.rail_paid_service=true
s.stock_ship_commercial={service={stations={
  {host_mode="rail",host_id=p.id,owner=owner,time_since_load=20,time_since_unload=255},
}}}
s.passenger_house_clock.counter=12604
assert(Lib.remove_facility(s,owner,a))
local old=Retired.get(s,"rail",1)
assert(old.stock_station_id==5 and old.tile-1==8132 and old.time_since_load==20)
assert(s.tiles[a].stock_station_random_bits==nil and not s.stock_rail_stations[1])
s.stock_ship_commercial=nil
s=assert(Codec.decode(Codec.encode(s)))
s.passenger_house_clock.counter=13315
s.passenger_rating_rng={3709208607,2440490597}
local q=assert(Lib.retired_station(s,owner,b))
assert(q.id==1)
assert(Lib.commit_station(s,owner,{b},0,nil,nil,nil,nil,q.id))
p=s.stock_rail_stations[1]
assert(p.name=="Rail Way" and p.stock_station_id==5 and p.sign_tile-1==8133)
assert(p.stock_random_bits==49410 and s.tiles[b].stock_station_random_bits==1)
assert(s.passenger_rating_rng[1]==233814719 and s.passenger_rating_rng[2]==37982641)
assert(s.next_stock_rail_station==2 and not Retired.get(s,"rail",1))
local t=G.new(1,70,64)
for i,time in ipairs({13315,13316,13498,13505}) do
  local load,unload,phase=Views.reactivated_clocks(s,p,time)
  assert(load==(i<3 and 20 or 21) and unload==255 and phase==({3,4,1,8})[i])
  assert(G.active_stations(t,Views.view(s,false,time))==(i<3 and 1 or 0))
end
-- Per-tile draws for Axis Y run down a track before moving across.
s.passenger_rating_rng={14458292,5577991}
local k,l,n,o=Sim.id(72,77),Sim.id(73,77),Sim.id(72,78),Sim.id(73,78)
local draw={passenger_rating_rng={unpack(s.passenger_rating_rng)}}
local bit=Sim.stock_random_u32(draw)%65536
local values={}
for _,i in ipairs({k,n,l,o}) do values[i]=Sim.stock_random_u32(draw)%16 end
assert(Lib.commit_station(s,owner,{k,l,n,o},1))
assert(s.stock_rail_stations[2].stock_random_bits==bit)
for _,i in ipairs({k,l,n,o}) do assert(s.tiles[i].stock_station_random_bits==values[i]) end
assert(draw.passenger_rating_rng[1]==s.passenger_rating_rng[1] and draw.passenger_rating_rng[2]==s.passenger_rating_rng[2])
print("PASS live RC1 rail sign renewal: physical ID 5, two draws, delayed rating and 20/21 service-age boundary")
