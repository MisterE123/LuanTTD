-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Port from pinned OpenTTD 14.1, src/station_cmd.cpp UpdateStationRating and
-- StationHandleSmallTick; constants from src/station_base.h and
-- src/timer/timer_game_tick.h. Loading telemetry from src/economy.cpp.
-- A game adapter applies the queue removal and any cross-station feedback.
local R={initial=175,maximum=255,day_ticks=74,rating_ticks=185}
local floor,min,max=math.floor,math.min,math.max
local function clamp(n,lo,hi) return min(hi,max(lo,n)) end
local function byte_inc(n) return min(255,n+1) end
local function field(n,offset,width) return floor(n/2^offset)%2^width end
local function as_signed32(n)
  n=n%2^32
  return n>=2^31 and n-2^32 or n
end

function R.new()
  return {rating=R.initial,has_rating=false,time_since_pickup=255,
    last_speed=0,last_age=255,max_waiting_cargo=0}
end

-- Stock road vehicle loading uses cached maximum speed / 2. The caller
-- supplies speed already converted to station-rating units, not the
-- tile-per-day simulation speed. A full vehicle can still report speed
-- and build age without recording a pickup opportunity. No-load orders
-- skip this function entirely, as in the loading branch in economy.cpp.
function R.observe_loading(g,speed,age,capacity_left)
  g.last_speed=clamp(floor(speed),0,255)
  g.last_age=clamp(floor(age),0,255)
  if capacity_left>0 then g.time_since_pickup=0 end
end

function R.has_tried_loading(g) return g.last_speed~=0 end

-- UpdateStationWaiting turns on GES_RATING only after rounding creates
-- whole waiting cargo. It is a different flag from load eligibility.
function R.observe_waiting(g,whole_units)
  if whole_units>0 then g.has_rating=true end
end

function R.advance_clock(phase,elapsed_ticks)
  local time=phase+elapsed_ticks
  return time%R.rating_ticks,floor(time/R.rating_ticks)
end

function R.increment_station_timers(st)
  st.time_since_load=byte_inc(st.time_since_load or 0)
  st.time_since_unload=byte_inc(st.time_since_unload or 0)
end

-- Pure one-cargo update. g fields follow OpenTTD GoodsEntry naming.
-- options.waiting: available (not reserved) units; destinations: map size,
-- 0 if empty, normally 1 for manual distribution. options.select_goods:
-- use the expiry check. options.random_u32 is lazy and only called for
-- the random loss branches; inject the game's deterministic RNG.
-- options.callback_rating supplies an optional raw 16-bit NewGRF result.
-- No callback is invoked here. 0xFFFF is CALLBACK_FAILED.
-- Carry options.waiting_changed only if updating multiple goods entries in
-- the same station/tick (stock keeps a station-wide dirty flag across them).
-- waiting is the actual remaining queue, not a possibly larger virtual
-- value from the stock low-rating branch. drop is the removal to apply.
function R.step(g,opts)
  local r={
    rating=g.rating,has_rating=g.has_rating,time_since_pickup=g.time_since_pickup,
    last_speed=g.last_speed,last_age=g.last_age,max_waiting_cargo=g.max_waiting_cargo,
    waiting=opts.waiting,drop=0,expire=false,waiting_changed=not not opts.waiting_changed,
    rng_calls=0,
  }
  if not r.has_rating then
    if r.rating<R.initial then r.rating=r.rating+1 end
    return r
  end

  r.time_since_pickup=byte_inc(r.time_since_pickup)
  if r.time_since_pickup==255 and opts.select_goods then
    r.has_rating=false
    r.last_speed=0
    r.drop=opts.waiting
    r.waiting=0
    r.expire=true
    r.waiting_changed=true
    return r
  end

  local waiting,num_dests=opts.waiting,opts.destinations
  local waiting_avg=floor(waiting/(num_dests+1))
  local old,rating,skip=r.rating,0,false
  if opts.cheat then
    old,rating,skip=R.maximum,R.maximum,true
  elseif opts.callback_rating~=nil and opts.callback_rating~=65535 then
    local code=opts.callback_rating
    rating=field(code,0,14)-field(code,14,1)*16384
    skip=true
  end

  if not skip then
    local b=g.last_speed-85
    if b>=0 then rating=rating+floor(b/4) end

    local since=r.time_since_pickup
    if opts.ship then since=floor(since/4) end
    if since<=21 then rating=rating+25 end
    if since<=12 then rating=rating+25 end
    if since<=6 then rating=rating+45 end
    if since<=3 then rating=rating+35 end

    local m=g.max_waiting_cargo
    rating=rating-90
    if m<=1500 then rating=rating+55 end
    if m<=1000 then rating=rating+35 end
    if m<=600 then rating=rating+10 end
    if m<=300 then rating=rating+20 end
    if m<=100 then rating=rating+10 end
  end

  if opts.statue then rating=rating+26 end
  if g.last_age<3 then rating=rating+10 end
  if g.last_age<2 then rating=rating+10 end
  if g.last_age<1 then rating=rating+13 end
  r.rating=old+clamp(clamp(rating,0,255)-old,-2,2)

  local function random()
    r.rng_calls=r.rng_calls+1
    return assert(opts.random_u32,"deterministic RNG required for station cargo loss")()%2^32
  end
  if r.rating<=64 and waiting_avg>=100 then
    local dec=field(random(),0,waiting_avg<200 and 3 or 5)
    waiting=(waiting-(dec+1)*num_dests)%2^32
    r.waiting_changed=true
  end
  if r.rating<=127 and waiting~=0 then
    local rng=random()
    if r.rating<=field(rng,0,7) then
      waiting=max(as_signed32(waiting)-as_signed32((field(rng,8,2)-1)*num_dests),0)
      r.waiting_changed=true
    end
  end
  if waiting>4096 then
    waiting=min(waiting-floor((waiting-4096)/64),32768)
    r.waiting_changed=true
  end
  if r.waiting_changed and waiting<opts.waiting then
    r.max_waiting_cargo=0
    r.drop=opts.waiting-waiting
    r.waiting=waiting
  else
    r.max_waiting_cargo=waiting_avg
  end
  return r
end
return R
