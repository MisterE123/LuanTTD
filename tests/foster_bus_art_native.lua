-- Actual native rendering with the genuine right-hand road projection.
local d=core.get_modpath("foster")
local Routes=dofile(d.."/foster_bus_route.lua")(d.."/source/")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("foster:grass"..i,{description="County grass",pointable=false,walkable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  for _,m in ipairs({3,5,6,9,10,12}) do
    core.register_node("foster:road"..m.."_"..i,{description="Source road arms",pointable=false,walkable=false,
      tiles={"bl_road_"..m.."_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  end
end
local function mesh(n,source,atlas)
  core.register_node("foster:"..n,{description=n,drawtype="mesh",mesh=source..".obj",
    tiles={atlas..".png"},paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
end
mesh("house","bl_scenery_house_0","bl_scenery_palette")
mesh("house2","bl_scenery_house_2","bl_scenery_palette")
mesh("stop","bl_bus_shelter","bl_road_architecture")
for _,v in ipairs({{"bus","bl_foster_bus","bl_foster_bus_atlas"},
                   {"older","bl_leopard_bus","bl_road_fleet_palette"}}) do
  core.register_entity("foster:"..v[1],{initial_properties={static_save=false,physical=false,
    collide_with_objects=false,pointable=false,visual="mesh",mesh=v[2]..".obj",
    textures={v[3]..".png"},shaded=true,backface_culling=true,visual_size={x=.40,y=.40,z=.40}}})
end
local function node(n,x,y,z) core.set_node({x=x,y=y,z=z},{name="foster:"..n}) end
local function pave(route)
  for _,p in ipairs(route.points) do
    for x=0,1 do for z=0,1 do
      node("road"..p.mask.."_"..(x+2*(1-z)),2*p.x+x,0,2*p.z+z)
    end end
  end
end
local function sample(route,fx,fz,angle)
  local best,pos=math.huge,nil
  for i=1,#route.frames-1 do
    for f=0,6 do
      local x,z,yaw,id=route.pose(i,f/6)
      if id==route.id then
        local score=(fx-x)^2+(fz-z)^2
        if not angle or math.abs((yaw-angle+math.pi)%(2*math.pi)-math.pi)<.001 then
          if score<best then pos={x=x,z=z,yaw=yaw};best=score end
        end
      end
    end
  end
  return assert(pos)
end
local function bus(kind,p)
  local o=assert(core.add_entity({x=p.x,y=.5,z=p.z},"foster:"..kind))
  o:set_rotation({x=0,y=math.pi-p.yaw,z=0})
  assert(math.abs(o:get_pos().y-.5)<.0001 and math.abs(o:get_properties().visual_size.x-.40)<.00001)
end
local eye=1.47
local views={
  passing={from={x=10.23,y=.91,z=10.62},at={x=8.66,y=.61,z=12.50}},
}
local function camera(p,along,side,h)
  local dx,dz=math.sin(p.yaw),math.cos(p.yaw)
  return {from={x=p.x+along*dx+side*dz,y=h-eye,z=p.z+along*dz-side*dx},
    at={x=p.x,y=.642,z=p.z}}
end
local function place()
  for x=-8,35 do for z=-8,32 do
    node("grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4),x,0,z)
  end end
  for x=4,12,2 do node(x%4==0 and "house" or "house2",x,1,14) end
  node("stop",6,1,12)
  local forward=Routes.compile(2,2,4,6)
  local back=Routes.compile(0,0,4,6)
  pave(forward)
  local main=sample(forward,8.45,12.345)
  local older=sample(back,8.69,12.655)
  bus("bus",main);bus("older",older)
  views.street=camera(main,1.16,.72,.85)
  views.rear=camera(main,-1.16,.81,.87)
  local left=Routes.compile(1,0,10,8)
  local right=Routes.compile(1,2,10,3)
  pave(left);pave(right)
  local a=sample(left,20.08,16.29,-math.pi/4)
  local b=sample(right,20.65,6.60, math.pi/4)
  bus("bus",a);bus("bus",b)
  views.left=camera(a,.89,-1.01,1.44)
  views.right=camera(b,.94,.92,1.42)
end
local function look(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+eye,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local key=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd8e4",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  look(p,views.passing)
  if not pending then
    pending=true
    core.emerge_area({x=-8,y=-1,z=-8},{x=35,y=5,z=33},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(key)
        if current then look(current,views.passing) end
        core.log("action","FOSTER_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showfoster",{
  params="street|rear|passing|left|right",
  func=function(name,arg)
    local player=core.get_player_by_name(name)
    if not player or not ready or not views[arg] then return false end
    look(player,views[arg]);return true
  end,
})
