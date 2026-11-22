-- Native Coleman presentation isolated from the production save and renderer.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for z=0,2 do for x=0,3 do
  local cell=x.."_"..z
  core.register_node("coleman:cell_"..cell,{description="Country airport "..cell,drawtype="mesh",
    mesh="bl_small_airport_"..cell..".obj",tiles={"bl_small_airport_atlas.png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
end end
for v=0,3 do
  core.register_node("coleman:grass"..v,{description="Airport meadow",
    tiles={"bl_grass"..v..".png","bl_grass0.png","bl_grass_side.png"},pointable=false,walkable=false})
end
for _,m in ipairs({{"count","bl_coleman_count","bl_coleman_count_atlas"},
                   {"flight","bl_coleman_count_flight","bl_coleman_count_atlas"},
                   {"sampson","bl_bayshore_trimotor","bl_bayshore_trimotor_palette"}}) do
  core.register_entity("coleman:"..m[1],{initial_properties={static_save=false,physical=false,
    collide_with_objects=false,pointable=false,visual="mesh",mesh=m[2]..".obj",
    textures={m[3]..".png"},shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}}})
end
local function plane(n,x,y,z,turn,pitch)
  local ob=assert(core.add_entity({x=x,y=y,z=z},"coleman:"..n))
  ob:set_rotation({x=pitch or 0,y=turn or 0,z=0})
  assert(math.abs(ob:get_pos().y-y)<1e-5 and ob:get_properties().visual_size.x==1)
end
local function place()
  for x=-11,34 do for z=-12,32 do
    core.set_node({x=x,y=0,z=z},{name="coleman:grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4)})
  end end
  for z=0,2 do for x=0,3 do
    core.set_node({x=8+x*2,y=1,z=8+z*2},{name="coleman:cell_"..x.."_"..z})
  end end
  -- Genuine (32,23) and (10,23) stand points in source units, both nose -Z.
  local g=.505
  plane("count",11.50,g,10.375,0)
  plane("sampson",8.75,g,10.375,0)
  -- Source exact hangar stop (53,3), pointing out (dir 3, +Z).
  plane("count",14.125,g,7.875,math.pi)
  -- Separate gear-up visual specimen; do not pretend this static scene tests motion.
  plane("flight",19.50,3.05,14.15,-math.pi/2,-.11)
end
local views={
  apron_low={from={x=13.32,y=-.62,z=9.687},at={x=11.54,y=.807,z=10.28}},
  apron_survey={from={x=12.16,y=2.56,z=13.62},at={x=10.60,y=.61,z=9.57}},
  hangar={from={x=14.46,y=-.50,z=10.25},at={x=14.10,y=.86,z=8.12}},
  gear_up={from={x=21.31,y=1.13,z=15.58},at={x=19.55,y=3.31,z=14.16}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local ready,pending=false,false
core.register_on_joinplayer(function(player)
  local name=player:get_player_name()
  player:set_physics_override({gravity=0})
  player:override_day_night_ratio(.95)
  player:set_sky({type="plain",base_color="#bed9e3",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    player:hud_set_flags({[flag]=false})
  end
  view(player,views.apron_survey)
  if not pending then
    pending=true
    core.emerge_area({x=-11,y=-1,z=-12},{x=35,y=5,z=32},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(name)
        if current then view(current,views.apron_survey) end
        core.log("action","COLEMAN_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showcoleman",{
  params="apron_low|apron_survey|hangar|gear_up",
  func=function(name,arg)
    local player=core.get_player_by_name(name)
    if not player or not ready or not views[arg] then return false end
    view(player,views[arg]);return true
  end,
})
