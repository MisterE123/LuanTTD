-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 order_cmd.cpp CmdCloneOrder, DeleteVehicleOrders and
-- CmdDeleteOrder: order data can be linked, a vehicle's cursor cannot.
-- Lua host adapter for ROAD station orders only. The caller defines
-- CanVehicleUseStation and stops a vehicle before replacing its list.
local O={}
local OWNER_CAP=60

local function duplicate(orders)
  local result={}
  for i,order in ipairs(orders) do
    local item={}
    for k,v in pairs(order) do item[k]=v end
    result[i]=item
  end
  return result
end

function O.members(s,v)
  if not v.order_group then return {v} end
  local result={}
  for _,other in pairs(s.fleet) do
    if other.order_group==v.order_group and other.owner==v.owner then
      result[#result+1]=other
    end
  end
  table.sort(result,function(a,b) return a.id<b.id end)
  return result
end

local function detach(s,v)
  if not v.order_group then return end
  local group=O.members(s,v)
  v.order_group=nil
  if #group==2 then
    for _,other in ipairs(group) do
      if other~=v then other.order_group=nil end
    end
  end
end

-- Core state owns table identity while the game runs. Saved vehicle order
-- tables are rebound explicitly; this does not require serialization to
-- preserve Lua object sharing. No new pool is necessary for station orders
-- in the host's sixty vehicle, sixteen order limit.
function O.restore(s)
  local groups={}
  local greatest=0
  for _,v in pairs(s.fleet) do
    local key=v.order_group
    if key then
      assert(type(key)=="number" and key>=1 and key%1==0 and key<2^53,"bad road order group")
      greatest=math.max(greatest,key)
      local g=groups[key] or {};groups[key]=g
      g[#g+1]=v
    end
  end
  for _,g in pairs(groups) do
    table.sort(g,function(a,b) return a.id<b.id end)
    local first=g[1]
    assert(#g<=OWNER_CAP,"oversized road order group")
    if #g==1 then first.order_group=nil end
    for i=2,#g do
      local v=g[i]
      assert(v.owner==first.owner and ((v.cargo=="passenger")==(first.cargo=="passenger")),
        "road order group crosses operator or vehicle class")
      assert(#v.orders==#first.orders,"divergent road order lists")
      for j,a in ipairs(first.orders) do
        local b=v.orders[j]
        assert(a.station==b.station and a.action==b.action,"divergent road order")
      end
      v.orders=first.orders
    end
  end
  local next_id=s.next_road_order_group or 1
  assert(type(next_id)=="number" and next_id>=1 and next_id%1==0 and next_id<2^53,
    "bad road order group allocator")
  if greatest>0 or s.next_road_order_group then
    s.next_road_order_group=math.max(next_id,greatest+1)
  end
end

function O.stopped(v)
  return v and not v.running and not v.route and not v.road_return_depot
end

local function can_clone(s,owner,id,from,action,road,use)
  local dst=s.fleet[id]
  if not dst or dst.owner~=owner or not road(dst) then return nil,"Select your road vehicle." end
  if not O.stopped(dst) then return nil,"Stop the receiving vehicle first." end
  if action=="unshare" then return dst end
  if action~="copy" and action~="share" then return nil,"Unknown order-list action." end
  local src=s.fleet[from]
  if not src or src==dst or src.owner~=owner or not road(src) then
    return nil,"Choose a different road vehicle you own."
  end
  if action=="share" then
    if (src.cargo=="passenger")~=(dst.cargo=="passenger") then return nil,"Buses and trucks cannot share orders." end
    if dst.order_group and dst.order_group==src.order_group then return nil,"These vehicles already share orders." end
  end
  for _,order in ipairs(src.orders) do
    if (action=="copy" or use(src,order)) and not use(dst,order) then
      return nil,"The receiving vehicle cannot call at an ordered stop."
    end
  end
  return dst,src
end

function O.clone(s,owner,id,from,action,road,use)
  local dst,src=can_clone(s,owner,id,from,action,road,use)
  if not dst then return false,src end
  local old_index=dst.index
  local old_length=#dst.orders
  local orders,newindex
  if action=="unshare" then
    orders,newindex={},1 -- OpenTTD Stop Sharing clears this vehicle's list.
  else
    orders=action=="copy" and duplicate(src.orders) or src.orders
    newindex=old_length==#orders and old_index or 1
  end
  if action=="share" and not src.order_group then
    local number=s.next_road_order_group or 1
    if number>=2^53-1 then return false,"Shared list IDs exhausted." end
    src.order_group=number;s.next_road_order_group=number+1
  end
  detach(s,dst)
  dst.orders,dst.index=orders,newindex
  if action=="share" then dst.order_group=src.order_group end
  return true,action=="share" and "Orders shared." or action=="copy" and "Orders copied." or "Sharing stopped; this list is now empty."
end

function O.release(s,v) detach(s,v) end

-- Bayline currently permits edits only while the affected vehicles are
-- stopped, so no active order/cargo packet is changed by this helper.
function O.can_edit(s,v)
  local members=O.members(s,v)
  for _,other in ipairs(members) do
    if not O.stopped(other) then return nil,"Stop every vehicle sharing these orders before editing." end
  end
  return members
end

function O.cursor_after_remove(v,index)
  if v.index>index then v.index=v.index-1 end
  if v.index>#v.orders then v.index=1 end
end

function O.cursor_after_move(v,from,to)
  if v.index==from then v.index=to
  elseif v.index==to then v.index=from end
end

return O
