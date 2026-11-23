-- Actual stock road depot, three road stops, selected vehicle command.
local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local s=Sim.new(1751)
dofile(root.."town_layout.lua")(Sim,s)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for _,t in ipairs(s.tiles) do t.h=0;t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil end
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_bay_build=true,true,true,true,true
local a,b,c,d=Sim.id(11,12),Sim.id(27,12),Sim.id(20,12),Sim.id(12,13)
local owner="Test"
local function build(tool,ids)
  local ok,why=Sim.build(s,owner,tool,ids);assert(ok,why)
end
build("road",Sim.line(a,b))
build("road_bay_pair",{a,b})
build("road_station",{c})
build("road_depot",{d})
local sa,sb,sc=s.tiles[a].station,s.tiles[b].station,s.tiles[c].station
local adapter=dofile(root.."road_vehicle_orders.lua")({s=s,Sim=Sim}).road
local id=assert(Sim.purchase(s,owner,"bus","passenger",nil,d))
local other=assert(Sim.purchase(s,owner,"bus","passenger",nil,d))
local host=s.fleet[id]
local function read()
  return assert(adapter.read(owner,id))
end
local function edit(op,i,t)
  local p=read()
  return adapter.edit(owner,id,p.revision,op,i,t)
end
assert(edit("append",1,sa));assert(edit("append",1,sb));assert(edit("append",1,sc))
assert(Sim.clone_road_orders(s,owner,other,id,"share"))
assert(Sim.toggle(s,owner,id))
assert(not adapter.read("rival",id))
for _=1,6 do
  Sim.daily(s)
  if host.route and Sim.position(s,host)~=d then break end
end
assert(host.route and host.dest==sa and host.running and host.home_depot==d and not host.depot)
local stale=read().revision
assert(edit("down",1))
assert(host.dest==sa and host.dest_index==2 and host.running and s.fleet[other].index==2)
assert(not adapter.edit(owner,id,stale,"remove",1))
assert(edit("skip",1))
assert(edit("remove",3))
assert(edit("append",1,sc))
local skipped=false
for _=1,40 do
  Sim.daily(s)
  if host.dest==sb then skipped=true end
  if host.station==sb then skipped=true;break end
end
assert(skipped,"bus follows changed destination while still in service")
assert(host.running and host.orders==s.fleet[other].orders)
assert(host.home_depot==d)
-- Park the first vehicle's peer still in its purchase depot; sharing
-- does not copy another bus's active skip or reroute state.
local peer=s.fleet[other]
assert(peer.depot==d and peer.road_order_override==nil and not peer.running)
local function clone(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local out={}
  seen[t]=out
  for k,v in pairs(t) do out[k]=clone(v,seen) end
  return out
end
-- Persist an edit made between simulation steps, then resume; its destination
-- cannot silently reset to the one from before the command.
local ix=read().active%#host.orders+1
local target=host.orders[ix].station
assert(edit("skip",ix))
s=clone(s);Sim.restore_road_orders(s)
host=s.fleet[id]
assert(host.road_order_override==ix and host.home_depot==d)
local visited=false
for _=1,45 do
  Sim.daily(s)
  if host.dest==target or host.station==target then visited=true;break end
end
assert(visited and host.running,"vehicle must honor persisted skip")
print("PASS shared road lists preserve independent cursors; moving bus accepts skip, reloads a pending skip and reaches edited destinations")
