-- SPDX-License-Identifier: GPL-2.0-only
local Join=dofile("mods/luanttd_core/openttd/station_join_command.lua")
local function id(x,y) if x>=0 and y>=0 and x<128 and y<128 then return x+128*y end end
local area={tile=id(43,52),w=4,h=3}
local bus={id=1,owner=0,tile=id(43,47),town=0,spread={tile=id(43,47),w=1,h=1}}
local third={id=3,owner=2,spread={tile=id(46,55),w=1,h=1}}
local four={id=4,owner=0,spread={tile=id(43,51),w=1,h=1}}
local five={id=5,owner=0,spread={tile=id(47,52),w=1,h=1},airport=true}
local retired={id=8,owner=0}
local rows={[1]=bus,[3]=third,[4]=four,[5]=five,[8]=retired}
local map={[bus.tile]=bus,[third.spread.tile]=third}
local board={
  id=id,xy=function(t) return t%128,math.floor(t/128) end,
  station=function(n) return rows[n] end, station_at=function(t) return map[t] end,
  matches=function() return true end,
}
local function quote(p,expected,reason)
  p.spread=p.spread or 12
  local actual,why=Join.airport_target(board,area,0,p)
  assert(actual==expected and why==reason,(why or "no error").." != "..(reason or "no error"))
end
-- Native 16.0-RC1 airport-road trace: retain the original sign at
-- TileIndex 6059 and town, adding Airport facility to Bus station ID 1.
quote({join_id=1,distant=true},bus)
assert(bus.tile==6059 and bus.town==0)
-- The native joined snapshot records facility mask 12, same sign, and
-- retains the existing goods/counters. Adding an airport doesn't redraw.
local station={tile=bus.tile,town=bus.town,facilities=Join.BUS,random_bits=4132,
  rating_phase=37,time_since_load=3,time_since_unload=3,waiting_passengers=2}
local draws=0
local function rng() draws=draws+1;return 65537 end
Join.add_facility(station,Join.AIRPORT,area.tile,0,12602,rng)
assert(draws==0 and station.facilities==12 and station.tile==6059 and station.random_bits==4132)
assert(station.rating_phase==37 and station.waiting_passengers==2 and station.build_date==12602)
local new=Join.add_facility({},Join.AIRPORT,area.tile,0,12602,rng)
assert(draws==1 and new.tile==area.tile and new.facilities==8 and new.random_bits==1)
Join.add_facility(new,Join.AIRPORT,area.tile,0,12603,rng)
assert(draws==1 and new.facilities==8 and new.build_date==12603)
quote({join_id=1,distant=false},nil,"INVALID_STATION")
quote({join_id=99,distant=true},nil,"INVALID_STATION")
quote({join_id=1,distant=true,spread=7},nil,"STATION_TOO_SPREAD_OUT")
quote({join_id=3,distant=true},nil,"NOT_STATION_OWNER")
quote({new_station=true,allow_adjacent=true},false)
map[four.spread.tile]=four
-- A single owned adjacency overrides explicit distant target when
-- joining neighbours; competitor ownership is not counted by this scan.
quote({join_id=1,distant=true},four)
quote({join_id=1,distant=true,allow_adjacent=true},bus)
quote({new_station=true},four)
map[five.spread.tile]=five
quote({join_id=1,distant=true},nil,"ADJOINS_MORE_THAN_ONE_EXISTING")
quote({join_id=5,distant=true,allow_adjacent=true},nil,"TOO_CLOSE_TO_ANOTHER_AIRPORT")
board.closest_deleted=function(t,owner) assert(t==area.tile and owner==0);return retired end
quote({allow_adjacent=true},retired)
quote({new_station=true,allow_adjacent=true},false)
print("PASS mixed RC1 airport command selection: physical join, spread, ancestry and distinct construction flags")
