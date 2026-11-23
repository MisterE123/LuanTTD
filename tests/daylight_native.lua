-- Appended to a disposable copy of the ordinary game, with its actual
-- authority handoff and real engine clock (no scripted native phase).
local port_calendar=Sim.engine_calendar
local function log_stamp(label,sample)
  local phase=core.get_timeofday()
  local expected=solar.phase(sample,sample.us)
  local tolerance=sample.rate==0 and 1/24000 or .025 -- accelerated fixture; host and owner sample asynchronously
  assert(math.abs((phase-expected+.5)%1-.5)<tolerance,"native clock disagrees with authority")
  core.log("action",("DAYLIGHT_WORKER %s year=%d day=%d frac=%.9f native=%.9f rate=%.2f"):format(
    label,sample.year,sample.year_day,sample.fraction,phase,sample.rate))
end
if not resumed_owner then
  assert(port_calendar.date(2000,1,1)==S.stock_bus_market.epoch)
  assert(not next(S.companies))
  -- Begin just before the end of the stock 366-day calendar year.
  S.day=364
  S.campaign_day_fraction=.17
  S.speed=2
end
local player="DaylightQA"
local function sample_when(what,check)
  local deadline=core.get_us_time()+9000000
  local function poll()
    local c=authority.solar_clock()
    if c and check(c) then
      log_stamp(what,c)
      return
    end
    assert(core.get_us_time()<deadline,"timeout at "..what)
    core.after(.075,poll)
  end
  core.after(.25,poll)
end
local function begin()
  if authority.status()~="owned" then core.after(.075,begin);return end
  if resumed_owner then
    sample_when("reopen",function(c)
      assert(c.rate==0 and c.year==2001)
      core.after(.1,function() core.request_shutdown("Calendar reopen verified",false,0) end)
      return true
    end)
    return
  end
  sample_when("after-new-year",function(c)
    if c.year~=2001 then assert(c.year_days==366);return false end
    assert(c.year_days==365 and c.year_day<45)
    assert(authority.query({kind="command",player=player,command={kind="company_open"}},function(company)
      assert(company.ok,company.why)
      assert(authority.query({kind="command",player=player,command={kind="speed",speed=0,revision=company.revision}},function(r)
        assert(r.ok,r.why)
        sample_when("paused",function(paused)
          assert(paused.rate==0)
          local fixed=core.get_timeofday()
          core.after(.7,function()
            local still=assert(authority.solar_clock())
            assert(still.day==paused.day and still.fraction==paused.fraction)
            assert(core.get_timeofday()==fixed and tonumber(core.settings:get("time_speed"))==0)
            log_stamp("held",still)
            core.request_shutdown("Calendar pause verified",false,0)
          end)
          return true
        end)
      end))
    end))
    return true
  end)
end
core.register_on_mods_loaded(begin)
core.register_on_shutdown(function()
  assert(tonumber(core.settings:get("time_speed"))==72,"temporary clock configuration was not restored")
end)
