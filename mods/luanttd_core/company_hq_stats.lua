-- Adapt durable simulation records to the OpenTTD finance inputs. Ignore
-- non-owned demonstrations and reconstruct depreciation from purchase age
-- rather than measuring depreciation from the time the HQ window opens.
return function(Sim)
  local M={min_age=730}
  local floor,max=math.floor,math.max
  function M.operating(v,year,amount)
    if not v or amount==0 then return end
    local b=v.stock_profit or {}
    v.stock_profit=b
    b[year]=(b[year] or 0)+amount
    for y in pairs(b) do if y<year-1 then b[y]=nil end end
  end
  local function value(price,months)
    while months>0 and price>=256 do
      price=price-floor(price/256)
      months=months-1
    end
    return price
  end
  function M.collect(s)
    local year,month=Sim.date(s)
    local known={}
    local function data(owner)
      if owner and s.companies[owner] then
        local r=known[owner]
        if not r then r={vehicles={},stations={},min_age=M.min_age};known[owner]=r end
        return r
      end
    end
    local function station(st,rec)
      local r=data(st.owner)
      if r then
        rec=rec or st
        local facilities=1
        if st.road_members then
          local kinds={}
          for _,kind in pairs(st.road_members) do kinds[kind]=true end
          facilities=kinds.truck and kinds.bus and 2 or 1
        end
        r.stations[#r.stations+1]={facilities=facilities,time_since_load=rec.time_since_load,time_since_unload=rec.time_since_unload}
      end
    end
    local function vehicle(owner,v,price,bought,primary)
      local r=data(owner)
      if not r or type(price)~="number" or price<0 then return end
      local age=max(0,s.day-(bought or s.day))
      local y,m=Sim.date(s,bought or s.day)
      local depreciation=max(0,year*12+month-y*12-m)
      r.vehicles[#r.vehicles+1]={primary=primary,age=age,value=value(price,depreciation),
        profit_last_year=v.stock_profit and v.stock_profit[year-1] or 0}
    end
    for _,st in pairs(s.stations or {}) do station(st) end
    local service=s.stock_ship_commercial and s.stock_ship_commercial.service
    local index={rail={},ship={},air={}}
    for _,st in pairs(service and service.stations or {}) do
      if index[st.host_mode] then index[st.host_mode][st.host_id]=st end
    end
    for _,row in ipairs({{"rail",s.stock_rail_stations},{"ship",s.stock_ship_stations},{"air",s.stock_small_airports}}) do
      local mode,grid=row[1],row[2]
      for id,st in pairs(grid or {}) do
        local rec=index[mode][id]
        station(st,rec)
      end
    end
    for _,v in pairs(s.fleet or {}) do
      local def=Sim.vehicles[v.engine] or {}
      vehicle(v.owner,v,v.stock_purchase_value or def.cost,v.bought,true)
    end
    local rail=s.stock_rail_fleet
    for _,v in pairs(rail and rail.units or {}) do
      -- Value is based on each physical vehicle, including loose wagons.
      -- Only the leading powered vehicle contributes performance profit.
      for i,p in ipairs(v.parts or {}) do
        local active=i==1 and not v.loose and v.status~="free" and v.status~="loose"
        vehicle(v.owner,active and v or p,p.purchase_value,p.purchase_day or v.purchase_day,active)
      end
    end
    for _,v in pairs(s.stock_owned_air_fleet or {}) do vehicle(v.owner,v,v.price,v.day,true) end
    if s.stock_owned_aircraft then
      local v=s.stock_owned_aircraft;vehicle(v.owner,v,v.price,v.day,true)
    end
    for _,k in ipairs({"stock_owned_ferry","stock_owned_oil_ship","stock_coal_ship"}) do
      local v=s[k]
      if v then vehicle(v.owner,v,v.price or v.purchase,v.purchase_day,true) end
    end
    local function tram(run)
      local v=run and run.carrier
      if v then vehicle(v.owner,v,v.stock_purchase_value,v.bought,true) end
    end
    tram(s.tram_pilot)
    for _,run in pairs(s.stock_tram_fleet or {}) do tram(run) end
    return known
  end
  function M.record(s,asset,amount)
    if asset and amount~=0 then M.operating(asset,Sim.date(s),amount) end
  end
  return M
end
