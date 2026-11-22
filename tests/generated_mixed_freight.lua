-- SPDX-License-Identifier: GPL-2.0-only
-- Actual optional stock mixed industries, not a resized Harbor layout:
-- native road quote/build, ordinary directed YAPF stops, stock producer
-- and receipt clocks, two repeating goods against one shared network.
local root="mods/bayline/"
local function m(path) return dofile(root..path..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local TG=m("openttd/terragenesis")(m("openttd/slope"))
local Clear=m("openttd/terragenesis_clear")
local Gen={generate=function(o) return Clear.generate(TG.generate(o),TG.next_random) end,
  describe=Clear.describe,next_random=TG.next_random}
local Cam,G=m("generated_campaign"),m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local Calendar=m("openttd/stock_engine_calendar")
local at=Sim.id
local s=Cam.landscape(Sim,Terrain,Gen,{width=64,depth=64,seed=1751,terrain_type=1,quantity_sea_lakes=0,
  tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751)})
local named=m("openttd/stock_town_name")
assert(Cam.towns(Sim,Terrain,s,Gen,m("openttd/town_worldgen")(G,Build),named,G,Build,
  {difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}).success)
local P,Rating=m("openttd/passengers"),m("openttd/station_rating")
local Cat=m("openttd/station_catchment")(P,Rating,function()return 0 end,function()return 0 end)
local Coal=m("openttd/coal_industry")(P,Rating,Cat,m("openttd/income"))
local Timber=Sim.timber_rules()
local CoalWorld=m("coal_industry_world")(Sim,Terrain,Coal)
local TimberWorld=m("timber_world")(Sim,Terrain,Timber)
local picked=Cam.industries(Sim,Terrain,s,Gen,m("openttd/industry_worldgen")(Coal,Timber),CoalWorld,4,nil,TimberWorld)
assert(picked.target==4 and picked.shortfall==0)
Cam.landmarks(Sim,Terrain,s,Gen,m("openttd/scenery_object_worldgen"),Calendar.date(Sim.date(s)))
Cam.forests(Sim,Terrain,s,Gen,m("openttd/tree_worldgen"),2)
local by_tile={}
for _,r in ipairs(s.stock_generated_profile.industries) do by_tile[r.tile]=r end
local mine,power,mill,forest=by_tile[at(47,41)],by_tile[at(30,28)],by_tile[at(23,42)],by_tile[at(48,44)]
assert(mine.kind=="coal_mine" and power.kind=="power_station")
assert(mill.kind=="sawmill" and forest.kind=="forest")
local growth=m("town_growth_runtime")(Sim,Terrain,G,Build,m("openttd/town_passengers"))
local function attach()
  Sim.mount_stock_town_growth(s,growth,true)
  Sim.mount_road_bus_market(s,Calendar,1950,true)
  Sim.mount_coastal_flood(s)
end
s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_coal,s.road_timber,s.road_junction_clearance=true,true,true
attach()
local owner="Mixed Freight"
local function road(x,z,u,v)
  local ok,why=Sim.build(s,owner,"road",Sim.line(at(x,z),at(u,v)))
  assert(ok,("Road %d,%d to %d,%d: %s"):format(x,z,u,v,tostring(why)))
end
-- One spine, one honest through stop for each endpoint, and room to
-- turn in the actual direction of travel. No terrain modifications.
road(25,44,47,44)
for _,r in ipairs{
  {25,44,25,45},{25,45,30,45},{30,45,30,44}, -- Wood: turn beyond sawmill
  {47,44,47,46},{47,46,46,46},{46,46,46,44}, -- Wood: turn beyond Forest
  {46,44,46,40},{46,40,45,40},{45,40,45,43},{45,43,46,43}, -- Coal: mine approach and loop
  {29,44,29,26},{29,26,28,26},{28,26,28,30},{28,30,29,30}, -- Coal: plant approach and loop
} do road(unpack(r)) end
local wood_pick,wood_drop=at(45,44),at(26,44)
local coal_pick,coal_drop=at(46,41),at(29,28)
local depot=at(32,43)
local function stop(id)
  local ok,why=Sim.build_truck_stop(s,owner,id);assert(ok,why)
  return s.stations[s.tiles[id].station]
