-- Native sky, sun and moon follow the campaign playback rate.
local A={}
local function smooth(a,b,x)
  local t=math.max(0,math.min(1,(x-a)/(b-a)))
  return t*t*(3-2*t)
end
local function blend(from,to,t)
  local values={}
  for i=1,3 do values[i]=math.floor(from[i]+(to[i]-from[i])*t+.5) end
  return values
end
local function hex(rgb)
  return ("#%02X%02X%02X"):format(rgb[1],rgb[2],rgb[3])
end
local function color(night,day,dusk,d,t)
  return hex(blend(blend(night,day,d),dusk,t))
end

function A.sample(time,moonlight)
  local solar=-math.cos(2*math.pi*time)
  local daylight=smooth(-.23,.23,solar)
  local twilight=1-smooth(0,.32,math.abs(solar))
  -- Brighten the exposed landscape without making the sky look like day.
  -- Also vary moonlight slightly as the moon rises rather than clamping
  -- to a permanent nighttime override as soon as the sun sets.
  local moon=moonlight-.035*(1-smooth(0,.95,-solar))
  return {
    ratio=moon+(.98-moon)*daylight,
    sky=color({74,102,150},{135,181,206},{142,146,186},daylight,twilight),
    horizon=color({93,127,171},{207,224,217},{229,170,135},daylight,twilight),
    fog=color({39,59,87},{188,209,214},{158,116,111},daylight,twilight),
  }
end

local function set_sky(p,haze,phase)
  -- Luanti may choose its day palette from the overridden brightness.
  -- Preblend the outdoor colors from the actual clock so brighter
  -- moonlight never selects a sky that looks like noon.
  p:set_sky({type="regular",clouds=haze,body_orbit_tilt=20,
    sky_color={day_sky=phase.sky,dawn_sky=phase.sky,night_sky=phase.sky,
      day_horizon=phase.horizon,dawn_horizon=phase.horizon,night_horizon=phase.horizon,
      fog_tint_type="custom",fog_sun_tint="#E2C6AA",fog_moon_tint="#8FA7BB"},
    fog=haze and {fog_color=phase.fog,fog_start=.65,fog_distance=185}
      or {fog_color="#00000000",fog_start=-1,fog_distance=-1}})
end

-- Luanti uses accelerated seconds per real second and re-reads time_speed
-- before each environment step. Let it advance/interpolate the actual sun
-- and moon. Only send a sync when playback changes; /time and the saved
-- world phase still work, unlike repeatedly deriving a phase from S.day.
local DEFAULT_ENGINE_SPEED=72
local DEFAULT_CAMPAIGN_SPEED=720 -- 86400 / 720 = two minutes at 1×
local function campaign_clock(core,speed)
  local settings=core.settings
  local original=settings:get("time_speed")
  local configured=tonumber(original) or DEFAULT_ENGINE_SPEED
  if configured==0 then return function() end end -- admin or visual QA freeze
  local base=configured==DEFAULT_ENGINE_SPEED and DEFAULT_CAMPAIGN_SPEED or math.max(0,configured)
  local applied=configured
  local owned=false
  local function update()
    local wanted=base*math.max(0,speed() or 0)
    if wanted==applied then return end
    settings:set("time_speed",tostring(wanted))
    applied,owned=wanted,true
    core.set_timeofday(core.get_timeofday()) -- prompt native phase/speed packet; do not jump
  end
  core.register_on_shutdown(function()
    if not owned or tonumber(settings:get("time_speed"))~=applied then return end
    if original then settings:set("time_speed",original) else settings:remove("time_speed") end
  end)
  update()
  return update
end

function A.start(core,speed)
  local haze,moonlight=true,.53
  local joined,elapsed={},0
  local update_clock=speed and campaign_clock(core,speed)
  local function update(p,state,phase)
    local sky=phase.sky..phase.horizon..phase.fog
    if sky~=state.sky then
      set_sky(p,haze,phase)
      state.sky=sky
    end
    if not state.ratio or math.abs(state.ratio-phase.ratio)>=.004 then
      p:override_day_night_ratio(phase.ratio)
      state.ratio=phase.ratio
    end
  end
  core.register_globalstep(function(dt)
    if update_clock then update_clock() end
    if not next(joined) then return end
    elapsed=elapsed+dt
    if elapsed<.6 then return end
    elapsed=elapsed%.6
    local phase=A.sample(core.get_timeofday(),moonlight)
    for name,state in pairs(joined) do
      local p=core.get_player_by_name(name)
      if p then update(p,state,phase) end
    end
  end)
  core.register_on_leaveplayer(function(p) joined[p:get_player_name()]=nil end)
  return function(p)
    local state={}
    joined[p:get_player_name()]=state
    p:set_sun({visible=true,sunrise_visible=true})
    p:set_moon({visible=true,scale=.79,texture="bl_coastal_moon.png",tonemap=""})
    p:set_stars({visible=true,count=720,scale=.78,star_color="#D6E4FFB5"})
    if haze then
      p:set_clouds({density=.17,height=66,thickness=6,speed={x=1.1,z=.4},
        color="#E5ECE4D2",ambient="#243B58",shadow="#91A8B8"})
    end
    if p.set_lighting then p:set_lighting({shadows={intensity=.34}}) end
    update(p,state,A.sample(core.get_timeofday(),moonlight))
  end
end

return A
