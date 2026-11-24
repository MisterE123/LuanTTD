-- Bind the crossing adapter to discrete committed road and rail poses.
-- No rendered/interpolated positions enter the admission decision.
return function(Sim,World)
  local R={world=World}
  local function has_crossing(s)
    return next(s.level_crossing_tiles or {})~=nil
  end
  R.has_crossing=has_crossing
  local function touches(s,v)
    for _,id in ipairs(v.route or {}) do if World.protected(s,id) then return true end end
    return false
  end
  function R.context(s,rail,road_hash)
    return {rail_board=rail,vehicles_at=function(id)
      local a=World.dispatch_parts(s,id)
      for _,v in pairs(s.fleet) do
        local spec=Sim.vehicles[v.engine]
        if spec and spec.mode=="road" then
          local f=Sim.road_motion_frame(s,v)
          -- A migrated road route with no trustworthy continuous clock
          -- cannot be guessed from legacy tile-fraction progress.
          if not f and v.route and (not v.road_motion_frames or not v.road_speed_state and (v.progress or 1)>1)
              and touches(s,v) then return nil end
          if f and f[4]==id and not (f[12] or f[14]) then
            a[#a+1]={type="road",id=v.id,tile=id,x=f[1],y=f[2],direction=f[3]}
          end
        end
      end
      local tram=s.tram_pilot
      if tram and tram.phase~="depot" then
        local leg=tram.legs[tram.leg]
        local f=leg and leg.frames[tram.index]
        if f and f[4]==id then
          a[#a+1]={type="road",id=-1,tile=id,x=f[1],y=f[2],direction=f[3]}
        end
      end
      -- Before the first physical movement a new frame may live in the
      -- road loop's authoritative hash but not yet in saved fleet state.
      -- Merge it with saved stationary/stop records without duplicates.
      if road_hash then
        local present={}
        for _,v in ipairs(a) do if v.type=="road" then present[v.id]=true end end
        for _,v in ipairs(road_hash.vehicles_at(id)) do
          if not present[v.id] and not (v.frame[12] or v.frame[14]) then a[#a+1]=v end
        end
      end
      return a
    end}
  end
  function R.road_board(s,base)
    return has_crossing(s) and World.road_board(s,base) or base
  end
  function R.rail_board(s,base)
    return has_crossing(s) and World.rail_board(s,base) or base
  end
  function R.road_step(s,rail,hash,from,to,td,commit)
    if from==to or not (World.protected(s,from) or World.protected(s,to)) then return commit() end
    return World.road_step(s,R.context(s,rail,hash),from,to,td,false,commit)
  end
  function R.tram_step(s,rail,from,to,td,commit)
    if from==to or not (World.protected(s,from) or World.protected(s,to)) then return commit() end
    return World.road_step(s,R.context(s,rail),from,to,td,true,commit)
  end
  function R.train_move(s,rail,transitions,owner,commit)
    if not has_crossing(s) or #transitions==0 then return commit() end
    local sites={}
    for _,v in ipairs(transitions) do
      if World.protected(s,v.old_tile) or World.protected(s,v.tile) then
        sites[#sites+1]={from=v.old_tile,to=v.tile,td=v.td}
      end
    end
    if #sites==0 then return commit() end
    return World.train_batch(s,R.context(s,rail),sites,owner,commit)
  end
  function R.refresh(s,rail)
    if has_crossing(s) then return World.refresh_all(s,R.context(s,rail)) end
    return {}
  end
  function R.quote(s,owner,id,request,rail)
    if not (s.road_economy and s.road_stock_clock) then return nil,"NEEDS_STOCK_ROAD_CLOCK" end
    if s.stock_rail_run then return nil,"CLEAR_EXCLUSIVE_RAIL_PILOT" end
    for _,v in pairs(s.fleet) do
      if v.route and Sim.vehicles[v.engine].mode=="road" and not v.road_motion_frames then
        for _,i in ipairs(v.route) do if i==id then return nil,"ROAD_POSE_UNKNOWN" end end
      end
    end
    return World.quote(s,owner,id,request,R.context(s,rail))
  end
  function R.apply(s,p,rail)
    return World.apply(s,p,R.context(s,rail))
  end
  function R.commit(s,owner,p,rail)
    if not p then return false,"STALE_QUOTE" end
    local q,why=R.quote(s,owner,p.id,p.request,rail)
    if not q then return false,why end
    local ok,price,ids,record=World.commit(s,owner,p,R.context(s,rail))
    if ok then R.refresh(s,rail) end
    return ok,price,ids,record
  end
  return R
end
