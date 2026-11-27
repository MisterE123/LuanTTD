-- SPDX-License-Identifier: GPL-2.0-only
-- Shared coastal chain for authority and native graphical test worlds.
local Q={}
function Q.place(Sim,Terrain,s)
  s.ship_paid_service,s.ship_coal_service,s.road_heavy,s.road_farm=true,true,true,true
  s.road_junction_clearance=true
  local Farm,rng,Rules=Sim.mount_farm_world(s,Terrain,true)
  local H=Sim.mount_heavy_world(s,Terrain)
  assert(Sim.mount_oil_world(s,Terrain,true))
  local function original(kind,x,z)
    return {record=Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950}),name=kind}
  end
  local ore=assert(H.place_generated(s,"iron_mine",Sim.id(10,12),original("iron_mine",10,12)))
  local mill=assert(H.place_generated(s,"steel_mill",Sim.id(26,12),original("steel_mill",26,12)))
  local factory=assert(Farm.place_generated(s,"factory",Sim.id(45,12),original("factory",45,12),rng))

  assert(Sim.road_heavy_active(s))
  return {ore=ore.id,mill=mill.id,factory=factory.id}
end
function Q.supply(Sim,s)
  local haul="Heavy Roads"
  local points={{8,16,31,16},{8,16,8,17},{8,17,14,17},{14,17,14,16},
    {23,16,23,17},{23,17,31,17},{31,17,31,16}}
  for _,r in ipairs(points) do assert(Sim.build(s,haul,"road",Sim.line(Sim.id(r[1],r[2]),Sim.id(r[3],r[4])))) end
  local function stop(x)
    local id=Sim.id(x,16);assert(Sim.build_truck_stop(s,haul,id));return s.tiles[id].station
  end
  local pickup,drop=stop(11),stop(27)
  local depot=Sim.id(18,17)
  assert(Sim.build(s,haul,"road_depot",{depot}))
  local supply=assert(Sim.purchase(s,haul,"iron_mps","iron_ore",nil,depot))
  assert(Sim.add_order(s,haul,supply,pickup))
  assert(Sim.add_order(s,haul,supply,drop))
  assert(Sim.toggle(s,haul,supply))
  return supply
end
return Q
