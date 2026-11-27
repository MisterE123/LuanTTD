local Tick=dofile("mods/luanttd_core/campaign_tick_step.lua")

local function setup(fraction)
  local now,accounted=0,0
  local world={speed=1,day=10,campaign_day_fraction=fraction,passenger_house_clock={counter=0916}}
  local clock=Tick.new(world,.74,{
    now=function() return now end,
    budget=12000,
    advance=function(boundary)
      world.day=world.day+1
      for _=1,74 do
        now=now+7000
        world.passenger_house_clock.counter=world.passenger_house_clock.counter+1
        boundary(world.passenger_house_clock.counter)
      end
      accounted=accounted+1
    end,
  })
  return world,clock,function() return accounted end
end

local s,c,settled=setup()
assert(c.poll_ms()==10 and not c.partial() and c.completed_tick()==916)
assert(c.step(.004)>0 and c.completed_tick()==916)
assert(c.step(.006)==1/74 and c.partial() and c.completed_tick()==917)
assert(settled()==0 and s.day==11)
local f,n,late=c.step(.10)
assert(f==3/74 and n==0 and late and settled()==0,"Slice budget must return to the mailbox")
assert(c.poll_ms()==0,"A due stock tick should not sleep before checking its mailbox")
assert(c.flush() and not c.partial() and c.completed_tick()==990 and settled()==1)
assert(not c.flush() and s.campaign_day_fraction==0,"Only complete days can checkpoint")
-- Early flush charged the future ticks. It must not advance another
-- day early, and changing the game speed can't throw away that debt.
assert(c.step(.40)==1 and c.completed_tick()==990)
s.speed=0
assert(c.poll_ms()==35 and c.step(2)==1 and c.completed_tick()==990)
s.speed=2
assert(c.step(.121)==1/74 and c.completed_tick()==991)
assert(c.flush() and c.completed_tick()==1064 and settled()==2)

s,c,settled=setup(.5)
assert(c.poll_ms()==0,"A due stock tick should not sleep before checking its mailbox")
local trace={}
local done=0
while done==0 do
  local _,n=c.step(.02)
  done=done+n
  trace[#trace+1]=c.completed_tick()
end
assert(#trace>=37 and not c.partial() and c.completed_tick()==990 and settled()==1)
for i=2,#trace do assert(trace[i]>trace[i-1],"Clock cannot rewind") end
assert(s.campaign_day_fraction>0 and s.campaign_day_fraction<1)

print("PASS paced source ticks, bounded slices, pause, early settlement debt and monotonic checkpoint state")
