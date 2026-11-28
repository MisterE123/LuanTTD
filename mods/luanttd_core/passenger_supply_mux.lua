-- SPDX-License-Identifier: GPL-2.0-only
-- Bridge one OpenTTD 14.1 house tile-loop event to one station contest.
-- Keep the road and pilot save schemas; no second source or parallel
-- allocation pass is allowed while the mounted source owns this event.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local sector=dofile(mod.."/catchment_sectors.lua")
local Stats=dofile(mod.."/openttd/town_cargo_stats.lua")
return function(Sim,Catchment,Packets,RoadRating,StockRating)
  local M={}
  local geometry=setmetatable({},{__mode="k"})
  local function tile_key(e) return e.x..":"..e.y end
  local function append(batch,e)
    batch.events[#batch.events+1]=e
    batch.by_tile[tile_key(e)]=#batch.events
  end
  local function batch_at(tick)
    return {tick=tick,events={},by_tile={},next=1}
  end
  local function ledger(s)
    local g=s.stock_passenger_mux
    if not g then
      g={version=2};s.stock_passenger_mux=g
    end
    if g.version==1 then
      -- Earlier private saves buffered one house. Preserve both a
      -- waiting event and the most recent acknowledged receipt.
      if g.pending then
        local event=g.pending
        g.pending=batch_at(event.tick);append(g.pending,event)
      end
      if g.consumed then
        g.receipt=batch_at(g.consumed.tick);append(g.receipt,g.consumed)
        g.receipt.next=2
      end
      g.version=2
    end
    assert(g.version==2,"Unsupported passenger source ledger")
    return g
  end
  local function matches(batch,e)
    local prior=batch.events[batch.by_tile[tile_key(e)]]
    return prior and prior.amount==e.amount and prior.town==e.town and prior.source==e.source and prior.source_type==e.source_type and prior.area==e.area
  end

  -- RunTileLoop can visit many producing houses on one absolute tick.
  -- Preserve actual visit order (not XY, town or traversal via pairs).
  -- There is one passenger emission per visited house, independent of
  -- mail. Arrays and tile keys survive Lua save/reload without aliasing.
  function M.capture(s,amount,x,y,house,tick)
    assert(type(tick)=="number" and tick>=0 and tick==math.floor(tick)
      and type(amount)=="number" and amount>0 and amount==math.floor(amount),"Invalid stock house event")
    local g=ledger(s)
    local e={tick=tick,x=x,y=y,amount=amount,town=house.town,source=house.source,source_type=house.source_type,area=house.area}
    if g.receipt and tick<=g.receipt.tick then
      if tick==g.receipt.tick then
        assert(matches(g.receipt,e),"Conflicting or late house event at an already consumed tick")
      end
      return false
    end
    local pending=g.pending
    if not pending then
      pending=batch_at(tick);g.pending=pending
    end
    assert(pending.tick==tick,"Different passenger tick before the pending batch was consumed")
    if pending.by_tile[tile_key(e)] then
      assert(matches(pending,e),"Conflicting stock passenger emission for this tile and tick")
      return false
    end
    assert(pending.next==1,"New house emission arrived after consumption began")
    append(pending,e)
    return true
  end

  -- Passed as Town.day's third argument. Presence of this callback
  -- replaces legacy road distribution instead of observing it.
  M.town_hooks={passenger=M.capture}

  local function is_bus(st) return st.mode=="road" and st.stop_type~="truck" end
  local function station_key(ctx,kind,st)
    local id=ctx.station_id(kind,st)
    return assert(type(id)=="number" and id>=0 and id<0xFFFE and id==math.floor(id) and id,
      "Each physical station needs its single global numeric StationID")
  end
  local function view_geometry(st,key,tiles,ctx)
    local c=geometry[st]
    if not c or c.global_key~=key or c.width~=ctx.width or c.height~=ctx.height or
        c.modified~=ctx.modified or c.source_tiles~=(tiles or st.tiles) or c.road_tile~=st.tile then
      c=Catchment.build({id=st.id,tiles=tiles or st.tiles},ctx.width,ctx.height,ctx.modified)
      c.source_tiles,c.road_tile,c.modified,c.global_key=tiles or st.tiles,st.tile,ctx.modified,key
      geometry[st]=c
    end
    return c
  end

  local function each_station(s,service,ctx,add)
    local native=service and service.stations or {}
    for _,st in pairs(native) do
      if not ctx.station_active or ctx.station_active(st) then add("service",st) end
    end
    for _,st in pairs(s.stations) do
      if is_bus(st) then
        local x,y=Sim.xy(st.tile)
        local shared_id=ctx.road_alias and ctx.road_alias(st)
        if shared_id~=nil then
          local shared=assert(native[shared_id],"Missing canonical rail/dock station for bus alias")
          assert(st.owner==shared.owner and (st.id==shared.id or shared.joined_road==st.id)
            and station_key(ctx,"road",st)==station_key(ctx,"service",shared),
            "Road alias must use the same station ownership and StationID")
          assert(st.stock==shared.stock and st.passenger_rating_state==shared.passenger_rating_state
              and (st.loading_order==shared.loading_order or shared.joined_road==st.id),
            "Road alias must already point at the canonical service queue, rating and loading order")
          local part
          for _,tile in ipairs(shared.tiles) do
            if tile.kind=="bus" and tile.x==x-1 and tile.y==y-1 and
              (tile.station==nil or tile.station==shared.id) then part=true;break end
          end
          assert(part,"Canonical station missing the aliased physical bus tile")
        else
          add("road",st,Sim.road_stop_tiles(st))
        end
      end
    end
  end

  -- Town events near a station must still use the exact union of its
  -- facility squares. This index only picks coarse candidates, with no
  -- changes to town rights, active ratings, packet math, or tie order.
  local buckets_by_context=setmetatable({},{__mode="k"})
  local function index_for(s,service,ctx)
    local q=buckets_by_context[ctx]
    if q and q.s==s and q.native==(service and service.stations) and q.topology==s.topology then return q.index end
    local index=sector(ctx.width,ctx.height)
    each_station(s,service,ctx,function(kind,st,tiles)
      local key=station_key(ctx,kind,st)
      local c=view_geometry(st,key,tiles,ctx)
      if c.bounds then index.add(c.bounds,{kind=kind,station=st,key=key,coverage=c}) end
    end)
    q={s=s,native=service and service.stations,topology=s.topology,index=index}
    buckets_by_context[ctx]=q
    return index
  end

  local function gather(s,service,e,ctx)
    local stations,covers,sinks,goods_by_key={},{},{},{}
    local function add(kind,st,key,c)
      if not Catchment.covers_area(c,e.x,e.y,e.area,e.area) then return end
      assert(not sinks[key],"Duplicate global StationID; mount a shared station as a single queue")
      local town=ctx.station_town and ctx.station_town(kind,st) or st.town
      if town==nil and kind=="road" then town=st.site end
      stations[#stations+1]={id=key,owner=st.owner,town=town}
      covers[key],sinks[key]=c,{st=st,kind=kind}
      assert(st.owner~=nil,"Missing station owner")
      if kind=="road" then RoadRating.status(s,st) end
      goods_by_key[key]=assert(st.passenger_rating_state,"Missing station passenger rating")
    end
    if ctx.index_passenger_catchments then
      local index=index_for(s,service,ctx)
      for _,row in ipairs(index.query(e.x,e.y,e.area)) do
        local entry=row.value
        add(entry.kind,entry.station,entry.key,entry.coverage)
      end
    else
      each_station(s,service,ctx,function(kind,st,tiles)
        local key=station_key(ctx,kind,st)
        add(kind,st,key,view_geometry(st,key,tiles,ctx))
      end)
    end
    return stations,covers,sinks,goods_by_key
  end

  -- Exact source packet merge for newly produced manual-distribution cargo.
  -- Origin initially refers to the sink's local station ID because its
  -- loading runtime owns that queue; canonical IDs only order competition.
  local function generated(st,units,e)
    local source=e.source or e.town
    local kind=e.source_type or "town"
    local q=st.stock.passenger
    if not q then q={};st.stock.passenger=q end
    for i=#q,1,-1 do
      local p=q[i]
      local own=p.origin_station==st.id or st.stock_station_id~=nil and p.stock_origin_station==st.stock_station_id
      if own and p.origin_tile==nil and p.age==0 and
          (p.source_type or "town")==kind and p.source==source and p.units+units<=65535 then
        p.units,p.source_type=p.units+units,kind
        return
      end
    end
    q[#q+1]={units=units,source=source,source_type=kind,origin_station=st.id,stock_origin_station=st.stock_station_id,age=0}
  end

  local function consume_event(s,service,e,ctx,result)
    local candidates,covers,sinks,goods=gather(s,service,e,ctx)
    local allotment=Catchment.allocate(e.amount,candidates,covers,"passenger",e.x,e.y,
      function(st) return goods[st.id] end,{select_goods=ctx.select_goods,
        neutral_owner=ctx.neutral_owner,town_rights=ctx.town_rights,area=e.area})
    local total=0
    for _,entry in ipairs(allotment) do
      local destination=sinks[entry.st.id]
      local st=destination.st
      local units=Packets.whole_units(st,entry.fixed)
      if units>0 then
        generated(st,units,e)
        if destination.kind=="road" then RoadRating.generated(s,st,units)
        else
          StockRating.observe_waiting(st.passenger_rating_state,units)
          if ctx.airport_new_cargo then ctx.airport_new_cargo(st) end
        end
        total=total+units
      end
      result[#result+1]={station=entry.st.id,kind=destination.kind,
        local_id=st.id,fixed=entry.fixed,units=units}
    end
    Stats.supply(s,e,"passenger",0,total)
    return total
  end

  -- Airport callbacks consume stock RNG within the house tile command,
  -- before returning to the landscape loop or rolling the mail amount.
  -- Do not buffer those passenger allocations until vehicle processing.
  function M.emit(s,service,ctx,amount,x,y,house,tick)
    return consume_event(s,service,{
      tick=tick,x=x,y=y,amount=amount,town=house.town,source=house.source,
      source_type=house.source_type,area=house.area,
    },ctx,{})
  end

  -- Call from PassengerService.pre_motion_tick's ctx.production, after
  -- station rating small ticks for both modes and before either loader.
  -- Save the road world, this ledger and service state together.
  function M.consume(s,service,tick,ctx)
    local g=ledger(s)
    local pending=g.pending
    if not pending or pending.tick>tick then return 0,{} end
    assert(pending.tick==tick,"A generated house batch must be consumed on its own stock tick")
    assert(not g.receipt or g.receipt.tick<pending.tick,"Duplicate pending passenger batch")
    local total,result=0,{}
    for i=pending.next,#pending.events do
      total=total+consume_event(s,service,pending.events[i],ctx,result)
      pending.next=i+1
    end
    -- Keep the original recent-event summary for diagnostics. Retain the
    -- complete last receipt so any house on that tick can be retried
    -- without crediting its queue or rerunning the contest.
    g.consumed,g.receipt,g.pending=pending.events[#pending.events],pending,nil
    return total,result
  end

  return M
end
