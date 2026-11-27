-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 one ordinary carrying wagon (#29), manual coal orders.
-- Source: economy.cpp LoadUnloadVehicle/UpdateLoadUnloadTicks/
-- CargoPayment::PayFinalDelivery, station_cmd.cpp, cargoaction.cpp,
-- cargopacket.h and table/engines.h. Reuse production, rating, packet and
-- station command kernels rather than producing coal in a second clock.
return function(Sim,Coal,Catchment,Roster,Packets,Rating,Station,Income,LoadingFactory,Timing)
  local R={VERSION=1,wagon=assert(Roster.entry(29)),cargo=Coal.cargo,rail_index=0x4000}
  local function keys(t)
    local out={}
    for k in pairs(t or {}) do out[#out+1]=k end
    table.sort(out)
    return out
  end
  function R.index(id)
    assert(type(id)=="number" and id>=0 and id%1==0 and id<R.rail_index,"Invalid local rail station")
    return R.rail_index+id
  end
  function R.new()
    return {version=R.VERSION,stations={},vehicles={}}
  end
  function R.loading_pulse(m,length,tiles,penalty)
    local _,stop,finished,refresh=Timing.pulse(m)
    local delay
    if m.retry_unload and m.loaded+m.unloaded==0 then
      -- Acceptance disappeared while unloading: source deliberately
      -- treats it as unloading but no cargo changed (0 non-gradual ticks).
      delay=m.gradual and Roster.GRADUAL_WAIT or 0
      local overhang=length-tiles*16
      if penalty~=false and overhang>0 then delay=2*delay+math.floor(overhang*2*delay/8) end
      delay=math.max(1,delay)
    else
      delay=Roster.loading_wait(length,tiles,m.loaded,m.unloaded,
        {gradual_loading=m.gradual,platform_penalty=penalty})
    end
    return delay,stop,finished,refresh
  end

  local function use_option(ctx,k,s,tick)
    local opt=ctx[k]
    if type(opt)=="function" then return opt(s,tick) end
    return opt
  end
  local function count(q)
    local n=0
    for _,p in ipairs(q or {}) do n=n+p.units end
    return n
  end
  local function physical(s,st)
    local seen,list={},{}
    for _,id in ipairs(st.tiles or {}) do
      local t=s.tiles[id]
      if not seen[id] and t and t.owner==st.owner and t.rail_station_id==st.id and
          t.rail_station_axis==st.axis and t.rail_tracks==2^st.axis then
        seen[id]=true;list[#list+1]=id
      end
    end
    return list,seen
  end
  function R.platform(s,st,front)
    local _,ids=physical(s,st)
    if not ids[front] then return end
    local n=1
    for _,dir in ipairs(st.axis==0 and {2,4} or {1,3}) do
      local at=Sim.adjacent(front,dir)
      while at and ids[at] do n=n+1;at=Sim.adjacent(at,dir) end
    end
    return n
  end

  -- The list handed here is the road coal clock's authoritative mixed
  -- list, not a new production path. One offer -> one fixed-point
  -- allocation. Generated packets have no first loading tile in source,
  -- unlike legacy single-tile road records which stamped the stop sign.
  function R.distribute(mine,amount,stations,coverage,opts)
    local previous={}
    for _,st in ipairs(stations) do previous[st.id]=#(st.stock and st.stock.coal or {}) end
    local moved,candidates=Coal.distribute(mine,amount,stations,coverage,opts)
    for _,entry in ipairs(candidates) do
      local st=entry.source
      local q=st.stock and st.stock.coal
      if q and #q>previous[st.id] then
        local fresh=q[#q]
        fresh.origin_tile=nil
        for i=#q-1,1,-1 do
          local old=q[i]
          if old.origin_station==fresh.origin_station and old.origin_tile==nil and
              old.age==0 and old.source==fresh.source and old.source_type==fresh.source_type and
              old.units+fresh.units<=65535 then
            old.units=old.units+fresh.units
            table.remove(q)
            break
          end
        end
      end
    end
    return moved,candidates
  end

  function R.bind(s,state,ctx)
    ctx=ctx or {}
    assert(state.version==R.VERSION,"Unsupported rail coal save")
    local width,height=ctx.width or Sim.W,ctx.height or Sim.H
    local xy=ctx.xy or Sim.xy
    local industries={}
    for _,ind in pairs(ctx.industries or s.stock_coal_industries or {}) do industries[#industries+1]=ind end
    table.sort(industries,function(a,b)return a.id<b.id end)
    local list,coverage,instances,ids={}, {}, {}, {}
    for _,host_id in ipairs(keys(s.stock_rail_stations)) do
      local raw=s.stock_rail_stations[host_id]
      assert(raw.id==host_id)
      local marked=raw.coal_role=="load" or raw.coal_role=="unload"
      local tiles=physical(s,raw)
      if #tiles>0 and (not ctx.only_id or ctx.only_id==host_id) and (not ctx.only_marked or marked) then
        local id=R.index(host_id)
        local geo={}
        for _,tile in ipairs(tiles) do
          local x,z=xy(tile)
          geo[#geo+1]={x=x-1,y=z-1,kind="rail"}
        end
        local ref=table.concat(tiles,":")
        local old=state.stations[id]
        local st=old or {id=id,owner=raw.owner,host_id=host_id,stock={coal={}},
          loading_order={},time_since_load=255,time_since_unload=255,rating_phase=0}
        assert(st.owner==raw.owner,"Freight station ownership changed")
        if old and old.footprint~=ref then assert(#old.loading_order==0,"Freight platform changed while loading") end
        st.tiles,st.tile,st.footprint,st.role=geo,tiles[1],ref,raw.coal_role
        local x,z=xy(st.tile)
        st.x,st.z=x-1,z-1
        local town=ctx.station_town and ctx.station_town(raw,st.tile) or Sim.nearest_town(s,st.tile)
        st.town=type(town)=="table" and town.id or town
        Coal.goods(st)
        list[#list+1]=st;ids[id]=true
        coverage[id]=Catchment.build(st,width,height,ctx.modified_catchment)
        instances[id]={raw=raw,list=tiles}
        state.stations[id]=st
        if not old or old.last_acceptance==nil or old.last_acceptance_footprint~=ref then
          st.last_acceptance=Coal.acceptance(st,coverage[id],industries).accepts
          st.last_acceptance_footprint=ref
        end
      end
    end
    for id,st in pairs(state.stations) do
      if not ids[id] then
        if #st.loading_order==0 then state.stations[id]=nil end
        -- Retain the saved cargo/reservation ledger at a disappeared
        -- platform until its owning run explicitly handles the fault.
        -- A detached station participates in neither loading nor supply.
      end
    end
    local B={views=list,coverage=coverage}
    -- Truck views alias their real saved queue/goods. Rail views reference
    -- the persistent rail state directly, so there are no mirrored tons.
    function B.extend(stations,covers)
      local seen={}
      for _,st in ipairs(stations) do seen[st.id]=true end
      for _,st in ipairs(list) do
        assert(not seen[st.id] and not covers[st.id],"Coal station IDs have collided")
        stations[#stations+1]=st;covers[st.id]=coverage[st.id]
      end
      table.sort(stations,function(a,b) return a.id<b.id end)
      return stations,covers
    end
    local function emit(kind,st,v,tick,extra)
      local e={kind=kind,cargo="coal",mode="rail",station=st.id,station_local=st.host_id,
        vehicle=v.id,owner=v.owner,tile=v.cargo_tile,tick=tick,visit=v.visit}
      for k,value in pairs(extra or {}) do e[k]=value end
      if ctx.emit then ctx.emit(e) end
      return e
    end
    local function carrier(st,v) return {id=st.id,tile=v.cargo_tile} end
    local function year(tick) return ctx.year and ctx.year(s,tick) or Sim.date(s) end
    local function random() return (ctx.random_u32 or Station.random_u32)(s) end
    local function load_rights(st,v)
      local rights=ctx.town_rights and ctx.town_rights(st.town)
      return Catchment.may_load(st,v.owner,rights,ctx.neutral_owner)
    end
    function B.report(local_id)
      local st=state.stations[R.index(local_id)]
      if not st or not coverage[st.id] then return end
      local r=Coal.acceptance(st,coverage[st.id],industries)
      r.accepts,r.station,r.sources,r.role=st.last_acceptance,st,{},st.role
      for _,ind in ipairs(industries) do
        if not ind.removed and ind.produced then
          for _,tile in ipairs(ind.tiles) do
            if Catchment.contains(coverage[st.id],tile.x,tile.z) then
              r.sources[#r.sources+1]=ind.id;break
            end
          end
        end
      end
      table.sort(r.sources)
      return r
    end
    local pulses
    local Loader=LoadingFactory({initial=Timing.initial,can_leave=Timing.can_leave,
      pulse=function(m)
        assert(pulses,"Coal timing requires an ordered loading phase")
        pulses[#pulses+1]=m
        return Timing.pulse(m)
      end},Packets)
    local function ops(tick)
      local pending={}
      return {
        pending=pending,queue=function(st) return st.stock.coal end,
        slice=R.wagon.load_amount,gradual=s.stock_gradual_loading~=false,
        feeder_percent=s.stock_feeder_percent,
        accepts=function(st) return st.last_acceptance end,
        can_load=load_rights,
        pickup=function(st,v,p) Packets.pickup(p,carrier(st,v),xy) end,
        drop=function(st,v,p) Packets.drop(p,carrier(st,v),xy) end,
        attempt=function(st,v,left)
          Coal.observe_loading(st,{mode="rail",build_year=v.built,max_speed=v.cached_max_speed},left,year(tick))
        end,
        loaded=function(st,v,n)
          Catchment.loaded(st,"rail",n)
          emit("board",st,v,tick,{units=n})
        end,
        unloaded=function(st) Station.unloaded(st) end,
        transferred=function(st,v,p)
          local g=Coal.goods(st)
          if not g.has_rating then g.has_rating=true;g.time_since_pickup=0 end
          emit("transfer",st,v,tick,{units=p.units,source_industry=p.source})
        end,
        transfer_income=function(_,v,p)
          return Income.regular(p.units,Packets.distance(p,v.cargo_tile,xy),p.age or 0,
            use_option(ctx,"current_payment",s,tick) or Coal.cargo.payment,Coal.cargo.days1,Coal.cargo.days2)
        end,
        deliver=function(st,v,p)
          local d=Packets.distance(p,v.cargo_tile,xy)
          local result=Coal.delivery(st,B.report(st.host_id),p,{distance=d,
            current_payment=use_option(ctx,"current_payment",s,tick),
            date=use_option(ctx,"economy_date",s,tick) or s.day,refused=ctx.refused})
          if Sim.stock_town_accept then Sim.stock_town_accept(s,st.town,"coal",result.accepted,0) end
          if result.accepted>0 and Sim.stock_subsidy_active and Sim.stock_subsidy_active(s) then
            result.payment=Sim.stock_subsidy_pay(s,"coal",v.owner,p,result.payment,coverage[st.id].tiles,"coal")
          end
          local l=v.load_state
          l.coal_accepted=(l.coal_accepted or 0)+result.accepted
          for _,plant in ipairs(result.plants) do
            pending[plant.industry.id]=plant.industry
            if plant.amount>0 then
              if ctx.received then ctx.received(s,plant.industry,plant.amount) end
              emit("deliver",st,v,tick,{units=plant.amount,distance=d,age=p.age or 0,
                source_industry=p.source,destination_industry=plant.industry.id})
            end
          end
          return result.payment
        end,
        payment=function(st,v,p)
          local l=assert(v.load_state)
          local accepted=l.coal_accepted or 0
          l.coal_accepted=nil
          assert(accepted<=p.delivered)
          if accepted>0 then
            local company=Sim.company(s,v.owner)
            if ctx.credit then ctx.credit(company,p.route)
            else
              company.cash,company.revenue,company.month_rev=
                company.cash+p.route,company.revenue+p.route,company.month_rev+p.route
            end
            company.units,company.paid_units=company.units+accepted,company.paid_units+accepted
            if Sim.stock_economy_delivered then Sim.stock_economy_delivered(company,"coal",accepted) end
            if Sim.stock_vehicle_operating then
              Sim.stock_vehicle_operating(s,s.stock_rail_fleet and s.stock_rail_fleet.units[v.id],p.route)
            end
            v.delivered,v.revenue=v.delivered+accepted,v.revenue+p.route
            emit("fare",st,v,tick,{units=accepted,amount=p.route})
          end
          v.profit_with_feeders=v.profit_with_feeders+p.visual+p.transfer
        end,
      }
    end
    local function finish(operations)
      local plants={}
      for _,id in ipairs(keys(operations.pending)) do plants[#plants+1]={industry=operations.pending[id]} end
      Coal.trigger_delivery({plants=plants})
    end

    function B.vehicle(def)
      if next(state.vehicles) or def.stock_id~=R.wagon.stock_id or type(def.id)~="number" or
          def.length~=2*R.wagon.length or not def.owner or type(def.speed)~="number" or type(def.built)~="number" then
        return nil,"UNSUPPORTED_COAL_CONSIST"
      end
      local v={id=def.id,owner=def.owner,mode="rail",stock_id=def.stock_id,cargo="coal",total_length=def.length,
        cached_max_speed=def.speed,built=def.built,batches={},units=0,cargo_age_counter=1,
        delivered=0,revenue=0,profit_with_feeders=0}
      state.vehicles[v.id]=v
      return v
    end
    function B.arrive(vid,local_id,visit,tick,head_tile,cargo_tile,order)
      local v=state.vehicles[vid]
      if not v then return nil,"NO_COAL_CONSIST" end
      local id=R.index(local_id)
      if v.visit then
        if visit==v.visit and v.load_state and v.load_state.station==id and
            v.cargo_tile==cargo_tile and v.head_tile==head_tile then return v.load_state end
        if visit<=v.visit then return nil,"DUPLICATE_OR_STALE_VISIT" end
        if v.load_state then return nil,"ALREADY_LOADING" end
      end
      local st,p=state.stations[id],instances[id]
      if not st or not s.tiles[cargo_tile] or not (st.owner==v.owner or
          ctx.neutral_owner~=nil and st.owner==ctx.neutral_owner) then return nil,"INCOMPATIBLE_STATION" end
      local platform=R.platform(s,p.raw,head_tile)
      if not platform then return nil,"FRONT_NOT_ON_PLATFORM" end
      order=order or {}
      local flags=Loader.compact_order(order.action)
      for _,k in ipairs({"full","force_unload","transfer","no_load","no_unload"}) do
        if order[k]~=nil then flags[k]=order[k] end
      end
      flags.wait,flags.lateness=order.wait or 0,order.lateness or 0
      v.visit,v.head_tile,v.cargo_tile=visit,head_tile,cargo_tile
      local l=Loader.begin(st,v,R.wagon.capacity,flags,ops(tick))
      l.platform_tiles,l.arrived_tick=platform,tick
      emit("arrive",st,v,tick,{platform_tiles=platform,head=head_tile})
      return l
    end
    function B.loading_tick(tick)
      if state.loading_tick==tick then return {} end
      if state.loading_tick and (tick~=state.loading_tick+1 or state.post_tick~=state.loading_tick) then
        return nil,"NONCONTIGUOUS_COAL_CLOCK"
      end
      state.loading_tick=tick
      local ready={}
      for _,st in ipairs(list) do
        if #st.loading_order>0 then
          local options=ops(tick)
          pulses={}
          local ok,rounds,departures=pcall(Loader.tick,st,state.vehicles,options)
          local m=pulses;pulses=nil
          if not ok then error(rounds) end
          assert(#rounds==#m)
          for i,round in ipairs(rounds) do
            local v=state.vehicles[round.vehicle]
            v.load_state.ticks=R.loading_pulse(m[i],v.total_length,v.load_state.platform_tiles,ctx.loading_penalty)
          end
          for _,vid in ipairs(departures) do
            state.vehicles[vid].load_state.ready_tick=tick
            ready[#ready+1]=vid
          end
          finish(options)
        end
      end
      return ready
    end
    function B.leave(vid,visit,tick)
      local v=state.vehicles[vid]
      local l=v and v.load_state
      if not l or v.visit~=visit then return false,"DUPLICATE_OR_STALE_VISIT" end
      if l.ready_tick~=tick or state.loading_tick~=tick or state.post_tick==tick then return false,"NOT_READY" end
      local st=state.stations[l.station]
      local options=ops(tick)
      Loader.leave(st,v,options);finish(options)
      emit("leave",st,v,tick)
      v.head_tile,v.cargo_tile=nil,nil
      return true
    end

    -- Always after actual train advance, before industry production. If
    -- passenger and coal share a powered platform, pass rating_due from
    -- the shared station phase rather than incrementing it twice.
    function B.after_motion(tick)
      if state.loading_tick~=tick then return nil,"NO_MATCHING_COAL_TICK" end
      if state.post_tick==tick then return false end
      for _,v in pairs(state.vehicles) do Loader.age_vehicle(v,1,R.wagon.cargo_age_ticks) end
      for _,st in ipairs(list) do
        local due
        if ctx.rating_due then due=ctx.rating_due(st,tick)
        else
          local phase,events=Rating.advance_clock(st.rating_phase,1)
          st.rating_phase=phase;due=events>0
          if due then Rating.increment_station_timers(st) end
        end
        if due then
          Coal.rating_tick(st,{select_goods=ctx.select_goods,random_u32=random,
            statue=Sim.station_has_town_statue and Sim.station_has_town_statue(s,st),
            truncate=Station.truncate,station_at=function(id)
              return state.stations[id] or s.stations and s.stations[id]
            end})
        end
        if (tick+st.id)%250==0 then
          st.last_acceptance=Coal.acceptance(st,coverage[st.id],industries).accepts
          Coal.goods(st).accepted_bigtick=nil
        end
      end
      state.post_tick=tick
      return true
    end
    function B.withdraw(vid,tick)
      local v=state.vehicles[vid]
      if not v then return false end
      if v.load_state then
        local st=assert(state.stations[v.load_state.station],"Removed station still owns coal reservations")
        local options=ops(tick)
        Loader.leave(st,v,options);finish(options)
      end
      state.vehicles[vid]=nil
      return true
    end
    function B.waiting(local_id)
      local st=state.stations[R.index(local_id)]
      if not st then return 0,0 end
      local waiting,reserved=count(st.stock.coal),0
      for _,vid in ipairs(st.loading_order) do
        reserved=reserved+state.vehicles[vid].load_state.reserved_units
      end
      return waiting+reserved,waiting
    end
    return B
  end
  return R
end
