local m="mods/luanttd_core"
local Sim=dofile(m.."/sim.lua")
local T=dofile(m.."/openttd/terrain.lua")
local F=dofile(m.."/openttd/yapf_road_follow.lua")
local Pack=dofile(m.."/packed_campaign.lua")
local Runtime=dofile(m.."/campaign_authority_runtime.lua")
local Endpoint=dofile(m.."/campaign_authority_endpoint.lua")
local cap={road={start_year=1950,breakdowns=0,service_interval=150},seconds_per_day=1.25}
local owner="Shared lane QA"
local s=Sim.new(1751)
local function at(x,z) return Sim.id(x,z) end
dofile(m.."/town_layout.lua")(Sim,s)
s.corner_grid=T.new(Sim.W,Sim.H)
local function clear(x,z)
  local tile=s.tiles[at(x,z)]
  tile.h,tile.terrain,tile.build,tile.owner,tile.house,tile.wood,tile.site=0,"grass",nil,nil,nil,nil,nil
end
for x=11,17 do clear(x,12) end
for z=9,15 do clear(15,z) end
clear(12,11)
clear(12,13)
s.tram_enabled,s.road_stock_clock,s.road_stock_loading,s.road_economy,s.road_stock_house_supply=
  true,true,true,true,true
local runtime=Runtime(Sim,m,s,cap)
local A=Endpoint(Sim,runtime)
assert(Sim.shared_road_tram_active(s))
local tram,a,b=at(12,11),at(15,10),at(15,14)
local west,east,depot=at(11,12),at(17,12),at(12,13)
assert(Sim.build(s,owner,"road",Sim.line(west,east)))
assert(Sim.build(s,owner,"road_station",{west,east}))
assert(Sim.build(s,owner,"road_depot",{depot}))
local N=runtime.tram.net
assert(N.construct(s,owner,"depot",{tram},F.SE))
assert(N.construct(s,owner,"road",Sim.line(at(12,12),at(15,12))))
assert(N.construct(s,owner,"road",Sim.line(at(15,9),at(15,15))))
assert(N.construct(s,owner,"road",{at(12,12)},1))
assert(N.construct(s,owner,"drive_stop",{a},F.SE))
assert(N.construct(s,owner,"drive_stop",{b},F.SE))
local p=assert(runtime.tram.run.start(s,owner,tram,a,b))
local bus=assert(Sim.purchase(s,owner,"bus","passenger",nil,depot))
for _,stop in ipairs({west,east}) do
  assert(Sim.add_order(s,owner,bus,s.tiles[stop].station))
end
assert(Sim.toggle(s,owner,bus))
assert(A.advance(1).ok and p.ticks==74,"separate tram clock must not double tick")
local near=assert(A.snapshots({{x=5,z=6,w=16,h=11}},1).value[1])
assert(#near.actors>0)
assert(not runtime.tram.pose_at(0),"depot must stay hidden until stock release")
local anchor,pose=runtime.tram.pose_at(1)
assert(anchor and pose and anchor==runtime.tram.run.frame(p))
local _,mid=runtime.tram.pose_at(.75)
assert(mid and math.abs(mid.x-pose.x)+math.abs(mid.z-pose.z)>.001,
  "worker must no longer replay an identical whole-day tram pose")
assert(p.ticks==74,"read-only pose interpolation never advances the tram")
local function completed()
  return p.arrivals>=4 and s.fleet[bus].delivered>0
end
for _=1,90 do
  if completed() then break end
  local before=p.ticks
  assert(A.advance(1).ok and p.ticks-before==74)
end
assert(completed(),("arrivals %s, bus %s, waits %s %s"):format(p.arrivals,s.fleet[bus].delivered,tostring(p.traffic_wait),tostring(p.crossing_wait)))
local v=s.fleet[bus]
local saved_ticks,arrivals,paid=p.ticks,p.arrivals,v.delivered
s=assert(Pack.decode(Pack.encode(s)))
runtime=Runtime(Sim,m,s,cap)
A=Endpoint(Sim,runtime)
p=assert(runtime.tram.run.current(s))
assert(p.ticks==saved_ticks)
for _=1,65 do
  if p.arrivals>=arrivals+2 and s.fleet[bus].delivered>paid then break end
  assert(A.advance(1).ok)
end
assert(p.arrivals>=arrivals+2 and s.fleet[bus].delivered>paid)
print("PASS production owner advances live tram and paying bus on a shared street exactly once per tick, including after packed restore")
