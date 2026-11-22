-- SPDX-License-Identifier: GPL-2.0-only
-- Generated river/ferry geometry and ordinary movement, no mocked path.
local root="mods/luanttd_core/"
local function m(path) return dofile(root..path..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Slope=m("openttd/slope")
local TG=m("openttd/terragenesis")(Slope)
local Clear=m("openttd/terragenesis_clear")
local Rivers=m("openttd/river_worldgen")(Slope)
local Gen={generate=function(o)
  local land,river=Rivers.generate(TG.generate(o),TG.next_random,{original=false,terrain=Terrain,
    amount_of_rivers=o.amount_of_rivers,min_river_length=o.min_river_length})
  return Clear.generate(land,TG.next_random),river
end,describe=Clear.describe,next_random=TG.next_random}
local Cam,G=m("generated_campaign"),m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local Calendar=m("openttd/stock_engine_calendar")
local at=Sim.id
local s=Cam.landscape(Sim,Terrain,Gen,{width=64,depth=64,seed=1751,terrain_type=1,quantity_sea_lakes=0,
  tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751),
  amount_of_rivers=3,min_river_length=2})
assert(Cam.towns(Sim,Terrain,s,Gen,m("openttd/town_worldgen")(G,Build),m("openttd/stock_town_name"),G,Build,
  {difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}).success)
local P,Rating=m("openttd/passengers"),m("openttd/station_rating")
local Cat=m("openttd/station_catchment")(P,Rating,function()return 0 end,function()return 0 end)
local Coal=m("openttd/coal_industry")(P,Rating,Cat,m("openttd/income"))
local CoalWorld=m("coal_industry_world")(Sim,Terrain,Coal)
Cam.industries(Sim,Terrain,s,Gen,m("openttd/industry_worldgen")(Coal),CoalWorld,4)
Cam.landmarks(Sim,Terrain,s,Gen,m("openttd/scenery_object_worldgen"),Calendar.date(Sim.date(s)))
Cam.forests(Sim,Terrain,s,Gen,m("openttd/tree_worldgen"),2)
s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
local growth=m("town_growth_runtime")(Sim,Terrain,G,Build,m("openttd/town_passengers"))
Sim.mount_stock_town_growth(s,growth,true)
Sim.mount_coastal_flood(s)

local Track=m("openttd/rail_track")
local Water=m("openttd/ship_follow")(Track)
local Facilities=m("openttd/ship_facilities")(Track,Water)
local Network=m("ship_network")(Sim,Terrain,Water,Facilities)
local World=m("ship_water_world")(Sim,Network,m("openttd/water_construction")(Track,Water))
local Y=m("openttd/ship_yapf")(Track,Water,m("openttd/yapf_road_search"))
local Motion=m("openttd/ship_motion")(Track,Water)
local Run=m("ship_preview_run")(Network,Track,Water,Y,Motion,m("openttd/ship_regions"),
  {width=Sim.W,height=Sim.H,x0=1,z0=1})
local owner="Lock Company"

local terminal=arg and arg[1]=="terminal"
local middle=at(25,20)
local high_berth=terminal and at(26,20) or at(27,18)
local arrival_ticks=terminal and {1020,1511,2004} or {1191,2231,3047}
local build_cost=terminal and 24150 or 69150
local company=Sim.company(s,owner)
local initial=company.cash
local board=Network.board(s)
assert(s.stock_generated_profile.river_stats.rivers==2)
assert(board.tile(middle).kind=="river" and board.tile(middle).slope==3)
assert(Water.at(board,middle)==0)

-- The outer basin is already navigable. The approach from that basin to
-- the bottom lock gate needs one lawful corner edit and one canal tile.
-- The longer variant uses two actual dock loops. The narrow terminal
-- variant puts both piers on existing river flats, with no extra canals
-- except the paid one-tile bottom approach shared by both recipes.
local depot=assert(Network.build(s,owner,"depot",at(15,18),Track.X))
if not terminal then assert(World.build(s,owner,at(23,17),at(24,17))) end
local lower=assert(Network.build(s,owner,"dock",at(26,18)))
if not terminal then
  assert(World.build(s,owner,at(27,16),at(27,19)))
  assert(World.build(s,owner,at(28,16),at(28,18)))
end
local upper=assert(Network.build(s,owner,"dock",terminal and at(28,20) or at(29,18)))
assert(board.tile(at(23,20)).kind=="clear" and board.tile(at(23,20)).slope==4)
assert(Terrain.corner(s.corner_grid,23,21)==2)
local q,cost=Sim.landscape(s,owner,"lower",23,21,nil,nil,nil,true)
assert(q and cost==250)
assert(Sim.landscape(s,owner,"lower",23,21))
assert(board.tile(at(23,20)).slope==0 and Terrain.corner(s.corner_grid,23,21)==1)
assert(World.build(s,owner,at(23,20),at(23,20)))

