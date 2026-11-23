-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 src/industry_cmd.cpp CheckIfIndustryIsAllowed,
-- CheckIfIndustryTilesAreSuitable, ChangeIndustryProduction; src/economy.cpp
-- TriggerIndustryProduction; stock Temperate Bank / Valuables table.
return function(F,Data)
  local tile_acceptance=F.tile_acceptance
  F.layout.temperate_bank,F.spec.temperate_bank,F.cargo.valuables=Data.layout,Data.spec,Data.cargo
  F.trucks.valuables={id=153,speed=96,load_amount=5,age_ticks=185}
  function F.tile_acceptance(gfx,cargo)
    if Data.refuses_slopes[gfx] then return Data.tile_acceptance[cargo] or 0 end
    return tile_acceptance(gfx,cargo)
  end
  local R={}
  function R.refuses(current,refused)
    if current>=16 then return true end
    if current==0 then return false end
    local complement=15-current
    local test=function(mask,bit) return math.floor(mask/bit)%2==1 end
    if test(refused,1) and (test(complement,8) or test(complement,1)) then return true end
    if test(refused,2) and (test(complement,8) or test(complement,4)) then return true end
    if test(refused,4) and (test(complement,2) or test(complement,1)) then return true end
    if test(refused,8) and (test(complement,2) or test(complement,4)) then return true end
    return false
  end
  function R.site(town,a,b)
    if not town or town.population<1200 then return nil,"BANK_NEEDS_TOWN_POPULATION_1200" end
    for i,t in ipairs({a or false,b or false}) do
      if not t or t.occupied_by_vehicle or t.bridge or t.water then return nil,"BANK_SITE_NOT_SUITABLE" end
      if not t.house then return nil,"BANK_NEEDS_TWO_HOUSE_TILES" end
      if not t.clearable then return nil,"BANK_TOWN_COULD_NOT_CLEAR_HOUSE" end
      local mask=Data.refuses_slopes[Data.layout[0][i][3]]
      if R.refuses(assert(t.slope),mask) then return nil,"BANK_LAND_SLOPED_WRONG_DIRECTION" end
    end
    return true
  end
  return R
end
