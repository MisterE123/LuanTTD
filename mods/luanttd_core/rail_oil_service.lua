-- SPDX-License-Identifier: GPL-2.0-only
-- Original standard rail Oil Tanker profile; preserve its save layout and
-- absolute clock through the shared single-wagon industry service.
local base=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local make=dofile(base.."/rail_industry_service.lua")
return function(...)
  return make({tag="OIL",single_error="SINGLE_STOCK_OIL_TANKER_REQUIRED",
    wagon={stock_id=30,image_index=36,tare=24,capacity=30,cargo="oil",length=8,
      load_amount=5,cargo_age_ticks=185,cost_factor=200,railtype=0,base_intro=1827,
      decay_speed=20,vehicle_life=20,model_life=255,climates=7}},...)
end
