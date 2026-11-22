-- Native stock-art inspection: no production game or existing save changes.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("goodsart:grass"..i,{description="Lot ground",pointable=false,
    tiles={"bl_grass"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("goodsart:road"..i,{description="Ordinary stock town road",pointable=false,
    tiles={"bl_road_10_plain_q"..i..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("goodsart:stage"..i,{description="Stock construction stage "..i,
    drawtype="mesh",mesh=i==3 and "bl_scenery_house_0.obj" or ("bl_house_build_stage_"..i..".obj"),
    tiles={i==3 and "bl_scenery_palette.png" or "bl_house_build_atlas.png"},
    paramtype="light",sunlight_propagates=true,pointable=false,walkable=false})
end

local views={
  stage0={from={x=3.38,y=.66,z=6.54},at={x=4.55,y=.60,z=8.52}},
  stage1={from={x=5.83,y=.80,z=6.58},at={x=6.57,y=.82,z=8.48}},
  stage2={from={x=9.94,y=.60,z=6.54},at={x=8.58,y=1.01,z=8.49}},
  sequence={from={x=6.62,y=3.56,z=1.92},at={x=7.50,y=.68,z=8.50}},
}
local function view(p,v)
  p:set_pos(v.from)
  local delta=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-delta.x,delta.z))
  p:set_look_vertical(math.atan2(-delta.y,math.sqrt(delta.x*delta.x+delta.z*delta.z)))
end
local function build()
  for x=-11,31 do for z=-8,28 do
    core.set_node({x=x,y=0,z=z},{name="goodsart:grass"..((math.floor(x/2)*7+math.floor(z/2)*17)%4)})
  end end
  for x=-8,25 do for z=6,7 do
    core.set_node({x=x,y=0,z=z},{name="goodsart:road"..(x%2+2*(1-z%2))})
  end end
  for i=0,3 do
    core.set_node({x=4+i*2,y=1,z=8},{name="goodsart:stage"..i})
  end
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local key=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.sequence)
  if not pending then
    pending=true
    core.emerge_area({x=-11,y=-1,z=-8},{x=31,y=5,z=29},function(_,_,rest)
      if rest==0 then
        build();ready=true
        local current=core.get_player_by_name(key)
        if current then view(current,views.sequence) end
        core.log("action","HOUSE_BUILD_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showhouse",{
  params="stage0|stage1|stage2|sequence",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    view(p,views[arg]);return true
  end,
})
