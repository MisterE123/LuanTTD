-- Derive the native sun from the owner's date; the viewport, platform
-- focus and the client's frame clock cannot move the campaign calendar.
local M={sample_interval=.2}
local clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
function M.new(Sim,s,interval)
  local year,year_start,year_days
  return function(now,fraction)
    local elapsed=s.day
    local stock=s.stock_bus_market
    local day=stock and stock.epoch+elapsed or elapsed
    if not year_start or day<year_start or day>=year_start+year_days then
      year=Sim.date(s)
      if stock then
        local C=Sim.engine_calendar
        year_start=assert(C.date(year,1,1))
        year_days=(C.date(year+1,1,1) or C.MAX_DATE+1)-year_start
      else
        year_days=360
        year_start=(year-1950)*year_days
      end
    end
    return {day=elapsed,year=year,year_day=day-year_start,year_days=year_days,
      fraction=clamp(fraction or s.campaign_day_fraction or 0,0,1),rate=(s.speed or 0)/interval,us=now}
  end
end
function M.phase(sample,now)
  -- Extrapolate only within the confirmed calendar day and within one
  -- publication interval. No free-running sky on a stalled/disconnected VM.
  local age=clamp((now-sample.us)/1000000,0,M.sample_interval)
  local time=clamp(sample.fraction+age*sample.rate,0,1)
  return (.5+(sample.year_day+time)/sample.year_days)%1
end
return M
