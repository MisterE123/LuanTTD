-- Original stock iron ore vehicles on the real stock right-hand presentation trajectory.
local d=core.get_modpath("farmtrucks")
local Routes=dofile(d.."/foster_bus_route.lua")(d.."/source/")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("farmtrucks:grass"..i,{description="Farm pasture",walkable=false,pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  for _,m in ipairs({3,5,6,9,10,12}) do
    core.register_node("farmtrucks:road"..m.."_"..i,{description="Road arms",walkable=false,pointable=false,
      tiles={"bl_road_"..m.."_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  end
end
local mps="bl_stock_mps_iron_ore_truck"
local uhl="bl_stock_uhl_iron_ore_truck"
local chippy="bl_stock_chippy_iron_ore_truck"
for _,f in ipairs({{"mps",mps.."_loaded",mps},{"uhl",uhl.."_loaded",uhl},{"chippy",chippy,chippy}}) do
  core.register_entity("farmtrucks:"..f[1],{initial_properties={physical=false,pointable=false,static_save=false,
    collide_with_objects=false,visual="mesh",mesh=f[2]..".obj",textures={f[3].."_atlas.png"},
    shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42}}})
end
local function node(n,x,y,z)core.set_node({x=x,y=y,z=z},{name="farmtrucks:"..n})end
local function pave(route)
  for _,p in ipairs(route.points) do
    for x=0,1 do for z=0,1 do
      node("road"..p.mask.."_"..(x+2*(1-z)),2*p.x+x,0,2*p.z+z)
    end end
  end
end
local function sample(route,fx,fz,angle)
  local nearest,p=math.huge
  for i=1,#route.frames-1 do for step=0,8 do
    local x,z,yaw,id=route.pose(i,step/8)
    if id==route.id and (not angle or math.abs((yaw-angle+math.pi)%(math.pi*2)-math.pi)<.0001) then
      local dist=(fx-x)^2+(fz-z)^2
      if dist<nearest then nearest=dist;p={x=x,z=z,yaw=yaw} end
    end
  end end
  return assert(p)
end
local function truck(kind,p)
  local o=assert(core.add_entity({x=p.x,y=.5,z=p.z},"farmtrucks:"..kind))
  o:set_rotation({x=0,y=math.pi-p.yaw,z=0})
  assert(math.abs(o:get_pos().y-.5)<.0001 and math.abs(o:get_properties().visual_size.x-.42)<.00001)
  return o
end
local views={
  farm={from={x=10.93,y=2.28,z=10.22},at={x=13.07,y=.62,z=14.38}},
}
local swap
local eye=1.47
local function camera(p,along,side,h)
  local dx,dz=math.sin(p.yaw),math.cos(p.yaw)
  return {from={x=p.x+along*dx+side*dz,y=h-eye,z=p.z+along*dz-side*dx},
    at={x=p.x,y=.641,z=p.z}}
end
local function place()
  for x=-8,37 do for z=-8,34 do
    node("grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4),x,0,z)
  end end
  local east,west=Routes.compile(2,2,6,6),Routes.compile(0,0,6,6)
  pave(east)
  local truck1=sample(east,12.36,12.345)
  local truck2=sample(west,12.93,12.655)
  truck("mps",truck1)
  truck("uhl",truck2)
  views.mps=camera(truck1,.88,.57,1.14)
  views.uhl=camera(truck2,-.83,-.72,1.02)
  local corner=Routes.compile(1,2,10,3)
  pave(corner)
  local p=sample(corner,20.65,6.60,math.pi/4)
  swap=truck("chippy",p)
  views.empty=camera(p,-.94,.74,1.08)
  views.loaded=views.empty
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
  look(p,views.farm)
  if not pending then
    pending=true
    core.emerge_area({x=-8,y=-1,z=-8},{x=37,y=5,z=35},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(key)
        if current then look(current,views.farm) end
        core.log("action","IRON_ORE_TRUCK_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showoretruck",{
  params="empty|loaded|mps|uhl|farm",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    swap:set_properties({mesh=chippy..(arg=="empty" and "" or "_loaded")..".obj"})
    look(p,views[arg])
    return true
  end,
})
