-- Keep live pilot motion independent of visibility and ObjectRefs.
-- Paid road/rail/water/air instead advance inside the shared Sim daily clock.
return function(s,seconds_per_day,active,advance)
  assert(seconds_per_day>0)
  local accumulated=0
  return function(dt)
    if not active() then accumulated=0;return end
    if s.speed<=0 then return end
    accumulated=math.min(148,accumulated+dt*74*s.speed/seconds_per_day)
    local ticks=math.floor(accumulated)
    if ticks>0 then
      advance(ticks)
      accumulated=accumulated-ticks
    end
  end
end
