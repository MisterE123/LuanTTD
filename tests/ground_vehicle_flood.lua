-- SPDX-License-Identifier: GPL-2.0-only
local F=dofile("mods/luanttd_core/openttd/ground_vehicle_flood.lua")
local first,second,raised,dead={}, {}, {}, {crashed=true}
local at={[1]={{front=dead,z=0},{front=first,z=1},{front=second,z=0}},
          [2]={{front=raised,z=2},{front=second,z=0},{front=first,z=0}}}
local called={}
F.visit_ground(1,2,0,function(tile) return at[tile] end,function(front)
  assert(not front.crashed)
  front.crashed=true
  called[#called+1]=front
end)
assert(#called==2 and called[1]==second and called[2]==first and not raised.crashed)
assert(F.train_crash_age(true)==4000 and F.train_crash_age(false)==1)
for started=0,31 do
  local age=F.train_crash_age(true)
  local n=0
  for tick=started+1,started+512 do
    local due
    age,due=F.train_wreck_tick(age,tick)
    assert(age==4000+tick-started)
    if due then
      assert(age>=4440 and tick%32==0)
      if n==0 then assert(age<=4471) end
      n=n+1
    end
  end
  assert(n>=2)
end
assert(F.train_victims(0,99,true)==2 and F.train_victims(2^32-1,99,true)==101)
assert(F.train_victims(2^31,9,false)==5)
print("PASS stock ordered ground-body flood, two bridge ends, randomized victims, and per-vehicle wreck clock")

-- RoadVehicle::Crash adds one driver, and retires much earlier than rail.
assert(F.road_victims(0,99,true)==1 and F.road_victims(2^32-1,99,true)==100)
assert(F.road_victims(2^31,9,false)==5 and F.road_victims(2^32-1,0,true)==1)
assert(F.road_crash_age(true)==2000 and F.road_crash_age(false)==1)
for started=0,31 do
  local age,first=F.road_crash_age(true),nil
  for tick=started+1,started+260 do
    local due
    age,due=F.road_wreck_tick(age,tick)
    assert(age==2000+tick-started and due==(age>=2220 and tick%32==0))
    if due and not first then first=age end
  end
  assert(first>=2220 and first<=2251)
end
print("PASS stock road casualties and one-body flood wreck retirement timing")
