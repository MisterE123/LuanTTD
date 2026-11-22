-- The real stock Sim clock, saved leg, route compiler and physical timeline.
local F=dofile("tests/road_oneway_live_fixture.lua")("mods/luanttd_core/",dofile("tests/road_overtake_fixture.lua"))
local Sim,World,owner,id,target,fixture,held,reached,setup_sign=
  F.Sim,F.World,F.owner,F.id,F.target,F.fixture,F.held,F.reached,F.setup_sign
local function cl(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=cl(v) end
  return out
end

local s,car,dest=fixture()
setup_sign(s)
-- Newly dispatched paths are directed too. No valid return from the
-- western stop can travel east past this entire signed single corridor.
local red=s.stations[s.tiles[id(7,12)].station]
local blue=s.stations[s.tiles[id(20,12)].station]
assert(not Sim.path(s,red,blue,"road",owner,nil,s.fleet[car]))
local okay,msg=Sim.build(s,owner,"road",{target,id(12,13)})
assert(not okay and msg:find("cannot have junctions",1,true))
assert(s.tiles[target].road_bits==10 and s.tiles[target].road_disallowed==2)
local index,x=held(s,car)

-- Deserialize into a new state identity without a weak Sim.mount entry:
-- persisted restrictions must still apply when the construction UI is off.
local copy=cl(s)
assert(Sim.road_motion_timeline(copy,car)==nil)
for _=1,2 do Sim.daily(copy) end
assert(copy.fleet[car].road_speed_state.index==index and Sim.road_motion_frame(copy,copy.fleet[car])[1]==x)
assert(copy.fleet[car].road_speed_state.waiting=="oneway")
assert(World.build(copy,owner,id(14,12),target,0))
assert(World.read(copy.tiles[target])==0)
for _=1,12 do
  Sim.daily(copy)
  local v=copy.fleet[car]
  if v.last_road_arrival_tick then
    assert(reached(copy,car,dest))
    break
  end
end
assert(copy.fleet[car].last_road_arrival_tick)

-- Ordinary demolition clears sign metadata but cannot cause a vehicle
-- waiting on the former directed leg to drive into bare grass.
local busy,reason=Sim.build(s,owner,"clear",{target})
assert(not busy and reason:find("clear that route",1,true))
local frozen=s.fleet[car]
s.fleet[car]=nil
assert(Sim.build(s,owner,"clear",{target}))
s.fleet[car]=frozen -- saved compiled route deliberately restored for the safety check
assert(not s.tiles[target].build and s.tiles[target].road_disallowed==nil and s.tiles[target].disallowed==nil)
Sim.daily(s)
assert(s.fleet[car].road_speed_state.index==index and s.fleet[car].road_speed_state.oneway_reason=="ONEWAY_ROAD_LAYOUT_CHANGED")
assert(Sim.build(s,owner,"road",{id(11,12),target,id(13,12)}))
assert(not s.road_oneway_removed[target] and not s.tiles[target].road_disallowed)
Sim.daily(s)
assert(s.fleet[car].road_speed_state.index>index)

-- A physical legal bypass is selected before entering the closed part.
-- Recompile from the *current* stock row and preserve the motion seam.
local alternate,alt=fixture()
local branch={id(10,12)}
for xx=10,16 do branch[#branch+1]=id(xx,13) end
branch[#branch+1]=id(16,12)
assert(Sim.build(alternate,owner,"road",branch))
setup_sign(alternate)
local v=alternate.fleet[alt]
local old=Sim.road_motion_frame(alternate,v)
Sim.daily(alternate)
assert(v.road_speed_state and v.road_speed_state.oneway_reroutes==1)
local t=Sim.road_motion_timeline(alternate,alt)
local old_visible=t.frames[t.cursors[1]]
assert(old_visible[1]==old[1] and old_visible[2]==old[2] and old_visible[3]==old[3] and old_visible[4]==old[4])
local used_detour=false
for _,cell in ipairs(v.route) do
  if cell==id(13,13) then used_detour=true end
  assert(cell~=target)
end
assert(used_detour)
for _=1,12 do
  Sim.daily(alternate)
  if v.last_road_arrival_tick then break end
end
assert(v.last_road_arrival_tick and reached(alternate,alt,dest))
print("PASS live one-way roads revalidate saved stock frames, resume, reroute without a pose jump and stop after demolition")
