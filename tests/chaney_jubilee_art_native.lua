-- Isolated rendered Linux test: an all-mesh pilot and a trained rail crew.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local function mesh(name,source,atlas)
  core.register_node("railpreview:"..name,{
    description=name,drawtype="mesh",mesh=source..".obj",tiles={atlas..".png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,
  })
end
for i=0,3 do
  core.register_node("railpreview:grass"..i,{description="Meadow",
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
end
for _,bits in ipairs({1,2,3,32,33}) do
  mesh("track_"..bits,"bl_rail_track_"..bits,"bl_rail_atlas")
end
mesh("depot","bl_rail_depot_1","bl_rail_architecture_atlas")
for id,atlas in pairs({rail_chaney_jubilee="rail_chaney_jubilee",rail_open_wagon="rail_wagon_atlas",rail_passenger_wagon="rail_wagon_atlas"}) do
  core.register_entity("railpreview:"..id,{
    initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
      mesh="bl_"..id..".obj",textures={"bl_"..atlas..".png"},shaded=true,
      backface_culling=true,visual_size={x=1,y=1,z=1}},
  })
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local function roll(kind,x,z,dir)
  local ob=assert(core.add_entity({x=x,y=.614,z=z},"railpreview:"..kind))
  ob:set_rotation({x=0,y=dir,z=0})
end
local views={
  survey={from={x=8.05,y=1.76,z=5.7},at={x=10.85,y=.59,z=9.15}},
  street={from={x=9.28,y=-.33,z=7.21},at={x=10.5,y=.86,z=8.5}},
  curve={from={x=17.45,y=-.32,z=18.01},at={x=16.10,y=.85,z=16.70}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function build()
  for x=-13,33 do for z=-12,37 do
    node(x,0,z,"grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for z=4,18,2 do node(10,1,z,"track_2") end
  node(10,1,2,"depot")
  roll("rail_chaney_jubilee",10.5,8.4,0)
  roll("rail_open_wagon",10.5,9.4,0)
  roll("rail_passenger_wagon",10.5,10.4,0)
  -- True stock NE->SE unit-radius curve and tangent adjoining straights.
  for x=8,14,2 do node(x,1,16,"track_1") end
  for z=18,24,2 do node(16,1,z,"track_2") end
  node(10,1,16,"track_3")
  node(16,1,16,"track_33")
  node(18,1,16,"track_1")
  node(20,1,16,"track_1")
  local s=math.sqrt(.5)
  roll("rail_chaney_jubilee",16.5-1+s,16.5+1-s,math.pi-math.atan2(s,s))
  roll("rail_passenger_wagon",14.5+math.pi/4,16.5,-math.pi/2)
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bfd5df",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do p:hud_set_flags({[f]=false}) end
  view(p,views.survey)
  if not pending then
    pending=true
    core.emerge_area({x=-13,y=-1,z=-12},{x=34,y=4,z=38},function(_,_,left)
      if left==0 then
        build();ready=true
        local current=core.get_player_by_name(name)
        if current then view(current,views.survey) end
        core.log("action","CHANEY_JUBILEE_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showjubilee",{
  params="survey|street|curve",description="Inspect Chaney Jubilee native rail contact",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg]);return true
  end,
})
