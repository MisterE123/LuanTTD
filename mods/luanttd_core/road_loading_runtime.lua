-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 one-body road loading, manual distribution. Stock sources:
-- economy.cpp PrepareUnload, GetLoadAmount, LoadUnloadStation, LoadUnloadVehicle
-- and CargoPayment; cargopacket.cpp Stage, ChooseAction, Unload and Reserve;
-- cargoaction.cpp packet movement; vehicle.cpp BeginLoading/HandleLoading.
-- Callbacks supply actual station acceptance, payments, and presentation.
-- Optional train assembly provides per-body parameters and one shared payment.
return function(Timing,Packets)
  local L={}
  local floor,min,max=math.floor,math.min,math.max
  local function trunc(n) return n<0 and -floor(-n) or floor(n) end

  local function queue(st,v,ops)
    if ops.queue then return ops.queue(st,v) end
    st.stock=st.stock or {}
    st.stock[v.cargo]=st.stock[v.cargo] or {}
    return st.stock[v.cargo]
  end
  local function append_packet(q,p)
    -- Source's manual next-hop bucket checks backward through all packets
    -- of this designation. A merge retains the existing packet's route
    -- details and adds both counts and feeder shares.
    for i=#q,1,-1 do
      local old=q[i]
      if old.origin_tile==p.origin_tile and old.origin_station==p.origin_station
          and (old.age or 0)==(p.age or 0) and old.source==p.source
          and old.source_type==p.source_type and old.units+p.units<=65535 then
        old.units=old.units+p.units
        if old.feeder_share or p.feeder_share then
          old.feeder_share=(old.feeder_share or 0)+(p.feeder_share or 0)
        end
        return
      end
    end
    q[#q+1]=p
  end
  local function append(st,v,p,ops)
    if ops.enqueue then return ops.enqueue(st,v,p) end
    append_packet(queue(st,v,ops),p)
  end
  local function take_packet(p,n)
    if n==p.units then return p end
    local take=Packets.split(p,n)
    if p.feeder_share then
      take.feeder_share=trunc(p.feeder_share*n/(n+p.units))
      p.feeder_share=p.feeder_share-take.feeder_share
    end
    return take
  end
  local function shift(q,n,move)
    local size=#q
    if size>=32 and n>=2 and q[1].units<n then
      -- RC1 StationCargoList::ShiftCargo pulls a FIFO prefix (and
      -- possibly part of its next packet). Its list erases do not move
      -- the entire waiting tail for each boarded packet. The two live
      -- destinations are the vehicle's batches/reservations; callbacks
      -- never modify this distinct source queue during a move.
      local left,i=n,1
      while left>0 and i<=size do
        local p=q[i]
        local part=take_packet(p,min(left,p.units))
        if part==p then i=i+1 end
        move(part)
        left=left-part.units
      end
      local removed=i-1
      for j=i,size do q[j-removed]=q[j] end
      for j=size-removed+1,size do q[j]=nil end
      return n-left
    end
    local left=n
    while left>0 and #q>0 do
      local p=q[1]
      local part=take_packet(p,min(left,p.units))
      if p==part then table.remove(q,1) end
      move(part)
      left=left-part.units
    end
    return n-left
  end
  local function accepted(st,v,ops)
    return ops.accepts and ops.accepts(st,v) or false
  end

  -- Flags are independent upstream. The current game UI's compact orders
  -- can map transfer/unload to their respective flag plus no_load.
  function L.compact_order(action)
    return {full=action=="full",force_unload=action=="unload",
            transfer=action=="transfer",no_load=action=="transfer" or action=="unload"}
  end
  function L.designation(p,station_id,accept,order)
    if order.no_unload then return nil end
    local deliver=accept and p.origin_station~=station_id
    if order.force_unload and deliver then return "deliver" end
    if order.force_unload or order.transfer then return "transfer" end
    if deliver then return "deliver" end
  end

  -- On arrival classify packet destinations once, and stage transfers
  -- ahead of deliveries. Stock places each transfer at the list head,
  -- reversing their original order; deliveries/keeps preserve order.
  function L.begin(st,v,capacity,order,ops)
    assert(v.id and st.id and not v.load_state)
    assert(capacity>0,"Road loading needs one positive-capacity body")
    order=order or {}
    local l={station=st.id,ticks=Timing.initial,elapsed=0,capacity=capacity,
      reserved={},reserved_units=0,gradual=ops.gradual~=false,
      slice=max(1,ops.slice or Timing.stock_road_slice),finished=false,
      wait=order.wait or 0,lateness=order.lateness or 0,
      full=not not order.full,no_load=not not order.no_load,force_unload=not not order.force_unload,
      transfer=not not order.transfer,unload={},unload_units=0,
      payment={route=0,visual=0,transfer=0,delivered=0}}
    local transfer,deliver,keep={},{},{}
    local accept=accepted(st,v,ops)
    local units=0
    for _,p in ipairs(v.batches or {}) do
      local action=L.designation(p,st.id,accept,order)
      units=units+p.units
      if action=="transfer" then
        local share=0
        if ops.transfer_income then
          local value=ops.transfer_income(st,v,p)
          share=trunc((value-(p.feeder_share or 0))*(ops.feeder_percent or 75)/100)
          p.feeder_share=(p.feeder_share or 0)+share
        end
        l.payment.transfer=l.payment.transfer+share
        transfer[#transfer+1]={packet=p,action=action}
      elseif action=="deliver" then deliver[#deliver+1]={packet=p,action=action}
      else keep[#keep+1]=p end
      if action then l.unload_units=l.unload_units+p.units end
    end
    assert(units<=capacity,"Stored road cargo exceeds capacity")
    for i=#transfer,1,-1 do l.unload[#l.unload+1]=transfer[i] end
    for _,p in ipairs(deliver) do l.unload[#l.unload+1]=p end
    l.unloading=l.unload_units>0
    v.load_state=l
    v.batches=keep
    v.units=units
    st.loading_order=st.loading_order or {}
    if not ops.part_of_consist then st.loading_order[#st.loading_order+1]=v.id end
    return l
  end

  local function pick(p,st,v,ops)
    if ops.pickup then ops.pickup(st,v,p)
    elseif ops.xy then Packets.pickup(p,st,ops.xy) end
  end
  local function drop(p,st,v,ops)
    if ops.drop then ops.drop(st,v,p)
    elseif ops.xy and p.origin_tile then Packets.drop(p,st,ops.xy) end
  end
  local function can_load(st,v,ops)
    return not ops.can_load or ops.can_load(st,v)
  end
  local function reserve(st,v,ops)
    local l=v.load_state
    if not l.full or not can_load(st,v,ops) then return end
    -- RemainingCount excludes still-to-unload units. ReservedCount is
    -- counted separately from onboard space; rating sees only available.
    local cap=l.capacity-(v.units-l.unload_units+l.reserved_units)
    if cap<=0 then return end
    local amount=shift(queue(st,v,ops),cap,function(p)
      pick(p,st,v,ops)
      append_packet(l.reserved,p)
    end)
    l.reserved_units=l.reserved_units+amount
  end
  local function settle(st,v,ops)
    local p=v.load_state.payment
    if p and ops.payment then ops.payment(st,v,p) end
    v.load_state.payment=nil
  end

  -- Per-physical-body scan. An optional train-level handler owns timing
  -- and the single CargoPayment; otherwise the original one-body path below.
  function L.body_round(st,v,ops,payment)
    local l=v.load_state
    local loaded,unloaded,delivered,transferred=0,0,0,0
    local retry,full_slice,cargo_not_full=false,false,false
    local attempted,unloading=false,l.unloading
    local pay=payment or l.payment
    if l.unloading then
      local limit=l.gradual and min(l.unload_units,l.slice) or l.unload_units
      if not accepted(st,v,ops) then
        -- Acceptance may change after arrival. The stock command keeps
        -- normal deliveries, but forced orders turn them into transfers.
        local unload,kept={},{}
        for _,item in ipairs(l.unload) do
          if item.action=="deliver" and not (l.force_unload or l.transfer) then
            retry=true
            kept[#kept+1]=item.packet
            l.unload_units=l.unload_units-item.packet.units
          else
            if item.action=="deliver" then item.action="transfer" end
            unload[#unload+1]=item
          end
        end
        l.unload=unload
        for _,p in ipairs(v.batches) do kept[#kept+1]=p end
        v.batches=kept
        -- Now RemainingCount may exceed capacity if we already reserved.
        local excess=v.units-l.unload_units+l.reserved_units-l.capacity
        local i=#l.reserved
        while excess>0 and i>0 do
          local p=l.reserved[i]
          local part=take_packet(p,min(excess,p.units))
          if part==p then table.remove(l.reserved,i) end
          drop(part,st,v,ops);append(st,v,part,ops)
          excess=excess-part.units
          l.reserved_units=l.reserved_units-part.units
          i=i-1
        end
      end
      while limit>0 and #l.unload>0 do
        local item=l.unload[1]
        local p=take_packet(item.packet,min(limit,item.packet.units))
        if p==item.packet then table.remove(l.unload,1) end
        if item.action=="transfer" then
          if ops.transferred then ops.transferred(st,v,p) end
          drop(p,st,v,ops)
          append(st,v,p,ops)
          transferred=transferred+p.units
        else
          local income=ops.deliver and ops.deliver(st,v,p) or 0
          pay.route=pay.route+income
          pay.visual=pay.visual+income-(p.feeder_share or 0)
          pay.delivered=pay.delivered+p.units
          if pay.by_cargo then
            local detail=pay.by_cargo[v.cargo]
            if not detail then detail={route=0,visual=0,transfer=0,delivered=0};pay.by_cargo[v.cargo]=detail end
            detail.route=detail.route+income
            detail.visual=detail.visual+income-(p.feeder_share or 0)
            detail.delivered=detail.delivered+p.units
          end
          delivered=delivered+p.units
        end
        unloaded=unloaded+p.units
        limit=limit-p.units
        v.units=v.units-p.units
        l.unload_units=l.unload_units-p.units
      end
      if unloaded>0 then
        if ops.unloaded then ops.unloaded(st,v,unloaded) end
        -- Linked aircraft holds use the controller's one Empty trigger
        -- after the whole chain has finished unloading, not per body.
        if v.mode~="rail" and not v.part and v.units==0 and ops.emptied then ops.emptied(st,v) end
      end
      l.unloading=l.gradual and l.unload_units>0
    elseif not l.no_load and not l.stop_loading then
      local left=l.capacity-v.units
      if ops.attempt then ops.attempt(st,v,left) end
      if left>0 and can_load(st,v,ops) then
        local limit=l.gradual and min(left,l.slice) or left
        local from_reserved=l.reserved_units>0
        local q=from_reserved and l.reserved or queue(st,v,ops)
        attempted=#q>0
        if attempted and v.units==0 and ops.new_cargo then ops.new_cargo(st,v) end
        loaded=shift(q,limit,function(p)
          if not from_reserved then pick(p,st,v,ops) end
          append_packet(v.batches,p)
        end)
        if from_reserved then l.reserved_units=l.reserved_units-loaded end
        v.units=v.units+loaded
        full_slice=loaded==limit
        if loaded>0 and ops.loaded then ops.loaded(st,v,loaded) end
      end
      cargo_not_full=v.units<l.capacity
    end
    return {vehicle=v.id,loaded=loaded,unloaded=unloaded,delivered=delivered,transferred=transferred,
      attempted=attempted,unloading=unloading,retry_unload=retry,full_slice=full_slice,
      reservations=l.reserved_units,gradual=l.gradual,full=l.full,cargo_not_full=cargo_not_full,
      finished=l.finished,elapsed=l.elapsed,wait=l.wait,lateness=l.lateness}
  end
  L.body_reserve=reserve

  local function round(st,v,ops)
    local l=v.load_state
    local m=L.body_round(st,v,ops)
    if m.unloaded==0 and not m.retry_unload then settle(st,v,ops) end
    local refresh
    l.ticks,l.stop_loading,l.finished,refresh=Timing.pulse(m)
    if refresh and ops.refresh_link then ops.refresh_link(st,v) end
    if v.mode=="rail" and not l.unloading and m.loaded==0 and
       (m.unloaded>0 or m.retry_unload) and ops.emptied then ops.emptied(st,v) end
    return {vehicle=v.id,loaded=m.loaded,unloaded=m.unloaded,delivered=m.delivered,transferred=m.transferred}
  end

  function L.leave(st,v,ops,destroyed)
    local l=v.load_state
    if not l then return end
    assert(st.id==l.station)
    settle(st,v,ops)
    -- Vehicle::Crash does not transfer reserved packets back to the
    -- station. Ordinary departure still follows CancelReservation.
    if not destroyed then
      -- CancelReservation pops the reserved tail back to this station,
      -- not the other vehicle queues.
      for i=#l.reserved,1,-1 do
        local p=l.reserved[i]
        drop(p,st,v,ops)
        append(st,v,p,ops)
      end
      if #l.unload>0 then
        local onboard={}
        for _,item in ipairs(l.unload) do onboard[#onboard+1]=item.packet end
        for _,p in ipairs(v.batches) do onboard[#onboard+1]=p end
        v.batches=onboard
      end
    end
    v.load_state=nil
    if not ops.part_of_consist then
      for i,id in ipairs(st.loading_order) do
        if id==v.id then table.remove(st.loading_order,i);break end
      end
    end
  end

  -- One economy tick of a station, followed by each road controller's
  -- order-time increment and first departure check. Arrival order governs
  -- service/reservation. The caller should call leave() for departure
  -- candidates in the same tick before trying to move the vehicle. Stock
  -- can leave its loading order even if a blocked exit holds its position.
  function L.tick(st,vehicles,ops)
    local order=st.loading_order or {}
    local rounds,departures,last={},{},nil
    for i,id in ipairs(order) do
      local v=assert(vehicles[id])
      local l=assert(v.load_state)
      if not v.stopped and not v.crashed then
        l.ticks=l.ticks-1
        if l.ticks==0 then last=i end
      end
    end
    if last then
      for i=1,last do
        local v=vehicles[order[i]]
        if not v.stopped and not v.crashed then
          if v.carrying_parts then
            local c=assert(ops.consist,"Multiple cargo stores need one shared carrier controller")
            c.reserve(st,v,ops)
            if v.load_state.ticks==0 then rounds[#rounds+1]=c.round(st,v,ops) end
          else
            reserve(st,v,ops)
            if v.load_state.ticks==0 then rounds[#rounds+1]=round(st,v,ops) end
          end
        end
      end
    end
    for _,id in ipairs(order) do
      local v=vehicles[id]
      local l=v.load_state
      l.elapsed=l.elapsed+1
      if not v.stopped and not v.crashed and not v.broken
          and Timing.can_leave(true,l.finished,l.elapsed,l.wait,l.lateness) then
        departures[#departures+1]=id
      end
    end
    return rounds,departures
  end

  local function age_packet(p,times)
    p.age=min(65535,(p.age or 0)+times)
  end

  -- Call after the vehicle controller, stock now also ages reservations.
  -- A host still on daily aging must not also call the old aggregate rule.
  function L.age_vehicle(v,ticks,period)
    period=period or 185
    if period<=0 then return end
    local counter=v.cargo_age_counter or (v.passenger_age_ticks and period-v.passenger_age_ticks) or 1
    counter=min(counter,period)
    local elapsed=period-counter+ticks
    -- Almost every vehicle tick only decrements the stock countdown.
    if elapsed>=0 and elapsed<period then
      v.cargo_age_counter=period-elapsed
      return
    end
    local times=floor(elapsed/period)
    v.cargo_age_counter=period-elapsed%period
    if times>0 then
      for _,p in ipairs(v.batches or {}) do age_packet(p,times) end
      local l=v.load_state
      if l then
        for _,item in ipairs(l.unload) do age_packet(item.packet,times) end
        for _,p in ipairs(l.reserved) do age_packet(p,times) end
      end
    end
  end

  return L
end
