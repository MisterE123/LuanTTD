-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 waypoint_cmd.cpp GetAxisForNewWaypoint, IsValidTileForWaypoint
-- and CmdBuildRailWaypoint; station_cmd.cpp RemoveFromRailBaseStation;
-- table/pricebase.h. Original 1x1 rail waypoints, no adjacent joining/NewGRF.
local W={BUILD=600,REMOVE=80,CLEAR_RAIL=-70}
function W.axis(t)
  if not t then return end
  if t.kind=="waypoint" then return t.axis end
  if t.kind~="rail" then return end
  if t.trackbits==1 then return 0 end
  if t.trackbits==2 then return 1 end
end
local function bands(shape,axis)
  local part=math.floor(shape/2^axis)%4*2^axis
  return part>0 and part~=shape
end
function W.build(t,axis,o)
  o=o or {}
  if (axis~=0 and axis~=1) or W.axis(t)~=axis then return nil,"NO_SUITABLE_RAILROAD_TRACK" end
  if t.owner~=o.owner then return nil,"OWNED_BY_ANOTHER" end
  if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
  local slope=t.slope or 0
  if slope~=0 and (not o.build_on_slopes or slope>=16 or not bands(slope,axis)) then
    return nil,"FLAT_LAND_REQUIRED"
  end
  if t.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
  return {axis=axis,railtype=t.railtype or 0,reserved=t.reserved==true,
    price=t.kind=="waypoint" and 0 or (o.build or W.BUILD)}
end
function W.remove(t,o)
  o=o or {}
  if not t or t.kind~="waypoint" then return nil,"NO_WAYPOINT" end
  if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
  if t.owner~=o.owner then return nil,"OWNED_BY_ANOTHER" end
  return {axis=t.axis,railtype=t.railtype or 0,reserved=t.reserved==true,
    price=(o.remove or W.REMOVE)-(o.clear_rail or W.CLEAR_RAIL)}
end
return W
