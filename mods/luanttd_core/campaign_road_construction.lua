-- Validate the normal road gesture, then quote and commit it inside the
-- authoritative Lua VM. Only finite typed values cross the mailbox.
return function(Sim,s,oneway,Bank,host)
  local M={}
  local function valid(id) return type(id)=="number" and id%1==0 and s.tiles[id]~=nil end
  local methods={}
  for _,op in ipairs({"road_station","road_depot","road_bay_pair","clear"}) do methods[op]=true end
  local function plan(player,request)
    if type(request)~="table" or not valid(request.first) then return nil,"INVALID_TILE" end
    local first,last,op=request.first,request.last or request.first,request.tool
    if not valid(last) then return nil,"INVALID_TILE" end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if math.abs(x-u)+math.abs(z-v)>=128 then return nil,"ROAD_DRAG_TOO_LONG" end
    if op=="oneway" then
      if not oneway then return nil,"ONEWAY_REQUIRES_STOCK_ROAD_CLOCK" end
      if request.axis~=0 and request.axis~=1 then return nil,"INVALID_AXIS" end
      return oneway.quote(s,player,first,last,request.axis,{start_half=request.start_half==true,
        end_half=request.end_half==true})
    elseif op=="drag" then
      if request.axis~=0 and request.axis~=1 then return nil,"INVALID_AXIS" end
      return Sim.autoroad_plan(s,player,first,last,request.axis,request.start_half,request.end_half)
    elseif op=="remove" then
      local q,why=Sim.road_remove_plan(s,player,first,last,request.axis,request.start_half==true,request.end_half==true)
      if not q then return nil,Sim.road_removal_error(why) end
      return q
    elseif op=="tram_facility" and first==last then
      local tr=host and host.tram
      if not tr then return nil,"Tramway tools are unavailable in this campaign." end
      local busy=tr.busy_probe and tr.busy_probe() or tr.busy
      local changes,cost=tr.net.plan(s,player,request.kind,{first},request.direction,busy)
      if not changes then return nil,cost end
      local company=s.companies[player]
      if not company or cost>company.cash then return nil,"Not enough cash." end
      for _,c in ipairs(changes) do
        c.tool="tram_facility"
        c.build=c.record.kind
        c.tram_bits=c.record.tram_bits
        c.depot_dir=c.record.dir
        c.road_terminal_level=c.record.terminal_level
      end
      return {changes=changes,cost=cost,facility=request.kind}
    elseif op=="tram_remove" or op=="tram_lay" then
      local tr=host and host.tram
      if not tr then return nil,"Tramway tools are unavailable in this campaign." end
      local planner=op=="tram_lay" and tr.net.drag_plan or tr.net.remove_plan
      local busy=tr.busy_probe and tr.busy_probe() or tr.busy
      local q,why=planner(s,player,request,busy,tr.span_busy)
      if not q then
        local messages={TRAM_FACILITY_PROTECTED="Use the Bulldozer to review the platform or depot.",
          NO_TRAM="No electric tram track was selected.",
          NO_TRAMWAY="There is no tramway in the selected direction.",
          OUTSIDE_PORTAL_BIT_REQUIRED="Click the outside half of the ramp or portal, away from the span.",
          TRAM_NEEDS_FLAT_CLEARANCE="A tram platform or depot needs flat ground.",
          TRAM_SITE_CLEARANCE="Choose a clear site away from overhead or underground structures.",
          PROTECTED_TILE="The requested tile has a protected structure.",
          ALREADY_BUILT="That tram track is already built.",NOT_ENOUGH_MONEY="Not enough cash."}
        return nil,messages[why] or Sim.road_removal_error(why)
      end
      return q
    elseif op=="bend" then
      return Sim.autoroad_bend_plan(s,player,first,last)
    elseif op=="road_waypoint" then
      if request.join~=nil and (type(request.join)~="number" or request.join<1 or request.join%1~=0) then
        return nil,"INVALID_ROAD_GESTURE"
      end
      local q,why=Sim.road_waypoint_plan(s,player,{first=first,last=last,axis=request.axis,
        remove=request.remove==true,join=request.join,separate=request.separate==true})
      if not q then
        local errors={ALREADY_BUILT="This road waypoint is already built.",
          NO_VALID_ROAD_WAYPOINT_AXIS="Start on a straight, ordinary road.",
          WAYPOINT_IN_USE="Wait for the vehicle traveling to this waypoint.",
          WAYPOINT_IN_ORDERS="Remove the waypoint from vehicle orders before removing its last tile.",
          NO_CLEAR_WAYPOINT="Choose an empty road waypoint your company owns.",
          STATION_SPREAD="The waypoint is too wide. Hold E to place a separate waypoint.",
          ADJOINS_MULTIPLE_WAYPOINTS="The drag joins more than one waypoint. Hold E to keep them separate.",
          VEHICLE_IN_THE_WAY="Wait for the road to clear.",
          NO_ROAD="Waypoints need existing road on every tile.",
          FLAT_LAND_REQUIRED="All waypoint tiles need a suitable slope at the same height."}
        return nil,errors[why] or Sim.stock_road_terminal_error(why)
      end
      return q
    elseif op=="stock_stop_remove" then
      local q,why=Sim.stock_road_stop_remove_plan(s,player,first,last)
      if not q then return nil,Sim.stock_road_terminal_error(why) end
      return q
    elseif op=="stock_stop_area" then
      if request.join~=nil and (type(request.join)~="number" or request.join<1 or request.join%1~=0) then
        return nil,"INVALID_ROAD_GESTURE"
      end
      local q,why=Sim.stock_road_stop_area_plan(s,player,first,last,{kind=request.kind,dir=request.direction,
        through=request.through==true,join=request.join,adjacent=request.adjacent==true})
      if not q then return nil,Sim.stock_road_terminal_error(why) end
      return q
    elseif op=="stock_terminal_auto" and first==last then
      if request.join~=nil and (type(request.join)~="number" or request.join<1 or request.join%1~=0) then
        return nil,"INVALID_ROAD_GESTURE"
      end
      local q,why=Sim.auto_road_terminal_plan(s,player,first,request)
      if not q then return nil,Sim.stock_road_terminal_error(why) end
      return q
    elseif op=="stock_terminal" and first==last then
      if request.kind~="depot" and request.kind~="truck" and request.kind~="bus" then
        return nil,"INVALID_ROAD_GESTURE"
      end
      local q,why=Sim.stock_road_terminal_plan(s,player,first,{kind=request.kind,dir=request.direction,through=request.through})
      if not q then return nil,Sim.stock_road_terminal_error(why) end
      return q
    elseif op=="fund_bank" and first==last and Bank then
      local q,why=Bank.plan(s,first)
      if not q then return nil,Bank.reason(why) end
      local changes={}
      for i,id in ipairs(q.clears) do changes[i]={id=id,tool="fund_bank",foundation=q.town} end
      return {cost=q.price,changes=changes,bank=q}
    elseif op=="truck_stop" and first==last then
      if not (s.road_mail and s.road_stock_house_supply) and not Sim.road_coal_active(s)
        and not Sim.road_timber_active(s) and not Sim.road_farm_active(s) and not Sim.road_oil_active(s) and not Sim.road_heavy_active(s) and not Sim.road_bank_active(s) then
        return nil,"No stock mail or freight service in this campaign."
      end
      if s.tiles[first].station then return nil,"Build a new truck stop rather than converting a station." end
      local changes,cost=Sim.plan(s,player,"road_station",{first})
      if not changes then return nil,cost end
      return {changes=changes,cost=cost}
    elseif methods[op] and first==last then
      local changes,cost=Sim.plan(s,player,op,{first})
      if not changes then return nil,cost end
      return {changes=changes,cost=cost}
    end
    return nil,"INVALID_ROAD_GESTURE"
  end
  local function summary(q)
    local ids,parts={},{}
    for i,c in ipairs(q.changes) do
      ids[i]=c.id or c.tile
      parts[i]=table.concat({tostring(ids[i]),tostring(c.build),tostring(c.road_bits),
        tostring(c.h),tostring(c.tool),tostring(c.disallowed),tostring(c.foundation),tostring(c.rail_tracks),tostring(c.railtype),
        c.rail_owner and ("%q"):format(c.rail_owner) or "-",tostring(c.depot_dir),tostring(c.stop_axis),
        tostring(c.road_terminal_level),tostring(c.tram_bits),tostring(c.stop_type),tostring(c.rotate_depot),tostring(c.waypoint),tostring(c.join_stop),tostring(c.joined_tram_station),tostring(c.clear_road_site),tostring(c.clear_road_coast),tostring(c.road_site_cost),tostring(c.road_tree_town)},":")
    end
    if q.span then
      local span=q.span
      parts[#parts+1]=table.concat({span.kind,span.key,span.id,span.other,span.requested,span.action},":")
    end
    if q.ratings then
      local keys={}
      for id in pairs(q.ratings) do keys[#keys+1]=id end
      table.sort(keys)
      for _,id in ipairs(keys) do parts[#parts+1]="town:"..id..":"..q.ratings[id] end
    end
    if q.unfunded then parts[#parts+1]="unfunded:"..tostring(q.first_unfunded) end
    return {tiles=ids,cost=q.cost,topology=s.topology,terrain=s.corner_grid and s.corner_grid.revision,stopped_at=q.stopped_at,stop_reason=q.stop_reason,ticket=table.concat(parts,"/")}
  end
  function M.quote(player,request)
    local q,why=plan(player,request)
    if not q then return nil,why end
    return summary(q)
  end
  local picker
  function M.join_choices(player,request)
    if type(request)~="table" then return nil,"INVALID_ROAD_GESTURE" end
    local waypoint=request.tool=="road_waypoint" and not request.remove
    if not waypoint and request.tool~="stock_stop_area" and
        (request.tool~="stock_terminal_auto" or request.kind=="depot") then return nil,"INVALID_ROAD_GESTURE" end
    local separate={tool=request.tool,first=request.first,last=request.last,kind=request.kind,
      direction=request.direction,axis=request.axis,through=request.through,adjacent=true,separate=true}
    local q,why=plan(player,separate)
    if not q then return nil,why end
    if not picker then
      local path=debug and debug.getinfo(1,"S").source
      local base=path and path:match("^@(.*/)campaign_road_construction%.lua$")
      base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
      picker=dofile(base.."openttd/station_join_picker.lua")
    end
    local area=q.picker_area
    local board={id=Sim.id,xy=Sim.xy,deleted={}}
    for _,st in ipairs(Sim.road_station_retirement().list(s,waypoint and "waypoint" or "station",player)) do
      if not st.tram_only then
        board.deleted[#board.deleted+1]={id=st.id,name="Rebuild "..st.name,tile=st.tile,owner=st.owner,eligible=true}
      end
    end
    function board.station_at(id)
      local t=s.tiles[id]
      if not t then return end
      local st=waypoint and s.stock_road_waypoints and s.stock_road_waypoints[t.road_waypoint_id]
        or not waypoint and s.stations[t.station]
      if not st then return end
      return {id=st.id,name=st.name,tile=st.tile,owner=st.owner,
        spread=st.spread or st.area or {tile=st.tile,w=1,h=1},
        eligible=waypoint or not waypoint and st.mode=="road"
          and not s.tiles[st.tile].road_stop_pair}
    end
    function board.matches(st) return st.eligible end
    local rows={}
    for _,st in ipairs(picker.find(board,area,player,12,true)) do
      rows[#rows+1]=st.new and {name=waypoint and "New waypoint" or "New station"} or
        {id=st.id,name=st.name,tile=st.tile}
    end
    return {choices=rows,cost=q.cost,area=q.picker_area}
  end
  function M.commit(player,request,published,direct)
    local q,why=plan(player,request)
    if not q then return false,why end
    local current=summary(q)
    if request.join_picker_cost~=nil and request.join_picker_cost~=q.cost then
      return false,"ROAD_QUOTE_CHANGED"
    end
    -- A deliberate placement can arrive before a speculative preview.
    -- Recompute inside the owner; if the player saw a price/footprint,
    -- never silently replace it. Unrelated changes do not spoil an
    -- otherwise identical direct action.
    if not (direct and published==nil) then
      if type(published)~="table" or published.cost~=current.cost or published.ticket~=current.ticket
        or published.stopped_at~=current.stopped_at or published.stop_reason~=current.stop_reason or (not direct and
          (published.topology~=current.topology or published.terrain~=current.terrain)) then
        return false,"ROAD_QUOTE_CHANGED"
      end
    end
    local first=request.first
    if request.tool=="oneway" then
      local ok,cost,ids=oneway.commit(s,player,q)
      if not ok then return false,cost end
      local note=("%d road tiles updated for $%d."):format(#ids,cost)
      if #q.skipped>0 then note=note..(" %d skipped."):format(#q.skipped) end
      return true,note,ids
    elseif request.tool=="drag" or request.tool=="bend" then
      return Sim.apply_road_construction(s,player,q)
    elseif request.tool=="stock_stop_remove" then
      return Sim.apply_road_stop_remove(s,player,q)
    elseif request.tool=="road_waypoint" then
      return Sim.apply_road_waypoint(s,player,q)
    elseif q.span and (request.tool=="tram_lay" or request.tool=="tram_remove") then
      return host.tram.net.apply_span(s,player,q,host.tram.span_busy)
    elseif request.tool=="tram_lay" then
      return host.tram.net.apply_drag(s,player,q)
    elseif request.tool=="tram_facility" then
      return host.tram.net.apply_facility(s,player,q)
    elseif request.tool=="tram_remove" then
      return host.tram.net.apply_remove(s,player,q)
    elseif request.tool=="remove" then
      return Sim.apply_road_removal(s,player,q)
    elseif request.tool=="fund_bank" then
      local bank,ids=Bank.execute(s,player,first,q.bank)
      if not bank then return false,Bank.reason(ids) end
      return true,("Bank founded for $%d."):format(q.cost),ids
    elseif request.tool=="truck_stop" then
      local ok,note,ids=Sim.build_truck_stop(s,player,first)
      if ok then
        local st=s.stations[s.tiles[first].station]
        st.freight_art=true;st.coal_art=Sim.road_coal_active(s) or nil
        if Sim.road_bits(s,first)==0 then note="Truck stop built. Connect it to the road before ordering trucks." end
      end
      return ok,note,ids
    end
    return Sim.apply_road_construction(s,player,q)
  end
  return M
end
