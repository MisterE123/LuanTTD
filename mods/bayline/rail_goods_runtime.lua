-- SPDX-License-Identifier: GPL-2.0-only
local base=core and core.get_modpath and core.get_modpath("bayline") or "mods/bayline"
local make=dofile(base.."/rail_industry_runtime.lua")
return function(Sim,Service,RailStation,Roster,debit,credit,asset)
  return make({cargo="goods",name="Rail Goods",block="block_goods",
    enabled=function(s) return asset(s) and Sim.road_timber_active(s) end,
    choose_source="Choose a platform in a working sawmill's catchment.",
    choose_sink="Choose a platform whose town catchment accepts Goods.",
    source_lost="The ordered sawmill has closed or moved out of catchment.",
    sink_lost="The ordered destination no longer accepts Goods in catchment."},Sim,Service,RailStation,Roster,debit,credit)
end
