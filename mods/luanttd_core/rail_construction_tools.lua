-- Native quote/commit adapter for ordinary Trackworks. Pricing functions
-- are supplied by the pinned construction kernel, not the menu.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(mod.."/rail_freight_kinds.lua")
local Types=dofile(mod.."/openttd/rail_types.lua")
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
    if S.stock_rail_run or api.trackworks_demo and not api.trackworks_demo.is_clear() then return true end
    for _,r in ipairs(d and d.runs or {}) do
      if not r.local_signals and (not r.crashed or #r.consist.parts>0) then return true end
    end
    return false
  end
  local function live_edit_guard(id)
    local d=S.stock_rail_dispatch
    if not d then return end
    if d.life and d.life.claims and d.life.claims[id] then
      return "A train has reserved this tile."
    end
    for _,r in ipairs(d.runs or {}) do
      for _,p in ipairs(r.consist.parts) do
        if p.tile==id then return "A train is on this tile." end
      end
      -- Until full dispatch replanning on destructive edits is ported,
      -- keep live ordered infrastructure intact. This guard does not
      -- stop adding track elsewhere on the same or another map.
      if not r.crashed then
        if r.ordered_tiles and r.ordered_tiles[id] then return "A running train uses this route." end
        for _,step in ipairs(r.route or {}) do
          if step.tile==id then return "A running train uses this route." end
        end
      end
    end
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
      if t.terrain=="water" and not t.stock_void then r.kind,r.coast="water",t.coastal_water==true and not t.wood end
    end
    if r.kind=="rail" and signed(id) then
      r.kind="signals"
      for k,v in pairs(S.stock_rail_dispatch.signals.records[id]) do r[k]=v end
    end
    r.slope,r.base_level,r.flooding=shape,base,t.rail_ground==13
    if r.coast and Sim.coastal_in_use then r.occupied=Sim.coastal_in_use(S,id) end
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
  local Depot=dofile(upstream.."rail_depot_construction.lua")(Track,dofile(upstream.."rail_construction.lua")(Track))
  local function gauge_allowed(owner,gauge)
    return gauge==nil or gauge==Types.RAIL or Types.entry(gauge) and
      api.company_can_build_stock_railtype and api.company_can_build_stock_railtype(owner,gauge)
  end
  local function quote_pieces(owner,list,remove,quick_drag,gauge)
    if R.busy() then return nil,blocked() end
    gauge=gauge or Types.RAIL
    if not gauge_allowed(owner,gauge) then
      return nil,"This rail type is not available to your company."
    end
    local out={kind="track",pieces={},ids={},preview=list,price=0,tree_count=0,
      remove=remove,quick_drag=quick_drag,gauge=gauge}
    local unchanged=remove and "There is no matching track to remove." or "Already built."
    local function append(item)
      local id,track=item.id,item.track
      local t=S.tiles[id]
      local existing=t.rail_tracks or 0
      if Track.has(existing,track)==remove then
        local why=live_edit_guard(id);if why then return nil,why end
      end
      local p,value
      if t.level_crossing then
        if gauge~=Types.RAIL then return nil,"This crossing uses a different rail type." end
        if remove or track~=t.level_crossing.rail_axis then return nil,span_msg end
        if t.level_crossing.rail_owner~=owner then return nil,"Another company owns a tile on this route." end
        return false,unchanged
      elseif protected(id) then return nil,span_msg
      elseif not remove and S.level_crossing_enabled and (t.build=="road" or t.tram and t.tram.kind=="road") and not t.rail_tracks then
        if gauge~=Types.RAIL then return nil,"Build this rail type away from road crossings." end
        local q,why=Sim.crossing_construction_quote(S,owner,id,{kind="rail",track=track})
        if not q then return nil,Sim.crossing_construction_error(why) end
        p={id=id,track=track,shape=q.crossing.slope,tracks=2^track,crossing_quote=q}
        value=q.price
        out.crossing=true
      elseif Track.has(existing,track)==remove then
        local shape=api.terrain.tile(id)
        local ok,plan=Lab.piece_plan(S,owner,id,track,remove,shape)
        if not ok then return nil,plan end
        p=plan
        if p.split_foundation and gauge~=Types.RAIL then return nil,"Use ordinary rail on this split foundation." end
        local tile=record(id)
        if tile.kind=="signals" then
          -- CmdBuildSingleRail keeps signals when adding an independent
          -- half track. The stock client's auto-remove setting is off.
          if not remove and Track.tracks_overlap(p.tracks) then
            return nil,"Remove the signal before building overlapping rail."
          end
          if remove and R.signal_details(id,track) then
            if not Run then return nil,"Remove the signal before removing its track." end
            p.remove_signal=true
          end
        end
        if tile.overhead or tile.subsurface then return nil,"This railway preview cannot build on protected structure layers." end
        local why,quote
        local options=opts(owner)
        options.railtype=gauge
        value,why,quote=prices.track(tile,p,options)
        if value==nil then return nil,why end
        if quote and quote.railtype==Types.ELECTRIC and Track.tracks_overlap(p.tracks) then
          return nil,"This electrified junction has no mounted catenary model."
        end
        -- Normal quotes preserve an existing rail type when no
        -- conversion is needed. Explicit advanced quotes use the
        -- returned type, never the player's requested type blindly.
        if p.shore and (not quote or quote.water_ground~=true or not p.split_foundation) then
          return nil,"Only the raised half of this shore supports ordinary rail."
        end
        if quote then p.result_railtype,p.water_ground=quote.railtype,quote.water_ground
        elseif gauge~=Types.RAIL and not remove then return nil,"No builder for this rail type." end
        if p.remove_signal then value=value+prices.clear_signal() end
        if not remove and tile.kind=="trees" then out.tree_count=out.tree_count+tile.tree_count end
      elseif t.owner and t.owner~=owner then
        return nil,"Another company owns a tile on this route."
      else
        if not remove and t.rail_tracks and not Types.is_compatible(t.rail_type or Types.RAIL,gauge) then
          return nil,"IMPOSSIBLE_TRACK_COMBINATION"
        end
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
  function R.quote_track(owner,first,last,track,remove,gauge)
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if first~=last and not (track==0 and z==v or track==1 and x==u) then
      return nil,"Straight track drags follow their selected X or Z axis."
    end
    local list={}
    for _,id in ipairs(Sim.line(first,last)) do list[#list+1]={id=id,track=track} end
    return quote_pieces(owner,list,remove,false,gauge)
  end
  function R.quote_autotrack(owner,first,last,gauge)
    local track,u,v=Autorail.snap(first.x,first.z,last.x,last.z)
    local trace=Autorail.trace(math.floor(first.x/16),math.floor(first.z/16),u,v,track)
    local list={}
    for _,p in ipairs(trace or {}) do
      local id=Sim.id(p.x,p.z)
      if not id then return nil,"The snapped track runs outside the map.",list end
      list[#list+1]={id=id,track=p.track}
    end
    if #list==0 then return nil,"Aim along a straight or diagonal railway.",list end
    local plan,why=quote_pieces(owner,list,false,#list>1,gauge)
    return plan,why,list
  end
  local StationPlacement=dofile(upstream.."rail_station_placement.lua")
  function R.quote_station(owner,first,last,layout)
    if R.busy() then return nil,blocked() end
    if not gauge_allowed(owner,layout.railtype) then return nil,"This rail type is not available to your company." end
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
      local why=live_edit_guard(id);if why then return nil,why,group end
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
      if Freight.role(join) then
        return nil,"Clear the station's designated freight role before extending it.",group
      end
    end
    local options=opts(owner)
    options.railtype=layout.railtype
    local value,why=prices.station_area(topics,area.axis,area.tracks,area.length,options)
    if value==nil then return nil,why,group end
    return budget(owner,{kind="platform",axis=area.axis,area=area,combined=combined,join=join and join.id,
      ids=group,price=value,gauge=layout.railtype})
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
  function R.quote_depot(owner,id,dir,gauge)
    if R.busy() then return nil,blocked() end
    if not gauge_allowed(owner,gauge) then return nil,"This rail type is not available to your company." end
    local tile=record(id)
    local t=id and S.tiles[id]
    if not t or not tile or not tile.slope or tile.subsurface or
        S.rail_tunnel_below and S.rail_tunnel_below[id] or t.rail_span_id or t.level_crossing then
      return nil,"Choose a clear tile without protected structures for this depot."
    end
    if protected(id) and not (S.rail_bridge_above and S.rail_bridge_above[id]) then return nil,span_msg end
    local over_rail=S.rail_bridge_above and S.rail_bridge_above[id]
    local over_road=S.bridge_above and S.bridge_above[id]
    local over_aqua=S.aqueduct_above and S.aqueduct_above[id]
    local above=(over_rail and S.stock_rail_spans and S.stock_rail_spans[over_rail]) or
      (over_road and S.stock_road_bridges and S.stock_road_bridges[over_road]) or
      (over_aqua and S.stock_aqueducts and S.stock_aqueducts[over_aqua])
    tile.overhead=not not (over_rail or over_road or over_aqua)
    tile.deck=above and above.deck
    local lib=opts(owner)
    lib.build_on_slopes=S.rail_build_on_slopes~=false
    lib.railtype=gauge or tile.kind=="depot" and tile.railtype or 0
    local guard=live_edit_guard(id)
    tile.occupied=Lab.owned_depot_occupied and Lab.owned_depot_occupied(S,id) or nil
    local function clear_depot_tile(r)
      if guard then return nil,guard end
      -- The stock GUI command is DC_AUTO|DC_NO_WATER. Do not silently
      -- demolish other infrastructure, even when we own it.
      if (r.owner and r.owner~=owner) then return nil,"OWNED_BY_ANOTHER" end
      if r.kind=="rail" or signed(id) then return nil,"MUST_REMOVE_RAILROAD_TRACK" end
      if r.kind=="water" then
        if t.coastal_water and Sim.clear_water then
          local q,msg=Sim.clear_water(S,owner,id,true)
          if q then return msg end
          return nil,msg
        end
        return nil,"CANT_BUILD_ON_WATER"
      end
      if r.kind=="clear" then
        if t.stock_clear_ground==1 then return 40 end
        if t.stock_clear_ground==2 then return 200 end
      end
      return clear_quote(r)
    end
    lib.clear=clear_depot_tile
    local depot,why,detail=Depot.quote(tile,dir,lib)
    if not depot then
      local errors={
        INVALID_PARAMETER="Choose a valid depot tile and door direction.",
        FLAT_LAND_REQUIRED="Depot foundations are disabled. Choose flat ground.",
        LAND_SLOPED_IN_WRONG_DIRECTION="The depot door cannot face down that slope. Right-click to choose another direction.",
        OWNED_BY_ANOTHER="Another company owns this tile.",
        VEHICLE_IN_THE_WAY="Move the vehicles out of this depot before rotating it.",
        MUST_REMOVE_RAILROAD_TRACK="Remove the existing rails before building a depot on this tile.",
        CANT_BUILD_ON_WATER="A rail depot must stand on land.",
        UNKNOWN_BRIDGE_HEIGHT="The overlying span has no verified height.",
      }
      return nil,why=="BRIDGE_TOO_LOW_FOR_TRAIN_DEPOT" and
        ("This bridge is %d height level%s too low for the depot."):format(detail/8,detail==8 and "" or "s")
        or errors[why] or why
    end
    if guard and not depot.noop then return nil,guard end
    depot.kind,depot.id,depot.ids,depot.price="depot",id,{id},depot.cost
    depot.clear_coast=t.coastal_water or nil
    depot.requested_railtype=gauge
    return budget(owner,depot)
  end
  function R.quote_waypoint(owner,id,remove)
    if R.busy() then return nil,blocked() end
    local why=live_edit_guard(id);if why then return nil,why end
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
  local PickSignal=dofile(upstream.."rail_signal_place.lua")(Track)
  local Signal=dofile(upstream.."rail_signals.lua")(Track)
  function R.signal_track(id,hit)
    local t=id and S.tiles[id]
    local bits=t and t.rail_tracks
    if not bits or Track.tracks_overlap(bits) then return end
    local u,v
    if hit then
      local x,z=Sim.xy(id)
      u=math.max(0,math.min(15,math.floor((hit.x-(2*x-.5))*8)))
      v=math.max(0,math.min(15,math.floor((hit.z-(2*z-.5))*8)))
    end
    local track=PickSignal(bits,u,v)
    if track and Track.has(bits,track) then return track end
  end
  function R.quote_signal_track(owner,id,td,kind,both)
    if R.busy() then return nil,blocked() end
    local why=live_edit_guard(id);if why then return nil,why end
    if protected(id) then return nil,span_msg end
    local one,block=kind==Signal.PBS_ONEWAY,kind==Signal.BLOCK
    if block and not api.rail_block_tools then return nil,"Conventional block signals are not available." end
    if not Run or not Track.valid_trackdir(td) then return nil,"Choose a valid approach." end
    local t=Lab.board(S).tile(id)
    local track=Track.track(td)
    if not t or t.owner~=owner or t.kind~="rail" or not Track.has(t.trackbits,track) or Track.tracks_overlap(t.trackbits) then
      return nil,"Choose owned plain track. Junctions and crossings cannot hold these signals."
    end
    if R.signal_details(id,track) then return nil,"This track already has a signal." end
    local value
    if prices.signal_track then value,why=prices.signal_track(t,track,kind,opts(owner))
    elseif track<=1 then value,why=prices.signal(t,Track.exit_side(td),one,opts(owner))
    else return nil,"The curved-track signal price is not mounted." end
    if value==nil then return nil,why end
    return budget(owner,{kind="signal",id=id,td=td,block=block,one_way=one,both=block and not not both,
      ids={id},price=value})
  end
  function R.quote_signal(owner,id,dir,oneway,block,both)
    return R.quote_signal_track(owner,id,Track.diagonal_trackdir(dir),block and Signal.BLOCK or
      oneway and Signal.PBS_ONEWAY or Signal.PBS,both)
  end
  function R.signal_details(id,track)
    local d=S.stock_rail_dispatch
    local rec=d and d.signals and d.signals.records[id]
    local t=id and S.tiles[id]
    if not rec or not t or not t.rail_tracks then return end
    if track==nil then
      for i=0,5 do if Track.has(t.rail_tracks,i) and R.signal_details(id,i) then track=i;break end end
    end
    if track==nil or not Track.has(t.rail_tracks,track) then return end
    local dirs,tds={},{}
    for _,td in ipairs({track,track+8}) do
      if Track.intersect(rec.present_signals or 0,Track.signal_along(td))~=0 then
        dirs[#dirs+1]=Track.exit_side(td);tds[#tds+1]=td
      end
    end
    if #tds==0 then return end
    return {owner=t.owner,dirs=dirs,tds=tds,track=track,kind=Signal.signal_type(rec,track),record=rec}
  end
  function R.quote_remove_signal(owner,id,track)
    if R.busy() then return nil,blocked() end
    local why=live_edit_guard(id);if why then return nil,why end
    if protected(id) then return nil,span_msg end
    local d=R.signal_details(id,track)
    if not d or d.owner~=owner then return nil,"Choose your own signal." end
    return budget(owner,{kind="signal_remove",id=id,track=d.track,ids={id},price=prices.clear_signal()})
  end
  function R.quote_flip_signal(owner,id,track)
    if R.busy() then return nil,blocked() end
    local why=live_edit_guard(id);if why then return nil,why end
    if protected(id) then return nil,span_msg end
    local d=R.signal_details(id,track)
    if not d or d.owner~=owner or #d.tds~=1 then return nil,"Choose an owned signal with one head." end
    return budget(owner,{kind="signal_flip",id=id,td=d.tds[1],track=d.track,
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
  local function depot_connect(owner,id,dir,railtype)
    -- Stock GUI auto-connection quotes every connector piece in the
    -- same rail type as the depot; never add a misplaced normal rail.
    if not gauge_allowed(owner,railtype) then return 0 end
    local board=Lab.board(S)
    local read=board.tile
    function board.tile(tile)
      local p=read(tile)
      local t=S.tiles[tile]
      if not p or p.kind~="depot" and (t.level_crossing or t.rail_span_id) then return end
      if p.kind=="rail" and signed(tile) then p.kind="signals" end
      return p
    end
    return Depot.connect(board,id,dir,{auto_remove_signals=false},function(front,track)
      local piece=R.quote_track(owner,front,front,track,false,railtype)
      return piece and R.build(owner,piece)
    end)
  end
  function R.build(owner,plan)
    if not plan or plan.owner~=owner or plan.topology~=S.topology or R.busy() then
      return false,"The railway changed. Select the construction again."
    end
    if plan.price>company(owner).cash then return false,"Your company cannot afford that railway work." end
    for _,id in ipairs(plan.ids or {}) do
      if plan.kind~="depot" then
        local why=live_edit_guard(id);if why then return false,why end
        if protected(id) then return false,span_msg end
      end
    end
    local ok,note
    if plan.kind=="track" then
      -- Physical occupancy and forest density can change without a topology
      -- revision. Requote before applying ANY piece of the drag.
      if plan.preview then
        local fresh,why=quote_pieces(owner,plan.preview,plan.remove,plan.quick_drag,plan.gauge)
        if not fresh then return false,why end
        if fresh.crossing~=plan.crossing or fresh.price~=plan.price or fresh.tree_count~=plan.tree_count or #fresh.ids~=#plan.ids then
          return false,"The railway changed. Select the construction again."
        end
        for i,id in ipairs(fresh.ids) do
          if id~=plan.ids[i] or fresh.pieces[i].result_railtype~=plan.pieces[i].result_railtype then
            return false,"The railway changed. Select the construction again."
          end
        end
        plan=fresh
      end
      for _,piece in ipairs(plan.pieces) do
        if piece.crossing_quote then Sim.apply_crossing_construction(S,piece.crossing_quote)
        else
          if piece.remove_signal then assert(Run.remove_signal(S,owner,piece.id,piece.track)) end
          assert(Lab.commit_piece(S,owner,piece))
        end
      end
      if plan.crossing then
        S.topology=S.topology+1
        Sim.refresh_crossing_construction(S)
      end
      ok,note=true,plan.crossing and "Track laid, including level crossing work." or "Track pieces updated."
    elseif plan.kind=="platform" then
      if not gauge_allowed(owner,plan.gauge) then return false,"This rail type is not available to your company." end
      ok,note=Lab.commit_station(S,owner,plan.ids,plan.axis,plan.combined or plan.area,plan.join,plan.gauge)
    elseif plan.kind=="depot" then
      local fresh,why=R.quote_depot(owner,plan.id,plan.direction,plan.requested_railtype)
      if not fresh then return false,why end
      if fresh.price~=plan.price or fresh.level~=plan.level or fresh.shape~=plan.shape or
          fresh.railtype~=plan.railtype or fresh.rotate~=plan.rotate or fresh.noop~=plan.noop or
          fresh.clear_coast~=plan.clear_coast then
        return false,"The depot site changed. Select the construction again."
      end
      plan=fresh
      if plan.noop then ok,note=true,"Depot already faces that way."
      else ok,note=Lab.commit_depot(S,owner,plan.id,plan.direction,plan.railtype,true,plan.clear_coast) end
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
      local fresh,why=R.quote_flip_signal(owner,plan.id,plan.track)
      if not fresh then return false,why end
      if fresh.td~=plan.td or fresh.locked_record~=plan.locked_record then
        return false,"The signal changed. Inspect it again."
      end
      ok,note=Run.flip_signal(S,owner,plan.id,plan.td)
      if ok then S.topology=S.topology+1 end
    elseif plan.kind=="signal_remove" then
      ok,note=Run.remove_signal(S,owner,plan.id,plan.track)
    else return false,"No railway placement selected." end
    if not ok then return false,note end
    debit(owner,plan.price)
    if plan.kind=="depot" then
      local connections=depot_connect(owner,plan.id,plan.direction,plan.railtype)
      if connections>0 then note=note.." Connected to nearby track." end
      if api.render.raise_bound then api.render.raise_bound(plan.level) end
      if plan.noop and connections==0 then return true,note end
    end
    api.render.update(plan.ids);api.save()
    return true,note
  end
  return R
end
