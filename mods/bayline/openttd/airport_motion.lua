-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 14.1 aircraft_cmd.cpp fixed-wing AircraftController,
-- UpdateAircraftSpeed, GetAircraftFlightLevel{Bounds}, vehicle.cpp
-- GetNewVehiclePos and GetDirectionTowards. Uses source 16px tile units.
return function(FTA)
  local M={TAXI=50,APPROACH=230,BROKEN=320,HOLD=425,NONE=65535,PLANE_SPEED=4}
  local F=FTA.flag
  local floor,ceil,abs,min,max=math.floor,math.ceil,math.abs,math.min,math.max
  local delta_x,delta_z={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local directions={[0]=0,7,6,1,3,5,2,3,4}
  local function sign(n) return n<0 and -1 or n>0 and 1 or 0 end
  local function one_turn(old,new)
    local diff=(new-old)%8
    return diff==0 and old or (old+(diff>4 and -1 or 1))%8
  end
  local function towards(v,x,z)
    return one_turn(v.direction,directions[3*(sign(z-v.z)+1)+sign(x-v.x)+1])
  end
  local function flag(f,b) return floor(f/b)%2==1 end

  function M.speed(v,limit,hard,plane_speed)
    plane_speed=plane_speed or M.PLANE_SPEED
    if hard==nil then hard=true end
    limit=(limit or M.NONE)*plane_speed
    local inc=v.acceleration*77
    if v.broken then
      if M.BROKEN<limit then hard=false end
      limit=min(limit,M.BROKEN)
    end
    if v.max_speed<limit then
      if v.speed<limit then hard=false end
      limit=v.max_speed
    end
    local t=v.subspeed
    v.subspeed=(v.subspeed+inc%256)%256
    if not hard and v.speed>limit then
      limit=v.speed-max(1,floor(floor(v.speed*v.speed/16384)/plane_speed))
    end
    v.speed=min(v.speed+floor(inc/256)+(v.subspeed<t and 1 or 0),limit)
    local advance=floor(v.speed/plane_speed)
    if v.direction%2==0 then advance=floor(advance*3/4) end
    advance=advance+v.progress
    v.progress=advance%256
    return floor(advance/256)
  end

  function M.bounds(v,terrain_height)
    local base=(terrain_height or 0)+(v.direction<4 and 10 or 0)
    base=base+min(20*floor(v.max_speed/200)-90,0)
    return base+120,base+360
  end
  function M.flight_height(v,terrain_height,takeoff)
    local lo,hi=M.bounds(v,terrain_height)
    local mid=floor((lo+hi)/2)
    local h=v.y
    if h<lo or v.correct_min and h<mid then
      v.correct_min=true
      return h+(takeoff and 2 or 1)
    elseif not takeoff and (h>hi or v.correct_max and h>mid) then
      v.correct_max=true;return h-1
    elseif v.correct_min and h>=mid then
      v.correct_min=nil
    elseif v.correct_max and h<=mid then
      v.correct_max=nil
    end
    return h
  end
  function M.glide(y,ground,dist)
    local t=max(1,dist-4)
    local delta=y-ground
    if delta>=t then y=y-ceil(delta/t) end
    return max(y,ground)
  end
  local function ground_at(a,v,h)
    return h.terrain_height and h.terrain_height(v.x,v.z) or (a.ground or 0)
  end

  -- Exactly one invocation of the fixed-wing position controller. DD
  -- state/tile updates in the game are exposed as v.airborne and coordinates.
  -- Sounds, breakdown dispatch, station removal, and crashes are external.
  function M.move(a,v,h)
    h=h or {}
    if v.helicopter then return nil,"fixed_wing_only" end
    local x,z,f,exit=FTA.point(v.pos,a.rotation,a.width,a.height)
    if not x then return nil,"invalid_position" end
    x,z=x+a.x,z+a.z
    if flag(f,F.HELI_RAISE) or flag(f,F.HELI_LOWER) then return nil,"heli_point" end
    local dist=abs(x-v.x)+abs(z-v.z)
    local exact,slow,landing,brake=flag(f,F.EXACTPOS),flag(f,F.SLOWTURN),flag(f,F.LAND),flag(f,F.BRAKE)
    if not exact and dist<=(slow and 8 or 4) then return true end
    if dist==0 then
      if v.direction==exit then v.speed=0;return true end
      if M.speed(v,M.TAXI,true,h.plane_speed)==0 then return false end
      v.direction=one_turn(v.direction,exit)
      v.speed=floor(v.speed/2)
      return false
    end
    if brake and v.speed>M.TAXI*(h.plane_speed or M.PLANE_SPEED) and h.brake_hazard then
      if h.brake_hazard(v,a)==false then return nil,"aircraft_crashed" end
    end
    local limit,hard=M.TAXI,true
    if flag(f,F.NOSPDCLAMP) then limit=M.NONE end
    if flag(f,F.HOLD) then limit,hard=M.HOLD,false end
    if landing then limit,hard=M.APPROACH,false end
    if brake then limit,hard=M.TAXI,false end
    local count=M.speed(v,limit,hard,h.plane_speed)
    if count==0 then return false end
    local nudge=count+3>dist
    if (v.turn_counter or 0)>0 then v.turn_counter=v.turn_counter-1 end
    for i=1,count do
      local px,pz
      if nudge or landing then
        px,pz=v.x+sign(x-v.x),v.z+sign(z-v.z)
      else
        local new=towards(v,x,z)
        if new~=v.direction then
          if slow and (v.consecutive_turns or 0)<8 then
            if (v.turn_counter or 0)==0 or new==v.last_direction then
              if new==v.last_direction then v.consecutive_turns=0
              else v.consecutive_turns=(v.consecutive_turns or 0)+1 end
              v.turn_counter=2*(h.plane_speed or M.PLANE_SPEED)
              v.last_direction,v.direction=v.direction,new
            end
            px,pz=v.x+delta_x[v.direction],v.z+delta_z[v.direction]
          else
            v.speed=floor(v.speed/2)
            v.direction=new
            px,pz=v.x,v.z
          end
        else
          v.consecutive_turns=0
          px,pz=v.x+delta_x[v.direction],v.z+delta_z[v.direction]
        end
      end
      local takeoff=flag(f,F.TAKEOFF)
      v.airborne=takeoff or slow or landing
      if takeoff then v.y=M.flight_height(v,ground_at(a,v,h),true)
      elseif flag(f,F.HOLD) then
        if v.y>ground_at(a,v,h)+150 then v.y=v.y-1 end
      elseif slow and flag(f,F.NOSPDCLAMP) then v.y=M.flight_height(v,ground_at(a,v,h),false) end
      local ground=(a.ground or 0)+1
      if landing then v.y=M.glide(v.y,ground,dist) end
      if brake then v.y=v.y+sign(ground-v.y) end
      v.x,v.z=px,pz
    end
    return false
  end

  -- Source invokes the aircraft event controller twice per simulation tick.
  -- Returns discrete events so callers can handle loading, audio and a new
  -- target airport without conflating the FTA position and actual XY.
  function M.tick(a,v,h)
    h=h or {}
    v.tick=(v.tick or 0)+1
    local events={}
    for _=1,2 do
      if v.stopped or v.loading or v.crashed then break end
      local done,why=M.move(a,v,h)
      if h.position then h.position(_,a.id) end
      if done==nil then return a,events,why end
      if done then
        -- Optional trace of actual AirportClearBlock/AirportMove, not a
        -- second admission or ownership rule. Preserve both intra-tick
        -- transitions when one aircraft clears and another claims later.
        local before
        if h.transition then
          before={loop=_,airport=a.id,flags=a.flags,pos=v.pos,previous=v.previous_pos,state=v.state,
            x=v.x,z=v.z,y=v.y,speed=v.speed,subspeed=v.subspeed}
        end
        local event,next=FTA.arrive(a,v,h)
        if not event then return a,events,next end
        if before then
          before.kind,before.after_flags,before.after_pos,before.after_state=event,a.flags,v.pos,v.state
          before.after_speed,before.after_subspeed=v.speed,v.subspeed
          before.destination=next and next.id
          h.transition(before)
        end
        events[#events+1]=event
        if event=="departed" then
          if not next then return a,events,"destination_missing" end
          a=next
        end
      end
    end
    return a,events
  end
  return M
end
