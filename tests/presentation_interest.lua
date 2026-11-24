local module=dofile("mods/luanttd_core/presentation_interest.lua")
local interest=module.new()
local x,z=31,21
local p={get_pos=function()return {x=x,y=5,z=z} end}
interest.refresh({p,p}) -- two players with overlapping subscriptions
assert(interest.near({x=126,z=21},false))
assert(not interest.near({x=132,z=21},false))
assert(interest.near({x=132,z=21},true))
assert(not interest.near({x=144,z=21},true))
local seen={}
local Sim={W=4096,H=4096,id=function(x_,z_)
  assert(x_>=1 and x_<=4096 and z_>=1 and z_<=4096)
  local id=(z_-1)*4096+x_;assert(not seen[id]);seen[id]=true;return id
end}
local n=0;interest.each_tile(Sim,96,function()n=n+1 end)
assert(n>3000 and n<20000 and seen[1])
x,z=7902,8102;interest.refresh({p})
assert(not interest.near({x=40,z=30},true))
assert(interest.sectors(96)["124:126"])
interest.refresh({})
assert(not interest.near({x=x,z=z},true) and not next(interest.sectors(96)))

-- Run the actual tram renderer; replacing or removing an ObjectRef
-- must never reset or replace the motion actor.
local time,refs=0,{}
core={add_entity=function(pos,name)
  assert(name:find("tram"))
  local r={position=pos}
  function r:get_pos() return self.position end
  function r:move_to(v) self.position=v end
  function r:set_rotation() end
  function r:remove() self.position=nil end
  refs[#refs+1]=r;return r
end}
local actor={}
local Run={current=function() return actor end,
  advance=function(_,ticks) time=time+ticks end,
  frame=function(a) assert(a==actor);return {time,0,0,42} end}
local Pose={at=function(frames) return frames[1][1],frames[1][2],0 end}
local Visual={nose_yaw=function()return 0 end,turn=function()return 0 end}
local state={speed=1}
local V=dofile("mods/luanttd_core/tram_preview_view.lua")({
  interest=interest,s=state,Sim={id=function()return 42 end},
  terrain={tile=function() return 0,1 end}},Run,Pose,Visual)
local clock=dofile("mods/luanttd_core/aux_transport_clock.lua")(state,74,Run.current,
  function(n) Run.advance(state,n) end)
local function step(dt,online) clock(dt); V.step(dt,online) end
x,z=1000,1000;interest.refresh({p})
step(10,true);assert(time==10 and #refs==0)
x,z=10,0;interest.refresh({p});step(1,true)
assert(#refs==1 and refs[1]:get_pos().x==11)
x,z=1000,1000;interest.refresh({p});step(10,true)
assert(time==21 and #refs==1 and not refs[1]:get_pos())
x,z=21,0;interest.refresh({p});step(2,true)
assert(time==23 and #refs==2 and refs[2]:get_pos().x==23)
step(2,false);assert(time==25 and not refs[2]:get_pos() and Run.current()==actor)
state.speed=0;step(3,false);assert(time==25)
print("PASS bounded overlapping subscriptions and actual tram spawn/despawn without stopping off-camera motion")
