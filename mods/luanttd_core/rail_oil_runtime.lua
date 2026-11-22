-- SPDX-License-Identifier: GPL-2.0-only
local base=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local make=dofile(base.."/rail_industry_runtime.lua")
return function(Sim,...)
  return make({cargo="oil",name="Rail Oil",enabled=function(s) return Sim.road_oil_active(s) end,block="block_oil",
    choose_source="Choose a platform in a real oil well's catchment.",
    choose_sink="Choose a platform that accepts crude oil at a real refinery.",
    source_lost="The ordered oil well has closed or moved out of catchment.",
    sink_lost="The ordered refinery no longer accepts crude oil in catchment."},Sim,...)
end
