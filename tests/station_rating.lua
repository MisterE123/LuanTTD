local R=dofile("mods/luanttd_core/openttd/station_rating.lua")
local g=R.new()
assert(not g.has_rating and g.rating==175 and not R.has_tried_loading(g) and g.time_since_pickup==255)

-- The adapter does not call loading telemetry on an unload-only order.
-- A normal empty bus visit makes a stop eligible, even before passengers queue.
R.observe_loading(g,97,0,30)
assert(R.has_tried_loading(g) and g.time_since_pickup==0 and g.last_speed==97 and g.last_age==0)
assert(not g.has_rating)
R.observe_waiting(g,0)
assert(not g.has_rating)
R.observe_waiting(g,1)
assert(g.has_rating)
local reply=R.step(g,{waiting=1,destinations=1,select_goods=true})
assert(reply.time_since_pickup==1 and reply.drop==0 and reply.waiting==1 and reply.rating==177)
assert(g.rating==175 and g.time_since_pickup==0,"Kernel must not mutate its inputs")

local held=R.new()
R.observe_loading(held,123,2,0)
assert(R.has_tried_loading(held) and held.time_since_pickup==255 and held.last_speed==123 and held.last_age==2)
held.time_since_pickup=254;R.observe_waiting(held,1)
local expired=R.step(held,{waiting=23,destinations=1,select_goods=true})
assert(expired.expire and expired.drop==23 and not expired.has_rating and not R.has_tried_loading(expired))
assert(expired.time_since_pickup==255 and expired.rng_calls==0 and expired.waiting==0)
R.observe_loading(expired,97,0,30)
assert(R.has_tried_loading(expired) and not expired.has_rating and expired.time_since_pickup==0)

g.rating=99
local unsigned=R.step(g,{waiting=19,destinations=1,select_goods=true,random_u32=function() return 127 end})
assert(unsigned.waiting_changed and unsigned.drop==0 and unsigned.waiting==19 and unsigned.max_waiting_cargo==9)
local removed=R.step(g,{waiting=19,destinations=1,select_goods=true,random_u32=function() return 0x37f end})
assert(removed.waiting_changed and removed.drop==2 and removed.waiting==17 and removed.max_waiting_cargo==0)
local clock,elapsed=0,0
for i=1,5 do
  local periods
  clock,periods=R.advance_clock(clock,R.day_ticks)
  elapsed=elapsed+periods
end
assert(clock==0 and elapsed==2)

print("PASS: station eligibility, active cargo, full-bus telemetry, expiration, signed loss arithmetic and rating phase")
