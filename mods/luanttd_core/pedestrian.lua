-- Street-level camera uses Luanti's local walking and collision prediction.
-- Authoritative simulation remains separate: pedestrians don't buy/build
-- or affect any route, vehicle reservation, or cargo.
local unpack_values=table.unpack or unpack
-- House doors are .335 nodes tall, with their thresholds .05 above
-- tile level. Size the walker to fit under those doors, with eyes near
-- their glazing rather than the upper window/roof line.
local scale=.57
local P={eye_height=.462*scale,visual_height=.511*scale,visual_scale=scale}
local hidden_texture="bl_sightseeing_hidden_player.png"
local model="bl_street_pedestrian.glb"
local idle,walking={x=0,y=1},{x=2,y=14}
local walk_rate=15
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
  p:set_properties({visual="sprite",mesh="",textures={hidden_texture},
    visual_size={x=.001,y=.001,z=.001},nametag_color={r=255,g=255,b=255,a=0}})
end

function P.capture(p)
  local props=p:get_properties()
  local avatar={}
  for _,key in ipairs({"eye_height","collisionbox","stepheight","visual","mesh","textures",
      "visual_size","is_visible","backface_culling"}) do avatar[key]=copy(props[key]) end
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
function P.slope_box(sample,shape)
  local fixed={}
  -- Simple ramps have one axis with constant height; eight strips are
  -- identical to 64 squares and cheaper for native collision scanning.
  local nx=(shape==6 or shape==9) and 1 or 8
  local nz=(shape==3 or shape==12) and 1 or 8
  for z=0,nz-1 do for x=0,nx-1 do
    local u,v=x/nx,z/nz
    local w,q=(x+1)/nx,(z+1)/nz
    local y=math.min(sample(u,v,shape),sample(u,q,shape),
      sample(w,v,shape),sample(w,q,shape))-.50
    if y>-.50 then
      fixed[#fixed+1]={u*2-.5,-.51,v*2-.5,w*2-.5,y,q*2-.5}
    end
  end end
  return {type="fixed",fixed=fixed}
end

function P.new(api)
  local Sim,S=api.Sim,api.s
  local function cell(id)
    if api.authority_handoff and api.render.host_tile then return api.render.host_tile(id) end
    return S.tiles[id]
  end
  local W={}
  local function tile_at(x,z) return Sim.id(math.floor((x+.5)/2),math.floor((z+.5)/2)) end
  local function wet(t)
    return not t or t.stock_void or t.terrain=="water" or t.coastal_water or
      t.stock_canal or t.water_class=="river" or (t.ship and t.ship.water_ground)
  end
  local function blocked(t)
    return wet(t) or t.site or t.house or t.stock_landmark or t.stock_industry
      or t.build=="road_depot" or t.rail_depot_dir or t.road_bridge_id or
      t.road_tunnel_id or t.rail_span_id or t.airfield
  end
  local function surface(id,x,z)
    local t=cell(id)
    if api.render.uses_slope(id) then return api.render.surface(id,x,z) end
    return t.h+.5
  end
  local function clamp(a,lo,hi) return math.min(hi,math.max(lo,a)) end
  local function point(id,x,z)
    if not id or blocked(cell(id)) then return end
    local u,v=Sim.xy(id)
    x=x and clamp(x,u*2-.25,u*2+1.25) or u*2+.5
    z=z and clamp(z,v*2-.25,v*2+1.25) or v*2+.5
    return {x=x,y=surface(id,x,z)+.045,z=z}
  end
  function W.find(p,tile,hit)
    local direct=tile and point(tile,hit and hit.x,hit and hit.z)
    if direct then return direct end
    local focus=hit or p:get_pos()
    if tile and not hit then local x,z=Sim.xy(tile);focus={x=x*2+.5,z=z*2+.5} end
    local x,z=math.floor((focus.x+.5)/2),math.floor((focus.z+.5)/2)
    local best,score
    for dz=-7,7 do for dx=-7,7 do
      local id=Sim.id(x+dx,z+dz)
      local land=point(id)
      if land then
        local t=cell(id)
        local road=t.build=="road" or t.road_town or t.town_road
        local distance=(land.x-focus.x)^2+(land.z-focus.z)^2+(road and 0 or 12)
        if not score or distance<score then best,score=land,distance end
      end
    end end
    return best
  end
  function W.enter(p,state,land)
    state.last_dry=land
    p:set_eye_offset()
    p:set_properties({eye_height=P.eye_height,collisionbox={-.064,0,-.064,.064,.32,.064},stepheight=.28,
      visual="mesh",mesh=model,textures={"bl_street_pedestrian_atlas.png"},
      visual_size={x=scale,y=scale,z=scale},backface_culling=false})
    p:set_physics_override({gravity=1,jump=.27,sneak=true,speed=1,speed_walk=.38,
      speed_crouch=.67,acceleration_default=1,acceleration_air=1})
    if p.set_local_animation then p:set_local_animation(idle,walking,idle,walking,walk_rate) end
    if p.set_animation then p:set_animation(idle,walk_rate,.1,true) end
    state.walking=false
    position(p,land,state.saved.yaw,0)
  end
  function W.step(p,state)
    local at=p:get_pos()
    local speed=p:get_velocity()
    local moving=speed.x*speed.x+speed.z*speed.z>.12^2
    if p.set_animation and state.walking~=moving then
      p:set_animation(moving and walking or idle,walk_rate,.1,true)
      state.walking=moving
    end
    local id=tile_at(at.x,at.z)
    local t=id and cell(id)
    if not wet(t) and math.abs(at.y-surface(id,at.x,at.z))<.32 then
      state.last_dry=at
    elseif (wet(t) and at.y<.30 and p:get_velocity().y<-.2) or at.y<-.8 then
      -- A single recovery when falling into water, not per-tick movement.
      position(p,state.last_dry,p:get_look_horizontal(),p:get_look_vertical())
    end
  end
  return W
end
return P
