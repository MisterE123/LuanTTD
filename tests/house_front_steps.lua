local m="mods/luanttd_core/"
local M=dofile(m.."house_front_steps.lua")
local F=dofile(m.."house_frontage.lua")
local S=dofile(m.."sim.lua")
local plan=M.make(F)
local id=S.id(10,10)
for d=1,4 do
  local road=S.adjacent(id,d)
  local foot=d%2==1 and 4 or 1
  local a=S.adjacent(road,foot)
  local b=S.adjacent(road,(foot+1)%4+1)
  local t={house=true,h=3,source_house={id=3,completed=true}}
  local s={tiles={[id]=t,[road]={build="road",h=2,road_bits=d%2==1 and 10 or 5}}}
  assert(plan(S,s,id,t,3)==d)
  s.tiles[a]={build="road_station"}
  assert(plan(S,s,id,t,3)==d+4)
  s.tiles[b]={build="road_station"}
  assert(not plan(S,s,id,t,3))
  s.tiles[a],s.tiles[b]=nil,nil
  assert(plan(S,s,id,t,3)==d)
  assert(not plan(S,s,id,t,2) and not plan(S,s,id,t,4))
  s.tiles[road].road_bits=15
  assert(not plan(S,s,id,t,3))
  s.tiles[road].road_bits=d%2==1 and 10 or 5
  s.bridge_above={[road]=4}
  assert(not plan(S,s,id,t,3))
  s.bridge_above=nil
  s.tiles[road].build="road_station"
  assert(not plan(S,s,id,t,3))
  for _,key in ipairs({d,d+4}) do
    local boxes=M.boxes(key)
    local dx,dz=M.anchor(d)
    local x,z=F.placement(S,s,id,t,nil,nil,d)
    assert(dx~=x or dz~=z)
    for i,bx in ipairs(boxes) do
      assert(math.abs(bx[5]-(i/7-1.5))<1e-9 and bx[2]==-1.5)
      assert(math.abs((d%2==1 and bx[6]-bx[3] or bx[4]-bx[1])-.317)<1e-9)
    end
  end
end
print("PASS four curb orientations, two hands, same-tile/adjacent stop protection, exact lane-safe collision treads")

-- A stop two tiles outside a one-tile viewport still changes the house
-- receipt; clients never guess a shared-view staircase from partial data.
local Grid=dofile(m.."openttd/terrain.lua")
local world=S.new(1751)
world.fleet={}
world.corner_grid=Grid.new(S.W,S.H,function(x,z)
  return (x==10 or x==11) and z==10 and 3 or 2
end)
local road=S.id(10,11)
local foot=S.id(9,11)
world.tiles[id]={house=true,h=2,source_house={id=3,completed=true},terrain="grass",variant=0}
world.tiles[road]={build="road",road_bits=10,h=2,terrain="grass",variant=0}
world.tiles[foot]={build="road",road_bits=10,h=2,terrain="grass",variant=0}
local A=dofile(m.."campaign_authority_endpoint.lua")(S,{world=world,terrain=Grid,
  terrain_projection=dofile(m.."campaign_terrain_projection.lua")})
local function snapshot(known)
  local r=A.snapshots({{x=10,z=10,w=1,h=1,scene=known}})
  assert(r.ok)
  return r.value[1]
end
local original=snapshot()
assert(original.tiles[1].front_steps==3)
assert(not snapshot(original.scene).tiles)
world.tiles[foot].station=9
local changed=snapshot(original.scene)
assert(changed.scene~=original.scene and changed.tiles[1].front_steps==7)
world.tiles[foot].station=nil
local restored=snapshot(changed.scene)
assert(restored.tiles[1].front_steps==3)
print("PASS worker repaints a one-tile house sector when an adjacent stop outside it affects the approach")
