-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright OpenTTD contributors. OpenTTD 16.0-RC1 vehicle.cpp (road branch
-- of CheckVehicleBreakdown, HandleBreakdown, AgeVehicle and depot service)
-- and ordering from roadveh_cmd.cpp. No path, storage backend or clock owner.
local B={VERSION=1,OFF=0,REDUCED=1,NORMAL=2}
local floor,min,max=math.floor,math.min,math.max
-- TimerGameCalendar::DateAtStartOfYear(5000001) - 1. First four
-- elapsed-year boundaries include February 29 of proleptic year zero.
B.MAX_AGE=1826212865
local age_boundary={[0]=true,[366]=true,[731]=true,[1096]=true,[1461]=true}
local thresholds={[0]=
   3,  3,  3,  3,  3,  3,  3,  3,
   4,  4,  5,  5,  6,  6,  7,  7,
   8,  8,  9,  9, 10, 10, 11, 11,
  12, 13, 13, 13, 13, 14, 15, 16,
  17, 19, 21, 25, 28, 31, 34, 37,
  40, 44, 48, 52, 56, 60, 64, 68,
  72, 80, 90,100,110,120,130,140,
 150,170,190,210,230,250,250,250,
}
local function uint(n,upper)
  return type(n)=="number" and n>=0 and n<=upper and n%1==0
end
local function validate_difficulty(d)
  d=d==nil and B.REDUCED or d
  assert(uint(d,2),"stock road breakdown difficulty must be 0, 1, or 2")
  return d
end

-- Build uses the engine's age-specific *current* reliability and source
-- decay, not percent units. Dates are absolute stock timer day counts.
function B.new(engine_reliability,decay,max_age,economy_date,calendar_date)
  assert(uint(engine_reliability,65535) and uint(decay,65535) and uint(max_age,B.MAX_AGE))
  return {version=B.VERSION,reliability=engine_reliability,reliability_spd_dec=decay,age=0,max_age=max_age,
    tick_counter=0,breakdown_ctr=0,breakdown_delay=0,breakdown_chance=0,breakdowns_since_last_service=0,
    date_of_last_service=economy_date,date_of_last_service_newgrf=calendar_date}
end

-- Once on the road front's source economy-day event, before automatic
-- servicing/orders and daily settlement. Supplier is the host's global
-- simulation Random(), called exactly once iff the stock guard admits it.
-- Road traffic blockage skips even the reliability decay. Flags are
-- supplied on the day they apply; a pending breakdown isn't cancelled by
-- changing difficulty.
function B.economy_day(s,ctx,random32)
  if ctx.front==false or ctx.menu or (ctx.blocked_ctr or 0)~=0 then return false,false end
  local difficulty=validate_difficulty(ctx.difficulty)
  if difficulty==B.REDUCED and ctx.loading then return false,false end
  local dirty=false
  if ctx.no_servicing_if_no_breakdowns==false or difficulty~=B.OFF then
    local old=s.reliability
    s.reliability=min(ctx.engine_reliability or 65535,max(old-s.reliability_spd_dec,0))
    dirty=floor(old/256)~=floor(s.reliability/256)
  end
  if s.breakdown_ctr~=0 or ctx.stopped or difficulty==B.OFF or ctx.cur_speed<5 then
    return false,dirty
  end
  local r=random32()
  assert(uint(r,2^32-1),"expected one stock uint32 Random() draw")
  -- Chance16I(1,25,r): unsigned low half only, rounding by b/2.
  local boost=floor(((r%65536)*25+12)/65536)<1
  s.breakdown_chance=min(s.breakdown_chance+(boost and 26 or 1),255)
  local rel=s.reliability+(difficulty==B.REDUCED and 0x6666 or 0)
  if thresholds[floor(min(rel,65535)/1024)]<=s.breakdown_chance then
    s.breakdown_ctr=floor(r/2^16)%64+0x3F
    s.breakdown_delay=floor(r/2^24)%128+0x80
    s.breakdown_chance=0
    return true,dirty
  end
  return false,dirty
