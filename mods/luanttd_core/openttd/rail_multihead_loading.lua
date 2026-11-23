-- SPDX-License-Identifier: GPL-2.0-only
-- Pinned 16.0-RC1 economy.cpp LoadUnloadVehicle/PrepareUnload/ReserveConsist.
-- Shared ordered train bodies / aircraft compartments. One station queue,
-- one carrier visit/timer and CargoPayment; independent cargo stores.
local M={}
function M.create(Loading,Timing)
  local C={}
  local step=5
  local function copy_ops(ops)
    local out={}
    for k,v in pairs(ops) do out[k]=v end
    out.part_of_consist,out.slice=true,step
    return out
  end
  local function add(total,p)
    for _,k in ipairs({"route","visual","transfer","delivered"}) do total[k]=total[k]+p[k] end
  end
  function C.bodies(v,with_coach,seats_per_head)
    assert(seats_per_head and seats_per_head>0)
    v.linked_heads=true
    v.carrying_parts={}
    local count=with_coach and 3 or 2
    for i=1,count do
      local role=i==1 and "front" or i==count and "rear" or "carriage"
      v.carrying_parts[i]={id=v.id,owner=v.owner,mode=v.mode,cargo=v.cargo,
        cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=1,
        batches={},units=0,part=i,role=role,capacity=role=="carriage" and 40 or seats_per_head}
    end
    return v.carrying_parts
  end
  function C.coaches(v,count)
    v.carrying_parts={}
    for i=1,count do
      v.carrying_parts[i]={id=v.id,owner=v.owner,mode=v.mode,cargo=v.cargo,
        cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=1,
        batches={},units=0,part=i+1,role="carriage",capacity=40}
    end
    return v.carrying_parts
  end
  function C.town_wagons(v,parts,Roster,linked_express,advanced)
    if linked_express then assert(#parts==3);v.linked_heads=true end
    local seen={}
    v.carrying_parts={}
    for i,part in ipairs(parts) do
      local stock=assert(Roster.entry(part.stock))
      local expected=linked_express and (i==2 and 27 or 22)
      local compatible=expected and stock.stock_id==expected or not expected and
        ((not advanced and (stock.stock_id==27 or stock.stock_id==28)) or
          advanced and stock.railtype==advanced and stock.kind=="wagon" and
          (stock.cargo=="passenger" or stock.cargo=="mail"))
      assert(compatible and not seen[part.body_id] and part.index==i+(linked_express and 0 or 1),
        "Invalid or duplicated physical town wagon")
      seen[part.body_id]=true
      v.carrying_parts[i]={id=v.id,body_id=part.body_id,stock=stock.stock_id,owner=v.owner,mode=v.mode,
        cargo=stock.cargo,cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=1,
        batches={},units=0,part=part.index,role=linked_express and (i==1 and "front_mail" or i==3 and "rear_mail" or "carriage") or
          (stock.cargo=="mail" and "mail_van" or "carriage"),
        capacity=stock.capacity,slice=stock.load_amount,aging=stock.cargo_age_ticks}
    end
    return v.carrying_parts
  end
  function C.aircraft(v,stock)
    -- RC1 Aircraft::CmdBuildAircraft: the primary carries people; its
    -- linked shadow stores Mail. They share the one terminal position.
    assert(v.mode=="air" and stock.mail>0 and not v.load_state)
    local passengers={id=v.id,owner=v.owner,mode=v.mode,cargo="passenger",
      cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=v.cargo_age_counter,
      batches=v.batches,units=v.units,part=1,role="passenger_cabin",
      capacity=stock.cap,slice=stock.slice,aging=stock.aging}
    local mail={id=v.id,owner=v.owner,mode=v.mode,cargo="mail",
      cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=1,
      batches={},units=0,part=2,role="mail_hold",
      capacity=stock.mail,slice=math.ceil(stock.slice/4),aging=stock.aging}
    v.carrying_parts={passengers,mail}
    v.batches={}
    return v.carrying_parts
  end
  function C.begin(st,v,tiles,flags,ops,visit)
    local payment={route=0,visual=0,transfer=0,delivered=0}
    if v.cargo=="mixed" then payment.by_cargo={} end
    local out={station=st.id,ticks=Timing.initial,elapsed=0,capacity=0,reserved_units=0,
      gradual=ops.gradual~=false,full=not not flags.full,full_any=flags.full_any,wait=flags.wait or 0,lateness=flags.lateness or 0,
      no_load=not not flags.no_load,finished=false,payment=payment}
    local child_ops=copy_ops(ops)
    for i,body in ipairs(v.carrying_parts) do
      body.visit,body.cargo_tile=visit,tiles[i]
      local capacity=body.capacity or seat_count -- old paired service snapshots
      out.capacity=out.capacity+capacity
      child_ops.slice=body.slice or step
      local l=Loading.begin(st,body,capacity,flags,child_ops)
      add(payment,l.payment)
      if payment.by_cargo then
        local detail=payment.by_cargo[body.cargo]
        if not detail then detail={route=0,visual=0,transfer=0,delivered=0};payment.by_cargo[body.cargo]=detail end
        add(detail,l.payment)
      end
      l.payment=nil
    end
    st.loading_order[#st.loading_order+1]=v.id
    v.load_state=out
    return out
  end
  function C.reserve(st,v,ops)
    local l=v.load_state
    l.reserved_units=0
    local bodies=v.carrying_parts
    local function reserve(body)
      Loading.body_reserve(st,body,ops)
      l.reserved_units=l.reserved_units+body.load_state.reserved_units
    end
    -- Source ReserveConsist calls IterateVehicleParts on the front,
    -- which visits its linked rear immediately. Then the independent
    -- carriage is reached by the outer loop. Actual load/unload timing
    -- instead scans physical order: front, carriage, rear.
    if v.linked_heads then
      reserve(bodies[1])
      reserve(bodies[#bodies])
      if #bodies==3 then reserve(bodies[2]) end
    else
      for _,body in ipairs(bodies) do reserve(body) end
    end
  end
  local function settle(st,v,ops)
    local payment=v.load_state.payment
    if payment and ops.payment then ops.payment(st,v,payment) end
    v.load_state.payment=nil
  end
  function C.round(st,v,ops)
    local l=v.load_state
    local meta={vehicle=v.id,loaded=0,unloaded=0,retry_unload=false,gradual=l.gradual,full=l.full,
      full_slice=false,reservations=0,cargo_not_full=false,consist=true,elapsed=l.elapsed,wait=l.wait,lateness=l.lateness}
    v.units,l.reserved_units=0,0
    local slices,open,full={},{},{}
    for _,body in ipairs(v.carrying_parts) do
      local bs=body.load_state
      bs.stop_loading=l.stop_loading
      local m=Loading.body_round(st,body,ops,l.payment)
      meta.loaded,meta.unloaded=meta.loaded+m.loaded,meta.unloaded+m.unloaded
      -- There is one bit per CargoID. A later body's unsuccessful
      -- *attempt* clears this bit; seeing no waiting cargo does not.
      if m.attempted then
        slices[body.cargo]=m.full_slice or nil
        meta.reservations=meta.reservations+m.reservations
      end
      meta.retry_unload=meta.retry_unload or m.retry_unload
      if not m.unloading and not bs.no_load and not bs.stop_loading then
        if m.cargo_not_full then open[body.cargo]=true else full[body.cargo]=true end
      end
      meta.cargo_not_full=meta.cargo_not_full or m.cargo_not_full
      l.reserved_units=l.reserved_units+bs.reserved_units
      v.units=v.units+body.units
    end
    meta.full_slice=next(slices)~=nil
    if meta.unloaded==0 and not meta.retry_unload then settle(st,v,ops) end
    l.stop_loading=false
    if meta.loaded>0 or meta.unloaded>0 or meta.retry_unload then
      l.stop_loading=meta.unloaded==0 and not meta.retry_unload and not meta.full_slice and
        meta.reservations==0 and not l.full and l.elapsed>=Timing.wait_threshold(l.wait,l.lateness)
    else
      local complete_type=false
      if l.full_any then
        for cargo in pairs(full) do if not open[cargo] then complete_type=true;break end end
      end
      -- RC1 economy.cpp: for Full Load Any, an aircraft with primary
      -- passenger cargo may not depart until that cabin is itself full.
      local cabin=v.mode=="air" and v.carrying_parts[1]
      local waiting_for_cabin=l.full_any and cabin and cabin.cargo=="passenger" and cabin.units<cabin.capacity
      l.finished=not (l.full and (waiting_for_cabin or meta.cargo_not_full and not complete_type))
      if not l.finished and ops.refresh_link then ops.refresh_link(st,v) end
    end
    -- The ordered station sweep applies the actual mode delay (including rail overhang).
    l.ticks=1
    return meta
  end
  function C.leave(st,v,ops)
    settle(st,v,ops)
    local child_ops=copy_ops(ops)
    for _,body in ipairs(v.carrying_parts) do
      Loading.leave(st,body,child_ops)
      body.cargo_tile=nil
    end
    v.load_state=nil
    for i,id in ipairs(st.loading_order) do
      if id==v.id then table.remove(st.loading_order,i);return end
    end
    error("Missing combined carrier loading position")
  end
  function C.age(v,period)
    for _,body in ipairs(v.carrying_parts) do Loading.age_vehicle(body,1,body.aging or period) end
  end
  return C
end
return M
