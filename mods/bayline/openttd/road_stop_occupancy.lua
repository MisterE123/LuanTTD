-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, pinned 14.1 roadstop.cpp, roadstop_base.h,
-- station_cmd.cpp VehicleEnter_Station and roadveh_cmd.cpp
-- IndividualRoadVehicleController. C++ Entry pointers are represented
-- by shared integer line keys so a plain save/reload preserves identity.
return function(Motion)
  local O={TILE=16,BAY=32,DRIVE=64,BAY_END=48,DRIVE_END=80,
    BASE_ENTRY=6,ENTRY_BUSY=7,USING_SECOND_BAY=1,ENTERED_STOP=2,DRIVE_STOP_FRAME=11}
  local floor=math.floor
  local function bit(n,i) return floor(n/2^i)%2~=0 end
  local function sb(n,i,one) return n+(one and 1 or 0)*2^i-(bit(n,i) and 2^i or 0) end
  local function inside(n,a,b) return n>=a and n<b end
  local function reverse(d) return (d+2)%4 end
  local function diag(d) return floor(d/2) end
  local function reversing(td) return td%8>=6 end
  local function vlength(v) return assert(v.total_length,"Stock cached_total_length required") end
  local function is_front(v)
    if v.front~=nil then return v.front end
    return v.first==nil or v.id==v.first
  end
  local function is_primary(v)
    if v.primary~=nil then return v.primary end
    return is_front(v)
  end
  local function side_of(d) return d>=2 and "west" or "east" end
  local function entry() return {length=0,occupied=0} end
  local function line() return {east=entry(),west=entry()} end
  local function bay_state(n) return inside(n,O.BAY,O.BAY_END) end
  local function through_state(n) return inside(n,O.DRIVE,O.DRIVE_END) end

  function O.new() return {stops={},lines={}} end
  function O.has_free(rs) return rs.status%4~=0 end
  function O.bay_free(rs,n) assert(n==0 or n==1);return bit(rs.status,n) end
  function O.entrance_busy(rs) return bit(rs.status,O.ENTRY_BUSY) end
  function O.set_busy(rs,on) rs.status=sb(rs.status,O.ENTRY_BUSY,on) end
  function O.get_entry(s,id,d)
    local rs=s.stops[id]
    local root=rs and rs.base and s.lines[rs.base]
    return root and root[side_of(d)]
  end
  function O.entry(s,id,d)
    local e=O.get_entry(s,id,d)
    if e then return e.occupied,e.length end
  end

  -- Stock uses exact RoadStopDir, not just axis parity. Ordinary
  -- drive-through GFX is constructed with dir=AXIS_X (0) or AXIS_Y (1).
  function O.continues(board,base,n)
    if n==nil then return false end
    local a,b=board.tile(base),board.tile(n)
    return a and b and (a.kind=="drive_stop" or a.kind=="bay_stop") and b.kind=="drive_stop" and
      a.station==b.station and a.stop_type==b.stop_type and a.dir==b.dir or false
  end
  local function south_dir(t)
    assert(t.dir==0 or t.dir==1,"Ordinary drive-through GFX must carry the canonical stock axis")
    return 2-t.dir -- positive TileIndexDiff: SW on X and SE on Y
  end
  local function walk(board,id,d,excluded,func)
    for _=1,board.limit or 4096 do
      if id==nil or id==excluded or func(id)==false then return end
      id=board.adjacent(id,d)
    end
    assert(id==nil or id==excluded,"Road-stop board adjacency exceeded its bound")
  end
  local function set_base(rs,id,base)
    rs.base=base
    rs.status=sb(rs.status,O.BASE_ENTRY,id==base)
  end
  local function adjust(g,delta)
    g.east.length=g.east.length+delta
    g.west.length=g.west.length+delta
  end

  function O.register(s,board,id)
    assert(not s.stops[id],"Road stop already registered")
    local t=assert(board.tile(id),"Missing road stop tile")
    assert(t.kind=="bay_stop" or t.kind=="drive_stop","Tile not a road stop")
    local rs={tile=id,status=3}
    s.stops[id]=rs
    if t.kind=="bay_stop" then return rs end
    local d=south_dir(t)
    local north,south=board.adjacent(id,reverse(d)),board.adjacent(id,d)
    local n=O.continues(board,id,north) and s.stops[north]
    local p=O.continues(board,id,south) and s.stops[south]
    local a,b=n and n.base,p and p.base
    if a then
      local g=assert(s.lines[a])
      set_base(rs,id,a)
      local added=1
      if b then
        assert(a~=b,"Invalid cyclic drive-through stop board")
        local lower=assert(s.lines[b])
        for _,side in ipairs{"east","west"} do g[side].occupied=g[side].occupied+lower[side].occupied end
        walk(board,south,d,nil,function(j)
          local q=s.stops[j]
          if not O.continues(board,id,j) or not q or not q.base then return false end
          set_base(q,j,a)
          added=added+1
        end)
        s.lines[b]=nil
      end
      adjust(g,added*O.TILE)
    elseif b then
      local g=assert(s.lines[b])
      s.lines[id],s.lines[b]=g,nil
      set_base(rs,id,id)
      walk(board,south,d,nil,function(j)
        local q=s.stops[j]
        if not O.continues(board,id,j) or not q or q.base~=b then return false end
        set_base(q,j,id)
      end)
      adjust(g,O.TILE)
    else
      s.lines[id]=line()
      set_base(rs,id,id)
      adjust(s.lines[id],O.TILE)
    end
    return rs
  end

  -- Source rebuild counts *primary fronts*, same direction, any
  -- road-stop state >=32, not crashed, de-duplicated. It counts the
  -- full chain length even with a tail still on adjoining road. The
  -- board should supply the authoritative stock tile hash, not a
  -- sprite or a physical-tail list. Never cap occupancy by length.
  function O.rebuilt_entry(board,base,side,actors_at,excluded)
    local t=assert(board.tile(base))
    local d=south_dir(t)
    local direction=side=="east" and t.dir or reverse(t.dir)
    local e,seen=entry(),{}
    walk(board,base,d,excluded,function(id)
      if not O.continues(board,base,id) then return false end
      e.length=e.length+O.TILE
      for _,v in ipairs(assert(actors_at(id),"Missing road-stop tile occupancy")) do
        local key=v.id or v
        if v.type=="road" and diag(v.direction)==direction and is_primary(v) and not v.crashed
            and v.state>=O.BAY and not seen[key] then
          seen[key]=true;e.occupied=e.occupied+vlength(v)
        end
      end
    end)
    return e
  end
  function O.rebuild(s,board,base,actors_at,side)
    local r=assert(s.stops[base])
    assert(bit(r.status,O.BASE_ENTRY),"Rebuild must use the northern base")
    local g=assert(s.lines[base])
    if side then
      assert(side=="east" or side=="west")
      g[side]=O.rebuilt_entry(board,base,side,actors_at)
    else
      g.east=O.rebuilt_entry(board,base,"east",actors_at)
      g.west=O.rebuilt_entry(board,base,"west",actors_at)
    end
    return g
  end

  -- The host authorizes ordinary empty-ground demolition beforehand.
  -- It can still pass the old board here: exclude the removed tile while
  -- rebuilding the two halves, as DoClearSquare does in stock. No
  -- bankruptcy/flood semantics, later station-order rebuild here.
  function O.clear(s,board,id,actors_at)
    local rs=assert(s.stops[id])
    if not rs.base then s.stops[id]=nil;return true end
    local old=assert(s.lines[rs.base])
    local root=rs.base
    local t=assert(board.tile(id))
    local d=south_dir(t)
    local north,south=board.adjacent(id,reverse(d)),board.adjacent(id,d)
    local n=O.continues(board,id,north) and s.stops[north]
    local p=O.continues(board,id,south) and s.stops[south]
    if n then
      if p then
        -- Compute before changing group membership: failed/unknown
        -- hash data cannot half-split an otherwise valid saved line.
        local upper={east=O.rebuilt_entry(board,root,"east",actors_at,id),
          west=O.rebuilt_entry(board,root,"west",actors_at,id)}
        local lower={east=O.rebuilt_entry(board,south,"east",actors_at,id),
          west=O.rebuilt_entry(board,south,"west",actors_at,id)}
        s.lines[root],s.lines[south]=upper,lower
        walk(board,south,d,id,function(j)
          local q=s.stops[j]
          if not O.continues(board,south,j) or not q or q.base~=root then return false end
          set_base(q,j,south)
        end)
      else
        adjust(old,-O.TILE)
      end
    elseif p then
      s.lines[south],s.lines[root]=old,nil
      walk(board,south,d,id,function(j)
        local q=s.stops[j]
        if not O.continues(board,south,j) or not q or q.base~=root then return false end
        set_base(q,j,south)
      end)
      adjust(old,-O.TILE)
    else
      s.lines[root]=nil
    end
    s.stops[id]=nil
    return true
  end

  function O.enter(s,board,id,v)
    local rs=assert(s.stops[id])
    local t=assert(board.tile(id))
    if t.kind=="bay_stop" then
      if O.entrance_busy(rs) then return false,"entrance" end
      if not O.has_free(rs) then return false,"full" end
      if v.articulated then return false,"articulated" end
      local bay=O.bay_free(rs,0) and 0 or 1
      v.state=sb(sb(v.state,5,true),O.USING_SECOND_BAY,bay==1)
      rs.status=sb(rs.status,bay,false)
      O.set_busy(rs,true)
      return true,bay
    end
    local e=assert(O.get_entry(s,id,diag(v.direction)))
    e.occupied=e.occupied+vlength(v)
    v.state=sb(v.state,6,true)
    return true
  end
  function O.leave(s,board,id,v)
    local t=assert(board.tile(id))
    if t.kind=="bay_stop" then
      local rs=assert(s.stops[id])
      rs.status=sb(rs.status,bit(v.state,O.USING_SECOND_BAY) and 1 or 0,true)
      O.set_busy(rs,false)
    else
      local e=assert(O.get_entry(s,id,diag(v.direction)))
      local remaining=e.occupied-vlength(v)
      assert(remaining>=0,"Road-stop occupancy underflow: check front departure")
      e.occupied=remaining
    end
  end

  -- VehicleEnter_Station's frame-0 callback. The actor may still hold
  -- its *previous* tile and frame during initial path transition. The
  -- host must not conflate entering the tile with entering the bay.
  function O.station_callback(s,board,id,v)
    local t=id~=nil and board.tile(id)
    if t and (t.kind=="bay_stop" or t.kind=="drive_stop") and v.state<O.BAY and
        not reversing(v.state) and v.frame==0 and is_front(v) then
      return O.enter(s,board,id,v)
    end
    return true
  end

  -- Call only after the target pose passes trajectory, proximity and
  -- road-rail safety checks. Writer applies returned state to the new
  -- tile. Same-line continuation preserves arrival bit and occupancy.
  function O.transition(s,board,v,next_tile,td)
    local t=board.tile(v.tile)
    if t and (t.kind=="bay_stop" or t.kind=="drive_stop") and inside(v.state,O.BAY,O.DRIVE_END) then
      if reversing(td) and bay_state(v.state) then v.speed=0;return false,"bay_reverse" end
      if t.kind=="drive_stop" and next_tile~=v.tile and O.continues(board,v.tile,next_tile) then
        return true,v.state,"same_entry"
      end
      O.leave(s,board,v.tile,v)
      return true,td,"left"
    end
    return true,td
  end

  local function matching(v,t,order)
    return order.should_stop==true and v.owner==t.owner and t.stop_type==(v.bus and "bus" or "truck")
  end
  function O.blocked_load(board,v,order)
    local t=board.tile(v.tile)
    if t and t.kind=="drive_stop" and is_front(v) and v.speed==0 and through_state(v.state) and
        matching(v,t,order) and order.kind~="leave_station" then
      v.last_station_visited=t.station
      return true -- caller triggers stock BeginLoading, no entered-bit mutation
    end
    return false
  end

  -- The controller sees this branch only after the leading-vehicle and
  -- heading probes, at the current frame. Returned action tells the
  -- caller whether it consumed a movement attempt or requested loading.
  -- 'move_inline' is a one-frame commit with UpdateInclination(true,false).
  function O.at_stop(s,board,v,traffic_side,order,compatible)
    local t=board.tile(v.tile)
    if not t or not is_front(v) then return "ordinary" end
    local bay=bay_state(v.state)
    local drive=through_state(v.state)
    if not ((bay and Motion.bay_stop_frame(v.state,traffic_side)==v.frame) or
        (drive and matching(v,t,order) and v.frame==O.DRIVE_STOP_FRAME)) then return "ordinary" end
    local rs=assert(s.stops[v.tile])
    if not bit(v.state,O.ENTERED_STOP) then
      if t.kind=="drive_stop" then
        local next=board.adjacent(v.tile,diag(v.direction))
        if O.continues(board,v.tile,next) and compatible and compatible(next,v) then
          return "move_inline"
        end
      end
      O.set_busy(rs,false)
      v.state=sb(v.state,O.ENTERED_STOP,true)
      v.last_station_visited=t.station
      if t.kind=="drive_stop" or (order.kind=="go_station" and order.station==t.station) then
        return "load"
      end
    else
      if O.entrance_busy(rs) then v.speed=0;return "wait_entrance" end
      if order.kind=="leave_station" then order.kind=nil end
    end
    if t.kind=="bay_stop" then O.set_busy(rs,true) end
    return "depart" -- caller resumes ordinary movement and sound
  end

  function O.commit_through_motion(board,v,order)
    local t=board.tile(v.tile)
    if order.kind=="leave_station" and t and t.kind=="drive_stop" then order.kind=nil end
  end
  function O.routing(s,board)
    local out={}
    for k,v in pairs(board) do out[k]=v end
    out.bay_free=function(id,bay) return O.bay_free(assert(s.stops[id]),bay) end
    out.stop_entry=function(id,direction)
      local e=assert(O.get_entry(s,id,direction),"Missing directional road-stop entry")
      return e.occupied,e.length
    end
    out.stop_continues=function(id,other) return O.continues(board,id,other) end
    return out
  end
  function O.crash(s,board,v)
    if is_front(v) and through_state(v.state) then O.leave(s,board,v.tile,v) end
  end
  function O.delete_tail(s,board,v)
    if bay_state(v.state) then O.leave(s,board,v.tile,v) end
  end
  return O
end
