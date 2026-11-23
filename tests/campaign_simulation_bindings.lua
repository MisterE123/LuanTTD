-- Construct real campaign runtime state without a Luanti engine global.
local p="mods/luanttd_core/"
local Sim=dofile(p.."sim.lua")
local Terrain=dofile(p.."openttd/terrain.lua")
local House=dofile(p.."openttd/town_passengers.lua")
local Codec=dofile(p.."packed_campaign.lua")
local Bind=dofile(p.."campaign_simulation_bindings.lua")(Sim,p:sub(1,-2))
local Route=dofile("tests/town_growth_live_fixture.lua")
assert(core==nil,"test must not borrow host state")
local function mount(s)
  Bind.road(s,{start_year=1950,foster=true,craighead=true,breakdowns=0,service_interval=150,
    service_percent=false})
  assert(not Bind.flood(s))
  assert(Bind.towns(s))
  local slope=dofile(p.."openttd/slope.lua")
  local function tile(id)
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local net=Bind.networks(s,slope,tile)
  net.motion=dofile(p.."openttd/rail_motion.lua")(net.track)
  net.speed=dofile(p.."openttd/rail_station_speed.lua")(net.track,net.follow)
  net.owned=true
  local pilot,_,roster=Bind.rail(s,net)
  net.dispatch=pilot
  assert(Bind.owned_rail(s,net.lab,roster,pilot,function() return false end))
  Bind.rail_media(pilot,{engines={8},split={}})
  assert(pilot.owned_passenger_engine(8) and not pilot.owned_passenger_engine(9))
  s.rail_paid_service=true
  Sim.mount_paid_rail(s,pilot)
  Bind.water(s,net.track,function(id) return id==206 end)
  Bind.air(s,slope,function(id) return id==215 end)
end
local s=Sim.new(1751)
dofile(p.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(p.."terrain_preview.lua")(Sim,Terrain,s)
mount(s)
local qa=Route.first(Sim,s)
local saved=Codec.decode(Codec.encode(s))
Sim.restore_road_orders(saved)
mount(saved)
local h=Route.second(Sim,saved,qa,House.specs)
assert(saved.fleet[qa.id].last_fare and saved.stock_town_growth.towns[qa.town])
print(("PASS view-free road, town, rail, ferry and air bindings: bus earns fare, house completed at tick %d, produces cargo after checkpoint"):format(h.completed_tick))
