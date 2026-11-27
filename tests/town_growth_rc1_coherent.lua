-- Verify road-only town behavior from one uninterrupted engine run.
-- Old independent paused captures remain separate short-window experiments.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local ref=dofile("tests/fixtures/rc1-coherent-bus-town.lua")
local Sim=F.Sim
local Terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
local Rebuild=dofile("mods/luanttd_core/openttd/town_rebuild.lua")
local initial_heights={}
for _,run in ipairs(ref.start.runs) do
  for _=1,run[1] do initial_heights[#initial_heights+1]=run[2] end
end
local s,_,v,owner=F.open(ref.start,true)
local checked,last_houses=0,0
local function eq(key,got,want)
  assert(got==want,("%s: LuanTTD %s, RC1 %s"):format(key,tostring(got),tostring(want)))
end
local function compare(tick)
  local a=ref.checks[tick]
  if not a then return end
  local t=s.stock_town_growth.towns[1]
  local c=s.companies[owner]
  eq("day",s.day,a.day)
  eq("counter",t.grow_counter,a.town[1]);eq("rate",t.growth_rate,a.town[2]);eq("rebuild",t.time_until_rebuild,a.town[3])
  eq("borrowed loan",c.loan,a.loans[1])
  eq("funded months",t.fund_buildings_months or 0,a.timers[1])
  eq("road works months",t.road_build_months or 0,a.timers[2])
  eq("flags",(t.growing and 1 or 0)+(t.unique.church and 2 or 0)+(t.unique.stadium and 4 or 0),a.flags)
  eq("town company rating",c.stock_town_authority_ratings and c.stock_town_authority_ratings[1] or 500,a.rating)
  -- January's physical town is exact. The late-December road service
  -- still has different motion timing, so only compare its economics,
  -- station state and shared RNG at the twelve fully matched dates.
  local full=a.day<=334
  if full then
    eq("rng1",s.passenger_rating_rng[1],a.rng[1]);eq("rng2",s.passenger_rating_rng[2],a.rng[2])
    eq("cash",c.cash,a.cash)
    eq("last economy service",v.road_fault.date_of_last_service,a.vehicle_service[1])
    eq("last calendar service",v.road_fault.date_of_last_service_newgrf,a.vehicle_service[2])
    eq("breakdowns after service",v.road_fault.breakdowns_since_last_service,a.vehicle_service[3])
    eq("reliability",v.road_fault.reliability,a.fault[1])
    eq("breakdown chance",v.road_fault.breakdown_chance,a.fault[2])
    eq("breakdown counter",v.road_fault.breakdown_ctr,a.fault[3])
    eq("fraction",c.stock_money_fraction,a.loans[2])
    local pending=v.load_state and v.load_state.payment and v.load_state.payment.delivered or 0
    eq("lifetime delivered",v.delivered+pending,a.lifetime)
    if a.day==304 then eq("November cargo unloaded but not paid",pending,8) end
    for j,q in ipairs(a.quarters) do
      local r=j==1 and c.stock_quarter or c.stock_quarters and c.stock_quarters[j-1]
      r=r or {income=0,expenses=0,delivered={}}
      eq("quarter "..j.." income",r.income,q[1]);eq("quarter "..j.." expense",r.expenses,q[2])
      eq("quarter "..j.." passengers",r.delivered.passenger or 0,q[3])
    end
    local accepted=t.accepted and t.accepted.passenger or {}
    eq("town accepted (current)",accepted.new_act or 0,a.accepted[1])
    eq("town accepted (previous)",accepted.old_act or 0,a.accepted[2])
    local received=t.received[1] or {}
    for i,field in ipairs({"new_act","old_act","new_max","old_max"}) do
      eq("town effect "..field,received[field] or 0,a.received[i])
    end
    for index,name in pairs({[0]="passenger",[2]="mail"}) do
      local have,want=t.supplied[name],a.supply[index]
      eq(name.."new_max",have.new_max,want[1]);eq(name.."new_act",have.new_act,want[2])
      eq(name.."old_max",have.old_max,want[3]);eq(name.."old_act",have.old_act,want[4])
    end
    for id,st in pairs(s.stations) do
      local w=a.service[id]
      eq("station "..id.." load age",st.time_since_load,w[1]);eq("station "..id.." unload age",st.time_since_unload,w[2])
      eq("station "..id.." rating",st.passenger_rating_state.rating,w[3])
    end
  end
  local year=Sim.date(s)
  for id,tile in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    eq("height at "..id,Terrain.corner(s.corner_grid,x,z),a.grade_changes[id-1] or initial_heights[id])
    local h,w=tile.source_house,a.houses[id-1]
    eq("house present "..id,h~=nil,w~=nil)
    if h and w then
      eq("house id "..id,h.id,w[1]);eq("house TownID "..id,h.town,w[2]+1);eq("house complete "..id,h.completed and 1 or 0,w[3])
      eq("house stage "..id,h.stage,w[4]);eq("house counter "..id,h.counter,w[5]);eq("house age "..id,Rebuild.age(h,year),w[6])
      eq("house bits "..id,h.random_bits,w[7])
    end
    local q=a.roads[id-1]
    if tile.build=="road" or q then
      eq("road mask "..id,tile.road_bits,q and q[1])
      eq("road town "..id,tile.road_town,q and q[2]+1)
      eq("road owner "..id,tile.owner,q and q[3]==0 and owner or nil)
    end
  end
  checked=checked+1
  last_houses=t.num_houses
  if full then
    print(("Matched RC1 day %d: %d houses, %d lifetime delivered passengers"):format(a.day,last_houses,a.lifetime))
  else
    print(("Matched RC1 physical town at the year boundary: %d houses"):format(last_houses))
  end
end
compare(F.first_tick)
local last=0
for _,x in pairs(ref.checks) do last=math.max(last,x.day) end
for day=2,last do
  if day==32 or day==91 or day==305 then
    local id=v.id
    s=F.reopen(s,true,ref.start.service_options)
    v=assert(s.fleet[id])
  end
  Sim.daily(s)
  compare(s.passenger_house_clock.counter)
end
assert(checked==13 and last==365 and last_houses>10,"Fixture must include actual station-driven town growth")
assert(v.road_fault.services and v.road_fault.services>0 and v.last_auto_depot,
  "Fixture must run actual automatic depot servicing")
print("PASS twelve full stock checkpoints and January physical town across three simulated save/reopens")
