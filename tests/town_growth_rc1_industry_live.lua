-- Real 16.0-RC1 Normal industry/rivers, four towns and default subsidies.
-- Source CallLandscapeTick trace after every tick to 7104 plus save snapshots
-- compared by tests/town_growth_rc1_industry_start.lua. No company or routes.
local expected={
  {{1281,7541,1469947224,2242462710,815929123,1755659935,606552607,1895352048},{5931,477080829,0,0,11269,10,17,24,10,12},{11571,3683487949,1,0,5669,10,64,88,25,44},{1890,4280403754,0,1,11269,10,14,30,8,15},{13708,1201640385,0,2,11269,10,44,84,20,42}},
  {{1354,331,1971220149,1006027529,815929123,979708375,305615703,1895352048},{5931,477080829,0,0,11269,10,19,24,10,12},{11571,3683487949,1,0,5669,10,69,88,27,44},{1890,4280403754,0,1,11269,10,14,30,8,15},{13708,1201640385,0,2,11269,10,48,84,20,42}},
  {{3574,6145,1992897415,1645079432,815929123,1240953723,1567645,1895352048},{5931,477080829,0,0,11269,10,0,49,0,21},{11571,3683487949,1,0,5669,10,0,171,0,77},{1890,4280403754,0,1,11269,10,0,54,0,21},{13708,1201640385,0,2,11269,10,0,146,0,56}},
  {{5646,873,3356907187,3634553275,815929123,997650306,576288490,1895352048},{5931,477080829,0,0,11269,10,0,40,0,13},{11571,3683487949,1,0,5669,10,0,99,0,41},{1890,4280403754,0,1,11269,10,0,33,0,14},{13708,1201640385,0,2,11269,10,0,117,0,51}},
}
local check={}
for _,sample in ipairs(expected) do check[sample[1][1]]=sample end
local F=dofile("tests/town_growth_rc1_industry_start.lua")
local Sim,T,s,mod=F.Sim,F.Terrain,F.world,F.mod
local Rebuild=dofile(mod.."/openttd/town_rebuild.lua")
local mount,Codec=dofile(mod.."/campaign_authority_runtime.lua"),dofile(mod.."/packed_campaign.lua")
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
-- The same industry chain admissions as init.lua, all five proven present
-- in this actual generated map. There are no owned services to mount.
s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
local owner=mount(Sim,mod,s,cap)
local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local function eq(a,b,tick,k)
  assert(a==b,("RC1 live tick %d %s, got %s expected %s"):format(tick,k,tostring(a),tostring(b)))
end
local function same(tick,k,a,b)
  assert(#a==#b)
  for i,v in ipairs(b) do eq(a[i],v,tick,k.." "..i) end
end
local digest,seen,snapshots=1,0,0
local function observe(tick)
  if tick<=7104 then
    digest=fold(digest,tick,unpack(s.passenger_rating_rng))
    seen=seen+1
  end
  local ref=check[tick]
  if not ref then return end
  local hh,tt,house,road=1,1,1,1
  local year=Sim.date(s)
  for id,t in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    local typ=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4
      or t.terrain=="water" and 6 or t.build=="road" and 2 or t.source_house and 3 or 0
    hh=fold(hh,T.corner(s.corner_grid,x,z));tt=fold(tt,typ)
    local r=t.source_house
    if r then house=fold(house,id-1,r.id,r.town-1,r.completed and 1 or 0,r.stage,r.counter,Rebuild.age(r,year),r.random_bits) end
    if typ==2 then road=fold(road,id-1,t.road_bits,t.road_town-1) end
  end
  same(tick,"map/timer",{tick,s.passenger_house_clock.head,s.passenger_rating_rng[1],s.passenger_rating_rng[2],
    hh,tt,house,road},ref[1])
  for i,t in ipairs(s.stock_town_growth.towns) do
    local site=s.sites[i]
    local p,q=t.supplied.passenger,t.supplied.mail
    same(tick,"town "..i,{site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
      t.time_until_rebuild,p.new_max,p.old_max,q.new_max,q.old_max},ref[i+1])
  end
  snapshots=snapshots+1
end
for day=1,79 do
  if day==32 or day==60 then
    s=assert(Codec.decode(Codec.encode(s)))
    owner=mount(Sim,mod,s,cap)
  end
  owner.day(observe)
end
assert(seen==5824 and snapshots==4)
eq(digest,1865938467,7104,"5824-tick digest")
print("PASS Normal-industry live region: 5824 matching RC1 ticks, settled map and town cargo/clocks, two packed reopens")
