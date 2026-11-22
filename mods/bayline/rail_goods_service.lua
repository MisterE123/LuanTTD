-- SPDX-License-Identifier: GPL-2.0-only
-- Stock ordinary Goods Van #32 shares the existing Goods producer,
-- catchments and final delivery ledger with the competing truck.
local base=core and core.get_modpath and core.get_modpath("bayline") or "mods/bayline"
local make=dofile(base.."/rail_industry_service.lua")
return function(...)
  return make({tag="GOODS",single_error="SINGLE_STOCK_GOODS_VAN_REQUIRED",
    wagon={stock_id=32,image_index=38,tare=21,capacity=25,cargo="goods",cargo_id=5,length=8,
      load_amount=5,cargo_age_ticks=185,cost_factor=190,railtype=0,base_intro=1827,
      decay_speed=20,vehicle_life=20,model_life=255,climates=7}},...)
end
