-- Ordinary road loader, real landscape house cargo and paid vehicles.
-- Arrange two municipal catchments, deliberately giving the destination
-- station a different associated town from its physically covered houses.
local root="mods/luanttd_core/"
local function m(x) return dofile(root..x..".lua") end
local Sim,Terrain,G=m("sim"),m("openttd/terrain"),m("openttd/town_growth")
local owner="Closing the loop"
local function run(cargo,offer)
  local s=Sim.new(1751)
  m("town_layout")(Sim,s)
  s.corner_grid=m("terrain_preview")(Sim,Terrain,s)
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_mail=true,true,true,true,true
  local a,b,d=Sim.id(11,12),Sim.id(17,12),Sim.id(12,13)
  assert(Sim.build(s,owner,"road",Sim.line(a,b)))
  if cargo=="mail" then
    assert(Sim.build_truck_stop(s,owner,a) and Sim.build_truck_stop(s,owner,b))
  else
    assert(Sim.build(s,owner,"road_station",{a,b}))
  end
  assert(Sim.build(s,owner,"road_depot",{d}))
  local Towns=m("campaign_simulation_bindings")(Sim,root:sub(1,-2))
  Towns.towns(s)
  local left=s.stations[s.tiles[a].station]
  local right=s.stations[s.tiles[b].station]
  local coverage_l=Sim.road_stop_catchment(s,left,3)
  local coverage_r=Sim.road_stop_catchment(s,right,3)
  local counts={0,0}
  for id,t in ipairs(s.tiles) do
    local h=t.source_house
    if h then
      if coverage_l[id] then h.town=1;counts[1]=counts[1]+1
      elseif coverage_r[id] then h.town=2;counts[2]=counts[2]+1 end
    end
  end
  assert(counts[1]>0 and counts[2]>0)
  right.town=1 -- deliberately different from qualifying covered houses
  local book=assert(Sim.mount_stock_subsidies(s))
  local rules=m("openttd/subsidy")(G.range,G.chance)
  if offer then
    -- The offer is the same source-supported command outcome as a
    -- GameScript CreateSubsidy, not a fare or passenger injection.
    assert(rules.create(book.subsidies,cargo=="mail" and 2 or 0,
      {type="town",id=0},{type="town",id=1}))
  end
  local id=assert(Sim.purchase(s,owner,cargo=="mail" and "mail_van" or "bus",cargo,nil,d))
  assert(Sim.add_order(s,owner,id,left.id,"full"))
  assert(Sim.add_order(s,owner,id,right.id,"no_load"))
  assert(Sim.toggle(s,owner,id))
  for _=1,180 do
    Sim.daily(s)
    local v=s.fleet[id]
    if v.last_fare and v.last_fare.amount>0 then
      if offer then
        assert(book.subsidies.rows[0].awarded==owner,
          "A station must qualify by its covered town, not its associated town")
      end
      return v.last_fare.amount,v.last_fare.units
    end
  end
  error("Ordinary service never paid")
end
for _,cargo in ipairs({"passenger","mail"}) do
  local a,n=run(cargo,false)
  local b,moved=run(cargo,true)
  assert(n==moved and b==3*a,("%s road fare %d vs %d; cargo %s vs %s"):format(cargo,a,b,tostring(n),tostring(moved)))
  print(("PASS road %s physically delivered for %d → %d with one stock multiplier"):format(cargo,a,b))
end
