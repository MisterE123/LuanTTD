-- SPDX-License-Identifier: GPL-2.0-only
-- Adapts OpenTTD 16.0-RC1 src/vehicle.cpp Vehicle::ShowVisualEffect and
-- src/train_cmd.cpp TrainLocoHandler to a 3D chimney and a host-side clock.
-- Model outlet coordinates are in native Luanti entity nodes (x,height,z).
-- Keep them aligned with tools/build_{kirby,chaney_jubilee,ginzu_a4,
-- sh_8p,early_diesel,floss_47,manley_morel,stock_rail_f}_art.py.
local E={}
local function exhaust(diesel,...)
  local p={diesel=diesel,...}
  for i,q in ipairs(p) do p[i]={x=q[1],y=q[2],z=q[3]} end
  return p
end
E.profiles={
  steam=exhaust(false,{0,.730,-.352}),
  jubilee=exhaust(false,{0,.700,-.361}),
  ginzu=exhaust(false,{0,.594,-.355},{0,.594,-.316}),
  sh_8p=exhaust(false,{0,.563,-.380},{0,.563,-.343}),
  manley=exhaust(true,{-.183,.110,.148},{.183,.110,.148}),
  dash=exhaust(true,{-.172,.111,.148},{.172,.111,.148}),
  hendry=exhaust(true,{0,.577,.067},{0,.577,.096}),
  uu37=exhaust(true,{0,.587,.067},{0,.587,.096}),
  floss=exhaust(true,{-.086,.604,-.159},{-.086,.604,.027},{-.086,.604,.164}),
  sh_125=exhaust(true,{-.062,.563,.286},{.062,.563,.261}),
}
function E.work(train,kind,index,tile,portal,under_bridge)
  local p=E.profiles[kind]
  if not p or index~=1 and not ((train.dual_head or train.stock_engine==11) and
      index==#train.consist.parts) then return end
  if not tile or tile.rail_depot_dir~=nil or portal and portal.kind=="tunnel" or under_bridge or
      train.phase~="running" or train.slowing or train.stuck or train.crashed or
      (train.speed or 0)<2 then return end
  -- Steam cadence has thirds of max speed in the source; the 3D renderer
  -- uses a modest, bounded interval for each band. Diesel is the small
  -- smoke profile: nothing once past half speed, with no idle soot.
  local limit=train.max_track_speed or 80
  local ratio=math.min(1,train.speed/math.max(1,limit))
  if p.diesel and ratio>=.5 then return end
  return ratio
end
return E
