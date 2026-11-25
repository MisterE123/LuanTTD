-- Native same-tile level crossing transaction and host-only admission.
-- The source kernel owns the command quote and stock bar/red predicates.
-- The adapter deliberately does not pretend local rendering is occupancy.
return function(Sim,Terrain,Crossing,Track)
  local W={VERSION=1}
  local function copy(t)
    local out={}
    for k,v in pairs(t or {}) do out[k]=v end
    return out
  end
  local function tile(s,id) return id~=nil and s.tiles[id] or nil end
  -- The base RC1 catalog permits crossings on all four stock rail
  -- gauges. Native media is mounted independently; don't accept a
  -- gauge before its rail geometry and continuity can be represented.
  local function admitted(s,gauge)
    return gauge==0 or s.stock_level_crossing_art and s.stock_level_crossing_art[gauge]==true
  end
  local function unsupported(gauge)
    return gauge==1 and "ELECTRIC_CROSSING_NOT_MOUNTED" or "GUIDEWAY_CROSSING_NOT_MOUNTED"
  end
  function W.record(s,id)
    local t=tile(s,id)
    return t and t.level_crossing
  end
  function W.protected(s,id) return W.record(s,id)~=nil end
  function W.foundation_quote(record,mask,base,opts)
    return Crossing.autoslope(record.top,mask,base,opts)
  end
  function W.reindex(s)
    local index={}
    for id,t in pairs(s.tiles) do if t.level_crossing then index[id]=true end end
    s.level_crossing_tiles=index
    return index
  end
  local function shape(s,id)
    if not s.corner_grid then return end
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function occupied_layer(s, id, t, plain_tram)
    local dispatch=s.stock_rail_dispatch
    return t.terrain=="water" or t.tunnel_id or t.road_tunnel_id or t.road_bridge_id or
      t.rail_span_id or t.rail_station_id or t.rail_waypoint_id or t.road_waypoint_id or t.rail_depot_dir or t.station or t.depot_dir or
      t.site or t.house or t.wood or t.tram and not plain_tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or
      t.signal or dispatch and dispatch.signals and dispatch.signals.records and dispatch.signals.records[id] or
      s.tunnel_below and s.tunnel_below[id] or s.bridge_above and s.bridge_above[id] or
      s.aqueduct_above and s.aqueduct_above[id] or s.rail_bridge_above and s.rail_bridge_above[id] or
      s.rail_tunnel_below and s.rail_tunnel_below[id]
  end
  local function reservation(s,id,axis,ctx,fallback)
    if ctx and ctx.reserved then
      local value=ctx.reserved(id,axis)
      if type(value)=="boolean" then return value end
      return nil
    end
    local life=s.stock_rail_dispatch and s.stock_rail_dispatch.life
    if life and life.bits then return Track.has(life.bits[id] or 0,axis) end
    return not not fallback
  end
  local function observe(ctx,id)
    if not (ctx and ctx.vehicles_at) then return nil end
    local a=ctx.vehicles_at(id)
    if type(a)~="table" then return nil end
    for _,v in ipairs(a) do
      if type(v)~="table" or v.tile~=id or (v.type~="road" and v.type~="train") then return nil end
    end
    return a
  end
  local function physical(v) return not v.wormhole and not v.hidden end
  function W.quote(s,owner,id,r,ctx)
    if not s.level_crossing_enabled then return nil,"LEVEL_CROSSING_DISABLED" end
    local t=tile(s,id)
    if not t or not r or (r.kind~="road" and r.kind~="rail" and r.kind~="tram") then return nil,"INVALID_PARAMETER" end
    local existing=t.level_crossing
    local company=s.companies and s.companies[owner]
    if not company then return nil,"OWNED_BY_ANOTHER" end
    if existing then
      if r.kind=="rail" or r.kind=="road" and existing.roadtype~=nil or r.kind=="tram" and existing.tramtype~=nil then
        return nil,"ALREADY_BUILT"
      end
      local vehicles=observe(ctx,id)
      if not vehicles then return nil,"OCCUPANCY_UNKNOWN" end
      local input=copy(existing)
      for _,part in ipairs(vehicles) do if physical(part) then input.occupied=true;break end end
      local reserved=reservation(s,id,existing.rail_axis,ctx,existing.reserved)
      if reserved==nil then return nil,"RESERVATION_UNKNOWN" end
      input.reserved=reserved
      local request=copy(r);request.owner=owner
      local plan,why=Crossing.quote(input,request,{cash=company.cash})
      if not plan then return nil,why end
      return {id=id,owner=owner,topology=s.topology,request=request,price=plan.cost,prior_build=t.build,
        prior_bits=existing.road_bits or 0,prior_tram_bits=existing.tram_bits or 0,crossing=plan}
    end
    local tram=r.kind=="rail" and t.tram and t.tram.kind=="road" and t.tram or nil
    if (t.owner or tram and tram.tram_owner)~=owner or t.road_town then return nil,"OWNED_BY_ANOTHER" end
    if occupied_layer(s,id,t,tram) then return nil,"PROTECTED_TILE" end
    local slope,base,top=shape(s,id)
    if slope==nil then return nil,"NEEDS_SHARED_CORNERS" end
    local present=observe(ctx,id)
    if not present then return nil,"OCCUPANCY_UNKNOWN" end
    local base_record={owner=owner,slope=slope,base=base,top=top}
    -- Construction's EnsureNoVehicleOnGround does not count wormhole/hidden parts.
    for _,v in ipairs(present) do if physical(v) then base_record.occupied=true;break end end
    local req=copy(r)
    req.owner=owner
    if r.kind=="rail" and (t.build=="road" or tram) and not t.rail_tracks then
      local gauge=r.railtype or 0
      if not admitted(s,gauge) then return nil,unsupported(gauge) end
      base_record.kind="road"
      -- Host bit order N/E/S/W already equals stock NW/SW/SE/NE.
      base_record.road_bits=Sim.road_bits(s,id)
      if base_record.road_bits==0 and not tram then return nil,"NO_ROAD_TRACK" end
      base_record.roadtype=base_record.road_bits>0 and (t.roadtype or 0) or nil
      if base_record.roadtype and base_record.roadtype~=0 then return nil,"HOST_ROADTYPE_UNSUPPORTED" end
      base_record.road_owner=base_record.roadtype~=nil and t.owner or nil
      if tram then
        base_record.tramtype,base_record.tram_bits,base_record.tram_owner=tram.tramtype,tram.tram_bits,tram.tram_owner
      end
      base_record.disallowed,base_record.roadworks=t.road_disallowed or t.disallowed,t.roadworks
    elseif (r.kind=="road" or r.kind=="tram") and t.build=="stock_rail" and t.rail_tracks then
      local wanted=r.kind=="tram" and 1 or 0
      if (r.roadtype or wanted)~=wanted then return nil,"HOST_ROADTYPE_UNSUPPORTED" end
      local gauge=t.rail_type or t.railtype or 0
      if not admitted(s,gauge) then return nil,unsupported(gauge) end
      if (r.disallowed or 0)~=0 then return nil,"CROSSING_ON_ONEWAY_ROAD" end
      base_record.kind="rail"
      base_record.trackbits,base_record.railtype=t.rail_tracks,gauge
      local axis=t.rail_tracks==1 and 0 or t.rail_tracks==2 and 1 or nil
      -- Only one straight axis can cross a road. In Lua false is not
      -- nil; passing it into the current reservation bits caused a crash
      -- as soon as dispatch state existed elsewhere in a fresh world.
      if axis==nil then return nil,"FALLBACK_CLEAR" end
      local b=reservation(s,id,axis,ctx,false)
      if b==nil then return nil,"RESERVATION_UNKNOWN" end
      base_record.reserved_bits=b and 2^axis or 0
    else return nil,"NEEDS_PLAIN_ROAD_OR_RAIL" end
    local out,err=Crossing.quote(base_record,req,{cash=company.cash})
    if not out then return nil,err end
    return {id=id,owner=owner,topology=s.topology,request=req,price=out.cost,
      prior_build=t.build,prior_bits=base_record.road_bits or base_record.trackbits,
      prior_tram_bits=base_record.tram_bits or 0,crossing=out}
  end
  -- RC1 RemoveRoad, RoadTileType::Crossing: the road's whole axis
  -- goes away even when the drag selects a single half. The separate
  -- rail claim lives in the dispatcher, not the road tile record.
  function W.surface_remove_quote(s,owner,id,wanted,ctx,tram,piece_price)
    local a=W.record(s,id)
    if not a or tram and a.tramtype==nil or not tram and a.roadtype==nil then
      return nil,tram and "NO_TRAM" or "NOT_PLAIN_ROAD"
    end
    local type_owner=tram and a.tram_owner or a.road_owner
    if type_owner~=owner then return nil,"OWNED_BY" end
    if a.road_axis~=0 and a.road_axis~=1 or a.rail_axis~=1-a.road_axis then return nil,"INVALID_PARAMETER" end
    local present=tram and a.tram_bits or a.road_bits
    for _,b in ipairs{1,2,4,8} do
      if math.floor(wanted/b)%2==1 and math.floor(present/b)%2==0 then return nil,"NO_ROAD_PIECES" end
    end
    local current=observe(ctx,id)
    if not current then return nil,"OCCUPANCY_UNKNOWN" end
    for _,v in ipairs(current) do if physical(v) then return nil,"VEHICLE_IN_THE_WAY" end end
    local life=s.stock_rail_dispatch and s.stock_rail_dispatch.life
    if a.reserved and not (life and life.bits) then return nil,"RESERVATION_UNKNOWN" end
    local remains=tram and a.roadtype~=nil or not tram and a.tramtype~=nil
    return {id=id,tool=tram and "tram_remove_crossing" or "remove_crossing",build=remains and "road" or "stock_rail",
      road_bits=tram and a.road_bits or 0,tram_bits=tram and 0 or a.tram_bits,
      rail_tracks=2^a.rail_axis,railtype=a.railtype,rail_owner=a.rail_owner,cost=2*piece_price}
  end
  function W.road_remove_quote(s,owner,id,wanted,ctx)
    return W.surface_remove_quote(s,owner,id,wanted,ctx,false,40)
  end
  function W.surface_remove_apply(s,edit)
    local id=edit.id
    local t=s.tiles[id]
    local record=assert(t.level_crossing)
    assert(edit.rail_tracks)
    if edit.build=="road" then
      if edit.tool=="tram_remove_crossing" then record.tramtype,record.tram_owner,record.tram_bits=nil,nil,0
      else record.roadtype,record.road_owner,record.road_bits=nil,nil,0 end
      t.owner,t.road_bits=record.road_owner or record.tram_owner,record.road_bits
    else
      t.build,t.owner,t.rail_tracks,t.rail_type=edit.build,edit.rail_owner,edit.rail_tracks,edit.railtype
      t.road_bits,t.roadtype,t.road_town,t.road_disallowed,t.disallowed,t.level_crossing=nil,nil,nil,nil,nil,nil
      t.roadside,t.stock_roadside_town=nil,nil
      s.level_crossing_tiles[id]=nil
    end
  end
  W.road_remove_apply=W.surface_remove_apply

  -- RC1 CmdRemoveSingleRail on a road crossing. Both other layers
  -- keep their full inherited road axis and independent owners.
  function W.rail_remove_quote(s,owner,id,ctx)
    local a=W.record(s,id)
    if not a then return nil,"NO_RAIL_ON_CROSSING" end
    if a.rail_owner~=owner then return nil,"OWNED_BY" end
    local occupied=observe(ctx,id)
    if not occupied then return nil,"OCCUPANCY_UNKNOWN" end
    for _,part in ipairs(occupied) do if physical(part) then return nil,"VEHICLE_IN_THE_WAY" end end
    local held=reservation(s,id,a.rail_axis,ctx,a.reserved)
    if held==nil then return nil,"RESERVATION_UNKNOWN" end
    if held then return nil,"WAIT_RAIL_RESERVATION" end
    return {id=id,cost=-70,rail_axis=a.rail_axis,roadtype=a.roadtype,road_bits=a.road_bits,road_owner=a.road_owner,
      tramtype=a.tramtype,tram_bits=a.tram_bits,tram_owner=a.tram_owner}
  end
  function W.rail_remove_apply(s,edit)
    local id=edit.id
    local t=s.tiles[id]
    assert(t.level_crossing)
    t.level_crossing,t.rail_tracks,t.rail_type=nil,nil,nil
    -- MakeRoadNormal initializes the cross-section as barren again.
    if s.stock_generated_profile then t.roadside,t.stock_roadside_town="barren",nil end
    t.build=edit.roadtype~=nil and "road" or nil
    t.road_bits=edit.roadtype~=nil and edit.road_bits or nil
    t.roadtype,t.owner=edit.roadtype,edit.road_owner
    if edit.tramtype~=nil then
      t.tram={kind="road",tramtype=edit.tramtype,tram_bits=edit.tram_bits,tram_owner=edit.tram_owner}
    end
    s.level_crossing_tiles[id]=nil
  end

  function W.revalidate(s,owner,p,ctx)
    if not p or p.owner~=owner or p.topology~=s.topology then return nil,"STALE_QUOTE" end
    local q,err=W.quote(s,owner,p.id,p.request,ctx)
    if not q then return nil,err end
    local a,b=q.crossing,p.crossing
    if not b or q.price~=p.price or q.prior_build~=p.prior_build or q.prior_bits~=p.prior_bits or q.prior_tram_bits~=p.prior_tram_bits or
        a.tramtype~=b.tramtype or a.roadtype~=b.roadtype or a.railtype~=b.railtype or
        a.rail_axis~=b.rail_axis or a.road_axis~=b.road_axis or a.slope~=b.slope or a.top~=b.top then
      return nil,"STALE_QUOTE"
    end
    return q
  end
  -- Internal application for a route-wide preflighted construction batch.
  -- The caller owns the single combined debit and topology invalidation.
  function W.apply(s,q,ctx)
    local a=q.crossing
    local index=s.level_crossing_tiles or W.reindex(s)
    local t=s.tiles[q.id]
    a.version,a.phase,a.barred=W.VERSION,"unobserved",true
    local d=s.stock_rail_dispatch
    if (ctx and ctx.reserved) or (d and d.life and d.life.bits) then a.reserved=nil end
    -- Do not leave a second owner or competing rail editing path: Rail
    -- board reads the canonical crossing while legacy road keeps its tool.
    t.build,t.owner,t.road_bits,t.rail_tracks="road",a.road_owner or a.tram_owner,a.road_bits,nil
    t.tram,t.rail_type,t.railtype=nil,nil,nil
    -- MakeRoadCrossing clears its roadside bits on first conversion.
    -- Adding the other road layer to an existing crossing preserves it.
    if s.stock_generated_profile and not t.level_crossing then
      t.roadside,t.stock_roadside_town="barren",nil
    end
    t.level_crossing=a
    index[q.id]=true
    return a
  end
  function W.commit(s,owner,p,ctx)
    local q,err=W.revalidate(s,owner,p,ctx)
    if not q then return false,err end
    local a=W.apply(s,q,ctx)
    local c=s.companies[owner]
    c.cash,c.expense,c.month_exp=c.cash-q.price,(c.expense or 0)+q.price,(c.month_exp or 0)+q.price
    s.topology=s.topology+1
    return true,q.price,{q.id},a
  end

  function W.board(s,rail)
    return {
      tile=function(id)
        if id~=nil then return W.record(s,id) or (rail and rail.tile(id)) end
      end,
      adjacent=function(id,d) return Sim.adjacent(id,4-d) end,
    }
  end

  -- Wrap the existing navigable boards; do not use the visual state as
  -- a path graph closure. Gate physical next frames, not route searches.
  function W.rail_board(s,base,ctx)
    local b=copy(base)
    b.tile=function(id)
      local t=W.record(s,id)
      if not t then if id~=nil then return base.tile(id) end;return end
      local out=Crossing.rail_view(t)
      out.trackbits=2^t.rail_axis
      local r=reservation(s,id,t.rail_axis,ctx,t.reserved)
      out.reserved,out.reserved_bits=r,r and out.trackbits or 0
      return out
    end
    local old=b.stock_height
    b.stock_height=function(id,x,y)
      local t=W.record(s,id)
      if t then return t.top*8 end
      if old then return old(id,x,y) end
    end
    return b
  end
  function W.road_board(s,base)
    local b=copy(base)
    b.tile=function(id)
      local t=W.record(s,id)
      if not t then if id~=nil then return base.tile(id) end;return end
      local out=Crossing.road_view(t)
      out.owner,out.disallowed,out.roadworks=t.road_owner,0,false
      return out
    end
    local old=b.center_z
    b.center_z=function(id)
      local t=W.record(s,id)
      if t then return t.top*8 end
      if old then return old(id) end
    end
    return b
  end

  local function probe(s,board,group,ctx)
    local by_id,rv,tv,inspect,reserved,road_at={},{},{},{},{},{}
    local function ask(id)
      if id==nil then return {} end
      if inspect[id]~=nil then return inspect[id] or nil end
      local data=observe(ctx,id)
      if not data then inspect[id]=false;return nil end
      local on={}
      for _,v in ipairs(data) do if physical(v) then on[#on+1]=v end end
      inspect[id]=on
      return on
    end
    for _,id in ipairs(group) do
      by_id[id]=true
      local t=board.tile(id)
      local people=ask(id)
      if not people then return nil end
      for _,v in ipairs(people) do
        local out=v.type=="train" and tv or rv
        out[#out+1]=v
        if v.type=="road" then road_at[id]=true end
      end
      local r=reservation(s,id,t.rail_axis,ctx,t.reserved)
      if r==nil then return nil end
      reserved[id]=r
      if not ask(board.adjacent(id,t.rail_axis)) or not ask(board.adjacent(id,t.rail_axis+2)) then return nil end
    end
    return {roads=rv,trains=tv,by_id=by_id,road_at=road_at,rule={
      vehicles_at=function(id) return id~=nil and inspect[id] or {} end,
      reserved=function(id) return reserved[id] end,
      ambient=ctx.ambient,compatible=ctx.compatible,
    }}
  end

  -- Set visible state after probing the authoritative host poses. On
  -- reload the persisted phase is presentational only; never permission.
  local function reconcile(s,id,ctx,force)
    local board=W.board(s,ctx and ctx.rail_board)
    local group=Crossing.group(board,id)
    if #group==0 then return nil,"INVALID_CROSSING" end
    local observations=probe(s,board,group,ctx)
    local known=observations~=nil
    local events=Crossing.update(board,id,known and observations.rule or nil,
      known and (not ctx or ctx.ambient~=false),force or not known)
    local phase="unobserved"
    if known then
      local road,rail=#observations.roads>0,#observations.trains>0
      if road and rail then phase="mixed_occupancy"
      elseif rail then phase="rail_occupied"
      elseif board.tile(id).barred then phase=road and "road_draining" or "barred"
      else phase="open" end
    end
    for _,k in ipairs(group) do board.tile(k).phase=phase end
    if observations then
      observations.board,observations.group,observations.events=board,group,events
    end
    return observations,phase,events
  end
  function W.refresh(s,id,ctx)
    local _,phase,events=reconcile(s,id,ctx)
    return phase,events
  end
  function W.refresh_all(s,ctx)
    local index=s.level_crossing_tiles or W.reindex(s)
    local ids,events,seen={},{},{}
    for id in pairs(index) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
      if not seen[id] and W.protected(s,id) then
        local group=Crossing.group(W.board(s),id)
        for _,other in ipairs(group) do seen[other]=true end
        local _,_,changes=reconcile(s,id,ctx)
        for _,change in ipairs(changes or {}) do events[#events+1]=change end
      end
    end
    return events
  end

  -- Commit callbacks must mutate the authoritative physical pose
  -- synchronously. Their sole return is truthy on committed movement.
  -- A lock prevents reentrant competing entries into the same world
  -- between the probe and that write. It is ephemeral, never save data.
  local locks=setmetatable({},{__mode="k"})
  local function run(s,commit)
    if locks[s] then return false,"REENTRANT_STEP" end
    if type(commit)~="function" then return false,"MISSING_STEP_COMMIT" end
    locks[s]=true
    local ok,a,b,c=pcall(commit)
    locks[s]=nil
    if not ok then error(a,0) end
    return a,b,c
  end
  local function geometry(board,from,to,td,axis)
    return from~=nil and Track.valid_trackdir(td) and Track.track(td)==axis and
      board.adjacent(from,Track.exit_side(td))==to
  end
  function W.road_step(s,ctx,from,to,td,tram,commit)
    local target=W.record(s,to)
    if not target or from==to then
      local ok,why=run(s,commit)
      if ok and from~=to and W.protected(s,from) then reconcile(s,from,ctx) end
      return ok,why
    end
    return run(s,function()
      local o,why=reconcile(s,to,ctx)
      if not o then return false,why end
      local axis=target.road_axis
      if (tram and target.tramtype==nil or not tram and target.roadtype==nil) or
          not geometry(o.board,from,to,td,axis) then return false,"WRONG_ROAD_TRACK" end
      -- Drain the entire contiguous crossing group. This deliberately
      -- differs from source per-track reds: it admits no new road traffic
      -- at a distant end, but lets traffic already inside reach the exit.
      if #o.trains>0 then return false,"TRAIN_ON_CROSSING" end
      if o.by_id[from] and not o.road_at[from] then return false,"ROAD_POSE_NOT_OBSERVED" end
      if target.barred and not o.by_id[from] then return false,"CROSSING_BARRED" end
      local ok,err=commit()
      if ok then reconcile(s,to,ctx) end
      return ok,err
    end)
  end
  -- TrainController plans a whole consist substep against one journal.
  -- Include tail/wagon transitions even when the head never changes tile.
  -- Each transition is the actual directed next claim {from,to,td},
  -- not a future route item or the renderer's interpolated sample.
  function W.train_batch(s,ctx,transitions,owner,commit)
    local board=W.board(s,ctx and ctx.rail_board)
    return run(s,function()
      local pending,groups,exits={},{},{}
      for _,p in ipairs(transitions) do
        local to,from=p.to,p.from
        if to~=from then
          local target=W.record(s,to)
          if target then
            if target.rail_owner~=owner or not geometry(board,from,to,p.td,target.rail_axis) then
              return false,"WRONG_RAIL_TRACK"
            end
            pending[#pending+1]=to
          end
          if W.protected(s,from) then exits[#exits+1]=from end
        end
      end
      local checked={}
      for _,to in ipairs(pending) do
        if not checked[to] then
          -- Close at actual entry even without a PBS claim.
          local o,why=reconcile(s,to,ctx,true)
          if not o or #o.roads>0 then
            for _,first in ipairs(groups) do reconcile(s,first,ctx) end
            return false,o and "ROAD_DRAINING" or why
          end
          groups[#groups+1]=to
          for _,i in ipairs(o.group) do checked[i]=true end
        end
      end
      local ok,err=commit()
      -- Failed underlying motion did not become an occupancy claim.
      for _,to in ipairs(groups) do reconcile(s,to,ctx) end
      if ok then
        for _,from in ipairs(exits) do
          if not checked[from] then reconcile(s,from,ctx);checked[from]=true end
        end
      end
      return ok,err
    end)
  end
  function W.train_step(s,ctx,from,to,td,owner,commit)
    return W.train_batch(s,ctx,{{from=from,to=to,td=td}},owner,commit)
  end

  -- Adapter for the existing stock dispatcher; returns only physically
  -- relevant records, not the reservation registry, route or view pose.
  -- Callers must additionally include any other rail runtimes they mount
  -- on this crossing board.
  function W.dispatch_parts(s,id)
    local list={}
    local dispatch=s.stock_rail_dispatch
    for _,service in ipairs(dispatch and dispatch.runs or {}) do
      local parts=service.consist and service.consist.parts or {}
      for i,part in ipairs(parts) do
        if part.tile==id then
          local p=part.pose
          list[#list+1]={type="train",id=service.id,part=i,front=i==1,owner=service.owner,tile=id,
            hidden=part.hidden,wormhole=part.wormhole,crashed=service.crashed or part.crashed,
            compatible={[0]=true},x=p.x,y=p.y,z=part.z or 0,td=p.td,direction=p.direction}
        end
      end
    end
    return list
  end
  return W
end
