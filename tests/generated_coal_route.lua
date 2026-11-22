-- SPDX-License-Identifier: GPL-2.0-only
-- Real generated 64² campaign, native construction commands and stock
-- YAPF both ways. Ordinary orders, no injected road, cargo or industries.
-- Clean-room host integration, using real source-port modules, not Harbor seeds.
local root="mods/bayline/"
local function load(name) return dofile(root..name..".lua") end
local Sim,Terrain,Slope=load("sim"),load("openttd/terrain"),load("openttd/slope")
local TG=load("openttd/terragenesis")(Slope)
local Clear=load("openttd/terragenesis_clear")
local Gen={generate=function(o) return Clear.generate(TG.generate(o),TG.next_random) end,
  describe=Clear.describe,next_random=TG.next_random}
local Cam,Names=load("generated_campaign"),load("openttd/stock_town_name")
local G=load("openttd/town_growth")
local Build=load("openttd/town_growth_build")(G,load("openttd/town_growth_houses"))
local Worldgen=load("openttd/town_worldgen")(G,Build)
local landscape={width=64,depth=64,seed=1751,terrain_type=1,quantity_sea_lakes=0,tgen_smoothness=1,
  freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751)}
local settings={difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}
local function make()
  local s=Cam.landscape(Sim,Terrain,Gen,landscape)
  local result=assert(Cam.towns(Sim,Terrain,s,Gen,Worldgen,Names,G,Build,settings))
  assert(result.success,#s.sites)
  return s,result
end
local a=make()
local P,R=load("openttd/passengers"),load("openttd/station_rating")
local Cat=load("openttd/station_catchment")(P,R,function()return 0 end,function()return 0 end)
local Coal=load("openttd/coal_industry")(P,R,Cat,load("openttd/income"))
Cam.industries(Sim,Terrain,a,Gen,load("openttd/industry_worldgen")(Coal),load("coal_industry_world")(Sim,Terrain,Coal),4)
Cam.landmarks(Sim,Terrain,a,Gen,load("openttd/scenery_object_worldgen"),
  load("openttd/stock_engine_calendar").date(Sim.date(a)))
Cam.forests(Sim,Terrain,a,Gen,load("openttd/tree_worldgen"),2)
local at=Sim.id
a.road_stock_loading,a.road_stock_clock,a.road_stock_house_supply,a.road_economy=true,true,true,true
a.road_coal,a.road_junction_clearance=true,true
local world=load("town_growth_runtime")(Sim,Terrain,G,Build,load("openttd/town_passengers"))
Sim.mount_stock_town_growth(a,world,true)
Sim.mount_road_bus_market(a,load("openttd/stock_engine_calendar"),1950,true)
Sim.mount_coastal_flood(a)
assert(Sim.W==64 and Sim.H==64 and a.seed==1751 and a.stock_generated_profile.width==64)
local records={}
for _,rec in ipairs(a.stock_generated_profile.industries) do records[rec.tile]=rec end
local mine=assert(records[at(24,43)])
local plant=assert(records[at(30,28)])
assert(mine.kind=="coal_mine" and plant.kind=="power_station")
assert(select(2,Terrain.tile(a.corner_grid,24,43))==3 and select(2,Terrain.tile(a.corner_grid,30,28))==3)
local owner="Stock Coal Route"
local function road(x,z,u,v)
 local ok,no=Sim.build(a,owner,"road",Sim.line(at(x,z),at(u,v)))
 assert(ok,("ROAD %d,%d to %d,%d: %s"):format(x,z,u,v,tostring(no)))
end
road(29,26,29,45)
for _,p in ipairs{
 {29,26,28,26},{28,26,28,30},{28,30,29,30},
 {29,45,28,45},{28,45,28,41},{28,41,29,41},
} do road(unpack(p)) end
-- The truck always forwards past a through stop. Both turns are genuine
-- loops, not reverse-at-stop or joint geometry. The Z46 corner is sloped.
if arg[1]=="signed" then
  local Follow=load("openttd/yapf_road_follow")
  local Rule=load("openttd/road_oneway")(load("openttd/road_slope"),Follow)
  local Oneway=load("road_oneway_world")(Sim,Terrain,Follow,Rule)
  Sim.mount_road_oneway(a,Oneway)
  for _,z in ipairs{{27,29},{44,42}} do
    local quote=assert(Oneway.quote(a,owner,at(28,z[1]),at(28,z[2]),1))
    assert(Oneway.commit(a,owner,quote))
    assert(Oneway.marking(a,at(28,(z[1]+z[2])/2)))
  end
end
local src,sink,depot=at(29,43),at(29,28),at(30,35)
assert(Sim.build_truck_stop(a,owner,src));assert(Sim.build_truck_stop(a,owner,sink))
assert(Sim.build(a,owner,"road_depot",{depot}))
local first,second=a.stations[a.tiles[src].station],a.stations[a.tiles[sink].station]
local _,is_accept,_,from=Sim.coal_stop_status(a,first)
local _,accept,_,to=Sim.coal_stop_status(a,second)
assert(not is_accept and #from.sources==1 and from.sources[1]==mine.industry)
assert(accept and to.eighths>=8 and to.near[1].ind.id==plant.industry)
local v=assert(Sim.purchase(a,owner,"coal_tipper","coal",nil,depot))
local f=a.fleet[v]
local function leg(start,finish)
  local route,td,cost,frames=Sim.path(a,start,finish,"road",owner,nil,f)
  assert(route and #route==16 and td and cost>0 and #frames>180,tostring(frames and #frames))
  assert(route[1]==start.tile and route[#route]==finish.tile)
  assert(frames[1][4]==start.tile and frames[#frames][4]==finish.tile)
end
leg(first,second);leg(second,first)
assert(Sim.add_order(a,owner,v,first.id,"normal"))
assert(Sim.add_order(a,owner,v,second.id,"normal"))
assert(Sim.toggle(a,owner,v))
local paid,first_fare,turnaround=0,nil,false
for day=1,160 do
  Sim.daily(a)
  for _,e in ipairs(Sim.road_loading_events(a)) do
    if e.kind=="fare" and e.vehicle==v then
      assert(e.data.tile==sink and e.data.units==20 and e.data.amount>0)
      paid=paid+e.data.units
    end
  end
  if not first_fare and f.delivered>0 then
    assert(day==48 and f.delivered==20 and f.revenue==212 and f.expense==73)
    first_fare=day
  elseif first_fare and f.last_departure and f.last_departure>first_fare then
    turnaround=true
  end
  if f.delivered>=40 then break end
end
assert(first_fare and turnaround and f.delivered==40 and paid==40 and f.revenue>212,f.status)
assert(a.sites[plant.site].received.coal==f.delivered and a.companies[owner].revenue==f.revenue)
assert(a.stock_load_tick==a.passenger_house_clock.counter)
print(("PASS generated seed 1751: actually hauled %dt/$%d, first 20t/$212 on day %d, road stock directions %s")
  :format(f.delivered,f.revenue,first_fare,arg[1]=="signed" and "signed loops" or "ordinary"))
