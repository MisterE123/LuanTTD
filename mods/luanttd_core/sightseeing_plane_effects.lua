-- Personal non-spatial sound: it never leaks into commercial traffic
-- and every loop is owned by the current cockpit session.
return function(core)
  local E={}
  local min,max=math.min,math.max
  function E.start(for_player)
    local a={time=0,player=for_player,mode="ready",gain={}}
    for k,low in pairs({prop_idle=.14,prop_power=.002,wind=.002}) do
      a[k]=core.sound_play("bl_plane_"..k,{to_player=for_player,loop=true,gain=low})
      a.gain[k]=low
    end
    return a
  end
  function E.update(a,flight,dt)
    if a.mode=="air" and flight.mode=="rollout" then
      core.sound_play("bl_plane_touchdown",{to_player=a.player,gain=.24},true)
    end
    a.mode=flight.mode
    a.time=a.time+dt
    if a.time<.135 then return end
    a.time=0
    local t,airspeed=flight.throttle,flight.speed
    local wind=flight.mode=="air" and min(.22,max(.012,(airspeed/12)^1.6*.21)) or .002
    for k,value in pairs({prop_idle=.16*(1-t)+.027,prop_power=.002+.22*t^1.45,wind=wind}) do
      if a[k] and math.abs(value-a.gain[k])>.008 then
        a.gain[k]=value
        core.sound_fade(a[k],.75,value)
      end
    end
  end
  function E.stop(a)
    if not a then return end
    for _,k in ipairs({"prop_idle","prop_power","wind"}) do
      if a[k] then core.sound_stop(a[k]);a[k]=nil end
    end
  end
  return E
end
