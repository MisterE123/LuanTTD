-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, aircraft_cmd.cpp AircraftController HeliRaise and
-- HeliLower. Uses the common stock aircraft speed/altitude rules.
return function(M)
  local min,max,floor=math.min,math.max,math.floor
  local H={}
  -- HelicopterTickHandler is once per simulation tick, outside the two
  -- controller substeps. Lower nonzero rotor speed is a faster period.
  function H.tick(v,ctx)
    if v.rotor_hidden then return end
    local speed,state=v.rotor_speed,v.rotor_state or 0
    if v.loading or v.stopped then
      if speed~=0 then
        speed=speed+1
        if speed>=0x80 and state==3 then speed=0 end
      end
    else
      if speed==0 then speed=0x70 end
      if speed>=0x50 then speed=speed-1 end
    end
    local tick=((v.rotor_tick or 0)+1)%256
    local interval=floor(speed/16)
    local changed=false
    if interval==0 then
      changed=state~=0
      state=0
    elseif tick>=interval then
      tick,state=0,state+1
      if state>3 then state=1 end
      changed=true
    end
    v.rotor_speed,v.rotor_state,v.rotor_tick=speed,state,tick
    if changed and ctx.rotor_frame then ctx.rotor_frame(v,state,interval) end
  end
  function H.raise(v,ctx)
    if v.rotor_speed>32 then
      v.speed=0
      v.rotor_speed=v.rotor_speed-1
      if v.rotor_speed==32 and ctx.takeoff_sound then ctx.takeoff_sound(v) end
    else
      v.rotor_speed=32
      local count=M.speed(v,nil,nil,ctx.plane_speed)
      if count>0 then
        v.tile=nil
        v.airborne=true
        local z=M.bounds(v,ctx.flight_terrain_height(v.x,v.z))
        if v.y>=z then v.speed=0;return true end
        v.y=min(v.y+count,z)
      end
    end
    return false
  end
  function H.lower(a,v,ctx)
    v.direct_descent=true
    if not a then
      v.state=ctx.flying_state
      ctx.update_aircraft_cache(v)
      ctx.next_airport_order(v)
      return false
    end
    local x,z=v.x,v.z
    if a.layout=="oilrig" then x,z=a.x,a.z end
    v.tile=a.layout=="oilrig" and a.origin or ctx.tile_at(x,z)
    v.airborne=false
    local target=ctx.slope_pixel_z(x,z)+1+(a.delta_z or 0)
    if target==v.y then
      if v.rotor_speed>=80 then v.direct_descent=nil;return true end
      v.rotor_speed=v.rotor_speed+4
    else
      local count=M.speed(v,nil,nil,ctx.plane_speed)
      if count>0 then
        if v.y>target then v.y=max(v.y-count,target) else v.y=min(v.y+count,target) end
      end
    end
    return false
  end
  return H
end
