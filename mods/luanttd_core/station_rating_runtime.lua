-- SPDX-License-Identifier: GPL-2.0-only
-- Stock mechanics from OpenTTD 14.1 src/station_cmd.cpp (station tick and
-- TruncateCargo), src/cargopacket.cpp (StationCargoList::Truncate), and
-- src/core/random_func.cpp (Randomizer), copyright OpenTTD contributors.
-- LuanTTD adapter: one passenger cargo, one manual-distribution destination,
-- no reservations. Daily batches place the stock timer events within each
-- 74-tick day, but production, loading and unloading are day-batched.
local floor,min,max=math.floor,math.min,math.max
local UINT,HALF=2^32,2^16
local function rotr(x,n) return floor(x/2^n)+(x%2^n)*2^(32-n) end
local function xor(x,y)
  local v,p=0,1
  for _=1,32 do
    if x%2~=y%2 then v=v+p end
    x,y,p=floor(x/2),floor(y/2),2*p
  end
  return v
end

-- LuaJIT rotations produce signed words; reducing modulo 2^32 gives
-- the same unsigned arithmetic that Randomizer::Next uses in RC1.
local function next_words(a,b)
  return (a+rotr(xor(b,0x1234567f),7)+1)%UINT,(rotr(a,3)-1)%UINT
end
if bit and bit.ror and bit.bxor then
  local ror,bxor=bit.ror,bit.bxor
  next_words=function(a,b)
    return (a+ror(bxor(b,0x1234567f),7)+1)%UINT,(ror(a,3)-1)%UINT
  end
end

-- Exact stock generator arithmetic. The current roadmap world does not yet
-- run all of OpenTTD's other Random() callers. Keep this saved simulation
-- stream separate, never claim matching seed traces across whole worlds.
local function random_u32(s)
  local state=s.passenger_rating_rng
  if not state then
    local seed=floor(s.seed or 0)%UINT
    state={seed,seed}
    s.passenger_rating_rng=state
  end
  local a,b=state[1],state[2]
  state[1],state[2]=next_words(a,b)
  return state[2]
end

-- Unsigned multiply-high without converting an arbitrary 64-bit product to
-- a Lua double. This preserves RandomRange() at uint32 boundaries.
local function mul_high(x,y)
  local a,b=floor(x/HALF),x%HALF
  local c,d=floor(y/HALF),y%HALF
  return a*c+floor((a*d+b*c+floor(b*d/HALF))/HALF)
end

-- Direct translation of StationCargoList::Truncate for a single packet
-- ring. Preserve packet identity/age on partial cuts, count retained cargo
-- by the packet's first station, and never reach into vehicle batches.
local function truncate(queue,waiting,drop,random)
  local max_move=min(waiting,drop)
  local moved,loop,retained=0,0,{}
  local function count(p,delta)
    if p.origin_station then
      retained[p.origin_station]=(retained[p.origin_station] or 0)+delta
    end
  end
  while max_move>moved do
    local i=1
    while queue[i] do
      local p=queue[i]
      if waiting>max_move and mul_high(random(),waiting)<waiting-max_move then
        if loop==0 then count(p,p.units) end
        i=i+1
      else
        local diff=max_move-moved
        if p.units>diff then
          if diff>0 then p.units=p.units-diff;moved=moved+diff end
          if loop>0 then count(p,-diff);return retained end
          count(p,p.units)
          i=i+1
        else
          if loop>0 then count(p,-p.units) end
          moved=moved+p.units
          table.remove(queue,i)
        end
      end
    end
    loop=loop+1
  end
  return retained
end

