-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 16.0-RC1 src/town_cmd.cpp:
-- TownActionRoadRebuild, GetTownActionCost; src/road_cmd.cpp TileLoop_Road;
-- road_map.h StartRoadWorks / IncreaseRoadWorksCounter / TerminateRoadWorks;
-- core/random_func.hpp Chance16I.
local R={}
local floor=math.floor

R.months=6
R.cost=floor(1000000*35/256)

function R.fund(town)
  town.road_build_months=R.months
end

function R.chance(roll)
  return floor(((roll%65536)*40+20)/65536)<1
end

local function has_multiple_bits(road,tram)
  local count=0
  for p=0,3 do
    local flag=2^p
    if floor(road/flag)%2==1 or floor(tram/flag)%2==1 then
      count=count+1
      if count>1 then return true end
    end
  end
  return false
end

-- The game owner supplies the original foundation slope and ground
-- occupancy, and visits tiles in the stock landscape tile-loop order.
-- If neither launch nor progress applies, consume no random number.
function R.visit(tile,town,distance,zone,is_clear,random)
  if not tile or tile.kind~="road" then return end
  if tile.works then
    local next_step=((tile.counter or 0)+1)%16
    if next_step==15 then
      return {effect="complete",roadside=tile.works=="grass" and "grass" or "paved",counter=0}
    end
    return {effect="progress",works=tile.works,roadside=tile.roadside,counter=next_step}
  end
  if not town or town.road_build_months==0 or town.road_build_months==nil or
      distance>=8 and zone==0 or tile.grade~=0 or
      not has_multiple_bits(tile.road_bits or 0,tile.tram_bits or 0) or not is_clear() or not R.chance(random()) then
    return
  end
  local rs=tile.roadside
  return {effect="start",works=(rs=="barren" or rs=="grass") and "grass" or "paved",
    roadside=rs,counter=0}
end

-- src/road.cpp CleanUpRoadBits / IsPossibleCrossing. These are logical
-- future connectors; ordinary road and clear land need not already offer
-- the reciprocal bit. A structure or station must physically offer it.
function R.cleanup(bits,neighbor)
  local result=bits
  for d=1,4 do
    local flag=2^(d-1)
    if floor(bits/flag)%2==1 then
      local t=neighbor(d)
      local allowed=false
      if t then
        if t.kind=="clear" or t.kind=="trees" or t.kind=="road" then allowed=true
        elseif t.kind=="structure" or t.kind=="station" or t.kind=="road_facility" then
          local mirrored=2^((d+1)%4)
          allowed=floor((t.road_bits or 0)/mirrored)%2==1 or floor((t.tram_bits or 0)/mirrored)%2==1
        elseif t.kind=="rail" then
          local rail_axis=1-d%2 -- perpendicular to this native road edge
          allowed=t.normal and t.track_bits==2^rail_axis and t.grade==0
        elseif t.kind=="water" then allowed=not t.real_water end
      end
      if not allowed then result=result-flag end
    end
  end
  return result
end
return R
