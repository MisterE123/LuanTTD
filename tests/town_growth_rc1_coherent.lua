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
local frame_count,traced=0,0
local digest_rng,digest_pose,digest_wait=1,1,1
local function hash(h,...)
  for i=1,select("#",...) do h=(h*65599+(select(i,...)))%2147483647 end
  return h
end
local function compare_tick(tick)
  traced=traced+1
  digest_rng=hash(digest_rng,tick,s.passenger_rating_rng[1],s.passenger_rating_rng[2])
  local f=Sim.road_motion_frame(s,v)
  if f then
    local moving=v.road_speed_state
    local c=moving or assert(v.road_stop_motion)
    digest_pose=hash(digest_pose,tick,f[4]-1,f[1]-16,f[2]-16,Sim.stock_road_frame_z(s,f),
      f[3],c.progress,moving and c.speed or 0,c.subspeed)
  else
    local c=assert(v.road_stop_motion,"Trace must hide the bus only after actual depot entry")
    assert(c.depot and v.depot and v.last_depot_entry_tick==tick)
    digest_pose=hash(digest_pose,tick,v.depot-1,-1,-1,-1,-1,c.progress,0,c.subspeed)
  end
  for id=1,2 do
    local st=s.stations[id]
    local waiting=0
    for _,p in ipairs((st.stock or {}).passenger or {}) do waiting=waiting+p.units end
    digest_wait=hash(digest_wait,tick,id-1,waiting,st.passenger_fraction or 0)
  end
  local want=ref.digest[tick]
  if want then
    eq("random stream through tick "..tick,digest_rng,want[1])
    eq("bus motion through tick "..tick,digest_pose,want[2])
    eq("station queues through tick "..tick,digest_wait,want[3])
  end
end
local function compare_physical(tick)
  local want=ref.physical[tick]
  if not want then return end
  local label="native RC1 vehicle frame "..tick.." "
  local f=Sim.road_motion_frame(s,v)
  if want[9]==254 then
    eq(label.."visible",f~=nil,false)
    eq(label.."depot tile",v.depot,want[1]+1)
    eq(label.."actual entry tick",v.last_depot_entry_tick,tick)
    local c=assert(v.road_stop_motion)
    eq(label.."retained progress",c.progress,want[6])
    eq(label.."retained subspeed",c.subspeed,want[8])
    local packing=dofile("mods/luanttd_core/packed_campaign.lua")
    local copy=assert(packing.decode(assert(packing.encode(s))))
    local saved=assert(copy.fleet[v.id].road_stop_motion)
    eq(label.."packed retained subspeed",saved.subspeed,want[8])
    eq(label.."packed retained progress",saved.progress,want[6])
    eq(label.."packed departure gate",saved.depot,true)
  else
    local moving=v.road_speed_state
    local c=moving or assert(v.road_stop_motion)
    local got={f[4]-1,f[1]-16,f[2]-16,Sim.stock_road_frame_z(s,f),f[3],
      c.progress,moving and c.speed or 0,c.subspeed,f[6],f[15]}
    for i,value in ipairs(want) do
      -- The stock entered-stop bit is represented by load_state, not
      -- duplicated in the adapter's mechanical motion state.
      if i==9 and value>=64 and value<80 then value=value-math.floor(value/4)%2*4 end
      eq(label..i,got[i],value)
    end
  end
  frame_count=frame_count+1
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
  print(("Matched RC1 day %d: %d houses, %d lifetime delivered passengers"):format(a.day,last_houses,a.lifetime))
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
  Sim.daily(s,nil,function(tick) compare_physical(tick);compare_tick(tick) end)
  compare(s.passenger_house_clock.counter)
end
assert(frame_count==25,"Fixture must exercise the sloped reversal and the full depot transition")
assert(checked==13 and last==365 and last_houses>10,"Fixture must include actual station-driven town growth")
assert(v.road_fault.services and v.road_fault.services>=2 and v.last_auto_depot,
  "Fixture must run actual automatic depot servicing")
assert(traced==26936)
print("PASS thirteen RC1 checkpoints, including every shared RNG word, bus pose and station queue across 26,936 ticks and three save/reopens")
