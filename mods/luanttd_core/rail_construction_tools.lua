-- Native quote/commit adapter for ordinary Trackworks. Pricing functions
-- are supplied by the pinned construction kernel, not the menu.
return function(api,Lab,Track,Run,prices)
  local R={}
  local Sim,S=api.Sim,api.s
  local function protected(id) return Lab.span_protected and Lab.span_protected(S,id) end
  local span_msg="That tile is part of a protected rail span."
  local function company(owner)
    return S.companies[owner] or {cash=100000}
  end
  local function debit(owner,cost)
    local c=Sim.company(S,owner)
    c.cash,c.expense,c.month_exp=c.cash-cost,c.expense+cost,c.month_exp+cost
  end
  local function signed(id)
    local d=S.stock_rail_dispatch
    return d and d.signals.records[id]~=nil or false
  end
  function R.busy()
    local d=S.stock_rail_dispatch
    return S.stock_rail_run or d and #d.runs>0 or
      api.trackworks_demo and not api.trackworks_demo.is_clear()
  end
  local function record(id)
    local t=S.tiles[id]
    if not t then return end
    local shape,base=api.terrain.tile(id)
    local r=Lab.board(S).tile(id)
    if not r then
      r={kind="clear",owner=t.owner,railtype=0}
      if t.stock_void or t.build or t.site or t.house or t.tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or t.owner then
        r.kind="protected"
      elseif t.wood then
        r.kind="trees"
        r.tree_count=type(t.wood)=="table" and t.wood.count or 1
      end
      if t.terrain=="water" and not t.stock_void then r.kind="water" end
    end
    r.slope,r.base_level=shape,base
    r.id=id
    r.overhead=S.bridge_above and S.bridge_above[id]~=nil or S.aqueduct_above and S.aqueduct_above[id]~=nil or false
    if S.tunnel_below and S.tunnel_below[id] then r.subsurface=true end
    return r
  end
  local function clear_quote(t)
    if t.kind=="clear" and not t.subsurface then return 20 end
    -- OpenTTD 16.0-RC1 ClearTile_Trees charges ClearTrees (20) per temperate stem.
    -- Tree removal is committed by the track piece itself, never by quoting.
    if t.kind=="trees" and not t.subsurface then return 20*t.tree_count end
    return nil,"Clear trees, structures and protected ground first."
  end
  local function opts(owner)
    return {owner=owner,clear_quote=clear_quote,build_on_slopes=true}
  end
  local function blocked()
    return "Clear the running or surveyed train before editing the railway."
  end
  local function budget(owner,plan)
    if plan.price>company(owner).cash then return nil,"Your company cannot afford that railway work." end
    plan.topology,plan.owner=S.topology,owner
    return plan
  end
  local upstream=(core and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/"
  local Autorail=dofile(upstream.."autorail.lua")(Track)
  local Waypoint=dofile(upstream.."rail_waypoint.lua")
  local quote_drag=dofile(upstream.."rail_drag_build.lua")
  local function quote_pieces(owner,list,remove,quick_drag)
    if R.busy() then return nil,blocked() end
    local out={kind="track",pieces={},ids={},preview=list,price=0,tree_count=0,remove=remove,quick_drag=quick_drag}
    local unchanged=remove and "There is no matching track to remove." or "Already built."
    local function append(item)
      local id,track=item.id,item.track
      local t=S.tiles[id]
      local existing=t.rail_tracks or 0
      local p,value
      if t.level_crossing then
        if remove or track~=t.level_crossing.rail_axis then return nil,span_msg end
        if t.level_crossing.rail_owner~=owner then return nil,"Another company owns a tile on this route." end
        return false,unchanged
      elseif protected(id) then return nil,span_msg
      elseif not remove and S.level_crossing_enabled and t.build=="road" and not t.rail_tracks then
        local q,why=Sim.crossing_construction_quote(S,owner,id,{kind="rail",track=track})
        if not q then return nil,Sim.crossing_construction_error(why) end
        p={id=id,track=track,shape=q.crossing.slope,tracks=2^track,crossing_quote=q}
        value=q.price
        out.crossing=true
      elseif Track.has(existing,track)==remove then
        if signed(id) then return nil,"This tile has a path signal." end
        local shape=api.terrain.tile(id)
        local ok,plan=Lab.piece_plan(S,owner,id,track,remove,shape)
        if not ok then return nil,plan end
        p=plan
        local tile=record(id)
        if tile.overhead or tile.subsurface then return nil,"This railway preview cannot build on protected structure layers." end
        local why
        value,why=prices.track(tile,p,opts(owner))
        if value==nil then return nil,why end
        if not remove and tile.kind=="trees" then out.tree_count=out.tree_count+tile.tree_count end
      elseif t.owner and t.owner~=owner then
        return nil,"Another company owns a tile on this route."
      else
        return false,unchanged
      end
      out.price=out.price+value
      out.pieces[#out.pieces+1]=p;out.ids[#out.ids+1]=id
      return true
    end
    if quick_drag then
      local ok,why,stopped,skipped=quote_drag(list,append,false)
      if not ok then return nil,why or unchanged end
      out.stopped_at,out.skipped_start=stopped,skipped
    else
      for _,item in ipairs(list) do
        local ok,why=append(item)
        if ok==nil then return nil,why end
      end
    end
    if #out.ids==0 then return nil,unchanged end
    return budget(owner,out)
  end
  function R.quote_track(owner,first,last,track,remove)
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if first~=last and not (track==0 and z==v or track==1 and x==u) then
      return nil,"Straight track drags follow their selected X or Z axis."
    end
    local list={}
    for _,id in ipairs(Sim.line(first,last)) do list[#list+1]={id=id,track=track} end
    return quote_pieces(owner,list,remove)
  end
  function R.quote_autotrack(owner,first,last)
    local track,u,v=Autorail.snap(first.x,first.z,last.x,last.z)
    local trace=Autorail.trace(math.floor(first.x/16),math.floor(first.z/16),u,v,track)
    local list={}
    for _,p in ipairs(trace or {}) do
      local id=Sim.id(p.x,p.z)
      if not id then return nil,"The snapped track runs outside the map.",list end
      list[#list+1]={id=id,track=p.track}
    end
    if #list==0 then return nil,"Aim along a straight or diagonal railway.",list end
    local plan,why=quote_pieces(owner,list,false,#list>1)
    return plan,why,list
  end
  local StationPlacement=dofile(upstream.."rail_station_placement.lua")
  function R.quote_station(owner,first,last,layout)
    if R.busy() then return nil,blocked() end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    local area=StationPlacement.bounds(x,z,u,v,layout)
    local group,topics,existing={},{}
    for row=area.z,area.z+area.h-1 do
      for col=area.x,area.x+area.w-1 do
        local id=Sim.id(col,row)
        if id then group[#group+1]=id end
      end
    end
    if #group~=area.w*area.h then return nil,"The station footprint is outside playable land.",group end
    for _,id in ipairs(group) do
      if S.tiles[id].stock_void then return nil,"The station footprint is outside playable land.",group end
      if protected(id) then return nil,span_msg,group end
      if signed(id) then return nil,"A platform cannot cover a signal.",group end
      local tile=record(id)
      if tile.kind=="station" then
        local st=S.stock_rail_stations[tile.station]
        if not st then return nil,"This platform has no matching station record.",group end
        if st.owner~=owner then return nil,"Another company owns this station.",group end
        if existing and existing.id~=st.id then return nil,"Adjoins more than one existing station.",group end
        existing=st
      end
      if tile.slope~=0 or tile.overhead or tile.subsurface then return nil,"Platforms need open level ground.",group end
      topics[#topics+1]=tile
    end
    local join,deny=StationPlacement.find_join(area,owner,existing,layout.separate,function(col,row)
      local tid=Sim.id(col,row)
      local t=tid and S.tiles[tid]
      return t and t.rail_station_id and S.stock_rail_stations[t.rail_station_id]
    end)
    if deny then return nil,deny,group end
    local combined=area
    if join then
      local box=Lab.station_bounds(S,join)
      combined=StationPlacement.combined(area,box)
      if math.max(combined.w,combined.h)>StationPlacement.spread then
        return nil,"The joined station would exceed the station spread.",group
      end
      if join.coal_role or join.goods_role or join.oil_role then
        return nil,"Clear the station's designated freight role before extending it.",group
      end
    end
    local value,why=prices.station_area(topics,area.axis,area.tracks,area.length,opts(owner))
    if value==nil then return nil,why,group end
    return budget(owner,{kind="platform",axis=area.axis,area=area,combined=combined,join=join and join.id,ids=group,price=value})
  end
  function R.quote_platform(owner,first,last,d)
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if x~=u and z~=v then return nil,"A platform follows one straight axis." end
    local axis=first==last and d%2 or z==v and 0 or 1
    if prices.station_area then
      return R.quote_station(owner,first,last,{axis=axis,drag=true,tracks=1,length=1})
    end
    -- Externally supplied one-platform test adapter.
    local group,topics=Sim.line(first,last),{}
    for _,id in ipairs(group) do topics[#topics+1]=record(id) end
    local value,why=prices.platform(topics,axis,opts(owner))
    if value==nil then return nil,why end
    return budget(owner,{kind="platform",axis=axis,ids=group,price=value})
  end
  function R.quote_depot(owner,id,dir)
    if R.busy() then return nil,blocked() end
    if protected(id) then return nil,span_msg end
    if signed(id) then return nil,"The tile has a path signal." end
    local tile=record(id)
    if not tile or tile.slope~=0 or tile.subsurface then return nil,"Choose clear, level ground for this depot." end
    local value,why=prices.depot(tile,dir,opts(owner))
    if value==nil then return nil,why end
    return budget(owner,{kind="depot",id=id,direction=dir,ids={id},price=value})
  end
  function R.quote_waypoint(owner,id,remove)
    if R.busy() then return nil,blocked() end
    if protected(id) then return nil,span_msg end
    if signed(id) then return nil,"A waypoint cannot cover a signal." end
    local t=record(id)
    if not t then return nil,"Choose existing straight railway." end
    local d=S.stock_rail_dispatch
    local bits=d and d.life and d.life.bits and d.life.bits[id] or 0
    local axis=Waypoint.axis(t)
    if axis~=nil then t.reserved=Track.has(bits,axis) end
    if remove and t.reserved then return nil,"Clear the reservation before removing this waypoint." end
    if t.kind=="waypoint" and not remove then return nil,"A waypoint already stands on this tile." end
    local unit,why
    if remove then unit,why=Waypoint.remove(t,{owner=owner})
    else unit,why=Waypoint.build(t,axis,{owner=owner,build_on_slopes=true}) end
    if not unit then
      local errors={NO_SUITABLE_RAILROAD_TRACK="Choose an existing plain, straight rail tile.",
        NO_WAYPOINT="Choose a rail waypoint.",OWNED_BY_ANOTHER="Another company owns that tile.",
        VEHICLE_IN_THE_WAY="A train is on that tile.",
        FLAT_LAND_REQUIRED="That slope cannot support a waypoint.",
        MUST_DEMOLISH_BRIDGE_FIRST="A bridge crosses over that tile."}
      return nil,errors[why] or why
    end
    if t.subsurface then return nil,"A protected structure layer occupies this tile." end
    if t.slope~=0 then
      local grade,level=Lab.surface(t.slope,t.base_level,t.trackbits)
      -- GetSlopePixelZ_Station uses the highest corner. Only mount the
      -- existing foundation if its visible track already agrees with that
      -- stock station height; rendering an inclined track with a flat
      -- waypoint movement profile would lift a moving train off the rail.
      if grade~=0 or level~=t.base_level+1 then
        return nil,"Use level track or a level rail foundation for this waypoint."
      end
    end
    return budget(owner,{kind=remove and "waypoint_remove" or "waypoint",id=id,axis=unit.axis,ids={id},price=unit.price})
  end
  function R.quote_signal(owner,id,dir,oneway,block,both)
    if R.busy() then return nil,blocked() end
    if protected(id) then return nil,span_msg end
    if block and not api.rail_block_tools then return nil,"Enable conventional block signals first." end
    if not Run then return nil,"Enable the rail-dispatch preview to place path signals." end
    if signed(id) then return nil,"This tile already has a path signal." end
    local t=Lab.board(S).tile(id)
    if not t or t.owner~=owner or t.kind~="rail" or t.trackbits~=2^(dir%2) then
      return nil,"Choose a plain straight rail tile that matches the signal direction."
    end
    -- OpenTTD 16.0-RC1 CmdBuildSingleSignal permits existing plain
    -- track on slopes. Grade support here supplies the matching 3D base.
    local value,why=prices.signal(t,dir,oneway,opts(owner))
    if value==nil then return nil,why end
    return budget(owner,{kind="signal",id=id,td=Track.diagonal_trackdir(dir),
      one_way=oneway,block=not not block,both=block and not not both,ids={id},price=value})
  end
  function R.quote_remove_signal(owner,id)
    if R.busy() then return nil,blocked() end
    if protected(id) then return nil,span_msg end
    local t=Lab.board(S).tile(id)
    if not signed(id) or not t or t.owner~=owner then return nil,"Choose your own path signal." end
    return budget(owner,{kind="signal_remove",id=id,ids={id},price=prices.clear_signal()})
  end
  function R.signal_details(id)
    local d=S.stock_rail_dispatch
    local rec=d and d.signals and d.signals.records[id]
    local t=id and S.tiles[id]
    if not rec or not t or (t.rail_tracks~=1 and t.rail_tracks~=2) then return end
    local dirs={}
    for dir=t.rail_tracks-1,3,2 do
      local td=Track.diagonal_trackdir(dir)
      if Track.intersect(rec.present_signals or 0,Track.signal_along(td))~=0 then
        dirs[#dirs+1]=dir
      end
    end
    return {owner=t.owner,dirs=dirs,kind=rec.upper_signal_type,axis=t.rail_tracks-1,record=rec}
  end
  function R.quote_flip_signal(owner,id)
    if R.busy() then return nil,blocked() end
    if protected(id) then return nil,span_msg end
    local d=R.signal_details(id)
    if not d or d.owner~=owner or #d.dirs~=1 then return nil,"Choose an owned signal with one head." end
    return budget(owner,{kind="signal_flip",id=id,td=Track.diagonal_trackdir(d.dirs[1]),
      locked_record=d.record,price=0,ids={id}})
  end
  function R.order(owner,depot,first,last)
    if not Run then return false,"Enable the rail dispatch preview." end
    if api.trackworks_demo and not api.trackworks_demo.is_clear() then return false,"Clear the surveyed train first." end
    local ok,msg
    if last then ok,msg=Run.start_shuttle(S,owner,depot,first,last)
    else ok,msg=Run.start(S,owner,depot,first) end
    if ok then api.save() end
    return ok,msg
  end
  function R.order_block(owner,depot,station)
    if not (Run and api.rail_block_tools) then return false,"Enable conventional block signals first." end
    if api.trackworks_demo and not api.trackworks_demo.is_clear() then return false,"Clear the surveyed train first." end
    local ok,msg=Run.start_block(S,owner,depot,station)
    if ok then api.save() end
    return ok,msg
  end
  function R.clear_order(owner)
    if not Run then return false,"Enable the rail dispatch preview." end
    local ok,msg=Run.clear(S,owner)
    if ok then api.save() end
    return ok,msg
  end
  -- OpenTTD 16.0-RC1 rail_gui.cpp: CcBuildTrainDepot calls
  -- TryBuildRailDepotTrack on the mouth tile. Each eligible connection
  -- posts its own ordinary, paid BuildRail; a failure never undoes the depot.
  local connect_pieces={
    [0]={{Track.LEFT,Track.SE},{Track.X,Track.SW},{Track.LOWER,Track.NW}},
    [1]={{Track.UPPER,Track.SW},{Track.Y,Track.NW},{Track.LEFT,Track.NE}},
    [2]={{Track.UPPER,Track.SE},{Track.X,Track.NE},{Track.RIGHT,Track.NW}},
    [3]={{Track.RIGHT,Track.SW},{Track.Y,Track.SE},{Track.LOWER,Track.NE}},
  }
  local function depot_connect(owner,id,dir)
    local board=Lab.board(S)
    local front=board.adjacent(id,dir)
    if not front or signed(front) then return 0 end
    local t=S.tiles[front]
    if not t or t.rail_depot_dir~=nil or t.rail_station_id or t.rail_waypoint_id or
        t.level_crossing or t.rail_span_id or not t.rail_tracks then return 0 end
    local across=board.adjacent(front,dir)
    local next_depot=across and S.tiles[across].rail_depot_dir~=nil
    local built=0
    for i,c in ipairs(connect_pieces[dir]) do
      if not (i==2 and next_depot) and
          Track.intersect(t.rail_tracks,Track.trackbits(Track.reachable(c[2])))~=0 then
        local piece=R.quote_track(owner,front,front,c[1],false)
        if piece and R.build(owner,piece) then built=built+1 end
      end
    end
    return built
  end
  function R.build(owner,plan)
    if not plan or plan.owner~=owner or plan.topology~=S.topology or R.busy() then
      return false,"The railway changed. Select the construction again."
    end
    if plan.price>company(owner).cash then return false,"Your company cannot afford that railway work." end
    for _,id in ipairs(plan.ids or {}) do
      if protected(id) then return false,span_msg end
    end
    local ok,note
    if plan.kind=="track" then
      -- Physical occupancy and forest density can change without a topology
      -- revision. Requote before applying ANY piece of the drag.
      if plan.crossing or (plan.tree_count or 0)>0 or not plan.remove then
        local fresh,why=quote_pieces(owner,plan.preview,plan.remove,plan.quick_drag)
        if not fresh then return false,why end
        if fresh.crossing~=plan.crossing or fresh.price~=plan.price or fresh.tree_count~=plan.tree_count or #fresh.ids~=#plan.ids then
          return false,"The railway changed. Select the construction again."
        end
        for i,id in ipairs(fresh.ids) do
          if id~=plan.ids[i] then return false,"The railway changed. Select the construction again." end
        end
        plan=fresh
      end
      for _,piece in ipairs(plan.pieces) do
        if piece.crossing_quote then Sim.apply_crossing_construction(S,piece.crossing_quote)
        else assert(Lab.commit_piece(S,owner,piece)) end
      end
      if plan.crossing then
        S.topology=S.topology+1
        Sim.refresh_crossing_construction(S)
      end
      ok,note=true,plan.crossing and "Track laid, including level crossing work." or "Track pieces updated."
    elseif plan.kind=="platform" then
      ok,note=Lab.commit_station(S,owner,plan.ids,plan.axis,plan.combined or plan.area,plan.join)
    elseif plan.kind=="depot" then
      ok,note=Lab.commit_depot(S,owner,plan.id,plan.direction)
    elseif plan.kind=="waypoint" or plan.kind=="waypoint_remove" then
      local removal=plan.kind=="waypoint_remove"
      local fresh,why=R.quote_waypoint(owner,plan.id,removal)
      if not fresh then return false,why end
      if fresh.axis~=plan.axis or fresh.price~=plan.price then return false,"The railway changed. Select the waypoint again." end
      plan=fresh
      ok,note=Lab.commit_waypoint(S,owner,plan.id,plan.axis,removal)
    elseif plan.kind=="signal" then
      ok,note=Run.place_signal(S,owner,plan.id,plan.td,plan.block and 0 or plan.one_way and 5 or 4,plan.both)
    elseif plan.kind=="signal_flip" then
      local fresh,why=R.quote_flip_signal(owner,plan.id)
      if not fresh then return false,why end
      if fresh.td~=plan.td or fresh.locked_record~=plan.locked_record then
        return false,"The signal changed. Inspect it again."
      end
      ok,note=Run.flip_signal(S,owner,plan.id,plan.td)
      if ok then S.topology=S.topology+1 end
    elseif plan.kind=="signal_remove" then
      S.stock_rail_dispatch.signals.records[plan.id]=nil
      S.topology=S.topology+1
      ok,note=true,"Signal removed; rail remains."
    else return false,"No railway placement selected." end
    if not ok then return false,note end
    debit(owner,plan.price)
    if plan.kind=="depot" then
      local connections=depot_connect(owner,plan.id,plan.direction)
      if connections>0 then note=note.." Connected to nearby track." end
    end
    api.render.update(plan.ids);api.save()
    return true,note
  end
  return R
end
