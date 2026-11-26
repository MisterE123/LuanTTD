-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. 16.0-RC1: src/road_cmd.cpp CheckAllowRemoveRoad,
-- src/town_cmd.cpp CheckforTownRating, ChangeTownRating and
-- UpdateTownRating; source constants in src/town_type.h.
local R={initial=500}
local required={[0]=16,64,112,-1000}
function R.road_removal_minimum(tolerance) return required[tolerance] end
-- TownAuthorityWindow::GetRatingString, strict OpenTTD boundaries.
function R.rating_name(rating)
  if rating>800 then return "Outstanding" end
  if rating>600 then return "Excellent" end
  if rating>400 then return "Very good" end
  if rating>200 then return "Good" end
  if rating>0 then return "Mediocre" end
  if rating>-200 then return "Poor" end
  if rating>-400 then return "Very poor" end
  return "Appalling"
end
-- town_cmd.cpp CheckIfAuthorityAllowsNewStation. Unlike road removal
-- there is one hardcoded threshold for every non-permissive council.
function R.allow_new_station(rating,distance,limit,tolerance,no_test)
  return tolerance==3 or no_test or distance==nil or distance>=limit or rating>-200
end
local bits={1,2,4,8} -- NW, SW, SE, NE in native board order
local reverse={4,8,1,2}
local function has(mask,b) return math.floor(mask/b)%2==1 end
local function lower(rating,by,limit)
  return rating>limit and math.max(rating-by,limit) or rating
end
-- Tree clearing penalizes the company once per tile, not per stem.
-- Tree purchase/removal price is a separate per-stem amount.
-- 16.0-RC1 CheckforTownRating(TunnelBridgeRemove), and the
-- post-clear rating change from DoClearBridge / DoClearTunnel.
function R.span_removal(rating,tolerance,magic)
  local needed=({[0]=144,208,400,-1000})[tolerance]
  if not magic and rating<assert(needed) then return nil,"TOWN_REFUSES" end
  return magic and rating or lower(rating,250,0)
end

function R.clear_trees(rating)
  return lower(rating,35,-1000)
end
-- Only the valid company / town-owner branch. The owning command
-- resolves the town and source flags; no map or persistent rating is
-- modified while evaluating a quote.
function R.check(rating,tolerance,extra_dynamite,present,remove,neighbors)
  local minimum=required[tolerance]
  if not minimum then return nil,"INVALID_TOLERANCE" end
  if rating<minimum then return nil,"TOWN_REFUSES" end
  local n,intersects=0,false
  for i,b in ipairs(bits) do
    if has(present,b) and has(neighbors[i] or 0,reverse[i]) then
      n=n+1
      if has(remove,b) then intersects=true end
    end
  end
  if n>1 and intersects then
    if not extra_dynamite then return nil,"TOWN_REFUSES" end
    return lower(rating,50,-100)
  end
  return lower(rating,18,-100)
end

-- (ForAllStationsNearTown): query square first, then exact squared
-- radius using a station's sign coordinate (not a catchment rectangle).
function R.in_radius(town,station,limit)
  local x,z=station.x-town.x,station.z-town.z
  local search=math.floor(limit/2)
  return math.abs(x)<=search and math.abs(z)<=search and x*x+z*z<=limit
end
local function sat(n,lo,hi) return math.min(hi,math.max(lo,n)) end
-- The order of station deltas matters when the int16 intermediate
-- saturates. Do not clamp the final rating after each facility.
function R.month(rating,stations)
  if rating<200 then rating=math.min(200,rating+5) end
  for _,station in ipairs(stations) do
    if (station.time_since_load or 255)<=20 or (station.time_since_unload or 255)<=20 then
      rating=math.min(32767,rating+12)
    else
      rating=math.max(-32768,rating-15)
    end
  end
  return sat(rating,-1000,1000)
end
return R
