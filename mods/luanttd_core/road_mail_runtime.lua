-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 contributors: src/table/cargo_const.h, src/table/engines.h,
-- src/table/town_land.h, src/station_cmd.cpp, src/town_cmd.cpp,
-- src/economy.cpp and src/cargopacket.cpp. Manual-distribution road mail.
-- Reuse the existing stock-tested packet, income, rating and house kernels.
-- Vehicle acceleration, gradual loading, subsidies, link graphs, group
-- stations, and the game-wide price and RNG streams remain host concerns.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local sector=dofile(mod.."/catchment_sectors.lua")
local history=dofile(mod.."/openttd/station_acceptance_history.lua")
return function(Sim,H,Packets,Income,Kernel,Station)
  local M={}
  M.cargo={key="mail",id=2,bitnum=2,label="MAIL",weight_sixteenths=4,
    capacity_multiplier=0x200,transit_period_1=20,transit_period_2=90,base_payment=4550}
  M.engine={id=126,road_model=10,capacity=22,max_speed=96,load_amount=8,
    cargo_aging_ticks=185,intro_days_after_1920=5479,cost_factor=115,
    running_cost_factor=90,weight_quarters=38,power_tens_hp=12}
  local floor,max=math.floor,math.max

  -- AddAcceptedCargo_Town totals each house's mail acceptance in eighths,
  -- even if a house is unfinished (only production is gated on completion).
  -- Original house IDs 0..109 from the second cargo acceptance column in
  -- src/table/town_land.h. Each original entry puts CT_MAIL in that slot.
  local house_accept={
    [0]=3,3,3,0,4,4,1,1,1,0,0,0,0,2,2,2,
    2,3,3,2,0,0,0,0,1,1,1,2,3,2,3,2,
    0,0,0,0,3,1,1,2,2,2,2,2,2,2,1,1,
    1,1,3,3,3,3,3,3,1,1,1,1,0,0,1,1,
    2,2,1,1,1,1,2,2,3,3,2,2,2,2,1,1,
    1,1,2,0,1,2,2,3,3,2,3,0,2,1,1,1,
    1,1,4,1,1,4,1,1,4,4,4,1,1,2,
  }
  function M.house_acceptance(id) return house_accept[id] end

  function M.truck_stop(st)
    return Sim.road_stop_has(st,"truck")
  end

  function M.supported_vehicle(v)
    return v and v.cargo=="mail" and (v.engine=="mail_van" or Sim.road_freight_cargo and Sim.road_freight_cargo(v.engine)=="mail")
  end

  -- The default modified road-stop catchment is three tiles from each platform.
  local radius=3 -- station_type.h CA_TRUCK
  M.catchment=radius
  function M.acceptance(s,st)
    if not M.truck_stop(st) then return 0 end
    local total=0
    for id in pairs(Sim.road_stop_catchment(s,st,radius)) do
      local tile=id and s.tiles[id]
      local house=tile and tile.house and tile.source_house
      if house then total=total+assert(house_accept[house.id],"Unknown mail acceptance for house")
      else
        local hq=id and Sim.hq_cargo_at and Sim.hq_cargo_at(s,id)
        if hq then total=total+Sim.hq_acceptance(hq,"mail") end
      end
    end
    return total
  end
  function M.accepts(s,st) return M.acceptance(s,st)>=8 end

  -- The legacy packet kernel calls the cargo list 'passenger' internally.
  -- Provide a view of the same stock mail packet objects without sharing
  -- waiting lists, fractional rounding, or station ratings between goods.
  local function packet_view(st)
    return {stock={passenger=st.stock.mail},passenger_fraction=st.mail_fraction}
  end
  function M.waiting(st) return Packets.waiting(packet_view(st)) end
  function M.enqueue(st,p)
    local view=packet_view(st)
    Packets.enqueue(view,p)
    st.stock.mail=view.stock.passenger
  end
  function M.whole_units(st,fixed)
    local view=packet_view(st)
    local units=Packets.whole_units(view,fixed)
    st.mail_fraction=view.passenger_fraction
    return units
  end

  local function goods(st)
    if st.mail_rating_state then return st.mail_rating_state end
    local g=Kernel.new()
    st.mail_rating_state=g
    -- A legacy road stockpile is not proof of a selective loading visit.
    if M.waiting(st)>0 then
      g.has_rating=true
      g.time_since_pickup=0
    end
    return g
  end
  function M.accepted(st) history.record(goods(st)) end
  function M.offer(st)
    if not M.truck_stop(st) then return end
    local g=goods(st)
    if Kernel.has_tried_loading(g) and g.rating>0 then return g.rating end
  end
  function M.status(st)
    if not M.truck_stop(st) then return end
    local g=goods(st)
    return g.rating,g.has_rating,Kernel.has_tried_loading(g)
  end
  function M.observe_loading(s,st,v,capacity_left,calendar_year)
    if not M.truck_stop(st) or not M.supported_vehicle(v) then return end
    local build_year=Sim.date(s,v.bought or s.day)
    local running_year=calendar_year or Sim.date(s)
    Kernel.observe_loading(goods(st),floor((Sim.vehicles and Sim.vehicles[v.engine] and Sim.vehicles[v.engine].display_speed or M.engine.max_speed/2)),running_year-build_year,capacity_left)
  end

  -- Call at the existing station's stock rating event (every 185 ticks),
  -- after advancing its shared station timers exactly once. Do not invent
  -- a second timer/RNG stream for mail. Exclusively typed truck stops
  -- cannot have an active passenger goods entry in this road-first slice.
  function M.step_rating(s,st,dirty)
    if not M.truck_stop(st) then return end
    local g=goods(st)
    local waiting=M.waiting(st)
    local random=function() return Station.random_u32(s) end
    local r=Kernel.step(g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
      select_goods=s.stock_select_goods~=false,random_u32=random,waiting_changed=dirty,
      statue=Sim.station_has_town_statue and Sim.station_has_town_statue(s,st)})
    g.rating,g.has_rating,g.time_since_pickup=r.rating,r.has_rating,r.time_since_pickup
    g.last_speed,g.last_age,g.max_waiting_cargo=r.last_speed,r.last_age,r.max_waiting_cargo
    if r.drop>0 then
      for station,remaining in pairs(Station.truncate(st.stock.mail,waiting,r.drop,random)) do
        local source=s.stations[station]
        if M.truck_stop(source) then
          local original=goods(source)
          original.max_waiting_cargo=max(original.max_waiting_cargo,remaining)
        end
      end
    end
    return r.waiting_changed
  end

  function M.stops(s)
    local list={}
    for _,st in pairs(s.stations) do if M.truck_stop(st) then list[#list+1]=st end end
    table.sort(list,function(a,b) return a.id<b.id end)
    return list
  end

  -- The shared TownGenerateCargo output is not aggregated by town/center.
  -- Feed each finished house emission, in stock tick order. x,z are
  -- zero-based coordinates from H.advance_houses; callbacks do no RNG.
  local function generated(st,units,record,source_type)
    if source_type then
      local source=record.source or record.town
      local q=st.stock.mail or {}
      st.stock.mail=q
      for i=#q,1,-1 do
        local p=q[i]
        if p.origin_station==st.id and p.origin_tile==nil and (p.age or 0)==0 and
            (p.source_type or "town")==source_type and p.source==source and p.units+units<=65535 then
          p.units,p.source_type=p.units+units,source_type
          return
        end
      end
      q[#q+1]={units=units,source=source,source_type=source_type,origin_station=st.id,age=0}
    else
      M.enqueue(st,{units=units,source=record.town,origin_station=st.id,age=0})
    end
  end
  local function allocate(amount,record,list,source_type,new_cargo)
    if #list==0 then return 0 end
    Packets.allocate(amount,list)
    local moved=0
    for _,entry in ipairs(list) do
      local st=entry.st
      local units=M.whole_units(st,entry.fixed)
      if units>0 then
        generated(st,units,record,source_type)
        Kernel.observe_waiting(goods(st),units)
        if new_cargo then new_cargo(st) end
        moved=moved+units
      end
    end
    return moved
  end
  function M.from_house(s,amount,x,z,record,stops)
    if amount<=0 then return 0 end
    assert(record and (record.town or record.source),"Mail origin requires a stock source")
    local list={}
    local area=record.area or 1
    for _,st in ipairs(stops or M.stops(s)) do
      local covered=false
      for dz=0,area-1 do for dx=0,area-1 do
        if Sim.id(x+1+dx,z+1+dz) and Sim.road_stop_covers(s,st,x+1+dx,z+1+dz,radius) then covered=true end
      end end
      if covered then
        local rating=M.offer(st)
        if rating then list[#list+1]={st=st,rating=rating} end
      end
    end
    return allocate(amount,record,list,record.source_type)
  end

  -- The adapter publishes a new physical tile list when player
  -- construction changes a station. Only live daily contexts use that
  -- identity contract; external/test adapters with mutable lists do
  -- not automatically reuse their footprint.
  local mail_geometry=setmetatable({},{__mode="k"})
  local function mail_region(Catchment,st,width,depth,tiles,opts)
    local source=tiles or st.tiles
    local modified=opts and opts.modified
    local cache=opts and opts.immutable_footprints
    local entry=cache and mail_geometry[st]
    if entry and entry.source==source and entry.rules==Catchment and entry.id==st.id and
        entry.region.width==width and entry.region.height==depth and entry.modified==modified then return entry.region end
    local region=Catchment.build(tiles and {id=st.id,tiles=tiles} or st,width,depth,modified)
    if cache then
      mail_geometry[st]={source=source,rules=Catchment,id=st.id,modified=modified,region=region}
    end
    return region
  end

  -- The stock StationFinder sees one sorted station set for one house
  -- emission. Do not dispatch beside from_house: the two eligible modes
  -- must compete in this single MoveGoodsToStation call.
  function M.shared_allocator(Catchment,width,depth,physical,options)
    local stations,by_id={},{}
    local nearby=sector(width,depth)
    for _,st in ipairs(physical) do
      -- Keep the station's own packet IDs; use the host's unified
      -- StationID band only for this cross-mode search and tie break.
      local id=options and options.station_id and options.station_id(st) or st.id
      assert(not by_id[id],"Duplicate physical mail station")
      local tiles=options and options.tiles and options.tiles(st)
      local region=mail_region(Catchment,st,width,depth,tiles,options)
      by_id[id]={id=id,st=st,region=region}
      stations[#stations+1]=by_id[id]
    end
    table.sort(stations,function(a,b)return a.id<b.id end)
    -- Index coarse bounds, not a second set of tables for every
    -- covered tile. Exact coverage remains in the region and in offer().
    -- Index insertion order is the stock numeric StationID order.
    for _,q in ipairs(stations) do
      if q.region.bounds then nearby.add(q.region.bounds,q) end
    end
    local S={}
    local function lookup(id)
      local x=assert(by_id[id],"Unknown shared mail station")
      return x.st,x.region
    end
    function S.offer(amount,x,z,record)
      if amount<=0 or x<0 or x>=width or z<0 or z>=depth then return 0 end
      assert(record and (record.town or record.source),"Mail origin requires a stock source")
      local list={}
      local area=record.area or 1
      local offer=options
      if area>1 then
        offer={}
        for k,v in pairs(options or {}) do offer[k]=v end
        offer.area=area
      end
      for _,row in ipairs(nearby.query(x,z,area)) do
        local q=row.value
        local rank=Catchment.offer(q.st,q.region,"mail",x,z,goods,offer)
        if rank then list[#list+1]={st=q.st,rating=rank} end
      end
      return allocate(amount,record,list,record.source_type or "town",options and options.new_cargo)
    end
    function S.acceptance(id,house_at)
      local _,region=lookup(id)
      return Catchment.acceptance(region,"mail",house_at)
    end
    function S.loading(id,mode,max_speed,year,built,space)
      local st=lookup(id)
      return Catchment.observe_loading(goods(st),mode,max_speed,year,built,space)
    end
    function S.near(id,x,z)
      local _,region=lookup(id)
      return Catchment.contains(region,x,z)
    end
    return S
  end

  -- Shares original available-FIFO packet semantics. A full truck can
  -- report speed and age but does not reset the no-pickup timer.
  function M.load(s,st,v,cap)
    if not M.truck_stop(st) or not M.supported_vehicle(v) then return 0 end
    M.observe_loading(s,st,v,cap-v.units)
    v.batches=v.batches or {}
    local q,i,boarded=st.stock.mail or {},1,0
    while q[i] and v.units<cap do
      local p=q[i]
      if p.units>0 and p.last_vehicle~=v.id then
        local take=math.min(p.units,cap-v.units)
        local packet=Packets.split(p,take)
        if packet==p then table.remove(q,i) else i=i+1 end
        if packet.origin_station then Packets.pickup(packet,st,Sim.xy) end
        v.batches[#v.batches+1]=packet
        v.units=v.units+take
        boarded=boarded+take
      else
        i=i+1
      end
    end
    if boarded>0 then
      Station.loaded(st)
      st.last_service=st.last_service or {}
      st.last_service.mail=s.day
    end
    return boarded
  end

  function M.transfer(s,st,p,v)
    if not M.truck_stop(st) then return false end
    local g=goods(st)
    if not g.has_rating then
      g.has_rating=true
      g.time_since_pickup=0 -- first transfer grace in economy.cpp
    end
    p.last_vehicle=v.id
    if p.origin_tile then Packets.drop(p,st,Sim.xy) end
    M.enqueue(st,p)
    Station.unloaded(st)
    return true
  end

  function M.age_vehicle(v,days)
    -- 'passenger_age_ticks' is a historical serialization field name.
    -- Stock cadence and saturation do not depend on cargo type here.
    return Packets.age_vehicle(v,days)
  end

  local fare=Income and Income.temperate.mail
  assert(not fare or (fare[1]==M.cargo.base_payment and fare[2]==M.cargo.transit_period_1 and
    fare[3]==M.cargo.transit_period_2),"Mail CargoSpec differs from payment table")
  function M.fare(s,st,p)
    if not p.origin_tile or not Packets.accept_at(p,st) or not M.accepts(s,st) then return end
    local distance=Packets.distance(p,st.tile,Sim.xy)
    return Income.regular(p.units,distance,p.age,unpack(fare)),distance
  end
  return M
end
