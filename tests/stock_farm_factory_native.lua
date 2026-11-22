-- Art-only native camera fixture with the exact two stock footprints.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local layouts={
  farm={{1,0,33},{1,1,34},{1,2,36},{0,0,37},{0,1,37},{0,2,36},{2,0,35},{2,1,38},{2,2,38}},
  factory={{0,0,39},{0,1,40},{1,0,41},{1,1,42},{0,2,39},{0,3,40},{1,2,41},{1,3,42},
           {2,1,39},{2,2,40},{3,1,41},{3,2,42}},
}
local anchor={farm={x=3,z=4},factory={x=16,z=4}}
for key,lay in pairs(layouts) do
  for _,t in ipairs(lay) do
    local stem=key.."_"..t[1].."_"..t[2]
    core.register_node("goodsart:"..stem,{description="Stock "..key.." GFX "..t[3],
      drawtype="mesh",mesh="bl_industry_"..stem..".obj",tiles={"bl_industry_"..key.."_atlas.png"},
      paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,backface_culling=true})
  end
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
  ["farm-survey"]={from={x=9.98,y=3.98,z=11.50},at={x=5.84,y=1.04,z=6.85}},
  ["farm-yard"]={from={x=9.40,y=-.11,z=10.72},at={x=6.27,y=.88,z=6.35}},
  ["factory-survey"]={from={x=25.6,y=5.06,z=13.46},at={x=19.4,y=1.15,z=7.86}},
  ["factory-loading"]={from={x=24.87,y=.12,z=10.55},at={x=22.90,y=1.11,z=7.94}},
}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function build()
  for x=-8,34 do for z=-5,24 do
    node(x,0,z,"g"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for x=-4,28,2 do for dx=0,1 do for dz=0,1 do
    node(x+dx,0,12+dz,"r"..(dx+2*(1-dz)))
  end end end
  for key,layout in pairs(layouts) do
    local a=anchor[key]
    for _,t in ipairs(layout) do
      node(a.x+2*t[1],1,a.z+2*t[2],key.."_"..t[1].."_"..t[2])
    end
  end
  local lorry=assert(core.add_entity({x=19.95,y=.52,z=11.02},"goodsart:lorry"))
  lorry:set_rotation({x=0,y=-math.pi/2,z=0})
  local lorry2=assert(core.add_entity({x=23.03,y=.52,z=8.69},"goodsart:lorry"))
  lorry2:set_rotation({x=0,y=math.pi/2,z=0})
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bcd5df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views["farm-survey"])
  if pending then return end
  pending=true
  core.emerge_area({x=-8,y=-1,z=-5},{x=34,y=6,z=24},function(_,_,n)
    if n==0 then
      build();ready=true
      local current=core.get_player_by_name(name)
      if current then view(current,views["farm-survey"]) end
      core.log("action","FARM_FACTORY_MESH_FIXTURE_READY")
    end
  end)
end)
core.register_chatcommand("industryview",{params="farm-survey|farm-yard|factory-survey|factory-loading",
  func=function(name,key)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[key] then return false end
    view(p,views[key]);return true
  end})
