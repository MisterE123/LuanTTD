-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1: table/engines.h: MR/ROV #116–118, table/pricebase.h,
-- engine.cpp::GetCost, RoadVehicle::{Tick,OnNewEconomyDay},
-- vehicle.cpp::DecreaseVehicleValue and company_cmd.cpp.
-- The four original temperate buses, with the MkII row pinned to OpenTTD 16.0-RC1.
local B={}
local floor=math.floor
local original={
  [116]={engine="bus",name="MPS Regal Bus",image=0,capacity=31,source_speed=112,
    life=12,base_life=40,intro_after_1920=3378,weight_quarters=42,power_tens_hp=9,
    purchase_factor=120,running_factor=91},
  [117]={engine="leopard_bus",name="Hereford Leopard Bus",image=17,capacity=35,source_speed=176,
    life=15,base_life=30,intro_after_1920=16071,weight_quarters=60,power_tens_hp=12,
    purchase_factor=140,running_factor=128},
  [118]={engine="foster_bus",name="Foster Bus",image=17,capacity=37,source_speed=224,
    life=15,base_life=40,intro_after_1920=24107,weight_quarters=70,power_tens_hp=15,
    purchase_factor=150,running_factor=178},
  [119]={engine="foster_mk2_bus",name="Foster MkII Superbus",image=34,capacity=40,source_speed=255,
    life=15,base_life=80,intro_after_1920=32142,weight_quarters=100,power_tens_hp=25,
    purchase_factor=160,running_factor=240},
}
local ids={bus=116,leopard_bus=117,foster_bus=118,foster_mk2_bus=119}
B.order={"bus","leopard_bus","foster_bus","foster_mk2_bus"}
B.BUY_BASE,B.RUN_BASE=14000,1600
B.CAPACITY=original[116].capacity
B.DEPRECIATION_INTERVAL=8
function B.stock_id(engine) return ids[engine] end
function B.capacity(stock_id)
  return original[stock_id] and original[stock_id].capacity
end
B.DAY_TICKS,B.DAYS_IN_YEAR=74,365
function B.quote(buy,run,id)
  id=id or 116
  local entry=original[id]
  if not entry then return end
  local q={mode="road",stock_id=id,model_life=20,tractive_effort=76,air_drag=0,
    depreciation_interval=B.DEPRECIATION_INTERVAL,load_amount=5,age_ticks=185}
  for k,v in pairs(entry) do q[k]=v end
  q.cost=floor((buy or B.BUY_BASE)*q.purchase_factor/256)
  q.annual_fp=(run or B.RUN_BASE)*q.running_factor
  return q
end
function B.new(q)
  return {stock_id=q.stock_id,buy=q.cost,value=q.cost,annual_fp=q.annual_fp,
    day=0,ticks=0,charged_ticks=0,running_fp=0}
end
function B.tick(f)
  f.ticks=f.ticks+1
end
function B.charge(annual_fp,ticks)
  return floor(annual_fp*ticks/(B.DAYS_IN_YEAR*B.DAY_TICKS))
end
function B.day(f,balance,annual_fp)
  f.day=f.day+1
  if f.day%B.DEPRECIATION_INTERVAL==0 then f.value=f.value-floor(f.value/256) end
  local fixed=B.charge(annual_fp or f.annual_fp,f.ticks-f.charged_ticks)
  f.charged_ticks,f.running_fp=f.ticks,f.running_fp+fixed
  local next_balance=balance-fixed
  return -floor(next_balance/256),next_balance%256
end
return B
