local M=dofile("mods/luanttd_core/campaign_step.lua")
local world={day=0,speed=1}
local seen,captures,effects={},0,0
local hooks={advance=function(s)
  s.day=s.day+1
  s.changed={6,3,10,s.day%3+1}
end,refresh=function(ids)
  local a={}
  for i,v in ipairs(ids) do a[i]=v end
  seen[#seen+1]=table.concat(a,",")
end,capture=function() captures=captures+1 end,discard_effects=function() effects=effects+1 end}
local run=M.new(world,1,hooks)
local f,n=run.step(100,false,false)
assert(n==0 and f==1 and world.day==0 and #seen==0)
f,n=run.step(.5,false,true)
assert(n==0 and f==.5)
f,n=run.step(3,false,true)
assert(n==3 and f==.5 and world.day==3 and #seen==0 and captures==0 and effects==3)
assert(world.offscreen_terrain_dirty[1] and world.offscreen_terrain_dirty[2] and world.offscreen_terrain_dirty[3])
-- An engine process can restart while nothing behind the latest visual
-- unacknowledged tile state has been updated. The dirty set travels with it.
run=M.new(world,1,hooks)
f,n=run.step(.75,true,false)
assert(n==0 and f==.75 and seen[1]=="1,2,3,6,10" and not world.offscreen_terrain_dirty)
f,n=run.step(.25,true,false)
assert(n==1 and f==0 and world.day==4 and captures==1 and effects==3 and seen[2]=="6,3,10,2")
world.speed=0
f,n=run.step(60,false,true)
assert(n==0 and f==1 and world.day==4)
world.speed=4
f,n=run.step(600,false,true)
assert(n==12 and world.day==16 and captures==1 and effects==15)
print("PASS: exact one campaign clock, opt-in headless ticks, bounded serializable dirty IDs, fresh view flush and paused-time discard")
