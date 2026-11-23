-- Rebind an already initialized campaign after reading its durable checkpoint.
-- Runs in the worker VM before processing any commands. Availability comes
-- from a small immutable capability manifest, never an ObjectRef or renderer.
return function(Sim,mod,s,cap)
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local Slope=dofile(mod.."/openttd/slope.lua")
  local B=dofile(mod.."/campaign_simulation_bindings.lua")(Sim,mod)
  local grid=assert(s.corner_grid,"Cannot mount a campaign without a corner grid.")
  Sim.W,Sim.H=grid.width,grid.depth
  assert(#s.tiles==Sim.W*Sim.H,"The authority checkpoint has the wrong tile count.")
  local function tile(id)
    local x,z=Sim.xy(id)
    return Terrain.tile(grid,x,z)
  end
  Sim.restore_road_orders(s)
  B.road(s,cap.road)
  B.flood(s)
  B.towns(s)
  local farm,oil
  if s.stock_generated_profile or s.road_farm then
    farm=assert(Sim.mount_farm_world(s,Terrain,true))
  end
  if s.stock_generated_profile or s.road_oil then
    oil=assert(Sim.mount_oil_world(s,Terrain,cap.oil_tanker))
  end
  local network=B.networks(s,Slope,tile)
  local N={world=s,network=network,farm=farm,oil=oil,terrain=Terrain}
  local source=mod.."/openttd/"
  if s.ship_paid_service then
    local _,_,net,roster,run,depot,freight,coal=B.water(s,network.track,function(id) return cap.ferry[id]==true end)
    N.water={network=net,roster=roster,run=run,depot=depot,freight=freight,coal=coal}
  end
  if s.air_paid_service then
    local net,run,owned,roster=B.air(s,Slope,function(id) return cap.air[id]==true end)
    N.air={network=net,run=run,owned=owned,roster=roster}
  end
  if s.rail_paid_service then
    network.owned=s.rail_owned_service
    network.motion=dofile(source.."rail_motion.lua")(network.track)
    network.speed=dofile(source.."rail_station_speed.lua")(network.track,network.follow)
    local rail,signals,roster=B.rail(s,network)
    network.dispatch=rail
    N.rail={run=rail,signals=signals,roster=roster}
    if roster then
      local owned=B.owned_rail(s,network.lab,roster,rail,function() return Sim.rail_oil_active(s) end)
      if s.stock_electrification then owned.mount_electric(dofile(source.."rail_types.lua")) end
      N.rail.owned=owned
    end
    B.rail_media(rail,cap.rail)
    Sim.mount_paid_rail(s,rail)
    if s.rail_goods_service then
      Sim.mount_rail_goods(s,function() return cap.rail.ready.goods_van==true end)
    end
    if not cap.rail.ready.oil_tanker then s.rail_oil_service=false end
    network.crossings.refresh(s,network.lab.board(s))
  end
  function N.day() Sim.daily(s) end
  return N
end
