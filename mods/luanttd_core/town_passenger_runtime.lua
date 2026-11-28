-- Authored scenery -> explicit vanilla archetypes. This changes source
-- production and catchment, not town expansion or visual buildings.
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Lift=dofile(path.."openttd/town_lift.lua")
local Anim=dofile(path.."openttd/world_animation_rc1.lua")
local Stats=dofile(path.."openttd/town_cargo_stats.lua")
local road_candidates=dofile(path.."road_house_catchments.lua")
return function(Sim,H,Packets,Rating,Mail)
  local M={}
  local road_indexes=setmetatable({},{__mode="k"})
  local axis_log={[64]=6,[128]=7,[256]=8,[512]=9,[1024]=10,[2048]=11,[4096]=12}
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
    local log_x,log_y=6,6
    if profile then
      log_x=assert(axis_log[profile.width],"Unsupported town clock width")
      log_y=assert(axis_log[profile.depth],"Unsupported town clock depth")
    end
    s.passenger_house_clock=H.new_clock(log_x,log_y,profile and profile.river_rng_cursor)
    for id,t in ipairs(s.tiles) do if t.house and not t.source_house then M.stamp(s,t,id) end end
  end
  -- An alternate passenger owner replaces (never duplicates) the road
  -- allocation. The tile loop, RNG and mail path stay the same.
  function M.day(s,after_tick,hooks)
    M.start(s)
    local growth=hooks and hooks.growth
    local shared_mail=hooks and hooks.mail
    local mail=s.road_mail and Mail
    local truck_stops=not shared_mail and mail and mail.stops(s)
    local nearby
    if not (hooks and hooks.passenger) then
      local r=road_indexes[s]
      if not r or r.stations~=s.stations or r.topology~=s.topology or s.topology==nil then
        local stops={}
        for _,st in pairs(s.stations) do if st.mode=="road" and st.stop_type~="truck" then stops[#stops+1]=st end end
        table.sort(stops,function(a,b) return a.id<b.id end)
        r={stations=s.stations,topology=s.topology,
          nearby=#stops>0 and road_candidates(Sim,stops,H.bus_catchment) or nil}
        road_indexes[s]=r
      end
      nearby=r.nearby
    end
    local growth_calendar=hooks and hooks.growth_calendar
    local function house(x,z,id,t,tick)
      if id==nil then id=Sim.id(x+1,z+1);t=id and s.tiles[id] end
      if not t or not t.house then return end
      if not t.source_house then M.stamp(s,t,id) end
      if growth and growth.advance_house(s,id,t.source_house,tick,growth_calendar and growth_calendar(tick)) then return end
      return t.source_house
    end
    local function emit(cargo,amount,x,z,record,tick)
      if record.town_growth and not record.first_cargo_tick then record.first_cargo_tick=tick end
      -- Production counts even with no eligible station. The transported
      -- increment is only the integer amount added to station waiting
      -- cargo, including its existing per-station fraction.
      Stats.supply(s,record,cargo,amount,0)
      if cargo=="mail" then
        local moved
        if shared_mail then moved=shared_mail(s,amount,x,z,record,tick)
        elseif mail then moved=mail.from_house(s,amount,x,z,record,truck_stops) end
        Stats.supply(s,record,cargo,0,moved or 0)
        return moved
      end
      if cargo~="passenger" or amount<=0 then return end
      if hooks and hooks.passenger then return hooks.passenger(s,amount,x,z,record,tick) end
      if not nearby then return end
      local list
      local area=record.area or 1
      for _,row in ipairs(nearby(s,x,z,area)) do
        local st=row.value
        local covered=false
        for dz=0,area-1 do for dx=0,area-1 do
          if Sim.id(x+1+dx,z+1+dz) and Sim.road_stop_covers(s,st,x+1+dx,z+1+dz,H.bus_catchment) then covered=true end
        end end
        if covered and s.stations[st.id]==st then
          local rating=Rating.offer(s,st)
          if rating then
            list=list or {}
            list[#list+1]={st=st,rating=rating}
          end
        end
      end
      if not list then return end
      Packets.allocate(amount,list)
      local moved=0
      for _,entry in ipairs(list) do
        local st=entry.st
        local units=Packets.whole_units(st,entry.fixed)
        if units>0 then
          Packets.enqueue(st,{units=units,source=record.source or record.town,source_type=record.source_type,origin_station=st.id,age=0})
          Rating.generated(s,st,units)
          moved=moved+units
        end
      end
      Stats.supply(s,record,cargo,0,moved)
    end
    local random=function() return Rating.random_u32(s) end
    local clock=s.passenger_house_clock
    local function update_rating(tick,only)
      if only then return Rating.station_tick(s,only,mail and mail.step_rating or nil,tick or clock.counter) end
      if not (hooks and hooks.commercial_ratings) then
        Rating.advance(s,1,mail and mail.step_rating or nil,tick or clock.counter)
      end
    end
    local physical=Sim.W==2^clock.log_x and Sim.H==2^clock.log_y and s.tiles
    local hub=s.stock_world_animations
    local lift_registry=s.stock_town_lifts
    local settings={}
    if s.stock_generated_profile and growth and growth.rebuild then
      settings.rebuild=function(house,id,word,tick,rng)
        growth.rebuild(s,house,id,word,tick,rng,growth_calendar and growth_calendar(tick))
      end
    end
    local animate
    if lift_registry then
      -- OpenTTD GameLoop calls AnimateAnimatedTiles before the game
      -- timer increments and then runs the house tile loop. Both share
      -- the authoritative RNG, not a per-client decorative clock.
      settings.start_lift=function(_,tile) Lift.add(lift_registry,tile+1) end
      animate=function(tick)
        Lift.step(lift_registry,tick-1,function(id)
          local t=s.tiles[id]
          return t and t.house and t.source_house
        end,random)
      end
    end
    if hub then
      local function house(id)
        local t=s.tiles[id]
        return t and t.house and t.source_house
      end
      local function frame(id,role,tick)
        if role=="lift" and lift_registry then return Lift.frame(lift_registry,id,tick,house,random) end
        if role=="industry" and hooks and hooks.animate_industry then return hooks.animate_industry(id,tick) end
        return false
      end
      animate=function(tick) Anim.step(hub,tick-1,frame) end
    end
    local before_landscape=hooks and hooks.before_landscape
    if before_landscape then
      local first_animate=animate
      animate=function(tick)
        if first_animate then first_animate(tick) end
        before_landscape(tick-1)
      end
    end
    local rated=not animate and update_rating or function(tick)
      animate(tick)
      update_rating(tick)
    end
    local landscape_visit=hooks and hooks.landscape_tile
    local landscape_tile=landscape_visit
    if s.stock_company_hqs and next(s.stock_company_hqs) and Sim.hq_cargo_at then
      local headquarters={}
      for _,record in pairs(s.stock_company_hqs) do
        for _,id in ipairs(record.tiles) do headquarters[id]=Sim.hq_cargo_at(s,id) end
      end
      local width=Sim.W
      landscape_tile=function(x,z,tick,tile)
        if landscape_visit then landscape_visit(x,z,tick,tile) end
        local id=1+x+z*width
        local hq=headquarters[id]
        -- If a tide cleared the parcel earlier in this tick the local
        -- index must not emit from its now-obsolete source record.
        if hq and s.tiles[id].stock_landmark==hq then
          local p,m=Sim.hq_production(s,hq,random)
          local scale=s.stock_cargo_scale_percent or 100
          local record={source=hq.owner,source_type="headquarters",area=2}
          p,m=H.scale(p,scale,random),H.scale(m,scale,random)
          if p>0 then emit("passenger",p,x,z,record,tick) end
          if m>0 then emit("mail",m,x,z,record,tick) end
        end
      end
    end
    local traverse=hooks and hooks.traverse
    local tick_pulse=hooks and hooks.tick_pulse
    if after_tick then
      -- Use the same landscape cursor for housing and industry. The
      -- existing road passenger rating callback retains its placement.
      for _=1,H.day_ticks do
        if growth then
          -- Source OnTick_Town precedes OnTick_Station. The mounted
          -- adapter calls this rating hook after town and vehicle work.
          H.advance_houses(clock,1,house,settings,random,emit,animate,landscape_tile,traverse,physical)
          after_tick(clock.counter,update_rating)
        else
          H.advance_houses(clock,1,house,settings,random,emit,rated,landscape_tile,traverse,physical)
          after_tick(clock.counter)
        end
        if tick_pulse then tick_pulse(clock.counter) end
      end
    else
      H.advance_houses(clock,H.day_ticks,house,settings,random,emit,rated,landscape_tile,traverse,physical)
    end
  end
  return M
end
