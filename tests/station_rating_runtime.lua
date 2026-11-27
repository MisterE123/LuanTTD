local ROOT="mods/luanttd_core/"
local Sim=dofile(ROOT.."sim.lua")
local Kernel=dofile(ROOT.."openttd/station_rating.lua")
local Packets=dofile(ROOT.."openttd/passengers.lua")
local R=dofile(ROOT.."station_rating_runtime.lua")(Sim,Kernel,Packets)
dofile("tests/stock_rng_rc1_vectors.lua")(R)
local function station(s,id)
  local st={id=id,mode="road",stock={},last_service={}}
  s.stations[id]=st
  return st
end
local function enqueue(s,st,units,source)
  Packets.enqueue(st,{units=units,origin_station=source or st.id,source=1,age=0})
  R.generated(s,st,units)
end
local function world()
  return {day=0,seed=1751,stations={}}
end
local bus={engine="bus",bought=0}
local s=world()
local a=station(s,1)
assert(R.offer(s,a)==nil)
R.observe_loading(s,a,bus,30)
assert(R.offer(s,a)==175)
assert(a.passenger_rating_state.time_since_pickup==0 and not a.passenger_rating_state.has_rating)
enqueue(s,a,40)
R.advance(s,74)
local b=station(s,2)
R.advance(s,74)
assert(a.passenger_rating_phase==148 and b.passenger_rating_phase==74)
assert(a.passenger_rating_state.rating==175 and not a.time_since_load)
R.advance(s,74)
assert(a.passenger_rating_state.rating==177 and a.time_since_load==1 and a.time_since_unload==1)
assert(b.passenger_rating_phase==148 and b.time_since_load==nil)
R.advance(s,74)
assert(b.time_since_load==1 and a.time_since_load==1)
R.loaded(a);R.unloaded(a)
assert(a.time_since_load==0 and a.time_since_unload==0 and a.last_vehicle_type=="road")
s.day=360*4
local since=a.passenger_rating_state.time_since_pickup
R.observe_loading(s,a,bus,0)
assert(a.passenger_rating_state.time_since_pickup==since)
assert(a.passenger_rating_state.last_age==4 and a.passenger_rating_state.last_speed==56)
a.stop_type="truck"
assert(not R.offer(s,a))
a.stop_type=nil
a.passenger_rating_state.rating=0
assert(not R.offer(s,a))

s=world()
a=station(s,1)
-- Only a real transferred batch is eligible for the first-drop grace.
R.transferred(s,a)
Packets.enqueue(a,{units=23,origin_station=2})
assert(a.passenger_rating_state.time_since_pickup==0)
assert(R.offer(s,a)==nil and a.passenger_rating_state.has_rating)
R.advance(s,Kernel.rating_ticks*255)
assert(Packets.waiting(a)==0 and not a.passenger_rating_state.has_rating)
assert(R.offer(s,a)==nil and a.passenger_rating_state.time_since_pickup==255)
R.observe_loading(s,a,bus,30)
assert(R.offer(s,a)>0 and not a.passenger_rating_state.has_rating)

s=world()
a=station(s,1);b=station(s,2)
R.observe_loading(s,a,bus,30)
R.observe_loading(s,b,bus,30)
enqueue(s,b,2000,a.id)
R.advance(s,185)
assert(Packets.waiting(b)==2000,"legacy 1,200 limit must not return")
enqueue(s,b,8000,a.id)
R.advance(s,185)
assert(Packets.waiting(b)==9908,"use stock queue pressure, not a hard read limit")
assert(a.passenger_rating_state.max_waiting_cargo==9908,"stock truncation feeds remaining cargo by origin back to that station")
assert(b.passenger_rating_state.max_waiting_cargo==0)
assert(s.passenger_rating_rng~=nil,"stock packet selection must use a deterministic saved stream")

-- Waiting total and event/RNG sequence must not depend on how often the caller
-- drives advance(), including differently staggered stations and source feedback.
local function stagger()
  local s=world()
  local later=station(s,9)
  R.advance(s,99)
  local earlier=station(s,1)
  enqueue(s,later,200,earlier.id)
  enqueue(s,earlier,600,later.id)
  for _,st in pairs(s.stations) do
    local g=st.passenger_rating_state
    g.rating=40;g.time_since_pickup=20
  end
  return s
end
local full,sliced=stagger(),stagger()
R.advance(full,1480)
for _=1,20 do R.advance(sliced,74) end
assert(sliced.passenger_rating_rng[1]==full.passenger_rating_rng[1])
assert(sliced.passenger_rating_rng[2]==full.passenger_rating_rng[2])
for id,st in pairs(full.stations) do
  local src=sliced.stations[id]
  assert(Packets.waiting(st)==Packets.waiting(src))
  assert(st.passenger_rating_phase==src.passenger_rating_phase)
  for k,v in pairs(st.passenger_rating_state) do assert(src.passenger_rating_state[k]==v) end
end

-- Version-1 saves preserve both previously eligible and transfer-only stops.
s=world()
s.day=40
a=station(s,1);b=station(s,2)
a.passenger_service_day=18;a.last_service.passenger=32
Packets.enqueue(a,{units=50})
Packets.enqueue(b,{units=30,origin_station=1})
assert(R.offer(s,a)==175 and a.passenger_rating_state.time_since_pickup==3)
assert(R.offer(s,b)==nil and b.passenger_rating_state.time_since_pickup==0)
assert(Packets.waiting(a)==50 and Packets.waiting(b)==30)
print("PASS: stock station rating runtime: phased ticks, loading/transfer distinction, selective expiry, actual packet loss, source feedback, deterministic RNG and legacy migration")
