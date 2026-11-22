-- Native completed-style Sawmill graphic test, no simulation changes.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local lay={{1,0,14},{1,1,12},{1,2,11},{2,0,14},{2,1,13},{0,0,15},{0,1,15},{0,2,12}}
for _,t in ipairs(lay) do
  local s=t[1].."_"..t[2]
  core.register_node("goodsart:mill_"..s,{description="Stock sawmill gfx "..t[3],
    drawtype="mesh",mesh="bl_sawmill_0_"..s..".obj",tiles={"bl_sawmill_atlas.png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
end
for q=0,3 do
  core.register_node("goodsart:g"..q,{description="Meadow",pointable=false,
    tiles={"bl_grass"..q..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("goodsart:r"..q,{description="Flush road surface",pointable=false,
    tiles={"bl_road_10_plain_q"..q..".png","bl_grass0.png","bl_grass_side.png"}})
end
core.register_entity("goodsart:lorry",{
  initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
    mesh="bl_balogh_goods_truck.obj",textures={"bl_balogh_goods_truck_atlas.png"},
    shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42}},
})
local views={
  survey={from={x=11.80,y=3.82,z=14.85},at={x=6.52,y=.83,z=8.48}},
  intake={from={x=11.88,y=.88,z=9.17},at={x=8.66,y=1.10,z=8.51}},
  hall={from={x=6.934,y=-.422,z=9.017},at={x=6.507,y=.848,z=8.554}},
  dispatch={from={x=8.92,y=.06,z=14.53},at={x=5.47,y=.82,z=11.03}},
}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function place()
  for x=-11,34 do for z=-12,35 do
    node(x,0,z,"g"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for x=-4,16,2 do for dx=0,1 do for dz=0,1 do
    node(x+dx,0,12+dz,"r"..(dx+2*(1-dz)))
  end end end
  for _,t in ipairs(lay) do
    local a,b=t[1],t[2]
    node(4+2*a,1,6+2*b,"mill_"..a.."_"..b)
  end
  local o=core.add_entity({x=5.95,y=.5,z=12.345},"goodsart:lorry")
  o:set_rotation({x=0,y=math.pi/2,z=0})
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
  view(p,views.survey)
  if not pending then
    pending=true
    core.emerge_area({x=-11,y=-1,z=-12},{x=34,y=5,z=36},function(_,_,left)
      if left==0 then
        place();ready=true
        local p=core.get_player_by_name(name)
        if p then view(p,views.survey) end
        core.log("action","SAWMILL_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showsawmill",{
  params="survey|intake|hall|dispatch",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg]);return true
  end,
})
