-- SPDX-License-Identifier: GPL-2.0-only
-- Non-articulated OpenTTD 14.1 tram trip adapter. YAPF chooses
-- all routing and legal one-bit reversals; TramMotion owns pixels and
-- the controller's long/short turn decisions. No map/vehicle mutation.
return function(F,Cost,Search,Motion)
  local M={}
  local dirs={[0]=8,4,2,1}
  local function one(bits) return bits==1 or bits==2 or bits==4 or bits==8 end
  local function depot(t) return t and t.kind=="depot" end
  local function stop(t) return t and t.kind=="drive_stop" end
  local function end_state(t,td) return stop(t) and 64+td or td end
  local function driving(t) return t and (t.kind=="road" or depot(t) or stop(t)) end
  local function tram_type(v,t)
    if not driving(t) or t.tramtype==nil then return false end
    if v.compatible then return v.compatible[t.tramtype]==true end
    return t.tramtype==(v.tramtype or 1)
  end
  local function effective(board,id,t)
    if board.tram_bits then return board.tram_bits(id,true) or 0 end
    return t.tram_bits or 0
  end
  local function at_end(table_state,t,frame)
    if stop(t) then return table_state>=64 and frame==Motion.DRIVE_THROUGH_STOP end
    if depot(t) then return table_state<16 and frame==11 end -- RVC_DEPOT_STOP_FRAME
    return false
  end

  -- Presentation mapping matches road_motion_presentation. Flips between
  -- lateral and longitudinal units in genuine table-defined curves only.
  local last_frame={}
  local function projection(td,state,frame,side)
    local leaving=F.exit_direction(td)
    local entering=F.exit_direction(F.reverse_trackdir(td))
    if leaving==nil or entering==nil then return .5 end
    local a,b=1-entering%2,1-leaving%2
    if a==b then return a end
    local idx=state+80*side
    if not last_frame[idx] then
      local i=0
      while Motion.sample(state,side,i+1)=="position" do i=i+1 end
      last_frame[idx]=math.max(1,i)
    end
    local f=math.max(0,math.min(1,(frame/last_frame[idx]-.23)/.54))
    return a+(b-a)*f*f*(3-2*f)
  end

  -- Compile a stock YAPF trace from depot release/current through-stop
  -- frame to the destination's true stop frame. Advanced callers can
  -- supply a requested synthetic reversal {tile=same,td=opposite} for
  -- a short turn; ordinary automatic YAPF never fabricates that at a
  -- broken multi-bit tram track. Traces that cannot be executed fail
  -- rather than teleporting, guessing an alternate route or skipping it.
  function M.compile(board,trace,vehicle,settings)
    settings=settings or {}
    if #trace<2 or vehicle.articulated then return nil,"unsupported_trip" end
    local side=settings.road_side or 1
    if side~=0 and side~=1 then return nil,"invalid_road_side" end
    local first=trace[1]
    local start=board.tile(first.tile)
    local finish=board.tile(trace[#trace].tile)
    if not (depot(start) or stop(start)) or not (depot(finish) or stop(finish)) then
      return nil,"terminal_required"
    end
    local height=board.center_z(first.tile)
    for i,p in ipairs(trace) do
      local t=board.tile(p.tile)
      if not tram_type(vehicle,t) then return nil,"unsupported_surface" end
      if p.td==nil or not F.has_trackdir(F.tile_trackdirs(t,true),p.td) then return nil,"illegal_trackdir" end
      if board.surface then
        if not board.surface(p.tile) then return nil,"unsupported_surface" end
        local prev=trace[i-1]
        if prev and prev.tile~=p.tile and
            not board.edge_available(prev.tile,p.tile,F.exit_direction(prev.td),vehicle) then
          return nil,"unsupported_surface"
        end
      elseif (t.slope or 0)~=0 or board.center_z(p.tile)~=height then return nil,"unsupported_surface" end
    end
    if depot(start) and first.td~=F.direction_trackdir(start.dir) then return nil,"wrong_depot_departure" end
    local v={direction=2*F.exit_direction(first.td)+1,tile=first.tile,
      state=end_state(start,first.td),frame=depot(start) and Motion.DEPOT_START or Motion.DRIVE_THROUGH_STOP,
      owner=vehicle.owner,tramtype=vehicle.tramtype or 1,compatible=vehicle.compatible,
      articulated=false,front=true,tram=true,bus=vehicle.bus}
    local k,dx,dy=Motion.sample(v.state,side,v.frame)
    if k~="position" then return nil,"invalid_initial_frame" end
    local sx,sy=board.xy(first.tile)
    v.x,v.y=16*sx+dx,16*sy+dy
    local p=1
    local frames,turn_mode={}
    local function append(x,y,entered)
      frames[#frames+1]={v.x,v.y,v.direction,v.tile,projection(trace[p].td,v.state,v.frame,side),
        v.state,x,y,entered}
    end
    local function enter(id,state,frame)
      local tx,ty=board.xy(id)
      local event,x,y,d,f=Motion.enter(v,tx,ty,state,side,frame)
      if not event or math.abs(x-v.x)>1 or math.abs(y-v.y)>1 then return false end
      v.x,v.y,v.direction,v.frame,v.state,v.tile=x,y,d,f,state,id
      return true
    end
    local function start_turn(target,approach,expected)
      local reverse=Motion.reverse_trackdir[approach]
      local style,id,frame=Motion.start_reverse(board,v,target,reverse)
      if style=="wait" then return nil,"awaiting_track" end
      if style~=expected or id==nil or not enter(id,reverse,frame) then return nil,"unavailable_turn" end
      turn_mode=style
      return true
    end
    append()
    for _=1,#trace*96 do
      local tile=board.tile(v.tile)
      if p==#trace and at_end(v.state,tile,v.frame) then return frames end
      local event,x,y,d,f,cx,cy=Motion.step(v,side)
      if event=="move" or event=="rotate" then
        v.x,v.y,v.direction,v.frame=x,y,d,f
        append(cx,cy)
      elseif event=="next_tile" then
        local target=board.adjacent(v.tile,x)
        local nextp=trace[p+1]
        if not nextp then return nil,"trace_ends_in_motion" end
        if nextp.tile==v.tile then
          -- The short turn is performed at the current tile's far edge;
          -- trace advances only when the TURNED marker is consumed.
          if turn_mode then return nil,"overlapping_turn" end
          local ok,reason=start_turn(target,x,"short")
          if not ok then return nil,reason end
          append()
        else
          if target~=nextp.tile or turn_mode=="short" then return nil,"discontinuous_trace" end
          local nextt=board.tile(target)
          if not tram_type(v,nextt) then return nil,"unavailable_track" end
          local after=trace[p+2]
          if nextt.kind=="road" and nextt.tram_bits==dirs[F.reverse_direction(x)] and
              after and after.tile==target and after.td==F.reverse_trackdir(nextp.td) then
            if not one(effective(board,target,nextt)) then return nil,"invalid_one_bit_endpoint" end
            local ok,reason=start_turn(target,x,"long")
            if not ok then return nil,reason end
          else
            turn_mode=nil
            if not enter(target,end_state(nextt,nextp.td),Motion.DEFAULT_START) then return nil,"bad_tile_entry" end
          end
          p=p+1
          append(nil,nil,true)
        end
      elseif event=="turned" then
        local nextp=trace[p+1]
        if not turn_mode or not nextp or nextp.tile~=v.tile then return nil,"missing_turn_trace" end
        local td,frame=Motion.turned(tile,effective(board,v.tile,tile),x,nextp.td)
        if not td or not enter(v.tile,td,frame) then return nil,"bad_turn_continuation" end
        turn_mode=nil
        p=p+1
        append(nil,nil,true)
      else
        return nil,"invalid_drive_table"
      end
    end
    return nil,"excessive_trip"
  end

  -- Road YAPF source kernel returns route while the presentation trace has
  -- extra duplicate tiles for long/internal turns. Keep both rather than
  -- replacing a curve with a line segment or modifying source path cost.
  function M.route(board,a,b,vehicle,settings)
    settings=settings or {}
    if not vehicle or vehicle.articulated then return nil,"unsupported_trip" end
    local start,finish=board.tile(a),board.tile(b)
    if not (stop(start) or depot(start)) or not (stop(finish) or depot(finish)) or
        not tram_type(vehicle,start) or not tram_type(vehicle,finish) then
      return nil,"compatible_terminals_required"
    end
    if (start.owner~=nil and start.owner~=vehicle.owner) or
        (finish.owner~=nil and finish.owner~=vehicle.owner) then return nil,"terminal_owner" end
    local bus=vehicle.bus
    if bus==nil then bus=vehicle.cargo==nil or vehicle.cargo=="passenger" end
    local facility=bus and "bus" or "truck"
    if (stop(start) and start.stop_type~=facility) or (stop(finish) and finish.stop_type~=facility) then
      return nil,"terminal_facility"
    end
    local v={tram=true,tramtype=vehicle.tramtype or 1,owner=vehicle.owner,bus=bus,tile=a,
      display_max_speed=vehicle.display_max_speed or 96,order_max_speed=vehicle.order_max_speed,
      compatible=vehicle.compatible or {[vehicle.tramtype or 1]=true}}
    local td=vehicle.tram_arrival_td or vehicle.road_arrival_td
    if a==b then return {a},td,0,nil,{} end
    local mask
    if depot(start) then
      mask=2^F.direction_trackdir(start.dir)
    else
      local available=F.tile_trackdirs(start,true)
      mask=td and F.has_trackdir(available,td) and 2^td or available
    end
    local order=stop(finish) and {kind="station",station=finish.station} or {kind="tile",tile=b}
    local d=Cost.destination(board,v,order)
    local yes,best=Search.find(board,v,a,mask,d,settings)
    if not yes then return nil,"no_path" end
    local trace=Search.trace(board,v,d,best,settings)
    if trace[#trace].tile~=b then return nil,"alternate_station_tile" end
    local frames,why=M.compile(board,trace,v,settings)
    if not frames then return nil,why end
    local path={}
    for _,piece in ipairs(trace) do
      if path[#path]~=piece.tile then path[#path+1]=piece.tile end
    end
    return path,best.last_td,best.cost,frames,trace
  end
  return M
end
