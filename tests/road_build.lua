local M=dofile('mods/bayline/sim.lua')
local T=dofile('mods/bayline/openttd/terrain.lua')
local function fresh(field)
  local s=M.new(1751)
  s.corner_grid=T.new(M.W,M.H,field)
  -- Strip scenery and water from the test region, not from shared game state.
  for z=3,18 do for x=3,21 do
    local t=s.tiles[M.id(x,z)]
    t.terrain="grass";t.h=0;t.house=nil;t.site=nil;t.wood=nil
  end end
  return s,M.company(s,"A")
end
local function id(x,z) return M.id(x,z) end
local function command(s,tool,ids)
  local ok,msg,changes=M.build(s,"A",tool,ids)
  assert(ok,msg)
  return changes
end
local function path(s,a,b)
  return M.path(s,{tile=a,mode="road",owner="A"},{tile=b,mode="road",owner="A"},"road","A")
end
local s,c=fresh(function(x) return x>12 and 1 or 0 end)
local a,b,hill=id(9,12),id(18,12),id(12,12)
local drag=M.line(a,b)
local preview,cost=M.plan(s,"A","road",drag)
assert(preview and cost>0 and not s.tiles[a].build)
local old_cash=c.cash
c.cash=cost-1
local ok,err=M.build(s,"A","road",drag)
assert(not ok and err=="Not enough cash." and not s.tiles[a].build and c.cash==cost-1)
c.cash=old_cash
assert(#command(s,"road",drag)==#drag and c.cash==old_cash-cost)
local shape,base,foundation=M.road_surface(s,hill)
assert(shape==3 and base==0 and foundation=="none")
assert(s.tiles[hill].road_bits==10 and s.tiles[a].road_bits==2 and s.tiles[b].road_bits==8)
assert(M.road_edge(s,hill,4) and M.road_connected(s,hill,4))
assert(M.road_connected(s,hill,2) and not M.road_edge(s,hill,1))
assert(#assert(path(s,a,b))==#drag)
assert(not M.build(s,"A","road",M.line(id(12,11),id(12,13))))
assert(not M.build(s,"A","road_station",{hill}))
local flat=id(10,12)
command(s,"road",M.line(id(10,10),id(10,14)))
assert(s.tiles[flat].road_bits==15 and M.road_connected(s,flat,1) and M.road_connected(s,flat,3))
command(s,"road_station",{a,b})
local sa,sb=s.tiles[a].station,s.tiles[b].station
assert(sa and sb and #assert(path(s,a,b))==#drag)
local depot=id(11,11)
local depot_access=id(11,12)
assert(not M.road_edge(s,depot_access,1))
command(s,"road_depot",{depot})
assert(s.tiles[depot].depot_dir==3 and M.road_edge(s,depot_access,1) and M.road_connected(s,depot,3))
assert(#assert(path(s,depot,a))==4)
command(s,"road",{a,id(9,13)})
assert(s.tiles[a].station==sa and s.tiles[a].build=="road_station" and M.road_connected(s,a,3))
local bus=assert(M.purchase(s,"A","bus","passenger",nil,depot))
assert(M.add_order(s,"A",bus,sa))
assert(M.add_order(s,"A",bus,sb))
assert(M.toggle(s,"A",bus))
for _=1,30 do M.daily(s) end
assert(s.fleet[bus].revenue>0 and s.fleet[bus].delivered>0)

-- Parallel roads are physically adjacent but do not acquire phantom turns.
s=fresh()
command(s,"road",M.line(id(9,12),id(18,12)))
command(s,"road",M.line(id(9,13),id(18,13)))
assert(not M.road_connected(s,id(11,12),3))
assert(not path(s,id(11,12),id(11,13)))

-- A triangular natural slope requires an inclined foundation for the straight route.
s,c=fresh(function(x,z) return x==13 and z==12 and 1 or 0 end)
a,b,hill=id(10,11),id(15,11),id(12,11)
drag=M.line(a,b)
local changes,fare=M.plan(s,"A","road",drag)
assert(changes and fare==math.ceil(M.tools.road.price/2)*2+
  (#drag-2)*M.tools.road.price+2*M.road_foundation_price, fare)
command(s,"road",drag)
shape,base,foundation=M.road_surface(s,hill)
assert(shape==3 and base==0 and foundation=="x")
assert(#assert(path(s,a,b))==#drag)

-- A pair of reciprocal pieces alone is insufficient: a wrong retaining
-- foundation on an opposite edge creates a real, non-drivable step.
s=fresh(function(x,z) return x==13 and z==12 and 1 or 0 end)
local v,w=id(12,11),id(12,10)
s.tiles[v].build="road_bridge";s.tiles[v].h=2;s.tiles[v].owner="A";s.tiles[v].road_bits=1
s.tiles[w].build="road";s.tiles[w].owner="A";s.tiles[w].road_bits=4
-- A carried-over bridge stub is at level 2; its neighbor is at level 0.
-- Explicit bits alone cannot make a usable route to that deck.
assert(M.road_edge(s,v,1) and M.road_edge(s,w,3))
assert(not M.road_connected(s,v,1) and not path(s,v,w))
print("PASS: slope/foundation road construction and costs, reciprocal grades, junctions, stations and depot service")
