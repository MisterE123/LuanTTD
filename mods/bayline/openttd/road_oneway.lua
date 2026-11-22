-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors; 14.1 src/road_cmd.cpp CmdBuildRoad,
-- CmdBuildLongRoad, CanConnectToRoad and GetTileTrackStatus_Road;
-- src/road_gui.cpp PlaceRoad. Ordinary company roads and default road type.
return function(Slope,Follow)
  local R={NONE=0,SOUTHBOUND=1,NORTHBOUND=2,BOTH=3,X=0,Y=1}
  local floor=math.floor
  local axis_bits={[0]=10,5}
  local road_bit={[0]=8,4,2,1}
  local function reverse(d) return (d+2)%4 end
  local function has(n,b) return floor(n/b)%2==1 end
  local function count(n)
    local c=0
    while n>0 do c=c+n%2;n=floor(n/2) end
    return c
  end
  local function combine(a,b,op)
    local c=0
    for _,i in ipairs({1,2,4,8}) do if op(has(a,i),has(b,i)) then c=c+i end end
    return c
  end
  local function bor(a,b) return combine(a,b,function(x,y) return x or y end) end
  local function clear(a,b) return combine(a,b,function(x,y) return x and not y end) end
  local function xor(a,b) return combine(a,b,function(x,y) return x~=y end) end
  local function straight(bits) return bits==5 or bits==10 end
  local function integer(value,lo,hi)
    return type(value)=="number" and value>=lo and value<=hi and floor(value)==value
  end

  -- A sign toggle is zero cost. A half-built tile can acquire a sign when
  -- completed; a request on that same half alone is rejected as not straight.
  -- On an empty tile a half edge can be built, but there is no sign to apply.
  -- Quote only: the returned record is an edit, never mutates the input.
  -- An ordinary unowned road uses nil owner; a town road needs a distinct
  -- town owner sentinel, not the same nil used by unowned pavement.
  function R.tile(t,pieces,toggle,opts,id)
    opts=opts or {}
    if not integer(pieces,1,15) or not integer(toggle,0,3) then return nil,"PARAMETERS" end
    if opts.tram then return nil,"UNSUPPORTED_ROADTYPE" end
    if not t or (t.kind~="road" and t.kind~="clear") then return nil,"UNSUPPORTED_TILE" end
    if t.roadworks then return nil,"ROAD_WORKS_IN_PROGRESS" end
    if t.kind=="road" and t.roadtype~=nil and t.roadtype~=0 then return nil,"UNSUPPORTED_ROADTYPE" end
    local existing=t.kind=="road" and (t.road_bits or 0) or 0
    local other=t.kind=="road" and (t.tram_bits or 0) or 0
    local old=existing~=0 and (t.disallowed or 0) or 0
    local owner=t.owner
    local result={kind="road",roadtype=0,road_bits=existing,disallowed=old,owner=owner,cost=0,added=0}
    local function occupied()
      if opts.occupied then return opts.occupied(t,id) end
      return t.occupied
    end
    if existing~=0 then
      local is_straight=straight(bor(existing,pieces))
      if (old~=R.NONE or toggle~=R.NONE) and not is_straight then return nil,"ONEWAY_JUNCTION" end
      if clear(pieces,existing)==0 then
        if toggle==R.NONE then return nil,"ALREADY_BUILT" end
        if owner~=nil and owner~=opts.company then return nil,"OWNED_BY" end
        local new=xor(old,toggle)
        if count(old)<=count(new) and occupied() then return nil,"VEHICLE_IN_THE_WAY" end
        result.disallowed=straight(existing) and new or old
        result.changed=result.disallowed~=old
        return result
      end
    end
    if t.kind=="clear" then
      -- CmdLandscapeClear is called before the foundation check.
      if occupied() then return nil,"VEHICLE_IN_THE_WAY" end
      if opts.clear then
        local price,err=opts.clear(t,id)
        if price==nil then return nil,err end
        result.cost=price
      end
    end
    local terrain=t.slope or 0
    local foundation=false
    if other~=pieces then
      pieces,foundation=Slope.prepare(terrain,pieces,existing,other,opts.build_on_slopes~=false)
      if not pieces then return nil,"WRONG_SLOPE" end
    end
    if t.kind=="road" then
      pieces=clear(pieces,existing)
      if other~=0 and Slope.foundation(terrain,other)~=Slope.foundation(terrain,bor(existing,pieces)) then
        return nil,"WRONG_SLOPE"
      end
      if occupied() then return nil,"VEHICLE_IN_THE_WAY" end
    end
    local bits=bor(existing,pieces)
    result.added=pieces
    result.road_bits=bits
    result.disallowed=straight(bits) and xor(old,toggle) or R.NONE
    if existing==0 then result.owner=opts.company end
    result.foundation=foundation
    result.cost=result.cost+count(pieces)*(opts.piece_cost or 95)+(foundation and (opts.foundation_cost or 250) or 0)
    result.changed=true
    return result
  end

  -- Call after a successful bit removal on an ordinary tile. Stock
  -- always clears the road sign when any of its pavement is removed;
  -- removal of tram rails never touches the road's sign.
  function R.after_remove(disallowed,tram)
    return tram and disallowed or R.NONE
  end

  -- OpenTTD trackdir codes 0,1,8,9. Follow.status queries the same
  -- DRD-to-trackdir multiplier as the routing code, including occupancy-
  -- independent 'no entry' flags. Output is diag direction NE/SE/SW/NW.
  function R.arrow(bits,disallowed)
    if disallowed==R.NONE or not straight(bits) then return nil end
    if disallowed==R.BOTH then return nil,"no-entry" end
    local tile={kind="road",roadtype=0,road_bits=bits,disallowed=disallowed}
    local status=Follow.status(tile,false)
    for d=0,3 do
      if Follow.has_trackdir(status,Follow.direction_trackdir(d)) then return d end
    end
  end

  -- Complete diagonal axes, not arbitrary polyline or Manhattan bends.
  -- board.xy(id) and board.adjacent(id,diag) use stock map axes, plus the
  -- board's compatible continuation predicate (or R.can_connect below).
  -- Requests are enumerated from the original pointer-down tile, not
  -- reordered by the numeric ID. This matters when an obstacle is met.
  function R.drag(board,start,last,axis,opts)
    opts=opts or {}
    if opts.tram then return nil,"UNSUPPORTED_ROADTYPE" end
    if not integer(axis,0,1) or type(start)~="number" or type(last)~="number" then return nil,"PARAMETERS" end
    local sx,sy=board.xy(start)
    local ex,ey=board.xy(last)
    local toggle=opts.toggle==nil and R.NORTHBOUND or opts.toggle -- GUI's One Way button
    if not sx or not sy or not ex or not ey or not integer(toggle,0,3) or
        (axis==R.X and sy~=ey) or (axis==R.Y and sx~=ex) then return nil,"PARAMETERS" end
    local d=2-axis
    local start_half,end_half=not not opts.start_half,not not opts.end_half
    local single=start==last
    if start>last or (single and start_half) then
      d=reverse(d)
      start_half,end_half=not start_half,not end_half
      if toggle==R.SOUTHBOUND or toggle==R.NORTHBOUND then toggle=xor(toggle,R.BOTH) end
    end
    if (toggle==R.SOUTHBOUND or toggle==R.NORTHBOUND) and ((axis==R.Y)==(single and start_half==end_half)) then
      toggle=xor(toggle,R.BOTH)
    end
    local function connects(tile,dir)
      if board.connects then return board.connects(tile,dir) end
      return R.can_connect(board,tile,dir)
    end
    local dirbit,reversebit=road_bit[d],road_bit[reverse(d)]
    local out={axis=axis,direction=d,toggle=toggle,requests={}}
    local distance=math.abs(sx-ex)+math.abs(sy-ey)
    local tile=start
    for _=0,distance do
      if not tile then return nil,"PARAMETERS" end
      local bits=axis_bits[axis]
      if not opts.ai and not single then
        if tile==last and not connects(tile,d) then bits=reversebit
        elseif tile==start and not connects(tile,reverse(d)) then bits=dirbit end
      else
        if tile==last and not end_half then bits=has(bits,reversebit) and reversebit or 0 end
        if tile==start and start_half then bits=has(bits,dirbit) and dirbit or 0 end
      end
      out.requests[#out.requests+1]={tile=tile,bits=bits,toggle=toggle}
      if tile==last then return out end
      tile=board.adjacent(tile,d)
    end
    return nil,"PARAMETERS"
  end

  function R.can_connect(board,tile,d)
    local next=board.adjacent(tile,d)
    local t=next~=nil and board.tile(next)
    if not t or t.roadtype==nil then return false end
    if board.compatible then
      if not board.compatible(t.roadtype,0) then return false end
    elseif t.roadtype~=0 then return false end
    local bits=board.road_bits and board.road_bits(next,t) or t.road_bits or 0
    return has(bits,road_bit[reverse(d)])
  end

  -- Stock GUI skips non-build obstacles at the beginning, then stops
  -- on the first non-ALREADY_BUILT failure after *any* success (including
  -- a free sign toggle). AI fails on the first non-ALREADY_BUILT error and
  -- honors dragged half-tile endpoints, so quote permits atomic execution.
  -- Apply this immutable result once after budget/race checks at the host.
  function R.sweep(drag,quote,ai)
    local out={changes={},cost=0,skipped={},drag=drag,successes=0}
    local last_error="PARAMETERS"
    for _,req in ipairs(drag.requests) do
      local edit,why=quote(req)
      if edit then
        out.cost=out.cost+edit.cost
        out.successes=out.successes+1
        if edit.changed then out.changes[#out.changes+1]=edit end
      else
        last_error=why
        out.skipped[#out.skipped+1]={tile=req.tile,reason=why}
        if why~="ALREADY_BUILT" then
          if ai then return nil,why,req.tile end
          if out.successes>0 then out.stopped_at=req.tile;break end
        end
      end
    end
    if out.successes==0 then return nil,last_error end
    return out
  end

  function R.plan(board,start,last,axis,opts)
    local drag,err=R.drag(board,start,last,axis,opts)
    if not drag then return nil,err end
    opts=opts or {}
    return R.sweep(drag,function(req)
      local edit,why=R.tile(board.tile(req.tile),req.bits,req.toggle,opts,req.tile)
      if edit then edit.tile=req.tile end
      return edit,why
    end,opts.ai)
  end
  return R
end
