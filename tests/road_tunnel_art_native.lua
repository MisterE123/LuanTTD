-- Isolated graphical fixture for the true portal mesh. No gameplay state.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local prefix="bl_road_tunnel_portal"
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="tunnelpreview:"..n}) end
for i=0,3 do
  core.register_node("tunnelpreview:grass"..i,{description="Temperate hill",pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("tunnelpreview:straight"..i,{description="Approach cross section",pointable=false,
    tiles={"bl_road_5_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
end
for i,shape in pairs({uphill=6,downhill=9}) do
  core.register_node("tunnelpreview:"..i,{description=i,drawtype="mesh",
    mesh="bl_land_"..shape..".obj",tiles={"bl_grass0.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
core.register_node("tunnelpreview:deep_rock",{description="Tunnel interior beyond portal tile",pointable=false,
    tiles={"bl_grass0.png","bl_grass0.png","bl_grass_side.png^[multiply:#252a32"}})
for d=0,3 do
  core.register_node("tunnelpreview:portal_"..d,{description="Portal",drawtype="mesh",
    mesh=prefix.."_"..d..".obj",tiles={prefix..".png"},paramtype="light",sunlight_propagates=true,
    walkable=false,pointable=false})
end
core.register_entity("tunnelpreview:bus",{
  initial_properties={physical=false,static_save=false,pointable=false,visual="mesh",shaded=true,
    backface_culling=true,mesh="bl_town_flyer.obj",textures={"bl_vehicle_palette.png"},
    visual_size={x=.42,y=.42,z=.42}},
})
local views={
  mouth={from={x=6.55,y=.61,z=5.2},at={x=8.5,y=.84,z=9.0}},
  approach={from={x=8.45,y=-.46,z=5.45},at={x=8.49,y=.83,z=9.16}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function setup()
  for x=-16,34 do for z=-10,39 do
    local i=(math.floor(x/2)*7+math.floor(z/2)*17)%4
    node(x,0,z,"grass"..i)
    if z>=10 and z<=17 then node(x,1,z,"grass"..i) end
    if x%2==0 then
      if z==8 then node(x,1,z,"uphill") end
      if z==18 then node(x,1,z,"downhill") end
    end
  end end
  for _,row in ipairs({4,6,20,22}) do
    for dx=0,1 do for dz=0,1 do node(8+dx,0,row+dz,"straight"..(2*(1-dz)+dx)) end end
  end
  node(8,1,8,"portal_1")
  node(8,1,18,"portal_3")
  -- Separate rock beyond the asset's actual open back edge, at a distance.
  for x=8,9 do node(x,1,10,"deep_rock") end
  for _,p in ipairs({{x=8.654,z=9.56,yaw=math.pi},{x=8.346,z=7.8,yaw=0}}) do
    local o=core.add_entity({x=p.x,y=.52,z=p.z},"tunnelpreview:bus")
    if o then o:set_rotation({x=0,y=p.yaw,z=0}) end
  end
end
local ongoing,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#b7d4e3",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.mouth)
  if not ongoing then
    ongoing=true
    core.emerge_area({x=-16,y=-3,z=-10},{x=35,y=5,z=39},function(_,_,remaining)
      if remaining==0 then
        setup();ready=true
        local active=core.get_player_by_name(name)
        if active then view(active,views.mouth) end
        core.log("action","ROAD_TUNNEL_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showtunnel",{
  params="mouth|approach",description="Inspect the actual two-lane tunnel portal art",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg])
    return true
  end,
})
