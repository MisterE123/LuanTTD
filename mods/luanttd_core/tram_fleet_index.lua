-- One read contract for the visual pilot and paid road-compatible trams.
-- The free test car has no company fleet serial. Its traffic identity
-- sorts after the saved RoadVehicle serials without requiring a fake bus.
local M={test_serial=9007199254740991}
function M.serial(run) return run.carrier and run.carrier.id or M.test_serial end
function M.each(s,fn)
  if s.tram_pilot and fn(s.tram_pilot) then return true end
  for _,run in pairs(s.stock_tram_fleet or {}) do if fn(run) then return true end end
  return false
end
function M.get(s,serial)
  local run=s.stock_tram_fleet and s.stock_tram_fleet[serial]
  if run then return run end
  local primary=s.tram_pilot
  if primary and (not serial or M.serial(primary)==serial) then return primary end
end
function M.sorted(s)
  local out={}
  M.each(s,function(run) out[#out+1]=run end)
  table.sort(out,function(a,b) return M.serial(a)<M.serial(b) end)
  return out
end
function M.frame(run)
  if run.phase=="depot" then return end
  local leg=run.legs and run.legs[run.leg]
  return leg and leg.frames and leg.frames[run.index]
end
function M.uses(s,id)
  return M.each(s,function(run)
    for _,leg in ipairs(run.legs or {}) do
      for _,tile in ipairs(leg.path or {}) do if tile==id then return true end end
    end
  end)
end
return M
