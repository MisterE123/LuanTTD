-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 src/rail_cmd.cpp VehicleEnterTile_Rail,
-- TicksToLeaveDepot, _fractcoords_behind, _fractcoords_enter and
-- _deltacoord_leaveoffset. The caller journals the returning tile
-- latch separately from the final, whole-train VehicleEnterDepot.
local D={}
local behind_x,behind_y={[0]=15,8,0,8},{[0]=8,0,8,15}
local enter_x,enter_y={[0]=10,8,4,8},{[0]=8,4,8,10}
local descend_x,descend_y={[0]=-1,0,1,0},{[0]=0,1,0,-1}

function D.coordinates(dir)
  return enter_x[dir],enter_y[dir]
end

function D.tile_event(dir,heading,x,y,next_offset,has_next)
  x,y=x%16,y%16
  if x==behind_x[dir] and y==behind_y[dir] then return "blocked" end
  local frontier,transverse=enter_x[dir],enter_y[dir]
  if heading==dir*2+1 then
    local n=next_offset+1
    if has_next and x==(frontier+n*descend_x[dir])%256 and y==(transverse+n*descend_y[dir])%256 then
      return "reveal"
    end
  elseif x==frontier and y==transverse then
    assert(heading==((dir+2)%4)*2+1,"A depot is entered on its owned track axis")
    return "hide"
  end
end

function D.ticks_to_leave(dir,x,y,next_offset)
  local n=next_offset+1
  return (enter_x[dir]+n*descend_x[dir]-x%16)*descend_x[dir]+
    (enter_y[dir]+n*descend_y[dir]-y%16)*descend_y[dir]
end

return D
