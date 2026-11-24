-- Native board adapter for the stock ordinary-road one-way command.
-- No UI, rendering, live clock mutation or route replacement is performed.
return function(Sim,Terrain,Follow,OneWay,settings)
  settings=settings or {}
  local W={}
  local town_owner={} -- stock OWNER_TOWN is not genuinely unowned pavement
  local tickets=setmetatable({},{__mode="k"})
  local function copy(t)
    local q={}
    for k,v in pairs(t) do q[k]=v end
    return q
  end
  local function tile(s,id) return id~=nil and s.tiles[id] or nil end
  local function normal(t)
    return t and t.build=="road" and not t.level_crossing and not t.road_waypoint_id and not t.road_bridge_id and not t.road_tunnel_id
  end
  local function straight(bits) return bits==5 or bits==10 end
  local function is_active(s)
    return s.road_economy and s.corner_grid and s.road_stock_clock
  end
  local function is_road(v)
    local engine=Sim.vehicles[v.engine]
    return engine and engine.mode=="road"
  end
  function W.read(t)
    if not normal(t) then return 0 end
    local d=t.road_disallowed
    if d==nil then d=t.disallowed end
    return d or 0
  end
  local function valid_drd(d) return type(d)=="number" and d>=0 and d<=3 and d==math.floor(d) end
  local function below_or_above(s,f)
    if not f then return false end
    if f[13] or f[14] then return true end
    if f[10] then
      local span=s.stock_road_bridges and s.stock_road_bridges[f[10]]
      return f[12] or span and span.middle_by_tile and span.middle_by_tile[f[4]]
    end
    return f[12] or false
  end

  -- Reuse one exact ground-occupancy snapshot per construction sweep;
  -- a long road drag must not walk the entire fleet once per tile.
  function W.ground_occupancy(s)
    local ground={}
    for _,v in pairs(s.fleet or {}) do
      if is_road(v) and not (Sim.road_hidden_depot and Sim.road_hidden_depot(v)) then
        local f=Sim.road_motion_frame and Sim.road_motion_frame(s,v)
        if f then
          if f[4] and not below_or_above(s,f) then ground[f[4]]=true end
        elseif v.route then
          if type(v.progress)=="number" then
            local id=Sim.position(s,v)
            if id then ground[id]=true end
          else
            -- Missing cursor data cannot establish that the tile is clear.
            for _,id in ipairs(v.route) do ground[id]=true end
          end
        end
      end
    end
    local tram=s.tram_pilot
    if tram and tram.phase~="depot" then
      local leg=tram.legs and tram.legs[tram.leg]
      local f=leg and leg.frames and leg.frames[tram.index]
      if f and f[4] and not below_or_above(s,f) then ground[f[4]]=true end
    end
    return ground
  end

  function W.occupied(s,id,ctx)
    if ctx and ctx.vehicles_at then
      local entries=ctx.vehicles_at(s,id)
      if type(entries)~="table" then return true end -- unknown ground state fails closed
      for _,entry in pairs(entries) do
        if type(entry)~="table" or (entry.tile~=nil and entry.tile~=id) then return true end
        if not (entry.hidden or entry.wormhole or entry.underground or entry.elevated) then return true end
      end
      return false
    end
    return (ctx and ctx.ground or W.ground_occupancy(s))[id]==true
  end

  local function snapshot(s,id)
    local t=tile(s,id)
    if not t then return end
    local x,z=Sim.xy(id)
    local slope=Terrain.tile(s.corner_grid,x,z)
    if slope==nil then return end
    local out={kind="obstructed",slope=slope,roadworks=t.roadworks}
    if Sim.rail_span_protected and Sim.rail_span_protected(s,id) then return out end
    local tram_only=t.build==nil and t.tram and t.tram.kind=="road"
    if normal(t) or tram_only then
      if t.site or t.stock_industry or t.ship or t.airfield or t.house or (t.tram and t.tram.kind~="road") then return out end
      local d=W.read(t)
      local bits=Sim.road_bits(s,id)
      if not valid_drd(d) or (d~=0 and not straight(bits)) then return out end
      out.kind,out.roadtype,out.road_bits,out.disallowed="road",t.roadtype or 0,bits,d
      out.owner=t.road_town and town_owner or t.owner
      out.tram_bits=t.tram and t.tram.tram_bits or t.tram_bits
    elseif not t.build and not (t.owner or t.station or t.site or t.house or t.stock_industry or
        t.source_house or t.level_crossing or t.rail_tracks or t.rail_span_id or t.tram or t.ship or t.airfield or
        t.stock_canal or t.water_class or t.tunnel_id or t.road_tunnel_id or t.road_bridge_id or t.terrain=="water") then
      -- Natural terrain has an exact source clearing charge. Other
      -- structures and occupied facilities remain outside this adapter.
      out.kind="clear"
    end
    return out
  end

  function W.board(s)
    local b={xy=Sim.xy}
    function b.tile(id) return snapshot(s,id) end
    function b.adjacent(id,d) return Sim.adjacent(id,4-d) end
    function b.connects(id,d)
      local around=b.adjacent(id,d)
      local t=tile(s,around)
      if not t or (t.roadtype or 0)~=0 then return false end
      -- Includes the outside bit of native portals and adjacent stations.
      -- Existing restrictions don't change the physical endpoint test.
      return Sim.road_edge(s,around,4-Follow.reverse_direction(d))
    end
    return b
  end

  local function proposed(s,p)
    local patches={}
    for _,e in ipairs(p.changes) do
      local t=copy(s.tiles[e.tile])
      if t.build~="road" or Sim.road_bits(s,e.tile)==0 then t.owner=p.owner end
      t.build,t.road_bits="road",e.road_bits
      t.disallowed=nil -- compatibility field; one canonical stored value
      t.road_disallowed=e.disallowed~=0 and e.disallowed or nil
      patches[e.tile]=t
    end
    return patches
  end
  local function geometry_check(s,p,patches)
    local test=copy(s)
    test.tiles=setmetatable(copy(patches),{__index=s.tiles})
    for _,e in ipairs(p.changes) do
      if e.added~=0 then
        local id=e.tile
        for d=1,4 do
          local j=Sim.adjacent(id,d)
          if j and Sim.road_edge(test,id,d) and Sim.road_edge(test,j,(d+1)%4+1)
              and not Sim.road_geometry_connected(test,id,d,j) then
            return false,"ROAD_EDGE_HEIGHT_MISMATCH",id
          end
        end
      end
    end
    return true
  end
  local function legacy_check(s,p)
    local added_gate={}
    for _,e in ipairs(p.changes) do
      local before=W.read(s.tiles[e.tile])
      if e.disallowed%2>before%2 or math.floor(e.disallowed/2)>math.floor(before/2) then
        added_gate[e.tile]=true
      end
    end
    if not next(added_gate) then return true end
    for _,v in pairs(s.fleet or {}) do
      if v.route and is_road(v) and not v.road_motion_frames then
        for _,id in ipairs(v.route) do
          if added_gate[id] then return false,"LEGACY_ROAD_ROUTE_IN_THE_WAY",id end
        end
      end
    end
    return true
  end

  local function compare(a,b)
    if a.cost~=b.cost or a.stopped_at~=b.stopped_at or a.successes~=b.successes or #a.changes~=#b.changes or #a.skipped~=#b.skipped then
      return false
    end
    for i,e in ipairs(a.changes) do
      local f=b.changes[i]
      for _,key in ipairs{"tile","road_bits","disallowed","owner","cost","added","foundation","road_tree_town"} do
        if e[key]~=f[key] then return false end
      end
    end
    for i,e in ipairs(a.skipped) do
      if e.tile~=b.skipped[i].tile or e.reason~=b.skipped[i].reason then return false end
    end
    return true
  end
  local function compute(s,owner,start,last,axis,q,ctx)
    if not is_active(s) then return nil,"ONEWAY_REQUIRES_STOCK_ROAD_CLOCK" end
    local company=s.companies and s.companies[owner]
    if not company then return nil,"COMPANY_REQUIRED" end
    if type(start)~="number" or type(last)~="number" or not tile(s,start) or not tile(s,last) then
      return nil,"PARAMETERS"
    end
    if q.tram then return nil,"UNSUPPORTED_ROADTYPE" end
    ctx=ctx or {ground=W.ground_occupancy(s)}
    local p,reason,id=OneWay.plan(W.board(s),start,last,axis,{
      start_half=q.start_half,end_half=q.end_half,ai=q.ai,toggle=q.toggle,company=owner,
      build_on_slopes=settings.build_on_slopes~=false, piece_cost=settings.piece_cost or Sim.road_piece_price,
      foundation_cost=settings.foundation_cost or Sim.road_foundation_price,
      clear=function(_,id)
        return settings.clear_cost or Sim.road_site_clear_cost(s.tiles[id],s.stock_farm_fields and s.stock_farm_fields[id])
      end,
      occupied=function(_,i) return W.occupied(s,i,ctx) end,
    })
    if not p then return nil,reason,id end
    p.owner,p.start,p.last,p.axis,p.topology=owner,start,last,axis,s.topology
    p.terrain_revision=s.corner_grid.revision
    p.affordable=company.cash>=p.cost
    local occupied=Sim.road_piece_occupancy(s)
    -- Host keeps town/competitor geometry protected even in the stock
    -- half-tile additions path where there is no sign-only ownership gate.
    for _,e in ipairs(p.changes) do
      local t=s.tiles[e.tile]
      if e.added~=0 and (t.road_town or t.owner and t.owner~=owner) then
        return nil,"OWNED_BY",e.tile
      end
      if e.added~=0 and t.tram and s.tram_pilot and occupied(e.tile,true) then
        return nil,"VEHICLE_IN_THE_WAY",e.tile
      end
      if e.added~=0 and not t.build and t.wood and not t.tram then
        e.road_tree_town=Sim.road_tree_authority().tree_town(s,e.tile)
      end
    end
    local patches=proposed(s,p)
    local ok,why,where=geometry_check(s,p,patches)
    if not ok then return nil,why,where end
    ok,why,where=legacy_check(s,p)
    if not ok then return nil,why,where end
    return p,patches
  end

  function W.quote(s,owner,start,last,axis,opts,ctx)
    opts=opts or {}
    local query={start_half=opts.start_half,end_half=opts.end_half,ai=opts.ai,tram=opts.tram,toggle=opts.toggle}
    local p,why,at=compute(s,owner,start,last,axis,query,ctx)
    if not p then return nil,why,at end
    -- Do not rely on client-visible totals or fields later. A real quote
    -- capability binds the command to this campaign and saved revisions.
    local public=copy(p)
    public.changes,public.skipped={},{}
    for i,e in ipairs(p.changes) do public.changes[i]=copy(e) end
    for i,e in ipairs(p.skipped) do public.skipped[i]=copy(e) end
    public.drag=copy(p.drag);public.drag.requests={}
    for i,e in ipairs(p.drag.requests) do public.drag.requests[i]=copy(e) end
    tickets[public]={s=s,p=p,query=query}
    return public
  end

  function W.commit(s,owner,quote,ctx)
    local token=tickets[quote]
    if not token or token.s~=s or token.p.owner~=owner or token.p.topology~=s.topology or
        token.p.terrain_revision~=(s.corner_grid and s.corner_grid.revision) then
      return false,"STALE_ONEWAY_QUOTE"
    end
    local prev=token.p
    local p,patches,id=compute(s,owner,prev.start,prev.last,prev.axis,token.query,ctx)
    if not p then return false,patches,id end
    if not compare(prev,p) then return false,"STALE_ONEWAY_QUOTE" end
    if not p.affordable then return false,"NOT_ENOUGH_CASH" end
    tickets[quote]=nil
    local dirty={}
    for _,e in ipairs(p.changes) do
      local t,patch=s.tiles[e.tile],patches[e.tile]
      if e.road_tree_town then Sim.road_tree_authority().clear_road_trees(s.companies[owner],e.road_tree_town) end
      if t.build==nil and not t.tram and e.added~=0 then
        t.wood,t.stock_clear_ground,t.stock_clear_density=nil,nil,nil
        if s.stock_farm_fields then s.stock_farm_fields[e.tile]=nil end
      end
      t.build,t.road_bits,t.owner=patch.build,patch.road_bits,patch.owner
      t.disallowed,t.road_disallowed=patch.disallowed,patch.road_disallowed
      if s.road_oneway_removed and s.road_oneway_removed[e.tile]==true then s.road_oneway_removed[e.tile]=nil end
      dirty[#dirty+1]=e.tile
    end
    if #dirty>0 then
      local c=s.companies[owner]
      c.cash,c.expense,c.month_exp=c.cash-p.cost,(c.expense or 0)+p.cost,(c.month_exp or 0)+p.cost
      s.topology=(s.topology or 0)+1
      s.road_oneway_revision=(s.road_oneway_revision or 0)+1
    end
    return true,p.cost,dirty,p
  end

  function W.build(s,owner,start,last,axis,opts,ctx)
    local q,why,at=W.quote(s,owner,start,last,axis,opts,ctx)
    if not q then return false,why,at end
    return W.commit(s,owner,q,ctx)
  end

  function W.marking(s,id)
    local t=tile(s,id)
    if not normal(t) then return nil end
    local d=W.read(t)
    if not valid_drd(d) or d==0 then return nil end
    local bits=Sim.road_bits(s,id)
    local dir,kind=OneWay.arrow(bits,d)
    if not dir and not kind then return nil end
    local slope,base=Sim.road_surface(s,id)
    local x,z=Sim.xy(id)
    return {tile=id,dir=dir,kind=kind or "arrow",axis=bits==10 and 0 or 1,
      x=x,z=z,slope=slope,base=base,disallowed=d}
  end

  -- Wrap the real YAPF adapter after any crossing overlay. Do not cache
  -- directed masks across revisions, and never add restrictions to trams,
  -- level crossings, platforms or the road layer below a paired portal.
  function W.path_board(s,base)
    local b=copy(base)
    function b.tile(id)
      local record=base.tile(id)
      local raw=tile(s,id)
      if record and record.kind=="road" and normal(raw) then
        local d=W.read(raw)
        if not valid_drd(d) or (d~=0 and not straight(record.road_bits)) then d=3 end
        if (record.disallowed or 0)~=d then
          record=copy(record);record.disallowed=d
        end
      end
      return record
    end
    return b
  end

  local function blocked(s,f)
    if not f or not f[4] or below_or_above(s,f) then return false end
    local t=s.tiles[f[4]]
    if not normal(t) then return false end
    local d=W.read(t)
    if d==0 then return false end
    local td=f[6]
    if not valid_drd(d) or d==3 or (td~=0 and td~=1 and td~=8 and td~=9) then return true end
    local track=Follow.status({kind="road",roadtype=0,road_bits=Sim.road_bits(s,f[4]),disallowed=d},false)
    return not Follow.has_trackdir(track,td)
  end

  -- Invoke after proposing the actual next movement frame, before changing
  -- speed/heading/index or occupancy. Reject attempts to reverse on a
  -- signed tile (TD 6/7/14/15), illegally enter one or replay a now-invalid
  -- saved frame. Return false without mutating the route: park at the same
  -- physical frame/index, retry after edits or replace only with an exact
  -- current-frame route. A tram is explicitly outside this road guard.
  function W.guard(s,previous,wanted,ctx)
    if ctx and ctx.tram then return true end
    if blocked(s,previous) then return false,"ONEWAY_CURRENT_POSE_BLOCKED",previous[4] end
    if blocked(s,wanted) then
      local t=tile(s,wanted[4])
      if W.read(t)==3 then return false,"ROAD_NO_ENTRY",wanted[4] end
      return false,"WRONG_ONE_WAY_DIRECTION",wanted[4]
    end
    return true
  end

  function W.removal_blocks(s,f)
    if not f or not f[4] or below_or_above(s,f) then return false end
    local id=f[4]
    if not (s.road_oneway_removed and s.road_oneway_removed[id]) then return false end
    local t=s.tiles[id]
    if not normal(t) then
      return not (t and (t.build=="road_station" or t.build=="road_depot" or t.level_crossing))
    end
    local td=f[6]
    -- Normal pavement only has TD 0..5, 8..13. The turnaround rows
    -- require the straight approach on the same axis, as in the stock
    -- follower. Other facility rows aren't valid on a repaved tile.
    if td==6 or td==7 or td==14 or td==15 then td=(td-6)%2 end
    if type(td)~="number" or td<0 or td>13 then return true end
    local bits=Follow.status({kind="road",roadtype=t.roadtype or 0,road_bits=Sim.road_bits(s,id)},false)
    return not Follow.has_trackdir(bits,td)
  end

  -- Optional route selection when the prior physical pose is on ordinary
  -- pavement. No arbitrary teleport or direction change. The caller owns
  -- compilation from origin_frame[15] and must demand equality of the
  -- first motion pose before replacing the frozen old cursor. Without a
  -- safe trail the live guard simply waits before the sign.
  function W.reroute(s,v,current,base,Search,Cost,vehicle)
    if not current or not current[15] or below_or_above(s,current) or not normal(tile(s,current[4])) or
        (v.road_speed_state and v.road_speed_state.lane_pose) then return nil,"NO_REROUTE_ORIGIN" end
    local target=v.dest and s.stations[v.dest]
    if not target or target.mode~="road" or target.owner~=v.owner then return nil,"NO_ROAD_DESTINATION" end
    if not vehicle or not vehicle.display_max_speed then return nil,"NO_ROAD_ENGINE_SPEED" end
    local b=W.path_board(s,base)
    local td=current[6]
    if type(td)~="number" or td<0 or td>15 or not Follow.has_trackdir(Follow.status(b.tile(current[4]),false),td) then
      return nil,"NO_LEGAL_ORIGIN_TRACK"
    end
    local engine=copy(vehicle)
    engine.tile,engine.owner,engine.bus=current[4],v.owner,v.cargo=="passenger"
    local dest=Cost.destination(b,engine,{kind="station",station=v.dest})
    local found,best=Search.find(b,engine,current[4],2^td,dest)
    if not found then return nil,"NO_LEGAL_ROAD_ROUTE" end
    local trace=Search.trace(b,engine,dest,best)
    if not trace or not trace[1] or trace[1].tile~=current[4] or trace[1].td~=td then return nil,"NO_CONTINUOUS_ROAD_ROUTE" end
    return {trace=trace,origin_frame=copy(current),last_td=best.last_td,cost=best.cost,station=v.dest}
  end

  return W
end
