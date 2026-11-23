-- Async workers may differ across days. A job receives only the saved
-- stock cursor, never a world, pointer or random generator.
local M={}
local function run(x,y,head,counter)
  return core.luanttd_landscape_day(x,y,head,counter)
end

function M.new(engine,mod)
  engine.register_async_dofile(mod.."/campaign_landscape_worker.lua")
  local H=dofile(mod.."/openttd/town_passengers.lua")
  local slot,closed,disabled
  local Q={}
  local function disable(why)
    disabled=true
    slot=nil
    engine.log("warning","LuanTTD landscape worker: "..why.."; using the exact in-thread clock.")
  end
  local function current(p,s)
    local c=s.passenger_house_clock
    return c and p.x==c.log_x and p.y==c.log_y and p.start==c.counter and p.head==c.head and p.day==s.day
  end
  function Q.prepare(s)
    if closed or disabled or slot then return end
    local c=s.passenger_house_clock
    if not c then return end
    assert(c.log_x+c.log_y<=24,"Landscape exceeds OpenTTD stock dimensions")
    local p={x=c.log_x,y=c.log_y,start=c.counter,head=c.head,day=s.day,submitted=engine.get_us_time()}
    slot=p
    local ok,accepted=pcall(engine.handle_async,run,function(tape,last,finish)
      if closed or slot~=p then return end
      local visits=2^(p.x+p.y-8)*H.day_ticks
      if not (type(tape)=="string" and #tape==3*visits and type(last)=="number" and
        last%1==0 and last>0 and last<2^(p.x+p.y) and finish==p.start+H.day_ticks) then
        disable("invalid result")
        return
      end
      if current(p,s) then p.tape,p.last=tape,last else slot=nil end
    end,p.x,p.y,p.head,p.start)
    if not ok or not accepted then disable("job submission rejected") end
  end
  function Q.take(s)
    if closed then return false end
    local c=s.passenger_house_clock
    if not c or disabled then return true end
    if slot and slot.tape then
      local p=slot
      slot=nil
      if current(p,s) then return true,H.tape_reader(c,H.day_ticks,p.tape,p.last) end
    end
    if slot and engine.get_us_time()-slot.submitted>=5000000 then
      disable("no result within five seconds")
      return true
    end
    Q.prepare(s)
    return disabled==true
  end
  function Q.close()
    closed=true
    slot=nil
  end
  return Q
end
return M
