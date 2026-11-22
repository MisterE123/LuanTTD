-- Shared seed-1751 native rail/road Oil route fixture. Uses actual
-- paid public construction and an optionally dispatched real Goods truck.
return function(api,owner,with_truck)
  local Sim,S=api.Sim,api.s
  local at,Build=Sim.id,assert(api.rail_build)
  local Track=dofile(core.get_modpath("bayline").."/openttd/rail_track.lua")
  local function build(ticket,reason)
    assert(ticket,reason)
    local ok,note=Build.build(owner,ticket)
    assert(ok,note)
  end
  local function line(a,b,c,d) return assert(Sim.line(at(a,b),at(c,d))) end
  local function track(a,b,c,d,k) build(Build.quote_track(owner,at(a,b),at(c,d),k,false)) end
  -- Flat western arc avoids town houses and all protected industry cells.
  assert(Sim.build(S,owner,"clear",line(4,5,4,15)))
  track(5,5,13,5,Track.X)
  track(4,5,4,5,Track.LOWER)
  track(4,6,4,16,Track.Y)
  track(4,17,4,17,Track.LEFT)
  track(5,17,14,17,Track.X)
  build(Build.quote_depot(owner,at(14,5),Track.NE))
  build(Build.quote_platform(owner,at(10,5),at(12,5),Track.NE))
  build(Build.quote_platform(owner,at(11,17),at(13,17),Track.SW))
  build(Build.quote_signal(owner,at(9,5),Track.NE,false))
  build(Build.quote_signal(owner,at(13,5),Track.SW,false))
  build(Build.quote_signal(owner,at(14,17),Track.SW,false))
  local wells=S.tiles[at(10,5)].rail_station_id
  local sink=S.tiles[at(11,17)].rail_station_id
  if not with_truck then return wells,sink end
  -- The factory outlet and its route are still driven by a real truck.
  local paths={
    {12,8,15,8},{12,8,12,14},{12,14,14,14},{14,14,14,16},{14,16,18,16},
    {15,8,15,12},{15,12,12,12},{18,16,18,15},{18,15,14,15},
  }
  for _,p in ipairs(paths) do assert(Sim.build(S,owner,"road",line(unpack(p)))) end
  local start,finish,depot=at(16,16),at(14,8),at(11,12)
  assert(Sim.build_truck_stop(S,owner,start))
  assert(Sim.build_truck_stop(S,owner,finish))
  assert(Sim.build(S,owner,"road_depot",{depot}))
  local goods=assert(Sim.purchase(S,owner,"goods_truck","goods",nil,depot))
  assert(Sim.add_order(S,owner,goods,S.tiles[start].station))
  assert(Sim.add_order(S,owner,goods,S.tiles[finish].station))
  assert(Sim.toggle(S,owner,goods))

  return wells,sink,goods
end
