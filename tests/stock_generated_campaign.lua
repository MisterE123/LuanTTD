-- Clean-room host integration, using real source-port modules, not Harbor seeds.
local root="mods/luanttd_core/"
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
local a,q=make()
-- Booting the authoritative house tile clock must not replace stock
-- worldgen IDs or completion flags with the Harbor scenery archetypes.
local world=load("town_growth_runtime")(Sim,Terrain,G,Build,load("openttd/town_passengers"))
local before={}
for i,t in ipairs(a.tiles) do if t.source_house then before[i]=t.source_house end end
a.road_stock_loading,a.road_stock_clock,a.road_stock_house_supply,a.road_economy=true,true,true,true
local live=Sim.mount_stock_town_growth(a,world,true)
assert(live==a.stock_town_growth and a.passenger_house_clock)
for i,h in pairs(before) do assert(a.tiles[i].source_house==h) end
local b=make()
assert(Sim.W==64 and Sim.H==64 and #a.tiles==4096 and #a.corner_grid.levels==65^2)
assert(#a.sites>=2 and q.target==2)
assert(#a.sites==#b.sites)
local specs=load("openttd/town_passengers").specs
local tmap={}
local numstreet,numhouses,water,coast,void=0,0,0,0,0
for id,t in ipairs(a.tiles) do
  local u=b.tiles[id]
  assert(t.terrain==u.terrain and t.build==u.build and t.h==u.h and t.road_bits==u.road_bits and t.stock_clear_ground==u.stock_clear_ground)
  if t.stock_void then
    assert(not Sim.mode_on(a,id,"water","Tester"));void=void+1
  elseif t.coastal_water then coast=coast+1
  elseif t.terrain=="water" then water=water+1
  elseif t.source_house then
    assert(t.source_house.id==u.source_house.id)
    assert(t.house and a.sites[t.source_house.town])
    local h=t.source_house
    if h.completed then tmap[h.town]=(tmap[h.town] or 0)+specs[h.id][1] end
    numhouses=numhouses+1
  elseif t.road_town then
    assert(t.build=="road" and t.road_bits>0 and t.owner==nil and a.sites[t.road_town])
    numstreet=numstreet+1
  end
end
for i,v in ipairs(a.sites) do
  assert(v.name==Names.display(v.nameparts) and v.name==b.sites[i].name and v.tile==b.sites[i].tile)
  assert(v.name~="Port Alder" and v.name~="Mason Quay")
  assert(v.population==tmap[i] and v.population>0)
  assert(a.stock_town_growth.towns[i].population==v.population)
end
for i,l in ipairs(a.corner_grid.levels) do assert(l==b.corner_grid.levels[i]) end
assert(numstreet>3 and numhouses>8 and water>0 and coast>0 and void==252)
print(("PASS generated campaign: %d named stocked towns, %d real municipal road tiles, %d actual houses, %d water/%d coast/%d void"):format(#a.sites,numstreet,numhouses,water,coast,void))
