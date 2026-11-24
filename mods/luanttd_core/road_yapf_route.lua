-- Integration for the current day-stepped motion renderer. The chosen
-- route is the stock YAPF parent chain and exact segment trace, not BFS.
-- The stock per-tick vehicle controller still needs its own integration.
return function(Sim,F,C,Search,Board,Motion,MotionLeg)
  local R={}
  local base=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local speed=dofile(base.."/road_stock_speeds.lua")
  function R.frames(board,trace,origin,departure_bay)
    local last=trace[#trace]
    local dest=last and board.tile(last.tile)
    if not dest then return end
    local leg=MotionLeg(Motion,F,board)
    local frames=leg.compile(trace,origin,{departure_bay=departure_bay})
    if not frames or not dest.pair then return frames end
    local second=leg.compile(trace,origin,{departure_bay=departure_bay,arrival_bay=1})
    if not second then return end
    -- Only the arrival in this final dead-end tile can diverge.
    -- Retain a single common route and an alternate local tail.
    local entry
    for i=2,#frames do
      if frames[i][4]==last.tile and frames[i][9] then entry=i;break end
    end
    if not entry or not second[entry] or second[entry][4]~=last.tile or not second[entry][9] then return end
    for i=1,entry-1 do
      local a,z=frames[i],second[i]
      for n=1,15 do if a[n]~=z[n] then return end end
    end
    local bays={first=entry,second={},tile=last.tile}
    for i=entry,#second do bays.second[#bays.second+1]=second[i] end
    return frames,bays
  end
  -- Concatenate stock pathfinder legs by the exact trackdir of the
  -- moving front. The waypoint is a destination for YAPF, never a
  -- stopping frame; the complete motion raster is compiled only once.
  local function through(board,v,start,mask,stops,destination)
    local trace,cost,best={},0,nil
    local orders={}
    for _,wp in ipairs(stops or {}) do
      if not board.station_area(wp,"road_waypoint") then return end
      orders[#orders+1]={kind="road_waypoint",station=wp}
    end
    orders[#orders+1]=destination
    for _,order in ipairs(orders) do
      v.tile=start
      local goal=C.destination(board,v,order)
      local found,tail=Search.find(board,v,start,mask,goal)
      if not found then return end
      local leg=Search.trace(board,v,goal,tail)
      if not leg or #leg==0 then return end
      if #trace>0 then
        local prior,current=trace[#trace],leg[1]
        if prior.tile~=current.tile or prior.td~=current.td then return end
        cost=cost-C.one_tile(board,prior.tile,prior.td)
      end
      for i=#trace>0 and 2 or 1,#leg do trace[#trace+1]=leg[i] end
      local last=assert(trace[#trace])
      start,mask=last.tile,2^last.td
      cost,best=cost+tail.cost,tail
    end
    return trace,best,cost
  end
  function R.route(s,a,b,owner,vehicle,occupancy,waypoints)
    local board=Board(Sim,s,F,occupancy)
    local from=a.tile
    local pose=vehicle and vehicle.road_stop_pose
    if pose and a.id then
      local t=board.tile(pose[4])
      if t and t.station==a.id and not t.waypoint then from=pose[4] end
    end
    local source,dest=board.tile(from),board.tile(b.tile)
    if not source or not dest or not dest.station then return nil end
    local bus=vehicle==nil or vehicle.cargo=="passenger"
    if (source.pair or dest.pair) and vehicle and vehicle.engine~="bus" and
        vehicle.engine~="leopard_bus" and vehicle.engine~="foster_bus" and vehicle.engine~="foster_mk2_bus" then return nil end
    local v={owner=owner,bus=bus,tile=from,display_max_speed=speed[vehicle and vehicle.engine or "bus"]}
    local facility=bus and "bus" or "truck"
    if dest.stop_type~=facility and not board.station_area(dest.station,facility) then return nil end
    if (a.id~=nil and a.id==b.id or from==b.tile) and not (waypoints and #waypoints>0) then return {from},vehicle and vehicle.road_arrival_td end
    local mask
    if source.kind=="depot" or source.kind=="bay_stop" then
      -- Stock depot departure or the outward-facing phase after leaving
      -- a bay. The renderer handles the local in-tile visual turnaround.
      mask=2^F.direction_trackdir(source.dir)
    elseif source.kind=="drive_stop" then
      local available=F.tile_trackdirs(source,false)
      local td=vehicle and vehicle.road_arrival_td
      -- A vehicle arriving in a through stop keeps its approach heading.
      -- Both axes are legal only before its first run (or an older save).
      mask=td and F.has_trackdir(available,td) and 2^td or available
    else
      return nil
    end
    local trace,best,cost=through(board,v,from,mask,waypoints,{kind="station",station=dest.station})
    if not trace then return nil end
    local path,bridge={},false
    for _,piece in ipairs(trace) do
      local kind=board.tile(piece.tile).kind
      if kind=="bridge" or kind=="tunnel" then bridge=true end
      -- A same-tile stock turn consumes time in the fine controller, but
      -- cannot be drawn as a zero-length line by the legacy renderer.
      if path[#path]~=piece.tile then path[#path+1]=piece.tile end
    end
    local origin=source.pair and vehicle and vehicle.road_stop_pose
    local row=origin and origin[6]
    local origin_bay=row and row>=32 and row<48 and math.floor(row/2)%2 or nil
    local frames,bays=R.frames(board,trace,nil,origin_bay)
    -- Do not fall back to a ground-plane line between bridgeheads if a
    -- stale or malformed span cannot produce its selected crossing.
    if (bridge or source.pair or dest.pair or waypoints and #waypoints>0) and not frames then return nil end
    return path,best.last_td,cost,frames,bays
  end
  -- From the exact front position on an ordinary road in mid-leg.
  -- Warehouse stops, tunnel/bridge interiors and a temporary passing lane
  -- have distinct controller states; never snap them to an invented road
  -- origin. The caller can retry after a real ordinary position is reached.
  function R.from_live_frame(s,vehicle,frame,target_station,occupancy,waypoints)
    if not frame or not vehicle or vehicle.road_speed_state and vehicle.road_speed_state.lane_pose then return end
    local board=Board(Sim,s,F,occupancy)
    local id,td=frame[4],frame[6]
    local source=board.tile(id)
    if not source or source.kind~="road" or not F.has_trackdir(F.status(source,false),td)
        or frame[10] or frame[12] or frame[13] or frame[14] then return end
    local bus=vehicle.cargo=="passenger"
    local v={owner=vehicle.owner,bus=bus,tile=id,display_max_speed=speed[vehicle.engine]}
    if not v.display_max_speed then return end
    local dest=target_station and {kind="station",station=target_station} or {kind="any_depot"}
    local trace,best,cost=through(board,v,id,2^td,waypoints,dest)
    if not trace or #trace<2 then return end
    local last=trace[#trace]
    local finish=board.tile(last.tile)
    if not finish or finish.owner~=vehicle.owner then return end
    local frames,bays
    if target_station then
      if finish.station~=target_station then return end
      frames,bays=R.frames(board,trace,frame)
    else
      if finish.kind~="depot" then return end
      frames=MotionLeg(Motion,F,board).compile(trace,frame,{depot=true})
    end
    if not frames or #frames<2 then return end
    for _,key in ipairs({1,2,3,4,6,15}) do
      if frames[1][key]~=frame[key] then return end
    end
    local path={}
    for _,piece in ipairs(trace) do
      if path[#path]~=piece.tile then path[#path+1]=piece.tile end
    end
    return path,last.tile,best.last_td,cost,frames,bays
  end

  -- OpenTTD 14.1 YapfRoadVehicleFindNearestDepot: exact current trackdir
  -- and the unbounded-cost any-owned-depot destination, not a search by
  -- Manhattan distance or an iteration over depot IDs. This adapter
  -- only accepts a settled stock road-stop pose, never a guessed one.
  function R.nearest_depot(s,stop,vehicle,occupancy)
    local board=Board(Sim,s,F,occupancy)
    local frame=vehicle.road_stop_pose
    local from=frame and frame[4]
    local source=from and board.tile(from)
    if not source or source.station~=stop.id or source.waypoint then return end
    local dir
    if source.kind=="bay_stop" then dir=source.dir
    elseif source.kind=="drive_stop" then dir=math.floor(frame[3]/2)
    else return end
    local td=F.direction_trackdir(dir)
    if not td or not F.has_trackdir(F.status(source,false),td) then return end
    local v={owner=vehicle.owner,bus=vehicle.cargo=="passenger",tile=from,display_max_speed=speed[vehicle.engine]}
    local to=C.destination(board,v,{kind="any_depot"})
    local found,best=Search.find(board,v,from,2^td,to)
    if not found then return end
    local selected=Search.trace(board,v,to,best)
    if not selected or #selected<2 then return end
    local last=selected[#selected]
    local exit=board.tile(last.tile)
    if not exit or exit.kind~="depot" or exit.owner~=vehicle.owner then return end
    local by=source.pair and math.floor(frame[6]/2)%2 or nil
    local frames=MotionLeg(Motion,F,board).compile(selected,nil,{departure_bay=by,depot=true})
    if not frames or #frames<2 then return end
    local origin=frames[1]
    for _,i in ipairs({1,2,3,4,6,15}) do if frame[i]~=origin[i] then return end end
    local path={}
    for _,p in ipairs(selected) do if path[#path]~=p.tile then path[#path+1]=p.tile end end
    return path,last.tile,best.last_td,best.cost,frames
  end
  return R
end
