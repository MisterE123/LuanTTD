-- SPDX-License-Identifier: GPL-2.0-only
-- Passenger-only, manual OpenTTD 14.1 service adapter for transport pilots.
-- A coupled train has one passenger carriage or two reciprocally
-- powered DMU bodies; a ferry or fixed-wing aircraft has one passenger body. Aircraft mail
-- holds are not mounted; the selected orders are ordinary passenger
-- stops. Existing packet and station kernels own
-- reserve/stage/load/drop/timetable and payment arithmetic. Side effects
-- below are saved; all host geometry, events and hooks are injected.
return function(Catchment,Packets,Income,Rating,Queue,LoadingFactory,BaseTiming)
  local base=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
  local aircraft={}
  for _,row in ipairs(dofile(base.."/openttd/airport_roster.lua").catalog()) do
    aircraft[row.stock_id]={engine=row.stock_id,cap=row.passengers,slice=20,aging=185,wait=20}
  end
  local vessels={}
  local ships=dofile(base.."/openttd/passenger_ship_roster.lua")
  for _,id in ipairs(ships.order) do
    vessels[id]={engine=id,cap=ships.model(id).capacity,slice=10,aging=185,wait=10}
  end
  local S={version=1,stock={
    rail={engine=27,cap=40,slice=5,aging=185,wait=40},
    ship=vessels[206],
    air=aircraft[215],
  }}

  local manley={engine=11,cap=76,slice=5,aging=185,wait=40}
  local manley_coach={engine=11,cap=116,slice=5,aging=185,wait=40}
  function S.stock_for(mode,engine,coach)
    if mode=="ship" and engine then return vessels[engine] end
    if mode=="rail" and engine==11 then return coach and manley_coach or manley end
    if mode=="air" and engine then return aircraft[engine] end
    return S.stock[mode]
  end
  local floor,max=math.floor,math.max
  local active_pulses
  local Loading=LoadingFactory({
    initial=BaseTiming.initial,stock_road_slice=BaseTiming.stock_road_slice,
    can_leave=BaseTiming.can_leave,
    pulse=function(m)
      assert(active_pulses,"Passenger pulse must run within ordered station tick")
      active_pulses[#active_pulses+1]=m
      return BaseTiming.pulse(m)
    end,
  },Packets)

  local DMU=dofile(base.."/openttd/rail_multihead_loading.lua").create(Loading,BaseTiming)

  local function keys(t,predicate)
    local out={}
    for k,v in pairs(t) do
      if not predicate or predicate(v) then out[#out+1]=k end
    end
    table.sort(out)
    return out
  end
  local function goods(st) return st.passenger_rating_state end
  local function town_rights(ctx,town) return ctx.town_rights and ctx.town_rights(town) end
  local function neutral(st,ctx) return ctx.neutral_owner~=nil and st.owner==ctx.neutral_owner end
  local function count(packets)
    local units=0
    for _,p in ipairs(packets) do units=units+p.units end
    return units
  end

  function S.new(seed)
    return {version=S.version,seed=seed,stations={},vehicles={},companies={},towns={}}
  end

  local geometry=setmetatable({},{__mode="k"})
  local function coverage(state,st,ctx)
    local cache=geometry[state]
    if not cache then cache={};geometry[state]=cache end
    local c=cache[st.id]
    if not c or c.footprint~=st.tiles or c.width~=ctx.width or c.height~=ctx.height or c.modified~=ctx.modified then
      c=Catchment.build(st,ctx.width,ctx.height,ctx.modified)
      c.footprint,c.modified=st.tiles,ctx.modified
      cache[st.id]=c
    end
    return c
  end

  function S.refresh_acceptance(state,id,ctx)
    local st=assert(state.stations[id])
    local summary=Catchment.acceptance(coverage(state,st,ctx),"passenger",ctx.house_at)
    st.passenger_acceptance=summary.eighths
    st.always_accept_passengers=summary.always_accepted
    return summary
  end

  -- Canonical station IDs only; a shared station owns one queue and one
  -- loading order. Change the physical footprint through S.footprint.
  function S.station(state,def,ctx)
    assert(type(def.id)=="number" and def.owner~=nil and not state.stations[def.id],"Invalid or duplicate station")
    local st={id=def.id,owner=def.owner,town=def.town,
      stock={passenger={}},loading_order={},passenger_rating_state=Rating.new(),
      rating_phase=def.rating_phase or 0,time_since_load=255,time_since_unload=255,
      tick_index=def.tick_index}
    state.stations[def.id]=st
    S.footprint(state,def.id,def.tiles,ctx)
    return st
  end
  function S.footprint(state,id,tiles,ctx)
    local st=assert(state.stations[id])
    -- Install a fresh reference so a topology edit invalidates geometry.
    local copy={}
    for i,tile in ipairs(tiles) do
      copy[i]={x=tile.x,y=tile.y,kind=tile.kind,station=tile.station}
    end
    st.tiles=copy
    return S.refresh_acceptance(state,id,ctx)
  end

  function S.vehicle(state,def)
    assert(type(def.id)=="number" and def.owner~=nil and not state.vehicles[def.id],"Invalid or duplicate vehicle")
    local stock=assert(S.stock_for(def.mode,def.engine,def.coach),"Only mounted stock passenger bodies")
    assert(type(def.speed)=="number" and type(def.built)=="number",
      "Stock speed-cache units and calendar build year are required")
    local v={id=def.id,owner=def.owner,mode=def.mode,engine=def.engine,cargo="passenger",cached_max_speed=def.speed,
      built=def.built,cargo_age_counter=1,batches={},units=0}
    if def.mode=="rail" then v.total_length=assert(def.length,"Train total length in 1/16-tile units required") end
    if def.mode=="rail" and def.engine==11 then
      assert(v.total_length==(def.coach and 24 or 16),"Invalid Manley-Morel physical formation")
      v.coach=def.coach or nil
      DMU.bodies(v,v.coach)
    elseif def.mode=="rail" and def.passenger_coaches then
      local paired=def.dual_head==true
      assert(def.passenger_coaches>=(paired and 1 or 2) and v.total_length==(def.passenger_coaches+(paired and 2 or 1))*8,
        "Invalid physical railway coach length")
      DMU.coaches(v,def.passenger_coaches)
    end
    state.vehicles[v.id]=v
    return v
  end

  -- Newly produced packets have no loading tile, travelled vector or
  -- feeder claim. Source station bucket scans the entire manual hop
  -- backward when merging, not only the tail.
  local function enqueue_generated(st,units,town)
    local queue=st.stock.passenger
    for i=#queue,1,-1 do
      local p=queue[i]
      if p.origin_station==st.id and p.origin_tile==nil and p.age==0 and
          p.source_type=="town" and p.source==town and p.units+units<=65535 then
        p.units=p.units+units
        return
      end
    end
    queue[#queue+1]={units=units,source=town,source_type="town",origin_station=st.id,age=0}
  end

  function S.produce(state,x,y,amount,town,ctx)
    local live,nearby={},{}
    for _,id in ipairs(ctx.nearby and ctx.nearby(x,y) or keys(state.stations)) do
      local st=state.stations[id]
      if st and not live[id] then
        nearby[#nearby+1]=st
        live[id]=coverage(state,st,ctx)
      end
    end
    local moved=0
    local allocation=Catchment.allocate(amount,nearby,live,"passenger",x,y,goods,{
      neutral_owner=ctx.neutral_owner,town_rights=ctx.town_rights,select_goods=ctx.select_goods,
    })
    for _,entry in ipairs(allocation) do
      local st=entry.st
      local units=Packets.whole_units(st,entry.fixed)
      if units>0 then
        enqueue_generated(st,units,town)
        Rating.observe_waiting(goods(st),units)
        moved=moved+units
      end
    end
    return moved
  end

  function S.waiting(state,id)
    local st=assert(state.stations[id])
    local available=Packets.waiting(st)
    local reserved=0
    for _,vid in ipairs(st.loading_order) do
      reserved=reserved+assert(state.vehicles[vid].load_state).reserved_units
    end
    return available+reserved,available
  end

  local function rating_tick(state,st,tick,ctx)
    local coverage_now=coverage(state,st,ctx)
    if coverage_now.radius==0 then return end
    local phase,events=Rating.advance_clock(st.rating_phase,1)
    st.rating_phase=phase
    if events>0 then
      Rating.increment_station_timers(st)
      local g=goods(st)
      local waiting=Packets.waiting(st)
      local random=function() return (ctx.random_u32 or Queue.random_u32)(state) end
      local r=Catchment.rating_step(st,g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
        select_goods=ctx.select_goods~=false,random_u32=random})
      for _,k in ipairs({"rating","has_rating","time_since_pickup","last_speed","last_age","max_waiting_cargo"}) do g[k]=r[k] end
      if r.drop>0 then
        for sid,retained in pairs(Queue.truncate(st.stock.passenger,waiting,r.drop,random)) do
          local source=state.stations[sid]
          if source then
            local origin=goods(source);origin.max_waiting_cargo=max(origin.max_waiting_cargo,retained)
          end
        end
      end
    end
    if (tick+(st.tick_index or st.id))%250==0 then
      goods(st).accepted_bigtick=nil
      S.refresh_acceptance(state,st.id,ctx)
    end
  end

  local function emit(events,kind,st,v,tick,values)
    local e={kind=kind,station=st.id,vehicle=v.id,mode=v.mode,visit=v.visit,tick=tick,tile=v.cargo_tile,
      part=v.part,role=v.role}
    for k,value in pairs(values or {}) do e[k]=value end
    if events then events[#events+1]=e end
    return e
  end

  local function fare(v,p,ctx)
    -- Stock routing measures the actual *carrying* part's tile (the
    -- carriage or vessel at arrival), not station sign, locomotive,
    -- nominal port tile, straight spline length or arbitrary time ratio.
    local d=Packets.distance(p,v.cargo_tile,ctx.xy)
    return Income.regular(p.units,d,p.age or 0,unpack(Income.temperate.passenger)),d
  end

  local function options(state,tick,ctx,events)
    local function carrier(st,v) return {id=st.id,tile=v.cargo_tile} end
    return {
      gradual=ctx.gradual~=false,feeder_percent=ctx.feeder_percent,consist=DMU,
      accepts=function(st) return st.passenger_acceptance>=8 end,
      can_load=function(st,v)
        return Catchment.may_load(st,v.owner,town_rights(ctx,st.town),ctx.neutral_owner)
      end,
      pickup=function(st,v,p) Packets.pickup(p,carrier(st,v),ctx.xy) end,
      drop=function(st,v,p) Packets.drop(p,carrier(st,v),ctx.xy) end,
      attempt=function(st,v,capacity_left)
        local speed=ctx.speed and ctx.speed(v) or v.cached_max_speed
        Catchment.observe_loading(goods(st),v.mode,speed,ctx.year(tick),v.built,capacity_left)
      end,
      loaded=function(st,v,n)
        Catchment.loaded(st,v.mode,n)
        local train=v.part and assert(state.vehicles[v.id]) or v
        train.boarded=(train.boarded or 0)+n
        train.last_board=emit(events,"board",st,v,tick,{units=n})
      end,
      unloaded=function(st) st.time_since_unload=0 end,
      transferred=function(st,v,p)
        local g=goods(st)
        if not g.has_rating then g.has_rating=true;g.time_since_pickup=0 end
        emit(events,"transfer",st,v,tick,{units=p.units,source=p.source})
      end,
      deliver=function(st,v,p)
        assert(st.always_accept_passengers,"House delivery staged without stock always-acceptance")
        -- DeliverGoods credits the station's associated town, not which
        -- catchment block has the most houses, or the trip origin's town.
        if st.town~=nil then state.towns[st.town]=(state.towns[st.town] or 0)+p.units end
        local g=goods(st)
        g.ever_accepted,g.current_month,g.accepted_bigtick=true,true,true
        local amount,distance=fare(v,p,ctx)
        if ctx.subsidy then amount=ctx.subsidy(st,v,p,amount) end
        emit(events,"deliver",st,v,tick,{units=p.units,source=p.source,
          origin_station=p.origin_station,age=p.age,distance=distance,amount=amount})
        return amount
      end,
      transfer_income=function(st,v,p) return fare(v,p,ctx) end,
      payment=function(st,v,payment)
        v.route_profit=(v.route_profit or 0)+payment.route
        v.visual_profit=(v.visual_profit or 0)+payment.visual+payment.transfer
        if payment.delivered>0 then
          local company=state.companies[v.owner] or {cash=0,revenue=0,units=0}
          state.companies[v.owner]=company
          company.cash=company.cash+payment.route
          company.revenue=company.revenue+payment.route
          company.units=company.units+payment.delivered
          v.delivered=(v.delivered or 0)+payment.delivered
          v.last_fare=emit(events,"fare",st,v,tick,{units=payment.delivered,amount=payment.route})
        end
      end,
    }
  end

  -- Physical first arrival runs after the station tick in the mover.
  -- The host supplies a monotonically increasing visit ID per vehicle;
  -- duplicate arrival callbacks cannot board or pay twice across saves.
  function S.begin(state,vid,id,visit,cargo_tile,order,tick,ctx,events)
    local st,v=state.stations[id],state.vehicles[vid]
    assert(v and type(visit)=="number" and type(cargo_tile)=="number","Invalid carrier, visit or cargo tile")
    assert(tick==state.tick and state.post_tick~=tick,"Arrival must follow this tick's station pass")
    if v.visit then
      if visit==v.visit and v.load_state and id==v.load_state.station and cargo_tile==v.cargo_tile then
        local t=order and order.cargo_tiles
        local same=not v.carrying_parts or type(t)=="table" and #t==#v.carrying_parts
        if same and v.carrying_parts then
          for i,body in ipairs(v.carrying_parts) do
            if body.cargo_tile~=t[i] then same=false;break end
          end
        end
        if same then return v.load_state end
      end
      if visit<=v.visit then return nil,"DUPLICATE_OR_STALE_VISIT" end
      if v.load_state then return nil,"ALREADY_LOADING" end
    end
    local stock=S.stock_for(v.mode,v.engine,v.coach)
    if not st or (st.owner~=v.owner and not neutral(st,ctx)) or
       not coverage(state,st,ctx).facilities[v.mode=="rail" and "rail" or v.mode=="air" and "airport" or "dock"] then
      return nil,"INCOMPATIBLE_STATION"
    end
    order=order or {}
    if v.mode=="rail" then
      assert(type(order.platform_tiles)=="number" and order.platform_tiles>=1,
        "Pass stock continuous platform length including both directions")
    end
    local tiles=order.cargo_tiles
    if v.carrying_parts then
      if type(tiles)~="table" or #tiles~=#v.carrying_parts or cargo_tile~=tiles[1] then
        return nil,"ACTUAL_RAIL_BODY_TILES_REQUIRED"
      end
      for i=1,#v.carrying_parts do
        if type(tiles[i])~="number" then return nil,"ACTUAL_RAIL_BODY_TILES_REQUIRED" end
      end
    end
    v.visit,v.cargo_tile=visit,cargo_tile
    local flags=Loading.compact_order(order.action)
    for _,name in ipairs({"full","force_unload","transfer","no_load","no_unload"}) do
      if order[name]~=nil then flags[name]=order[name] end
    end
    flags.wait,flags.lateness=order.wait or 0,order.lateness or 0
    local ops=options(state,tick,ctx,events);ops.slice=stock.slice
    local load=v.carrying_parts and DMU.begin(st,v,tiles,flags,ops,visit) or Loading.begin(st,v,stock.cap,flags,ops)
    load.platform_tiles=order.platform_tiles
    load.arrived_tick=tick
    v.travel_ticks=v.last_left and tick-v.last_left or nil
    emit(events,"arrive",st,v,tick,{travel_ticks=v.travel_ticks})
    return load
  end

  -- OpenTTD 16.0-RC1 CmdModifyOrder: change the active loading flag,
  -- without redoing BeginLoading or changing the unloading designations.
  function S.update_load_type(v,full,no_load)
    local l=v.load_state
    if not l then return end
    local function apply(a)
      a.full,a.no_load=full,no_load
    end
    apply(l)
    for _,body in ipairs(v.carrying_parts or {}) do apply(body.load_state) end
  end

  -- economy.cpp LoadUnloadVehicle + UpdateLoadUnloadTicks. The latter
  -- applies the train overhang penalty to the idle/full-load retry too.
  function S.loading_delay(mode,m,total_length,platform_tiles,loading_penalty)
    local active=m.loaded>0 or m.unloaded>0 or m.retry_unload
    local n=active and (m.gradual and S.stock[mode].wait or m.loaded+m.unloaded) or BaseTiming.retry_wait
    if mode=="rail" and loading_penalty~=false then
      local length=platform_tiles*16
      local overhang=total_length-length
      if overhang>0 then n=2*n+floor(overhang*2*n/8) end
    end
    return max(1,n)
  end

  -- Order: station ratings -> host tile/house production -> loading scans.
  -- Move vehicle controllers in ID order after this, calling leave/begin
  -- as appropriate, then post_motion_tick. Tick must be the absolute
  -- stock clock, not render frames, 74-tick days, or pilot elapsed time.
  function S.pre_motion_tick(state,tick,ctx)
    if state.tick==tick then return {},{} end
    if state.tick then
      assert(tick==state.tick+1 and state.post_tick==state.tick,"Passenger service clock skipped or reversed")
    end
    state.tick=tick
    local departures,events={},{}
    local ids=keys(state.stations)
    table.sort(ids,function(a,b)
      local l,r=state.stations[a].tick_index or a,state.stations[b].tick_index or b
      return l==r and a<b or l<r
    end)
    for _,id in ipairs(ids) do
      local st=state.stations[id]
      if not ctx.station_active or ctx.station_active(st) then rating_tick(state,st,tick,ctx) end
    end
    if ctx.production then ctx.production(state,tick) end
    local ops=options(state,tick,ctx,events)
    for _,id in ipairs(ids) do
      local st=state.stations[id]
      if #st.loading_order>0 and (not ctx.station_active or ctx.station_active(st)) then
        assert(not active_pulses,"Station service cannot reenter an active station tick")
        active_pulses={}
        local ok,rounds,leaves=pcall(Loading.tick,st,state.vehicles,ops)
        local pulses=active_pulses;active_pulses=nil
        if not ok then error(rounds) end
        local i=0
        for _,r in ipairs(rounds) do
          local v=state.vehicles[r.vehicle]
          if not r.consist then i=i+1 end
          v.load_state.ticks=S.loading_delay(v.mode,r.consist and r or assert(pulses[i]),v.total_length,
            v.load_state.platform_tiles,ctx.loading_penalty)
        end
        assert(i==#pulses,"Every one-body loading round must emit one timing pulse")
        for _,vid in ipairs(leaves) do
          local v=state.vehicles[vid]
          v.load_state.ready_tick=tick
          departures[#departures+1]=vid
        end
      end
    end
    table.sort(departures)
    return departures,events
  end

  function S.leave(state,vid,visit,tick,ctx,events,skip_order)
    local v=assert(state.vehicles[vid])
    local l=v.load_state
    if not l or v.visit~=visit then return false,"DUPLICATE_OR_STALE_VISIT" end
    if not skip_order and l.ready_tick~=tick then return false,"NOT_READY" end
    assert(state.tick==tick and state.post_tick~=tick,"Departure must follow this tick's station pass")
    local st=assert(state.stations[l.station])
    local ops=options(state,tick,ctx,events)
    if v.carrying_parts then DMU.leave(st,v,ops) else Loading.leave(st,v,ops) end
    v.last_left=tick
    emit(events,"leave",st,v,tick)
    v.cargo_tile=nil
    return true
  end

  -- Used when removing an explicitly cleared pilot. Return its genuine
  -- station reservations and settle already unloaded deliveries before
  -- deleting the vessel. Unshipped onboard cargo is not a final delivery.
  function S.withdraw_vehicle(state,vid,tick,ctx,events)
    local v=state.vehicles[vid]
    if not v then return false end
    if v.load_state then
      local st=assert(state.stations[v.load_state.station],"Cannot withdraw from a missing station")
      local ops=options(state,tick,ctx,events)
      if v.carrying_parts then DMU.leave(st,v,ops) else Loading.leave(st,v,ops) end
    end
    state.vehicles[vid]=nil
    return true
  end

  function S.accident_rating(state,owner,x,y)
    local rows={}
    for _,st in pairs(state.stations) do
      local sign=st.sign or st.tiles[1]
      if sign then
        local g=goods(st)
        rows[#rows+1]={owner=st.owner,x=sign.x,y=sign.y,goods={{
          active=g.has_rating or (st.passenger_acceptance or 0)>=8 or st.always_accept_passengers,
          state=g}}}
      end
    end
    return Rating.modify_around(rows,owner,x,y,-160,30)
  end

  function S.crash_rail(state,vid,tick,ctx,events)
    local v=state.vehicles[vid]
    if not v or v.mode~="rail" or v.crashed then return false end
    if v.load_state then
      local st=assert(state.stations[v.load_state.station])
      local ops=options(state,tick,ctx,events)
      if v.carrying_parts then DMU.leave(st,v,ops) else Loading.leave(st,v,ops) end
    end
    v.crashed,v.stopped,v.units,v.batches=true,true,0,{}
    for _,part in ipairs(v.carrying_parts or {}) do part.units,part.batches=0,{} end
    return true
  end

  function S.post_motion_tick(state,tick,ctx)
    assert(state.tick==tick,"Passenger aging must follow the same absolute movement tick")
    if state.post_tick==tick then return false end
    for _,v in pairs(state.vehicles) do
      if not ctx or not ctx.vehicle_active or ctx.vehicle_active(v) then
        local aging=S.stock_for(v.mode,v.engine,v.coach).aging
        if v.carrying_parts then DMU.age(v,aging) else Loading.age_vehicle(v,1,aging) end
      end
    end
    state.post_tick=tick
    return true
  end

  return S
end