local no,why=Run.quote(s,owner,depot.id,upper.id,lower.id)
assert(not no and why=="NO_CHANNEL_TO_FIRST_DOCK")
local cash=company.cash
local quote=assert(World.quote_lock(s,owner,middle))
assert(quote.lower==at(24,20) and quote.upper==at(26,20) and quote.cost==17500)
assert(company.cash==cash and board.tile(middle).kind=="river")
local lock=assert(World.build_lock(s,owner,middle))
assert(lock.cost==quote.cost and company.cash==cash-17500)
assert(board.tile(middle).water_class=="river" and Water.at(board,middle)~=0)
assert(initial-company.cash==build_cost and company.expense==build_cost)
if terminal then
  local berths=board.station_dock_tiles(upper.id)
  assert(#berths==1 and berths[1]==high_berth)
  assert(board.tile(high_berth).kind=="lock" and board.tile(high_berth).part=="upper")
  assert(board.adjacent(high_berth,Track.SW)==upper.water and Water.at(board,upper.water)==0)
end

-- These natural docks are a movement test, not a profitable passenger route.
-- No town grows here and the test does not inject houses or simulate fares.
local function no_house_catchment(dock)
  local box=dock.station_area
  for x=box.x-5,box.x+box.w-1+5 do
    for z=box.z-5,box.z+box.h-1+5 do
      local id=at(x,z)
      assert(not id or not s.tiles[id].house)
    end
  end
end
no_house_catchment(lower)
no_house_catchment(upper)

local p=assert(Run.start(s,owner,depot.id,upper.id,lower.id))
assert(not p.paid_clock and p.phase=="depot" and not Run.pose(p))
local presentation=m("ship_lock_presentation")
local function snapshot(t)
  local typ=type(t)
  if typ~="table" then assert(typ=="number" or typ=="string" or typ=="boolean");return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=snapshot(v) end
  return out
end
local ascents,descents,phase_steps={}, {}, {}
local restored,prior_tick,previous_height,previous_tile=false,nil,nil,nil
local docked_before_reverse,left_in_reverse=0,0
for tick=1,arrival_ticks[3] do
  local count=p.arrivals
  local before=p.vehicle
  local prior_x,prior_tile,prior_direction=before.x,before.tile,before.direction
  assert(Run.tick(s,1)==p)
  assert(p.vehicle.tick==tick and not p.failure,p.failure)
  local v=p.vehicle
  local tile=board.tile(v.tile)
  local pos=Run.pose(p)
  if tile.part=="middle" then
    assert(v.tile==middle and v.z>=8 and v.z<=16 and pos.y==v.z/8+.5)
    local frame=presentation.frame(s.stock_ship_locks[middle],tile,v,25,20,1)
    local phase=(v.z-8)/8
    assert(frame.phase==phase)
    if phase>0 and phase<1 then assert(not frame.lower and not frame.upper) end
    if previous_tile==middle and v.z~=previous_height then
      local sign=v.direction==5 and 1 or v.direction==1 and -1
      assert(sign and v.z-previous_height==sign)
      if prior_tick then assert(tick-prior_tick==8) end
      prior_tick=tick
      local steps=sign==1 and ascents or descents
      steps[#steps+1]=v.z
      phase_steps[#phase_steps+1]=phase
    end
    if not restored and phase==.5 then
      local x,z,y=v.x,v.y,v.z
      s=snapshot(s);p=assert(Run.current(s));board=Network.board(s);restored=true
      assert(p.vehicle.x==x and p.vehicle.y==z and p.vehicle.z==y and p.vehicle.tick==tick)
      assert(not p.vehicle.loading and p.arrivals==0 and s.stock_ship_locks[middle].middle==middle)
    end
  else
    prior_tick=nil
  end
  if p.arrivals>count then
    local reached=p.arrivals%2==1 and upper or lower
    local berth=p.arrivals%2==1 and high_berth or at(24,18)
    assert(p.phase=="moored" and p.last_dock==reached.id and p.last_berth==berth)
    assert(Water.ship_destination(board,berth,reached.id))
    assert(pos.y==(p.arrivals%2==1 and 2.5 or 1.5))
    assert(tick==arrival_ticks[p.arrivals])
    if terminal and reached==upper then
      -- Confirm the original 14.1 order: continue inside the same tile
      -- to begin loading before reconsidering the dead end for departure.
      assert(prior_tile==high_berth and v.tile==high_berth and v.x==prior_x+1)
      assert(prior_direction==5 and v.direction==5 and v.loading)
      docked_before_reverse=docked_before_reverse+1
    end
  end
  if terminal and prior_tile==high_berth and v.tile==high_berth and prior_direction==5 and v.direction==1 then
    assert(p.arrivals==1 and tick>=arrival_ticks[1]+44 and not v.loading)
    left_in_reverse=left_in_reverse+1
  end
  previous_height,previous_tile=v.z,v.tile
end
assert(restored and p.arrivals==3 and p.steps==(terminal and 338 or 562) and #phase_steps==24)
if terminal then assert(docked_before_reverse==2 and left_in_reverse==1) end
assert(table.concat(ascents,",")=="9,10,11,12,13,14,15,16,9,10,11,12,13,14,15,16")
assert(table.concat(descents,",")=="15,14,13,12,11,10,9,8")
company=Sim.company(s,owner)
assert(initial-company.cash==build_cost and company.revenue==0 and company.paid_units==0)
print(("PASS generated rivers seed1751 (%s): ferry moors high→low→high via all 8 lock steps, mid-chamber reload, $%d build"):
  format(terminal and "dead-end berth" or "dock loops",build_cost))
