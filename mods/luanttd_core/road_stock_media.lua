-- Host only checks the files; worker receives the compact readiness map.
local M={}
M.models={
  foster_mk2_bus="stock_foster_mk2_bus",
  iron_mps="stock_mps_iron_ore_truck",iron_uhl="stock_uhl_iron_ore_truck",iron_chippy="stock_chippy_iron_ore_truck",
  steel_balogh="stock_balogh_steel_truck",steel_uhl="stock_uhl_steel_truck",steel_kelling="stock_kelling_steel_truck",
  valuables_balogh="stock_balogh_armoured_truck",valuables_uhl="stock_uhl_armoured_truck",valuables_foster="stock_foster_armoured_truck",
  coal_uhl="stock_uhl_coal_truck",coal_dw="stock_dw_coal_truck",
  oil_foster="stock_foster_oil_tanker",oil_perry="stock_perry_oil_tanker",
  goods_goss="stock_goss_goods_truck",
  mail_mps="stock_mps_mail_truck",mail_reynard="stock_reynard_mail_truck",mail_perry="stock_perry_mail_truck",
  wood_foster="stock_foster_wood_truck",wood_moreland="stock_moreland_wood_truck",
  grain_thomas="stock_thomas_grain_truck",grain_goss="stock_goss_grain_truck",
  livestock_uhl="stock_uhl_livestock_van",livestock_foster="stock_foster_livestock_van",
}
local minimum={iron_mps=11,iron_uhl=12,iron_chippy=13,steel_balogh=7,steel_uhl=9,steel_kelling=10,
  coal_tipper=1,coal_uhl=12,coal_dw=14,wood_truck=10,wood_foster=11,wood_moreland=12,grain_truck=10,grain_thomas=12,grain_goss=15}
function M.scan(files)
  local ready={}
  for engine,name in pairs(M.models) do
    local stem="bl_"..name
    if files[stem..".obj"] and files[stem.."_atlas.png"] and
        (not minimum[engine] or files[stem.."_loaded.obj"]) then ready[engine]=true end
  end
  return ready
end
function M.payload(engine,model,amount)
  if model and minimum[engine] then
    return "bl_"..model..((amount or 0)>=minimum[engine] and "_loaded" or "")..".obj"
  end
end
return M
