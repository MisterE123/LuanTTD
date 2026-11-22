local P=dofile("mods/luanttd_core/openttd/road_proximity.lua")
local front={blocked_ctr=4,reverse_ctr=0}
local bus={id=1,first=1, type="road",x=12,y=12,z=0,direction=5}
local function other(id,x,y,z,d,kind,depot,first)
  return {id=id,first=first or id,type=kind or "road",x=x,y=y,z=z,direction=d or 5,in_depot=depot}
end
local a,b,c=other(8,18,12,0),other(4,18,12,0),other(5,19,12,0)
local ignored={bus,other(2,14,12,0,1),other(3,14,12,6),other(6,14,11,0),
               other(7,20,12,0),other(9,14,12,0,5,"rail"),other(10,14,12,0,5,nil,true),
               other(11,14,12,0,5,nil,false,1)}
assert(not P.find(bus,front,12,12,5,ignored))
assert(front.blocked_ctr==0)
assert(P.find(bus,front,12,12,5,{c,a,b})==b and front.blocked_ctr==1)
assert(P.find(bus,front,12,12,5,{a,c,b},false)==b and front.blocked_ctr==1)
front.blocked_ctr=1479
assert(P.find(bus,front,12,12,5,{b})==b and front.blocked_ctr==1480)
assert(not P.find(bus,front,12,12,5,{b}) and front.blocked_ctr==1481)
front.reverse_ctr=5
assert(not P.find(bus,front,12,12,5,{b}) and front.blocked_ctr==1481)
print("PASS: stock leading vehicle, directional range, ownership-chain exclusion, ties and blocked timeout")
