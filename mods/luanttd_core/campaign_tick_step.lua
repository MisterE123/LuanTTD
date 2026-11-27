-- A generated campaign may expose completed source ticks while its
-- daily accounting/bindings remain a single transaction. Only the owner
-- resumes or finishes it, and only complete days are checkpointed.
local M={}
local ticks_per_day=74
local min,max=math.min,math.max
function M.new(s,interval,hooks)
  assert(interval>0 and hooks.advance and hooks.now)
  local C={}
  local task,first,done
  local credit=max(0,min(1,s.campaign_day_fraction or 0))*ticks_per_day
  local budget=hooks.budget or 12000
  local function start()
    first=assert(s.passenger_house_clock).counter
    done=0
    task=coroutine.create(function()
      hooks.advance(function(tick)
        done=done+1
        assert(tick==first+done and done<=ticks_per_day,"Stock tick order changed")
        -- Finish final accounting on the terminal tick before making
        -- the state available as a command/checkpoint boundary.
        if done<ticks_per_day then coroutine.yield() end
      end)
      assert(done==ticks_per_day,"Campaign advanced without a complete stock day")
    end)
  end
  local function next_tick()
    if not task then start() end
    local ok,why=coroutine.resume(task)
    if not ok then error(debug and debug.traceback and debug.traceback(task,tostring(why)) or why,0) end
    credit=credit-1
    if coroutine.status(task)=="dead" then
      task=nil
      if s.changed then
        if hooks.refresh then hooks.refresh(s.changed) end
        s.changed=nil
      end
      s.campaign_day_fraction=max(0,min(credit/ticks_per_day,1))
      return 1
    end
    return 0
  end
  function C.partial() return task~=nil end
  function C.completed_tick() return s.passenger_house_clock.counter end
  function C.sample()
    if task then return done/ticks_per_day end
    if done then return 1 end
    return s.campaign_day_fraction or 0
  end
  function C.step(dt)
    local speed=s.speed or 0
    if speed<=0 then return C.sample(),0,false end
    credit=min(credit+dt*speed*ticks_per_day/interval,5*ticks_per_day)
    local until_=hooks.now()+budget
    local days=0
    while credit>=1-1e-9 do
      days=days+next_tick()
      -- Return to the actual mailbox between bounded batches. A single
      -- source tick can exceed the budget, so this is not a deadline.
      if days>0 or hooks.now()>=until_ then break end
    end
    if not task then s.campaign_day_fraction=max(0,min(credit/ticks_per_day,1)) end
    return C.sample(),days,credit>=1-1e-9
  end
  function C.flush()
    if not task then return false end
    repeat next_tick() until not task
    return true
  end
  function C.poll_ms()
    local speed=s.speed or 0
    if speed<=0 then return 35 end
    return max(1,min(35,math.ceil(max(0,1-credit)*interval*1000/(speed*ticks_per_day))))
  end
  return C
end
return M
