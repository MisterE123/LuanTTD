-- Bridge the saved shared-corner world to OpenTTD ELRL construction and
-- traversal. Track, platform and depot use the stock surface at tile edges.
-- Tram and road bits/owners are independent even where they share a tile.
return function(Sim,T,Terrain,Span)
  local N={}
  local ELRL,ROAD=1,0
  local path=debug and debug.getinfo(1,"S").source
  local mod=path and path:match("^@(.*/)tram_network%.lua$")
  mod=mod or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local Slope=dofile(mod.."openttd/slope.lua")
  local Grade=dofile(mod.."openttd/tram_grade_surface.lua")(
    dofile(mod.."openttd/road_slope.lua"),Slope)
  local function shape(s,id)
    if not s.corner_grid or not s.tiles[id] then return end
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function load(s,id)
    local t=id and s.tiles[id]
    if not t then return end
    local p=t.tram
    local crossing=t.level_crossing
    if crossing then
      return {kind="crossing",axis=crossing.road_axis,tramtype=crossing.tramtype,
        tram_bits=crossing.tram_bits,tram_owner=crossing.tram_owner,roadtype=crossing.roadtype,
        road_bits=crossing.road_bits,road_owner=crossing.road_owner,slope=0,base=crossing.top}
    end
    local slope,base=shape(s,id)
    local out={slope=slope,base=base,roadworks=t.roadworks,
      overhead=(s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id])~=nil}
    if p then
      for k,v in pairs(p) do out[k]=v end
    end
    -- RC1 road_cmd.cpp CmdBuildRoad/TileType::Station admits only the
    -- through-stop axis, preserving the existing Stop and road owner.
    local station=t.build=="road_station" and t.station and s.stations[t.station]
    local road_mask=station and Sim.road_bits(s,id)
    local axis=road_mask==10 and 0 or road_mask==5 and 1 or nil
    if station and not t.road_stop_pair and axis and Sim.road_stop_tile_kind(station,id,t)=="bus" then
      out.kind,out.dir,out.owner="drive_stop",axis,station.owner
      out.terminal_level=t.road_terminal_level or select(2,Sim.road_surface(s,id))
      out.station,out.stop_type,out.shared_station=id,"bus",station.id
    end
    if t.build=="road" or out.shared_station or (p and p.kind=="drive_stop" and t.build=="road_station") then
      out.kind=out.kind or "road"
      out.road_bits=Sim.road_bits(s,id)
      if out.road_bits>0 then
        out.roadtype=ROAD
        out.road_owner=t.road_town and "town" or t.owner
      end
    end
    if not out.kind then
      if t.terrain=="water" then out.kind="water"
      elseif t.build or t.site or t.house or t.wood or t.ship or t.airfield or t.stock_industry or t.stock_landmark then out.kind="protected"
      else out.kind="clear" end
    end
    return out
  end
  local function playable(s,id,t)
    return t and t.slope~=nil and not t.overhead and
      not (t.kind~="crossing" and Sim.rail_span_protected and Sim.rail_span_protected(s,id)) and
      not (s.tunnel_below and s.tunnel_below[id])
  end
  local function options(owner,allow_slopes)
    return {owner=owner,build_on_slopes=allow_slopes==true,no_water=true,drive_through=true,
      stop_type="bus",clear_quote=function(t)
        if t.kind=="clear" then return 0 end
        return nil,"PROTECTED_TILE"
      end}
  end
  local function propose(s,owner,kind,id,arg,occupancy)
    local t=load(s,id)
    if not playable(s,id,t) then return nil,"TRAM_SITE_CLEARANCE" end
    if occupancy and occupancy(id) then t.occupied=true end
    local source=s.tiles[id]
    if kind=="road" and (source.level_crossing or source.build=="stock_rail") and Sim.crossing_construction_quote then
      if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
      local q,why=Sim.crossing_construction_quote(s,owner,id,{kind="tram",pieces=arg})
      if not q then return nil,why end
      local crossing=q.crossing
      return {kind="crossing",tramtype=crossing.tramtype,tram_bits=crossing.tram_bits,
        tram_owner=crossing.tram_owner,crossing_quote=q},q.price
    end
    local p,why
    local policy=s.stock_road_town_policy or {}
    local opts=options(owner,policy.build_on_slopes~=false)
    opts.on_town_road=policy.stop_on_town_road
    if kind=="road" and (t.kind=="road" or t.kind=="clear" or t.kind=="drive_stop") then
      p,why=T.lay(t,arg,ELRL,opts)
    elseif kind=="depot" and (t.kind=="clear" or t.kind=="depot") then
      p,why=T.depot(t,arg,ELRL,opts)
    elseif kind=="drive_stop" and (t.kind=="clear" or t.kind=="road") then
      -- Do not silently replace/extend the shared road in this preview.
      -- Complete the through carriageway with the road tool first.
      local axis=arg==0 and 10 or arg==1 and 5
      if not axis then return nil,"INVALID_PARAMETER" end
      if t.roadtype~=nil and t.road_bits~=axis then return nil,"TRAM_STOP_NEEDS_THROUGH_ROAD" end
      p,why=T.stop(t,arg,ELRL,opts)
      if p and t.roadtype~=nil then
        local slope,level=Sim.road_surface(s,id)
        if slope~=0 or level~=p.base then return nil,"TRAM_STOP_ROAD_FOUNDATION" end
      end
    else
      return nil,"PROTECTED_TILE"
    end
    if not p then return nil,why end
    return {kind=p.kind,dir=p.dir or t.dir,tram_bits=p.tram_bits,tramtype=p.tramtype,
      owner=p.kind~="road" and (p.owner or t.owner) or nil,tram_owner=p.tram_owner,
      terminal_level=(kind=="depot" or kind=="drive_stop") and p.base or t.terminal_level,
      station=(p.kind=="drive_stop") and id or nil,stop_type=(p.kind=="drive_stop") and "bus" or nil,
      shared_station=(p.kind=="drive_stop") and t.shared_station or nil,
      tram_station=(p.kind=="drive_stop") and t.tram_station or nil,
      tram_shelter=(p.kind=="drive_stop") and t.tram_shelter or nil},
      p.cost
  end

  -- Quotes are read-only and failed drags have no cash/tile side effects.
  -- Command input uses the stock mask or stock diag direction; no ID cache
  -- lives past a board's snapshot lifetime.
  function N.plan(s,owner,kind,ids,arg,occupancy)
    if not s.corner_grid or type(owner)~="string" or type(ids)~="table" or #ids==0 or
       (kind~="road" and kind~="drive_stop" and kind~="depot") then return nil,"INVALID_PARAMETER" end
    if kind=="road" and arg~=nil and (type(arg)~="number" or arg%1~=0 or arg<1 or arg>15) then
      return nil,"INVALID_PARAMETER"
    end
    if kind~="road" and (#ids~=1 or type(arg)~="number" or arg%1~=0 or arg<0 or arg>3) then
      return nil,"INVALID_PARAMETER"
    end
    if kind=="road" and arg and #ids~=1 then return nil,"INVALID_PARAMETER" end
    local requests,seen,total,items={},{},0,{}
    for n,id in ipairs(ids) do
      if not s.tiles[id] or seen[id] then return nil,"INVALID_PARAMETER" end
      seen[id]=true
      if kind=="road" and n>1 then
        local prev,matched=ids[n-1],false
        for d=1,4 do
          if Sim.adjacent(prev,d)==id then
            requests[prev]=(requests[prev] or 0)+2^(d-1)
            requests[id]=2^((d+1)%4)
            matched=true;break
          end
        end
        if not matched then return nil,"TRAM_DRAG_NOT_CONNECTED" end
      end
    end
    if kind=="drive_stop" and Sim.road_tree_authority and not Sim.road_tree_authority().new_station(s,owner,ids[1]) then
      return nil,"LOCAL_AUTHORITY_REFUSES",ids[1]
    end
    for _,id in ipairs(ids) do
      local request=arg or requests[id]
      if request==nil then return nil,"INVALID_PARAMETER" end
      local p,cost=propose(s,owner,kind,id,request,occupancy)
      if p then
        items[#items+1]={id=id,record=p}
        total=total+cost
      elseif cost~="ALREADY_BUILT" or kind~="road" then
        return nil,cost,id
      end
    end
    if #items==0 then return nil,"ALREADY_BUILT" end
    -- OpenTTD 16.0-RC1 road_gui.cpp: CcRoadDepot/CcRoadStop call
    -- ConnectRoadToStructure after the facility is placed. Only extend an
    -- existing normal tram layer; nothing is built on empty or road-only
    -- land. A blocked or unaffordable extension never cancels the facility.
    if kind~="road" then
      local budget=(s.companies[owner] and s.companies[owner].cash or 100000)-total
      local axis=4-arg
      local directions=kind=="drive_stop" and {axis,(axis+1)%4+1} or {axis}
      for _,dir in ipairs(directions) do
        local next_id=Sim.adjacent(ids[1],dir)
        local neighbor=load(s,next_id)
        if neighbor and neighbor.kind=="road" and neighbor.tramtype==ELRL and (neighbor.tram_bits or 0)>0 then
          local back=2^((dir+1)%4)
          local link,price=propose(s,owner,"road",next_id,back,occupancy)
          if link and price<=budget then
            items[#items+1]={id=next_id,record=link,frontage=true}
            total,budget=total+price,budget-price
          end
        end
      end
    end
    return items,total
  end
  local function apply(s,owner,items,cost)
    local company=s.companies[owner]
    if (company and company.cash or 100000)<cost then return nil,"NOT_ENOUGH_MONEY" end
    company=company or Sim.company(s,owner)
    company.cash=company.cash-cost
    company.expense=company.expense+cost
    company.month_exp=company.month_exp+cost
    local dirty={}
    local crossing
    for i,p in ipairs(items) do
      if p.record and p.record.crossing_quote then
        Sim.apply_crossing_construction(s,p.record.crossing_quote)
        crossing=true
      else
        local previous=s.tiles[p.id].tram
        local part=p.record
        if part and part.kind=="drive_stop" and not (part.shared_station or part.tram_station) then
          part.tram_station=Sim.register_tram_station(s,owner,p.id)
        end
        if previous and previous.tram_station and
            (not part or part.tram_station~=previous.tram_station) then
          Sim.retire_road_station(s,previous.tram_station)
        end
        local tile=s.tiles[p.id]
        tile.tram=part
        if part and part.tram_station and tile.build=="road" then
          -- CmdBuildRoadStop preserves each existing way and its owner.
          -- Whether road or tram is added first, this is one station.
          Sim.activate_tram_road_stop(s,p.id,tile.owner)
        end
      end
      dirty[i]=p.id
    end
    s.topology=s.topology+1
    if crossing then Sim.refresh_crossing_construction(s) end
    return dirty,cost
  end
  function N.construct(s,owner,kind,ids,arg,occupancy)
    local items,cost,failed=N.plan(s,owner,kind,ids,arg,occupancy)
    if not items then return nil,cost,failed end
    return apply(s,owner,items,cost)
  end
  function N.apply_facility(s,owner,q)
    local ids,price=apply(s,owner,q.changes,q.cost)
    if not ids then return false,price end
    local name=q.facility=="depot" and "Tram depot" or q.facility=="drive_stop" and "Tram platform" or "Tram half-piece"
    return true,("%s built for $%d."):format(name,price),ids
  end
  function N.span_at(s,id,include_above)
    if not Span then return end
    local t=Span.get(s,id)
    if t or not include_above then return t end
    local b=s.bridge_above and s.bridge_above[id]
    local span=b and s.stock_road_bridges and s.stock_road_bridges[b]
    return span and Span.get(s,span.start)
  end
  function N.span_plan(s,owner,id,bits,action,busy)
    local q,why=Span.quote(s,owner,id,bits,action,busy)
    if not q then return nil,why end
    local model=assert(Span.get(s,id))
    local changes={}
    for i,at in ipairs(q.dirty) do
      changes[i]={id=at,build=s.tiles[at].build,tool="tram_span_"..action,
        road_bits=Sim.road_bits(s,at),tram_bits=action=="lay" and model.axis or 0}
    end
    return {span=q,changes=changes,cost=q.cost}
  end
  function N.apply_span(s,owner,plan,busy)
    local ids,price=Span.apply(s,owner,plan.span,busy)
    if not ids then return false,price end
    if plan.span.action=="lay" then
      return true,("Electrified both ends and the full %s for $%d."):format(plan.span.kind,price),ids
    end
    return true,("Removed tramway from the %s; pavement stays. %s $%d."):format(
      plan.span.kind,price<0 and "Recovered" or "Cost",math.abs(price)),ids
  end
  local stock_sweep
  function N.drag_plan(s,owner,req,busy,span_busy)
    local company=s.companies[owner]
    local first,last=req.first,req.last or req.first
    if not company or not s.corner_grid or not s.tiles[first] or not s.tiles[last] or not busy then
      return nil,"INVALID_PARAMETER"
    end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if math.abs(x-u)+math.abs(z-v)>=128 then return nil,"INVALID_PARAMETER" end
    if not stock_sweep then
      local path=debug and debug.getinfo(1,"S").source
      local mod=path and path:match("^@(.*/)tram_network%.lua$")
      mod=mod or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
      stock_sweep=dofile(mod.."openttd/road_oneway.lua")(dofile(mod.."openttd/road_slope.lua"))
    end
    local board={xy=Sim.xy}
    function board.adjacent(id,d) return Sim.adjacent(id,4-d) end
    function board.connects(id,d)
      local t=load(s,board.adjacent(id,d))
      if not t or t.tramtype~=ELRL then return false end
      local bit=8/2^((d+2)%4)
      return math.floor((t.tram_bits or 0)/bit)%2==1
    end
    -- CmdBuildLongRoad uses the same half-tile selection for Road and
    -- Tram when disallowed directions are none. End halves attach only
    -- to an existing compatible continuation, with no road substitution.
    local gesture,why=stock_sweep.drag(board,first,last,req.axis,{toggle=0,
      start_half=req.start_half==true,end_half=req.end_half==true})
    if not gesture then return nil,why end
    if first==last and span_busy and N.span_at(s,first) then
      return N.span_plan(s,owner,first,gesture.requests[1].bits,"lay",span_busy)
    end
    local q,reason=stock_sweep.sweep(gesture,function(row)
      if row.bits==0 then return nil,"NO_TRAM_PIECE" end
      local record,cost=propose(s,owner,"road",row.tile,row.bits,busy)
      if not record then return nil,cost end
      return {id=row.tile,tool="tram_lay",changed=true,cost=cost,record=record,
        build=s.tiles[row.tile].build,road_bits=Sim.road_bits(s,row.tile),tram_bits=record.tram_bits}
    end)
    if not q then return nil,reason end
    if #q.changes==0 then return nil,"ALREADY_BUILT" end
    if q.cost>company.cash then return nil,"NOT_ENOUGH_MONEY" end
    return q
  end
  function N.apply_drag(s,owner,q)
    local ids,price=apply(s,owner,q.changes,q.cost)
    if not ids then return false,price end
    local note=("Laid tram track on %d tile%s for $%d."):format(#ids,#ids==1 and "" or "s",price)
    if q.stopped_at then note=note.." Stopped at an obstruction." end
    return true,note,ids
  end
  local removal
  function N.remove_plan(s,owner,request,busy,span_busy)
    local id=request.first
    local p=span_busy and (not request.last or request.last==id) and N.span_at(s,id)
    if p then
      local bits=request.axis==0 and 10 or request.axis==1 and 5
      if not bits then return nil,"INVALID_PARAMETER" end
      return N.span_plan(s,owner,id,bits,"remove",span_busy)
    end
    if not removal then
      local path=debug and debug.getinfo(1,"S").source
      local mod=path and path:match("^@(.*/)tram_network%.lua$")
      mod=mod or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
      local bridges=dofile(mod.."openttd/road_bridge.lua")(dofile(mod.."openttd/slope.lua"))
      removal=dofile(mod.."tram_remove_world.lua")(Sim,Terrain,
        dofile(mod.."openttd/road_slope.lua"),dofile(mod.."openttd/road_remove_long.lua"),bridges.road_clear_cost(ELRL))
    end
    return removal.plan(s,owner,request,busy)
  end
  function N.apply_remove(s,owner,plan)
    return assert(removal).apply(s,owner,plan)
  end
  -- RC1 RemoveRoadDepot and RemoveRoadStop (keep driveway).
  -- Both are facility removals, never whole-tile landscape clearing.
  function N.facility_removal_plan(s,owner,id,busy)
    local tile=s.tiles[id]
    local part=tile and tile.tram
    local company=s.companies[owner]
    if not company or not part or part.tramtype~=ELRL or
        (part.kind~="depot" and part.kind~="drive_stop") then return nil,"NO_TRAM_FACILITY" end
    if part.shared_station then
      local st=s.stations[part.shared_station]
      if not st or not part.tram_shelter or st.road_members then return nil,"SHARED_BUS_PLATFORM" end
      if Sim.road_station_in_use(s,st.id) then return nil,"STOP_IN_ORDERS" end
    end
    if part.owner~=owner then return nil,"OWNED_BY_ANOTHER" end
    if not busy or busy(id) then return nil,"VEHICLE_IN_THE_WAY" end
    local price=part.kind=="depot" and 80 or 50
    if price>company.cash then return nil,"NOT_ENOUGH_MONEY" end
    return {id=id,cost=price,kind=part.kind,dir=part.dir,terminal_level=part.terminal_level,
      bits=part.tram_bits,tram_owner=part.tram_owner,tramtype=part.tramtype,tram_station=part.tram_station,shared_station=part.shared_station}
  end
  function N.apply_facility_removal(s,owner,prior,busy)
    local q,why=N.facility_removal_plan(s,owner,prior.id,busy)
    if not q then return false,why end
    for _,field in ipairs{"cost","kind","dir","terminal_level","bits","tram_owner","tramtype","tram_station","shared_station"} do
      if q[field]~=prior[field] then return false,"STALE_QUOTE" end
    end
    local items={{id=q.id}}
    if q.kind=="drive_stop" then
      items[1].record={kind="road",tram_bits=q.bits,tramtype=q.tramtype,tram_owner=q.tram_owner}
    end
    local dirty,price=apply(s,owner,items,q.cost)
    if not dirty then return false,price end
    if q.shared_station then
      local t=s.tiles[q.id]
      Sim.retire_road_station(s,q.shared_station)
      t.build,t.station,t.stop_axis,t.road_terminal_level,t.road_stop_type="road",nil,nil,nil,nil
    end
    local label=q.kind=="drive_stop" and "Removed tram platform, kept the tracks" or "Removed tram depot"
    return true,("%s for $%d."):format(label,price),dirty
  end

  function N.move(s,from,to,commit)
    if Sim.tram_crossing_step then return Sim.tram_crossing_step(s,from,to,commit) end
    return commit()
  end
  function N.surface(s,id)
    local portal=Span and Span.get(s,id)
    if portal and portal.tramtype~=nil then
      local slope,height,foundation=Sim.road_surface(s,id)
      if slope~=nil then return {grade=slope,base=height,foundation=foundation} end
    end
    local t=load(s,id)
    if not t or not t.tramtype then return end
    return Grade.for_tile(t.slope,t.base,t,t.road_bits)
  end
  function N.surface_at(s,id,x,z)
    local p=N.surface(s,id)
    if not p then return end
    local u,v=Sim.xy(id)
    return Grade.at(p,(x-2*u+.5)/2,(z-2*v+.5)/2)
  end
  function N.frame_z(s,f)
    local span=Span and (f[10] or f[14])
    if span then return Sim.stock_road_frame_z(s,f) end
    local surface=N.surface(s,f[4])
    if not surface then
      local _,base=shape(s,f[4])
      return (base or 0)*8
    end
    return surface.base*8+Slope.pixel(f[1]%16,f[2]%16,surface.grade)
  end
  function N.board(s,occupancy)
    local B={xy=Sim.xy,tile_at=Sim.id}
    function B.tile(id)
      local p=Span and Span.get(s,id) or load(s,id)
      if p and p.tramtype then return p end
    end
    function B.tram_bits(id) return T.effective_bits(B.tile(id),false) end
    function B.adjacent(id,d) return Sim.adjacent(id,4-d) end
    local surfaces,topology,terrain_revision
    function B.surface(id)
      local revision=s.corner_grid and s.corner_grid.revision
      if not surfaces or topology~=s.topology or terrain_revision~=revision then
        surfaces,topology,terrain_revision={},s.topology,revision
      end
      if surfaces[id]==nil then surfaces[id]=N.surface(s,id) or false end
      return surfaces[id] or nil
    end
    function B.center_z(id)
      local p=B.surface(id)
      if p then return Grade.at(p,.5,.5)*8 end
      local _,base=shape(s,id)
      return base and base*8
    end
    function B.edge_available(from,to,dir)
      local a,b=B.tile(from),B.tile(to)
      local function supported(id,t)
        return t and (t.kind=="bridge" or t.kind=="tunnel" or playable(s,id,t))
      end
      if not supported(from,a) or not supported(to,b) then return false end
      local left,right=B.surface(from),B.surface(to)
      if not left or not right then return false end
      if dir~=nil then return Grade.match(left,right,4-dir) end
      for d=1,4 do if Sim.adjacent(from,d)==to then return Grade.match(left,right,d) end end
      return false
    end
    function B.stop_continues(a,b)
      local t,u=B.tile(a),B.tile(b)
      return t and u and t.kind=="drive_stop" and u.kind=="drive_stop" and
        (t.shared_station and t.shared_station==u.shared_station or t.station==u.station) and
        t.dir==u.dir and t.stop_type==u.stop_type or false
    end
    function B.stop_entry(id,d)
      return occupancy and occupancy.drive_length and occupancy.drive_length(id,d) or 0,16
    end
    function B.station_area(id,facility)
      local t=B.tile(id)
      if t and t.kind=="drive_stop" and t.station==id and t.stop_type==facility then
        return {tile=id,w=1,h=1},id
      end
    end
    B.cache_trimmed_station_area=B.station_area
    function B.can_build_tram(v,id,requested)
      if not v.owner then return false end
      local p,reason=propose(s,v.owner,"road",id,requested)
      return p~=nil or reason=="ALREADY_BUILT"
    end
    return B
  end
  return N
end
