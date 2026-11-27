-- Mount the live town, catchment and road controllers on the pinned stock board.
-- Assertions here isolate physical bus motion; this does not assert the later
-- complete town replay, including station arrival and economy/RNG ordering.
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local samples=dofile("tests/fixtures/rc1-active-bus-motion.lua")
local Sim,first_tick=F.Sim,F.first_tick
local s,_,v=F.open(samples.start)
local count=0
local function tick(t)
  local e=t-first_tick
  local ref=samples.samples[e]
  if not ref then return end
  local c=assert(v.road_speed_state)
  local f=assert(Sim.road_motion_frame(s,v))
  local fields={f[4]-1,f[1]-16,f[2]-16,f[3],c.progress,c.speed,c.subspeed,f[6],f[15],c.incline}
  for i=1,#ref do
    assert(fields[i]==ref[i],("RC1 bus motion after %d ticks, field %d: LuanTTD %s vs stock %s")
      :format(e,i,tostring(fields[i]),tostring(ref[i])))
  end
  count=count+1
end
for day=2,5 do Sim.daily(s,nil,tick) end
local expected=0;for _ in pairs(samples.samples) do expected=expected+1 end
assert(count==expected and expected>=14)
print(("PASS %d real RC1 bus snapshots: pixels, heading, state, progress, speed and incline"):format(count))
