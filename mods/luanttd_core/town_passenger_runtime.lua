-- Authored scenery -> explicit vanilla archetypes. This changes source
-- production and catchment, not town expansion or visual buildings.
return function(Sim,H,Packets,Rating,Mail)
  local M={}
  local archetype={[0]=0x19,0x18,0x1A,0x06}
  function M.stamp(s,t,id)
    if not t.house then return end
    local town=Sim.nearest_town(s,id)
    if not town then return end
    local id=t.parcel=="green" and 0x0B or
      (t.parcel=="shop" or t.parcel=="market") and 0x0E or archetype[t.variant]
    t.source_house={id=assert(id),town=town.id,completed=true}
  end
  function M.start(s)
    if s.passenger_house_clock then return end
    -- Smaller scenarios use the smallest stock lattice; generated profiles
    -- cover their entire saved board and carry the river stage head.
    -- Imported or resumed maps keep their own stride and tick counter.
    local profile=s.stock_generated_profile
    local size_log=profile and profile.width==128 and 7 or 6
    s.passenger_house_clock=H.new_clock(size_log,size_log,profile and profile.river_rng_cursor)
    for id,t in ipairs(s.tiles) do if t.house and not t.source_house then M.stamp(s,t,id) end end
  end
  -- An alternate passenger owner replaces (never duplicates) the road
  -- allocation. The tile loop, RNG and mail path stay the same.
  function M.day(s,after_tick,hooks)
    M.start(s)
    local growth=hooks and hooks.growth
    local mail=s.road_mail and Mail
    local truck_stops=mail and mail.stops(s)
    local stops={}
    for _,st in pairs(s.stations) do if st.mode=="road" and st.stop_type~="truck" then stops[#stops+1]=st end end
    table.sort(stops,function(a,b) return a.id<b.id end)
    local function house(x,z)
      local id=Sim.id(x+1,z+1)
      local t=id and s.tiles[id]
      if not t or not t.house then return end
      if not t.source_house then M.stamp(s,t,id) end
      if growth and growth.advance_house(s,id,t.source_house) then return end
      return t.source_house
    end
    local function emit(cargo,amount,x,z,record,tick)
      if record.town_growth and not record.first_cargo_tick then record.first_cargo_tick=tick end
      if cargo=="mail" and mail then mail.from_house(s,amount,x,z,record,truck_stops);return end
      if cargo~="passenger" or amount<=0 then return end
      if hooks and hooks.passenger then return hooks.passenger(s,amount,x,z,record,tick) end
      local list={}
      for _,st in ipairs(stops) do
        local a,b=Sim.xy(st.tile)
        if H.single_tile_catchment(a-x-1,b-z-1,H.bus_catchment) then
          local rating=Rating.offer(s,st)
          if rating then list[#list+1]={st=st,rating=rating} end
        end
      end
      if #list==0 then return end
      Packets.allocate(amount,list)
      for _,entry in ipairs(list) do
        local st=entry.st
        local units=Packets.whole_units(st,entry.fixed)
        if units>0 then
          Packets.enqueue(st,{units=units,source=record.town,origin_station=st.id,age=0})
          Rating.generated(s,st,units)
        end
      end
    end
    local random=function() return Rating.random_u32(s) end
    local update_rating=function() Rating.advance(s,1,mail and mail.step_rating or nil) end
    local clock=s.passenger_house_clock
    local landscape_tile=hooks and hooks.landscape_tile
    if after_tick then
      -- Use the same landscape cursor for housing and industry. The
      -- existing road passenger rating callback retains its placement.
      for _=1,H.day_ticks do
        if growth then
          -- Source OnTick_Town precedes OnTick_Station. The mounted
          -- adapter calls this rating hook after town and vehicle work.
          H.advance_houses(clock,1,house,{},random,emit,nil,landscape_tile)
          after_tick(clock.counter,update_rating)
        else
          H.advance_houses(clock,1,house,{},random,emit,update_rating,landscape_tile)
          after_tick(clock.counter)
        end
      end
    else
      H.advance_houses(clock,H.day_ticks,house,{},random,emit,update_rating,landscape_tile)
    end
  end
  return M
end
