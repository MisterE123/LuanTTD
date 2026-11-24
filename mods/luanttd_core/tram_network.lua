-- Bridge the saved shared-corner world to OpenTTD ELRL construction and
-- traversal. Track, platform and depot use the stock surface at tile edges.
-- Tram and road bits/owners are independent even where they share a tile.
return function(Sim,T,Terrain)
  local N={}
  local ELRL,ROAD=1,0
  local path=debug and debug.getinfo(1,"S").source
  local mod=path and path:match("^@(.*/)tram_network%.lua$")
  mod=mod or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local Grade=dofile(mod.."openttd/tram_grade_surface.lua")(
    dofile(mod.."openttd/road_slope.lua"),dofile(mod.."openttd/slope.lua"))
  local function shape(s,id)
    if not s.corner_grid or not s.tiles[id] then return end
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function load(s,id)
    local t=id and s.tiles[id]
    if not t then return end
    local p=t.tram
    local slope,base=shape(s,id)
    local out={slope=slope,base=base,roadworks=t.roadworks,
      overhead=(s.bridge_above and s.bridge_above[id] or s.aqueduct_above and s.aqueduct_above[id])~=nil}
    if p then
      for k,v in pairs(p) do out[k]=v end
    end
    if t.build=="road" or (p and p.kind=="drive_stop" and t.build=="road_station") then
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
      not (Sim.rail_span_protected and Sim.rail_span_protected(s,id)) and
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
    local p,why
    local policy=s.stock_road_town_policy or {}
    local opts=options(owner,policy.build_on_slopes~=false)
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
      station=(p.kind=="drive_stop") and id or nil,stop_type=(p.kind=="drive_stop") and "bus" or nil},
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
    for i,p in ipairs(items) do s.tiles[p.id].tram=p.record;dirty[i]=p.id end
    s.topology=s.topology+1
    return dirty,cost
  end
  function N.construct(s,owner,kind,ids,arg,occupancy)
    local items,cost,failed=N.plan(s,owner,kind,ids,arg,occupancy)
    if not items then return nil,cost,failed end
    return apply(s,owner,items,cost)
  end
  local stock_sweep
  function N.drag_plan(s,owner,req,busy)
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
  function N.remove_plan(s,owner,request,busy)
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
  function N.surface(s,id)
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
  function N.board(s,occupancy)
    local B={xy=Sim.xy,tile_at=Sim.id}
    function B.tile(id)
      local p=load(s,id)
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
      if not playable(s,from,a) or not playable(s,to,b) then return false end
      local left,right=B.surface(from),B.surface(to)
      if not left or not right then return false end
      if dir~=nil then return Grade.match(left,right,4-dir) end
      for d=1,4 do if Sim.adjacent(from,d)==to then return Grade.match(left,right,d) end end
      return false
    end
    function B.stop_continues(a,b)
      local t,u=B.tile(a),B.tile(b)
      return t and u and t.kind=="drive_stop" and u.kind=="drive_stop" and
        t.station==u.station and t.dir==u.dir and t.stop_type==u.stop_type or false
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
