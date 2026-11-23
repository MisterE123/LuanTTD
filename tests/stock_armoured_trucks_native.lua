-- Read-only presentation exercise in an isolated disposable Luanti game.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local rows={"balogh","uhl","foster"}
for _,s in ipairs(rows) do
  local stem="bl_stock_"..s.."_armoured_truck"
  core.register_entity("armours:"..s,{
    initial_properties={static_save=false,physical=false,pointable=false,
      visual="mesh", mesh=stem..".obj",textures={stem.."_atlas.png"},
      shaded=true,backface_culling=true,visual_size={x=.42,y=.42,z=.42}},
  })
end
for q=0,3 do
  core.register_node("armours:grass"..q,{tiles={"bl_grass"..q..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("armours:road"..q,{tiles={"bl_road_10_plain_q"..q..".png","bl_grass0.png","bl_grass_side.png"}})
end
local views={
  lineup={cam={x=10.71,y=-.125,z=6.31},target={x=8.52,y=.65,z=8.33}},
  rear={cam={x=6.25,y=-.113,z=6.57},target={x=8.50,y=.65,z=8.32}},
}
local function view(p,v)
  p:set_pos(v.cam)
  local dx,dy,dz=v.target.x-v.cam.x,v.target.y-v.cam.y-1.47,v.target.z-v.cam.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
end
local ready=false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#c8dce0",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.lineup)
  if ready then return end
  ready=true
  core.emerge_area({x=-5,y=-1,z=-6},{x=31,y=5,z=35},function(_,_,left)
    if left~=0 then return end
    for x=-5,30 do for z=-6,34 do
      core.set_node({x=x,y=0,z=z},{name="armours:grass"..((x+3*z)%4)})
    end end
    for x=0,14,2 do
      for i=0,1 do for j=0,1 do
        core.set_node({x=x+i,y=0,z=8+j},{name="armours:road"..(i+2*(1-j))})
      end end
    end
    for i,s in ipairs(rows) do
      local o=assert(core.add_entity({x=8.5+(i-2)*.765,y=.5,z=8.5-.155},"armours:"..s))
      o:set_rotation({x=0,y=math.pi/2,z=0})
      assert(math.abs(o:get_properties().visual_size.x-.42)<.0001 and math.abs(o:get_pos().y-.5)<.0001)
      core.log("action","ARMOURED VEHICLE VISUAL READY "..s)
    end
    local q=core.get_player_by_name(name)
    if q then view(q,views.lineup) end
    core.log("action","NATIVE_ARMOURED_ART_ALL_READY")
  end)
end)
core.register_chatcommand("rearproof",{func=function(name)
  local p=core.get_player_by_name(name)
  if p then view(p,views.rear) end
  return true
end})