end
local wood_a,wood_b,coal_a,coal_b=stop(wood_pick),stop(wood_drop),stop(coal_pick),stop(coal_drop)
assert(Sim.build(s,owner,"road_depot",{depot}))
local _,forest_accept=Sim.timber_stop_status(s,wood_a,"wood")
local _,mill_accept=Sim.timber_stop_status(s,wood_b,"wood")
assert(not forest_accept.accepts and mill_accept.eighths==8 and mill_accept.near[1].id==mill.industry)
local _,source_accept,_,ca=Sim.coal_stop_status(s,coal_a)
local _,destination_accept,_,cb=Sim.coal_stop_status(s,coal_b)
assert(not source_accept and #ca.sources==1 and ca.sources[1]==mine.industry)
assert(destination_accept and cb.eighths==16 and cb.near[1].ind.id==power.industry)
local function truck(engine,cargo,from,to)
  local id=assert(Sim.purchase(s,owner,engine,cargo,nil,depot))
  local v=s.fleet[id]
  for _,leg in ipairs{{from,to},{to,from}} do
    local r,td,cost,frames=Sim.path(s,leg[1],leg[2],"road",owner,nil,v)
    assert(r and td and cost>0 and #frames>260)
    assert(r[1]==leg[1].tile and r[#r]==leg[2].tile)
    assert(frames[1][4]==leg[1].tile and frames[#frames][4]==leg[2].tile)
  end
  assert(Sim.add_order(s,owner,id,from.id,"normal"))
  assert(Sim.add_order(s,owner,id,to.id,"normal"))
  assert(Sim.toggle(s,owner,id))
  return id
end
local wood=truck("wood_truck","wood",wood_a,wood_b)
local coal=truck("coal_tipper","coal",coal_a,coal_b)
local function copy(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local out={};seen[t]=out
  for k,v in pairs(t) do out[k]=copy(v,seen) end
  return out
end
local paid_wood,paid_coal,day_wood,day_coal,restored=0,0,nil,nil,false
for day=1,141 do
  Sim.daily(s)
  local a,b=s.fleet[wood],s.fleet[coal]
  assert(s.passenger_house_clock.counter==s.stock_load_tick)
  for _,e in ipairs(Sim.road_loading_events(s)) do
    if e.kind=="fare" and e.vehicle==wood then
      assert(e.data.tile==wood_drop and e.data.units==20 and e.data.amount==228)
      paid_wood=paid_wood+e.data.units
    elseif e.kind=="fare" and e.vehicle==coal then
      assert(e.data.tile==coal_drop and e.data.units==20 and e.data.amount==424)
      paid_coal=paid_coal+e.data.units
    end
  end
  if not day_wood and a.delivered>0 then
    assert(day==60 and a.delivered==20 and a.revenue==228)
    day_wood=day
  end
  if not day_coal and b.delivered>0 then
    assert(day==90 and b.delivered==20 and b.revenue==424)
    day_coal=day
  end
  if day==76 then
    assert(a.delivered==20 and b.delivered==0)
    s=copy(s);attach();restored=true
  end
end
local a,b=s.fleet[wood],s.fleet[coal]
assert(restored and day_wood and day_coal and a.delivered==60 and b.delivered==40,a.status.." / "..b.status)
assert(paid_wood==a.delivered and paid_coal==b.delivered)
assert(s.stock_timber_industries[mill.industry].wood_received==60)
assert(s.sites[power.site].received.coal==40)
assert(s.companies[owner].paid_units==100 and s.companies[owner].revenue==1532 and a.expense>0 and b.expense>0)
print("PASS stock generated mixed seed 1751: Wood 60t/$684 and Coal 40t/$848, ordinary YAPF trips across save")
