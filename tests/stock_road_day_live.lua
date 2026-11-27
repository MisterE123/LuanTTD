-- Compare actual simulated town service, running costs and road wear
-- with typed observations from the pinned stock RC1 experiment.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local S=F.Sim
local source=dofile("tests/fixtures/rc1-active-bus-day.lua")
local motion=dofile("tests/fixtures/rc1-active-bus-motion.lua")
local s,_,v,owner=F.open(motion.start,true)
local through=2509
local early,boundaries=0,0
local function equal(value,expected,tick,label)
  assert(value==expected,("RC1 active bus at %d, %s: LuanTTD %s vs stock %s")
    :format(tick,label,tostring(value),tostring(expected)))
end
local function compare(tick)
  local expect=source[tick]
  if not expect then return end
  local function eq(got,want,key) equal(got,want,tick,key) end
  local town=s.stock_town_growth.towns[1]
  eq(s.day-(expect.fraction==0 and 0 or 1),expect.day,"date")
  eq(town.grow_counter,expect.town[1],"town grow countdown")
  eq(town.growth_rate,expect.town[2],"town growth interval")
  eq(town.time_until_rebuild,expect.town[3],"town rebuild countdown")
  eq(v.stock_vehicle_random_bits,expect.triggers[1],"stock vanilla sprite bits stay unchanged")
  eq(v.stock_waiting_random_triggers,expect.triggers[2],"retained stock vehicle trigger bits")
  if tick>through then
    if tick==3574 then
      eq(s.passenger_rating_rng[1],expect.rng[1],"random word 1 after a served month")
      eq(s.passenger_rating_rng[2],expect.rng[2],"random word 2 after a served month")
      eq(v.delivered,expect.delivered,"first month's paid passengers")
      for i,ref in ipairs(expect.service) do
        local st=s.stations[i]
        eq(st.time_since_load,ref[1],"town served station load age")
        eq(st.time_since_unload,ref[2],"town served station unload age")
        eq(st.passenger_rating_state.rating,ref[3],"station rating")
      end
    end
    boundaries=boundaries+1
    return
  end
  local rnd,ff=s.passenger_rating_rng,v.road_fault
  eq(rnd[1],expect.rng[1],"random word 1")
  eq(rnd[2],expect.rng[2],"random word 2")
  eq(s.companies[owner].cash,expect.cash,"company balance before finance rollover")
  eq(ff.reliability,expect.fault[1],"reliability")
  eq(ff.breakdown_chance,expect.fault[2],"breakdown chance")
  eq(ff.breakdown_ctr,expect.fault[3],"breakdown counter")
  eq(ff.age,expect.fault[4],"calendar age")
  eq(v.delivered,expect.delivered,"passengers paid")
  for id,ref in ipairs(expect.service) do
    eq(s.stations[id].passenger_rating_state.rating,ref[3],"road station rating "..id)
  end
  for index,name in pairs({[0]="passenger",[2]="mail"}) do
    local q,ref=town.supplied[name],expect.supply[index]
    eq(q.new_max,ref[1],"town generated "..name)
    eq(q.new_act,ref[2],"town loaded "..name)
    eq(q.old_max,ref[3],"last month generated "..name)
    eq(q.old_act,ref[4],"last month loaded "..name)
  end
  early=early+1
end
compare(F.first_tick)
for day=2,59 do
  if day==12 then
    local before=s
    s=F.reopen(s,true)
    v=assert(s.fleet[v.id])
    assert(s.passenger_house_clock.counter==before.passenger_house_clock.counter)
    assert(v.road_fault.reliability==before.fleet[v.id].road_fault.reliability)
  end
  S.daily(s,nil,compare)
end
assert(early==19 and boundaries==2)
print(("PASS %d exact active RC1 road economy snapshots plus two matching growth month boundaries"):format(early))

-- Confirm that a second depot purchase uses a different fraction in the
-- same ordinary day, without disturbing the stock comparisons above.
local next_id=assert(S.purchase(s,owner,"bus","passenger",nil,2383))
local next_bus=s.fleet[next_id]
local start_tick=s.passenger_house_clock.counter
local old_first=v.stock_bus.day
local old_second=next_bus.stock_bus.day
local old_second_age=next_bus.road_fault.age
S.daily(s,nil,function(tick)
  if tick==start_tick+1 then
    assert(next_id==2 and next_bus.stock_bus.day==old_second+1)
    assert(next_bus.road_fault.age==old_second_age+1 and v.stock_bus.day==old_first)
  elseif tick==start_tick+74 then
    assert(next_bus.stock_bus.day==old_second+1 and v.stock_bus.day==old_first+1)
  end
end)
print("PASS two owned buses settle on their own road-pool fractions in the same day")
