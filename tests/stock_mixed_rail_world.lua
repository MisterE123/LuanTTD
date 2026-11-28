-- SPDX-License-Identifier: GPL-2.0-only
-- Command and removal boundaries for a shared bus/rail station.
local mod="mods/luanttd_core/"
local function m(p) return dofile(mod..p..".lua") end
local S,T,Codec=m("sim"),m("openttd/rail_track"),m("packed_campaign")
local Trackworks=m("trackworks")(S,T,nil,m("openttd/slope"))
local Join=m("rail_road_station_join")(S)
S.W,S.H=128,128
local s=S.new(1751)
local owner="Company 0"
local sign,platform=S.id(44,48),S.id(44,54)
local area={x=44,z=54,w=1,h=1}
s.stock_pool_authority,s.stock_engine_startup_seed=true,1751
s.passenger_house_clock={counter=12602}
s.passenger_rating_rng={1125868558,1877327572}
local road={id=31,mode="road",owner=owner,tile=sign,stock_station_id=0,town=1,name="Bus Sign",
  stock_random_bits=0x5678,stock={passenger={{units=2}}},passenger_rating_phase=37,road_members={[sign]="bus"}}
s.stations[31]=road;s.tiles[sign].station=31
local function expect(target,reason,p)
  local id,why=Join.quote(s,owner,p or area,target)
  assert(id==nil and why==reason,tostring(why))
end
expect(71,"INVALID_STATION")
s.stock_distant_join_stations=false
expect(0,"INVALID_STATION")
s.stock_distant_join_stations=true
local other={id=32,mode="road",owner="Rival",tile=S.id(44,49),stock_station_id=2}
s.stations[32]=other;s.tiles[other.tile].station=32
expect(2,"NOT_STATION_OWNER")
expect(0,"STATION_TOO_SPREAD_OUT",{x=44,z=60,w=1,h=1})
local rows=Join.choices(s,owner,area)
assert(#rows==2 and rows[1].id==nil and rows[2].id==0 and rows[2].name=="Bus Sign")
local id=assert(Join.quote(s,owner,area,0))
assert(id==31)
local next_rng={passenger_rating_rng={unpack(s.passenger_rating_rng)}}
local next_tile=S.stock_random_u32(next_rng)%16
assert(Trackworks.commit_station(s,owner,{platform},0,area,nil,0,{},nil,id))
assert(s.tiles[platform].stock_station_random_bits==next_tile)
assert(s.passenger_rating_rng[1]==next_rng.passenger_rating_rng[1] and s.passenger_rating_rng[2]==next_rng.passenger_rating_rng[2])
local function check(state)
  local rail=state.stock_rail_stations[state.tiles[platform].rail_station_id]
  assert(rail.stock_station_id==0 and rail.sign_tile==sign and rail.stock_random_bits==0x5678 and rail.town==1)
  local group=assert(Join.group(state,rail))
  assert(group.facilities==5 and group.members.road==31 and group.members.rail==rail.id)
  assert(S.stock_station_slot(state)==1)
  return rail,group
end
s=assert(Codec.decode(Codec.encode(s)))
local rail,group=check(s)
local rx=Join.road_extent(s,rail)
assert(rx.x==44 and rx.z==48 and rx.w==1 and rx.h==1)
assert(Trackworks.remove_facility(s,owner,platform))
assert(not (s.retired_rail_stations or {})[rail.id] and group.facilities==4 and not s.tiles[platform].rail_station_id)
assert(s.stations[31].stock.passenger[1].units==2)
assert(Trackworks.commit_station(s,owner,{platform},0,area,nil,0,{},nil,31))
rail,group=check(s)
S.retire_road_station(s,31)
assert(not (s.retired_road_stations or {})[31] and group.facilities==1 and not group.members.road)
assert(rail.stock_station_id==0 and rail.sign_tile==platform and S.stock_station_slot(s)==1)
print("PASS shared bus/rail selection, foreign ownership, stock RNG, packed rebind and partial removal in both directions")
