-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- OpenTTD 14.1 CYapfCostRoadT, CYapfDestinationTileRoadT,
-- CYapfDestinationAnyDepotRoadT (src/pathfinder/yapf/yapf_road.cpp) and
-- CalcClosestStationTile (src/pathfinder/pathfinder_func.h).
-- Module factory takes the stock road follower. No search is performed.
return function(F)
  local C={TILE_LENGTH=100,TILE_CORNER_LENGTH=71,MAX_MAP_SIZE=4096}
  local defaults={road_slope_penalty=200,road_curve_penalty=100,
    road_crossing_penalty=300,road_stop_penalty=800,
    road_stop_occupied_penalty=800,road_stop_bay_occupied_penalty=1500}
  local min,max,abs,floor=math.min,math.max,math.abs,math.floor
  local has=F.has_trackdir
  local function setting(settings,k)
    return settings and settings[k] or defaults[k]
  end

  -- Board adds xy(id) and tile_at(stock_x,stock_y), center_z(id) in stock
  -- height pixels, and the following station/traffic adapters:
  -- station_area(station, "bus"|"truck"|"road_waypoint") -> {tile, w, h} or nil, sign id.
  -- Road-stop records have station and stop_type ("bus" or "truck").
  -- stop_continues(id, previous_id) compares stock stop continuation.
  -- stop_entry(id, exit_direction) -> occupied length, total length.
  -- bay_free(id, 0|1) is true when that bay is empty.
  function C.one_tile(board,tile,td,settings)
    if td~=0 and td~=1 and td~=8 and td~=9 then
      return C.TILE_CORNER_LENGTH+setting(settings,"road_curve_penalty")
    end
    local cost=C.TILE_LENGTH
    local t=assert(board.tile(tile))
    if t.kind=="crossing" then
      cost=cost+setting(settings,"road_crossing_penalty")
    elseif t.kind=="drive_stop" and t.stop_type~="road_waypoint" then
      cost=cost+setting(settings,"road_stop_penalty")
      local dir=F.exit_direction(td)
      local prior=board.adjacent(tile,F.reverse_direction(dir))
      if not board.stop_continues(tile,prior) then
        local occupied,length=board.stop_entry(tile,dir)
        cost=cost+floor(occupied*setting(settings,"road_stop_occupied_penalty")/length)
      end
    elseif t.kind=="bay_stop" then
      local occupied=(board.bay_free(tile,0) and 0 or 1)+(board.bay_free(tile,1) and 0 or 1)
      cost=cost+floor(setting(settings,"road_stop_bay_occupied_penalty")*occupied/2)
    end
    return cost
  end

  function C.slope(board,tile,next_tile,settings)
    if board.center_z(next_tile)-board.center_z(tile)>1 then
      return setting(settings,"road_slope_penalty")
    end
    return 0
  end

  function C.destination(board,vehicle,order)
    if order.kind=="any_depot" then return {kind=order.kind} end
    if order.kind~="station" and order.kind~="road_waypoint" then
      return {kind="tile",tile=order.tile,trackdirs=F.status(board.tile(order.tile),vehicle.tram)}
    end
    -- RC1 CYapfDestinationTileRoadT::SetDestination for OT_GOTO_WAYPOINT
    -- chooses the closest tile of the road-waypoint facility; it never
    -- treats it as a loading stop even when the vehicle is a bus.
    local stop_type=order.kind=="road_waypoint" and "road_waypoint" or (vehicle.bus and "bus" or "truck")
    local area,sign=board.station_area(order.station,stop_type)
    local target=sign
    if area and area.tile~=nil then
      local minx,miny=board.xy(area.tile)
      local x,y=board.xy(vehicle.tile)
      target=board.tile_at(max(minx,min(x,minx+area.w-1)),max(miny,min(y,miny+area.h-1)))
    end
    return {kind="station",tile=target,station=order.station,
      stop_type=stop_type,non_articulated=not vehicle.articulated}
  end

  function C.detect(board,d,tile,td)
    if d.kind=="tile" then return tile==d.tile and has(d.trackdirs,td) end
    local t=board.tile(tile)
    if d.kind=="any_depot" then return t and t.kind=="depot" or false end
    return t and (t.kind=="bay_stop" or t.kind=="drive_stop") and
      t.station==d.station and t.stop_type==d.stop_type and
      (d.non_articulated or t.kind=="drive_stop") or false
  end

  local dx,dy={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  function C.estimate(board,d,node)
    if d.kind=="any_depot" or C.detect(board,d,node.last_tile,node.last_td) then
      return node.cost
    end
    local x1,y1=board.xy(node.last_tile)
    local x2,y2=board.xy(d.tile)
    local dir=F.exit_direction(node.last_td)
    local x,y=abs(2*x1+dx[dir]-2*x2),abs(2*y1+dy[dir]-2*y2)
    local est=node.cost+min(x,y)*C.TILE_CORNER_LENGTH+(abs(x-y)-1)*(C.TILE_LENGTH/2)
    return est
  end

  -- Mutates only this search node. record is an optional trace sink for
  -- ordered tile/trackdir pairs, not part of the OpenTTD search algorithm.
  -- The transition into a junction ends this segment *before* charging
  -- slope, speed or span cost; that ordering is as in upstream.
  function C.calc(board,v,d,node,settings,max_cost,record)
    local cost,tiles=0,0
    local tile,td=node.tile,node.td
    local parent_cost=node.parent and node.parent.cost or 0
    while true do
      if record then record(tile,td) end
      cost=cost+C.one_tile(board,tile,td,settings)
      if C.detect(board,d,tile,td) then break end
      if max_cost and max_cost>0 and parent_cost+cost>max_cost then return false end
      local old=board.tile(tile)
      if old.kind=="depot" and td==F.direction_trackdir(F.reverse_direction(old.dir)) then break end

      local f=F.follow(board,v,tile,td)
      if not f.ok then break end
      local choices=F.trackdirs(f.trackdirs)
      if #choices>1 then break end
      local next_td=assert(choices[1])
      if f.tile==node.tile and next_td==node.td then return false end

      cost=cost+f.skip*C.TILE_LENGTH
      tiles=tiles+f.skip+1
      cost=cost+C.slope(board,tile,f.tile,settings)
      local max_vehicle=min(v.display_max_speed,(v.order_max_speed or 65535)*2)
      local limit,min_speed=F.speed_limit(old,v.tram)
      if limit<max_vehicle then
        cost=cost+floor(C.TILE_LENGTH*(max_vehicle-limit)*(4+f.skip)/max_vehicle)
      end
      if min_speed>max_vehicle then cost=cost+C.TILE_LENGTH*(min_speed-max_vehicle) end
      tile,td=f.tile,next_td
      if tiles>C.MAX_MAP_SIZE then break end
    end
    node.last_tile,node.last_td,node.cost=tile,td,parent_cost+cost
    return true
  end

  return C
end
