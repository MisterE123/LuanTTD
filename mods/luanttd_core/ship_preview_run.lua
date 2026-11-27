-- One MPS passenger ferry pilot. The stock pathfinder/controller is
-- shared by the original empty pilot and opt-in paid simulation clock.
return function(Network,Track,Water,Y,Motion,Regions,extents,config)
  config=config or {}
  local source=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/"
  local O=dofile(source.."rail_order_list.lua")
  local key,serial=config.key or "ship_pilot",config.serial or "next_paid_ferry_run"
  local R={VERSION=1,engine=config.engine or {id=206,max_speed=64,acceleration=1,capacity=100}}
  function R.engine_for(p) return config.engine_for and config.engine_for(p and p.engine_id) or R.engine end
  local function paid_mode(s) return config.paid and config.paid(s) or not config.paid and s.ship_paid_service end
  local function route_order(v)
    local o=v.order
    if o.kind=="waypoint" then return {kind=o.kind,tile=o.tile} end
    return {kind="station",station=o.id}
  end
  local worlds=setmetatable({},{__mode="k"})
  local function lookup(s)
    local cached=worlds[s]
    if not cached or cached.topology~=s.topology then
      local board=Network.board(s,config.occupancy and function(tile) return config.occupancy(s,tile) end)
      cached={board=board,topology=s.topology}
      cached.region=Regions and Regions(Track,Water,board,extents)
      worlds[s]=cached
    end
    return cached.board,cached.region
  end
  -- RC1 InvalidateWaterRegion: a changed tile dirties its own patch
  -- and any neighboring region whose boundary reads it. For anything
  -- other than a proven plain tide, keep the conservative full rebuild.
  function R.after_plain_flood(s,previous,first)
    local cached=worlds[s]
    if not cached or previous==nil or cached.topology~=previous or s.topology~=previous+1 then return end
    if cached.region then
      for i=first,#s.changed do cached.region.invalidate(s.changed[i]) end
    end
    -- The water board reads authoritative terrain and facilities live.
    -- Preserve its region index, not a previously sampled tile or route.
    cached.topology=s.topology
  end
  local function plan(board,v,td,region)
    if not td or not v.order then return end
    local order=route_order(v)
    if region then
      local follow=Water.follow(board,v,v.tile,td)
      if follow.ok then
        return region.find_route(Y,v,v.tile,Track.trackdirbit(td),follow.tile,order)
      end
    end
    local d=Y.destination(board,v,order)
    if not d then return end
    local found,best=Y.find(board,v,v.tile,Track.trackdirbit(td),d)
    if found then return Y.trace(board,v,d,best) end
  end
  local function depot_options(board,axis,v,region)
    local d1,d2=axis==0 and Track.NE or Track.NW,axis==0 and Track.SW or Track.SE
    return plan(board,v,Track.diagonal_trackdir(d1),region),plan(board,v,Track.diagonal_trackdir(d2),region)
  end
  function R.current(s)
    local p=s[key]
    if p and p.version==R.VERSION then return p end
  end
  function R.ordered_dock(p,id)
    if not p.transport_orders then return id==p.first or id==p.second end
    if p.vehicle.loading and p.last_dock==id then return true end
    for _,o in ipairs(p.transport_orders) do if o.kind=="station" and o.id==id then return true end end
    return false
  end
  function R.uses_facilities(s)
    return R.current(s)~=nil
  end
  local function waypoint_order(via,id)
    return {kind="waypoint",id=via.id,tile=via.tile,next_station=id}
  end
  local function station_order(id) return {kind="station",id=id} end
  function R.quote(s,owner,depot,first,second,via_tile,engine_id)
    if R.current(s) then return nil,"PILOT_ALREADY_EXISTS" end
    if paid_mode(s) and not (s.road_stock_house_supply and s.corner_grid) then
      return nil,"STOCK_HOUSE_CLOCK_REQUIRED"
    end
    local D=s.stock_ship_depots or {}
    local S=s.stock_ship_stations or {}
    local function permitted(st)
      return st and (st.owner==owner or config.use_neutral and config.use_neutral(s,st,owner))
    end
    if not (D[depot] and S[first] and S[second] and first~=second and D[depot].owner==owner and
        permitted(S[first]) and permitted(S[second])) then return nil,"OWN_DEPOT_AND_TWO_DOCKS_REQUIRED" end
    local model=R.engine_for({engine_id=engine_id})
    if engine_id and model.id~=engine_id then return nil,"UNKNOWN_PASSENGER_FERRY" end
    local board,region=lookup(s)
    local via
    if via_tile~=nil then
      local tile=board.tile(via_tile)
      local buoy=tile and tile.kind=="buoy" and s.stock_ship_buoys and s.stock_ship_buoys[tile.station]
      if not buoy or buoy.tile~=via_tile then return nil,"SELECT_BUOY" end
      via={id=buoy.id,tile=via_tile,passes=0}
    end
    if R.start_guard then
      local ok,why=R.start_guard(s,depot,first,second,board)
      if not ok then return nil,why end
    end
    local depot_tile,axis=D[depot].tiles[1],D[depot].axis
    local v=Motion.new(board,depot_tile,Track.diagonal_trackdir(axis==0 and Track.SW or Track.SE),{
      owner=owner,order={kind="station",id=first},max_speed=model.max_speed,
      acceleration=model.acceleration,in_depot=true})
    if not v then return nil,"INVALID_DEPOT" end
    v.ocean_speed_frac,v.canal_speed_frac=model.ocean_speed_frac or 0,model.canal_speed_frac or 0
    local left,right=depot_options(board,axis,v,region)
    if not left and not right then return nil,"NO_CHANNEL_TO_FIRST_DOCK" end
    if via then
      -- Region search can end at an intermediate patch. Preflight the
      -- actual directed goals, including the stock within-three skip
      -- frame (not the buoy tile we'd reach if we ignored that skip).
      local function from(frame,order)
        local mock={tile=frame.tile,owner=owner,order=order,ocean_speed_frac=v.ocean_speed_frac,
          canal_speed_frac=v.canal_speed_frac}
        return plan(board,mock,frame.td) or plan(board,mock,Track.reverse_trackdir(frame.td))
      end
      local routes={depot_options(board,axis,v,nil)}
      for _,trace in pairs(routes) do
        local frame=trace and trace[#trace]
        for _,next_ in ipairs({second,first}) do
          local approach=frame and from(frame,waypoint_order(via,next_))
          if not approach then return nil,"NO_CHANNEL_TO_BUOY" end
          local skip
          for _,step in ipairs(approach) do
            local x,z=board.xy(step.tile)
            local u,w=board.xy(via.tile)
            if math.abs(x-u)+math.abs(z-w)<=3 then skip=step;break end
          end
          local arrival=skip and from(skip,station_order(next_))
          if not arrival then return nil,"NO_CHANNEL_FROM_BUOY" end
          frame=arrival[#arrival]
        end
      end
      if not next(routes) then return nil,"NO_CHANNEL_TO_FIRST_DOCK" end
    elseif config.validate_both then
      local routes={left=left,right=right}
      -- Validate both legs from the physical arrival frame chosen by
      -- YAPF, using stock in-place reversal when the onward leg needs it.
      local function onward(trace,target)
        local last=trace and trace[#trace]
        if not last then return end
        local mock={tile=last.tile,owner=owner,order={kind="station",id=target}}
        return plan(board,mock,last.td,region) or plan(board,mock,Track.reverse_trackdir(last.td),region)
      end
      for _,trace in pairs(routes) do
        local outward=onward(trace,second)
        local reverse=onward(outward,first)
        if not reverse then return nil,"NO_RETURN_CHANNEL" end
      end
    end
    return {version=R.VERSION,owner=owner,depot=depot,first=first,second=second,vehicle=v,via=via,
      engine_id=engine_id,topology=s.topology,arrivals=0,steps=0,phase="depot",dwell=0}
  end
  -- Dispatch creates actual typed OrderList entries, even before the
  -- owner opens Orders. Stations and buoys remain separate ID domains.
  local function initial_orders(p)
    local a,b=station_order(p.first),station_order(p.second)
    if config.cargo_orders then a.cargo_order,b.cargo_order="full","no_load" end
    if not p.via then return {a,b} end
    local function buoy() return {kind="waypoint",id=p.via.id,tile=p.via.tile} end
    return {a,buoy(),b,buoy()}
  end
  function R.start(s,owner,depot,first,second,via_tile,engine_id)
    local p,why=R.quote(s,owner,depot,first,second,via_tile,engine_id)
    if not p then return nil,why end
    if paid_mode(s) and s.road_stock_house_supply and s.corner_grid then
      p.paid_clock=s[serial] or 1
      p.paid_built_day=s.day
      p.transport_orders,p.transport_order_cursor,p.transport_orders_revision=initial_orders(p),{real=0,implicit=0},0
      s[serial]=p.paid_clock+1
    end
    s[key]=p
    return p
  end
  function R.check_order(s,p,list)
    local board=lookup(s)
    if R.order_guard then
      local ok,reason=R.order_guard(s,p,list,board)
      if not ok then return false,reason end
    end
    local function origin(o)
      if o.kind=="waypoint" then return {o.tile} end
      return board.station_dock_tiles(o.id)
    end
    local function reachable(a,b)
      if a.kind==b.kind and a.id==b.id then return true end
      for _,tile in ipairs(origin(a)) do
        for _,td in ipairs(Water.trackdirs(Water.at(board,tile))) do
          local probe={tile=tile,owner=p.owner,order=b,
            ocean_speed_frac=p.vehicle.ocean_speed_frac,canal_speed_frac=p.vehicle.canal_speed_frac}
          if plan(board,probe,td) then return true end
        end
      end
    end
    -- This runtime must be able to draw every leg around the service
    -- loop. Unlike a Region estimate, the YAPF probe must reach the
    -- actual replacement dock/buoy before accepting it.
    local before,added,after=list[#list-1],list[#list],list[1]
    if not reachable(before,added) or not reachable(added,after) then
      return false,"No navigable route to or from the new order."
    end
    return true
  end
  function R.clear(s,owner)
    local p=R.current(s)
    if not p or p.owner~=owner then return nil,"NO_OWN_PILOT" end
    if p.owned then return nil,"OWNED_FERRY_CANNOT_BE_CLEARED" end
    s[key]=nil
    return true
  end
  local function tick(s,num,paid)
    local p=R.current(s)
    if not p or p.phase=="blocked" or (p.paid_clock~=nil)~=(paid~=nil) then return end
    local board,region=lookup(s)
    local v=p.vehicle
    if p.topology~=s.topology then
      if p.via and not p.transport_orders then
        local b=board.tile(p.via.tile)
        if not b or b.kind~="buoy" or b.station~=p.via.id then
          p.phase,p.failure="blocked","SELECT_BUOY"
          return p
        end
      end
      local route=v.path
      if route then
        for i=math.max(1,(v.path_index or 2)-1),#route-1 do
          local a,b=route[i],route[i+1]
          local f=Water.follow(board,v,a.tile,a.td)
          if not f.ok or f.tile~=b.tile or not Track.has(f.trackdirs,b.td) then
            p.phase,p.failure="blocked","NETWORK_CHANGED"
            return p
          end
        end
      end
      p.topology=s.topology
    end
    local hooks={
      station_has_dock=function(_,id) return s.stock_ship_stations[id]~=nil end,
      docking_area=function(B,berth,station)
        for _,tile in ipairs(B.station_dock_tiles(station)) do if tile==berth then return true end end
        return false
      end,
      max_speed=function(B,b)
        local ratio=Water.water_class(B.tile(b.tile))=="sea" and b.ocean_speed_frac or b.canal_speed_frac
        return math.floor(b.max_speed*(256-ratio)/256)
      end,
      on_waypoint=function(B,b,o)
        local target
        if p.transport_orders then
          local order,cursor=O.next_manual(p.transport_orders,p.transport_order_cursor)
          p.transport_order_cursor=cursor
          target=order and order.kind=="station" and order.id or nil
        else
          target=o.next_station
        end
        local via=p.via
        if not (via and via.id==o.id and via.tile==o.tile) then return end
        if not p.transport_orders then p.pending_buoy_dock=target end
        local x,z=B.xy(b.tile)
        local u,w=B.xy(o.tile)
        via.passes=via.passes+1
        p.last_buoy_pass={tile=b.tile,order_tile=o.tile,distance=math.abs(x-u)+math.abs(z-w),
          tick=b.tick,speed=b.speed,progress=b.progress,steps=p.steps,next_dock=target}
      end,
    }
    local function current_order(advance)
      local list,c=p.transport_orders,p.transport_order_cursor
      if advance and list[c.implicit+1].kind=="station" and list[c.implicit+1].id==v.last_station then
        O.increment_implicit(list,c)
      end
      O.update_real(list,c)
      return list[c.real+1]
    end
    local function leave(skipped)
      if p.transport_orders then
        Motion.leave(v,current_order(not skipped))
        p.phase="sailing"
        return
      end
      local next_=v.last_station==p.first and p.second or p.first
      Motion.leave(v,p.via and waypoint_order(p.via,next_) or station_order(next_))
      p.phase="sailing"
    end
    for _=1,num or 1 do
      if p.dock_forced_leave then
        if not v.loading then
          p.dock_forced_leave=nil
        elseif not paid or paid.leave(p,true) then
          local skipped=p.transport_skip_loading==true
          p.dock_forced_leave,p.transport_skip_loading,p.transport_cancel_full=nil,nil,nil
          p.dwell=0
          leave(skipped)
        else
          break -- do not depart with an unsettled load ledger
        end
      end
      if p.transport_orders then
        p.pending_buoy_dock=nil
        if v.loading and p.transport_skip_loading and (not paid or paid.leave(p,true)) then
          p.transport_skip_loading,p.transport_cancel_full=nil,nil
          leave(true)
        end
        if p.stopped then break end
        if not v.loading and not v.leaving then
          local order=current_order(false)
          if not v.order or v.order.kind~=order.kind or v.order.id~=order.id then
            v.order=order
            v.path,v.path_index=nil,nil
          end
        end
      elseif p.stopped then break end
      if p.pending_buoy_dock then
        v.order=station_order(p.pending_buoy_dock)
        p.pending_buoy_dock=nil
      end
      if paid then
        if v.loading and paid.leave(p) then
          p.transport_cancel_full=nil
          leave()
        end
      elseif p.dwell>0 then
        p.dwell=p.dwell-1
        if p.dwell==0 then
          leave()
        end
      end
      if v.track==Motion.DEPOT then
        local depot=board.tile(v.tile)
        local left,right=depot_options(board,depot.axis,v,region)
        hooks.reverse_depot=function() return not left and right~=nil end
        if Motion.depart_depot(board,v,hooks)=="depot_depart" then
          local td=Motion.trackdir(v)
          local trace=plan(board,v,td,region)
          if not trace or not Motion.set_path(v,trace) then
            p.phase,p.failure="blocked","NO_CHANNEL_FROM_DEPOT";break
          end
          p.phase="sailing"
        end
      elseif v.track~=Motion.WORMHOLE and not v.loading and (not v.path or v.path_index>#v.path) and not v.leaving and
          v.direction==v.rotation and
          not (v.order and v.order.kind=="station" and Water.ship_destination(board,v.tile,v.order.id)
            and hooks.docking_area(board,v.tile,v.order.id)) then
        -- Reaching the station tile ends YAPF's path, not the movement.
        -- Source ShipController moves to the next in-tile pixel and loads
        -- before taking the LEAVESTATION reversal at a dead-end berth.
        local forward=Motion.trackdir(v)
        local trace=plan(board,v,forward,region)
        if trace then
          Motion.set_path(v,trace)
        else
          local back=forward and Track.reverse_trackdir(forward)
          if plan(board,v,back,region) then Motion.reverse(v,back)
          else p.phase,p.failure="blocked","NO_CHANNEL_TO_DOCK";break end
        end
      end
      local event,steps=Motion.tick(board,v,hooks)
      p.steps=p.steps+steps
      if event=="dock" then
        p.phase,p.dwell,p.arrivals="moored",paid and 0 or 44,p.arrivals+1
        p.last_berth,p.last_dock=v.tile,v.last_station
        if R.news_arrival then R.news_arrival("ship",p.owner,p.last_dock,v.tile) end
        if paid then
          local ok,why=paid.arrive(p)
          if not ok then p.phase,p.failure="blocked",why or "MISSING_PAID_STATION";break end
        end
      elseif event:match("^bad_") or event=="blocked" then p.phase,p.failure="blocked",event;break end
    end
    return p
  end
  -- View-side timing must never move a paid vessel. This explicit
  -- controller entry is owned solely by the world's shared stock tick.
  function R.tick(s,num) return tick(s,num,nil) end
  function R.advance_paid(s,callbacks) return tick(s,1,callbacks) end
  function R.pose(p)
    if not p or p.vehicle.hidden then return end
    local x,z,y,d=Motion.visual(p.vehicle)
    return {x=x/8-.5,y=y/8+.5,z=z/8-.5},(d-3)*math.pi/4
  end
  return R
end
