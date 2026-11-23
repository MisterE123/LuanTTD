-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1: table/engines.h, table/pricebase.h, engine.cpp,
-- aircraft_cmd.cpp. Original temperate fixed-wing small-plane slice.
local A={}
local base=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Calendar=dofile(base.."/openttd/stock_engine_calendar.lua")
local rows={
  [215]={stock_id=215,name="Sampson U52",image=1,passengers=25,mail=4,acceleration=18,
    source_speed=37,intro_after_1920=2922,life=20,model_life=20,buy_factor=14,running_factor=85,
    small=true,visual="sampson"},
  [216]={stock_id=216,name="Coleman Count",image=0,passengers=65,mail=8,acceleration=20,
    source_speed=37,intro_after_1920=9922,life=24,model_life=20,buy_factor=15,running_factor=100,
    small=true,visual="coleman"},
  [219]={stock_id=219,name="Bakewell Cotswald LB-3",image=5,passengers=30,mail=6,acceleration=20,
    source_speed=37,intro_after_1920=4929,life=30,model_life=30,buy_factor=15,running_factor=98,
    small=true,visual="bakewell_cotswald"},
  [217]={stock_id=217,name="FFP Dart",image=2,passengers=90,mail=10,acceleration=35,
    source_speed=74,intro_after_1920=12659,life=18,model_life=20,buy_factor=16,running_factor=130,
    small=false,jet=true,visual="ffp_dart"},
  [220]={stock_id=220,name="Bakewell Luckett LB-8",image=6,passengers=200,mail=30,acceleration=40,
    source_speed=74,intro_after_1920=13695,life=23,model_life=25,buy_factor=18,running_factor=240,
    small=false,jet=true,visual="bakewell_luckett_lb8"},
  [225]={stock_id=225,name="Yate Aerospace YAC 1-11",image=2,passengers=95,mail=10,acceleration=35,
    source_speed=74,intro_after_1920=15371,life=22,model_life=25,buy_factor=16,running_factor=135,
    small=false,jet=true,visual="yate_yac_1_11"},
  [226]={stock_id=226,name="Darwin 100",image=2,passengers=170,mail=35,acceleration=40,
    source_speed=74,intro_after_1920=15461,life=25,model_life=25,buy_factor=18,running_factor=240,
    small=false,jet=true,visual="darwin_100"},
  [228]={stock_id=228,name="Darwin 300",image=7,passengers=300,mail=50,acceleration=40,
    source_speed=74,intro_after_1920=17227,life=25,model_life=30,buy_factor=30,running_factor=253,
    small=false,jet=true,visual="darwin_300"},
}
A.BUY_BASE,A.RUN_BASE=700000,9600
A.DAY_TICKS,A.DAYS_IN_YEAR=74,365
local floor=math.floor
for _,r in pairs(rows) do r.max_speed=floor(r.source_speed*128/10) end
function A.entry(id)
  local r=rows[id]
  if not r then return end
  local result={}
  for k,v in pairs(r) do result[k]=v end
  return result
end
function A.catalog()
  return {A.entry(215),A.entry(219),A.entry(216),A.entry(217),A.entry(220),A.entry(225),A.entry(226),A.entry(228)}
end
local calendar_cache=setmetatable({},{__mode="k"})
function A.available(Sim,s,id)
  local row=rows[id]
  if not row then return false end
  if not row.jet then return true end
  local market=s.stock_bus_market
  if not market then return Sim.date(s)>=({[217]=1955,[220]=1958,[225]=1962,[226]=1963,[228]=1968})[id] end
  local cached=calendar_cache[market]
  if not cached then cached={};calendar_cache[market]=cached end
  local model=cached[id]
  if not model then
    model=assert(Calendar.prepare_original({stock_id=id,vehicle_type=3,climates=7,
      intro_after_1920=row.intro_after_1920,decay_speed=20,life=row.life,base_life=row.model_life},market.settings))
    cached[id]=model
  end
  return Calendar.snapshot(model,market.epoch+s.day).public
end
local function uint(n)
  return type(n)=="number" and n>=0 and n%1==0 and n<=2^32-1
end
function A.quote(id,purchase_base,running_base)
  local r=rows[id]
  if not r then return nil,"UNKNOWN_STOCK_AIRCRAFT" end
  purchase_base=purchase_base or A.BUY_BASE
  running_base=running_base or A.RUN_BASE
  if not uint(purchase_base) or not uint(running_base) then return nil,"INVALID_PRICE_SETTINGS" end
  return {stock_id=id,price=floor(purchase_base*r.buy_factor/256),annual_fp=running_base*r.running_factor,
    passengers=r.passengers,mail=r.mail,acceleration=r.acceleration,max_speed=r.max_speed,visual=r.visual}
end
function A.day_charge(annual_fp,ticks)
  return floor(annual_fp*ticks/(A.DAYS_IN_YEAR*A.DAY_TICKS))
end
function A.debit_fraction(balance,fixed)
  local next_balance=balance-fixed
  return -floor(next_balance/256),next_balance%256
end
return A
