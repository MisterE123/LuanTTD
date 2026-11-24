-- SPDX-License-Identifier: GPL-2.0-only
-- Bridge one OpenTTD 14.1 house tile-loop event to one station contest.
-- Keep the road and pilot save schemas; no second source or parallel
-- allocation pass is allowed while the mounted source owns this event.
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
    return prior and prior.amount==e.amount and prior.town==e.town
  end

  -- RunTileLoop can visit many producing houses on one absolute tick.
  -- Preserve actual visit order (not XY, town or traversal via pairs).
  -- There is one passenger emission per visited house, independent of
  -- mail. Arrays and tile keys survive Lua save/reload without aliasing.
  function M.capture(s,amount,x,y,house,tick)
    assert(type(tick)=="number" and tick>=0 and tick==math.floor(tick)
      and type(amount)=="number" and amount>0 and amount==math.floor(amount),"Invalid stock house event")
    local g=ledger(s)
    local e={tick=tick,x=x,y=y,amount=amount,town=house.town}
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

  local function gather(s,service,e,ctx)
    local stations,covers,sinks,goods_by_key={},{},{},{}
    local native=service and service.stations or {}
    local function add(kind,st,tiles)
      local key=station_key(ctx,kind,st)
      local c=view_geometry(st,key,tiles,ctx)
      if not Catchment.contains(c,e.x,e.y) then return end
      assert(not sinks[key],"Duplicate global StationID; mount a shared station as a single queue")
      local town=ctx.station_town and ctx.station_town(kind,st) or st.town
      if town==nil and kind=="road" then town=st.site end
      stations[#stations+1]={id=key,owner=st.owner,town=town}
      covers[key],sinks[key]=c,{st=st,kind=kind}
      assert(st.owner~=nil,"Missing station owner")
      if kind=="road" then RoadRating.status(s,st) end
      goods_by_key[key]=assert(st.passenger_rating_state,"Missing station passenger rating")
    end
    for _,st in pairs(native) do
      if not ctx.station_active or ctx.station_active(st) then add("service",st) end
    end
    for _,st in pairs(s.stations) do
      if is_bus(st) then
        local x,y=Sim.xy(st.tile)
        local shared_id=ctx.road_alias and ctx.road_alias(st)
        if shared_id~=nil then
          local shared=assert(native[shared_id],"Missing canonical rail/dock station for bus alias")
          assert(st.owner==shared.owner and st.id==shared.id and station_key(ctx,"road",st)==station_key(ctx,"service",shared),
            "Road alias must use the same station ownership and StationID")
          assert(st.stock==shared.stock and st.passenger_rating_state==shared.passenger_rating_state
              and st.loading_order==shared.loading_order,
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
    return stations,covers,sinks,goods_by_key
  end

  -- Exact source packet merge for newly produced manual-distribution cargo.
  -- Origin initially refers to the sink's local station ID because its
  -- loading runtime owns that queue; canonical IDs only order competition.
  local function generated(st,units,town)
    local q=st.stock.passenger
    if not q then q={};st.stock.passenger=q end
    for i=#q,1,-1 do
      local p=q[i]
      if p.origin_station==st.id and p.origin_tile==nil and p.age==0 and
          (p.source_type==nil or p.source_type=="town") and p.source==town and p.units+units<=65535 then
        p.units,p.source_type=p.units+units,"town"
        return
      end
    end
    q[#q+1]={units=units,source=town,source_type="town",origin_station=st.id,age=0}
  end

  local function consume_event(s,service,e,ctx,result)
    local candidates,covers,sinks,goods=gather(s,service,e,ctx)
    local allotment=Catchment.allocate(e.amount,candidates,covers,"passenger",e.x,e.y,
      function(st) return goods[st.id] end,{select_goods=ctx.select_goods,
        neutral_owner=ctx.neutral_owner,town_rights=ctx.town_rights})
    local total=0
    for _,entry in ipairs(allotment) do
      local destination=sinks[entry.st.id]
      local st=destination.st
      local units=Packets.whole_units(st,entry.fixed)
      if units>0 then
        generated(st,units,e.town)
        if destination.kind=="road" then RoadRating.generated(s,st,units)
        else StockRating.observe_waiting(st.passenger_rating_state,units) end
        total=total+units
      end
      result[#result+1]={station=entry.st.id,kind=destination.kind,
        local_id=st.id,fixed=entry.fixed,units=units}
    end
    return total
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
