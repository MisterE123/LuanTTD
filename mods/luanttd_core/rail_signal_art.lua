-- SignalPositions and DrawSignals slot mapping translated from OpenTTD 14.1
-- src/rail_cmd.cpp (OpenTTD contributors). The geometry and pose adapter
-- are original LuanTTD work. SPDX-License-Identifier: GPL-2.0-only
-- Presentation data only: no signal state, reservations, or authorization.
local M={atlas="bl_rail_signal_atlas.png"}
local left={{8,5},{14,1},{1,14},{9,11},{1,0},{3,10},{11,4},{14,14},
  {11,3},{4,13},{3,4},{11,13}}
local right={{14,1},{12,10},{4,6},{1,14},{10,4},{0,1},{14,14},{5,12},
  {11,13},{4,3},{13,4},{3,11}}
-- Index by *protected* Trackdir, not the facing of its oncoming signal.
-- Slots in the original C++ array are one less than these Lua indexes.
local slot={[0]=9,11,5,7,1,3,[8]=10,[9]=12,[10]=6,[11]=8,[12]=2,[13]=4}
local yaw={[0]=math.pi/2,[1]=0,[8]=-math.pi/2,[9]=math.pi}
function M.anchor(td,right_side)
  local i=slot[td]
  if not i then return end
  local p=(right_side and right or left)[i]
  return p[1],p[2]
end
function M.pose(tile_x,tile_z,surface_y,td,right_side)
  if yaw[td]==nil then return end -- Curved stock sprite anchors need 3D clearance work.
  local u,v=M.anchor(td,right_side)
  -- Stock tile pixels (0..15) start at the lower boundary, not the center.
  -- In LuanTTD its two-node span starts at 2*tile-0.5.
  return {x=2*tile_x-.5+u/8,y=surface_y,z=2*tile_z-.5+v/8},
    {x=0,y=yaw[td],z=0}
end
function M.mesh(variant,green)
  if variant~="light" and variant~="semaphore" then return end
  return "bl_rail_signal_"..variant.."_"..(green and "green" or "red")..".obj"
end
return M
