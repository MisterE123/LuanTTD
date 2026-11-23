local dir="mods/luanttd_core"
local H=dofile(dir.."/openttd/town_passengers.lua")
local Broker=dofile(dir.."/campaign_landscape_async.lua")
local function same(x,y,head,first)
  local a,b,c=H.new_clock(x,y,head,first),H.new_clock(x,y,head,first),H.new_clock(x,y,head,first)
  local tape=H.tape(c,H.day_ticks)
  local next_visit=H.tape_reader(b,H.day_ticks,tape,c.head)
  for tick=first+1,first+H.day_ticks do
    local ids={}
    H.advance(a,1,function(id,t)
      assert(t==tick)
      ids[#ids+1]=id
    end)
    local n=0
    local pre
    next_visit(b,1,function(id,t)
      n=n+1
      assert(pre==t and t==tick and id==ids[n])
    end,function(t) pre=t;assert(b.counter==t-1) end)
    assert(n==#ids and a.counter==b.counter and a.head==b.head)
  end
  assert(not pcall(next_visit,b,1,function()end),"accidentally consumed the same tape twice")
end
same(6,6,42,255)
same(9,9,262143,183)
same(12,6,42,184)
same(6,12,15000,248)

local pending
local now,warnings=0,{}
core={get_modpath=function() return dir end,get_current_modname=function() return "luanttd_core" end}
core.register_async_dofile=dofile
core.get_us_time=function() return now end
core.log=function(_,warning) warnings[#warnings+1]=warning end
core.handle_async=function(job,done,...)
  assert(not pending,"dispatched a second unresolved worker request")
  local args={...}
  pending=function() pending=nil;done(job(unpack(args))) end
  return true
end
local q=Broker.new(core,dir)
local s={day=1,passenger_house_clock=H.new_clock(6,6,1,H.day_ticks)}
q.prepare(s)
assert(not q.take(s))
s.day=2
s.passenger_house_clock.head=5
pending()
assert(not q.take(s),"consumed stale result after state changed during dispatch")
pending()
local ready,apply=q.take(s)
assert(ready and type(apply)=="function")
apply(s.passenger_house_clock,H.day_ticks,function()end)
assert(s.passenger_house_clock.counter==2*H.day_ticks)
assert(not q.take(s),"latest tape could be consumed twice")
local last=pending
q.close()
last()
assert(not q.take(s),"late result escaped shutdown")
local healthy=core.handle_async
local delayed=Broker.new(core,dir)
delayed.prepare(s)
assert(not delayed.take(s))
now=5000000
assert(delayed.take(s)==true and #warnings==1)
pending()
assert(delayed.take(s)==true and s.passenger_house_clock.counter==2*H.day_ticks and #warnings==1)
core.handle_async=function() return false end
local rejected=Broker.new(core,dir)
assert(rejected.take(s)==true and #warnings==2)
core.handle_async=function(_,cb) cb("damaged",1,0);return true end
local invalid=Broker.new(core,dir)
assert(invalid.take(s)==true and #warnings==3)
core.handle_async=healthy
print("PASS: exact visit order, zero tile, once-only use, stale results, and simulation fallback")
