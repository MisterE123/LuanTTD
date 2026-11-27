-- SPDX-License-Identifier: GPL-2.0-only
-- Live save and presentation bridge for stock road station service.
-- Acceptance uses OpenTTD 14.1 src/table/town_land.h house eighths,
-- src/town_cmd.cpp AddAcceptedCargo_Town and src/station_cmd.cpp
-- UpdateStationAcceptance. Simulation mechanics stay in road_loading_runtime.
return function(Sim,Loading,Packets,Income,Rating,Mail,host)
  local M={}
  host=host or {}
  local floor,max,min=math.floor,math.max,math.min
  local function timber_cargo(cargo)
    return cargo=="oil" or cargo=="wood" or cargo=="goods" or cargo=="grain" or cargo=="livestock" or cargo=="steel" or cargo=="iron_ore" or cargo=="valuables"
  end
  local function loading_name(cargo)
    return ({coal="Loading coal",mail="Loading mail",wood="Loading logs",goods="Loading goods",
      grain="Loading grain",livestock="Loading livestock",oil="Loading crude oil",steel="Loading steel",iron_ore="Loading iron ore",valuables="Loading valuables"})[cargo] or "Boarding"
  end
  -- A house can accept while under construction. The town supply module
  -- separately gates production on completion, as the stock engine does.
  local passenger_accept={
    [0]=8,8,8,2,10,10,4,6,6,2,2,2,2,8,6,6,
    6,10,6,6,4,4,4,4,3,3,3,7,8,6,8,8,
    4,4,4,4,8,3,3,8,8,8,8,8,5,5,3,3,
    3,3,8,8,9,9,10,10,2,2,3,3,2,2,3,3,
    6,6,6,6,6,6,7,7,9,9,7,7,7,7,3,3,
    3,3,6,2,3,6,6,8,8,6,8,2,6,3,3,3,
    3,3,8,4,4,8,3,3,8,8,8,4,3,3,
  }
  function M.house_passenger_acceptance(id) return passenger_accept[id] end

  function M.handles(s,v)
    if not s.road_stock_loading or not s.road_economy or not v then return false end
    if v.stock_tram then return v.cargo=="passenger" end
    local def=Sim.vehicles[v.engine]
    return def and def.mode=="road" and
      (v.cargo=="passenger" or (s.road_mail and Mail.supported_vehicle(v)) or
       (host.coal_handles and host.coal_handles(s,v)) or
       (host.timber_handles and host.timber_handles(s,v))) or false
  end
  local function compatible(st,v)
    return st and st.mode=="road" and (not st.tram_only or v.stock_tram) and
      ((v.cargo=="passenger" and Sim.road_stop_has(st,"bus"))
        or ((v.cargo=="mail" or v.cargo=="coal" or timber_cargo(v.cargo)) and Mail.truck_stop(st)))
  end

  local function accepted_house_totals(s,st,cargo)
    local per_town,sum={},0
    local radius=cargo=="mail" and Mail.catchment or 3
    local accepts=cargo=="mail" and Mail.house_acceptance or M.house_passenger_acceptance
    for id in pairs(Sim.road_stop_catchment(s,st,radius)) do
      local tile=id and s.tiles[id]
      local rec=tile and tile.house and tile.source_house
      if rec then
        local value=assert(accepts(rec.id),"Unknown stock house acceptance")
        sum=sum+value
        if rec.town and value>0 then per_town[rec.town]=(per_town[rec.town] or 0)+value end
      else
        local hq=id and Sim.hq_cargo_at and Sim.hq_cargo_at(s,id)
        if hq then sum=sum+Sim.hq_acceptance(hq,cargo) end
      end
    end
    return sum,per_town
  end
  function M.acceptance(s,st,cargo)
    if not compatible(st,{cargo=cargo,stock_tram=st and st.tram_only}) then return 0 end
    if cargo=="coal" then
      local b=host.coal and host.coal(s)
      return b and b.report(st).eighths or 0
    end
    if timber_cargo(cargo) then
      local t=host.timber and host.timber(s)
      return t and t.report(st,cargo).eighths or 0
    end
    if s.road_stock_house_supply then return accepted_house_totals(s,st,cargo) end
    -- Older compatibility worlds do not carry stock HouseIDs. Continue
    -- their historical served-town admission only where opted in explicitly.
    if cargo=="mail" then return 0 end
    for _,id in ipairs(st.served or {}) do
      local site=s.sites[id]
      if site and Sim.facilities[site.kind].takes[cargo] then return 8 end
    end
    return 0
  end
  local function receiver(s,st,cargo)
    local function eligible(site)
      return site and Sim.facilities[site.kind].takes[cargo]
    end
    if s.road_stock_house_supply then
      local _,towns=accepted_house_totals(s,st,cargo)
      local best,n
      for id,accepts in pairs(towns) do
        if not n or accepts>n or (accepts==n and id<best) then best,n=id,accepts end
      end
      if best and eligible(s.sites[best]) then return s.sites[best] end
    end
    -- Some legacy or imported boards have records without an owner ID.
    local preferred=s.sites[st.site]
    if eligible(preferred) then return preferred end
    for _,id in ipairs(st.served or {}) do if eligible(s.sites[id]) then return s.sites[id] end end
  end

  local function stop_tile(s,st,v)
    return Sim.road_loading_tile(s,st,v)
  end
  local function cargo_stop(s,st,v)
    local tile=stop_tile(s,st,v)
    return tile==st.tile and st or {id=st.id,tile=tile}
  end

  -- Public existing snapshot fields persist on vehicles for save/UI. Keep
  -- a transient ordered FIFO too, so a 74-tick visual frame doesn't drop
  -- two separate boarding slices before the renderer sees one.
  local frames=setmetatable({},{__mode="k"})
  local function push(s,v,kind,st,tick,rec)
    rec.tile,rec.day,rec.tick=stop_tile(s,st,v),s.day,tick
    local frame=frames[s]
    if not frame or ((frame[#frame] and frame[#frame].data.day or s.day)<s.day-16) then
      frame={};frames[s]=frame
    end
    local previous=frame[#frame]
    if previous and previous.kind==kind and kind=="board"
       and previous.vehicle==v.id and previous.data.tile==rec.tile
       and previous.data.day==rec.day then
      rec.units=previous.data.units+rec.units
      previous.data=rec
    else
      frame[#frame+1]={kind=kind,vehicle=v.id,owner=v.owner,cargo=v.cargo,data=rec}
    end
    if #frame>4096 then table.remove(frame,1) end
    if kind=="board" then v.last_board=rec
    elseif kind=="fare" then v.last_fare=rec
    else v.last_arrival=rec end
  end
  function M.take_effects(s)
    local frame=frames[s] or {}
    frames[s]=nil
    return frame
  end

  -- Stock reservation removes units from AvailableCount. It must not make
  -- our visible figures disappear: they are still waiting for physical
  -- boarding. Queue pressure/rating continues to use unreserved units.
  local function loading_vehicle(s,id)
    local run=s.stock_tram_fleet and s.stock_tram_fleet[id]
    local carrier=(run or s.tram_pilot) and (run or s.tram_pilot).carrier
    return s.fleet[id] or carrier and carrier.id==id and carrier or nil
  end
  function M.display_waiting(s,st,cargo)
    if cargo=="coal" then
      local b=host.coal and host.coal(s)
      return b and b.display_waiting(st) or 0
    end
    if timber_cargo(cargo) then
      local t=host.timber and host.timber(s)
      return t and t.display_waiting(st,cargo) or 0
    end
    local count=0
    for _,p in ipairs((st.stock or {})[cargo] or {}) do count=count+p.units end
    for _,id in ipairs(st.loading_order or {}) do
      local v=loading_vehicle(s,id)
      if v and v.cargo==cargo and v.load_state and v.load_state.station==st.id then
        count=count+v.load_state.reserved_units
      end
    end
    return count
  end

  local function company_credit(company,amount)
    company.cash=(company.cash or 0)+amount
    company.revenue=(company.revenue or 0)+amount
    company.month_rev=(company.month_rev or 0)+amount
  end
  local function base_fare(s,st,v,p)
    if not p.origin_tile then return 0 end
    local dist=Packets.distance(p,stop_tile(s,st,v),Sim.xy)
    return Income.regular(p.units,dist,p.age or 0,unpack(Income.temperate[v.cargo]))
  end
  local function apply_subsidy(s,v,p,site,money)
    if host.subsidy then return host.subsidy(s,v,p,site,money) end
    -- Preserve the authored scenario's contract list until the stock
    -- subsidy system mounts. Money remains attributed to the real route.
    if v.cargo=="passenger" and site then
      for _,offer in ipairs(s.subsidies or {}) do
        if s.day<=offer.until_day and offer.src==p.source and offer.dst==site.id and offer.cargo==v.cargo then
          if not offer.owner then
            offer.owner=v.owner
            if host.news then host.news(s,v.owner.." earned a route subsidy to "..site.name..".") end
          end
          if offer.owner==v.owner then return floor(money*1.5) end
          break
        end
      end
    end
    return money
  end
  local function mark_first_transfer(st,v,s)
    if v.cargo=="mail" then
      Mail.status(st) -- initialize known cargo goods, not a service offer
      local g=st.mail_rating_state
      if not g.has_rating then g.has_rating=true;g.time_since_pickup=0 end
    else Rating.transferred(s,st) end
  end
  local function opts(s,tick,force_coal,force_timber)
    local b=host.coal and host.coal(s,force_coal)
    local coal=b and b.ops(tick,function(kind,st,v,detail)
      if kind=="fare" and host.news and Sim.company(s,v.owner).paid_units==detail.units then
        host.news(s,v.owner.." made their first paid delivery: "..detail.units.." tons of coal for $"..detail.amount..".")
      end
      -- Deliver/transfer are useful to industrial presentation; only
      -- real board/fare events update the existing vehicle snapshots.
      if kind=="board" or kind=="fare" then push(s,v,kind,st,tick,detail) end
    end)
    local wood=host.timber and host.timber(s,force_timber)
    local timber=wood and wood.ops(tick,function(kind,st,v,detail)
      if kind=="board" or kind=="fare" then push(s,v,kind,st,tick,detail) end
      if kind=="fare" and host.news and Sim.company(s,v.owner).paid_units==detail.units then
        host.news(s,v.owner.." made their first paid delivery of "..v.cargo.." for $"..detail.amount..".")
      end
    end)
    return {
      xy=Sim.xy,gradual=s.stock_gradual_loading~=false,feeder_percent=s.stock_feeder_percent,
      accepts=function(st,v)
        if v.cargo=="coal" then return coal and coal.accepts(st,v) or false end
        if timber_cargo(v.cargo) then return timber and timber.accepts(st,v) or false end
        return M.acceptance(s,st,v.cargo)>=8
      end,
      can_load=function(st,v)
        if host.can_load and not host.can_load(s,st,v) then return false end
        if v.cargo=="coal" then return coal and coal.can_load(st,v) or false end
        if timber_cargo(v.cargo) then return timber and timber.can_load(st,v) or false end
        return true
      end,
      queue=(coal or timber) and function(st,v)
        if v.cargo=="coal" then return coal.queue(st,v) end
        if timber_cargo(v.cargo) then return timber.queue(st,v) end
        st.stock=st.stock or {};st.stock[v.cargo]=st.stock[v.cargo] or {};return st.stock[v.cargo]
      end,
      pickup=function(st,v,p)
        if timber_cargo(v.cargo) and timber and timber.pickup then return timber.pickup(st,v,p) end
        return Packets.pickup(p,cargo_stop(s,st,v),Sim.xy)
      end,
      drop=function(st,v,p)
        if not p.origin_tile then return end
        if timber_cargo(v.cargo) and timber and timber.drop then return timber.drop(st,v,p) end
        return Packets.drop(p,cargo_stop(s,st,v),Sim.xy)
      end,
      station_done=(coal or timber) and function(st)
        if coal then coal.station_done() end
        if timber then timber.station_done(st) end
      end,
      attempt=function(st,v,cap)
        if v.cargo=="coal" then return coal.attempt(st,v,cap) end
        if timber_cargo(v.cargo) then return timber.attempt(st,v,cap) end
        if v.cargo=="mail" then Mail.observe_loading(s,st,v,cap)
        else Rating.observe_loading(s,st,v,cap) end
      end,
      loaded=function(st,v,count)
        if v.cargo=="coal" then return coal.loaded(st,v,count) end
        if timber_cargo(v.cargo) then return timber.loaded(st,v,count) end
        Rating.loaded(st);st.last_service[v.cargo]=s.day
        push(s,v,"board",st,tick,{units=count})
      end,
      transferred=function(st,v,p)
        if v.cargo=="coal" then return coal.transferred(st,v,p) end
        if timber_cargo(v.cargo) then return timber.transferred(st,v,p) end
        return mark_first_transfer(st,v,s)
      end,
      unloaded=function(st,v,n)
        if v.cargo=="coal" then return coal.unloaded(st,v,n) end
        if timber_cargo(v.cargo) then return timber.unloaded(st,v,n) end
        Rating.unloaded(st)
      end,
      deliver=function(st,v,p)
        if v.cargo=="coal" then return coal.deliver(st,v,p) end
        if timber_cargo(v.cargo) then return timber.deliver(st,v,p) end
        if Sim.stock_town_accept then Sim.stock_town_accept(s,st.town or st.site,v.cargo,p.units,p.units) end
        local site=receiver(s,st,v.cargo)
        if site then
          site.received[v.cargo]=(site.received[v.cargo] or 0)+p.units
          if v.cargo=="passenger" then
            site.service=(site.service or 0)+p.units
            local by_site=v.load_state.received_by_site or {}
            v.load_state.received_by_site=by_site
            by_site[site.id]=(by_site[site.id] or 0)+p.units
          end
        end
        return apply_subsidy(s,v,p,site,base_fare(s,st,v,p))
      end,
      transfer_income=function(st,v,p)
        if v.cargo=="coal" then return coal.transfer_income(st,v,p) end
        if timber_cargo(v.cargo) then return timber.transfer_income(st,v,p) end
        return base_fare(s,st,v,p)
      end,
      payment=function(st,v,payment)
        if v.cargo=="coal" then return coal.payment(st,v,payment) end
        if timber_cargo(v.cargo) then return timber.payment(st,v,payment) end
        local company=Sim.company(s,v.owner)
        if payment.delivered>0 then
          local credit=host.credit or company_credit
          credit(company,payment.route)
          if company.paid_units==0 and host.news then
            host.news(s,v.owner.." made their first paid delivery: "..payment.delivered.." "..
              Sim.cargo[v.cargo].name:lower().." for $"..payment.route..".")
          end
          v.revenue=v.revenue+payment.route
          if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,v,payment.route) end
          v.delivered=v.delivered+payment.delivered
          company.units=company.units+payment.delivered
          company.paid_units=company.paid_units+payment.delivered
          if Sim.stock_economy_delivered then Sim.stock_economy_delivered(company,v.cargo,payment.delivered) end
          push(s,v,"fare",st,tick,{amount=payment.route,units=payment.delivered})
          for id,count in pairs(v.load_state.received_by_site or {}) do
            local site=s.sites[id]
            if site and site.kind=="town" then
              company.rating[id]=min(100,(company.rating[id] or 48)+max(1,floor(count/10)))
            end
          end
        end
        v.stock_profit_with_feeders=(v.stock_profit_with_feeders or 0)+payment.visual+payment.transfer
      end,
    }
  end

  function M.begin(s,st,v,order,tick)
    if not M.handles(s,v) or not compatible(st,v) or st.owner~=v.owner then return nil,"INCOMPATIBLE_STATION" end
    if v.load_state then
      if v.load_state.station~=st.id then return nil,"ALREADY_LOADING_ELSEWHERE" end
      return v.load_state
    end
    assert(v.station==st.id and not v.route,"Save schema: hand off arrivals at their station")
    assert(type(tick)=="number","Road arrivals need a shared tick")
    st.last_service=st.last_service or {}
    order=order or {}
    local flags=Loading.compact_order(order.action)
    for _,name in ipairs({"full","force_unload","transfer","no_load","no_unload"}) do
      if order[name]~=nil then flags[name]=order[name] end
    end
    flags.wait,flags.lateness=order.wait or 0,order.lateness or v.lateness or 0
    local arrival=opts(s,tick)
    -- Older packets with a recorded first station can reconstruct that
    -- known loading point; wholly unknown origins earn no synthetic fare.
    for _,p in ipairs(v.batches or {}) do
      if not p.origin_tile and p.origin_station and s.stations[p.origin_station] then
        local origin=s.stations[p.origin_station]
        if p.travel_x~=nil and p.travel_z~=nil then p.origin_tile=origin.tile
        else Packets.pickup(p,origin,Sim.xy) end
      end
    end
    if v.cargo=="passenger" and Sim.vehicle_stock_load_amount then
      arrival.slice=Sim.vehicle_stock_load_amount(v) or arrival.slice
    end
    if v.cargo=="mail" then arrival.slice=Sim.vehicles[v.engine].load_amount or Mail.engine.load_amount end
    if v.cargo=="coal" then arrival.slice=assert(host.coal(s)).timing(v) end
    if timber_cargo(v.cargo) then arrival.slice=assert(host.timber(s)).timing(v) end
    local capacity=Sim.vehicle_capacity and Sim.vehicle_capacity(v) or Sim.vehicles[v.engine].capacity
    local l=Loading.begin(st,v,capacity,flags,arrival)
    l.arrived_tick=tick
    v.loaded_at=st.id
    v.stock_loading_complete=nil
    v.status=loading_name(v.cargo)
    if v.cargo=="passenger" then
      -- Initialize before recording the visual first arrival. Otherwise
      -- the legacy migration treats today's marker as a prior pickup.
      Rating.status(s,st)
      local first=not flags.no_load and st.passenger_service_day==nil
      if first then st.passenger_service_day=s.day end
      push(s,v,"arrival",st,tick,{first=first})
    end
    return l
  end

  -- Call after rating and house production, before movement. Return road
  -- departure candidates in stock vehicle-ID order; actual exit belongs
  -- to the movement adapter. Skipped whole ticks are programmer errors.
  function M.tick(s,tick)
    if s.stock_load_tick then
      if tick==s.stock_load_tick then return {},{} end
      assert(tick==s.stock_load_tick+1,"Stock loading clock skipped or reversed a tick")
    end
    s.stock_load_tick=tick
    local ids,departures,rounds={},{},{}
    for id,st in pairs(s.stations) do
      if st.loading_order and #st.loading_order>0 then ids[#ids+1]=id end
    end
    table.sort(ids)
    local api=opts(s,tick)
    local parked_tram=s.tram_pilot and s.tram_pilot.carrier
    local carriers=(parked_tram or s.stock_tram_fleet and next(s.stock_tram_fleet)) and
      setmetatable({},{__index=function(_,id)return loading_vehicle(s,id)end}) or s.fleet
    for _,sid in ipairs(ids) do
      local st=s.stations[sid]
      local aliases={}
      for _,id in ipairs(st.loading_order) do
        local v=assert(carriers[id],"Missing vehicle in saved loading order")
        aliases[id]={stopped=v.stopped,broken=v.broken}
        -- Stock station transfers are separate; a depot fault blocks the
        -- road controller's leave decision, not existing reservations.
        v.stopped=not v.running or v.stopped
        local fault=v.road_fault
        if fault and (fault.breakdown_ctr==1 or fault.breakdown_ctr==2) then v.broken=true end
      end
      local slice,leave=Loading.tick(st,carriers,api)
      if api.station_done then api.station_done(st) end
      for id,saved in pairs(aliases) do
        local v=carriers[id];v.stopped,v.broken=saved.stopped,saved.broken
      end
      for _,event in ipairs(slice) do
        event.tick=tick;event.station=sid;rounds[#rounds+1]=event
      end
      for _,id in ipairs(leave) do departures[#departures+1]=id end
      for _,id in ipairs(st.loading_order) do
        local v=carriers[id]
        if not v.running then v.status="Stopped"
        elseif v.load_state.finished then v.status="Waiting for departure"
        elseif v.load_state.full then v.status="Waiting for full load"
        else v.status=loading_name(v.cargo) end
      end
    end
    table.sort(departures)
    return departures,rounds
  end
  function M.leave(s,v,tick,destroyed)
    local l=v.load_state
    if not l then return false end
    local st=assert(s.stations[l.station],"Cannot remove an occupied stock station")
    local api=opts(s,tick,v.cargo=="coal",timber_cargo(v.cargo))
    Loading.leave(st,v,api,destroyed)
    if api.station_done then api.station_done(st) end
    v.stock_loading_complete=not destroyed and st.id or nil
    if v.stop_requested then
      v.stop_requested=nil;v.running=false;v.status="Stopped"
    end
    return true
  end

  -- Vehicle::Crash counts reserved passengers before destroying held
  -- packets. Existing completed deliveries settle, with no new fare.
  function M.crash(s,v,tick)
    if v.crashed or not M.handles(s,v) then return end
    local n=v.cargo=="passenger" and (v.units+(v.load_state and v.load_state.reserved_units or 0)) or 0
    M.leave(s,v,tick,true)
    v.crashed,v.running,v.stop_requested,v.stock_loading_complete=true,false,nil,nil
    v.units,v.batches,v.status=0,{},"Flooded"
    return n
  end

  -- Must replace s.daily legacy age for managed vehicles (including those
  -- parked, stopped or in a depot). Put after movement on each same tick.
  function M.age_vehicle(s,v,tick)
    if not M.handles(s,v) then return end
    if v.stock_aged_tick==tick then return end
    if v.stock_aged_tick then assert(tick==v.stock_aged_tick+1,"Road cargo aging tick skipped") end
    local period=v.stock_tram and v.stock_tram.aging or
      (v.cargo=="mail" and Mail.engine.cargo_aging_ticks or 185)
    if v.cargo=="coal" then local _,ticks=assert(host.coal(s)).timing(v);period=ticks end
    if timber_cargo(v.cargo) then local _,ticks=assert(host.timber(s)).timing(v);period=ticks end
    Loading.age_vehicle(v,1,period)
    v.stock_aged_tick=tick
  end
  return M
end
