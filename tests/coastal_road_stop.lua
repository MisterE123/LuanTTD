local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local H=dofile(root.."openttd/town_passengers.lua")
local s=S.new(1751)
dofile(root.."town_layout.lua")(S,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
local F=dofile("tests/coastal_road_stop_fixture.lua")(S,T,H,dofile(root.."campaign_road_construction.lua"))
local proof=F.start(s)
local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}
  if seen[value] then return seen[value] end
  local out={};seen[value]=out
  for k,v in pairs(value) do out[k]=copy(v,seen) end
  return out
end
assert(F.finish(copy(s),proof))
print("PASS: a real paid bus loses reserved passengers at a flooded through-stop, then retires before coastal clearance")
