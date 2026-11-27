-- Raw source call/engine state observed in the pinned 16.0-RC1 startup,
-- after forest generation for the controlled Temperate seed 1751 board.
local base="mods/luanttd_core/"
local function l(path) return dofile(base..path..".lua") end
local Sim=l("sim")
local E=l("openttd/stock_engine_calendar")
local T=l("openttd/terragenesis")(l("openttd/slope"))
local date=assert(E.date(1950,1,1))
local rng={3504580601,2864471766}
local s={seed=1751,day=0,fleet={},news={},stock_generated_profile={forest={rng[1],rng[2]}},
  passenger_rating_rng=rng}
Sim.mount_road_bus_market(s,E,1950)
assert(s.stock_bus_market.settings.startup_seed~=974943486)
Sim.stock_world_launch(s,E)
assert(s.stock_engine_startup_seed==974943486 and s.stock_bus_market.settings.startup_seed==974943486)
assert(rng[1]==648349777 and rng[2]==1686804224 and s.stock_disaster_delay==986)
local model=s.stock_bus_market.models[116]
assert(model.startup_age==249 and model.intro_date==704643)
assert(model.phase1==35 and model.phase2==398 and model.phase3==135)
assert(model.reliability_start==36268 and model.reliability_max==51931 and model.reliability_final==22700)
assert(E.snapshot(model,date).reliability==51931)
assert(not pcall(Sim.stock_world_launch,s,E) and rng[1]==648349777 and rng[2]==1686804224)

-- Disabled disaster clocks still draw at their EconomyDay expiry;
-- they must run before the Industry callback and not on its first tick.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local input=dofile("tests/fixtures/rc1-active-bus-motion.lua")
local running=F.open(input.start,true)
running.stock_disaster_delay=1
running=F.reopen(running,true)
local next_draw
local count=0
F.Sim.daily(running,nil,function(tick)
  count=count+1
  if count<74 then
    assert(running.stock_disaster_delay==1)
    local q=running.passenger_rating_rng
    next_draw={q[1],q[2]}
    T.next_random(next_draw)
  end
end,function(phase)
  assert(count==73 and phase=="day")
  local q=running.passenger_rating_rng
  assert(q[1]==next_draw[1] and q[2]==next_draw[2])
  assert(running.stock_disaster_delay==q[2]%512+730)
end)
assert(count==74)
print("PASS actual RC1 engine launch RNG, Regal design phases and disabled disaster rollover at the true day boundary")
