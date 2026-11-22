local F={}
function F.prepare(Sim,s)
  local a,b,d=Sim.id(11,12),Sim.id(17,12),Sim.id(12,13)
  assert(Sim.build(s,"GrowthQA","road",Sim.line(a,b)))
  assert(Sim.build(s,"GrowthQA","road_station",{a,b}))
  assert(Sim.build(s,"GrowthQA","road_depot",{d}))
  local bus=assert(Sim.purchase(s,"GrowthQA","bus","passenger",nil,d))
  assert(Sim.add_order(s,"GrowthQA",bus,s.tiles[a].station))
  assert(Sim.add_order(s,"GrowthQA",bus,s.tiles[b].station))
  return {id=bus,station=s.tiles[a].station,town=1,initial_pop=s.sites[1].population}
end
function F.first(Sim,s,check)
  local qa=F.prepare(Sim,s)
  local st=s.stations[qa.station]
  -- An idle station does not become recently serviced on the first rating
  -- event, nor does the mere arrival of an empty bus reset either age.
  for _=1,4 do Sim.daily(s);if check then check() end end
  assert(st.time_since_load==255 and st.time_since_unload==255 and st.passenger_rating_phase==111)
  assert(Sim.toggle(s,"GrowthQA",qa.id))
  local t=s.stock_town_growth.towns[qa.town]
  local observed,empty_visit=false,false
  for _=1,500 do
    Sim.daily(s)
    if check then check() end
    local bus=s.fleet[qa.id]
    if bus.last_road_arrival_tick and not bus.last_board then
      empty_visit=true
      assert(st.time_since_load==255 and st.time_since_unload==255)
    end
    if bus.last_board and bus.last_board.tile==st.tile and not observed then
      local tick=s.passenger_house_clock.counter
      local last=bus.last_board.tick
      assert(st.time_since_load==math.floor(tick/185)-math.floor((last-1)/185))
      observed=true
    end
    if t.last_build then
      qa.tile=t.last_build.tile
      assert(empty_visit and observed and s.fleet[qa.id].last_fare and t.reason=="serviced" and t.last_active>=1)
      assert(s.fleet[qa.id].last_board.tick<t.last_build.tick and s.stock_load_tick==s.passenger_house_clock.counter)
      break
    end
  end
  assert(qa.tile,"No transport-backed stock house built; last monthly gate: "..tostring(t.reason))
  local tile=s.tiles[qa.tile];local house=tile.source_house
  assert(house.town_growth and not house.completed and not house.first_cargo_tick)
  assert(house.built_tick==t.last_build.tick and t.population==qa.initial_pop)
  assert(house.stage==0 and t.num_houses>=1)
  for _=1,30 do
    Sim.daily(s)
    if check then check() end
    assert(not house.completed and not house.first_cargo_tick and t.population==qa.initial_pop)
    if house.stage==1 and house.counter>=1 then break end
  end
  assert(house.stage==1 and house.counter>=1)
  qa.built_tick,qa.stage,qa.counter=house.built_tick,house.stage,house.counter
  qa.head,qa.tick=s.passenger_house_clock.head,s.passenger_house_clock.counter
  qa.station_age,qa.station_phase=st.time_since_load,st.passenger_rating_phase
  return qa
end
function F.second(Sim,s,qa,spec,check)
  local t=s.stock_town_growth.towns[qa.town]
  local house=s.tiles[qa.tile].source_house
  local st=s.stations[qa.station]
  assert(t.population==qa.initial_pop and s.sites[qa.town].population==qa.initial_pop)
  assert(house.built_tick==qa.built_tick and house.stage==qa.stage and house.counter==qa.counter)
  assert(s.passenger_house_clock.head==qa.head and s.passenger_house_clock.counter==qa.tick)
  assert(st.time_since_load==qa.station_age and st.passenger_rating_phase==qa.station_phase)
  for _=1,90 do
    Sim.daily(s)
    if check then check() end
    if house.completed then break end
    assert(not house.first_cargo_tick and t.population==qa.initial_pop)
  end
  assert(house.completed and not house.first_cargo_tick and house.age==0)
  assert(house.completed_tick-house.built_tick>=11*256 and house.completed_tick-house.built_tick<=12*256)
  assert(s.sites[qa.town].population==qa.initial_pop+spec[house.id][1])
  for _=1,90 do
    Sim.daily(s)
    if check then check() end
    if house.first_cargo_tick then break end
  end
  assert(house.first_cargo_tick and house.first_cargo_tick>house.completed_tick)
  assert((house.first_cargo_tick-house.completed_tick)%256==0)
  return house
end
return F