end

-- Separately sourced calendar-day event (wallclock games may not use
-- the same calendar as the economy). Returns true when decay doubled.
function B.calendar_day(s,ctx)
  if ctx and ctx.front==false then return false end
  if s.age<B.MAX_AGE then s.age=s.age+1 end
  if age_boundary[s.age-s.max_age] then
    s.reliability_spd_dec=(s.reliability_spd_dec*2)%65536
    return true
  end
  return false
end

-- RoadVehicle::Tick increments the byte first, including non-front
-- parts. The front's controller checks crash *before* HandleBreakdown
-- and handles ordinary stopped/loading/motion after it.
--
-- The host must apply returned cur_speed and skip ordinary motion when
-- hold_motion is set. It must not treat this as changing the player stop
-- switch, speed subfraction, movement progress, or orders.
-- Shared Vehicle::HandleBreakdown. A train increments its byte once
-- before the two locomotive passes, and uses bit mask 3 for recovery.
function B.handle(s,ctx)
  local out={cur_speed=ctx.cur_speed,hold_motion=false}
  if ctx.front==false or ctx.crashed then return out end
  local n=s.breakdown_ctr
  if n==0 then return out end
  if n==2 then
    s.breakdown_ctr=1
    s.breakdowns_since_last_service=min(s.breakdowns_since_last_service+1,255)
    out.cur_speed=0
    out.started=true -- Sound request on this frame, not on daily scheduling.
    if not ctx.hidden and not ctx.no_breakdown_smoke then
      out.smoke_animation_state=s.breakdown_delay*2
    end
  elseif n~=1 then
    if not ctx.loading then s.breakdown_ctr=n-1 end
    return out
  end
  if s.tick_counter%(ctx.train and 4 or 2)==0 then
    s.breakdown_delay=(s.breakdown_delay-1)%256
    if s.breakdown_delay==0 then
      s.breakdown_ctr=0
      out.recovered=true -- Still consumes this complete controller tick.
    end
  end
  out.hold_motion=true
  return out
end

function B.tick(s,ctx)
  s.tick_counter=(s.tick_counter+1)%256
  return B.handle(s,ctx)
end

-- AircraftEventHandler calls this once per controller pass. Unlike a
-- road vehicle, a broken aircraft continues moving and the delay byte
-- is not decremented. HandleAircraftSmoke ends the breakdown at low
-- speed; the FTA applies the broken speed limit separately.
function B.aircraft_handle(s,ctx)
  if ctx.stopped or ctx.crashed then return {broken=not not s.aircraft_broken} end
  local n=s.breakdown_ctr
  if n==2 then
    s.breakdown_ctr=1
    s.breakdowns_since_last_service=min(s.breakdowns_since_last_service+1,255)
    s.aircraft_broken=true
  elseif n>2 and not ctx.loading then
    s.breakdown_ctr=n-1
  end
  if s.aircraft_broken and ctx.cur_speed<10 then
    s.aircraft_broken,s.breakdown_ctr=nil,0
    return {broken=false,recovered=true}
  end
  return {broken=not not s.aircraft_broken,started=n==2,
    smoke=s.aircraft_broken and not ctx.second_pass and s.tick_counter%16==0 or nil}
end

-- Actual depot service: both timer dates, reliability from the latest
-- engine calendar snapshot, service tally, and chance; *not* decay,
-- count-down, or repair timers. A host must still model reaching a depot:
-- do not call this merely because an order targets one.
function B.service(s,engine_reliability,economy_date,calendar_date,difficulty)
  assert(uint(engine_reliability,65535))
  difficulty=validate_difficulty(difficulty)
  s.date_of_last_service=economy_date
  s.date_of_last_service_newgrf=calendar_date
  s.breakdowns_since_last_service=0
  s.reliability=engine_reliability
  s.breakdown_chance=difficulty==B.REDUCED and 0 or floor(s.breakdown_chance/4)
end

return B
