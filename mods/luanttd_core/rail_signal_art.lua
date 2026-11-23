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
local root=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Track=dofile(root.."openttd/rail_track.lua")
local RailPose=dofile(root.."rail_pose.lua")(Track)
local yaw={[0]=math.pi/2,[1]=0,[8]=-math.pi/2,[9]=math.pi}
local mounted={}
function M.anchor(td,right_side)
  local i=slot[td]
  if not i then return end
  local p=(right_side and right or left)[i]
  return p[1],p[2]
end
function M.world_anchor(td,right_side,mask)
  local u,v=M.anchor(td,right_side)
  if u==nil or Track.track(td)<2 then return u,v end
  mask=mask or 2^Track.track(td)
  local key=td..":"..tostring(not not right_side)..":"..mask
  if mounted[key] then return mounted[key][1],mounted[key][2] end
  local route={}
  for track=0,5 do
    if Track.has(mask,track) then
      for i=0,24 do
        local x,z=RailPose.sample(track,i/24)
        route[#route+1]={x=x,z=z}
      end
    end
  end
  local function clear(x,z)
    x,z=x/8-1,z/8-1
    for _,p in ipairs(route) do
      if (x-p.x)^2+(z-p.z)^2<.405^2 then return false end
    end
    return true
  end
  local x,z=u,v
  if not clear(u,v) then
    -- The stock anchor is for a flat sprite. Keep it as close as
    -- possible while moving the native mast off the swept 3D body.
    local best
    for i=1,14 do for j=1,14 do
      local d=(i-u)^2+(j-v)^2
      if (not best or d<best) and clear(i,j) then x,z,best=i,j,d end
    end end
    if not best then return end
  end
  mounted[key]={x,z}
  return x,z
end
function M.pose(tile_x,tile_z,surface_y,td,right_side,mask)
  local u,v=M.world_anchor(td,right_side,mask)
  if u==nil then return end
  -- Stock tile pixels (0..15) start at the lower boundary.
  return {x=2*tile_x-.5+u/8,y=surface_y,z=2*tile_z-.5+v/8},
    {x=0,y=yaw[td] or (3-Track.heading(td))*math.pi/4,z=0}
end
function M.mesh(variant,green)
  if variant~="light" and variant~="semaphore" then return end
  return "bl_rail_signal_"..variant.."_"..(green and "green" or "red")..".obj"
end
return M
