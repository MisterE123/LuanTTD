local B=dofile("mods/luanttd_core/campaign_actor_buffer.lua")()
local function pos(x) return {x=x,y=1,z=1} end
local function car(x,yaw) return {mode="road",engine="bus",pos=pos(x),yaw=yaw} end
local t=1000000
B.observe({x=car(0,math.pi-.1)},t)
B.observe({x=car(1,-math.pi+.1)},t+100000)
B.observe({x=car(2,-math.pi+.2)},t+200000)
local a=B.sample(t+221000).x
local b=B.sample(t+241000).x
assert(a.pos.x>0 and b.pos.x<1 and b.pos.x>a.pos.x,"samples must advance between receipts")
assert(math.abs(math.abs(a.yaw)-math.pi)<.05,"heading must take the short path across Pi")
assert(B.sample(t+400000).x.pos.x==2 and B.sample(t+900000).x.pos.x==2,"never extrapolate")
B.observe({},t+200000)
assert(not next(B.sample(t+940000)),"culling cannot resurrect an actor from presentation history")
B.observe({x=car(12,0)},t+1100000)
assert(B.sample(t+1100000).x.pos.x==12,"long pause must start from the first live pose")
print("PASS time-buffered poses move between worker replies, cross the angle wrap, hold on starvation and cull immediately")
local Q=dofile("mods/luanttd_core/campaign_actor_buffer.lua")()
local function rail(x,flip)
  return {mode="rail",engine="steam",parts={
    {body_index=1,index=1,kind="steam",pos=pos(x),rotation={x=0,y=0,z=0},flip=flip},
    {body_index=2,index=2,kind="wagon",pos=pos(x-1),rotation={x=0,y=0,z=0},flip=flip},
  }}
end
Q.observe({r=rail(0,false)},t)
Q.observe({r=rail(1,false)},t+100000)
Q.observe({r=rail(2,true)},t+200000)
local k=Q.sample(t+224000).r.parts
assert(k[1].pos.x>0 and k[1].pos.x<1 and k[1].pos.x-k[2].pos.x==1)
local k=Q.sample(t+315000).r.parts
assert(k[1].pos.x==1 and k[2].pos.x==0 and not k[1].flip)
local k=Q.sample(t+410000).r.parts
assert(k[1].pos.x==2 and k[2].pos.x==1 and k[1].flip)
print("PASS articulated bodies advance and reverse on a shared playout frame")
