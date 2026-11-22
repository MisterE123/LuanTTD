-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Pin 14.1 ship_cmd.cpp ShipController, _ship_subcoord,
-- ShipAccelerate, ReverseShip, CheckShipLeaveDepot, track_func.h VehicleExitDir,
-- vehicle.cpp GetNewVehiclePos, vehicle_base.h and aqueduct-specific cases of
-- VehicleEnter_TunnelBridge. Orders, loading and ship dispatch are external.
return function(T,Water)
  local M={TILE=16,TILE_HEIGHT=8,WORMHOLE=64,DEPOT=128}
  local floor,abs,min=math.floor,math.abs,math.min
  local dx,dy={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local sub={
    [0]={[0]={15,8,1},[3]={15,8,2},[4]={15,7,0}},
    {[1]={8,0,3},[2]={7,0,2},[4]={8,0,4}},
    {[0]={0,8,5},[2]={0,7,6},[5]={0,8,4}},
    {[1]={8,15,7},[3]={8,15,6},[5]={7,15,0}},
  }
  local high_dir={[12]=0,[6]=1,[3]=2,[9]=3}
  local exit_bits={[0]=32,8,16,4}
  local opposite={[0]=0,1,3,2,5,4}
  local function first(bits)
    for tr=0,5 do if T.has(bits,tr) then return tr end end
  end

  function M.entry(dir,tr)
    local p=sub[dir] and sub[dir][tr]
    if p then return p[1],p[2],p[3] end
  end
  function M.displacement(dir) return dx[dir],dy[dir] end
  function M.exit_direction(dir,track)
    local d=floor(dir/2)
    if dir%2==0 and track~=exit_bits[d] then return (d+3)%4 end
    return d
  end
  function M.trackdir(v)
    if v.track==M.DEPOT or v.track==M.WORMHOLE then return T.diagonal_trackdir(floor(v.direction/2)) end
    local tr=first(v.track)
    return tr and T.trackdir_for_exit(tr,M.exit_direction(v.direction,v.track)) or nil
  end

  -- All coordinates are stock pixels: 16 per tile and 8 per height level.
  -- direction is the travel heading, rotation is what the user sees.
  function M.new(board,id,td,values)
    values=values or {}
    if not T.valid_trackdir(td) or not T.has(Water.at(board,id),td) then return nil,"invalid_origin" end
    local x,y=board.xy(id)
    local t=board.tile(id)
    local tr=T.track(td)
    local px,py=8,8
    if tr>=2 then px,py=M.entry(T.reverse_side(T.entry_side(td)),tr) end
    local heading=T.heading(td)
    return {x=values.x or x*16+px,y=values.y or y*16+py,z=values.z or (t.base or 0)*8,tile=id,
      direction=heading,rotation=heading,track=values.in_depot and M.DEPOT or 2^tr,
      order=values.order,speed=values.speed or 0,max_speed=values.max_speed or 0,
      acceleration=values.acceleration or 0,progress=values.progress or 0,tick=values.tick or 0,
      owner=values.owner,hidden=values.in_depot or nil}
  end

  function M.reverse(v,td)
    if td~=nil and T.valid_trackdir(td) then
      v.direction,v.track=T.heading(td),2^T.track(td)
    else
      v.direction=(v.direction+4)%8
    end
    v.rotation_x,v.rotation_y=v.x,v.y
    v.speed=0
    v.path,v.path_index=nil,nil
    return "reverse"
  end

  function M.rotate(v)
    local delta=(v.direction-v.rotation)%8
    if delta==0 then return false end
    if v.tick%8==0 then v.rotation=(v.rotation+(delta>4 and -1 or 1))%8 end
    return true
  end
  function M.visual(v)
    if v.direction~=v.rotation then return v.rotation_x or v.x,v.rotation_y or v.y,v.z,v.rotation end
    return v.x,v.y,v.z,v.rotation
  end

  function M.lock_delta(board,v)
    local t=board.tile(v.tile)
    if not t or t.kind~="lock" or t.part~="middle" or v.x%16~=8 or v.y%16~=8 then return 0 end
    local d=high_dir[t.slope]
    if d==nil then return 0 end
    local low=(t.base or 0)*8
    local high=(t.top or (t.base or 0)+1)*8
    if floor(v.direction/2)==d then return v.z<high and 1 or 0 end
    return v.z>low and -1 or 0
  end
  function M.move_lock(board,v)
    local d=M.lock_delta(board,v)
    if d==0 then return false end
    v.speed=0
    if v.tick%8==0 then v.z=v.z+d end
    return true
  end

  function M.accelerate(v,max_speed)
    v.speed=min(v.speed+v.acceleration,max_speed or v.max_speed,((v.order and v.order.max_speed) or 65535)*2)
    local distance=v.direction%2==1 and 192 or 256
    local advance=floor(v.speed*3/4)+v.progress
    v.progress=advance%distance
    return floor(advance/distance)
  end

  function M.set_path(v,trace)
    local origin=trace and trace[1]
    if not origin or origin.tile~=v.tile or origin.td~=M.trackdir(v) then return false end
    v.path,v.path_index=trace,2
    return true
  end
  function M.leave(v,next_order)
    v.loading=nil
    v.leaving=true
    v.order=next_order
    v.path,v.path_index=nil,nil
  end

  local function allowed(board,target,entry)
    return T.trackbits(T.intersect(Water.at(board,target),T.reachable(entry)))
  end
  local function adjacent(board,a,b)
    local x,y=board.xy(a)
    local u,v=board.xy(b)
    for d=0,3 do if u-x==dx[2*d+1] and v-y==dy[2*d+1] then return d end end
  end
  local function choose(board,v,target,bits,entry,h)
    local p=v.path and v.path[v.path_index]
    if p then
      local tr=T.track(p.td)
      if p.tile==target and T.has(bits,tr) and T.trackdir_for_entry(tr,entry)==p.td then
        v.path_index=v.path_index+1
        return tr
      end
      v.path,v.path_index=nil,nil
    end
    if v.order then return h.choose_track and h.choose_track(board,v,target,bits,entry) or nil end
    local tr=opposite[first(v.track)]
    return tr and T.has(bits,tr) and tr or first(bits)
  end

  -- The depot's saved tile is its north half. The south exit is two tiles
  -- away. The planner may select the south exit when both approaches work.
  function M.depart_depot(board,v,h)
    h=h or {}
    if v.track~=M.DEPOT then return "sailing" end
    if not v.order or v.wait_unbunch or (h.depot_busy and h.depot_busy(board,v.tile)) then return "depot_wait" end
    local t=board.tile(v.tile)
    if v.order.kind=="depot" and t.depot~=nil and t.depot==v.order.id then return "depot" end
    local south,north=t.axis==0 and 2 or 1,t.axis==0 and 0 or 3
    local a=board.adjacent(v.tile,north)
    local inside=board.adjacent(v.tile,south)
    local b=inside~=nil and board.adjacent(inside,south) or nil
    local left,right=allowed(board,a,north)~=0,allowed(board,b,south)~=0
    if left and right and h.reverse_depot and h.reverse_depot(board,v) then left=false end
    if not left and not right then return "depot_wait" end
    v.direction=(left and north or south)*2+1
    v.rotation,v.track,v.hidden,v.speed=v.direction,2^t.axis,nil,0
    return "depot_depart"
  end

  local function allow_entry(h,board,v,id,x,y,phase)
    return not h.can_enter or h.can_enter(board,v,id,x,y,phase)~=false
  end

  -- One stock movement proposal, separate from the fixed tick/speed
  -- policy. Returns an event and whether the stock controller returned
  -- early. choose_track(board,v,target,bits,entry) returns plain Track 0..5.
  function M.step(board,v,h)
    h=h or {}
    local x,y=v.x+dx[v.direction],v.y+dy[v.direction]
    local target=board.tile_at(floor(x/16),floor(y/16))
    if v.track==M.WORMHOLE then
      if target==v.wormhole_exit then
        local t=board.tile(target)
        local dir=floor(v.direction/2)
        if not t or t.kind~="aqueduct" or t.dir~=T.reverse_side(dir) or t.other~=v.tile then
          return "bad_aqueduct_exit",true
        end
        local deck=t.deck and t.deck*8 or v.z
        if abs(deck-v.z)>2 then return "bad_aqueduct_height",true end
        if not allow_entry(h,board,v,target,x,y,"aqueduct_exit") then return "blocked",true end
        v.tile,v.track,v.wormhole_exit=target,2^(dir%2),nil
        local p=v.path and v.path[v.path_index]
        if p and p.tile==target and p.td==T.diagonal_trackdir(dir) then v.path_index=v.path_index+1
        elseif p then v.path,v.path_index=nil,nil end
        v.x,v.y=x,y
        return "aqueduct_exit",false
      end
      if target==nil then return "bad_aqueduct_exit",true end
      v.x,v.y=x,y
      return "aqueduct",true
    end

    if target==v.tile then
      if v.track==M.DEPOT then return "depot_wait",true end
      if not allow_entry(h,board,v,target,x,y,"same") then return M.reverse(v),true end
      local t=board.tile(target)
      if t.kind=="aqueduct" and v.direction==2*t.dir+1 then
        local u=(t.dir%2==0 and x or y)%16
        if (t.dir==0 or t.dir==3) and u==0 or (t.dir==1 or t.dir==2) and u==15 then
          local deck=t.deck and t.deck*8 or v.z
          if abs(deck-v.z)>2 or t.other==nil then return M.reverse(v),true end
          v.track,v.wormhole_exit=M.WORMHOLE,t.other
          v.x,v.y=x,y
          return "aqueduct_enter",false
        end
      end
      local event="move"
      if v.leaving then
        v.leaving=nil
        local dir=M.exit_direction(v.direction,v.track)
        if Water.at(board,board.adjacent(v.tile,dir),dir)==0 then return M.reverse(v),true end
        event="leave"
      elseif v.order and not v.loading then
        local o=v.order
        if o.kind=="waypoint" and o.tile~=nil then
          local a,b=board.xy(v.tile)
          local c,d=board.xy(o.tile)
          if abs(a-c)+abs(b-d)<=3 then
            event="waypoint"
            v.order,v.path,v.path_index=nil,nil,nil
            if h.on_waypoint then h.on_waypoint(board,v,o) end
          end
        elseif o.kind=="depot" and o.tile==v.tile and x%16==8 and y%16==8 then
          v.x,v.y=x,y
          v.track,v.hidden,v.speed=M.DEPOT,true,0
          v.path,v.path_index=nil,nil
          return "depot",true
        elseif o.kind=="station" and Water.ship_destination(board,target,o.id) and
            (not h.docking_area or h.docking_area(board,target,o.id)) then
          v.last_station=o.id
          if not h.station_has_dock or h.station_has_dock(board,o.id) then
            v.loading=true
            event="dock"
          else
            v.leaving=true
            if h.on_no_dock then h.on_no_dock(board,v,o) end
            event="no_dock"
          end
        end
      end
      v.x,v.y=x,y
      return event,false
    end

    if target==nil or (board.is_valid and not board.is_valid(target)) then return M.reverse(v),true end
    local diag=adjacent(board,v.tile,target)
    if diag==nil then return M.reverse(v),true end
    local bits=allowed(board,target,diag)
    if bits==0 then
      local rev=h.reverse_trackdir and h.reverse_trackdir(board,v,target) or nil
      return M.reverse(v,rev),true
    end
    local tr=choose(board,v,target,bits,diag,h)
    if tr==nil or not T.has(bits,tr) then return M.reverse(v),true end
    local ax,ay,direction=M.entry(diag,tr)
    if ax==nil then return M.reverse(v),true end
    x,y=x-x%16+ax,y-y%16+ay
    local t=board.tile(target)
    if t.kind=="aqueduct" and (t.dir~=diag or abs((t.deck and t.deck*8 or v.z)-v.z)>2) then
      return M.reverse(v),true
    end
    if not allow_entry(h,board,v,target,x,y,"enter") then return M.reverse(v),true end
    local old=Water.water_class(board.tile(v.tile))
    v.tile,v.track=target,2^tr
    local new=Water.water_class(t)
    if new~=old and h.water_changed then h.water_changed(board,v,new,old) end
    local delta=(direction-v.direction)%8
    if delta==0 or delta==1 or delta==7 then
      v.rotation=direction
    else
      v.speed=0
      v.rotation_x,v.rotation_y=v.x,v.y
    end
    v.direction,v.x,v.y=direction,x,y
    return delta==0 and "enter" or (delta==1 or delta==7) and "curve" or "turn",false
  end

  function M.physical_tile(board,v)
    return board.tile_at(floor(v.x/16),floor(v.y/16))
  end

  function M.tick(board,v,h)
    h=h or {}
    v.tick=v.tick+1
    v.order_time=(v.order_time or 0)+1
    if v.stopped or v.breakdown then return "stopped",0 end
    if v.loading then return "loading",0 end
    if v.track==M.DEPOT then
      local outcome=M.depart_depot(board,v,h)
      if outcome~="depot_depart" then return outcome,0 end
    end
    if M.rotate(v) then return "rotate",0 end
    if M.move_lock(board,v) then return "lock",0 end
    local speed=h.max_speed and h.max_speed(board,v) or nil
    local steps=M.accelerate(v,speed)
    local report="wait"
    for i=1,steps do
      if M.move_lock(board,v) then return "lock",i-1 end
      local event,halt=M.step(board,v,h)
      if (report~="dock" and report~="no_dock" and report~="waypoint") or event=="depot" then report=event end
      if halt then return report,i end
    end
    return report,steps
  end
  return M
end
