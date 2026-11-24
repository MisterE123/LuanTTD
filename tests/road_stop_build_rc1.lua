local R=dofile("mods/luanttd_core/openttd/road_stop_build.lua")
local opts={company="Me",piece_price=function(t)return t==0 and 95 or 190 end,clear=function(t)return t.clear or 0 end,
  requested_type={kind="road",roadtype=0}}
local through={dir=0,through=true,stop_type="bus"}
local bay={dir=2,through=false,stop_type="truck"}
local r={kind="road",base=2,slope=0,road={roadtype=0,bits=10,owner="Me"}}
assert(R.tile(r,through,opts).cost==200)
r.road.bits=2
assert(R.tile(r,through,opts).cost==295)
r.slope=2 -- only the SW edge rises; through platform needs both exits
assert(select(2,R.tile(r,through,opts))=="FLAT_LAND_REQUIRED")
assert(R.tile(r,bay,opts).cost==640)
r.slope=10 -- opposite elevated corners, both entrance edges overlap
assert(R.tile(r,through,opts).cost==545)
assert(select(2,R.tile(r,through,opts,2))=="FLAT_LAND_REQUIRED")
assert(R.tile(r,through,opts,3).cost==545)
r.slope=0
r.road.bits=4
assert(select(2,R.tile(r,through,opts))=="DRIVE_THROUGH_DIRECTION")
r.road.bits=3
assert(select(2,R.tile(r,through,opts))=="DRIVE_THROUGH_CORNER")
r.road.bits=11
assert(select(2,R.tile(r,through,opts))=="DRIVE_THROUGH_JUNCTION")
r.road.bits,r.road.owner=10,"Other"
assert(R.tile(r,through,opts).cost==200)
r.road.disallowed=1
assert(select(2,R.tile(r,through,opts))=="OWNED_BY")
r.road.owner,r.road.disallowed="town",0
opts.on_town_road=false
assert(select(2,R.tile(r,through,opts))=="DRIVE_THROUGH_ON_TOWN_ROAD")
opts.on_town_road=true
r.tram={roadtype=1,bits=8,owner="Other"}
assert(select(2,R.tile(r,through,opts))=="OWNED_BY")
r.tram.bits=10
assert(R.tile(r,through,opts).cost==200)
r.occupied=true
assert(select(2,R.tile(r,through,opts))=="VEHICLE_IN_THE_WAY")
r.occupied=nil
r.bridge_forbidden=true
assert(select(2,R.tile(r,through,opts))=="MUST_DEMOLISH_BRIDGE_FIRST")
local old={kind="station",base=2,slope=0,station=13,through=true,stop_type="bus",axis=0}
assert(R.tile(old,through,opts).station==13 and R.tile(old,through,opts).cost==0)
assert(select(2,R.tile(old,bay,opts))=="INCOMPATIBLE_STATION_TILE")
opts.requested_type=nil
assert(select(2,R.tile({kind="clear",base=5,slope=0},through,opts))=="NO_ROAD")
local d={kind="clear",base=1,slope=0}
local depot={dir=2,roadtype=0}
assert(R.depot(d,depot,opts).cost==500)
d.slope=2
assert(R.depot(d,depot,opts).z==2 and R.depot(d,depot,opts).cost==750)
d.bridge_deck=4
assert(select(2,R.depot(d,depot,opts))=="BRIDGE_TOO_LOW_FOR_ROADVEH_DEPOT")
d.bridge_deck=5
assert(R.depot(d,depot,opts).cost==750)
d.kind,d.roadtype,d.dir,d.owner="depot",0,0,"Me"
d.bridge_deck=nil
assert(R.depot(d,depot,opts).rotate)
d.occupied=true
assert(select(2,R.depot(d,depot,opts))=="VEHICLE_IN_THE_WAY")
d.dir=2
assert(R.depot(d,depot,opts).unchanged and R.depot(d,depot,opts).cost==0)
d.owner="Other"
assert(select(2,R.depot(d,depot,opts))=="OWNED_BY")
print("PASS RC1 road stop tile foundation, axis/orientation, ownership, price, road/tram and reuse")
