local O=dofile("mods/luanttd_core/openttd/road_order_list.lua")
local s={fleet={}}
local function unit(id,cargo,stops,owner)
  local v={id=id,owner=owner or "A",cargo=cargo,mode="road",orders={},index=1}
  for _,st in ipairs(stops) do v.orders[#v.orders+1]={station=st,action="normal"} end
  s.fleet[id]=v
  return v
end
local bus1=unit(1,"passenger",{1,2})
local bus2=unit(2,"passenger",{1,3})
local bus3=unit(3,"passenger",{2,1,3})
local truck=unit(4,"grain",{4,5})
local rival=unit(5,"passenger",{1,2},"B")
local other=unit(6,"goods",{4,5})
local use=function(v,o)
  if #v.orders==0 then return o.station<4 end
  return not (v.unusable and v.unusable[o.station]) and ((o.station<4)==(v.cargo=="passenger"))
end
local road=function(v) return v.mode=="road" end
local function clone(id,from,action) return O.clone(s,"A",id,from,action,road,use) end
bus2.index=2
assert(clone(2,1,"share"))
assert(bus1.order_group==bus2.order_group and bus1.orders==bus2.orders)
assert(bus2.index==2 and bus1.index==1) -- Equal list length preserves the receiver's current index.
assert(not clone(2,1,"share"))
assert(not clone(2,5,"share") and not clone(2,2,"copy"))
assert(not clone(4,1,"share") and not clone(4,1,"copy"))
assert(clone(3,1,"share") and bus3.index==1 and #O.members(s,bus1)==3)
bus1.running=true
assert(not O.can_edit(s,bus3))
assert(not clone(1,2,"unshare"))
bus1.running=false
assert(O.can_edit(s,bus2))
bus2.orders[1].action="full"
assert(bus1.orders[1].action=="full" and bus3.orders[1].action=="full")
assert(clone(3,1,"copy"))
assert(bus3.order_group==nil and #O.members(s,bus1)==2 and bus3.orders~=bus1.orders)
bus3.orders[1].action="normal"
assert(bus1.orders[1].action=="full")
assert(clone(2,nil,"unshare"))
assert(#bus2.orders==0 and bus2.index==1 and bus1.order_group==nil and #bus1.orders==2)
-- Share can retain an unusable stop which the source already cannot reach.
-- Independent copies may not silently inherit such an unreachable stop.
truck.unusable={[4]=true};other.unusable={[4]=true}
assert(not clone(6,4,"copy"))
assert(clone(6,4,"share"))
local owner_save={fleet={}}
for id,v in pairs(s.fleet) do
  local fields={}
  for k,val in pairs(v) do if k~="orders" then fields[k]=val end end
  fields.orders={}
  for i,o in ipairs(v.orders) do fields.orders[i]={station=o.station,action=o.action} end
  owner_save.fleet[id]=fields
end
O.restore(owner_save)
local reopened=owner_save.fleet
assert(reopened[4].orders==reopened[6].orders)
assert(reopened[4].index==truck.index and reopened[6].index==other.index)
assert(owner_save.next_road_order_group>truck.order_group)
O.release(owner_save,reopened[4]);reopened[4]=nil
assert(reopened[6].order_group==nil and reopened[6].orders[2].station==5)
local cursor={orders={{},{},{}},index=3}
table.remove(cursor.orders,1);O.cursor_after_remove(cursor,1);assert(cursor.index==2)
O.cursor_after_move(cursor,2,1);assert(cursor.index==1)
table.remove(cursor.orders,1);O.cursor_after_remove(cursor,1);assert(cursor.index==1)
print("PASS: stock road copy, shared-list identity, isolated cursors, stop usability, declone and detached-save recovery")
