-- SPDX-License-Identifier: GPL-2.0-only
-- Build in either order, then remove individual facilities through their
-- normal commands without losing the physical station or its service ID.
local mod="mods/luanttd_core/"
local function m(p) return dofile(mod..p..".lua") end
local S,T,Track=m("sim"),m("openttd/terrain"),m("openttd/rail_track")
local Air=m("airport_network")(S,T,m("openttd/airport_small"))
local Rail=m("trackworks")(S,Track,nil,m("openttd/slope"))
local Join=m("rail_road_station_join")(S)
local Catalog=m("stock_station_catalog")(S)
local Views=m("town_station_services")(S)
local Codec=m("packed_campaign")
local owner="Joint operator"
S.W,S.H=128,128
local sign,field,track=S.id(44,48),S.id(44,55),S.id(48,46)
local area={x=48,z=46,w=1,h=1}
for _,air_first in ipairs({true,false}) do
  local s=S.new(1751)
  s.stock_pool_authority,s.stock_engine_startup_seed=true,1751
  s.passenger_house_clock={counter=12602}
  s.corner_grid=T.new(128,128,function() return 1 end)
  for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=1} end
  local road={id=31,mode="road",owner=owner,tile=sign,stock_station_id=0,town=1,name="Common sign",
    stock_random_bits=1234,stock={passenger={{units=2}}},road_members={[sign]="bus"}}
  s.stations[31]=road;s.tiles[sign].station=31
  S.company(s,owner)
  local function airport()
    if not air_first then
      local _,why=Air.quote(s,owner,S.id(44,56),"country",false,{adjacent=true,station_id=0})
      assert(why=="STATION_TOO_SPREAD_OUT")
    end
    local q=assert(Air.join_choices(s,owner,field,"country"))
    assert(q.choices[2].id==0)
    assert(Air.build(s,owner,field,"country",false,{adjacent=true,station_id=0}))
  end
  local function rail()
    local q=Join.choices(s,owner,area);assert(q[2].id==0)
    local id=assert(Join.quote(s,owner,area,0))
    assert(Rail.commit_station(s,owner,{track},0,area,nil,0,{},nil,id))
  end
  if air_first then airport();rail() else rail();airport() end
  s=assert(Codec.decode(Codec.encode(s)))
  local group=assert(s.stock_joined_stations[0])
  local airport=assert(s.stock_small_airports[group.members.air])
  local platform=assert(s.stock_rail_stations[group.members.rail])
  assert(group.facilities==13 and group.tile==sign and airport.sign_tile==sign and platform.sign_tile==sign)
  assert(S.stock_station_slot(s)==1 and #Views.view(s,true)==1)
  local spread=assert(Catalog.board(s).station(0)).spread
  assert(spread.tile==S.id(44,46) and spread.w==5 and spread.h==12)
  -- Back to air + rail. Both modes keep the original physical ID, hence
  -- Local Authority and growth continue to count one station, not two.
  group.service_station_id=49153
  s.air_paid_service,s.rail_paid_service=true,true
  local ledger={id=49153,host_mode="air",host_id=airport.id,owner=owner,time_since_load=2,
    time_since_unload=4,loading_order={},joined_road=31}
  s.stock_ship_commercial={service={stations={[49153]=ledger}}}
  S.retire_road_station(s,31)
  assert(group.facilities==9 and group.service_station_id==49153 and S.stock_station_slot(s)==1)
  assert(group.tile==sign and airport.sign_tile==sign and platform.sign_tile==sign and #Views.view(s,true)==1)
  assert(ledger.joined_road==nil and ledger.host_mode=="air")
  assert(Air.remove(s,owner,field,false))
  assert(group.facilities==1 and group.service_station_id==49153 and group.tile==track and platform.sign_tile==track)
  assert(not (s.retired_airports or {})[airport.id] and #Views.view(s,true)==1)
  assert(ledger.host_mode=="rail" and ledger.host_id==platform.id and ledger.sign.x==48 and ledger.sign.y==46)
  assert(Rail.remove_facility(s,owner,track))
  assert(not s.stock_joined_stations[0] and #Views.view(s,true)==1) -- inactive sign until the stock deletion clock
  local dead=assert(S.road_station_retirement().get(s,"rail",platform.id))
  assert(dead.stock_station_id==0 and dead.time_since_load==2 and dead.time_since_unload==4)
end
print("PASS bus, airport and rail in both orders; combined spread, one council station, and facility-by-facility removal")
