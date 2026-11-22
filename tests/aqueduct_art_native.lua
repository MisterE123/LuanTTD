-- Isolated native graphic QA; never touches a campaign or simulates routing.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local prefix="bl_aqueduct"
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="waterwaypreview:"..n}) end
for i=0,3 do
  core.register_node("waterwaypreview:grass"..i,{description="Temperate banks",pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("waterwaypreview:ground_road"..i,{description="North-south underpass",pointable=false,
    tiles={"bl_road_5_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
end
core.register_node("waterwaypreview:water",{description="Canal",pointable=false,
  tiles={"bl_water0.png","bl_water0.png","bl_water_side.png"}})
core.register_node("waterwaypreview:rail",{description="North-south rail",drawtype="mesh",
  mesh="bl_rail_track_2.obj",tiles={"bl_rail_atlas.png"},paramtype="light",
  sunlight_propagates=true,walkable=false,pointable=false})
local names={"span_0","span_1","pier_0","pier_1","pier_head_0","pier_head_1"}
for d=0,3 do names[#names+1]="head_"..d end
for _,n in ipairs(names) do
  core.register_node("waterwaypreview:"..n,{description=n,drawtype="mesh",
    mesh=prefix.."_"..n..".obj",tiles={prefix..".png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
for _,r in ipairs({
    {"ferry","bl_harbor_ferry","bl_harbor_ferry_palette",1},
    {"bus","bl_town_flyer","bl_vehicle_palette",.42},
    {"steam","bl_steam","bl_vehicle_palette",1},
}) do
  local a=r[4]
  core.register_entity("waterwaypreview:"..r[1],{
    initial_properties={physical=false,static_save=false,pointable=false,visual="mesh",shaded=true,
      backface_culling=true,mesh=r[2]..".obj",textures={r[3]..".png"},visual_size={x=a,y=a,z=a}},
  })
end
local views={
  crest={from={x=8.1,y=5.2,z=2.4},at={x=8.4,y=2.22,z=8.40}},
  approach={from={x=2.7,y=1.83,z=8.23},at={x=7.6,y=2.95,z=8.55}},
  below={from={x=7.25,y=-.47,z=5.87},at={x=7.82,y=1.43,z=9.45}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function actor(kind,x,y,z,yaw)
  local o=core.add_entity({x=x,y=y,z=z},"waterwaypreview:"..kind)
  assert(o,"Could not add test mesh "..kind)
  o:set_rotation({x=0,y=yaw,z=0})
end
local function setup()
  for x=-14,37 do for z=-19,36 do
    local i=(math.floor(x/2)*7+math.floor(z/2)*17)%4
    node(x,0,z,"grass"..i)
    if x<=5 or x>=12 then
      node(x,1,z,"grass"..i)
      if x<=3 or x>=14 then
        node(x,2,z,z>=8 and z<=9 and "water" or "grass"..i)
      end
    end
  end end
  node(4,2,8,"head_2")
  node(12,2,8,"head_0")
  for x=6,10,2 do node(x,2,8,"span_0") end
  node(10,1,8,"pier_head_0")  -- ground finishes at y=.5 under this span only
  for row=-2,18,2 do
    for dx=0,1 do for dz=0,1 do node(6+dx,0,row+dz,"ground_road"..(2*(1-dz)+dx)) end end
    node(8,1,row,"rail")
  end
  actor("ferry",7.57,2.5,8.5,math.pi/2)
  actor("bus",6.65,.52,8.60,math.pi)
  actor("steam",8.5,.614,8.9,0)
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
  view(p,views.crest)
  if not ongoing then
    ongoing=true
    core.emerge_area({x=-14,y=-3,z=-19},{x=37,y=6,z=36},function(_,_,remaining)
      if remaining==0 then
        setup();ready=true
        local active=core.get_player_by_name(name)
        if active then view(active,views.crest) end
        core.log("action","AQUEDUCT_ART_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showaqueduct",{
  params="crest|approach|below",description="Inspect the actual aqueduct assets",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg])
    return true
  end,
})
