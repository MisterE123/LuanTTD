-- Native sky, sun and moon follow the authoritative campaign calendar,
-- unless the world operator holds the time of day for presentation.
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

-- Explicit synchronization makes core.get_timeofday() (including for
-- headlights, beacons, and other mods) match the authoritative sun.
function A.start(core,calendar_phase,storage)
  local haze,moonlight=true,.53
  local mod=(core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Wind=dofile(mod.."/ambient_wind.lua")
  local key,fixed_sun="atmosphere_always_day_v1",.40
  local fixed=storage and storage:get_int(key)==1 or false
  local L={}
  function L.is_always_day() return fixed end
  function L.allowed(p)
    return calendar_phase~=nil and p~=nil and
      (core.is_singleplayer() or core.check_player_privs(p:get_player_name(),{server=true}))
  end
  local joined,elapsed={},0
  local clock_elapsed,solar_tick=.12,nil
  local function sync_clock()
    -- Do not alter the calendar or even sample it while the display is
    -- held. Releasing this override immediately uses its current phase.
    local phase=fixed and fixed_sun or calendar_phase()
    if phase==nil then return end
    local tick=math.floor(phase*24000+.5)%24000
    if solar_tick==tick and math.floor(core.get_timeofday()*24000+.5)%24000==tick then return end
    solar_tick=tick
    -- Aim inside the chosen native tick rather than at a floating-point
    -- boundary: the engine uses a truncated integer in set_timeofday().
    core.set_timeofday((tick+.25)/24000)
  end
  if calendar_phase then
    local settings=core.settings
    local original=settings:get("time_speed")
    settings:set("time_speed","0")
    core.register_on_shutdown(function()
      if tonumber(settings:get("time_speed"))~=0 then return end
      if original then settings:set("time_speed",original) else settings:remove("time_speed") end
    end)
    sync_clock()
  end
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
  local function refresh()
    if not next(joined) then return end
    local phase=A.sample(core.get_timeofday(),moonlight)
    for name,state in pairs(joined) do
      local p=core.get_player_by_name(name)
      if p then update(p,state,phase) end
    end
  end
  function L.toggle(p)
    if not L.allowed(p) then return false end
    fixed=not fixed
    if storage then storage:set_int(key,fixed and 1 or 0) end
    sync_clock()
    refresh()
    return true
  end
  core.register_globalstep(function(dt)
    if calendar_phase then
      clock_elapsed=clock_elapsed+dt
      if clock_elapsed>=.12 then clock_elapsed=clock_elapsed%.12;sync_clock() end
    end
    if not next(joined) then return end
    elapsed=elapsed+dt
    if elapsed<.6 then return end
    elapsed=elapsed%.6
    refresh()
  end)
  core.register_on_leaveplayer(function(p) joined[p:get_player_name()]=nil end)
  return function(p)
    local state={}
    joined[p:get_player_name()]=state
    p:set_sun({visible=true,sunrise_visible=true})
    p:set_moon({visible=true,scale=.79,texture="bl_coastal_moon.png",tonemap=""})
    p:set_stars({visible=true,count=720,scale=.78,star_color="#D6E4FFB5"})
    if haze then
      p:set_clouds({density=.17,height=66,thickness=6,speed=Wind.prevailing,
        color="#E5ECE4D2",ambient="#243B58",shadow="#91A8B8"})
    end
    if p.set_lighting then
      -- Use the built-in post-processing pass, not fake ray entities or
      -- fog billboards. Luanti still honours each client's shader settings.
      p:set_lighting({shadows={intensity=.34},bloom={intensity=.05},
        volumetric_light={strength=.20}})
    end
    if calendar_phase then sync_clock() end
    update(p,state,A.sample(core.get_timeofday(),moonlight))
  end,L
end

return A
