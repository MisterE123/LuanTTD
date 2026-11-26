-- SPDX-License-Identifier: GPL-2.0-only
-- First safe host mount for pinned OpenTTD 14.1 ordinary electrification.
-- Source quote/prices belong to rail_types.lua. The current native pilot
-- cannot atomically retarget an active train's reservations during work.
local base=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
return function(Sim,Terrain,Track,RailTypes,Spans)
  local R={FIELD="rail_type"}
  local Turnout=dofile(base.."rail_turnout_wire.lua")(Sim,Track,dofile(base.."openttd/rail_wire_mask.lua")(Track))
  local tickets=setmetatable({},{__mode="k"})
  local function int(n,lo,hi)
    return type(n)=="number" and n%1==0 and n>=lo and n<=hi
  end
  local function copy(t)
    local a={}
    for i,v in ipairs(t) do a[i]=v end
    return a
  end
  local function maps(s,key)
    local t=s[key]
    return type(t)=="table" and t or nil
  end
  local function lookup(s,k,id)
    local t=maps(s,k)
    return t and t[id]
  end
  local function tile(s,id)
    return int(id,1,Sim.W*Sim.H) and lookup(s,"tiles",id) or nil
  end
  local function rail_type(t)
    if t.rail_type==nil and (t.railtype==nil or t.railtype==0) then return 0 end
    local r=t.rail_type
    if (r==0 or r==1) and (t.railtype==nil or t.railtype==r) then return r end
  end
  function R.tile_type(s,id)
    local t=tile(s,id)
    if t and t.rail_tracks and t.build=="stock_rail" then return rail_type(t) end
  end
  local piece={[1]=Track.X,[2]=Track.Y,[4]=Track.UPPER,[8]=Track.LOWER,[16]=Track.LEFT,[32]=Track.RIGHT}
  local function shape(s,id)
    if not s.corner_grid then return end
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function adjacent(id,dir)
    return Sim.adjacent(id,4-dir)
  end
  local function structure(s,id,t)
    return (Sim.rail_span_protected and Sim.rail_span_protected(s,id)) or
      t.rail_span_id or t.level_crossing or t.road_bridge_id or t.road_tunnel_id or t.tunnel_id or
      lookup(s,"bridge_above",id) or lookup(s,"tunnel_below",id) or lookup(s,"aqueduct_above",id) or
      lookup(s,"rail_bridge_above",id) or lookup(s,"rail_tunnel_below",id)
  end
  local function physical(s,ctx)
    local blocked,owned_runs={},{}
    local priority={RAIL_ROUTE_ACTIVE=1,RAIL_RESERVED=2,RAIL_OCCUPIED=3}
    local function busy(id,why)
      if not int(id,1,Sim.W*Sim.H) then return nil end
      if (priority[blocked[id]] or 0)<priority[why] then blocked[id]=why end
      return true
    end
    -- The simple platform pilot and free-moving survey have no persistent
    -- consist occupancy index; never guess at their reserved geometry.
    if s.stock_rail_run then return nil,"RAIL_SURVEY_ACTIVE" end
    if ctx.is_clear~=nil then
      if type(ctx.is_clear)~="function" then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
      local clear=ctx.is_clear(s)
      if clear~=true then return nil,clear==false and "RAIL_SURVEY_ACTIVE" or "RAIL_OCCUPANCY_UNKNOWN" end
    end
    local dispatch=s.stock_rail_dispatch
    if dispatch~=nil then
      if type(dispatch)~="table" or type(dispatch.runs)~="table" or type(dispatch.life)~="table" or
          type(dispatch.life.bits)~="table" or type(dispatch.life.claims)~="table" or
          type(dispatch.signals)~="table" or type(dispatch.signals.records)~="table" then
        return nil,"RAIL_OCCUPANCY_UNKNOWN"
      end
      for id,bits in pairs(dispatch.life.bits) do
        if not int(bits,0,63) or bits~=0 and not busy(id,"RAIL_RESERVED") then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
      end
      for id,tracks in pairs(dispatch.life.claims) do
        if type(tracks)~="table" or next(tracks) and not busy(id,"RAIL_RESERVED") then
          return nil,"RAIL_OCCUPANCY_UNKNOWN"
        end
      end
      for _,run in pairs(dispatch.runs) do
        local parts=type(run)=="table" and type(run.consist)=="table" and run.consist.parts
        if type(parts)~="table" or #parts==0 then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
        if run.fleet_id then owned_runs[run.fleet_id]=true end
        for _,p in ipairs(parts) do
          if type(p)~="table" or not busy(p.tile,"RAIL_OCCUPIED") or
              p.draw_tile and not busy(p.draw_tile,"RAIL_OCCUPIED") then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
        end
        -- The production runner's already accepted path is not retargeted
        -- by this limited workbench, even on a currently empty tile ahead.
        local function ordered(route)
          if not route then return true end
          if type(route)~="table" then return false end
          for _,step in ipairs(route) do
            if type(step)~="table" or not busy(step.tile,"RAIL_ROUTE_ACTIVE") then return false end
          end
          return true
        end
        if not ordered(run.route) or run.paired and
            (type(run.paired)~="table" or not ordered(run.paired.second_leg)) then
          return nil,"RAIL_OCCUPANCY_UNKNOWN"
        end
      end
    end
    if s.stock_rail_fleet~=nil then
      local fleet=s.stock_rail_fleet
      local units=type(fleet)=="table" and fleet.units
      if type(units)~="table" then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
      for _,u in pairs(units) do
        if type(u)~="table" or u.status~="depot" and u.status~="dispatched" then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
        if u.status=="depot" and not busy(u.depot,"RAIL_OCCUPIED") then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
        if u.status=="dispatched" and not owned_runs[u.id] then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
      end
    end
    for _,u in pairs(s.fleet or {}) do
      local model=type(u)=="table" and Sim.vehicles[u.engine]
      if model and model.mode=="rail" then
        if not busy(Sim.position(s,u),"RAIL_OCCUPIED") then return nil,"RAIL_OCCUPANCY_UNKNOWN" end
      end
    end
    return blocked
  end
  local function classify(s,id,t)
    if t.build~="stock_rail" or t.station or t.depot_dir or t.terrain=="water" or t.stock_void or
        t.site or t.house or t.wood or t.tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or
        t.road_bits and t.road_bits~=0 then return nil,"UNKNOWN_RAIL_PLACEMENT" end
    local r=rail_type(t)
    if r==nil then return nil,"UNSUPPORTED_RAILTYPE_CONVERSION" end
    local kind,tk="rail",piece[t.rail_tracks]
    local turnout=tk==nil and Turnout.supported(t.rail_tracks)
    if tk==nil and not turnout then return nil,"SINGLE_RAIL_PIECE_REQUIRED" end
    local sl,base=shape(s,id)
    if sl==nil then return nil,"NEEDS_SHARED_CORNERS" end
    if sl~=0 then
      if not turnout or Track.foundation(sl,t.rail_tracks)~="leveled" then return nil,"FLAT_RAIL_REQUIRED" end
      base=base+1
    end
    if t.rail_station_id~=nil and t.rail_depot_dir~=nil then return nil,"UNKNOWN_RAIL_PLACEMENT" end
    local dispatch=maps(s,"stock_rail_dispatch")
    local record=dispatch and dispatch.signals and dispatch.signals.records and dispatch.signals.records[id]
    if turnout and (record or t.signal or t.rail_station_id or t.rail_depot_dir~=nil or t.rail_waypoint_id) then
      return nil,"SINGLE_RAIL_PIECE_REQUIRED"
    end
    if t.rail_station_id~=nil then
      if (tk~=Track.X and tk~=Track.Y) or t.rail_station_axis~=tk then return nil,"UNKNOWN_RAIL_PLATFORM" end
      if record or t.signal then return nil,"UNKNOWN_RAIL_PLATFORM" end
      kind="station"
    elseif t.rail_depot_dir~=nil then
      if not int(t.rail_depot_dir,0,3) or tk~=t.rail_depot_dir%2 then return nil,"UNKNOWN_RAIL_DEPOT" end
      if record or t.signal then return nil,"UNKNOWN_RAIL_DEPOT" end
      kind="depot"
    elseif record then
      if type(record)~="table" or not int(record.present_signals,1,15) then return nil,"UNKNOWN_RAIL_SIGNAL" end
      local mask=(tk==Track.LOWER or tk==Track.RIGHT) and 3 or 12
      if Track.intersect(record.present_signals,mask)~=record.present_signals then return nil,"UNKNOWN_RAIL_SIGNAL" end
      kind="signals"
    elseif t.signal then return nil,"UNKNOWN_RAIL_SIGNAL" end
    return {kind=kind,trackbits=t.rail_tracks,track=tk,owner=t.owner,railtype=r,
      station=t.rail_station_id,axis=t.rail_station_axis,dir=t.rail_depot_dir,base=base}
  end
  local function platform(s,first,owner,selection,r)
    local st=int(first.station,1,2^31-1) and lookup(s,"stock_rail_stations",first.station)
    if not st or st.id~=first.station or st.owner~=owner or st.axis~=first.axis or type(st.tiles)~="table" or
        #st.tiles<1 or #st.tiles>7 then return nil,"UNKNOWN_RAIL_PLATFORM" end
    local prior,seen=nil,{}
    for _,id in ipairs(st.tiles) do
      local t=tile(s,id)
      if not t or t.owner~=owner or t.rail_station_id~=st.id or t.rail_station_axis~=st.axis or
          seen[id] or prior and adjacent(prior,st.axis==Track.X and Track.SW or Track.SE)~=id then
        return nil,"UNKNOWN_RAIL_PLATFORM"
      end
      local b,class_error=classify(s,id,t)
      if not b then return nil,class_error,id end
      if b.railtype~=r then return nil,"MIXED_PLATFORM_UNSUPPORTED",id end
      if not selection[id] then return nil,"COMPLETE_PLATFORM_REQUIRED",id end
      prior,seen[id]=id,true
    end
    return seen
  end
  local function enclosure(s,id,t)
    local front,rear=adjacent(id,t.dir),adjacent(id,Track.reverse_side(t.dir))
    local portal,back=tile(s,front),tile(s,rear)
    -- A real portal needs a known connecting, same-gauge ordinary tile
    -- on its front; an occupied or intentionally tied-in rear is not an
    -- enclosed depot construction handled by this host.
    if not portal or portal.owner~=t.owner or not portal.rail_tracks or structure(s,front,portal) then return false end
    local p=classify(s,front,portal)
    if not p or p.kind=="depot" or p.base~=t.base or
        Track.intersect(Track.trackdirs(p.trackbits),Track.reachable(t.dir))==0 then return false end
    if back and back.rail_tracks and
        (not int(back.rail_tracks,1,63) or
          Track.intersect(Track.trackdirs(back.rail_tracks),Track.reachable(Track.reverse_side(t.dir)))~=0) then return false end
    if back and (back.rail_span_id or back.level_crossing) then return false end
    return true
  end
  local function flags(ctx,s,owner)
    if type(ctx)~="table" or type(ctx.availability)~="function" then return nil,"RAILTYPE_AVAILABILITY_UNKNOWN" end
    local mask,hidden,disabled=ctx.availability(s,owner)
    if not int(mask,0,15) or not int(hidden or 0,0,15) or
        disabled~=nil and type(disabled)~="boolean" then return nil,"RAILTYPE_AVAILABILITY_UNKNOWN" end
    return mask,nil,hidden,disabled
  end
  local legacy_build={rail=true,rail_depot=true,rail_station=true,rail_bridge=true,rail_tunnel=true,signal=true}
  local function quote(s,owner,ids,target,ctx)
    if type(owner)~="string" or owner=="" or type(ids)~="table" or not (#ids>0) or
        type(s.topology)~="number" or not s.corner_grid or (target~=0 and target~=1) then return nil,"INVALID_PARAMETER" end
    local c=lookup(s,"companies",owner)
    if not c or type(c.cash)~="number" or type(c.expense)~="number" or type(c.month_exp)~="number" then
      return nil,"OWN_COMPANY_REQUIRED"
    end
    local mask,err,hidden,disabled=flags(ctx,s,owner)
    if mask==nil then return nil,err end
    if not RailTypes.available(target,mask,hidden) then return nil,"RAILTYPE_NOT_AVAILABLE" end
    local selected={}
    for i in pairs(ids) do
      if not int(i,1,#ids) then return nil,"INVALID_PARAMETER" end
    end
    for i=1,#ids do
      local id=ids[i]
      if not tile(s,id) or selected[id] then return nil,"INVALID_PARAMETER",id end
      selected[id]=true
    end
    local blocked,e=physical(s,ctx)
    if not blocked then return nil,e end
    local rec,platforms,sig={},{},{}
    local spans={}
    local function safe_span(id)
      if not Spans or type(ctx.span_art_ready)~="function" then return nil,"PROTECTED_RAIL_STRUCTURE" end
      local p,e=Spans.electric_record(s,id)
      if not p then return nil,e end
      if ctx.span_art_ready(s,p)~=true then return nil,"PROTECTED_RAIL_STRUCTURE" end
      if not rec[id] then rec[id]=p end
      local mate,why=Spans.electric_record(s,p.other)
      if not mate then return nil,why end
      if not rec[p.other] then rec[p.other]=mate end
      if p.owner==owner and p.railtype~=target and not (disabled and p.railtype==1 and target==0)
          and not spans[p.span_id] then
        if not RailTypes.is_compatible(p.railtype,target) then return nil,"UNSUPPORTED_RAILTYPE_CONVERSION" end
        local footprint={p.start}
        for _,m in ipairs(p.middle) do footprint[#footprint+1]=m end
        footprint[#footprint+1]=p.finish
        for _,where in ipairs(footprint) do
          if blocked[where] then return nil,blocked[where],where end
          local element=s.tiles[where]
          if element and (element.rail_reserved and element.rail_reserved~=0 or
              element.reserved_rail and element.reserved_rail~=0) then return nil,"RAIL_RESERVED",where end
        end
        spans[p.span_id]=footprint
        sig[#sig+1]=table.concat({"span",p.span_id,p.kind,p.axis,p.railtype,table.concat(footprint,",")},":")
      end
      return true
    end
    for _,id in ipairs(ids) do
      local t=tile(s,id)
      -- Opt-in only: a recognized span is a different layer and always
      -- routes through its explicit portal record. Leave the default
      -- flat workbench and its protection rules unchanged.
      if t.rail_span_id then
        local ok,why,where=safe_span(id)
        if not ok then return nil,why,where or id end
      elseif structure(s,id,t) then
        local bridge=lookup(s,"rail_bridge_above",id)
        local tunnel=lookup(s,"rail_tunnel_below",id)
        local p=(bridge or tunnel) and lookup(s,"stock_rail_spans",bridge or tunnel)
        local candidate=p and Spans and Spans.electric_record(s,p.start)
        -- If the selected middle is plain protected land or water, it
        -- is not a conversion selection. Where the host has ground rail
        -- beneath it, fail closed until independent stacking is mounted.
        if not candidate or type(ctx.span_art_ready)~="function" or
            ctx.span_art_ready(s,candidate)~=true or t.rail_tracks or t.level_crossing or
            t.rail_type~=nil or t.build=="stock_rail" or legacy_build[t.build] then return nil,"PROTECTED_RAIL_STRUCTURE",id end
      elseif t.rail_tracks or t.build=="stock_rail" or t.rail_station_id~=nil or t.rail_depot_dir~=nil then
        if not t.rail_tracks then return nil,"UNKNOWN_RAIL_PLACEMENT",id end
        local r=rail_type(t)
        if r==nil then return nil,"UNSUPPORTED_RAILTYPE_CONVERSION",id end
        if t.owner~=owner or r==target or disabled and r==1 and target==0 then
          rec[id]={owner=t.owner,railtype=r,kind="rail"}
        else
          if not RailTypes.is_compatible(r,target) then return nil,"UNSUPPORTED_RAILTYPE_CONVERSION",id end
          local b,why=classify(s,id,t)
          if not b then return nil,why,id end
          if blocked[id] then return nil,blocked[id],id end
          for _,key in ipairs{"rail_reserved","reserved_rail"} do
            local reserved=t[key]
            if reserved~=nil and type(reserved)~="boolean" and not int(reserved,0,63) then
              return nil,"RAIL_OCCUPANCY_UNKNOWN",id
            end
            if reserved and reserved~=0 then return nil,"RAIL_RESERVED",id end
          end
          if b.kind=="station" then
            if not platforms[b.station] then
              local seen,reason,where=platform(s,b,owner,selected,r)
              if not seen then return nil,reason,where or id end
              platforms[b.station]=seen
            end
            if not platforms[b.station][id] then return nil,"UNKNOWN_RAIL_PLATFORM",id end
          elseif b.kind=="depot" and not enclosure(s,id,b) then
            return nil,"ENCLOSED_RAIL_DEPOT_REQUIRED",id
          end
          rec[id]=b
          sig[#sig+1]=table.concat({id,b.kind,b.railtype,b.trackbits,b.base,b.station or "",b.dir or ""},":")
        end
      elseif t.rail_type~=nil or legacy_build[t.build] then return nil,"UNKNOWN_RAIL_PLACEMENT",id end
    end
    if ctx.prices~=nil and type(ctx.prices)~="function" then return nil,"RAIL_PRICE_UNKNOWN" end
    local price=ctx.prices and ctx.prices(s,owner) or nil
    if ctx.prices and (type(price)~="table" or not int(price.rail,1,2^46) or
        type(price.clear_rail)~="number" or price.clear_rail%1~=0 or math.abs(price.clear_rail)>2^46) then
      return nil,"RAIL_PRICE_UNKNOWN"
    end
    local plan,reason,asked=RailTypes.quote_convert({size=Sim.W*Sim.H+1,tile=function(id)return rec[id]end},ids,target,
      {owner=owner,available=mask,hidden=hidden,disable_elrails=disabled,prices=price,cash=c.cash})
    if not plan then return nil,reason,asked end
    plan.span_footprints=spans
    plan.records=rec
    return plan,nil,table.concat(sig,";")
  end
  local function dirty_for(plan)
    local dirty,found={},{}
    local function mark(id) if not found[id] then found[id]=true;dirty[#dirty+1]=id end end
    for _,u in ipairs(plan.updates) do
      local k=plan.records[u.id].span_id
      if k then
        for _,id in ipairs(plan.span_footprints[k]) do mark(id) end
      else mark(u.id) end
    end
    return dirty
  end
  function R.quote(s,owner,ids,target,ctx)
    local plan,why,sig=quote(s,owner,ids,target,ctx)
    if not plan then return nil,why,sig end
    local dirty=dirty_for(plan)
    local ticket={price=plan.cost,cost=plan.cost,owner=owner,target=target,topology=s.topology,
      ids=dirty,skipped=plan.errors}
    tickets[ticket]={s=s,owner=owner,target=target,price=plan.cost,topology=s.topology,
      revision=s.corner_grid.revision,ids=copy(ids),sig=sig}
    return ticket
  end
  function R.commit(s,owner,ticket,ctx)
    local q=tickets[ticket]
    if not q or q.s~=s or q.owner~=owner or q.topology~=s.topology or
        not s.corner_grid or q.revision~=s.corner_grid.revision then return false,"STALE_RAILTYPE_QUOTE" end
    local plan,why,sig=quote(s,owner,q.ids,q.target,ctx)
    if not plan then return false,why,sig end
    if plan.cost~=q.price or sig~=q.sig then return false,"STALE_RAILTYPE_QUOTE" end
    -- All potentially failing checks above. No runtime/render callbacks are
    -- invoked while applying the validated tile/debit/topology transaction.
    local dirty,changed=dirty_for(plan),{}
    for _,u in ipairs(plan.updates) do
      local k=plan.records[u.id].span_id
      if k then
        if not changed[k] then
          local span=s.stock_rail_spans[k]
          span.railtype,span.head.railtype,span.tail.railtype=u.to,u.to,u.to
          changed[k]=true
        end
      else
        local t=s.tiles[u.id]
        t.rail_type,t.railtype=u.to,nil
      end
    end
    local c=s.companies[owner]
    c.cash,c.expense,c.month_exp=c.cash-plan.cost,c.expense+plan.cost,c.month_exp+plan.cost
    s.topology=s.topology+1
    tickets[ticket]=nil
    return true,plan.cost,dirty,{target=q.target,topology=s.topology,infra=plan.infra,skipped=plan.errors}
  end
  return R
end
