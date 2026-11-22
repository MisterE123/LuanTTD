local B=dofile("mods/luanttd_core/openttd/road_breakdowns.lua")
local E=dofile("mods/luanttd_core/openttd/stock_engine_calendar.lua")
local function copy(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
local function forbidden() error("stock Random() must not be consumed here") end

local model=assert(E.prepare(116,{starting_year=1950,generation_seed=1751,startup_seed=97721,climate="temperate"}))
local old_date,new_date=E.date(1950,1,1),E.date(1955,6,8)
local snapshot=E.snapshot(model,old_date)
local service_snapshot=E.snapshot(model,new_date)
local v=B.new(snapshot.reliability,snapshot.reliability_decay,12*366,old_date+10,old_date)
assert(v.version==B.VERSION and v.reliability==snapshot.reliability and v.reliability_spd_dec==80)
assert(v.date_of_last_service-v.date_of_last_service_newgrf==10)
assert(v.breakdown_ctr==0 and v.breakdown_delay==0 and v.breakdowns_since_last_service==0)
local calendar,original=v.age,v.reliability
B.economy_day(v,{front=false,difficulty=B.NORMAL,cur_speed=64},forbidden)
B.economy_day(v,{blocked_ctr=1,difficulty=B.NORMAL,cur_speed=64},forbidden)
assert(v.age==calendar and v.reliability==original)
B.calendar_day(v,{front=false})
assert(v.age==calendar)
B.calendar_day(v,{front=true})
assert(v.age==calendar+1 and v.reliability==original)
B.economy_day(v,{difficulty=B.OFF,cur_speed=64},forbidden)
assert(v.reliability==original)
B.economy_day(v,{difficulty=B.OFF,no_servicing_if_no_breakdowns=false,cur_speed=64},forbidden)
assert(v.reliability==original-80)
B.economy_day(v,{difficulty=B.NORMAL,cur_speed=4},forbidden)
B.economy_day(v,{difficulty=B.NORMAL,cur_speed=64,stopped=true},forbidden)
B.economy_day(v,{difficulty=B.NORMAL,cur_speed=64,menu=true},forbidden)
assert(v.reliability==original-4*80 and v.breakdown_chance==0)

-- The low byte threshold is checked after decay and after the 1/25
-- chance boost. High random bits are used once for both durations.
local calls=0
local function entropy() calls=calls+1;return 0x7f3f0000 end
v.reliability=0
v.breakdown_chance=0
assert(B.economy_day(v,{difficulty=B.NORMAL,cur_speed=5},entropy))
assert(calls==1 and v.breakdown_chance==0 and v.breakdown_ctr==126 and v.breakdown_delay==255)
B.economy_day(v,{difficulty=B.NORMAL,cur_speed=128},forbidden)
v.breakdowns_since_last_service=254
v.tick_counter=255
local loading=B.tick(v,{cur_speed=28,loading=true})
assert(v.tick_counter==0 and v.breakdown_ctr==126 and not loading.hold_motion and loading.cur_speed==28)
for _=1,124 do
  local run=B.tick(v,{cur_speed=18})
  assert(not run.hold_motion and not run.started and run.cur_speed==18)
end
assert(v.breakdown_ctr==2 and v.tick_counter==124)
-- If already at 2 it fires even when loading and the user stop flag
-- is set. Crash processing, however, precedes the breakdown handler.
local crash=B.tick(v,{cur_speed=20,crashed=true})
assert(v.tick_counter==125 and v.breakdown_ctr==2 and not crash.hold_motion and not crash.started)
local began=B.tick(v,{cur_speed=20,loading=true,stopped=true})
assert(began.started and began.hold_motion and began.cur_speed==0 and began.smoke_animation_state==510)
assert(v.breakdown_ctr==1 and v.breakdown_delay==254 and v.breakdowns_since_last_service==255)
v=copy(v) -- persisted playback including parity; no new RNG or invented timer
B.economy_day(v,{difficulty=B.OFF,cur_speed=0},forbidden)
assert(v.breakdown_ctr==1 and v.breakdown_delay==254)
for i=1,508 do
  local tick=B.tick(v,{cur_speed=0})
  assert(tick.hold_motion and not tick.started)
  assert((tick.recovered==true)==(i==508))
end
assert(v.breakdown_ctr==0 and v.breakdown_delay==0)
assert(not B.tick(v,{cur_speed=0}).hold_motion,"only next tick resumes motion")

-- An actual service may occur during a pending countdown (e.g. entered
-- depot during the grace period). It must not silently cancel the fault.
v.breakdown_ctr,v.breakdown_delay,v.breakdown_chance=4,151,255
v.reliability_spd_dec=641
B.service(v,service_snapshot.reliability,new_date+20,new_date,B.NORMAL)
assert(v.date_of_last_service==new_date+20 and v.date_of_last_service_newgrf==new_date)
assert(v.reliability==service_snapshot.reliability and v.breakdowns_since_last_service==0)
assert(v.breakdown_chance==63 and v.breakdown_ctr==4 and v.breakdown_delay==151 and v.reliability_spd_dec==641)
B.service(v,service_snapshot.reliability,new_date+21,new_date+1,B.REDUCED)
assert(v.breakdown_chance==0 and v.breakdown_ctr==4 and v.breakdown_delay==151)
v.breakdown_chance=255
B.service(v,service_snapshot.reliability,new_date+21,new_date+1,B.OFF)
assert(v.breakdown_chance==63)

-- Exact source age events on the separate calendar, including unsigned
-- decay overflow if a stock save supplied unusually large decay.
v.age=v.max_age-1
v.reliability_spd_dec=40000
assert(B.calendar_day(v) and v.age==v.max_age and v.reliability_spd_dec==14464)
local boundaries={[366]=true,[731]=true,[1096]=true,[1461]=true}
for d=1,1600 do assert(B.calendar_day(v)==not not boundaries[d]) end
v.age=B.MAX_AGE
assert(not B.calendar_day(v) and v.age==B.MAX_AGE)

-- Reduced mode biases comparison reliability (it is not a uniform
-- chance multiplier). Hidden/flagged smoke is suppressed, not the stop.
v=B.new(0,0,100,0,0)
local function no_boost() return 2621 end
B.economy_day(v,{difficulty=B.REDUCED,cur_speed=40},no_boost)
B.economy_day(v,{difficulty=B.REDUCED,cur_speed=40},no_boost)
assert(not B.economy_day(v,{difficulty=B.REDUCED,cur_speed=40},no_boost))
assert(B.economy_day(v,{difficulty=B.NORMAL,cur_speed=40},no_boost))
v.breakdown_ctr=2
local hidden=B.tick(v,{cur_speed=25,hidden=true})
assert(hidden.started and hidden.hold_motion and hidden.cur_speed==0 and hidden.smoke_animation_state==nil)
print("PASS: stock road chronology, difficulty/entropy, exact failure and restart across reload, service, and over-age decay")
