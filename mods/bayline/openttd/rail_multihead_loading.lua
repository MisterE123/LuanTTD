-- SPDX-License-Identifier: GPL-2.0-only
-- Pinned 14.1 economy.cpp LoadUnloadVehicle/PrepareUnload/ReserveConsist.
-- One rail station queue, one train visit/timer, one CargoPayment,
-- independent manual passenger cargo stores in stock predecessor order.
local M={}
function M.create(Loading,Timing)
  local C={}
  local seat_count,step=38,5
  local function copy_ops(ops)
    local out={}
    for k,v in pairs(ops) do out[k]=v end
    out.part_of_consist,out.slice=true,step
    return out
  end
  local function add(total,p)
    for _,k in ipairs({"route","visual","transfer","delivered"}) do total[k]=total[k]+p[k] end
  end
  function C.bodies(v,with_coach)
    v.carrying_parts={}
    local count=with_coach and 3 or 2
    for i=1,count do
      local role=i==1 and "front" or i==count and "rear" or "carriage"
      v.carrying_parts[i]={id=v.id,owner=v.owner,mode=v.mode,cargo=v.cargo,
        cached_max_speed=v.cached_max_speed,built=v.built,cargo_age_counter=1,
        batches={},units=0,part=i,role=role,capacity=role=="carriage" and 40 or seat_count}
    end
    return v.carrying_parts
  end
  function C.begin(st,v,tiles,flags,ops,visit)
    local payment={route=0,visual=0,transfer=0,delivered=0}
    local out={station=st.id,ticks=Timing.initial,elapsed=0,capacity=0,reserved_units=0,
      gradual=ops.gradual~=false,full=not not flags.full,wait=flags.wait,lateness=flags.lateness,
      no_load=not not flags.no_load,finished=false,payment=payment}
    local child_ops=copy_ops(ops)
    for i,body in ipairs(v.carrying_parts) do
      body.visit,body.cargo_tile=visit,tiles[i]
      local capacity=body.capacity or seat_count -- old paired service snapshots
      out.capacity=out.capacity+capacity
      local l=Loading.begin(st,body,capacity,flags,child_ops)
      add(payment,l.payment)
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
    reserve(bodies[1])
    reserve(bodies[#bodies])
    if #bodies==3 then reserve(bodies[2]) end
  end
  local function settle(st,v,ops)
    local payment=v.load_state.payment
    if payment and ops.payment then ops.payment(st,v,payment) end
    v.load_state.payment=nil
  end
  function C.round(st,v,ops)
    local l=v.load_state
    local meta={vehicle=v.id,loaded=0,unloaded=0,retry_unload=false,gradual=l.gradual,full=l.full,
      full_slice=false,reservations=0,cargo_not_full=false,consist=true}
    v.units,l.reserved_units=0,0
    for _,body in ipairs(v.carrying_parts) do
      local bs=body.load_state
      bs.stop_loading=l.stop_loading
      local m=Loading.body_round(st,body,ops,l.payment)
      meta.loaded,meta.unloaded=meta.loaded+m.loaded,meta.unloaded+m.unloaded
      -- There is one bit per CargoID. A later body's unsuccessful
      -- *attempt* clears this bit; seeing no waiting cargo does not.
      if m.attempted then
        meta.full_slice=m.full_slice
        meta.reservations=meta.reservations+m.reservations
      end
      meta.retry_unload=meta.retry_unload or m.retry_unload
      meta.cargo_not_full=meta.cargo_not_full or m.cargo_not_full
      l.reserved_units=l.reserved_units+bs.reserved_units
      v.units=v.units+body.units
    end
    if meta.unloaded==0 and not meta.retry_unload then settle(st,v,ops) end
    l.stop_loading=false
    if meta.loaded>0 or meta.unloaded>0 or meta.retry_unload then
      l.stop_loading=meta.unloaded==0 and not meta.retry_unload and not meta.full_slice and
        meta.reservations==0 and not l.full and l.elapsed>=Timing.wait_threshold(l.wait,l.lateness)
    else
      l.finished=not (l.full and meta.cargo_not_full)
      if not l.finished and ops.refresh_link then ops.refresh_link(st,v) end
    end
    -- Actual rail overhang/delay applied by the ordered station sweep.
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
    error("Missing combined rail loading position")
  end
  function C.age(v,period)
    for _,body in ipairs(v.carrying_parts) do Loading.age_vehicle(body,1,period) end
  end
  return C
end
return M
