-- Actual runtime oil meshes in exact, independent stock layout-0 positions.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local layouts={
  oil_well={{0,0,29},{1,0,29},{2,0,29},{0,1,29},{0,2,29}},
  oil_refinery={{0,0,20},{0,1,21},{0,2,22},{0,3,21},{1,0,20},{1,1,19},{1,2,22},{1,3,20},
           {2,1,18},{2,2,18},{2,3,18},{3,2,18},{3,3,18},{2,0,23},{3,1,23}},
}
local anchor={oil_well={x=4,z=5},oil_refinery={x=17,z=4}}
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
    tiles={"bl_road_5_plain_q"..q..".png","bl_grass0.png","bl_grass_side.png"}})
end
local tanker=core.settings:get_bool("oil_art_has_tanker",false)
if tanker then core.register_entity("goodsart:lorry",{
  initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
    mesh="bl_witcombe_oil_tanker.obj",textures={"bl_witcombe_oil_tanker_atlas.png"},
    shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42}},
}) end
local views={
  ["wells-survey"]={from={x=10.51,y=4.32,z=12.05},at={x=6.40,y=.97,z=7.12}},
  ["wellhead"]={from={x=7.83,y=-.05,z=8.43},at={x=6.53,y=.89,z=5.62}},
  ["refinery-survey"]={from={x=26.11,y=6.22,z=13.59},at={x=20.48,y=1.01,z=7.9}},
  ["receiving"]={from={x=20.8,y=.09,z=.92},at={x=18.5,y=1.00,z=4.81}},
}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="goodsart:"..n}) end
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function build()
  for x=-8,37 do for z=-7,27 do
    node(x,0,z,"g"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for z=-4,2,2 do for dx=0,1 do for dz=0,1 do
    node(19+dx,0,z+dz,"r"..(dx+2*(1-dz)))
  end end end
  for key,layout in pairs(layouts) do
    local a=anchor[key]
    for _,t in ipairs(layout) do
      node(a.x+2*t[1],1,a.z+2*t[2],key.."_"..t[1].."_"..t[2])
    end
  end
  if tanker then
    -- Three original receiving pads offer identical physical motor lanes.
    local lorry=assert(core.add_entity({x=19.44,y=.52,z=4.18},"goodsart:lorry"))
    lorry:set_rotation({x=0,y=math.pi,z=0})
    local lorry2=assert(core.add_entity({x=19.44,y=.52,z=10.77},"goodsart:lorry"))
    lorry2:set_rotation({x=0,y=0,z=0})
  end
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
  view(p,views["wells-survey"])
  if pending then return end
  pending=true
  core.emerge_area({x=-8,y=-1,z=-7},{x=37,y=6,z=27},function(_,_,n)
    if n==0 then
      build();ready=true
      local current=core.get_player_by_name(name)
      if current then view(current,views["wells-survey"]) end
      core.log("action","OIL_SITES_MESH_FIXTURE_READY")
    end
  end)
end)
core.register_chatcommand("oilscene",{params="wells-survey|wellhead|refinery-survey|receiving",
  func=function(name,key)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[key] then return false end
    view(p,views[key]);return true
  end})