return function(Sim,Kernel,Packets)
  local R={day_ticks=Kernel.day_ticks,random_u32=random_u32,random_range=mul_high,truncate=truncate}
  local base=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
  local history=dofile(base.."/openttd/station_acceptance_history.lua")
  -- Cache units from the authored engines, shared in value with road YAPF.
  -- The Town Flyer uses stock MPS Regal 112 / 2; the other visual road models
  -- are LuanTTD variants. Vehicle purchase date is our build date.
  local max_speed={bus=112,coach=144,leopard_bus=176,foster_bus=224,foster_mk2_bus=255,mail_van=96,truck=96}

  local function goods(s,st)
    local g=st.passenger_rating_state
    if g then return g end
    g=Kernel.new()
    st.passenger_rating_state=g
    local waiting=Packets.waiting(st)
    g.has_rating=waiting>0
    if st.passenger_rating~=nil then g.rating=st.passenger_rating end
    -- Old campaign records remembered a first service marker but not its
    -- latest no-cargo loading attempt. Infer conservatively from the last
    -- real boarding if available, else the first recorded service.
    if st.passenger_service_day then
      local last=(st.last_service or {}).passenger or st.passenger_service_day
      g.last_speed=max_speed.bus/2
      g.time_since_pickup=min(254,floor(max(0,s.day-last)*Kernel.day_ticks/Kernel.rating_ticks))
    elseif waiting>0 then
      -- An older transfer-only stop had a queue but no pickup telemetry.
      -- Keep it ineligible for new local production, with stock first-drop grace.
      g.time_since_pickup=0
    end
    return g
  end

  function R.generated(s,st,units)
    Kernel.observe_waiting(goods(s,st),units)
  end
  function R.transferred(s,st)
    local g=goods(s,st)
    if not g.has_rating then
      g.has_rating=true
      g.time_since_pickup=0
    end
  end
  function R.observe_loading(s,st,v,capacity_left,running_year)
    local year=running_year or Sim.date(s)
    local built=Sim.date(s,v.bought or s.day)
    local speed=v.stock_tram and v.stock_tram.speed or max_speed[v.engine]
    if speed then Kernel.observe_loading(goods(s,st),floor(speed/2),year-built,capacity_left) end
  end
  function R.loaded(st) st.time_since_load=0;st.last_vehicle_type="road" end
  function R.unloaded(st) st.time_since_unload=0 end
  function R.accepted(s,st) history.record(goods(s,st)) end

  function R.offer(s,st)
    if st.mode~="road" or st.stop_type=="truck" then return end
    local g=goods(s,st)
    if Kernel.has_tried_loading(g) and g.rating>0 then return g.rating end
  end

  function R.status(s,st)
    local g=goods(s,st)
    return g.rating,g.has_rating,Kernel.has_tried_loading(g)
  end

  local function tick(s,st)
    Kernel.increment_station_timers(st)
    local g=goods(s,st)
    local waiting=Packets.waiting(st)
    local random=function() return random_u32(s) end
    local r=Kernel.step(g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
      select_goods=true,random_u32=random,
      statue=Sim.station_has_town_statue and Sim.station_has_town_statue(s,st)})
    g.rating,g.has_rating,g.time_since_pickup=r.rating,r.has_rating,r.time_since_pickup
    g.last_speed,g.last_age,g.max_waiting_cargo=r.last_speed,r.last_age,r.max_waiting_cargo
    if r.drop<=0 then return r.waiting_changed end
    for station,remaining in pairs(truncate(st.stock.passenger,waiting,r.drop,random)) do
      local source=s.stations[station]
      if source and source.mode=="road" then
        local original=goods(s,source)
        original.max_waiting_cargo=max(original.max_waiting_cargo,remaining)
      end
    end
    return r.waiting_changed
  end

  function R.accident(s,owner,x,y,accepts_mail)
    local rows={}
    for _,st in pairs(s.stations) do
      local group=s.stock_joined_stations and st.stock_station_id~=nil and
        Sim.stock_joined_station.resolve(s,st.stock_station_id,"road",st.id,st)
      local c=s.stock_ship_commercial
      local air=group and Sim.stock_joined_station.commercial_member(group) and group.service_station_id and c and c.service.stations[group.service_station_id]
      if st.mode=="road" and not air then -- shared GoodsEntry was already rated by the commercial caller
        local xx,yy=Sim.xy(st.tile)
        local g=goods(s,st)
        local entries={{state=g,active=g.has_rating or (st.passenger_acceptance or 0)>=8}}
        local mail=st.mail_rating_state
        if mail then
          entries[#entries+1]={state=mail,active=mail.has_rating or mail.ever_accepted or
            mail.current_month or mail.accepted_bigtick or accepts_mail and accepts_mail(s,st)}
        end
        rows[#rows+1]={owner=st.owner,x=xx,y=yy,goods=entries}
      end
    end
    return Kernel.modify_around(rows,owner,x,y,-160,30)
  end

  local function big(st)
    if st.passenger_rating_state then history.big_tick(st.passenger_rating_state) end
    if st.mail_rating_state then history.big_tick(st.mail_rating_state) end
    for _,entry in pairs(st.goods or {}) do
      if type(entry)=="table" then history.big_tick(entry) end
    end
  end

  local airport_cache=setmetatable({},{__mode="k"})
  function R.airports(s)
    local fields=s.stock_small_airports
    if s.stock_engine_startup_seed==nil or not fields or not next(fields) then return end
    local cached=airport_cache[s]
    if cached and cached.topology==s.topology then return cached.rows end
    local rows={}
    for _,field in pairs(fields) do
      local tile=s.tiles[field.origin]
      if field.stock_station_id~=nil and tile and tile.airfield and tile.airfield.airport==field.id then
        rows[#rows+1]={id=field.stock_station_id,airport=field}
      end
    end
    table.sort(rows,function(a,b) return a.id<b.id end)
    airport_cache[s]={topology=s.topology,rows=rows}
    return rows
  end
  function R.airport_acceptance_tick(s,row,tick)
    if not row or not tick or (tick+row.id)%250~=0 then return end
    local field=row.airport
    if (s.stock_small_airports or {})[field.id]==field then
      -- newgrf_airporttiles.cpp TriggerAirportAnimation: an existing
      -- airport consumes the first word before testing any tile's GRF.
      random_u32(s)
    end
  end
  -- station_cmd.cpp OnTick_Station: a single BaseStation's small tick,
  -- then its staggered big tick. Its caller merges different modes by ID.
  function R.station_tick(s,st,other_goods,absolute_tick,freight)
    if st.mode~="road" then return end
    local phase,events=Kernel.advance_clock(st.passenger_rating_phase or 0,1)
    st.passenger_rating_phase=phase
    if events>0 then
      local dirty=tick(s,st)
      if freight and freight.coal then dirty=freight.coal(st,dirty) or dirty end
      if other_goods then dirty=other_goods(s,st,dirty) or dirty end
      if freight and freight.remaining then freight.remaining(st,dirty) end
    end
    if (absolute_tick+(st.stock_station_id or st.id-1))%250==0 then big(st) end
  end

  local combined_cache=setmetatable({},{__mode="k"})
  function R.advance(s,ticks,other_goods,absolute_tick)
    local airports=R.airports(s)
    if ticks==1 and absolute_tick and airports and #airports>0 then
      local cache=combined_cache[s]
      if not cache or cache.topology~=s.topology then
        local rows={}
        for _,st in pairs(s.stations) do
          if st.mode=="road" then rows[#rows+1]={id=st.stock_station_id or st.id-1,road=st} end
        end
        for _,airport in ipairs(airports) do rows[#rows+1]=airport end
        table.sort(rows,function(a,b) return a.id<b.id or a.id==b.id and a.road~=nil and b.road==nil end)
        cache={topology=s.topology,rows=rows}
        combined_cache[s]=cache
      end
      for _,row in ipairs(cache.rows) do
        local road=row.road
        if road and s.stations[road.id]==road then R.station_tick(s,road,other_goods,absolute_tick)
        elseif row.airport then R.airport_acceptance_tick(s,row,absolute_tick) end
      end
      return
    end
    local events={}
    for _,st in pairs(s.stations) do
      if st.mode=="road" then
        if absolute_tick and (absolute_tick+(st.stock_station_id or st.id-1))%250==0 then
          big(st)
        end
        local phase=st.passenger_rating_phase or 0
        -- Generate and merge each station's events in chronological order.
        -- Pool IDs break ties as stock BaseStation::Iterate() does.
        for when=Kernel.rating_ticks-phase,ticks,Kernel.rating_ticks do
          events[#events+1]={when=when,st=st}
        end
        st.passenger_rating_phase=Kernel.advance_clock(phase,ticks)
      end
    end
    table.sort(events,function(a,b)
      if a.when==b.when then return (a.st.stock_station_id or a.st.id)<(b.st.stock_station_id or b.st.id) end
      return a.when<b.when
    end)
    for _,event in ipairs(events) do
      tick(s,event.st)
      if other_goods then other_goods(s,event.st) end
    end
  end
  return R
end
