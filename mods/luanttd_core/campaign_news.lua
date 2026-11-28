-- OpenTTD 16.0-RC1 news integration. All event sources here are read from
-- the authoritative campaign or called by a real source vehicle arrival.
-- No random draws, UI state, finance details, or simulated headline timers.
return function(Sim,mod,R,cap)
  local s=R.world
  local source=mod.."/openttd/"
  local Kernel=dofile(source.."news.lua")
  local book=s.stock_news_journal or Kernel.new()
  s.stock_news_journal=book
  local W={}
  local arrivals={road={passenger="bus",freight="truck"},rail="train",ship="ship",air="aircraft"}
  local stations={road="stations",rail="stock_rail_stations",ship="stock_ship_stations",air="stock_small_airports"}
  local terminal_labels={road="road stop",rail="rail platform",ship="dock",air="airport"}
  local vehicles={road="Road vehicle",rail="Locomotive",ship="Ship",air="Aircraft"}
  local function publish(kind,style,headline,body,fields)
    local row=fields or {}
    row.year,row.month,row.day=Sim.date(s)
    row.economy,row.kind,row.style=s.day,kind,style
    row.headline,row.body=headline,body
    return Kernel.push(book,row)
  end
  -- RC1's had_vehicle_of_type bitset lives on the station, not per vehicle.
  -- Bus and Truck are different bits even on a shared road station.
  function W.arrive(mode,owner,id,tile,cargo)
    local map=stations[mode] and s[stations[mode]]
    local station=map and map[id]
    local kind=arrivals[mode]
    if not station or not kind or not owner then return end
    if mode=="road" then kind=cargo=="passenger" and kind.passenger or kind.freight end
    station.news_arrivals=station.news_arrivals or {}
    if station.news_arrivals[kind] then return end
    station.news_arrivals[kind]=true
    -- Keep this public event anonymous, even when the station or vehicle
    -- belongs to a different player. Use world town names, not user labels.
    local site=s.sites and s.sites[station.site or station.town or 0]
    local near=site and site.kind=="town" and (" near "..site.name) or ""
    local place=terminal_labels[mode].." #"..id..near
    return publish("arrival_player","thin","First "..kind.." arrives at "..place,
      "The first "..kind.." has reached the "..place..".",
      {owner=owner,tile=tile,icon=kind,ref_mode=mode,ref_station=id})
  end
  -- OpenTTD 16.0-RC1 TownActionRoadRebuild publishes general news.
  function W.road_reconstruction(id)
    local town=s.sites[id]
    if town and town.kind=="town" then
      return publish("general","normal","Road reconstruction in "..town.name,
        ("A transport company is funding six months of street repairs in %s."):format(town.name),
        {tile=town.tile,icon="industry"})
    end
  end
  function W.rail_collision(tile,victims)
    if type(victims)~="number" or victims<=0 then return end
    -- train_cmd.cpp CheckTrainCollision publishes a tile accident, not
    -- a private vehicle or company record, even for two owners.
    return publish("accident","thin","Train collision",
      ("A collision involving two trains has been reported. %d casualties."):format(victims),
      {tile=tile,icon="train"})
  end
  function W.rail_flood(tile,victims)
    return publish("accident","thin","Train flooded",
      ("A train has been flooded. %d casualties."):format(victims),{tile=tile,icon="train"})
  end
  function W.air_accident(owner,id,tile,victims)
    return publish("accident","thin","Aircraft crash at airport #"..id,
      ("An aircraft crashed while landing. %d casualties."):format(victims),
      {owner=owner,tile=tile,icon="aircraft",ref_mode="air",ref_station=id})
  end
  function W.road_flood(tile,victims,tram)
    return publish("accident","thin",tram and "Streetcar flooded" or "Road vehicle flooded",
      ("A %s has been flooded. %d casualties."):format(tram and "streetcar" or "road vehicle",victims),
      {tile=tile,icon="bus"})
  end
  local calendar=dofile(source.."stock_engine_calendar.lua")
  local market_models={}
  local function market_public(row)
    local market=s.stock_bus_market
    if not market or not row then return false end
    local id=row.stock_id or row.id
    if not id then return false end
    if not market_models[id] then market_models[id]=calendar.prepare_original(row,market.settings) or false end
    return market_models[id] and calendar.snapshot(market_models[id],market.epoch+s.day).public
  end
  local function roster()
    local rows={}
    local function add(mode,id,name,category)
      if name then rows[#rows+1]={mode=mode,id=id,name=name,category=category} end
    end
    -- Depot cash, space, and a player's holdings are irrelevant to a
    -- public-introduction event. Media/underlying service support is not.
    for _,id in ipairs(Sim.vehicle_order) do
      if Sim.vehicles[id].mode=="road" and Sim.vehicle_available(s,id) then
        local row=Sim.vehicle_offer(s,id)
        if row then add("road",row.stock_id or row.stock_engine_id or id,row.name) end
      end
    end
    if R.rail and R.rail.owned then
      for _,row in ipairs(R.rail.owned.catalog(s) or {}) do
        if row.kind=="engine" and row.passenger_model_ready and (not row.availability or row.availability.public) then
          add("rail",row.stock_id,row.name)
        end
      end
    end
    if R.water then
      for _,id in ipairs(R.water.roster.order or {}) do
        local row=R.water.depot.offer(s,id)
        if row then add("ship",id,row.name) end
      end
      for _,group in ipairs({R.water.coal or false,R.water.tanker or false}) do
        if group and group.active(s) then
          for _,id in ipairs(group.catalog or {}) do
            local row=group.model(id)
            if cap.ferry and cap.ferry[id] and market_public(row) then add("ship",id,row.name) end
          end
        end
      end
    end
    if R.air then
      for _,row in ipairs(R.air.roster.catalog(true)) do
        if cap.air and cap.air[row.stock_id] and (not row.jet or cap.city_airport) and R.air.roster.available(Sim,s,row.stock_id) then
          add("air",row.stock_id,row.name)
        end
      end
    end
    -- Source Engine::Iterate uses stock engine order, not a Lua hash order.
    table.sort(rows,function(a,b)
      if type(a.id)=="number" and type(b.id)=="number" then return a.id<b.id end
      if type(a.id)~=type(b.id) then return type(a.id)=="number" end
      return a.id<b.id
    end)
    return rows
  end
  local function introduction(initial)
    book.engines=book.engines or {}
    for _,row in ipairs(roster()) do
      local key=row.mode..":"..row.id
      if not book.engines[key] then
        book.engines[key]=true
        if not initial then
          local class=row.category or vehicles[row.mode]
          publish("new_vehicles","vehicle",class.." now available: "..row.name,
            "The "..row.name.." is now available to all companies. Check the appropriate depot to buy it.",
            {icon=row.mode})
        end
      end
    end
  end
  local chains={"stock_coal_industries","stock_timber_industries","stock_farm_industries","stock_oil_industries",
    "stock_heavy_industries","stock_bank_industries"}
  local function industries()
    local out={}
    for _,chain in ipairs(chains) do
      for id,i in pairs(s[chain] or {}) do
        local site=s.sites and s.sites[i.site or 0]
        if not i.removed and site and not site.closed then
          out[chain..":"..id]={name=site.name,tile=site.tile}
        end
      end
    end
    return out
  end
  local function industry_changes(initial)
    local before,after=book.industries,industries()
    book.industries=after
    if initial or not before then return end
    local events={}
    for key,row in pairs(before) do if not after[key] then events[#events+1]={key=key,data=row,kind="close"} end end
    for key,row in pairs(after) do if not before[key] then events[#events+1]={key=key,data=row,kind="open"} end end
    table.sort(events,function(a,b) return a.key<b.key end)
    for _,e in ipairs(events) do
      local name=e.data.name
      local closed=e.kind=="close"
      publish(e.kind,"thin",name..(closed and " closes" or " opens"),
        closed and (name.." has ceased operations. Review any transport orders serving this site.") or
        (name.." has opened. Inspect the site to see which cargos it supplies or accepts."),
        {tile=e.data.tile,icon="industry"})
    end
  end
  local function live_reference(row)
    if not row.ref_mode then return true end
    local m=s[stations[row.ref_mode]]
    return m and m[row.ref_station]~=nil
  end
  -- CmdFoundTown adds an IndustryOpen-style story aimed at the new site.
  function W.town_founded(town)
    return publish("open","thin",town.name.." founded",
      "A company sponsored construction of "..town.name..".",
      {tile=town.tile,icon="industry"})
  end
  function W.industry_opened(ind)
    local site=s.sites[ind.site or 0]
    if not site then return end
    for _,chain in ipairs(chains) do
      if s[chain] and s[chain][ind.id]==ind then
        book.industries=book.industries or {}
        local key=chain..":"..ind.id
        if book.industries[key] then return end
        book.industries[key]={name=site.name,tile=site.tile}
        return publish("open","thin",site.name.." opens",
          site.name.." has opened. Inspect the site to see which cargos it supplies or accepts.",
          {tile=site.tile,icon="industry"})
      end
    end
  end
  function W.day()
    local year,month=Sim.date(s)
    local ordinal=year*12+month
    if ordinal~=book.calendar_month then
      book.calendar_month=ordinal
      introduction(false)
      industry_changes(false)
    end
    Kernel.cleanup(book,s.day,month)
  end
  function W.topology_changed()
    -- OpenTTD's station deletion removes newspaper references. Lifetime
    -- events keep a tile instead, so an old factory closure can be read.
    Kernel.remove(book,function(row) return not live_reference(row) end)
  end
  local function endpoint(row)
    if row.type=="town" then return s.sites[row.id+1] end
    local pool=s.stock_economy_subsidies
    local key=pool and pool.industry_slots[row.id]
    if not key then return end
    local chain,id=key:match("^([^:]+):(%d+)$")
    local list=s["stock_"..chain.."_industries"]
    local firm=list and list[tonumber(id)]
    return firm and s.sites[firm.site]
  end
  local labels={[0]="Passengers","Coal","Mail","Oil","Livestock","Goods","Grain","Wood","Iron ore","Steel","Valuables"}
  local function projected(row)
    local src,dst=endpoint(row.src),endpoint(row.dst)
    if not src or not dst then return end
    return {id=row.id,cargo=assert(labels[row.cargo]),src=src.name,dst=dst.name,
      source_tile=src.tile,destination_tile=dst.tile,months=row.remaining,owner=row.awarded}
  end
  function W.subsidy(_,kind,row)
    local offer=projected(row)
    if not offer then return end
    local route=offer.cargo.." from "..offer.src.." to "..offer.dst
    local title,body
    if kind=="offer" then
      title="Service subsidy offered"
      body=route..". The first company to complete a qualifying delivery earns the contract."
    elseif kind=="awarded" then
      title="Service subsidy awarded"
      local rates={[0]="1.5×","2×","3×","4×"}
      body=offer.owner.." receives "..rates[s.stock_economy_subsidies.multiplier]..
        " the normal fare for "..route.." for "..offer.months.." months."
    elseif kind=="offer_expired" then
      title,body="Subsidy offer expired",route..". No company claimed the offer."
    else
      title,body="Service subsidy ended",route..". Deliveries now pay the normal fare."
    end
    return publish("subsidies","thin",title,body,{tile=offer.source_tile,icon="industry"})
  end
  function W.subsidies(page)
    local rows={}
    if s.stock_economy_subsidies then
      for _,item in ipairs(Sim.stock_subsidy_authority.entries(s)) do
        local row=projected(item)
        if row then rows[#rows+1]=row end
      end
    end
    local items={}
    for i=(page-1)*6+1,math.min(#rows,page*6) do items[#items+1]=rows[i] end
    return {items=items,count=#rows}
  end
  function W.head() return book.head end
  function W.history(name,page,limit)
    local items,n=Kernel.history(book,name,page,limit)
    return {items=items,count=n,head=book.head,economy=s.day}
  end
  function W.last(name,forced,current,shown,modes)
    local items=Kernel.history(book,name,1,Kernel.MAX_KEEP)
    return {article=Kernel.last(items,forced,current,shown,modes)}
  end
  function W.stream(name,after,limit)
    local items={}
    local cursor=math.min(after,book.head)
    for i=#book.items,1,-1 do
      local row=book.items[i]
      if row.seq>cursor then
        cursor=row.seq
        local visible=Kernel.view(row,name)
        if visible and Kernel.fresh(visible,s.day) then
          items[#items+1]=visible
          if #items>=limit then break end
        end
      end
    end
    if #items<limit then cursor=book.head end
    return {items=items,cursor=cursor,head=book.head,economy=s.day}
  end
  if not book.calendar_month then
    local year,month=Sim.date(s)
    book.calendar_month=year*12+month
    introduction(true)
    industry_changes(true)
  end
  return W
end
