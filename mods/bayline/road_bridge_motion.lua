-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- The road bridge branches of OpenTTD 14.1 VehicleEnter_TunnelBridge and
-- IndividualRoadVehicleController, and GetNewVehiclePos. This operates on
-- a validated, already-selected paired span. Geometry/site checks are done by
-- road_bridge.lua; vehicle occupancy, inclination, and clock are external.
local M={WORMHOLE=0xFF}
local dx,dy={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
local floor=math.floor

-- Direction of a straight road vehicle is 2*DiagDirection+1. Once its
-- inward frame reaches 15, PrepareToEnterBridge levels to the deck and the
-- ordinary road-drive table stops updating until the exit.
local tunnel_visibility={[0]=12,8,8,12}
local function axial_frame(dir,x,y)
  local p=(dir%2==0 and x or y)%16
  return (dir==0 or dir==3) and 15-p or p
end
function M.enters(head,direction,x,y)
  local d=head.dir
  if direction~=2*d+1 then return false end
  return axial_frame(d,x,y)==(head.kind=="tunnel" and tunnel_visibility[d] or 15)
end

function M.step(board,head,v)
  local d=head.dir
  if v.state~=M.WORMHOLE or v.direction~=2*d+1 then return end
  local x,y=v.x+dx[v.direction],v.y+dy[v.direction]
  local id=board.tile_at(floor(x/16),floor(y/16))
  if not id then return end
  if id==head.other then
    local exit=board.tile(id)
    if not exit or exit.kind~=head.kind or exit.dir~=(d+2)%4 or exit.other~=head.id then return end
    if head.kind=="tunnel" then
      if exit.tunnel~=head.tunnel then return end
      local f=16-tunnel_visibility[exit.dir]
      if axial_frame(d,x,y)==f then return "exit",x,y,id,f end
      return "span",x,y,id
    end
    if exit.span~=head.span then return end
    return "exit",x,y,id,0
  end
  if not head.plan.middle_by_tile[id] and not (head.kind=="tunnel" and id==head.id) then return end
  return "span",x,y,id
end

return M
