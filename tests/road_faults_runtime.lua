local path="mods/luanttd_core/"
local B=dofile(path.."openttd/road_breakdowns.lua")
local Host=dofile(path.."road_faults_runtime.lua")
local state={day=3,stock_bus_market={epoch=713620},fleet={}}
local v={id=1,engine="test_stock_bus",stock_bus={stock_id=118},running=true,
  road_speed_state={index=53,speed=86,progress=211,subspeed=17},orders={1,2}}
local rng_calls=0
local function rng() rng_calls=rng_calls+1;return 0x03040000 end
local source_reliability=50026
local Sim={stock_road_offer=function(s,engine)
    assert(s==state and engine==v.engine)
    return {reliability=source_reliability,reliability_decay=80,life_days=5490}
  end}
state.fleet[1]=v
local off=Host(B,Sim,state,0,rng)
off.purchased(v);assert(not v.road_fault and not off.report(v))
local runtime=Host(B,Sim,state,2,rng)
runtime.purchased(v);local f=assert(v.road_fault)
assert(f.reliability==50026 and f.max_age==5490 and f.date_of_last_service==713623)
assert(runtime.tick(v,11)==false and f.tick_counter==1)
v.road_speed_state.blocked_ctr=1
runtime.daily();assert(f.reliability==50026 and rng_calls==0)
v.road_speed_state.blocked_ctr=0
f.reliability,f.breakdown_chance=1500,255
runtime.daily()
assert(rng_calls==1 and f.breakdown_ctr==67 and f.breakdown_delay==131)
for tick=12,76 do
  assert(runtime.tick(v,tick)==false)
end
assert(f.breakdown_ctr==2 and v.road_speed_state.speed==86)
assert(runtime.tick(v,77)==true and v.road_speed_state.speed==0 and f.last_start==77)
local saved=v.road_fault
local resumed_disabled=Host(B,Sim,state,0,rng)
local tick=78
while f.breakdown_ctr~=0 do
  assert(resumed_disabled.tick(v,tick)==true)
  assert(v.road_speed_state.index==53 and v.road_speed_state.progress==211
      and v.road_speed_state.subspeed==17 and v.orders[2]==2 and v.running)
  tick=tick+1
end
assert(tick>300 and saved==v.road_fault and f.last_recovery==tick-1 and rng_calls==1)
assert(not resumed_disabled.tick(v,tick))
f.breakdown_chance=100;f.breakdown_ctr=35
state.day=18;source_reliability=49255
runtime.service(v,901)
assert(f.services==1 and f.last_service_tick==901 and f.reliability==49255)
assert(f.breakdown_chance==25 and f.breakdown_ctr==35 and f.date_of_last_service==713638)
assert(v.status=="En route")
print("PASS: live-host road fault guard, global draw, stock resume without resetting motion, and genuine service reset")
