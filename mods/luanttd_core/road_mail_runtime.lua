-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 contributors: src/table/cargo_const.h, src/table/engines.h,
-- src/table/town_land.h, src/station_cmd.cpp, src/town_cmd.cpp,
-- src/economy.cpp and src/cargopacket.cpp. Manual-distribution road mail.
-- Reuse the existing stock-tested packet, income, rating and house kernels.
-- Vehicle acceleration, gradual loading, subsidies, link graphs, group
-- stations, and the game-wide price and RNG streams remain host concerns.
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
    return st and st.mode=="road" and st.stop_type=="truck"
  end

  function M.supported_vehicle(v)
    return v and v.cargo=="mail" and (v.engine=="mail_van" or Sim.road_freight_cargo and Sim.road_freight_cargo(v.engine)=="mail")
  end

  -- The current game gives a truck stop one tile. Modified catchment, the
  -- stock default, is the same square radius 3 as a single bus stop.
  local radius=3 -- station_type.h CA_TRUCK
  M.catchment=radius
  function M.acceptance(s,st)
    if not M.truck_stop(st) then return 0 end
    local a,b=Sim.xy(st.tile)
    local total=0
    for z=b-radius,b+radius do for x=a-radius,a+radius do
      local id=Sim.id(x,z)
      local tile=id and s.tiles[id]
      local house=tile and tile.house and tile.source_house
      if house then total=total+assert(house_accept[house.id],"Unknown mail acceptance for house") end
    end end
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
  function M.observe_loading(s,st,v,capacity_left)
    if not M.truck_stop(st) or not M.supported_vehicle(v) then return end
    local build_year=Sim.date(s,v.bought or s.day)
    local running_year=Sim.date(s)
    Kernel.observe_loading(goods(st),floor((Sim.vehicles and Sim.vehicles[v.engine] and Sim.vehicles[v.engine].display_speed or M.engine.max_speed/2)),running_year-build_year,capacity_left)
  end

  -- Call at the existing station's stock rating event (every 185 ticks),
  -- after advancing its shared station timers exactly once. Do not invent
  -- a second timer/RNG stream for mail. Exclusively typed truck stops
  -- cannot have an active passenger goods entry in this road-first slice.
  function M.step_rating(s,st)
    if not M.truck_stop(st) then return end
    local g=goods(st)
    local waiting=M.waiting(st)
    local random=function() return Station.random_u32(s) end
    local r=Kernel.step(g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
      select_goods=true,random_u32=random})
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
  local function allocate(amount,record,list)
    if #list==0 then return 0 end
    Packets.allocate(amount,list)
    local moved=0
    for _,entry in ipairs(list) do
      local st=entry.st
      local units=M.whole_units(st,entry.fixed)
      if units>0 then
        M.enqueue(st,{units=units,source=record.town,origin_station=st.id,age=0})
        Kernel.observe_waiting(goods(st),units)
        moved=moved+units
      end
    end
    return moved
  end
  function M.from_house(s,amount,x,z,record,stops)
    if amount<=0 then return 0 end
    assert(record and record.town,"Mail origin requires the emitting house's town")
    local list={}
    for _,st in ipairs(stops or M.stops(s)) do
      local a,b=Sim.xy(st.tile)
      if H.single_tile_catchment(a-x-1,b-z-1,radius) then
        local rating=M.offer(st)
        if rating then list[#list+1]={st=st,rating=rating} end
      end
    end
    return allocate(amount,record,list)
  end

  -- The stock StationFinder sees one sorted station set for one house
  -- emission. Do not dispatch beside from_house: the two eligible modes
  -- must compete in this single MoveGoodsToStation call.
  function M.shared_allocator(Catchment,width,depth,physical,options)
    local stations,by_id={},{}
    for _,st in ipairs(physical) do
      assert(not by_id[st.id],"Duplicate physical mail station")
      local region=Catchment.build(st,width,depth,options and options.modified)
      by_id[st.id]={st=st,region=region}
      stations[#stations+1]=by_id[st.id]
    end
    table.sort(stations,function(a,b)return a.st.id<b.st.id end)
    local S={}
    local function lookup(id)
      local x=assert(by_id[id],"Unknown shared mail station")
      return x.st,x.region
    end
    function S.offer(amount,x,z,record)
      if amount<=0 then return 0 end
      assert(record and record.town,"Mail origin requires the emitting house's town")
      local list={}
      for _,q in ipairs(stations) do
        local rank=Catchment.offer(q.st,q.region,"mail",x,z,goods,options)
        if rank then list[#list+1]={st=q.st,rating=rank} end
      end
      return allocate(amount,record,list)
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
