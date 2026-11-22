-- Opt-in, ordinary stock-rail dispatch. Two one-way depot/platform orders
-- or one alternating-platform shuttle, never both together. Each consist
-- has one locomotive and one empty carriage; unique routes, PBS or an
-- explicitly separate opt-in conventional block pilot.
-- The source ports own kinematics, path search, track claims and aspects.
return function(Track,Follow,Costs,Search,PBS,Life,Signal,ConsistMotion,Dispatch,Speed,Lab,stock_height,Reverse,Spans,Crossings,Roster,Block)
  local R={VERSION=1,SHUTTLE_DWELL_TICKS=74,engine={id=1,power=600,weight=65,speed=80,visual="diesel"},
    wagon={id=27,weight=25,length=8}}
  local settings={forbid_90=false}
  local path_backoff=20 -- pathfinding_settings.ini, path_backoff_interval.
  local floor,min,max=math.floor,math.min,math.max
  local has=Track.has
  -- Each stock engine needs its own art. An installation with missing
  -- files freezes its restored work rather than rolling invisibly or
  -- using some other engine's model.
  local model_ready={[0]=true}
  local bridge_collectors_ready
  function R.mount_bridge_collectors(ready) bridge_collectors_ready=ready end
  function R.mount_owned_model(id)
    if id==8 or id==9 or id==10 or id==11 or id==15 or Roster and Roster.electric_engine(id) then
      model_ready[id]=true
      return true
    end
    return false
  end
  function R.owned_passenger_engine(id) return model_ready[id]==true end

  function R.current(s)
    local d=s.stock_rail_dispatch
    if d and d.version==R.VERSION then return d end
  end
  local function state(s,owner)
    local d=R.current(s)
    if d then return d end
    if s.stock_rail_dispatch then return nil end
    return {version=R.VERSION,owner=owner,runs={},signals=Signal.new(),life=Life.new(),ticks=0,topology=s.topology}
  end
  local function rail_board(s,span_mode)
    local b=Lab.board(s)
    if Crossings then b=Crossings.rail_board(s,b) end
    return Spans and Spans.board(s,b,span_mode) or b
  end
  local function portal(t) return t and (t.kind=="bridge" or t.kind=="tunnel") and t.transport=="rail" end
  local function signed(base,d) return Signal.view(base,d.signals) end
  local function viewed(base,d) return Life.view(signed(base,d),d.life) end

  local function physical_train_tracks(d,id)
    local bits
    for _,run in ipairs(d.runs) do
      for _,part in ipairs(run.consist.parts) do
        if part.tile==id then
          bits=bits or {}
          bits[#bits+1]=part.wormhole and Block.WORMHOLE or
            part.hidden and Block.DEPOT or Track.trackbit(Track.track(part.pose.td))
        end
      end
    end
    return bits
  end

  local function block_occupancy(d) return function(id) return physical_train_tracks(d,id) end end

  -- Modes never share a dispatch save while the other policy's signal
  -- heads are present. The detached stock solver supports mixed boundaries,
  -- but this two-consist pilot does not run stock mixed admission/mode changes.
  local function compatible_signals(base,d,is_block)
    local board=signed(base,d)
    for id in pairs(d.signals.records) do
      local tile=board.tile(id)
      if is_block and not (tile and tile.kind=="signals") then return false end
      for td=0,13 do
        if Track.valid_trackdir(td) and Signal.along(tile,td) then
          local kind=Signal.signal_type(tile,td)
          if is_block and kind~=Signal.BLOCK or not is_block and not Signal.pbs(kind) then return false end
        end
      end
    end
    return true
  end

  local function refresh_blocks(base,d)
    local entries={}
    local board=signed(base,d)
    for id in pairs(d.signals.records) do
      local tile=board.tile(id)
      for track=0,5 do
        if Signal.on_track(tile,track) and Signal.signal_type(tile,track)==Signal.BLOCK then
          entries[#entries+1]={tile=id,track=track}
        end
      end
    end
    table.sort(entries,function(a,b) return a.tile<b.tile or a.tile==b.tile and a.track<b.track end)
    return Block.update_buffer(base,d.signals,d.owner,block_occupancy(d),entries)
  end

  function R.board(s)
    local d=R.current(s)
    local base=rail_board(s,d and d.runs[1] and d.runs[1].span)
    return d and (d.runs[1] and d.runs[1].block and signed(base,d) or viewed(base,d)) or base
  end
  function R.signal(s,tile,td)
    if not Track.valid_trackdir(td) then return end
    return Signal.aspect(R.board(s).tile(tile),td)
  end
  function R.place_signal(s,owner,id,td,kind)
    if Lab.span_protected and Lab.span_protected(s,id) then return false,"That tile is part of a protected rail span." end
    local is_block=kind==Signal.BLOCK
    if is_block and not (Block and s.rail_block_preview) then
      return false,"Enable the conventional block signals preview first."
    end
    if not Track.valid_trackdir(td) or (kind~=nil and not is_block and not Signal.pbs(kind)) then
      return false,"Choose a track and signal direction."
    end
    local d=state(s,owner)
    if not d or d.owner~=owner or #d.runs>0 or s.stock_rail_run then
      return false,"Clear the active pilot before changing dispatch signals."
    end
    local base=Lab.board(s)
    local name=is_block and "Block signal" or "Path signal"
    if not compatible_signals(base,d,is_block) then
      return false,"Remove the other dispatch signal type before placing this signal."
    end
    local ok,why=Signal.place(base,d.signals,owner,id,Track.track(td),
      {kind=kind or Signal.PBS,copy_mask=Track.signal_along(td)},0,false)
    if not ok then return false,name..": "..why end
    if is_block then Block.update_track(base,d.signals,owner,block_occupancy(d),id,Track.track(td)) end
    s.stock_rail_dispatch=d
    return true,name.." placed."
  end

  local ordinary_traction={[0]=true,[1]=true}
  -- A route with competing reachable pieces is safe only for a
  -- controller that verifies its stock YAPF path before PBS writes.
  local function follows_plan(run,entry,td)
    return entry.trackdirs==2^td or (run.paired or run.branch_pbs) and has(entry.trackdirs,td)
  end
  local function vehicle(run,tile)
    return {tile=tile,owner=run.owner,railtype=run.engine_railtype or 0,compatible=run.traction_railtypes or ordinary_traction,
      max_speed=run.max_track_speed,length=run.total_length}
  end
  local function next_tracks(board,tile,td)
    local dir=Track.exit_side(td)
    local old=board.tile(tile)
    if board.span_enabled and portal(old) and old.dir==dir then
      local here=board.tile(old.other)
      if portal(here) and here.other==tile and here.kind==old.kind and has(Track.status(here),td) then
        return old.other,dir,{trackdirs=2^td,tracks=2^Track.track(td),red_tracks=0},true
      end
      return nil,dir,{trackdirs=0,tracks=0,red_tracks=0}
    end
    local id=board.adjacent(tile,dir)
    local new=id and board.tile(id)
    if not new then return id,dir,{trackdirs=0,tracks=0,red_tracks=0} end
    local forbid=Follow.disallow_90(board,old.railtype,new.railtype,settings.forbid_90)
    return id,dir,Signal.capture_entry(new,dir,td,forbid)
  end
  local function dense_route(board,v,best,allow_spans)
    local dense={}
    for _,x in ipairs(Search.trace(board,v,best,settings)) do
      local f=x.follow
      if f and f.station and f.skip>0 then
        local id=f.station_entry
        for _=1,f.skip do
          dense[#dense+1]={tile=id,td=x.td}
          id=board.adjacent(id,f.exit)
        end
        if id~=x.tile then return end
      elseif f and f.skip>0 and not (allow_spans and (f.bridge or f.tunnel)) then return end
      dense[#dense+1]={tile=x.tile,td=x.td}
    end
    return dense
  end
  local function search(board,run,tile,td)
    local v=vehicle(run,tile)
    local box,sign=board.station_area(run.order.station,run.order.kind)
    if not box and sign==nil then return end
    local dest=Costs.destination(board,v,run.order)
    local found,best=Search.find(board,v,{tile=tile,td=td},dest,settings)
    if found then return best,v end
  end

  -- Validated run scope: same-axis flat corridors with no turns/merges,
  -- conventional forward-only heads, and every X/Y diamond between its
  -- own incoming and outgoing heads, never at an adjoining facility.
  -- This lets the actual stock block controller interlock each crossing.
  local function block_route(board,run,d)
    local ran_signal,last_cross=false,nil
    local td=run.route[1].td
    if not Track.valid_trackdir(td) or Track.track(td)>Track.Y then return false end
    local single=Track.trackbit(Track.track(td))
    local pieces={}
    for i,r in ipairs(run.route) do
      local tile=board.tile(r.tile)
      if r.td~=td or not tile or (tile.slope or 0)~=0 then return false end
      if tile.kind=="signals" then
        if tile.trackbits~=single or Signal.signal_type(tile,td)~=Signal.BLOCK or
            not Signal.along(tile,td) or Signal.along(tile,Track.reverse_trackdir(td)) then return false end
        ran_signal,last_cross=true,nil
      elseif tile.kind=="rail" and tile.trackbits==3 then
        if not ran_signal then return false end
        last_cross=i
      elseif not (tile.trackbits==single and (tile.kind=="rail" or tile.kind=="depot" or tile.kind=="station")) then
        return false
      end
      pieces[r.tile]=r.td
    end
    if not ran_signal or last_cross then return false end
    for _,other in ipairs(d.runs) do
      if other~=run then
        for _,r in ipairs(other.route) do
          if pieces[r.tile] and (Track.track(pieces[r.tile])==Track.track(r.td) or
              board.tile(r.tile).kind~="rail" or board.tile(r.tile).trackbits~=3) then return false end
        end
      end
    end
    return true
  end

  local function unsafe_platform(board,last)
    local x,z=board.xy(last.tile)
    return ("Platform (%d,%d) has no safe exit. Add a forward Path Signal just beyond it, or end the track there."):format(x,z)
  end

  local function validate(board,run,allow_platform_origin)
    local function where(id)
      local x,z=board.xy(id)
      return ("(%d,%d)"):format(x,z)
    end
    local route=run.route
    local seen={}
    local span_jumps=0
    if #route<2 then return false,"The destination needs a different connected platform." end
    for i,r in ipairs(route) do
      local tile=board.tile(r.tile)
      if tile and tile.owner==run.owner and not (run.traction_railtypes or ordinary_traction)[tile.railtype] then
        return false,"The locomotive does not have power on rail at "..where(r.tile).."."
      end
      if not tile or tile.owner~=run.owner or
          (not (stock_height or run.span) and (tile.slope or 0)~=0) or
          not has(Track.status(tile),r.td) or seen[r.tile] then return false,"Unsupported or disconnected railway at "..where(r.tile).."." end
      seen[r.tile]=true
      if tile.kind=="depot" then
        if i~=1 or tile.dir~=Track.exit_side(r.td) then return false end
      elseif tile.kind=="signals" then
        if Signal.oneway_blocking(tile,r.td) or
            (not run.block and Signal.on_track(tile,Track.track(r.td)) and
              not Signal.pbs(Signal.signal_type(tile,r.td))) then return false,"Check the type and facing of the signal at "..where(r.tile).."." end
      elseif portal(tile) then
        if not run.span or not board.span_enabled or not board.stock_height then return false end
      elseif tile.kind~="rail" and tile.kind~="station" and tile.kind~="waypoint" and tile.kind~="crossing" then return false end
      if i<#route then
        local id,dir,entry,jump=next_tracks(board,r.tile,r.td)
        if jump then span_jumps=span_jumps+1 end
        local n=route[i+1]
        local route_track=follows_plan(run,entry,n.td)
        if id==n.tile and not route_track and has(entry.trackdirs,n.td) then
          return false,"This shuttle cannot choose between multiple tracks at "..where(n.tile)..". Use a single route into that junction."
        end
        if id~=n.tile or not route_track or Track.entry_side(n.td)~=Track.reverse_side(dir) then
          return false,"The planned railway does not connect at "..where(n.tile).."."
        end
        if run.span and not jump and board.span_seam and not board.span_seam(r.tile,r.td,n.tile,n.td) then return false end
      elseif tile.kind~="station" or tile.station~=run.station then return false,"The route does not reach the selected platform."
      elseif not run.platform_lookahead and not Costs.safe_waiting(board,vehicle(run,r.tile),r.tile,r.td,true,settings) then
        return false,unsafe_platform(board,r)
      end
    end
    if run.span and not run.shuttle and not run.fleet_id and span_jumps==0 then return false end
    local origin=board.tile(route[1].tile)
    return origin.kind=="depot" or allow_platform_origin and origin.kind=="station" and origin.station~=run.station
  end

  local function station_order(station)
    return {kind="station",station=station,nonstop=1,stop_location=Speed.FAR}
  end

  local function waypoint_order(wp)
    return {kind="waypoint",station=wp.id,nonstop=1}
  end

  -- Stock CheckReverseTrain compares the order from the actual front and
  -- reversed rear. Build the chosen leg before altering any live poses.
  local function choose_leg(board,run,consist,station)
    local final=station_order(station)
    local order=run.via and waypoint_order(run.via) or final
    local reverse_settings={forbid_90=settings.forbid_90,max_speed=run.max_track_speed}
    local flip=not run.paired and Reverse.check_order(board,consist,order,Costs,Search,reverse_settings)
    local origin=consist.parts[flip and #consist.parts or 1]
    local td=flip and Track.reverse_trackdir(origin.pose.td) or origin.pose.td
    local view={owner=run.owner,station=station,order=order,total_length=run.total_length,
      max_track_speed=run.max_track_speed,span=run.span,shuttle=true,fleet_id=run.fleet_id,paired=run.paired,
      branch_pbs=run.branch_pbs,platform_lookahead=run.platform_lookahead,
      engine_railtype=run.engine_railtype,traction_railtypes=run.traction_railtypes}
    local best,v=search(board,view,origin.tile,td)
    view.route=best and dense_route(board,v,best,run.span)
    if not view.route then return nil,nil,nil,run.via and "No connected track to the ordered waypoint." or
      "No connected route to the next platform in either direction." end
    if run.via then
      local last=view.route[#view.route]
      if last.tile~=run.via.tile then return nil,nil,nil,"The chosen waypoint no longer exists on that route." end
      view.order=final
      local onward,v2=search(board,view,last.tile,last.td)
      local suffix=onward and dense_route(board,v2,onward,run.span)
      if not suffix or #suffix<2 or suffix[1].tile~=last.tile or suffix[1].td~=last.td then
        return nil,nil,nil,"No forward route from the ordered waypoint to the next platform."
      end
      for i=2,#suffix do view.route[#view.route+1]=suffix[i] end
    end
    local ok,reason=validate(board,view,true)
    if not ok then return nil,nil,nil,reason end
    return view.route,order,flip
  end

  local function departure_probe(run,route)
    -- With the pilot's two stock 8-unit units and a FAR stop, the
    -- locomotive stops 4 subunits short of the final end and the
    -- carriage is 8 behind it, on that same final 16-unit tile.
    local r=route[#route]
    local pose={td=r.td,direction=Track.heading(r.td)}
    return {owner=run.owner,engine_railtype=run.engine_railtype,traction_railtypes=run.traction_railtypes,
      parts={{tile=r.tile,pose=pose,length=run.front_length},
      {tile=r.tile,pose=pose,length=run.total_length-run.front_length}}}
  end

  local function same_step(a,b)
    return a and b and a.tile==b.tile and a.td==b.td
  end

  local function matches_plan(confirmed,planned,index)
    if not confirmed or #confirmed<2 then return false end
    for i,track in ipairs(confirmed) do
      if not same_step(planned[index+i-1],track) then return false end
    end
    return true
  end

  -- One forward continuation on the approved next leg. A real order is
  -- still required at the platform, and neither the train nor its active
  -- order is advanced to inspect the following leg. To bound the stock
  -- ChooseTrainTrack loop in this controller, a second unsafe order end,
  -- repeated tile, span, or reversal before the stop point is unsupported.
  local function continuation_prefix(board,run,current,next_)
    local last=current[#current]
    if not next_ or not same_step(last,next_[1]) then return end
    local seen={}
    for _,step in ipairs(current) do seen[step.tile]=true end
    local v=vehicle(run,last.tile)
    for i=2,#next_ do
      local step=next_[i]
      local tile=board.tile(step.tile)
      if not tile or seen[step.tile] or tile.owner~=run.owner or portal(tile) or tile.kind=="depot" or
          not v.compatible[tile.railtype] then return end
      seen[step.tile]=true
      if Costs.safe_waiting(board,v,step.tile,step.td,true,settings) then return i end
    end
  end

  local function safe_leg_end(board,run,route)
    local stop=route[#route]
    return Costs.safe_waiting(board,vehicle(run,stop.tile),stop.tile,stop.td,true,settings)
  end

  local function validate_continuation(board,run,current,following)
    if safe_leg_end(board,run,current) or continuation_prefix(board,run,current,following) then return true end
    return false,unsafe_platform(board,current[#current])
  end

  local function start(s,owner,depot,station,second,span_mode,owned,freight,pair,is_block,cargo,via_tile)
    local freight_mode=cargo or "coal"
    local mode_enabled=freight and s["rail_"..freight_mode.."_service"] or not freight and s.rail_paid_service
    if owned and not (s.rail_owned_service and mode_enabled and Roster) then
      return false,"Enable owned rail and the shared paid rail clock first."
    end
    if second and s.rail_paid_service and not (s.road_stock_house_supply and s.corner_grid) then
      return false,"Paid rail needs the stock house clock and corner terrain."
    end
    local d=state(s,owner)
    if s.stock_rail_run then return false,"Clear the exclusive platform pilot first." end
    if not d or d.owner~=owner then return false,"Another company owns this dispatch pilot." end
    if d.failure then return false,"Clear the stopped dispatch pilot first." end
    if d.runs[1] and (not not d.runs[1].block)~=(not not is_block) then
      return false,"Clear the active pilot before changing its signal system."
    end
    if not compatible_signals(Lab.board(s),d,is_block) then
      return false,"Remove the other dispatch signal type before starting this pilot."
    end
    if (span_mode and #d.runs~=0) or (d.runs[1] and d.runs[1].span) then
      return false,"Clear the dispatch pilot before changing span services."
    end
    if (not pair and ((second or freight) and #d.runs~=0 or
        d.runs[1] and (d.runs[1].shuttle or d.runs[1].freight or d.runs[1].paired))) or
        pair and d.runs[1] and not d.runs[1].paired then
      return false,"Clear the dispatch pilot before switching between one-way and shuttle routes."
    end
    if #d.runs>=2 then return false,"The dispatch pilot supports two consists." end
    for _,other in ipairs(d.runs) do
      if (not pair and other.station==station) or other.depot==depot then
        return false,"Choose a different depot and destination platform for each train."
      end
    end
    local base=rail_board(s,span_mode)
    -- Ignore dynamic occupancy/aspects for order validation, but preserve
    -- physical signal facings and all track restrictions.
    local board=signed(base,d)
    local dt=depot and board.tile(depot)
    if not dt or dt.owner~=owner or dt.kind~="depot" then return false,"Select an owned depot." end
    if not station then return false,"Select an owned destination platform." end
    local stats=owned and owned.stats
    local consist=ConsistMotion.seed_depot(board,depot,stats and stats.lengths or {8,R.wagon.length})
    if not consist then return false,"Cannot seed the stock consist in this depot." end
    local run={id=#d.runs+1,owner=owner,depot=depot,station=station,consist=consist,span=span_mode,block=is_block,
      branch_pbs=owned and second and not pair and not freight and not is_block and true or nil,
      visual=R.engine.visual,phase="depot",index=1,speed=0,subspeed=0,progress=0,
      direction=consist.parts[1].pose.direction,z=0,ticks=0,stock_steps=0,wait_counter=0,
      max_track_speed=R.engine.speed,front_length=8,total_length=8+R.wagon.length,
      acceleration=Speed.acceleration(R.engine.power,R.engine.weight+R.wagon.weight),
      order=station_order(station)}
    if pair then run.paired={first=station,second=second,arrivals=0,reversals=0} end
    if via_tile~=nil then
      local wp=Lab.waypoint_at(s,via_tile)
      if not (owned and second and not pair and not freight and wp and wp.owner==owner) then
        return false,"Choose one of your own pass-through rail waypoints."
      end
      run.via={id=wp.id,tile=wp.tile,passes=0}
    end
    if owned then
      run.fleet_id,run.stock_engine,run.stock_wagon=owned.id,owned.stock_ids[1],owned.stock_ids[2]
      run.visual=stats.parts[1].visual
      if stats.parts[1].railtype==1 then
        run.engine_railtype,run.traction_railtypes=1,stats.compatible
        if not run.traction_railtypes[dt.railtype] then return false,"The depot does not supply power to this locomotive." end
        consist.engine_railtype,consist.traction_railtypes=1,stats.compatible
      end
      run.max_track_speed,run.front_length,run.total_length=stats.max_track_speed,stats.front_length,stats.total_length
      run.acceleration,run.consist_mass,run.power=stats.acceleration,stats.weight,stats.power
      run.paid_build_year=owned.parts[1].build_year
      run.running_ticks_total,run.running_year_fp=0,stats.running_year_fp
      if freight then
        run.cargo_onboard,run.freight_multiplier=0,stats.freight_trains
      else
        run.passengers_onboard=0
        run.passenger_finance={charged_ticks=0,expense=0,fixed=0,legacy_ticks=0}
      end
    end
    -- The implemented departure probe models two 8-unit vehicles on a
    -- FAR stop; don't admit new routing behavior outside those real poses.
    if not run.via and run.branch_pbs and #consist.parts==2 and run.front_length==8 and run.total_length==16 then
      run.platform_lookahead=true
    end
    local query=board
    if is_block then
      -- Search the static one-way layout; a physically red signal is a
      -- wait during this one-way run, not an invalid order on a unique route.
      query={}
      for k,v in pairs(board) do query[k]=v end
      query.tile=function(id)
        local tile=board.tile(id)
        if tile and tile.kind=="signals" then tile.green_signals=tile.present_signals end
        return tile
      end
    end
    local best,v=search(query,run,depot,consist.parts[1].pose.td)
    local route=best and dense_route(query,v,best,span_mode)
    run.route=route
    if not route then return false,"No connected route from the depot to the first platform. Check the depot exit, rail joints and signal direction"..(run.engine_railtype==1 and ", and make sure the whole route is electrified." or ".") end
    local valid,reason=validate(board,run)
    if not valid then return false,reason or "This railway layout is not supported for the first platform." end
    if is_block and not block_route(board,run,d) then
      return false,"Use a flat straight corridor with forward block signals guarding both sides of every diamond."
    end
    if pair then
      run.paired.second_leg=choose_leg(board,run,departure_probe(run,route),second)
      if not run.paired.second_leg then
        return false,"The passenger pair needs a safe one-direction path from its loading platform to its terminal."
      end
    elseif second then
      local second_leg,_,_,second_reason=choose_leg(board,run,departure_probe(run,route),second)
      if not second_leg then return false,"Second platform: "..(second_reason or "No safe route.") end
      local repeat_leg,_,_,repeat_reason=choose_leg(board,run,departure_probe(run,second_leg),station)
      if not repeat_leg then return false,"Return to the first platform: "..(repeat_reason or "No safe route.") end
      if run.platform_lookahead then
        local forward=choose_leg(board,run,departure_probe(run,repeat_leg),second)
        for _,legs in ipairs({{route,second_leg},{second_leg,repeat_leg},{repeat_leg,forward}}) do
          local ok,why=validate_continuation(board,run,legs[1],legs[2])
          if not ok then return false,why end
        end
      end
      if run.engine_railtype==1 then
        local function crosses_bridge(leg)
          for _,step in ipairs(leg) do
            local piece=board.tile(step.tile)
            if piece and piece.kind=="bridge" and piece.transport=="rail" then return true end
          end
        end
        if crosses_bridge(route) or crosses_bridge(second_leg) or crosses_bridge(repeat_leg) then
          if not (bridge_collectors_ready and bridge_collectors_ready()) then
            return false,"The moving electric collector is not mounted for this bridge."
          end
          run.bridge_collectors=true
        end
      end
      run.shuttle={first=station,second=second,arrivals=0,reversals=0}
    elseif freight then
      local loaded=choose_leg(board,run,departure_probe(run,route),freight)
      if not loaded then return false,cargo=="goods" and "No safe rail route from the sawmill to the town platform." or
        cargo=="oil" and "No safe rail route from the wells to the refinery platform." or
        "No safe rail route from mine to accepting power platform." end
      local empty=choose_leg(board,run,departure_probe(run,loaded),station)
      if not empty then return false,cargo=="goods" and "No safe rail return from the town platform to the sawmill." or
        cargo=="oil" and "No safe rail return from the refinery platform to the wells." or
        "No safe rail return from the power platform to the mine." end
      run.freight={mine=station,power=freight,cargo=cargo,visits=0,reversals=0,cycles=0,repeat_route=true}
    end
    if not is_block then
      local ok,why=Dispatch.register(board,d.life,run.id,consist)
      if not ok then return false,"Cannot allocate the depot: "..why end
    end
    local get_height=span_mode and base.stock_height or stock_height
    if get_height then
      local p=consist.parts[1].pose
      run.z=get_height(depot,p.x%16,p.y%16)
    end
    if freight or second and s.rail_paid_service then
      run.paid_clock=s.next_paid_rail_run or 1
      run.paid_built_day=s.day
      s.next_paid_rail_run=run.paid_clock+1
    end
    d.runs[run.id]=run
    s.stock_rail_dispatch=d
    return true,pair and "Owned steam coach ordered to board, deliver and park." or
      freight and (cargo=="goods" and "Owned Goods train ordered to repeat: full load at the sawmill, unload in town." or cargo=="oil" and "Owned oil train ordered to repeat: full load at the wells, unload at the refinery." or
        "Owned coal train ordered to repeat: full load at the mine, unload at the power station.") or
      owned and ("Owned "..stats.parts[1].name..(run.via and " shuttle ordered via the selected waypoint." or
        " shuttle ordered to alternate between both platforms.")) or
      run.paid_clock and "Paid shuttle ordered to alternate between both platforms." or
      second and "Shuttle ordered to alternate between both platforms." or
      is_block and "Stock locomotive and carriage ordered under conventional block signals." or
      "Stock locomotive and carriage ordered to the platform.",run
  end

  function R.start(s,owner,depot,station)
    return start(s,owner,depot,station)
  end

  function R.start_block(s,owner,depot,station)
    if not (Block and s.rail_block_preview) then return false,"Enable the conventional block signals preview first." end
    return start(s,owner,depot,station,nil,nil,nil,nil,nil,true)
  end

  function R.start_span(s,owner,depot,station)
    if not Spans or not s.rail_span_enabled then return false,"Enable the rail spans preview first." end
    return start(s,owner,depot,station,nil,true)
  end

  function R.start_shuttle(s,owner,depot,first,second)
    if not Reverse then return false,"The stock reversal module is not loaded." end
    if not first or not second or first==second then return false,"Choose two different owned platforms." end
    local stations=s.stock_rail_stations or {}
    local function dedicated(st) return st and (st.coal_role or st.oil_role or st.goods_role) end
    if s.rail_paid_service and (dedicated(stations[first]) or dedicated(stations[second])) then
      return false,"Choose passenger platforms, not dedicated freight stages."
    end
    return start(s,owner,depot,first,second)
  end

  -- The depot adapter validates the receipt and stock identity. The
  -- paid platform engine controls the real coach, its load and readiness.
  function R.start_owned(s,owner,owned,first,second,via_tile)
    if not Reverse then return false,"The stock reversal module is not loaded." end
    if not first or not second or first==second then return false,"Choose two different owned platforms." end
    local ids=owned and owned.stock_ids
    local recipe=ids and (#ids==1 and ids[1]==11 or #ids==2 and ids[2]==27)
    if not owned or owned.owner~=owner or not Roster or not recipe or not R.owned_passenger_engine(ids[1]) then
      return false,"The paid shuttle requires a supported purchased passenger consist."
    end
    return start(s,owner,owned.depot,first,second,Spans and s.rail_span_enabled or false,owned,
      nil,nil,nil,nil,via_tile)
  end

  local function clone(t)
    if type(t)~="table" then return t end
    local copy={}
    for k,v in pairs(t) do copy[k]=clone(v) end
    return copy
  end

  function R.start_owned_pair(s,owner,a,b)
    if not (s.rail_owned_pair_enabled and s.rail_owned_service and s.rail_paid_service and Reverse and Roster) then
      return false,"Enable the paired owned passenger preview and the shared paid rail clock first."
    end
    local present=R.current(s)
    if present and #present.runs>0 then return false,"Paired steam cannot replace a live railway dispatch." end
    if (s.next_paid_rail_run or 1)>=0x3FFF then return false,"No paid railway slot available." end
    local function unit_valid(x)
      local u=x and x.unit
      return u and u.owner==owner and x.first and x.second and x.first~=x.second and
        #u.stock_ids==2 and u.stock_ids[1]~=11 and not Roster.electric_engine(u.stock_ids[1]) and
        R.owned_passenger_engine(u.stock_ids[1]) and u.stock_ids[2]==27
    end
    if not unit_valid(a) or not unit_valid(b) or a.unit.id==b.unit.id or a.second==b.second then
      return false,"Use two supported owned passenger consists, independent depots and distinct terminal platforms."
    end
    local draft={}
    for k,v in pairs(s) do draft[k]=v end
    draft.stock_rail_dispatch=clone(s.stock_rail_dispatch)
    local ok,why,r1=start(draft,owner,a.unit.depot,a.first,a.second,false,a.unit,nil,true)
    if not ok then return false,why end
    local ok2,note,r2=start(draft,owner,b.unit.depot,b.first,b.second,false,b.unit,nil,true)
    if not ok2 then return false,note end

    local route_tiles={}
    local geometry=rail_board(draft,false)
    local function visit(r,other)
      local shared=0
      for _,route in ipairs({r.route,r.paired.second_leg}) do
        for _,track in ipairs(route) do
          local old=route_tiles[track.tile]
          local final=geometry.tile(track.tile).station==r.paired.second
          if old then
            if final or old.final then return end
            if old.td==track.td then shared=shared+1
            elseif Track.entry_side(old.td)~=Track.entry_side(track.td) and
                Track.exit_side(old.td)~=Track.exit_side(track.td) then return end
          end
          if not other then route_tiles[track.tile]={td=track.td,final=final} end
        end
      end
      return shared
    end
    if not visit(r1,false) then return false,"The first paired route revisits track in incompatible directions." end
    local shared=visit(r2,true)
    if not shared or shared==0 then
      return false,"Use shared track in the same direction, with each terminal clear of the other train's route."
    end
    s.stock_rail_dispatch,s.next_paid_rail_run=draft.stock_rail_dispatch,draft.next_paid_rail_run
    return true,"Two purchased trains ordered to board, deliver and park.",{r1,r2}
  end

  function R.start_owned_coal(s,owner,owned,mine,power)
    if not (Reverse and Roster and s.rail_coal_service and s.road_stock_house_supply and s.corner_grid) then
      return false,"Enable the stock Rail Coal service first."
    end
    if not mine or not power or mine==power or not owned or owned.owner~=owner or
        not owned.stock_ids or #owned.stock_ids~=2 or owned.stock_ids[1]~=0 or owned.stock_ids[2]~=29 then
      return false,"Use one owned Kirby Paul Tank and exactly one Coal Truck wagon."
    end
    return start(s,owner,owned.depot,mine,nil,false,owned,power)
  end

  function R.start_owned_oil(s,owner,owned,wells,refinery)
    if not (Reverse and Roster and s.rail_oil_service and s.road_stock_house_supply and s.corner_grid) then
      return false,"Enable stock Rail Oil service in the Oil world first."
    end
    if not wells or not refinery or wells==refinery or not owned or owned.owner~=owner or
        not owned.stock_ids or #owned.stock_ids~=2 or owned.stock_ids[1]~=0 or owned.stock_ids[2]~=30 then
      return false,"Use one owned Kirby Paul Tank and exactly one Oil Tanker wagon."
    end
    return start(s,owner,owned.depot,wells,nil,false,owned,refinery,nil,nil,"oil")
  end

  function R.start_owned_goods(s,owner,owned,mill,town)
    if not (Reverse and Roster and s.rail_goods_service and s.road_stock_house_supply and s.corner_grid) then
      return false,"Enable stock Rail Goods service on the Timber chain first."
    end
    if not mill or not town or mill==town or not owned or owned.owner~=owner or
        not owned.stock_ids or #owned.stock_ids~=2 or owned.stock_ids[1]~=0 or owned.stock_ids[2]~=32 then
      return false,"Use one owned Kirby Paul Tank and exactly one Goods Van."
    end
    return start(s,owner,owned.depot,mill,nil,false,owned,town,nil,nil,"goods")
  end

  -- Explicitly stop at the next completed power order; never delete or
  -- teleport the owned train. Existing town/pilot stops are unchanged.
  function R.park_coal(s,owner,fleet_id,on)
    local d=R.current(s)
    local run=d and d.runs[1]
    if not run or not run.freight or (run.freight.cargo or "coal")~="coal" or run.owner~=owner or run.fleet_id~=fleet_id then
      return false,"Select your active owned coal train."
    end
    if type(on)~="boolean" or d.failure or run.freight.complete then
      return false,"The coal train is already parked or blocked."
    end
    run.freight.park_after_delivery=on or nil
    return true,on and "Coal train will park after its next power delivery." or "The coal train will keep repeating.",run
  end

  function R.toggle_owned(s,owner,fleet_id)
    local d=R.current(s)
    local run
    for _,p in ipairs(d and d.runs or {}) do if p.fleet_id==fleet_id then run=p;break end end
    if not run or run.owner~=owner or run.fleet_id~=fleet_id then return false,"Select an active owned rail fleet unit." end
    if d.failure then return false,"This owned train is blocked: "..d.failure end
    if run.freight and run.freight.complete then return false,"This freight delivery is complete; the train is parked." end
    if run.paired and run.paired.complete then return false,"This passenger order is complete; the train is parked." end
    run.stopped=not run.stopped
    return true,run.stopped and "Owned train stopping; orders and occupied track retained." or "Owned train resumed.",run
  end

  function R.clear(s,owner)
    local d=R.current(s)
    if not d or d.owner~=owner or #d.runs==0 then return false,"No dispatch consists to clear." end
    if d.runs[1].fleet_id then return false,"An owned train cannot be erased. Stop or resume it from the rail fleet." end
    local board=signed(Lab.board(s),d)
    for id in pairs(d.signals.records) do
      for td=0,13 do
        if Track.valid_trackdir(td) and Signal.pbs_along(board.tile(id),td) then
          Signal.set_aspect(board,d.signals,id,td,false)
        end
      end
    end
    local is_block=d.runs[1].block
    d.runs={};d.life=Life.new();d.failure=nil;d.topology=s.topology
    if is_block and Block then refresh_blocks(Lab.board(s),d) end
    if Crossings then Crossings.refresh(s,rail_board(s)) end
    return true,is_block and "Dispatch consists cleared; block signals retained." or
      "Dispatch consists cleared; path signals retained."
  end

  local function emit(d,run,events,kind,fields)
    local ev=fields or {}
    ev.kind=kind;ev.train=run.id;ev.tick=d.ticks
    events[#events+1]=ev
    return ev
  end
  local function halt(d,run,events,why)
    if d.failure then return end
    d.failure=why
    for _,r in ipairs(d.runs) do
      if r.phase~="arrived" or r.shuttle then r.phase="blocked";r.failure=why;r.speed=0;r.progress=0 end
    end
    emit(d,run,events,"blocked",{reason=why})
  end
  local function block_freight(s,why,cargo)
    local d=R.current(s)
    local run=d and d.runs[1]
    local events={}
    if run and run.freight and (run.freight.cargo or "coal")==cargo and not run.freight.complete and not d.failure then
      run.stopped=true
      halt(d,run,events,why)
    end
    return events
  end
  function R.block_coal(s,why) return block_freight(s,why,"coal") end
  function R.block_oil(s,why) return block_freight(s,why,"oil") end
  function R.block_goods(s,why) return block_freight(s,why,"goods") end
  local function hold(d,run,events,id,why)
    if run.phase~="waiting" then emit(d,run,events,"waiting",{tile=id,reason=why}) end
    run.phase="waiting"
  end

  -- OpenTTD 14.1 train_cmd.cpp ChooseTrainTrack: YAPF may first
  -- reserve up to the active station without reaching a safe waiting
  -- position. Then it temporarily looks ahead to the next real order;
  -- only if no destination was found does it try any safe track. A
  -- discovered target that cannot reserve rolls back, not reroutes.
  local function reserve(board,d,run,tile,td)
    local paths=Life.view(board,d.life)
    local best,v=search(paths,run,tile,td)
    if best and (run.paired or run.branch_pbs) and
        not matches_plan(dense_route(paths,v,best,run.span),run.route,run.index) then return false end
    local target=best and PBS.choose_target(board,d.life.bits,v,best,settings)
    if not target then return false end
    if PBS.safe_end(board,d.life.bits,v,target.tile,target.td,true,settings) then
      return Life.reserve_path(board,d.life,run.id,target,settings)
    end
    local other,planned,safe_index
    if run.order.kind=="waypoint" and run.via and target.tile==run.via.tile then
      -- ChooseTrainTrack's NextOrder branch: the waypoint itself is not a
      -- required stop. Reserve to the first verified safe position on the
      -- following platform order, on the very same track continuation.
      other=run.station
      local prefix,index={},nil
      for i,step in ipairs(run.route) do
        prefix[i]=step
        if same_step(step,target) then index=i;break end
      end
      if not index then return false end
      planned={}
      for j=index,#run.route do planned[#planned+1]=run.route[j] end
      safe_index=continuation_prefix(board,run,prefix,planned)
    elseif run.platform_lookahead and run.shuttle and same_step(run.route[#run.route],target) then
      other=run.station==run.shuttle.first and run.shuttle.second or run.shuttle.first
      planned=choose_leg(board,run,departure_probe(run,run.route),other)
      safe_index=continuation_prefix(board,run,run.route,planned)
    end
    if not safe_index then return false end

    -- Stage both reservation levels together. Claims and bits are the only
    -- state Life.reserve_path may modify; retain the real moving consist
    -- and all pre-existing claims, even across a failed extension.
    local staged={version=d.life.version,trains=d.life.trains,bits=clone(d.life.bits),claims=clone(d.life.claims)}
    if not Life.reserve_path(board,staged,run.id,target,settings) then return false end
    local next_board=Life.view(board,staged)
    local future={owner=run.owner,station=other,order=station_order(other),
      max_track_speed=run.max_track_speed,total_length=run.total_length,
      engine_railtype=run.engine_railtype,traction_railtypes=run.traction_railtypes}
    local next_best,next_v=search(next_board,future,target.tile,target.td)
    local requested
    if next_best then
      if not matches_plan(dense_route(next_board,next_v,next_best,run.span),planned,1) then return false end
      requested=PBS.choose_target(board,staged.bits,next_v,next_best,settings)
    else
      next_v=vehicle(run,target.tile)
      local found,nearest=Search.find(next_board,next_v,{tile=target.tile,td=target.td},
        Costs.destination(next_board,next_v,{kind="safe"}),settings,{override_railtype=true})
      if not found or not matches_plan(dense_route(next_board,next_v,nearest,run.span),planned,1) then return false end
      requested=PBS.choose_target(board,staged.bits,next_v,nearest,settings)
    end
    if not same_step(planned[safe_index],requested) then return false end
    local ok,claims=Life.reserve_path(board,staged,run.id,requested,settings)
    if not ok then return false end
    -- A platform reservation writes all of its linked physical tiles.
    -- Verify actual claims, not only the YAPF vertices, against the prefix
    -- so no opportunistic branch, overrun, or incompatible fallback leaks.
    local allowed={}
    for i=2,safe_index do allowed[planned[i].tile]=Track.track(planned[i].td) end
    for _,claim in ipairs(claims) do if allowed[claim.tile]~=claim.track then return false end end
    d.life.bits,d.life.claims=staged.bits,staged.claims
    return true
  end

  local function acquire(base,d,run,id,dir,entry,next_td)
    local head=run.consist.parts[1]
    local board=signed(base,d)
    local track=Track.track(next_td)
    local current_claim=Life.claim_owner(d.life,id,track)
    if current_claim then return current_claim==run.id end
    local target=board.tile(id)
    if Signal.pbs_along(target,next_td) then
      local chosen,why=Signal.try_single_path_signal(base,d.signals,id,dir,entry.tracks,
        PBS.bits(board,d.life.bits,id),
        function(signal_view) return reserve(signal_view,d,run,head.tile,head.pose.td) end)
      return chosen==track and (why=="reserved" or why=="already_reserved") and
        Life.claim_owner(d.life,id,track)==run.id
    end
    return reserve(board,d,run,head.tile,head.pose.td) and Life.claim_owner(d.life,id,track)==run.id
  end
  local function look_ahead(base,d,run)
    local head=run.consist.parts[1]
    local next_=run.route[run.index+1]
    local board=signed(base,d)
    local t=board.tile(head.tile)
    if not next_ or t.kind=="station" and Speed.should_stop(run,t.station) then return end
    local id,dir,entry=next_tracks(board,head.tile,head.pose.td)
    if follows_plan(run,entry,next_.td) and Signal.pbs_along(board.tile(id),next_.td) and
        not Life.claim_owner(d.life,id,Track.track(next_.td)) then
      acquire(base,d,run,id,dir,entry,next_.td)
    end
  end
  local function mark_stuck(run)
    if not run.stuck then
      run.stuck=true;run.wait_counter=0;run.speed=0;run.subspeed=0
    end
  end

  local function switch_station_order(base,d,run,events,station,orders)
    if not Reverse then return halt(d,run,events,"The stock reversal module is not loaded.") end
    local route,order,flip
    if run.paired and station==run.paired.second then
      local head=run.consist.parts[1]
      local plan=run.paired.second_leg
      local candidate={owner=run.owner,station=station,order=station_order(station),route=plan,
        total_length=run.total_length,max_track_speed=run.max_track_speed,paired=run.paired}
      if head.tile==plan[1].tile and head.pose.td==plan[1].td and validate(signed(base,d),candidate,true) then
        route,order=plan,candidate.order
      end
    elseif run.platform_lookahead and not safe_leg_end(signed(base,d),run,run.route) then
      -- A verified forward reservation may already be held beyond this
      -- arrival. Dynamic costs (including our own holds) must not divert it.
      local board=signed(base,d)
      route,order,flip=choose_leg(board,run,run.consist,station)
      if flip or not continuation_prefix(board,run,run.route,route) then route=nil end
    else
      route,order,flip=choose_leg(viewed(base,d),run,run.consist,station)
    end
    if not route then return halt(d,run,events,"No supported route to the next ordered platform.") end
    local first=route[1]
    if flip then
      local reversal,why=Reverse.apply(base,run.consist,d.life,run.id,d.signals,{speed=run.speed,stuck=run.stuck})
      if not reversal then return halt(d,run,events,"Train reversal refused: "..why) end
      assert(reversal.origin.tile==first.tile and reversal.origin.td==first.td)
      orders.reversals=orders.reversals+1
      emit(d,run,events,"reversed",{tile=first.tile,td=first.td,station=station,cab_reversed=run.consist.reversed})
    end
    local head=run.consist.parts[1].pose
    run.direction=head.direction
    run.station=station;run.order=order;run.route=route;run.index=1
    run.speed=0;run.subspeed=0;run.progress=0;run.wait_counter=0;run.stuck=false
    run.slowing=false;run.phase="turnaround";orders.dwell_until=nil
    local height=run.span and base.stock_height or stock_height
    if height then run.z=height(first.tile,head.x%16,head.y%16) end
  end

  local function switch_shuttle_order(base,d,run,events)
    local q=run.shuttle
    return switch_station_order(base,d,run,events,run.station==q.first and q.second or q.first,q)
  end

  -- No call to the PBS lifecycle: stock path reservation is not the
  -- authority for crossing entry in this pure conventional mode. Keep
  -- the exact source front/tail signal update after each physical move.
  local function block_step(base,d,run,board,entry,choice)
    local move,why=ConsistMotion.plan(board,run.consist,choice,settings)
    if not move then return nil,why end
    local transitions=move.transitions
    -- Fixed eight-subunit separation on each straight sixteen-subunit tile
    -- means there is at most one boundary crossing in a movement pass.
    if #transitions>1 then return nil,"unsupported_block_consist_spacing" end
    local t=transitions[1]
    if t and t.front then
      local gate=Signal.entry_wait(board.tile(t.tile),entry,Track.track(t.td),run,
        {pbs_segment=false,reverse_at_signals=false,execute_reverse=false})
      if gate~="enter" then
        return nil,gate=="reverse" and "unsupported_reverse" or "red_block_signal",t
      end
    end
    local ok,reason=ConsistMotion.commit(run.consist,move)
    if not ok then return nil,reason end
    local events={}
    if t then
      local tile,dir,td,kind=t.tile,t.enterdir,t.td,"front_entered"
      if t.tail then tile,dir,td,kind=t.old_tile,Track.reverse_side(t.enterdir),t.old_td,"tail_left" end
      local needs_pbs,changes,overflow=Block.train_moved_change_signals(base,d.signals,block_occupancy(d),tile,dir)
      if needs_pbs or overflow then return nil,needs_pbs and "mixed_block_pbs" or "block_search_overflow" end
      events[1]={kind=kind,phase="after_position",tile=tile,enterdir=dir,td=td}
      for _,change in ipairs(changes) do
        change.kind="block_aspect";change.aspect=change.green and "green" or "red"
        events[#events+1]=change
      end
    end
    return {events=events,reveals=move.reveals}
  end

  local function pass(s,base,d,run,events,mode,paid)
    local head=run.consist.parts[1]
    if run.phase=="depot" then
      run.wait_counter=run.wait_counter+1
      if run.wait_counter<37 then return end
      run.wait_counter=0
      local next_=run.route[2]
      local id,dir,entry=next_tracks(signed(base,d),head.tile,head.pose.td)
      if id~=next_.tile then return end
      if run.block then
        local segment,_,overflow=Block.update_segment(base,d.signals,run.owner,block_occupancy(d),head.tile,Block.INVALID_SIDE)
        if overflow or segment==Block.PBS then halt(d,run,events,"Unsupported block at the depot mouth.");return end
        if segment==Block.FULL then return end
      elseif not acquire(base,d,run,id,dir,entry,next_.td) then return end
      assert(ConsistMotion.release_front(run.consist))
      if run.block then
        -- CheckTrainStayInDepot updates again with the now exposed engine.
        local _,_,overflow=Block.update_segment(base,d.signals,run.owner,block_occupancy(d),head.tile,Block.INVALID_SIDE)
        if overflow then halt(d,run,events,"Conventional block search overflow.");return end
      end
      run.phase="running";run.speed=0;run.stuck=false
      emit(d,run,events,"departed",{tile=head.tile})
    elseif run.phase=="turnaround" then
      local next_=run.route[2]
      local id,dir,entry=next_tracks(signed(base,d),head.tile,head.pose.td)
      if id~=next_.tile or not acquire(base,d,run,id,dir,entry,next_.td) then return end
      run.phase="running"
      emit(d,run,events,"shuttle_departed",{tile=head.tile,station=run.station,cab_reversed=run.consist.reversed or false})
    elseif run.stuck then
      if mode then return end
      run.wait_counter=run.wait_counter+1
      if run.wait_counter%path_backoff~=0 then return end
      local next_=run.route[run.index+1]
      local id,dir,entry=next_tracks(signed(base,d),head.tile,head.pose.td)
      if not next_ or id~=next_.tile or not acquire(base,d,run,id,dir,entry,next_.td) then return end
      run.stuck=false;run.wait_counter=0
    end
    local checked_approach=false
    if run.span then run.visible_bridge_speed=ConsistMotion.max_bridge_speed(base,run.consist) end
    Speed.move_pass(run,function()
      local old_parts=run.consist.parts
      local old,next_=old_parts[1],run.route[run.index+1]
      local board=signed(base,d)
      local id,dir,entry=next_tracks(board,old.tile,old.pose.td)
      if not checked_approach then
        checked_approach=true
        if next_ and has(entry.red_tracks,Track.track(next_.td)) then
          -- TrainCheckIfLineEnds reads red before the movement step.
          local front={x=old.pose.x,y=old.pose.y,direction=run.direction,
            front_length=run.front_length,speed=run.speed}
          Signal.approaching_end(front,true)
          run.speed=front.speed;run.slowing=front.slowing
        end
      end
      -- Cache red before track choice, exactly once per TrainController
      -- pixel. The PBS dispatch journal is read-only outside the consist:
      -- allocate a pending reservation between two atomic attempts, never
      -- inside its staged callback. Conventional mode runs no PBS journal.
      local withheld
      local function choose(_,into,travel,dirs)
        if next_ and id==into and into==next_.tile and travel==dir and has(dirs,next_.td) then return next_.td end
      end
      local function try_step()
        if run.block then return block_step(base,d,run,board,entry,choose) end
        return Dispatch.step(board,d.life,run.id,run.consist,choose,settings,function(_,_,t)
          local track=Track.track(t.td)
          if Life.claim_owner(d.life,t.tile,track)~=run.id then
            withheld=t
            return false,"unreserved"
          end
          local gate=Signal.entry_wait(board.tile(t.tile),entry,track,run,
            {pbs_segment=true,execute_reverse=false})
          if gate~="enter" then withheld=t;return false,gate=="reverse" and "unsupported_reverse" or "red_signal" end
          return true
        end,Crossings and function(transitions,commit)
          return Crossings.train_move(s,base,transitions,run.owner,commit)
        end)
      end
      local r,why,at=try_step()
      if why=="red_block_signal" then withheld=at end
      if why=="unreserved" and withheld then
        if acquire(base,d,run,id,dir,entry,withheld.td) then
          -- Updated aspects for lifecycle events, old red mask for entry.
          board=signed(base,d)
          withheld=nil
          r,why=try_step()
        else
          mark_stuck(run)
          why="pbs_path_blocked"
        end
      end
      if not r then
        if why=="ROAD_DRAINING" or why=="unobserved" then
          run.speed=0;run.subspeed=0
          hold(d,run,events,next_ and next_.tile or old.tile,why)
        elseif withheld and why~="unsupported_reverse" then
          hold(d,run,events,withheld.tile,why)
        else halt(d,run,events,why) end
        return "crashed" -- movement-loop interruption token, not an in-game crash.
      end
      local new=run.consist.parts[1]
      local entered=old.tile~=new.tile
      if entered then
        run.index=run.index+1;run.wait_counter=0
        if run.order.kind=="waypoint" and run.via and new.tile==run.via.tile and
            board.tile(new.tile).kind=="waypoint" and board.tile(new.tile).station==run.order.station then
          -- Stock CheckNextTrainTile processes OT_GOTO_WAYPOINT here;
          -- do not change speed/loading, stop, or release occupied claims.
          run.via.passes=run.via.passes+1
          run.order=station_order(run.station)
          emit(d,run,events,"waypoint_passed",{tile=new.tile,waypoint=run.via.id,station=run.station,speed=run.speed})
        end
      end
      if run.phase=="waiting" then
        run.phase="running"
        emit(d,run,events,"proceeded",{tile=new.tile})
      end
      for _,e in ipairs(r.events) do
        if not run.block then Signal.apply_consist_event(base,d.signals,e) end
        emit(d,run,events,e.kind,e)
      end
      if new.span_speed then run.speed=min(run.speed,new.span_speed) end
      local stop=Speed.station_step(board,new.tile,new.pose,run,old.pose.direction)
      run.stock_steps=run.stock_steps+1
      run.direction=new.pose.direction
      Speed.after_turn(run,old.pose.direction,new.pose.direction,0)
      if run.span then
        local z=new.z
        if not new.span_prepared then Speed.after_grade(run,run.z,z) end
        run.z=z
        for i,part in ipairs(run.consist.parts) do
          if i>1 and part.span_speed then run.speed=min(run.speed,part.span_speed) end
          if part.wormhole and part.hidden and not old_parts[i].hidden then
            emit(d,run,events,"tunnel_hidden",{tile=part.tile,index=i})
          elseif old_parts[i].wormhole and old_parts[i].hidden and not part.hidden then
            emit(d,run,events,"tunnel_revealed",{tile=part.tile,index=i})
          end
        end
      elseif stock_height then
        local z=stock_height(new.tile,new.pose.x%16,new.pose.y%16)
        Speed.after_grade(run,run.z,z);run.z=z
      end
      if stop=="arrived" then
        Speed.begin_loading(run,run.station)
        run.phase="arrived"
        run.arrival=emit(d,run,events,"arrived",{tile=new.tile,station=run.station,steps=run.stock_steps})
        if run.shuttle or run.freight or run.paired then
          -- Retain real PBS claims throughout each ordered loading dwell.
          run.phase="dwell"
          if run.freight then run.freight.visits=run.freight.visits+1
          else
            local orders=run.paired or run.shuttle
            orders.arrivals=orders.arrivals+1
          end
          if paid then
            local wagon=run.consist.parts[2]
            local dir=Track.exit_side(new.pose.td)
            local forward=Follow.platform(board,new.tile,dir)
            local backward=Follow.platform(board,new.tile,Track.reverse_side(dir))
            run.last_paid_platform=run.station
            run.arrival.cargo_tile=wagon and wagon.tile
            run.arrival.platform_tiles=forward+backward-1
            local cargo_tiles,visible
            if run.stock_engine==11 then
              cargo_tiles,visible={},true
              for i,part in ipairs(run.consist.parts) do
                cargo_tiles[i]=part.tile
                if part.hidden then visible=false end
              end
            end
            run.arrival.cargo_tiles=cargo_tiles
            if visible==false or not wagon or wagon.hidden or not paid.arrive(run,wagon.tile,forward+backward-1,cargo_tiles) then
              halt(d,run,events,"Paid cargo body or station controller was not available.")
            end
          elseif run.shuttle then
            run.shuttle.dwell_until=d.ticks+R.SHUTTLE_DWELL_TICKS
          end
        end
      elseif entered and not run.block then look_ahead(base,d,run) end
    end)
  end

  function R.current_paid(s,fleet_id)
    local d=R.current(s)
    for _,r in ipairs(d and d.runs or {}) do
      if r.paid_clock and (not fleet_id or r.fleet_id==fleet_id) then return r end
    end
  end

  function R.paid_passengers(s)
    local d=R.current(s)
    local out={}
    for _,r in ipairs(d and d.runs or {}) do if r.paid_clock and not r.freight then out[#out+1]=r end end
    return out
  end

  function R.paid_art_ready(s)
    for _,r in ipairs(R.paid_passengers(s)) do
      if r.fleet_id and not R.owned_passenger_engine(r.stock_engine) then return false end
      if r.bridge_collectors and not (bridge_collectors_ready and bridge_collectors_ready()) then return false end
    end
    return true
  end

  -- Same stock day charge and company fixed-point credit as the owned
  -- coal runtime. The host shares an economy-day boundary but does not
  -- yet expose the original global VehicleID day-tick stagger.
  function R.settle_passenger_running_day(s,fleet_id)
    local run=R.current_paid(s,fleet_id)
    if not (s.rail_paid_service and run and run.fleet_id and not run.freight and Roster and
        R.owned_passenger_engine(run.stock_engine)) then return end
    local total=run.running_ticks_total or 0
    local ledger=run.passenger_finance
    if not ledger then
      -- Old preview saves only kept the cumulative tick count, not the
      -- elapsed daily batches. Treat that history as already out of
      -- scope: charging it now would fabricate rounding and debt.
      ledger={charged_ticks=0,expense=0,fixed=0,legacy_ticks=total}
      run.passenger_finance=ledger
    end
    if ledger.last_day and s.day<=ledger.last_day then return end
    local pending=total-ledger.charged_ticks-ledger.legacy_ticks
    assert(pending>=0,"Owned passenger rail running-tick ledger went backwards")
    if pending==0 then ledger.last_day=s.day; return end
    local fixed=Roster.day_running_charge(run.running_year_fp,pending)
    local c=assert(s.companies[run.owner],"Missing owner for owned passenger rail ledger")
    local whole,remainder=Roster.debit_fraction(c.stock_money_fraction or 0,fixed)
    c.cash,c.expense,c.month_exp,c.stock_money_fraction=
      c.cash-whole,c.expense+whole,c.month_exp+whole,remainder
    ledger.charged_ticks,ledger.expense,ledger.fixed,ledger.last_day=
      ledger.charged_ticks+pending,ledger.expense+whole,ledger.fixed+fixed,s.day
    return whole,fixed,pending
  end

  local function stock_owned_tick(run,paid)
    if not (run.fleet_id and Roster) then return end
    run.running_ticks_total=Roster.running_tick(run.running_ticks_total or 0,run.stopped,run.speed)
    if not (paid and paid.cargo_count) then return end
    local n,a,b,coach=paid.cargo_count(run)
    local field=run.freight and "cargo_onboard" or "passengers_onboard"
    if run.stock_engine==11 then
      if a==nil or b==nil then return end
      if n~=run[field] or a~=run.front_passengers or b~=run.rear_passengers or coach~=run.coach_passengers then
        local p={{stock_id=11,cargo_count=a,rear_cargo_count=b}}
        if coach~=nil then p[2]={stock_id=27,cargo_count=coach} end
        local stats=assert(Roster.stats(p))
        run[field],run.front_passengers,run.rear_passengers,run.coach_passengers=n,a,b,coach
        run.consist_mass,run.acceleration=stats.weight,stats.acceleration
      end
    elseif n~=nil and n~=run[field] then
      local stats=assert(Roster.stats({run.stock_engine,{stock_id=run.stock_wagon,cargo_count=n}},
        {freight_trains=run.freight_multiplier}))
      run[field]=n
      run.consist_mass,run.acceleration=stats.weight,stats.acceleration
    end
  end

  local function tick(s,ticks,paid)
    local events,d={},R.current(s)
    if not d or #d.runs==0 or d.failure or
        (R.current_paid(s)~=nil)~=(paid~=nil) or paid and not R.paid_art_ready(s) then return events end
    local is_block=d.runs[1].block
    if is_block and not (Block and s.rail_block_preview) then return events end
    local base=rail_board(s,d.runs[1] and d.runs[1].span)
    if d.runs[1].span and not base.span_enabled then
      halt(d,d.runs[1],events,"The span runtime is not loaded.")
      return events
    end
    if d.topology~=s.topology then
      local board=signed(base,d)
      for _,run in ipairs(d.runs) do
        if not validate(board,run,(run.shuttle or run.freight or run.paired) and run.route[1].tile~=run.depot) or
            (is_block and (not block_route(board,run,d) or not compatible_signals(base,d,true))) or
            (not is_block and not Life.valid_state(board,d.life)) then
          halt(d,run,events,"The dispatch railway changed.")
          return events
        end
      end
      if is_block then
        local _,overflow=refresh_blocks(base,d)
        if overflow then halt(d,d.runs[1],events,"Conventional block search overflow.");return events end
      end
      d.topology=s.topology
    end
    for _=1,ticks or 1 do
      d.ticks=d.ticks+1
      -- Each vehicle's Train::Tick runs false then true before the next
      -- vehicle in stock pool order. Our two IDs are in creation order.
      for _,run in ipairs(d.runs) do
        stock_owned_tick(run,paid)
        if run.fleet_id and run.stopped and run.speed==0 then
          -- The real stock handler returns here. Do not leave a depot
          -- or station, move a stopped wagon, or discard path holdings.
        elseif run.phase=="dwell" then
          if run.paired then
            if paid and paid.leave(run) then
              if run.station==run.paired.first then
                switch_station_order(base,d,run,events,run.paired.second,run.paired)
              else
                run.paired.complete=true
                run.phase,run.stopped,run.speed="passenger_complete",true,0
                emit(d,run,events,"passenger_complete",{tile=run.consist.parts[1].tile,station=run.station})
              end
              if d.failure then return events end
            end
          elseif run.freight then
            if paid and paid.leave(run) then
              local q=run.freight
              if run.station==q.mine then
                switch_station_order(base,d,run,events,q.power,q)
              else
                q.cycles=(q.cycles or 0)+1
                if q.repeat_route and not q.park_after_delivery then
                  switch_station_order(base,d,run,events,q.mine,q)
                else
                  -- An old one-shot preview retains its original order.
                  -- Explicit repeat-lane park likewise preserves all real
                  -- positions and path claims at this accepting platform.
                  q.complete=true
                  run.phase,run.stopped,run.speed="freight_complete",true,0
                  emit(d,run,events,"freight_complete",{tile=run.consist.parts[1].tile,station=run.station,cycles=q.cycles})
                end
              end
              if d.failure then return events end
            end
          elseif paid and paid.leave(run) or not paid and d.ticks>=run.shuttle.dwell_until then
            switch_shuttle_order(base,d,run,events)
            if d.failure then return events end
          end
        elseif run.phase~="arrived" and run.phase~="freight_complete" and run.phase~="passenger_complete" then
          run.ticks=run.ticks+1
          pass(s,base,d,run,events,false,paid)
          if d.failure then return events end
          if run.phase~="arrived" and run.phase~="dwell" then pass(s,base,d,run,events,true,paid) end
          if d.failure then return events end
        end
      end
      if Crossings then Crossings.refresh(s,base) end
    end
    return events
  end

  -- The original view can still render paid trains, but only the shared
  -- stock world clock may advance them. One-way pilots remain non-paying.
  function R.tick(s,ticks) return tick(s,ticks,nil) end
  function R.advance_paid(s,callbacks) return tick(s,1,callbacks) end

  function R.sample(run,index)
    local part=run and run.consist.parts[index or 1]
    if not part or part.hidden then return end
    local p=part.pose
    local entry=Track.reverse_side(Track.entry_side(p.td))
    local f
    if Track.track(p.td)<2 then
      if entry==Track.NE then f=(15-p.x%16)/16
      elseif entry==Track.SE then f=(p.y%16)/16
      elseif entry==Track.SW then f=(p.x%16)/16
      else f=(15-p.y%16)/16 end
    else
      -- Stock subcoordinates change on both axes across a half curve.
      -- Measure from its directional entry (0/15 or center 7/8) along
      -- the actual tangent; there are eight committed pixel intervals.
      local ix,iy
      if entry==Track.NE then ix=15
      elseif entry==Track.SW then ix=0
      elseif entry==Track.SE then iy=0
      else iy=15 end
      f=(ix and math.abs(p.x%16-ix) or math.abs(p.y%16-iy))/8
    end
    return part.draw_tile or part.tile,p.td,min(1,max(0,f)),part.wormhole~=nil
  end
  return R
end
