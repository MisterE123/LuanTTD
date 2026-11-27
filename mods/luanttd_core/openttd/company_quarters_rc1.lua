-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, src/company_cmd.cpp SubtractMoneyFromCompany,
-- src/economy.cpp CompaniesGenStatistics, src/company_type.h.
-- The host attaches the expense types to existing ledger transactions.
local Q={max_history=24}
local function current(company)
  local r=company.stock_quarter
  if not r then r={income=0,expenses=0,delivered={}};company.stock_quarter=r end
  return r
end
local income={rail_income=true,road_income=true,air_income=true,ship_income=true}
local expense={rail_run=true,road_run=true,air_run=true,ship_run=true,property=true,loan_interest=true}
function Q.money(company,kind,amount)
  if amount==0 then return end
  if income[kind] then
    local c=current(company)
    c.income=c.income-amount
  elseif expense[kind] then
    local c=current(company)
    c.expenses=c.expenses-amount
  end
end
function Q.delivered(company,cargo,units)
  if type(cargo)~="string" or units<=0 then return end
  local c=current(company)
  c.delivered[cargo]=(c.delivered[cargo] or 0)+units
end
-- economy.cpp CompaniesPayInterest, untouched normal price table at
-- inflation=1 and no NewGRF overrides. Calendar/economy month is 1..12
-- in the host; the engine's formula observes the zero-based new month.
function Q.monthly_fees(loan,cash,month,rate,station_value,infinite_money)
  local floor=math.floor
  local yearly=floor(loan*rate/100)
  if not infinite_money and cash<0 then yearly=yearly+floor(-cash*rate/100) end
  local interest=floor(yearly*month/12)-floor(yearly*(month-1)/12)
  return interest,floor(station_value/4)
end
function Q.month(company,year,month)
  if (month-1)%3~=0 then return nil end -- 1-based host month
  local stamp=year*12+month
  if company.stock_quarter_closed==stamp then return nil end
  local history=company.stock_quarters or {}
  company.stock_quarters=history
  table.insert(history,1,current(company))
  company.stock_quarter=nil
  company.stock_quarter_closed=stamp
  history[Q.max_history+1]=nil
  return history[1]
end
return Q
