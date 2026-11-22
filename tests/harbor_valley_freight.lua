-- First coal service on the actual Harbor Valley starter geography.
local mod="mods/bayline/"
local function load(path) return dofile(mod..path..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local s=Sim.new(1751)
load("town_layout")(Sim,s)
s.corner_grid=load("harbor_valley_seed")(Sim,Terrain,s,load("terrain_preview")(Sim,Terrain,s))
local P,R=load("openttd/passengers"),load("openttd/station_rating")
local Catchment=load("openttd/station_catchment")(P,R)
local Coal=load("openttd/coal_industry")(P,R,Catchment,load("openttd/income"))
local at=Sim.id
local seeded=assert(load("coal_industry_world")(Sim,Terrain,Coal).seed(s,at(30,11),at(40,12)))
local Timber=load("timber_world")(Sim,Terrain,Sim.timber_rules())
assert(Timber.default_1751(s))
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_coal,s.road_timber,s.road_junction_clearance=true,true,true
Sim.mount_road_bus_market(s,load("openttd/stock_engine_calendar"),1950,true)
Sim.mount_coastal_flood(s)
local owner="Harbor coal haulier"
local function road(x,z,u,v)
  assert(Sim.build(s,owner,"road",Sim.line(at(x,z),at(u,v))))
end
road(29,14,43,14)
for _,r in ipairs({{29,14,29,15},{29,15,32,15},{32,15,32,14},{39,14,39,15},{39,15,43,15},{43,15,43,14}}) do
  road(unpack(r))
end
local a,b,d=at(31,14),at(41,14),at(34,15)
assert(Sim.build_truck_stop(s,owner,a))
assert(Sim.build_truck_stop(s,owner,b))
assert(Sim.build(s,owner,"road_depot",{d}))
local mine,plant=s.stations[s.tiles[a].station],s.stations[s.tiles[b].station]
local _,mine_accepts,_,mine_catchment=Sim.coal_stop_status(s,mine)
local _,plant_accepts,_,plant_catchment=Sim.coal_stop_status(s,plant)
assert(not mine_accepts and mine_catchment.sources[1]==seeded.mine and not mine_catchment.sources[2])
assert(plant_accepts and plant_catchment.eighths>=8 and #plant_catchment.sources==0)
local id=assert(Sim.purchase(s,owner,"coal_tipper","coal",nil,d))
assert(Sim.add_order(s,owner,id,mine.id,"normal"))
assert(Sim.add_order(s,owner,id,plant.id,"normal"))
assert(Sim.toggle(s,owner,id))
local v=s.fleet[id]
for _=1,70 do
  Sim.daily(s)
  if v.revenue>0 then
    assert(v.delivered==20 and v.revenue==140)
    assert(s.sites[s.stock_coal_industries[seeded.power].site].received.coal==20)
    print(("PASS: normal orders and two turnaround loops in Harbor Valley hauled %d tons for $%d on day %d"):format(v.delivered,v.revenue,s.day))
    return
  end
end
error("Harbor Valley's ordinary coal service did not pay")
