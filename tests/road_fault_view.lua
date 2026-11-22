-- Effects are viewer-local, throttled, and never imply a stopped order.
local seen={}
local V=dofile("mods/luanttd_core/road_fault_view.lua")(function(p)seen[#seen+1]=p end)
local function player(name,x)
  return {get_pos=function()return {x=x,y=1,z=2} end,get_player_name=function()return name end}
end
local viewers={player("near",2),player("far",200)}
local f,pos={breakdown_ctr=2,breakdown_delay=194},{x=1,y=.52,z=2}
assert(V.draw(1,f,pos,0,viewers,false)==0)
f.breakdown_ctr=1
assert(V.draw(1,f,pos,0,viewers,true)==0)
assert(V.draw(1,f,pos,0,viewers,false)==1 and #seen==1 and seen[1].playername=="near")
assert(seen[1].pos.y>.70 and seen[1].pos.z>pos.z)
assert(seen[1].texture.alpha_tween[2]==0)
V.step(.217)
assert(V.draw(1,f,pos,0,viewers,false)==0)
V.step(.005)
assert(V.draw(1,f,pos,0,viewers,false)==1)
f.breakdown_ctr=0
assert(V.draw(1,f,pos,0,viewers,false)==0 and not V.due[1])
V.remove(1)
print("PASS: actual faults only, one short visible step, no distant/paused particles and prompt release")
