local p="mods/luanttd_core/"
local Sim=dofile(p.."sim.lua")
local Terrain=dofile(p.."openttd/terrain.lua")
local G=dofile(p.."openttd/town_growth.lua")
local B=dofile(p.."openttd/town_growth_build.lua")(G,dofile(p.."openttd/town_growth_houses.lua"))
local H=dofile(p.."openttd/town_passengers.lua")
local W=dofile(p.."town_growth_runtime.lua")(Sim,Terrain,G,B,H)
local F=dofile("tests/town_growth_live_fixture.lua")
local function world()
  local s=Sim.new(1751)
  dofile(p.."town_layout.lua")(Sim,s)
  s.corner_grid=dofile(p.."terrain_preview.lua")(Sim,Terrain,s)
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  Sim.mount_stock_town_growth(s,W)
  return s
end
local s=world()
for _,town_id in ipairs(s.stock_town_growth.order) do
  local town=s.stock_town_growth.towns[town_id]
  local roots,population=0,0
  for _,tile in ipairs(s.tiles) do
    local h=tile.house and tile.source_house
    if h and h.town==town_id and h.root~=false then roots=roots+1;population=population+H.specs[h.id][1] end
  end
  assert(town.num_houses==roots and town.population==population and s.sites[town_id].population==population)
end
local x,z=5,15
local tile=s.tiles[Sim.id(x,z)]
tile.wood=nil
assert(W.eligible_site(s,x,z)~=nil)
for _,k in ipairs{"owner","site","wood","source_house","build","station","parcel","rail_tracks","stock_industry","ship","airfield","tram","signal"} do
  tile[k]=true
  assert(W.eligible_site(s,x,z)==nil,k)
  tile[k]=nil
end
local id=Sim.id(x,z)
for _,k in ipairs{"level_crossing_tiles","bridge_above","tunnel_below","rail_bridge_above","rail_tunnel_below","aqueduct_above"} do
  local old=s[k]
  s[k]={[id]=1}
  assert(W.eligible_site(s,x,z)==nil,k)
  s[k]=old
end
local proposed=assert(Terrain.plan(s.corner_grid,x,z,1,true,{freeform_edges=false}))
assert(Terrain.apply(s.corner_grid,proposed))
assert(W.eligible_site(s,x,z)==nil)
local qa=F.first(Sim,s)
print("Growth tile ",qa.tile,"built at",qa.built_tick,"saved at",qa.tick)
local function copy(x)
  if type(x)~="table" then return x end
  local t={}
  for k,v in pairs(x) do t[k]=copy(v) end
  return t
end
s=copy(s)
-- Explicit disable stops new starts but lets the project in flight finish.
Sim.mount_stock_town_growth(s,W,false)
local last=s.stock_town_growth.towns[qa.town].last_build.tick
local h=F.second(Sim,s,qa,H.specs)
assert(s.stock_town_growth.towns[qa.town].last_build.tick==last)
local before=s.sites[qa.town].population
assert(Sim.build(s,"GrowthQA","clear",{qa.tile}))
assert(s.sites[qa.town].population==before-H.specs[h.id][1])
assert(not s.tiles[qa.tile].house)
print(("PASS house built %d, completed %d, first stock production %d after reload"):format(h.built_tick,h.completed_tick,h.first_cargo_tick))
