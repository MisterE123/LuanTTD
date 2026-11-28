-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, RC1 table/build_industry.h, table/cargo_const.h,
-- newgrf.cpp GetActiveCargoLabel and industry_cmd.cpp CheckNewIndustry_Plantation.
local F={}
F.cargo={key="food",label="FOOD",effect=5,weight_sixteenths=16,
  capacity_multiplier=256,base_payment=5688,transit_period_1=0,transit_period_2=30}
F.process={id=13,cost_factor=55,conflicts={19,9,24},minimum_production=5,
  source_input={livestock_fruit={"livestock","fruit"},grain_wheat_maize={"grain","wheat","maize"}},
  multiplier={{256},{256}},produces="food",layout={
    {{0,0,60},{1,0,60},{2,0,60},{0,1,60},{1,1,60},{2,1,60},
     {0,2,61},{1,2,61},{2,2,63},{0,3,62},{1,3,62},{2,3,63}},
    {{0,0,61},{1,0,60},{2,0,61},{3,0,61},{0,1,62},{1,1,63},{2,1,63},{3,1,63},
     {0,2,60},{1,2,60},{2,2,60},{3,2,60},{0,3,62},{1,3,62}},
  }}
F.fruit={id=19,rate=10,cost_factor=86,conflicts={13},cargo="fruit",minimum_production=15}
F.maize={id=24,rate=11,cost_factor=48,conflicts={13},cargo="maize",minimum_production=5}
local stock={
  arctic={livestock=true,wheat=true},
  tropic={fruit=true,maize=true},
}

-- Stock reuses generic cargo labels and chooses the first one present.
local function active(labels,present)
  for _,cargo in ipairs(labels) do if present[cargo] then return cargo end end
end
function F.inputs(climate)
  local present=stock[climate]
  if not present then return end
  local s=F.process
  return active(s.source_input.livestock_fruit,present),active(s.source_input.grain_wheat_maize,present)
end
function F.acceptance_eighths(gfx,cargo,climate)
  if gfx<60 or gfx>63 then return 0 end
  local first,second=F.inputs(climate)
  return cargo and (cargo==first or cargo==second) and 8 or 0
end
function F.plantation_anchor(zone)
  return zone~=1 -- stock rejects actual desert, not a distance to water
end

return F
