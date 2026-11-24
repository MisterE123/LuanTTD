-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, src/road_cmd.cpp _town_road_types and
-- TileLoop_Road's Temperate ground transition. The native host supplies
-- the closest town zone; it must call after a reconstruction attempt
-- that did not start or complete, and after excluding depots.
local R={}
local target={[0]="grass","paved","paved","trees","street_lights"}
local before={[0]="grass","paved","paved","trees","paved"}
function R.visit(current,zone)
  local desired,pre=target[zone],before[zone]
  assert(desired and pre,"Invalid stock HouseZone")
  if current==desired then return current,false end
  if current==pre then return desired,true end
  if current=="barren" then return pre,true end
  return "barren",true
end
return R
