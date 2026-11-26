local mod="mods/luanttd_core"
local F=dofile("tests/road_fleet_perf.lua")(mod)
local codec=dofile(mod.."/packed_campaign.lua")
local s=F.make(2,2)
local function check(world)
  local a,b=world.fleet[1].road_motion_frames,world.fleet[2].road_motion_frames
  local different=world.fleet[3].road_motion_frames
  assert(a~=b and #a==#b and #a>100)
  for i=1,#a do assert(a[i]==b[i],"duplicate read-only frame") end
  assert(a[1]~=different[1],"an unrelated trace must not share a route")
  local old=b[#b]
  -- A vehicle owns its route list and may replace the tail without
  -- changing another vehicle, including after checkpoint rehydration.
  a[#a]={-1,-1}
  assert(b[#b]==old)
  a[#a]=old
  return a,b
end
local a,b=check(s)
local c,d=check(codec.decode(codec.encode(s)))
for i=1,#a do
  for k,v in pairs(a[i]) do assert(c[i][k]==v and d[i][k]==v) end
end
print("PASS independent route lists reference shared stock poses before and after the packed restore")
