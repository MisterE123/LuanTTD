-- Verify road-only town behavior from one uninterrupted engine run.
-- Old independent paused captures remain separate short-window experiments.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local ref=dofile("tests/fixtures/rc1-coherent-bus-town.lua")
local Sim=F.Sim
local Terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
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
  -- June 1 is the last complete live economy match. July 1 extends
  -- the proof for actual town growth/map effects, not the later fleet.
  if a.day<=151 then
    eq("rng1",s.passenger_rating_rng[1],a.rng[1]);eq("rng2",s.passenger_rating_rng[2],a.rng[2])
    eq("cash",c.cash,a.cash)
    eq("fraction",c.stock_money_fraction,a.loans[2])
    eq("lifetime delivered",v.delivered,a.lifetime)
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
  for id,tile in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    eq("height at "..id,Terrain.corner(s.corner_grid,x,z),a.grade_changes[id-1] or initial_heights[id])
    local h,w=tile.source_house,a.houses[id-1]
    eq("house present "..id,h~=nil,w~=nil)
    if h and w then
      eq("house id "..id,h.id,w[1]);eq("house TownID "..id,h.town,w[2]+1);eq("house complete "..id,h.completed and 1 or 0,w[3])
      eq("house stage "..id,h.stage,w[4]);eq("house counter "..id,h.counter,w[5]);eq("house age "..id,h.age or 0,w[6])
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
  if a.day<=151 then
    print(("Matched RC1 day %d: %d houses, %d lifetime paid passengers"):format(a.day,last_houses,a.lifetime))
  else
    print(("Matched RC1 day %d town map and clocks: %d houses"):format(a.day,last_houses))
  end
end
compare(F.first_tick)
local last=0
for _,x in pairs(ref.checks) do last=math.max(last,x.day) end
for day=2,last do
  if day==32 or day==91 then
    local id=v.id
    s=F.reopen(s,true)
    v=assert(s.fleet[id])
  end
  Sim.daily(s)
  compare(s.passenger_house_clock.counter)
end
assert(checked==7 and last==181 and last_houses>10,"Fixture must include actual station-driven town growth")
print("PASS seven checkpoints from one actual stock game with a running bus, across two simulated save/reopens")
