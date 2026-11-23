-- OpenTTD 14.1, roadveh.h and roadveh_cmd.cpp (OpenTTD contributors).
-- SPDX-License-Identifier: GPL-2.0-only
-- Read-only kinematics, in native 16-unit tile coordinates. The controller
-- integration owns path selection, entry permissions, loading and speed.
return function(data)
local M={TILE=16, DEFAULT_START=0, TURN_AROUND_START=1, DEPOT_START=6, DEPOT_STOP=11,
  DRIVE_THROUGH_STOP=11, DEPOT_STOP=11}

-- OpenTTD 16.0-RC1 roadveh_cmd.cpp _road_reverse_table, in diagonal
-- direction order. These are movement rows, not YAPF track directions.
local reverse_rows={[0]=6,7,14,15}
function M.reversing_state(diag) return reverse_rows[diag] end
local function bit(value,place) return math.floor(value/place)%2 end
local directions={[0]=0,7,6,255,1,0,5,255,2,3,4}

function M.sliding_direction(direction,dx,dy)
  if dx < -1 or dx > 1 or dy < -1 or dy > 1 then return direction end
  local target=directions[(dy+1)*4+dx+1]
  -- DIR_N at zero displacement is how the source table is defined.
  if target==direction then return direction end
  local delta=(target-direction)%8
  return (direction+(delta>4 and -1 or 1))%8
end

function M.sample(state,side,frame,overtaking)
  if state<0 or (state>=48 and state<64) or state>=80 then return end
  -- Drive-through stops use the ordinary straight entry selected by mask 0x09.
  if state>=64 and state<80 then state=bit(state,8)*8+bit(state,1) end
  local index=state+side*16
  if overtaking then index=index+(bit(index,16)==0 and 16 or -16) end
  local row=data.road[index]
  if not row or frame<0 or frame*2+2>#row then return end
  local x,y=row[frame*2+1],row[frame*2+2]
  if x>=128 then return "next_tile",x%4 end
  if x>=64 then return "turned",x%4 end
  return "position",x,y
end

function M.bay_stop_frame(state,side)
  if state>=32 and state<48 then return data.bay_stop_frame[state-32+side*16] end
end

-- Propose the ordinary within-tile step only. A changed direction consumes
-- this step, but not the table frame; occupancy must be checked by the caller.
function M.step(v,side,overtaking)
  local kind,x,y=M.sample(v.state,side,v.frame+1,overtaking)
  if kind~="position" then return kind,x end
  x=v.x-v.x%16+x
  y=v.y-v.y%16+y
  local direction=M.sliding_direction(v.direction,x-v.x,y-v.y)
  if direction~=v.direction then return "rotate",v.x,v.y,direction,v.frame end
  return "move",x,y,direction,v.frame+1
end

-- Propose a first sample after stock tile-entry/turnaround path selection.
-- Unlike step(), this source branch updates position and direction together.
function M.enter(v,tile_x,tile_y,state,side,frame,overtaking)
  local kind,x,y=M.sample(state,side,frame,overtaking)
  if kind~="position" then return end
  x=tile_x*16+x
  y=tile_y*16+y
  return "enter",x,y,M.sliding_direction(v.direction,x-v.x,y-v.y),frame
end

return M
end
