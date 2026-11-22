-- Native geometry QA for the original 1950 covered goods lorry.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local function mesh(name,source,atlas)
  core.register_node("goodsart:"..name,{
    description=name,drawtype="mesh",mesh=source..".obj",tiles={atlas..".png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,
  })
end
for q=0,3 do
  core.register_node("goodsart:grass"..q,{description="Meadow",pointable=false,
    tiles={"bl_grass"..q..".png","bl_grass0.png","bl_grass_side.png"}})
  for _,mask in ipairs({5,9,10}) do
    core.register_node("goodsart:road"..mask.."_"..q,{description="Stock road",pointable=false,
      tiles={"bl_road_"..mask.."_plain_q"..q..".png","bl_grass0.png","bl_grass_side.png"}})
  end
end
mesh("yard","bl_scenery_factory","bl_scenery_palette")
mesh("freight","bl_road_freight_stop_straight_0","bl_road_freight_stop")
for _,item in ipairs({
  {"lorry","bl_balogh_goods_truck.obj","bl_balogh_goods_truck_atlas.png"},
  {"tipper","bl_coal_tipper_loaded.obj","bl_coal_tipper_palette.png"},
}) do
  core.register_entity("goodsart:"..item[1],{
    initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
      mesh=item[2],textures={item[3]},shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42}},
  })
end
local eye=1.47
local views={
  street={from={x=9.46,y=-.64,z=7.51},at={x=8.68,y=.65,z=8.38}},
  rear={from={x=7.60,y=-.51,z=7.61},at={x=8.61,y=.68,z=8.37}},
  survey={from={x=9.14,y=1.37,z=12.0},at={x=8.74,y=.56,z=8.34}},
  bend={from={x=15.13,y=-.47,z=7.94},at={x=16.35,y=.68,z=8.42}},
}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local function road(x,z,mask)
  for dx=0,1 do for dz=0,1 do node(x+dx,0,z+dz,"road"..mask.."_"..(dx+2*(1-dz))) end end
end
local function roll(kind,x,z,dx,dz)
  local o=assert(core.add_entity({x=x,y=.5,z=z},"goodsart:"..kind))
  o:set_rotation({x=0,y=math.pi-math.atan2(dx,dz),z=0})
  assert(math.abs(o:get_pos().y-.5)<.0001 and math.abs(o:get_properties().visual_size.x-.42)<.00001,
         "Native goods art scale or tire datum is wrong")
end
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+eye,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function place()
  for x=-11,38 do for z=-12,35 do
    node(x,0,z,"grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for x=0,14,2 do road(x,8,10) end
  for z=-2,6,2 do road(16,z,5) end
  road(16,8,9)
  node(8,1,6,"yard")
  node(6,1,8,"freight")
  -- Full-size covered silhouette at the established one-lane .42 scale.
  -- Opposite-lane coal vehicle demonstrates separation in the survey.
  roll("lorry",8.65,8.5-.155,1,0)
  roll("tipper",9.10,8.5+.155,-1,0)
  -- Real compact left turn: center of the stock .36 quadratic plus the
  -- eased outside-lane .055 offset at half phase, no discontinuous yaw.
  local f=math.sqrt(.5)
  local a=16.5-.090+.055*f
  local b=8.5-.090+.055*f
  roll("lorry",a,b,-f,f)
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.street)
  if not pending then
    pending=true
    core.emerge_area({x=-11,y=-1,z=-12},{x=39,y=5,z=36},function(_,_,left)
      if left==0 then
        place();ready=true
        local q=core.get_player_by_name(name)
        if q then view(q,views.street) end
        core.log("action","BALOGH_GOODS_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showgoods",{
  params="street|survey|bend|rear",description="Inspect the original goods truck in land-correct poses",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg]);return true
  end,
})
