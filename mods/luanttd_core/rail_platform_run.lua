-- Persisted one-locomotive Trackworks pilot. Source YAPF owns routing,
-- rail_motion owns raw steps, rail_station_speed owns original acceleration
-- and stopping. No cargo, wagons, signalling, PBS, or return leg.
return function(Sim,Track,Motion,Speed,Lab,stock_height)
  local R={VERSION=1}
  -- OpenTTD 14.1 table/engines.h _orig_rail_vehicle_info index 1.
  -- Native model is original presentation art, not a stock sprite.
  R.engine={stock_id=1,name="MJS 250",visual="diesel",power=600,weight=65,
    max_track_speed=80,length=8,acceleration_type=0}
  -- train_cmd.cpp _vehicle_initial_*_fract in depot facing order.
  local spawn_x,spawn_y={[0]=10,8,4,8},{[0]=8,4,8,10}
  local min,max=math.min,math.max
  local function height(id,pose)
    return stock_height and stock_height(id,pose.x%16,pose.y%16) or 0
  end
  local function side_progress(direction,x,y)
    local d=math.floor(direction/2)
    if d==Track.NE then return 15-x end
    if d==Track.SE then return y end
    if d==Track.SW then return x end
    return 15-y
  end
  local function valid_tile(board,owner,id,td)
    local tile=board.tile(id)
    if not tile or tile.owner~=owner or tile.railtype~=0 or
        (tile.kind~="rail" and tile.kind~="station" and tile.kind~="depot") or
        (not stock_height and (tile.slope or 0)~=0) then return nil end
    if not Track.valid_trackdir(td) or not Track.has(Track.status(tile),td) then return nil end
    return tile
  end
  local function validate(board,run)
    local last,route=run.route[#run.route],run.route
    if #route<2 or not last then return false end
    local target=board.tile(last.tile)
    if not target or target.kind~="station" or target.station~=run.station then return false end
    for i=max(1,run.index),#route do
      local r=route[i]
      local tile=valid_tile(board,run.owner,r.tile,r.td)
      if not tile or (i==1 and (tile.kind~="depot" or tile.dir~=Track.exit_side(r.td))) or
          (i>1 and tile.kind=="depot") then return false end
      if i<#route then
        local next_=route[i+1]
        local exit=Track.exit_side(r.td)
        if board.adjacent(r.tile,exit)~=next_.tile or
            not Track.valid_trackdir(next_.td) or exit~=Track.reverse_side(Track.entry_side(next_.td)) then return false end
      end
    end
    return true
  end

  function R.current(s)
    local run=s.stock_rail_run
    if run and run.version==R.VERSION then return run end
  end

  function R.start(s,owner,depot_id,station_id)
    if s.stock_rail_run then return false,"Clear the existing pilot locomotive before starting another." end
    local board=Lab.board(s)
    local depot=board.tile(depot_id)
    if not depot or depot.kind~="depot" or depot.owner~=owner then
      return false,"Choose one of your Trackworks depots."
    end
    local td=Track.diagonal_trackdir(depot.dir)
    local route,cost=Lab.service_route(s,owner,{tile=depot_id,td=td},station_id)
    if not route then return false,"No stock route from this depot to that platform." end
    local tx,ty=Sim.xy(depot_id)
    local xf,yf=spawn_x[depot.dir],spawn_y[depot.dir]
    local direction=depot.dir*2+1
    local pose={x=16*tx+xf,y=16*ty+yf,tx=tx,ty=ty,td=td,direction=direction}
    local run={
      version=R.VERSION,owner=owner,depot=depot_id,station=station_id,
      engine=R.engine.stock_id,visual=R.engine.visual,route=route,route_cost=cost,
      topology=s.topology,index=1,tile_step=side_progress(direction,xf,yf),
      pose=pose,direction=direction,speed=0,subspeed=0,progress=0,
      max_track_speed=R.engine.max_track_speed,
      acceleration=Speed.acceleration(R.engine.power,R.engine.weight),
      total_length=R.engine.length,front_length=R.engine.length,
      order={kind="station",station=station_id,nonstop=1,stop_location=Speed.FAR},
      phase="depot",wait_counter=0,simulation_ticks=0,stock_steps=0,
    }
    if not validate(board,run) then
      return false,stock_height and "The pilot route needs ordinary, connected owned track and one destination platform."
        or "This pilot needs a flat route. It does not run on grades without the stock height sampler."
    end
    run.z=height(depot_id,pose)
    s.stock_rail_run=run
    return true,"Pilot locomotive ordered from depot to platform.",run
  end

  function R.clear(s,owner)
    local run=R.current(s)
    if not run or run.owner~=owner then return false,"No pilot locomotive belonging to your company." end
    s.stock_rail_run=nil
    return true,"Pilot locomotive cleared."
  end

  local function block(run,reason)
    run.phase="blocked";run.failure=reason;run.speed=0;run.progress=0
    return {kind="blocked",reason=reason,tick=run.simulation_ticks}
  end

  local function pass(board,run)
    if run.phase=="depot" then
      -- CheckTrainStayInDepot waits 37 TrainLocoHandler calls before
      -- revealing the fresh locomotive. The pilot precondition is an
      -- exclusive empty block; it does not synthesize a PBS reservation.
      run.wait_counter=run.wait_counter+1
      if run.wait_counter<37 then return end
      run.wait_counter=0;run.phase="running";run.speed=0
    end
    local event
    Speed.move_pass(run,function()
      local old=run.pose
      local next_=run.route[run.index+1]
      local tag,pose=Motion.step(old,next_ and next_.td)
      if tag=="invalid" or tag=="boundary" then
        event=block(run,"Route ended without reaching the ordered platform stop.")
        return
      end
      local index=run.index+(tag=="enter" and 1 or 0)
      local record=run.route[index]
      if not record or Sim.id(pose.tx,pose.ty)~=record.tile or pose.td~=record.td then
        event=block(run,"Track no longer matches the planned motion path.")
        return
      end
      local stop=Speed.station_step(board,record.tile,pose,run,old.direction)
      run.stock_steps=run.stock_steps+1
      run.index=index;run.pose=pose;run.direction=pose.direction
      run.tile_step=tag=="enter" and 0 or run.tile_step+1
      -- VehicleEnter_Station already applied the approach cap when a
      -- changed heading incurs TrainController's original turn fraction.
      Speed.after_turn(run,old.direction,pose.direction,R.engine.acceleration_type)
      if stop=="arrived" then
        Speed.begin_loading(run,run.station)
        run.phase="arrived"
        run.arrival={kind="arrived",station=run.station,tile=record.tile,
          pose={x=pose.x,y=pose.y,td=pose.td,direction=pose.direction},
          tick=run.simulation_ticks,steps=run.stock_steps}
        event=run.arrival
      end
      local z=height(record.tile,pose)
      Speed.after_grade(run,run.z,z);run.z=z
      if stop=="arrived" then run.speed=0 end
    end)
    if event and event.kind=="blocked" then run.progress=0 end
    return event
  end

  -- ticks are stock Train::Tick calls, not display frames. Returns the
  -- transition event once; persists the final arrival to show after reload.
  function R.tick(s,ticks)
    local run=R.current(s)
    if not run or run.phase=="arrived" or run.phase=="blocked" then return end
    local board=Lab.board(s)
    if run.topology~=s.topology then
      if not validate(board,run) then return block(run,"Track or destination was changed.") end
      run.topology=s.topology
    end
    for _=1,ticks or 1 do
      run.simulation_ticks=run.simulation_ticks+1
      -- Train::Tick has two TrainLocoHandler calls. Once at the ordered
      -- stop there is no second speed update or motion during loading.
      for _=1,2 do
        local event=pass(board,run)
        if event then return event end
      end
    end
  end

  -- Model follows rail_pose.sample(td,f) while stock raw position, speed
  -- and station logic remain separate. Fraction is the committed discrete
  -- step within this directed piece, not a wall-clock interpolation.
  function R.sample(run)
    if not run or run.phase=="depot" or run.phase=="blocked" then return end
    local record=run.route[run.index]
    local span=Track.track(record.td)<2 and 16 or 8
    return record.tile,record.td,min(run.tile_step/span,1)
  end

  return R
end
