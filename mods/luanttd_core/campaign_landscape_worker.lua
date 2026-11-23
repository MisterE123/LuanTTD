-- Loaded independently in each Luanti async VM.
local mod=assert(core.get_modpath(core.get_current_modname() or "luanttd_core"))
local H=dofile(mod.."/openttd/town_passengers.lua")
function core.luanttd_landscape_day(log_x,log_y,head,counter)
  assert(log_x+log_y<=24,"Landscape exceeds OpenTTD stock dimensions")
  local clock=H.new_clock(log_x,log_y,head,counter)
  return H.tape(clock,H.day_ticks),clock.head,clock.counter
end
