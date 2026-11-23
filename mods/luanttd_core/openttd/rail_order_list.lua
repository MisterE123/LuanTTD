-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright OpenTTD contributors. OpenTTD 16.0-RC1.
-- vehicle_base.h: SkipToNextRealOrderIndex, IncrementImplicitOrderIndex,
-- IncrementRealOrderIndex and UpdateRealOrderIndex. The real/implicit
-- indices are stock zero-based indexes; only Lua table access is adjusted.
local O={MAX_ORDERS=254}
local function implicit(order) return type(order)=="table" and order.kind=="implicit" end
local function manual(orders)
  for _,o in ipairs(orders) do if not implicit(o) then return true end end
  return false
end
local function wrapped(i,count)
  i=i+1
  return i>=count and 0 or i
end
local function next_real(orders,index)
  if not manual(orders) then index.real=0;return end
  repeat index.real=wrapped(index.real,#orders)
  until not implicit(orders[index.real+1])
end
function O.increment_implicit(orders,index)
  if index.implicit==index.real then next_real(orders,index) end
  assert(index.real==0 or index.real<#orders)
  repeat index.implicit=wrapped(index.implicit,#orders)
  until index.implicit==index.real or implicit(orders[index.implicit+1])
end
function O.increment_real(orders,index)
  if index.implicit==index.real then O.increment_implicit(orders,index)
  else next_real(orders,index) end
end
function O.update_real(orders,index)
  if index.real>=#orders then index.real=0 end
  if manual(orders) then
    while implicit(orders[index.real+1]) do index.real=wrapped(index.real,#orders) end
  else index.real=0 end
end
function O.next_manual(orders,index)
  local next_={real=index.real,implicit=index.implicit}
  O.increment_real(orders,next_)
  O.update_real(orders,next_)
  local o=orders[next_.real+1]
  if o and not implicit(o) then return o,next_ end
end

-- order_cmd.cpp InsertOrder maintains both indices of assigned stock
-- vehicles when insertion is before their current corresponding orders.
function O.insert(orders,index,slot,order)
  if #orders>=O.MAX_ORDERS or slot<0 or slot>#orders or slot%1~=0 then return false end
  table.insert(orders,slot+1,order)
  if slot<=index.real and index.real+1<#orders then index.real=index.real+1 end
  if slot==index.implicit then index.suppress_implicit=true end
  if slot<=index.implicit and index.implicit+1<#orders then index.implicit=index.implicit+1 end
  for i,o in ipairs(orders) do
    if type(o)=="table" and o.kind=="conditional" then
      local to=o.skip_to
      if to>=slot then o.skip_to=to+1 end
      if to==i-1 then o.skip_to=(to+1)%#orders end
    end
  end
  return true
end
-- order_cmd.cpp CmdSkipToOrder. The host calls LeaveStation for an
-- active loading order and invalidates timetable/unbunching state.
function O.skip(orders,index,slot)
  if type(slot)~="number" or slot%1~=0 or slot<0 or slot>=#orders or
      #orders<2 or slot==index.implicit then return false end
  index.real,index.implicit=slot,slot
  O.update_real(orders,index)
  return true
end

-- order_cmd.cpp CmdMoveOrder: zero-based rotation, preserving the two
-- cursor identities and re-targeting conditional jumps within that range.
function O.move(orders,index,from,to)
  if from==to or from<0 or to<0 or from>=#orders or to>=#orders then return false end
  local moved=table.remove(orders,from+1)
  table.insert(orders,to+1,moved)
  local function remap(n)
    if n==from then return to end
    if n>from and n<=to then return n-1 end
    if n<from and n>=to then return n+1 end
    return n
  end
  index.real,index.implicit=remap(index.real),remap(index.implicit)
  for _,o in ipairs(orders) do
    if type(o)=="table" and o.kind=="conditional" then o.skip_to=remap(o.skip_to) end
  end
  return true
end

-- DeleteOrder's index branch. The caller cancels a deleted active
-- loading order and handles timetable/unbunching windows when relevant.
function O.delete(orders,index,slot)
  if slot<0 or slot>=#orders then return false end
  table.remove(orders,slot+1)
  if slot<index.real then index.real=index.real-1
  elseif slot==index.real then O.update_real(orders,index) end
  if slot<index.implicit then index.implicit=index.implicit-1
  elseif slot==index.implicit then
    if index.implicit>=#orders then index.implicit=0 end
    while index.implicit~=index.real and not implicit(orders[index.implicit+1]) do
      index.implicit=wrapped(index.implicit,#orders)
    end
  end
  for i,o in ipairs(orders) do
    if type(o)=="table" and o.kind=="conditional" then
      local to=o.skip_to
      if to>=slot then to=math.max(to-1,0) end
      if to==i-1 then to=(to+1)%#orders end
      o.skip_to=to
    end
  end
  return true
end
-- order_cmd.cpp CmdCloneOrder / CO_COPY (16.0-RC1). The host checks
-- primary vehicle type, ownership and station-facility access. Then it
-- constructs a new, independent list and resets indices only if the
-- order count changed. Neither the live order nor the source cursor is copied.
function O.copy(source,dest,index,usable)
  if type(source)~="table" or #source>O.MAX_ORDERS then return nil,"Invalid number of orders." end
  local function deep(v)
    if type(v)~="table" then return v end
    local result={}
    for key,x in pairs(v) do result[key]=deep(x) end
    return result
  end
  local out={}
  for i,o in ipairs(source) do
    if type(o)~="table" or not usable(o) then
      return nil,("Order %d: this train cannot use that destination."):format(i)
    end
    out[i]=deep(o)
  end
  local cursor=#source==#dest and deep(index) or {real=0,implicit=0}
  return out,cursor
end
return O
