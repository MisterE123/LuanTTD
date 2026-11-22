-- Original art on actual native track alongside original industry layouts.
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
for _,bits in ipairs({1,2}) do
  mesh("track_"..bits,"bl_rail_track_"..bits,"bl_rail_atlas")
end
for _,kind in ipairs({"load","unload"}) do
  for axis=0,1 do
    for _,suffix in ipairs({"","_mirror"}) do
      local name=kind.."_"..axis..suffix
      mesh(name,"bl_rail_coal_stage_"..name,"bl_rail_coal_stage_atlas")
    end
  end
end
local mine={{1,1},{1,2},{0,0},{1,0},{2,0},{2,2}}
for _,q in ipairs(mine) do
  local tag=q[1].."_"..q[2]
  mesh("mine_"..tag,"bl_coal_mine_0_"..tag,"bl_coal_mine_atlas")
end
for x=0,3 do
  for z=0,1 do
    local tag=x.."_"..z
    mesh("plant_"..tag,"bl_power_station_"..tag,"bl_power_station_atlas")
  end
end
local actual=core.settings:get_bool("native_stock_coal_wagon",false)
local entities={rail_kirby_paul_tank="rail_kirby_paul_tank"}
if actual then
  entities.rail_coal_wagon_empty="rail_coal_wagon_atlas"
  entities.rail_coal_wagon_loaded="rail_coal_wagon_atlas"
else
  entities.rail_open_wagon="rail_wagon_atlas"
end
for id,atlas in pairs(entities) do
  core.register_entity("railpreview:"..id,{
    initial_properties={static_save=false,physical=false,pointable=false,visual="mesh",
      mesh="bl_"..id..".obj",textures={"bl_"..atlas..".png"},shaded=true,
      backface_culling=true,visual_size={x=1,y=1,z=1}},
  })
end

local views={
  survey={from={x=13.72,y=5.57,z=23.11},at={x=13.61,y=.8,z=11.0}},
  loading={from={x=9.77,y=.08,z=16.19},at={x=8.30,y=1.33,z=12.07}},
  receiving={from={x=23.45,y=.14,z=13.99},at={x=20.20,y=1.12,z=12.29}},
  cargo={from={x=22.47,y=1.34,z=13.33},at={x=20.71,y=1.13,z=12.50}},

}
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local function roll(kind,x,z,dir)
  local ob=assert(core.add_entity({x=x,y=.614,z=z},"railpreview:"..kind))
  ob:set_rotation({x=0,y=dir,z=0})
  return ob
end
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local test_wagon
local function build()
  for x=-12,46 do for z=-7,36 do
    node(x,0,z,"grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  for _,q in ipairs(mine) do node(2+2*q[1],1,8+2*q[2],"mine_"..q[1].."_"..q[2]) end
  for z=0,1 do for x=0,3 do node(16+2*x,1,8+2*z,"plant_"..x.."_"..z) end end
  for z=4,24,2 do node(8,1,z,"track_2") end
  node(8,1,12,"load_1_mirror")
  for x=12,30,2 do node(x,1,12,"track_1") end
  node(20,1,12,"unload_0_mirror")
  roll("rail_kirby_paul_tank",8.5,13.50,math.pi)
  roll(actual and "rail_coal_wagon_empty" or "rail_open_wagon",8.5,12.50,math.pi)
  roll("rail_kirby_paul_tank",19.51,12.5,-math.pi/2)
  test_wagon=roll(actual and "rail_coal_wagon_loaded" or "rail_open_wagon",20.51,12.5,-math.pi/2)
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5df",clouds=false})
  for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do p:hud_set_flags({[f]=false}) end
  view(p,views.survey)
  if not pending then
    pending=true
    core.emerge_area({x=-12,y=-1,z=-7},{x=47,y=4,z=37},function(_,_,left)
      if left==0 then
        build();ready=true
        local current=core.get_player_by_name(name)
        if current then view(current,views.survey) end
        core.log("action","COAL_RAIL_STAGE_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showstage",{
  params="survey|loading|receiving|cargo",description="Inspect coal transfer stages in native rail clearances",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    if actual and arg=="cargo" then
      -- See the exact in-place mesh swap with no placement/scale change;
      -- capture both before and after in the same view.
      if test_wagon:get_properties().mesh=="bl_rail_coal_wagon_loaded.obj" then
        test_wagon:set_properties({mesh="bl_rail_coal_wagon_empty.obj"})
        core.log("action","COAL_WAGON_ART_EMPTY_SHAPE_MOUNTED")
      else
        test_wagon:set_properties({mesh="bl_rail_coal_wagon_loaded.obj"})
        core.log("action","COAL_WAGON_ART_LOADED_SHAPE_MOUNTED")
      end
    end
    view(p,views[arg]);return true
  end,
})
