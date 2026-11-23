local mod=(core and core.get_modpath("luanttd_core") or "mods/luanttd_core")
local Sim=dofile(mod.."/sim.lua")
local Terrain=dofile(mod.."/openttd/terrain.lua")
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x<19 and 1 or 0 end)
s.rail_paid_service,s.rail_owned_service,s.ship_paid_service,s.air_paid_service=true,true,true,true
s.air_owned_preview,s.air_fleet_preview=true,true
for i,t in ipairs(s.tiles) do
  local x=Sim.xy(i)
  t.site,t.owner,t.wood,t.house,t.build=nil,nil,nil,nil,nil
  t.terrain=x>=19 and "water" or "grass"
end
local runtime=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,{
  road={start_year=1950,breakdowns=0,service_interval=150},
  rail={ready={},engines={},split={}},air={[215]=true},ferry={[206]=true}
})
local A=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,runtime)
local revision=0
local function command(owner,c)
  c.revision=revision
  local r=A.command(owner,c)
  assert(r.ok,r.why)
  revision=r.revision
  return r.value
end
for _,n in ipairs({"Rail","Water","Air"}) do command(n,{kind="company_open"}) end
local function choose(n,req)
  local q=A.transport_quote(n,req)
  assert(q.ok,q.why)
  local before=A.company(n).value.cash
  local value=command(n,{kind="transport_commit",token=q.value.token})
  assert(A.company(n).value.cash==before-q.value.cost)
  return value.id
end
local dock1=choose("Water",{mode="ship",operation="build",kind="dock",tile=Sim.id(18,8)})
local dock2=choose("Water",{mode="ship",operation="build",kind="dock",tile=Sim.id(18,16)})
local ship_depot=choose("Water",{mode="ship",operation="build",kind="depot",tile=Sim.id(22,10),axis=0})
assert(choose("Water",{mode="ship",operation="buy",engine=206,depot=ship_depot})=="ferry")
command("Water",{kind="transport_start",mode="ship",depot=ship_depot,first=dock1,second=dock2})
local ap=choose("Air",{mode="air",operation="build",tile=Sim.id(2,14)})
local aq=choose("Air",{mode="air",operation="build",tile=Sim.id(13,19)})
assert(choose("Air",{mode="air",operation="buy",engine=215,depot=ap}))
command("Air",{kind="transport_start",mode="air",first=ap,second=aq})
local function track(req)
  local q=A.rail_quote("Rail",req)
  assert(q.ok,q.why)
  command("Rail",{kind="rail_commit",token=q.value.token})
end
local depot=Sim.id(2,5)
track({tool="track",first=Sim.id(3,5),last=Sim.id(14,5),track=0})
track({tool="depot",first=depot,direction=runtime.network.track.SW})
track({tool="station",first=Sim.id(4,5),last=Sim.id(6,5),axis=0,tracks=1,length=3})
track({tool="station",first=Sim.id(12,5),last=Sim.id(14,5),axis=0,tracks=1,length=3})
local prospects=assert(A.depot("Rail","rail",depot).value)
assert(#prospects.offers>=1 and #prospects.vehicles==0)
assert(not A.depot("Air","rail",depot).ok)
local engine=choose("Rail",{mode="rail",operation="buy",depot=depot,parts={0,27}})
command("Rail",{kind="transport_start",mode="rail",vehicle=engine,
  first=s.tiles[Sim.id(12,5)].rail_station_id,second=s.tiles[Sim.id(4,5)].rail_station_id})
assert(A.depot("Rail","rail",depot).value.vehicles[1].id==engine)
assert(A.orders("Rail","rail",engine).ok and A.orders("Water","ship","ferry").ok and A.orders("Air","air",1).ok)
assert(A.advance(4).tick==296 and runtime.rail.run.current(s).ticks>0)
assert(runtime.water.run.current(s).vehicle.tick>0 and runtime.air.run.current(s).vehicle.tick>0)
print("PASS worker builds, buys and dispatches rail, ferry and air using the normal commands")
return true
