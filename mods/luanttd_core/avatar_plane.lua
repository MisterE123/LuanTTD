-- Reversible local sightseeing. Use existing airport geometry and art, never
-- register with ATC, write to a campaign, or touch a commercial aircraft.
return function(api,W)
  local mod=core.get_modpath("luanttd_core")
  local F=dofile(mod.."/sightseeing_flight.lua")
  local Small=dofile(mod.."/openttd/airport_small.lua")
  local City=dofile(mod.."/openttd/airport_city.lua")
  local Road=dofile(mod.."/road_motion.lua")
  local Effects=dofile(mod.."/sightseeing_plane_effects.lua")(core)
  local Plane,players={},{}
  local exterior="luanttd_core:sightseeing_plane"
  local third_person=exterior.."_third_person"
  -- Fit the instrument room within the original Sampson body envelope.
  -- Scale around the pilot eye, so the first-person perspective is kept.
  local cockpit_scale=.35
  local seat_offset={x=0,y=.353,z=-.30}
  local cabin="luanttd_core:sightseeing_plane_cockpit"
  local art=api.airframe_art and api.airframe_art[215]
  local Sim,R=api.Sim,api.render
  local function cell(x,z) return Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2)) end
  local function tile(id)
    if api.authority_handoff then return id and R.host_tile(id) end
    return id and api.s.tiles[id]
  end
  local function metadata(id)
    if api.authority_handoff then return R.host_record("stock_small_airports",id) end
    return api.s.stock_small_airports and api.s.stock_small_airports[id]
  end
  local function runway_at_tile(id)
    local t=tile(id)
    local a=t and t.airfield
    local d=a and metadata(a.airport)
    if not d or d.layout~=nil and d.layout~="city" and d.layout~="country" then return end
    local origin=tile(d.origin)
    if not origin or not origin.airfield or origin.airfield.airport~=a.airport then return end
    local x,z=Sim.xy(d.origin)
    return F.runway(d.layout=="city" and City or Small,a.airport,x,z,origin.h,d.layout=="city")
  end
  local function runway(p)
    return runway_at_tile(cell(p.x,p.z))
  end
  local function solids(p)
    local n=core.get_node_or_nil(p)
    if not n or n.name=="ignore" then return nil end
    local def=core.registered_nodes[n.name]
    if not def or n.name=="air" or not def.walkable then return false end
    return n.name
  end
  local samples={{0,0,.015},{.79,0,.19},{-.76,0,.26},{0,.89,.34},{0,-.89,.34},
    {.35,.60,.34},{.35,-.60,.34},{0,0,.51}}
  local function clear(p,heading,r,pitch,bank)
    -- Luanti scenery meshes (e.g. factories and terminals) may have no
    -- native walking collision. Check their authoritative tile footprint
    -- conservatively as well as exposed native solid voxels.
    local sx,cz=math.sin(heading),math.cos(heading)
    local rise,tilt=math.sin(pitch or 0),math.sin(bank or 0)
    for _,o in ipairs(samples) do
      local x,z=p.x+sx*o[1]+cz*o[2],p.z+cz*o[1]-sx*o[2]
      local id=cell(x,z)
      if not id then return false,"Map boundary. E to recover." end
      local t=tile(id)
      if not t then return false,"Terrain still loading. Hold position or press E." end
      local level=R.surface(id,x,z) or t.h+.5
      local y=p.y+o[3]+rise*o[1]-tilt*o[2]
      local height=0
      local a=t.airfield
      if a then
        -- The runway and adjacent final City taxiway row are flat.
        -- Reject the remaining apron/terminal volume conservatively.
        if a.z<(a.layout=="city" and 4 or 2) then height=1.45 end
      elseif t.stock_landmark then height=5
      elseif t.wood then height=3.6
      elseif t.house or t.site or t.stock_industry then height=3.0
      elseif t.station or t.rail_station_id or t.rail_depot_dir~=nil or t.build=="road_depot" then height=1.8
      elseif t.signal or t.tram then height=1.35 end
      local deck=R.host_deck and R.host_deck(id)
      if type(deck)=="number" and y<deck+.6 then height=math.max(height,deck+.60-level) end
      if y<=level+height+.004 then return false,"Terrain or an obstacle ahead. E to recover." end
      local n=solids({x=x,y=y,z=z})
      if n==nil then return false,"Terrain still loading. Hold position or press E." end
      if n then return false,"Terrain or an obstacle ahead. E to recover." end
    end
    return true
  end
  local world={runway_at=runway,clear=clear}
  local function hud(p,q)
    local f=q.flight
    local mode=({ready="Runway ready",takeoff="Takeoff roll",air=f.speed<4.5 and "STALL: add power" or "In flight",
      rollout="Landed · braking",short="Runway ended"})[f.mode]
    local x=q.origin.x+q.origin.dx*q.origin.length/2-f.pos.x
    local z=q.origin.z+q.origin.dz*q.origin.length/2-f.pos.z
    local bearing=(math.atan2(x,z)-f.heading+math.pi)%(2*math.pi)-math.pi
    local way=math.abs(bearing)<.32 and "ahead" or math.abs(bearing)>2.85 and "behind"
      or bearing<0 and "left" or "right"
    local text=("%s  ·  %d km/h  ·  Power %d%%  ·  Height %+.0f m  ·  Runway %.0f m %s"):
      format(mode,math.floor(f.speed*18+.5),math.floor(f.throttle*100+.5),(f.pos.y-q.origin.y)*5,
        F.distance(f,q.origin)*5,way)
    if text~=q.text then q.text=text;p:hud_change(q.status,"text",text) end
    local hint=q.blocked or (f.mode=="air" and "Landing: line up with the runway, descend gently at 55–110 km/h."
      or f.mode=="rollout" and "Safe landing. Press E for a new takeoff or right-click to leave."
      or "Hold W to build power and Space to lift off. The runway is short.")
    if hint~=q.hint_text then q.hint_text=hint;p:hud_change(q.hint,"text",hint) end
  end
  local function aim(p,f)
    p:set_look_horizontal((-f.heading)%(2*math.pi))
    p:set_look_vertical(.025-f.pitch)
  end
  local function pose(p,q,snap)
    local f=q.flight
    local rotation={x=-f.pitch,y=Road.nose_yaw(f.heading),z=-f.bank}
    -- First-person in Luanti follows the actual attachment origin.
    -- OBJ cockpit coordinates are exported relative to this same seat.
    local seat=vector.add(f.pos,vector.rotate(seat_offset,rotation))
    for _,row in ipairs({{q.object,seat},{q.exterior,f.pos}}) do
      local object,at=row[1],row[2]
      if snap then object:set_pos(at) else object:move_to(at,true) end
      object:set_rotation(rotation)
    end
    if snap then aim(p,f) end
  end
  local function release(q,p)
    Effects.stop(q.audio)
    if p then
      if p:get_attach()==q.object then p:set_detach() end
      for _,id in ipairs({q.status,q.hint,q.controls}) do p:hud_remove(id) end
    end
    if q.shell and q.shell:get_pos() then q.shell:remove() end
    if q.object and q.object:get_pos() then q.object:remove() end
    if q.exterior and q.exterior:get_pos() then q.exterior:remove() end
  end
  function Plane.leave(n)
    local q=players[n]
    if not q then return end
    players[n]=nil
    release(q,core.get_player_by_name(n))
  end
  local function text(p,y,color,content)
    return p:hud_add({type="text",position={x=.5,y=y},alignment={x=0,y=0},number=color,z_index=105,text=content})
  end
  local function observe_exterior(n,q)
    local watchers={}
    for _,p in ipairs(core.get_connected_players()) do
      if p:get_player_name()~=n then watchers[p:get_player_name()]=true end
    end
    if q.exterior and q.exterior:get_pos() then q.exterior:set_observers(watchers) end
  end
  core.register_on_joinplayer(function()
    for n,q in pairs(players) do observe_exterior(n,q) end
  end)
  function Plane.board(p,targeted)
    local n=p:get_player_name()
    if players[n] then return false,"Right-click or use /plane to leave this cockpit first." end
    if not art then return false,"The sightseeing plane is missing its native model." end
    local strip=runway_at_tile(targeted)
    if not strip then return false,"Aim at a built Country or City Airport to enter the sightseeing plane." end
    local f=F.start(strip)
    local safe,why=clear(f.pos,f.heading,strip)
    if not safe then return false,why or "The airport runway is not clear." end
    local avatar,note=W.begin_avatar(p,"plane")
    if not avatar then return false,note end
    local q={flight=f,origin=strip}
    q.object=core.add_entity(f.pos,cabin)
    q.exterior=core.add_entity(f.pos,exterior)
    q.shell=q.exterior and core.add_entity(f.pos,third_person)
    if not q.object or not q.exterior or not q.shell then
      release(q,p);W.end_avatar(p,"plane");return false,"Could not attach to the aircraft yet."
    end
    -- Only the pilot sees the cabin. Luanti's native camera mode shows
    -- its exterior child in chase view, without ever occluding the glass
    -- in first person. Other observers retain the normal exterior.
    q.object:set_observers({[n]=true})
    q.shell:set_observers({[n]=true})
    observe_exterior(n,q)
    p:set_physics_override({gravity=0,speed=0,jump=0,sneak=false,speed_walk=0,speed_crouch=0})
    p:set_properties({eye_height=.08*cockpit_scale,visual="sprite",textures={"bl_sightseeing_hidden_player.png"},
      visual_size={x=.001,y=.001,z=.001}})
    p:set_eye_offset({x=0,y=0,z=0},{x=0,y=8,z=0},{x=0,y=9,z=0})
    p:set_attach(q.object,"",{x=0,y=0,z=0},{x=0,y=0,z=0})
    q.shell:set_attach(p,"",vector.multiply(seat_offset,-10),{x=0,y=0,z=0},false)
    q.status=text(p,.118,0x25281c,"")
    q.hint=text(p,.165,0x26312c,"")
    q.controls=text(p,.212,0x26312c,"W/S power · A/D bank · Space/Shift pitch · E recover · Right-click or /plane exit")
    players[n]=q
    q.audio=Effects.start(n)
    pose(p,q,true)
    hud(p,q)
    return true,"Sightseeing at the "..strip.name..". This does not affect the airline."
  end
  function Plane.toggle(p)
    local n=p:get_player_name()
    if players[n] then
      Plane.leave(n)
      W.end_avatar(p,"plane")
      return true,"Returned to the builder camera."
    end
    return Plane.board(p,W.target(p))
  end
  function Plane.step(p,_,keys,dt)
    local n=p:get_player_name()
    local q=players[n]
    if not q then return end
    if not q.object:get_pos() or not q.exterior:get_pos() or not q.shell:get_pos() or p:get_attach()~=q.object then
      Plane.toggle(p)
      core.chat_send_player(n,"Aircraft view lost. Returned to the builder camera.")
      return
    end
    local reset=keys.aux1 and not q.reset
    q.reset=keys.aux1
    if reset then
      local origin=runway(q.origin)
      local f=origin and origin.id==q.origin.id and F.start(origin)
      if f and clear(f.pos,f.heading,origin) then
        q.flight,q.blocked=f,nil;pose(p,q,true);hud(p,q);Effects.update(q.audio,f,.2)
      else
        Plane.toggle(p)
        core.chat_send_player(n,"The departure runway is no longer available. Returned to the builder camera.")
      end
      return
    end
    if q.flight.mode=="air" and q.flight.pos.y>95 then
      keys={up=keys.up,down=keys.down,left=keys.left,right=keys.right,sneak=true}
    end
    if not q.blocked then
      local previous=q.flight.pitch
      local d,why=F.step(q.flight,keys,dt,world)
      q.blocked=why
      if math.abs(d)>.0001 then p:set_look_horizontal((p:get_look_horizontal()-d)%(2*math.pi)) end
      local pitch=q.flight.pitch-previous
      if math.abs(pitch)>.0001 then
        p:set_look_vertical(math.max(-1.4,math.min(1.4,p:get_look_vertical()-pitch)))
      end
      pose(p,q,false)
    elseif q.blocked:find("still loading",1,true) then
      -- Retry through a freshly loaded sector without resetting a flight.
      q.blocked=nil
    end
    hud(p,q)
    Effects.update(q.audio,q.flight,dt)
  end
  if art then
    local function register_exterior(id)
      core.register_entity(id,{initial_properties={physical=false,pointable=false,collide_with_objects=false,
      static_save=false,visual="mesh",mesh=art.mesh,textures={art.atlas},shaded=true,backface_culling=true,
      visual_size={x=art.scale,y=art.scale,z=art.scale}}})
    end
    register_exterior(exterior)
    register_exterior(third_person)
    core.register_entity(cabin,{initial_properties={physical=false,pointable=false,collide_with_objects=false,
      static_save=false,visual="mesh",mesh="bl_sightseeing_plane_cockpit.obj",
      textures={"bl_sightseeing_plane_cockpit_atlas.png"},shaded=false,backface_culling=false,
      visual_size={x=cockpit_scale,y=cockpit_scale,z=cockpit_scale}}})
  end
  core.register_chatcommand("plane",{description="Aim at a built airport and fly a sightseeing plane; repeat to exit.",
    func=function(n)
      local p=core.get_player_by_name(n)
      if not p then return false,"Join the world before flying." end
      return Plane.toggle(p)
    end})
  return Plane
end
