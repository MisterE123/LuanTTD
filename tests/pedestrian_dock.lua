local D=dofile("mods/luanttd_core/pedestrian_dock.lua")
local function close(a,b) return a and math.abs(a-b)<.001 end
local function world(d,a,c)
  if d==0 then return a,c elseif d==1 then return c,a
  elseif d==2 then return 1-a,1-c else return 1-c,1-a end
end
local function height(part,d,a,c)
  local x,z=world(d,a,c)
  return D.surface(part,d,x,z)
end
for d=0,3 do
  assert(#D.boxes(false,d)==40 and #D.boxes(true,d)==5)
  for _,box in ipairs(D.boxes(false,d)) do
    assert(box[1]<box[4] and box[2]<box[5] and box[3]<box[6])
  end
  assert(close(height(true,d,-.499,.5),-.32))
  assert(close(height(true,d,1.413,.5),-.32))
  assert(not height(true,d,1.42,.5))
  assert(not height(true,d,.9,.99))
  local at_shore=height(false,d,-.499,.5)
  assert(at_shore>.41 and at_shore<.50)
  local last=at_shore
  for i=1,19 do
    local at=height(false,d,-.499+i*.1,.5)
    assert(at<=last and last-at<.10)
    last=at
  end
  assert(math.abs(last-height(true,d,-.499,.5))<.09)
  assert(height(false,d,.5,.95)<height(false,d,.5,.5))
end
print("PASS all four rotated dock gangways join a bounded pier deck with no barrier at the boarding end")

local P=dofile("mods/luanttd_core/pedestrian.lua")
local cell={terrain="water",ship={kind="dock",water_part=true,dir=0}}
local function surface(_,x,z,near)
  local y=D.surface(true,0,x-2,z-2)
  if y and (not near or math.abs(1+y-near)<=.23) then return 1+y end
end
local walk=P.new({
  s={tiles={[1]=cell}},
  Sim={id=function() return 1 end,xy=function() return 1,1 end},
  render={walk_dock_surface=surface,walk_waterline=function() return .5 end},
})
local selected,wet=walk.at(1,{x=2.5,y=.68,z=2.5})
assert(close(selected.y,.725) and wet==nil)
local side,water=walk.at(1,{x=2.5,y=.5,z=2.99})
assert(close(side.y,.32) and water==.5)
local pos={x=2.5,y=.68,z=2.5}
local gravity
local p={
  get_pos=function()return pos end,
  get_velocity=function()return {x=0,y=0,z=0} end,
  set_physics_override=function(_,v)gravity=v.gravity end,
  add_velocity=function()end,
}
local state={}
walk.step(p,state,{})
assert(gravity==1 and state.last_safe==pos and not state.swimming)
pos={x=2.5,y=.49,z=2.99}
walk.step(p,state,{})
assert(gravity==0 and state.swimming and state.last_safe==pos)
print("PASS Walk lands on the deck and switches to swimming beside it without snapping back")
