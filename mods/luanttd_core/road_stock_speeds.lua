-- Stock vehicle speed, used by road YAPF and the motion controller.
local path=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local speed={bus=112,coach=144,leopard_bus=176,foster_bus=224,foster_mk2_bus=255,mail_van=96,
  truck=96,coal_tipper=96,goods_truck=96,craighead_goods_truck=176,oil_tanker=96}
for k,row in pairs(dofile(path.."/openttd/road_farm_fleet_data.lua")) do speed[k]=row.speed end
local freight=dofile(path.."/openttd/road_freight_catalog.lua")
for _,k in ipairs(freight.water_order) do speed[k]=freight.row(k).speed end
return speed
