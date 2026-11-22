-- SPDX-License-Identifier: GPL-2.0-only
-- Two fixed-wing Sampson U52 actors on the one original AT_SMALL airport
-- flags word. OpenTTD 14.1 CallVehicleTicks runs the first vehicle's
-- complete Tick (each of its two controller passes) before the next.
-- Loading readiness, platform cargo/fare and construction remain host-owned.
return function(Sim,Small,Motion,Terrain)
  local G={VERSION=1,engine={id=215,visual="bayshore_trimotor",passengers=25,mail=4,
    acceleration=18,max_speed=473}}
  local floor,min,max=math.floor,math.min,math.max

  function G.current(s)
    local pair=s.airport_ground_pair
    if pair and pair.version==G.VERSION then return pair end
  end
  function G.actor(s,id)
    local pair=G.current(s)
    for _,a in ipairs(pair and pair.actors or {}) do if a.id==id then return a end end
  end
  function G.protects_airfield(s,id)
    local pair=G.current(s)
    return not not (pair and pair.fields[id])
  end

  local function fingerprint(field)
    return {id=field.id,owner=field.owner,x=field.x,z=field.z,width=field.width,height=field.height,
      rotation=field.rotation,ground=field.ground,origin=field.origin}
  end
  local function valid_field(field,id,owner)
    return field and field.id==id and field.owner==owner and field.rotation==0 and
      field.width==Small.W and field.height==Small.H and type(field.tiles)=="table" and
      #field.tiles==Small.W*Small.H
  end
  function G.start(s,owner,originA,originB,shared)
    if s.airport_ground_pair or s.airport_pilot then return nil,"AIRSPACE_ALREADY_HAS_PREVIEW" end
    if not owner or not (s.companies and s.companies[owner] and s.corner_grid) then
      return nil,"OWNED_AIRFIELD_AND_TERRAIN_REQUIRED"
    end
    local airports=s.stock_small_airports or {}
    local a,b,c=airports[originA],airports[originB],airports[shared]
    if not (valid_field(a,originA,owner) and valid_field(b,originB,owner) and valid_field(c,shared,owner))
        or a==b or a==c or b==c then return nil,"THREE_DISTINCT_OWN_COUNTRY_AIRFIELDS_REQUIRED" end
    if a.flags~=0 or b.flags~=0 or c.flags~=0 then return nil,"AIRFIELD_OCCUPIED" end
    local pair={version=G.VERSION,owner=owner,shared=shared,ticks=0,
      fields={[a.id]=fingerprint(a),[b.id]=fingerprint(b),[c.id]=fingerprint(c)},actors={}}
    for id,field in ipairs({a,b}) do
      pair.actors[id]={id=id,stock_engine=G.engine.id,owner=owner,origin=field.id,destination=shared,
        target=field.id,arrivals=0,departures=0,phase="hangar",
        vehicle=Small.new(field,{owner=owner,order={kind="station",id=shared},
          max_speed=G.engine.max_speed,acceleration=G.engine.acceleration})}
    end
    s.airport_ground_pair=pair
    return pair
  end

  -- The host may advance a finished stock loading visit. With no cargo
  -- service mounted, the only departure from the hub is an explicit new
  -- order. No arbitrary elapsed time or whole-airfield lock is applied.
  function G.request_return(s,owner,id)
    local p=G.actor(s,id)
    if not p or p.owner~=owner then return nil,"SELECT_OWN_AIRCRAFT" end
    if p.phase~="terminal" or not p.vehicle.loading or p.last_airfield~=p.destination then
      return nil,"AIRCRAFT_NOT_AT_SHARED_TERMINAL"
    end
    p.return_requested=true
    return true
  end
  local function check_fields(s,pair)
    local airports=s.stock_small_airports
    if not airports then return false end
    for id,original in pairs(pair.fields) do
      local field=airports[id]
      if not valid_field(field,id,pair.owner) then return false end
      for key,value in pairs(original) do if field[key]~=value then return false end end
    end
    return true
  end

  function G.terrain_under(s,x,z)
    local tx=max(1,min(Sim.W,floor(x/16)))
    local tz=max(1,min(Sim.H,floor(z/16)))
    return Terrain.corner(s.corner_grid,tx,tz)*8
  end
  function G.advance(s,callbacks,world_tick)
    local pair=G.current(s)
    if not pair or pair.failure then return nil,pair and pair.failure or "NO_AIRCRAFT_PAIR" end
    if world_tick and pair.last_world_tick and world_tick<=pair.last_world_tick then
      return nil,"AIRCRAFT_TICK_ALREADY_PROCESSED"
    end
    if not s.corner_grid or not check_fields(s,pair) then
      pair.failure="AIRFIELD_CHANGED"
      return nil,pair.failure -- do not clear any stock bits after a bad edit
    end
    local airports=s.stock_small_airports
    local events={}
    pair.ticks=pair.ticks+1
    pair.last_world_tick=world_tick or pair.last_world_tick
    local hooks={airports=airports,plane_speed=Motion.PLANE_SPEED,terrain_height=function(x,z)
      return G.terrain_under(s,x,z)
    end}
    for _,p in ipairs(pair.actors) do
      local a=airports[p.target]
      local v=p.vehicle
      if p.phase=="terminal" and v.loading and (p.return_requested or callbacks and callbacks.leave and callbacks.leave(p,a)) then
        v.loading,p.return_requested=nil,nil
        v.order={kind="station",id=p.origin}
        p.phase="taxi"
      end
      hooks.position=callbacks and callbacks.position and function(pass,field)
        callbacks.position(p,pass,field)
      end or nil
      hooks.transition=function(e)
        e.vehicle,e.tick,e.world_tick=p.id,pair.ticks,world_tick
        events[#events+1]=e
      end
      local next,result,why=Motion.tick(a,v,hooks)
      if why then
        p.phase,p.failure,pair.failure="blocked",why,why
        return events,why
      end
      p.target=next.id
      if p.phase=="hangar" and not v.hidden then p.phase="taxi" end
      for _,event in ipairs(result) do
        if event=="departed" then p.departures=p.departures+1;p.phase="flying"
        elseif event=="hold" then p.phase="holding"
        elseif event=="approach" then p.phase="approach"
        elseif event=="touchdown" then p.phase="rollout"
        elseif event=="terminal" then
          local tile=Sim.id(floor(v.x/16),floor(v.z/16))
          local ref=tile and s.tiles[tile] and s.tiles[tile].airfield
          if not ref or ref.airport~=next.id then
            p.phase,p.failure,pair.failure="blocked","INVALID_TERMINAL_TILE","INVALID_TERMINAL_TILE"
            return events,p.failure
          end
          p.arrivals=p.arrivals+1
          p.last_airfield,p.last_terminal_tile=next.id,tile
          p.phase=next.id==p.origin and "returned" or "terminal"
          if callbacks and callbacks.arrive then
            local ok,problem=callbacks.arrive(p,tile,next)
            if not ok then
              p.phase,p.failure,pair.failure="blocked",problem or "LOADING_VISIT_FAILED",problem or "LOADING_VISIT_FAILED"
              return events,p.failure
            end
          end
        end
      end
    end
    return events
  end

  function G.pose(p)
    if not p or p.vehicle.hidden then return end
    local v=p.vehicle
    return {x=v.x/8-.5,y=(v.y-1)/8+.5,z=v.z/8-.5},(v.direction-3)*math.pi/4
  end
  return G
end
