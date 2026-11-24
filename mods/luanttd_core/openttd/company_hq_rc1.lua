-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, src/object_cmd.cpp CmdBuildObject,
-- UpdateCompanyHQ, ClearTile_Object, TileLoop_Object; src/economy.cpp
-- UpdateCompanyRatingAndValue, CalculateCompanyAssetValue/Value; and
-- src/station_cmd.cpp CheckBuildableTile.
local Q={}
local floor,min,max=math.floor,math.min,math.max
local stats={
  {"vehicles",100,120},{"stations",100,80},{"min_profit",100,10000},
  {"min_income",50,50000},{"max_income",100,100000},{"delivered",400,40000},
  {"cargo",50,8},{"cash",50,10000000},{"loan_paid",50,250000},
}
local thresholds={170,350,520,720}
function Q.stage(score,current)
  local level=0
  for _,limit in ipairs(thresholds) do if score>=limit then level=level+1 end end
  return max(level,current or 0)
end
function Q.score(company,vehicles,stations,history,min_age)
  local r={cash=company.cash,loan_paid=250000-company.loan,
    vehicles=0,stations=0,delivered=0,cargo=0}
  for _,v in ipairs(vehicles) do
    if v.primary then
      local profit=v.profit_last_year or 0
      if profit>0 then r.vehicles=r.vehicles+1 end
      if v.age>min_age then r.min_profit=min(r.min_profit or profit,profit) end
    end
  end
  for _,st in ipairs(stations) do
    if min(st.time_since_load or 255,st.time_since_unload or 255)<=20 then
      r.stations=r.stations+st.facilities
    end
  end
  for i=1,min(12,#history) do
    local row=history[i]
    local profit=row.income+row.expenses -- source expenses are signed
    r.min_income=min(r.min_income or profit,profit)
    r.max_income=max(r.max_income or profit,profit)
    if i<=4 then
      for cargo,n in pairs(row.delivered) do
        r.delivered=r.delivered+n
        if i==1 and n>0 then r.cargo=r.cargo+1 end
      end
    end
  end
  local points,total=0,0
  for _,s in ipairs(stats) do
    local factor=floor(min(max(r[s[1]] or 0,0),s[3])*s[2]/s[3])
    points,total=points+factor,total+s[2]
  end
  return floor(points*1000/total),r
end
function Q.value(company,vehicles,stations,station_price)
  local assets=0
  for _,st in ipairs(stations) do assets=assets+st.facilities*(station_price or 100)*25 end
  for _,v in ipairs(vehicles) do if v.asset~=false then assets=assets+floor(v.value*3/2) end end
  return max(1,assets+company.cash-company.loan)
end
function Q.relocation_fee(value) return floor(value/100) end
function Q.acceptance(stage)
  local level=stage+1
  return level,max(1,floor(level/2))
end
function Q.produce(stage,r,recession)
  local level=stage+1
  local p,m=r%256,floor(r/256)%256
  p=p<floor(64/(6-level)) and floor(p/32)+1 or 0
  m=m<floor(49/(6-level)) and floor(m/32)+1 or 0
  if recession then p,m=floor((p+1)/2),floor((m+1)/2) end
  return p,m
end
function Q.site(board,x,z,company,opts)
  if not opts.towns then return nil,"MUST_FOUND_TOWN_FIRST" end
  local a=board.id(x,z)
  if not a then return nil,"TOO_CLOSE_TO_EDGE_OF_MAP" end
  local pl={head=a,cost=0,tiles={}}
  local ground={}
  for dz=0,1 do for dx=0,1 do
    local id=board.id(x+dx,z+dz)
    local t=id and board.tile(id)
    if not t or t.void then return nil,"TOO_CLOSE_TO_EDGE_OF_MAP" end
    if t.water then return nil,"CAN_T_BUILD_ON_WATER" end
    local own_hq=t.hq and t.hq==opts.old_hq and t.owner==opts.owner
    local clear,reason=0
    if not own_hq then clear,reason=board.clear(id,t) end
    if clear==nil then return nil,reason or "CANT_BUILD_HEADQUARTERS" end
    pl.cost=pl.cost+clear
    ground[#ground+1]={id=id,tile=t}
  end end
  for _,cell in ipairs(ground) do
    local id,t=cell.id,cell.tile
    if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    local level=t.base+(t.slope~=0 and 1 or 0)
    if t.slope>=16 or t.slope~=0 and opts.build_on_slopes==false or pl.level and level~=pl.level then
      return nil,"FLAT_LAND_REQUIRED"
    end
    pl.level=pl.level or level
    pl.cost=pl.cost+(t.slope~=0 and (opts.foundation_price or 250) or 0)
    pl.tiles[#pl.tiles+1]={id=id,slope=t.slope,base=t.base}
  end
  for _,cell in ipairs(ground) do
    if cell.tile.bridge_above then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
  end
  if opts.old_hq then
    if a==opts.old_hq then return nil,"ALREADY_BUILT" end
    pl.cost=pl.cost+Q.relocation_fee(assert(opts.company_value))
  end
  if (opts.object_limit or 2048*65536)<65536 then return nil,"BUILD_OBJECT_LIMIT_REACHED" end
  pl.affordable=pl.cost<=company.cash
  return pl
end
return Q
