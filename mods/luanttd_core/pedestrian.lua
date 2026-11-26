-- Street-level camera uses Luanti's local walking and collision prediction.
-- Authoritative simulation remains separate: pedestrians don't buy/build
-- or affect any route, vehicle reservation, or cargo.
local unpack_values=table.unpack or unpack
-- House doors are .335 nodes tall, with their thresholds .05 above
-- tile level. Size the walker to fit under those doors, with eyes near
-- their glazing rather than the upper window/roof line.
local scale=.57
local P={eye_height=.462*scale,visual_height=.511*scale,visual_scale=scale}
-- Nominal adult stature 1.75 m; model height is in world nodes.
-- Keep the model-scale gait ratios, with a 1.5x sightseeing pace.
P.travel_pace=1.5
P.walk_nodes_per_second=P.visual_height*1.4/1.75*P.travel_pace
P.run_nodes_per_second=P.visual_height*3.2/1.75*P.travel_pace
local function movement_setting(name,default)
  local n=core and core.settings and core.settings.get and tonumber(core.settings:get("movement_speed_"..name))
  return n and n>0 and n or default
end
local slow=movement_setting("walk",4)
local fast=movement_setting("fast",20)
local crouch=movement_setting("crouch",1.35)
P.walk_speed,P.run_speed=P.walk_nodes_per_second/slow,P.run_nodes_per_second/slow
local hidden_texture="bl_sightseeing_hidden_player.png"
local model="bl_street_pedestrian.glb"
local idle,walking={x=0,y=1},{x=2,y=14}
local walk_rate=15
local step_height,shore_error,bank_recovery_limit=.18,.035,.28
local function copy(value)
  if type(value)~="table" then return value end
  local t={}
  for k,v in pairs(value) do t[k]=copy(v) end
  return t
end

local function position(p,pos,yaw,pitch)
  -- Keep the pose consistent when sending the transition's absolute packet.
  p:set_look_horizontal(yaw)
  p:set_look_vertical(pitch)
  p:set_pos(pos)
  local v=p:get_velocity()
  if math.abs(v.x)+math.abs(v.y)+math.abs(v.z)>.05 then
    p:add_velocity({x=-v.x,y=-v.y,z=-v.z})
  end
end

function P.hide_builder(p)
  -- PlayerSAO ignores is_visible=false on some engine versions. A fully
  -- transparent sprite works in all camera views and for other clients
  -- without affecting the local eye height or flight physics.
  -- The engine binds zoom locally (Z by default). Keep a nonzero camera
  -- FOV for the same key in overview, walking, piloting and passenger modes.
  p:set_properties({visual="sprite",mesh="",textures={hidden_texture},zoom_fov=24,
    visual_size={x=.001,y=.001,z=.001},nametag_color={r=255,g=255,b=255,a=0}})
end

function P.capture(p)
  local props=p:get_properties()
  local avatar={}
  for _,key in ipairs({"eye_height","collisionbox","stepheight","visual","mesh","textures",
      "visual_size","is_visible","backface_culling","use_texture_alpha"}) do avatar[key]=copy(props[key]) end
  return {pos=copy(p:get_pos()),yaw=p:get_look_horizontal(),pitch=p:get_look_vertical(),
    props=avatar,physics=copy(p:get_physics_override()),flags=copy(p:hud_get_flags()),
    eye=copy({p:get_eye_offset()}),animation=p.get_animation and copy({p:get_animation()}),
    local_anim=p.get_local_animation and copy({p:get_local_animation()})}
end

function P.restore_controls(p,saved)
  p:set_properties(saved.props)
  p:set_physics_override(saved.physics)
  p:set_eye_offset(saved.eye[1],saved.eye[2],saved.eye[3])
  if saved.animation then p:set_animation(unpack_values(saved.animation)) end
  if saved.local_anim then p:set_local_animation(unpack_values(saved.local_anim)) end
  local v=p:get_velocity()
  if math.abs(v.x)+math.abs(v.y)+math.abs(v.z)>.05 then
    p:add_velocity({x=-v.x,y=-v.y,z=-v.z})
  end
end

function P.restore_pose(p,saved)
  p:hud_set_flags(saved.flags)
  position(p,saved.pos,saved.yaw,saved.pitch)
end

