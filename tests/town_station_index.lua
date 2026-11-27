local G=dofile("mods/luanttd_core/openttd/town_growth.lua")
local function stream(seed)
  return function(n) seed=seed*16807%2147483647;return (seed%n)+1 end
end
local r=stream(1951)
local linear,indexed={},{}
for i=1,4000 do
  local x,z=r(1024),r(1024)
  local station={id=i,x=x,z=z,time_since_load=r(255),time_since_unload=r(255),
    indexed=i%55~=0,waypoint=i%83==0}
  if i%157==0 then station.x=nil end
  linear[i]=station
  indexed[i]=station
end
assert(not G.index_active_stations({}))
indexed.count_near=assert(G.index_active_stations(indexed))
local towns={}
local ra,rb=stream(82),stream(82)
for i=1,832 do
  local x,z,houses=r(1024),r(1024),r(800)
  local a,b=G.new(i,x,z,{num_houses=houses}),G.new(i,x,z,{num_houses=houses})
  assert(G.active_stations(a,linear)==G.active_stations(b,indexed))
  local ga,wa=G.month(a,linear,2,function() return ra(2147483646) end)
  local gb,wb=G.month(b,indexed,2,function() return rb(2147483646) end)
  assert(ga==gb and wa==wb and a.growth_rate==b.growth_rate and a.grow_counter==b.grow_counter)
  towns[i]=a
end
assert(ra(31)==rb(31),"Monthly RNG diverged")
local edge,edge_indexed={},{}
for i=1,160 do
  local st={x=i,z=1,time_since_load=i%5==0 and 20 or 21}
  edge[i],edge_indexed[i]=st,st
end
edge_indexed.count_near=assert(G.index_active_stations(edge_indexed))
for x=1,160 do
  for radius=0,199 do
    local t={x=x,z=1,radii={radius}}
    assert(G.active_stations(t,edge)==G.active_stations(t,edge_indexed))
  end
end
print("PASS exact town station index on 832 monthly decisions and 32,000 radius boundaries")
if arg and arg[1]=="--benchmark" then
  for _,snapshot in ipairs({linear,indexed,indexed,linear}) do
    local start=os.clock()
    if snapshot==indexed then snapshot.count_near=assert(G.index_active_stations(snapshot)) end
    local sum=0
    for _,town in ipairs(towns) do
      -- prepare_day updates the growth decision, then counts again for UI.
      sum=sum+G.active_stations(town,snapshot)+G.active_stations(town,snapshot)
    end
    print(("%s %.2f ms (%d)"):format(snapshot==indexed and "indexed" or "linear",(os.clock()-start)*1000,sum))
  end
end
