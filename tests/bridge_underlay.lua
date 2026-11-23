-- SPDX-License-Identifier: GPL-2.0-only
local U=dofile("mods/luanttd_core/openttd/bridge_underlay.lua")
local function height(t,required,tag)
  t.max_z=4
  assert(U.quote(t,0,4+required)==0)
  local cost,why,diff=U.quote(t,1,4+required-1)
  assert(cost==nil and why=="BRIDGE_TOO_LOW_FOR_"..tag and diff==8,why)
  cost,why,diff=U.quote(t,1,4+required-3)
  assert(cost==nil and why=="BRIDGE_TOO_LOW_FOR_"..tag and diff==24,why)
end
for _,mode in ipairs({"road","rail","ship"}) do
  height({kind=mode.."_depot"},3,({road="ROADVEH_DEPOT",rail="TRAIN_DEPOT",ship="SHIP_DEPOT"})[mode])
end
for p,h in pairs({middle=2,lower=3,upper=2}) do height({kind="lock",part=p},h,"LOCK") end
for _,ground in ipairs({"road","rail","crossing","signals","water","coast","river","tunnel"}) do
  assert(U.quote({kind=ground,max_z=3},0,4)==0)
end
height({kind="object",allow_under_bridge=true,object_height=4},4,"OBJECT")
for i=0,7 do height({kind="station",station_type="rail",layout=i},i>=4 and 5 or 2,"STATION") end
for i=0,5 do
  height({kind="station",station_type="bus",layout=i},2,"ROADSTOP")
  height({kind="station",station_type="truck",layout=i},2,"ROADSTOP")
  height({kind="station",station_type="dock",layout=i},i>=4 and 3 or 2,"DOCK")
end
height({kind="station",station_type="buoy",layout=0},1,"BUOY")
height({kind="station",station_type="rail_waypoint",layout=0},2,"RAIL_WAYPOINT")
height({kind="station",station_type="road_waypoint",layout=5},2,"ROAD_WAYPOINT")
local clear={clear=function(t,auto)
  assert(auto==(t.kind=="station"))
  if auto then return nil,"REMOVE_FACILITY_FIRST" end
  return 20,nil,true
end}
local c,e,g=U.quote({kind="station",station_type="airport",layout=0},0,7,clear)
assert(not c and e=="REMOVE_FACILITY_FIRST" and not g)
c,e,g=U.quote({kind="clear"},0,7,clear)
assert(c==20 and not e and g)
local under={kind="bridge",axis=1,deck=3}
assert(U.quote(under,0,4)==0)
c,e,g=U.quote(under,0,3,clear)
assert(c==20 and not e and g)
c,e,g=U.quote(under,1,9,clear)
assert(c==20 and not e and g)
local offsets={80,160,80,160,118,227,217,188}
for layout=0,7 do
  local _,mask=U.station_info("rail",layout)
  assert(mask==offsets[layout+1],layout..": "..mask)
end
print("PASS RC1 under-bridge tile handlers, stock level thresholds, obstruction pixels, clearance costs and station pillar exclusions")
