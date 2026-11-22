-- Original stock tanker on the real stock right-hand presentation trajectory.
local d=core.get_modpath("oiltanker")
local Routes=dofile(d.."/foster_bus_route.lua")(d.."/source/")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("oiltanker:grass"..i,{description="Temperate grass",walkable=false,pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  for _,m in ipairs({3,5,6,9,10,12}) do
    core.register_node("oiltanker:road"..m.."_"..i,{description="Road arms",walkable=false,pointable=false,
      tiles={"bl_road_"..m.."_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  end
end
local MODEL="bl_witcombe_oil_tanker"
core.register_entity("oiltanker:truck",{initial_properties={
  physical=false,pointable=false,static_save=false,collide_with_objects=false,
  visual="mesh",mesh=MODEL..".obj",textures={MODEL.."_atlas.png"},
  shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42},
}})
local function node(n,x,y,z)core.set_node({x=x,y=y,z=z},{name="oiltanker:"..n})end
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
local function truck(p)
  local o=assert(core.add_entity({x=p.x,y=.5,z=p.z},"oiltanker:truck"))
  o:set_rotation({x=0,y=math.pi-p.yaw,z=0})
  assert(math.abs(o:get_pos().y-.5)<.0001 and math.abs(o:get_properties().visual_size.x-.42)<.00001)
  return o
end
local VIEWS={waiting={from={x=11,y=.6,z=14},at={x=12,y=.65,z=12}}}
local eye=1.47
local function camera(p,along,side,h)
  local dx,dz=math.sin(p.yaw),math.cos(p.yaw)
  return {from={x=p.x+along*dx+side*dz,y=h-eye,z=p.z+along*dz-side*dx},
    at={x=p.x,y=.649,z=p.z}}
end
local function place()
  for x=-8,37 do for z=-8,34 do
    node("grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4),x,0,z)
  end end
  local east=Routes.compile(2,2,6,6)
  pave(east)
  local straight=sample(east,12.36,12.345)
  truck(straight)
  VIEWS.front=camera(straight,1.01,.28,.80)
  VIEWS.side=camera(straight,0,-1.03,.81)
  VIEWS.rear=camera(straight,-.72,.56,.94)
  VIEWS.survey=camera(straight,.83,.77,1.71)
  local corner=Routes.compile(1,2,10,3)
  pave(corner)
  local turn=sample(corner,20.65,6.60,math.pi/4)
  truck(turn)
  VIEWS.curve=camera(turn,.68,.72,1.08)
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
  look(p,VIEWS.waiting)
  if not pending then
    pending=true
    core.emerge_area({x=-8,y=-1,z=-8},{x=37,y=5,z=35},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(key)
        if current then look(current,VIEWS.survey) end
        core.log("action","WITCOMBE_OIL_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showoiltanker",{
  params="front|side|rear|curve|survey",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not VIEWS[arg] then return false end
    look(p,VIEWS[arg])
    return true
  end,
})
