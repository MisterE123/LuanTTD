-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, source pin 14.1: roadveh.h, roadveh_cmd.cpp
-- (RoadFindPathToDest and the tram-specific IndividualRoadVehicleController
-- branches), table/roadveh_movement.h. No live queue or YAPF decisions here.
return function(data,Motion)
  local M={DRIVE_THROUGH_STOP=11, DEPOT_START=6, DEFAULT_START=0,
      SHORT_TURN=16, AFTER_LONG_TURN=21, TURN_AROUND_START=1}
  local floor=math.floor
  local reverse_td={[0]=6,7,14,15}
  local approach_bit={[0]=8,4,2,1}
  local turn_in={[6]=0,[7]=1,[14]=2,[15]=3}
  local function has(mask,bit) return floor(mask/bit)%2==1 end
  local function one(bits) return bits==1 or bits==2 or bits==4 or bits==8 end
  M.reverse_trackdir=reverse_td

  -- Tram drive tables have no lay-by rows. Drive-through stops retain
  -- an in-station state but use the underlying straight road table.
  function M.sample(state,side,frame)
    if state<0 or state>=80 or frame<0 then return end
    if state>=64 then state=floor(state/8)%2*8+state%2 end
    local row=data[state+side*16]
    if not row then return end
    local x,y=row[2*frame+1],row[2*frame+2]
    if not x then return end
    if x>=128 then return "next_tile",x%4 end
    if x>=64 then return "turned",x%4 end
    return "position",x,y
  end

  -- Return a new in-tile frame, a rotation-only tick, or marker/direction.
  -- Like the stock bus controller, incremental heading changes delay the
  -- drive table; changing heading upon explicitly entering a tile does not.
  function M.step(v,side)
    local event,x,y=M.sample(v.state,side,v.frame+1)
    if event~="position" then return event,x end
    x,y=v.x-v.x%16+x,v.y-v.y%16+y
    local d=Motion.sliding_direction(v.direction,x-v.x,y-v.y)
    if d~=v.direction then return "rotate",v.x,v.y,d,v.frame,x,y end
    return "move",x,y,d,v.frame+1
  end
  function M.enter(v,tile_x,tile_y,new_state,side,frame)
    local event,x,y=M.sample(new_state,side,frame)
    if event~="position" then return end
    x,y=tile_x*16+x,tile_y*16+y
    return "enter",x,y,Motion.sliding_direction(v.direction,x-v.x,y-v.y),frame
  end

  -- RoadFindPathToDest's manual reverse-request eligibility after its
  -- no-track check. Approach is the direction of travel, NOT the near side.
  function M.can_reverse_request(bits,approach)
    local first=approach_bit[approach]
    local other=approach_bit[(approach+2)%4]
    return (has(bits,first) and has(bits,other)) or bits==first
  end

  -- On a selected reversing trackdir, choose the tile and first frame of
  -- the stock long/short turn. board.tile(id) returns the same kinds as the
  -- road YAPF board; board.tram_bits(id,include_portal_inside) corresponds
  -- to GetAnyRoadBits(RTT_TRAM), and board.can_build_tram(v,id,needed) is
  -- the query-only DC_NO_WATER build command, never a mutation.
  -- board.has_compatible(v,id) mirrors HasTileAnyRoadType; without callback
  -- use v.compatible roadtype set or the vehicle's single native type.
  -- v.front defaults true; v.previous_tile is the articulated predecessor.
  -- Returns ("long"|"short"|"wait", target, frame, needed).
  function M.start_reverse(board,v,next_id,td)
    local direction=turn_in[td]
    if direction==nil then return end
    local needed=approach_bit[(direction+2)%4]
    local t=next_id~=nil and board.tile(next_id)
    local front=v.front~=false
    local compatible=false
    if front and t and t.kind=="road" and not t.roadworks then
      if board.has_compatible then compatible=board.has_compatible(v,next_id)
      elseif t.tramtype~=nil then
        if v.compatible then compatible=v.compatible[t.tramtype]==true
        else compatible=t.tramtype==(v.tramtype or 1) end
      end
    end
    if (v.previous_tile~=nil and v.previous_tile==next_id) or
       (compatible and has(t.tram_bits or 0,needed)) then
      return "long",next_id,M.DEFAULT_START,needed
    end
    if not front or next_id==nil or not board.can_build_tram or not board.can_build_tram(v,next_id,needed) then
      return "short",v.tile,M.SHORT_TURN,needed
    end
    local current=board.tram_bits(v.tile,false) or 0
    if current==0 or current==needed then return "short",v.tile,M.SHORT_TURN,needed end
    return "wait",nil,nil,needed
  end

  -- The TURNED marker lives *inside* the long turn row. On a non-depot
  -- one-half tile it forces the same reversing row at frame 21 rather than
  -- running routing or restarting the row. Otherwise follow the fresh path
  -- selection (or articulated predecessor) starting at frame 1.
  function M.turned(tile, tram_bits, exit_direction, chosen_td)
    if tile.kind~="depot" and one(tram_bits) then
      return reverse_td[(exit_direction+2)%4],M.AFTER_LONG_TURN
    end
    if chosen_td~=nil then return chosen_td,M.TURN_AROUND_START end
  end
  return M
end
