-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 stock Temperate industry rows. Use the existing
-- translated fixed-slot OnTick_Industry, IndustryTileLoop, receipt and
-- TriggerIndustryProduction clock; never run a parallel simulated Factory.
return function(F,Data)
  local old=F.tile_acceptance
  for name,row in pairs(Data.spec) do F.spec[name]=row end
  for name,row in pairs(Data.layout) do F.layout[name]=row end
  for name,row in pairs(Data.cargo) do F.cargo[name]=row end
  local rows=dofile((core and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/road_farm_fleet_data.lua")
  F.trucks.iron_ore={id=rows.iron_mps.stock_id,speed=rows.iron_mps.speed,load_amount=5,age_ticks=185}
  function F.tile_acceptance(gfx,cargo)
    if gfx>=52 and gfx<=57 then
      if cargo=="iron_ore" then return 8 end
      if cargo=="passenger" then return 1 end
      return 0
    end
    return old(gfx,cargo)
  end
  return F
end
