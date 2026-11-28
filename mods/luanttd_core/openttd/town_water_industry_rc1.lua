-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 table/build_industry.h,
-- table/cargo_const.h and industry_cmd.cpp CheckNewIndustry_Water,
-- CheckIfIndustryTilesAreFree and CheckIfFarEnoughFromConflictingIndustry.
local M={}
M.cargo={key="water",label="WATR",effect=4,weight_sixteenths=16,
  capacity_multiplier=256,base_payment=4664,transit_period_1=20,transit_period_2=80}
M.supply={id=21,layout={{0,0,118},{0,1,119},{1,0,118},{1,1,119}},
  construction_factor=37,rate=12,cargo="water",conflict=22}
M.tower={id=22,layout={{0,0,120}},construction_factor=208,accepts="water",
  acceptance_eighths=8,conflict=21,only_in_town=true}
M.specs={[21]=M.supply,[22]=M.tower}
-- Source MR #165..167 and ROV #49..51. Do not expose in a depot
-- before the checked route, industry assets and Tropic campaign mount.
M.road_tankers={
  {stock_id=165,road_model=49,name="Uhl Water Tanker",vehicle_type=1,climates=4,
    intro_after_1920=5479,decay_speed=20,life=15,base_life=55,cargo="water",
    image=14,purchase_factor=111,running_factor=90,speed=96,capacity=21,weight_quarters=38,power_tens_hp=12},
  {stock_id=166,road_model=50,name="Balogh Water Tanker",vehicle_type=1,climates=4,
    intro_after_1920=20970,decay_speed=20,life=15,base_life=55,cargo="water",
    image=31,purchase_factor=141,running_factor=168,speed=176,capacity=25,weight_quarters=48,power_tens_hp=22},
  {stock_id=167,road_model=51,name="MPS Water Tanker",vehicle_type=1,climates=4,
    intro_after_1920=33388,decay_speed=20,life=15,base_life=85,cargo="water",
    image=48,purchase_factor=151,running_factor=240,speed=224,capacity=27,weight_quarters=69,power_tens_hp=45},
}

function M.anchor(zone)
  if zone~=1 then return false,"CAN_ONLY_BE_BUILT_IN_DESERT" end
  return true
end

function M.conflict(spec,x,z,others)
  for _,o in ipairs(others) do
    if o.type==spec.conflict and math.max(math.abs(o.x-x),math.abs(o.z-z))<=14 then
      return true
    end
  end
  return false
end

-- Call after raw map validity and before the independent slope/platform
-- checks. The host supplies the real house/automatic-landscape clear
-- quote; it does not remove a tree or house during this check. The
-- on_water field combines stock HasTileWaterClass and IsTileOnWater.
function M.surface(spec,tile,clear)
  if not tile or not tile.valid then return false,"SITE_UNSUITABLE" end
  if tile.vehicle then return false,"VEHICLE_IN_THE_WAY" end
  if tile.bridge_above or tile.on_water then return false,"SITE_UNSUITABLE" end
  if spec.only_in_town then
    -- Stock OnlyInTown refers to a house on this exact tile, not a
    -- town boundary or a minimum of 1,200 inhabitants.
    if not tile.house then return false,"CAN_ONLY_BE_BUILT_IN_TOWNS" end
    return clear("town",false,false,false)
  end
  return clear("company",true,true,true)
end

function M.tile_acceptance(gfx,cargo)
  return gfx==120 and cargo=="water" and M.tower.acceptance_eighths or 0
end

return M