-- Luanti meshes don't have arbitrary polygon collision. Closely spaced
-- thin steps use the same OpenTTD height field as the visible mesh.
-- Sample the low edge to avoid an invisible hurdle at the foot of a grade.
function P.slope_box(sample,shape,include_flat)
  local fixed={}
  -- Simple ramps have one axis with constant height; eight strips are
  -- identical to 64 squares and cheaper for native collision scanning.
  local nx=(shape==0 or shape==6 or shape==9) and 1 or 8
  local nz=(shape==0 or shape==3 or shape==12) and 1 or 8
  for z=0,nz-1 do for x=0,nx-1 do
    local u,v=x/nx,z/nz
    local w,q=(x+1)/nx,(z+1)/nz
    local y=math.min(sample(u,v,shape),sample(u,q,shape),
      sample(w,v,shape),sample(w,q,shape))-.50
    if include_flat or y>-.50 then
      fixed[#fixed+1]={u*2-.5,-.51,v*2-.5,w*2-.5,y,q*2-.5}
    end
  end end
  return {type="fixed",fixed=fixed}
end

-- Player velocity arrives in packets; apply a small acceleration-limited
-- trim rather than overwriting the client's vertical velocity every step.
function P.swim_impulse(error,velocity,dt)
  local function clamp(a,lo,hi) return math.min(hi,math.max(lo,a)) end
  dt=clamp(dt or .09,0,.10)
  local wanted=clamp(error*3.2,-.78,.95)
  local change=(wanted-velocity)*(1-math.exp(-7*dt))
  if math.abs(error)<.018 and math.abs(velocity)<.050 then return 0 end
  return clamp(change,-3.8*dt,4.8*dt)
end

function P.new(api)
  local Sim,S=api.Sim,api.s
  local function cell(id)
    if api.authority_handoff and api.render.host_tile then return api.render.host_tile(id) end
    return S.tiles[id]
  end
  local W={}
  local function tile_at(x,z) return Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2)) end
  local function blocked(t)
    return not t or t.stock_void or t.site or t.house or t.stock_landmark or t.stock_industry
      or t.build=="road_depot" or t.rail_depot_dir or t.road_bridge_id or
      t.road_tunnel_id or t.rail_span_id or t.airfield or (t.ship and t.ship.kind~="buoy" and t.ship.kind~="dock")
  end
  local function waterline(id,t,x,z)
    if blocked(t) then return end
    if api.render.walk_waterline then return api.render.walk_waterline(id,x,z) end
    if t.terrain=="water" or t.stock_canal or t.water_class=="river" then return t.h+.5 end
  end
  local function surface(id,x,z)
    local t=cell(id)
    if api.render.uses_slope(id) then return api.render.surface(id,x,z) end
    return t.h+.5
  end
  local function clamp(a,lo,hi) return math.min(hi,math.max(lo,a)) end
  local function point(id,x,z,aim_y)
    if not id then return end
    local u,v=Sim.xy(id)
    x=x and clamp(x,u*2-.25,u*2+1.25) or u*2+.5
    z=z and clamp(z,v*2-.25,v*2+1.25) or v*2+.5
    local deck=api.render.walk_bridge_surface and api.render.walk_bridge_surface(id,x,z,aim_y)
    if deck then return {x=x,y=deck+.045,z=z} end
    local dock=api.render.walk_dock_surface and api.render.walk_dock_surface(id,x,z)
    if dock and (not aim_y or math.abs(dock-aim_y)<.30) then return {x=x,y=dock+.045,z=z} end
    local arena=api.render.walk_stadium_surface and api.render.walk_stadium_surface(id,x,z)
    if arena then return {x=x,y=arena+.045,z=z} end
    if cell(id) and cell(id).rail_station_id and api.render.walk_platform_landings then
      local best,dist
      local ground=surface(id,x,z)
      for _,p in ipairs(ground and api.render.walk_platform_landings(id,aim_y or ground) or {}) do
        local d=(p.x-x)^2+(p.z-z)^2
        if not dist or d<dist then best,dist=p,d end
      end
      if best and (not aim_y or dist<=.4) then return best end
    end
    if blocked(cell(id)) then return end
    local water=waterline(id,cell(id),x,z)
    local y=water and water-.18 or surface(id,x,z)
    if not y then return end
    return {x=x,y=y+(water and 0 or .045),z=z},water
  end
  function W.at(tile,hit)
    if tile then return point(tile,hit and hit.x,hit and hit.z,hit and hit.y) end
  end
  function W.find(p,tile,hit)
    local direct,water=W.at(tile,hit)
    if direct then return direct,water end
    local focus=hit or p:get_pos()
    if tile and not hit then local x,z=Sim.xy(tile);focus={x=x*2+.5,z=z*2+.5} end
    local x,z=math.floor((focus.x+.5)/2),math.floor((focus.z+.5)/2)
    local best,score,wet
    for dz=-7,7 do for dx=-7,7 do
      local id=Sim.id(x+dx,z+dz)
      local land,depth=point(id)
      if land then
        local t=cell(id)
        local road=t.build=="road" or t.road_town or t.town_road
        local distance=(land.x-focus.x)^2+(land.z-focus.z)^2+(road and 0 or 12)+(depth and 24 or 0)
        if not score or distance<score then best,score,wet=land,distance,depth end
      end
    end end
    return best,wet
  end
  -- Bound both the search and the vertical drop. Don't move a rider
  -- through a hillside, down from flight, or back across the map.
  function W.ride_landing(mode,focus)
    if not focus then return end
    local x,z=math.floor((focus.x+.5)/2),math.floor((focus.z+.5)/2)
    local best,score
    local function offer(pos,priority)
      if not pos then return end
      local dx,dy,dz=pos.x-focus.x,pos.y-focus.y,pos.z-focus.z
      local distance=dx*dx+dz*dz
      if distance>36 or dy>1.10 or dy< -1.20 then return end
      if core and core.get_node_or_nil then
        -- Never place feet in an unloaded mapblock or a plain wall.
        local cube={x=math.floor(pos.x+.5),y=math.floor(pos.y+.56),z=math.floor(pos.z+.5)}
        local node=core.get_node_or_nil(cube)
        if not node then return end
        local def=core.registered_nodes[node.name]
        if def and def.walkable and def.drawtype=="normal" then return end
      end
      local cost=priority+distance+dy*dy*4
      if not score or cost<score then best,score=pos,cost end
    end
    local render=api.render
    for dz=-3,3 do for dx=-3,3 do
      local id=Sim.id(x+dx,z+dz)
      local t=id and cell(id)
      if t then
        local cx,cz=2*(x+dx)+.5,2*(z+dz)+.5
        if mode=="rail" and render.walk_platform_landings then
          for _,p in ipairs(render.walk_platform_landings(id,focus.y) or {}) do offer(p,0) end
        end
        if mode=="ship" and render.walk_dock_surface then
          local y=render.walk_dock_surface(id,cx,cz,focus.y)
          if y then offer({x=cx,y=y+.045,z=cz},0) end
        end
        if not blocked(t) and not t.rail_station_id and not t.rail_tracks then
          local p,wet=point(id,cx,cz,focus.y)
          if p and not wet then
            local road=t.build=="road" or t.town_road or t.road_town or t.stock_town_road or t.road_bits
            offer(p,road and 42 or 85)
          end
        end
      end
    end end
    return best
  end

  local function gait(p,state,swimming,running)
    local changed=state.swimming~=swimming
    if not changed and state.running==running then return end
    state.swimming,state.running=swimming,running
    local speed=swimming and .27*P.travel_pace or running and P.run_speed or P.walk_speed
    p:set_physics_override({gravity=swimming and 0 or 1,jump=swimming and 0 or .56,
      sneak=not swimming,speed_walk=speed,speed_fast=speed*slow/fast,
      speed_crouch=P.walk_nodes_per_second*.55/crouch,acceleration_air=swimming and 2.8 or 1})
    if changed and state.hint and p.hud_change then
      p:hud_change(state.hint,"text",swimming
        and "SWIMMING  ·  Space to surface  ·  Inventory: leave Walk"
        or "Walk  ·  E to run  ·  Click a vehicle to board  ·  Inventory: leave Walk")
    end
  end
  local function retreat_from_bank(p,state,at,speed)
    local back=state.last_wet
    if back then
      local id=tile_at(back.x,back.z)
      local level=waterline(id,id and cell(id),back.x,back.z)
      if level then
        -- Keep the stroke and camera, but stop the part of the velocity
        -- driving into the bank. Only return to the last sampled water;
        -- never search for (or hoist onto) a distant dry landing.
        local dx,dz=at.x-back.x,at.z-back.z
        local length=math.sqrt(dx*dx+dz*dz)
        local y=clamp(at.y,level-.42,level+.14)
        p:set_pos({x=back.x,y=y,z=back.z})
        if length>1e-5 then
          dx,dz=dx/length,dz/length
          local along=speed.x*dx+speed.z*dz
          if along>0 then p:add_velocity({x=-along*dx,y=0,z=-along*dz}) end
        end
        return
      end
    end
    -- Keep the existing out-of-world recovery if even the water sample
    -- disappeared (for example, a dock was built on it meanwhile).
    if state.last_safe then
      position(p,state.last_safe,p:get_look_horizontal(),p:get_look_vertical())
    end
  end
  local function settle_feet(p,at,speed,ground)
    -- Keep XZ, camera and the ongoing stroke. Do not add walk speed.
    local feet={x=at.x,y=ground+.01,z=at.z}
    p:set_pos(feet)
    if speed.y<0 then p:add_velocity({x=0,y=-speed.y,z=0}) end
    return feet
  end
  function W.enter(p,state,land,water,yaw,pitch)
    state.last_safe=land
    state.last_wet=water and land or nil
    state.bank_footing=nil
    state.step_height=step_height
    p:set_eye_offset()
    p:set_properties({eye_height=P.eye_height,collisionbox={-.064,0,-.064,.064,.32,.064},stepheight=step_height,
      visual="mesh",mesh=model,textures={"bl_street_pedestrian_atlas.png"},
      visual_size={x=scale,y=scale,z=scale},backface_culling=false})
    p:set_physics_override({speed=1,acceleration_default=1})
    if p.set_local_animation then p:set_local_animation(idle,walking,idle,walking,walk_rate) end
    if p.set_animation then p:set_animation(idle,walk_rate,.1,true) end
    state.walking,state.swimming,state.running=false,nil,nil
    gait(p,state,water~=nil,false)
    position(p,land,yaw or state.saved.yaw,pitch or 0)
  end
  function W.step(p,state,keys,dt)
    local at=p:get_pos()
    local speed=p:get_velocity()
    local moving=speed.x*speed.x+speed.z*speed.z>.07^2
    local id=tile_at(at.x,at.z)
    local t=id and cell(id)
    -- Platform coping is .28 nodes high, or up to .43 on elevated
    -- guideway stations. Only increase step-up inside station tiles;
    -- normal fences and walls keep the smaller pedestrian step height.
    local step=t and t.rail_station_id and ((t.rail_type or 0)>=2 and .45 or .30) or step_height
    if (state.step_height or step_height)~=step then
      state.step_height=step
      p:set_properties({stepheight=step})
    end
    local deck=id and api.render.walk_bridge_surface and api.render.walk_bridge_surface(id,at.x,at.z,at.y)
    if not deck and id and api.render.walk_dock_surface then
      deck=api.render.walk_dock_surface(id,at.x,at.z,at.y)
    end
    -- A sampled deck may be close above the swimmer. Its underside
    -- is not a bank: continue using the water beneath it.
    local under_deck=state.swimming and deck and deck-at.y>step_height
    local water=(not deck or under_deck) and waterline(id,t,at.x,at.z)
    if water and at.y<(water+(state.swimming and .37 or .18)) then
      state.bank_footing=nil
      gait(p,state,true,false)
      -- Keep horizontal input and collision local to Luanti. Only bias
      -- vertical velocity toward the mean surface; Space strokes upward
      -- into the walkable bank. Bounded correction avoids teleport jitters.
      local goal=water+((keys and keys.jump) and .14 or -.18)
      local dy=P.swim_impulse(goal-at.y,speed.y,dt)
      if math.abs(dy)>.016 then p:add_velocity({x=0,y=dy,z=0}) end
      if at.y>=water-.42 then state.last_safe,state.last_wet=at,at end
    else
      local ground=(not under_deck and deck) or
        (not water and not under_deck and id and not blocked(t) and surface(id,at.x,at.z))
      local bank_footing=state.bank_footing
      if state.swimming and not water then
        -- Coast classification uses XZ, so a packet can be on the dry
        -- side even while the *feet* are still below the native terrain.
        -- Accept only an ordinary-sized step onto a real walk surface.
        if not ground or ground-at.y>step_height then
          retreat_from_bank(p,state,at,speed)
          return
        end
        if ground-at.y>shore_error then
          -- Reconcile once across the low-edge strips of the native
          -- nodebox ramp.
          at=settle_feet(p,at,speed,ground)
        end
        if not deck and t.coastal_water then bank_footing=at end
      elseif bank_footing and ground and not deck then
        -- Keep the nearest sound step until leaving the mixed shore tile.
        -- Native collision approximates this ramp with 1/8-tile steps; a
        -- stale falling packet must not put a newly dry walker underneath.
        if ground-at.y>bank_recovery_limit then
          p:set_pos(bank_footing)
          if speed.y<0 then p:add_velocity({x=0,y=-speed.y,z=0}) end
          return
        elseif ground-at.y>.13 then
          at=settle_feet(p,at,speed,ground)
        end
      end
      gait(p,state,false,keys and keys.aux1==true or false)
      state.last_wet=nil
      state.bank_footing=bank_footing and ground and not deck and t.coastal_water
        and {x=at.x,y=ground+.01,z=at.z} or nil
      if ground and at.y>=ground-.08 and at.y-ground<.32 then state.last_safe=at
      elseif at.y<-.8 and state.last_safe then position(p,state.last_safe,p:get_look_horizontal(),p:get_look_vertical()) end
    end
    local rate=state.running and walk_rate*1.65 or walk_rate
    if state.walking~=moving or state.animation_rate~=rate then
      if p.set_animation then p:set_animation(moving and walking or idle,rate,.1,true) end
      if p.set_local_animation then p:set_local_animation(idle,walking,idle,walking,rate) end
      state.walking,state.animation_rate=moving,rate
    end
  end
  return W
end
return P
