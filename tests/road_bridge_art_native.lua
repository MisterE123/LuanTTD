-- Isolated X/Z and elevation seams using the actual game-format bridge art.
-- No gameplay or live world writes.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local prefix="bl_road_bridge_wood"
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="bridgepreview:"..n}) end
for i=0,3 do
  core.register_node("bridgepreview:grass"..i,{description="Temperate bank",pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("bridgepreview:straight"..i,{description="East-west approach",pointable=false,
    tiles={"bl_road_10_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
end
core.register_node("bridgepreview:water",{description="River",pointable=false,tiles={"bl_water0.png"}})
local names={"span_0","span_1","pier_0","pier_1"}
for d=0,3 do
  names[#names+1]="head_flat_"..d
  names[#names+1]="head_ramp_"..d
end
for _,n in ipairs(names) do
  core.register_node("bridgepreview:"..n,{description=n,drawtype="mesh",
    mesh=prefix.."_"..n..".obj",tiles={prefix..".png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
core.register_entity("bridgepreview:bus",{
  initial_properties={physical=false,static_save=false,pointable=false,visual="mesh",shaded=true,
    backface_culling=true,mesh="bl_town_flyer.obj",textures={"bl_vehicle_palette.png"},
    visual_size={x=.42,y=.42,z=.42}},
})
local views={
  river={from={x=7.8,y=3.6,z=2.2},at={x=8.5,y=.85,z=8.3}},
  approach={from={x=2.15,y=.05,z=7.8},at={x=7.2,y=1.5,z=8.55}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function setup()
  for x=-13,36 do for z=-20,36 do
    local i=(math.floor(x/2)*7+math.floor(z/2)*17)%4
    if x<=3 or x>=14 then
      node(x,0,z,"grass"..i)
      if x>=14 then node(x,1,z,"grass"..i) end
    else
      node(x,-2,z,"grass"..i)
      node(x,-1,z,"water")
    end
  end end
  for x=0,2,2 do
    for dx=0,1 do for dz=0,1 do node(x+dx,0,8+dz,"straight"..(2*(1-dz)+dx)) end end
  end
  for x=14,20,2 do
    for dx=0,1 do for dz=0,1 do node(x+dx,1,8+dz,"straight"..(2*(1-dz)+dx)) end end
  end
  node(4,1,8,"head_ramp_2")
  for x=6,10,2 do
    node(x,1,8,"span_0")
    node(x,0,8,"pier_0")
    -- The lower module is submerged; do not replace the water node with it.
  end
  node(12,1,8,"head_flat_0")
  for _,p in ipairs({{x=6.2,z=8.32,yaw=math.pi/2},{x=9.9,z=8.67,yaw=-math.pi/2}}) do
    local o=core.add_entity({x=p.x,y=1.52,z=p.z},"bridgepreview:bus")
    if o then o:set_rotation({x=0,y=p.yaw,z=0}) end
  end
end
local ongoing,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.94)
  p:set_sky({type="plain",base_color="#b7d4e3",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.river)
  if not ongoing then
    ongoing=true
    core.emerge_area({x=-13,y=-3,z=-20},{x=36,y=5,z=36},function(_,_,remaining)
      if remaining==0 then
        setup();ready=true
        local active=core.get_player_by_name(name)
        if active then view(active,views.river) end
        core.log("action","ROAD_BRIDGE_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showbridge",{
  params="river|approach",description="Look at the timber bridge fixture",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg])
    return true
  end,
})
