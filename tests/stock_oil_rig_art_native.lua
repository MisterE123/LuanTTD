-- GPL-2.0-only; disposable mesh visual fixture, not a gameplay command.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for x=0,1 do for z=0,2 do
  local suffix=x.."_"..z
  core.register_node("rigqa:r"..suffix,{description="Oil rig cell "..suffix,
    drawtype="mesh",mesh="bl_industry_oil_rig_"..suffix..".obj",
    tiles={"bl_industry_oil_rig_atlas.png"},paramtype="light",sunlight_propagates=true,
    walkable=false,pointable=false,backface_culling=true})
end end
for q=0,3 do
  core.register_node("rigqa:sea"..q,{description="Still sea",
    tiles={"bl_water"..q..".png"},walkable=false, pointable=false})
end
local helicopter=core.settings:get_bool("rig_art_helicopter",false)
local rotors,model,pose,craft
if helicopter then
  rotors=dofile(core.get_modpath("rigqa").."/airport_rotor_view.lua")(core)
  model=dofile(core.get_modpath("rigqa").."/airport_airframe_art.lua").tricario
  model.entity="rigqa:tricario"
  rotors.register(model)
  core.register_entity(model.entity,{initial_properties={visual="mesh",static_save=false,
    physical=false,pointable=false,backface_culling=true,visual_size={x=1,y=1,z=1},
    mesh=model.mesh,textures={model.atlas}}})
  core.register_globalstep(function(dt)
    if craft then rotors.step(craft,model,pose,3,dt) end
  end)
end
local views={
  approach={from={x=-6,y=.57,z=-7.3},at={x=1.2,y=4.72,z=3.3}},
  berth={from={x=-5.37,y=-.7,z=1.19},at={x=-.1,y=2.3,z=1.5}},
  pad={from={x=8.1,y=8.4,z=-3.1},at={x=1.7,y=5.5,z=2.3}},
  tricario={from={x=1.2,y=6.67,z=-1.4},at={x=2.85,y=7.42,z=.625}},
}
local function go(p,k)
  local v=views[k]; p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local pending,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  core.set_player_privs(name,{fly=true,fast=true,shout=true})
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.99)
  p:set_sky({type="plain",base_color="#b9cdd7",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  go(p,"approach")
  if pending then return end
  pending=true
  core.emerge_area({x=-24,y=-3,z=-24},{x=24,y=16,z=24},function(_,_,n)
    if n~=0 then return end
    for x=-24,24 do for z=-24,24 do
      core.set_node({x=x,y=0,z=z},{name="rigqa:sea"..(x%2+2*(z%2))})
    end end
    for x=0,1 do for z=0,2 do
      core.set_node({x=2*x,y=1,z=2*z},{name="rigqa:r"..x.."_"..z})
    end end
    if helicopter then
      pose={x=3.375,y=7.25,z=.625}
      local body=assert(core.add_entity(pose,model.entity))
      body:set_yaw(-math.pi/2)
      craft={ref=body}
      rotors.step(craft,model,pose,3,.1)
      assert(craft.rotors and #craft.rotors==2)
      for _,r in ipairs(craft.rotors) do assert(r:get_attach()==body) end
      core.log("action","OIL_RIG_ROTARY_DUAL_AXES_ATTACHED")
    end
    ready=true
    local joined=core.get_player_by_name(name)
    if joined then go(joined,"approach") end
    core.log("action","OIL_RIG_MESH_FIXTURE_READY")
  end)
end)
core.register_chatcommand("oilscene",{
  func=function(name,k)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[k] then return false end
    go(p,k)
    core.log("action","OIL_RIG_VIEW_READY "..k)
    return true
  end})
