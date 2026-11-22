-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 road slice rules from economy.cpp LoadUnloadVehicle and
-- UpdateLoadUnloadTicks, and vehicle.cpp Vehicle::HandleLoading.
local T={initial=1,road_gradual_wait=20,retry_wait=20,stock_road_slice=8}
function T.wait_threshold(wait,lateness)
  return math.max(wait-lateness,0)
end

-- A single road body and one cargo: full-load-all and full-load-any have
-- identical completion rules here. Timetabling is orthogonal to a pulse.
function T.pulse(m)
  local activity=m.loaded>0 or m.unloaded>0 or m.retry_unload
  if activity then
    local delay=m.gradual and T.road_gradual_wait or m.loaded+m.unloaded
    local stop=not (m.unloaded>0 or m.retry_unload) and not m.full_slice
      and m.reservations==0 and not m.full
      and m.elapsed>=T.wait_threshold(m.wait,m.lateness)
    return math.max(1,delay),not not stop,m.finished,false
  end
  local complete=not (m.full and m.cargo_not_full)
  return T.retry_wait,false,complete,not complete
end

-- The ordinary road controller increments current_order_time before
-- checking for departure. Non-first invocations in one tick don't leave.
function T.can_leave(first,finished,elapsed,wait,lateness)
  return first and finished and elapsed>=T.wait_threshold(wait,lateness)
end
return T
