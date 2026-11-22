local F=dofile("tests/road_overtake_fixture.lua")("mods/bayline/")
local function copy(value)
  if type(value)~="table" then return value end
  local out={}
  for k,v in pairs(value) do out[k]=copy(v) end
  return out
end
for _,kind in ipairs{"stopped","moving"} do
  local saved=copy(F.checkpoint(kind))
  assert(not F.Sim.road_motion_timeline(saved.s,saved.follow))
  F.resume(saved)
end
local s,a,b=F.setup("opposing")
for _=1,2 do
  F.Sim.daily(s)
  assert(not F.sample(s,a,b))
end
local c=s.fleet[b].road_speed_state
assert(not c.overtakes and c.waiting=="road" and F.Sim.road_motion_frame(s,s.fleet[b])[1]<178)
-- A planned straight route can survive a new side branch. The source
-- O.check still only scans its first two tiles; the live straight-window
-- adapter additionally declines a pass that would need the changed junction.
local changed,lead,follow=F.setup("moving")
local branch=F.Sim.id(12,12)
changed.tiles[branch].road_bits=changed.tiles[branch].road_bits+1
F.Sim.daily(changed)
assert(not F.sample(changed,lead,follow))
assert(not changed.fleet[follow].road_speed_state.overtakes)
print("PASS live stock road clock: stopped and moving overtakes resume from saved pose; oncoming tile queues")
