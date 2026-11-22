-- Local graphical fixture for both OpenTTD stock forestry industry shapes.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local plots={}
for i=0,1 do
  plots[i]={}
  for z=0,4 do for x=0,3+i do
    if z<4 or (x>0 and x<3+i) then
      local n=i.."_"..x.."_"..z
      local name="goodsart:forest_"..n
      core.register_node(name,{description="Stock active forestry plot",drawtype="mesh",
        mesh="bl_forest_"..n..".obj",tiles={"bl_forest_atlas.png"},
        paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
      plots[i][#plots[i]+1]={x=x,z=z,name=name}
    end
  end end
end
core.register_node("goodsart:cut",{description="Stock harvest cycle cut plot 17",drawtype="mesh",
  mesh="bl_forest_harvested.obj",tiles={"bl_forest_atlas.png"},paramtype="light",
  sunlight_propagates=true,walkable=false,pointable=false})
for n=0,3 do
  core.register_node("goodsart:g"..n,{description="Native meadow",pointable=false,
    tiles={"bl_grass"..n..".png","bl_grass0.png","bl_grass_side.png"}})
  core.register_node("goodsart:r"..n,{description="Native road",pointable=false,
    tiles={"bl_road_10_plain_q"..n..".png","bl_grass0.png","bl_grass_side.png"}})
end
local harvest={x=2,y=1,z=8}
local views={
  survey={from={x=10.65,y=5.80,z=16.92},at={x=3.88,y=1.11,z=4.74}},
  landing={from={x=10.32,y=.56,z=4.32},at={x=6.65,y=.92,z=2.52}},
  cut={from={x=2.58,y=.46,z=10.78},at={x=2.44,y=.81,z=8.58}},
  second={from={x=25.34,y=6.45,z=17.02},at={x=20.34,y=1.31,z=4.33}},
}
local function view(p,v)
  p:set_pos(v.from)
  local delta=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-delta.x,delta.z))
  p:set_look_vertical(math.atan2(-delta.y,math.sqrt(delta.x*delta.x+delta.z*delta.z)))
end
local function place()
  for x=-12,41 do for z=-7,32 do
    core.set_node({x=x,y=0,z=z},{name="goodsart:g"..((math.floor(x/2)*7+math.floor(z/2)*17)%4)})
  end end
  for x=-8,31 do for z=10,11 do
    core.set_node({x=x,y=0,z=z},{name="goodsart:r"..(x%2+2*(1-z%2))})
  end end
  for i,tiles in pairs(plots) do
    for _,q in ipairs(tiles) do
      core.set_node({x=16*i+2*q.x,y=1,z=2*q.z},{name=q.name})
    end
  end
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#bdd3dc",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.survey)
  if not pending then
    pending=true
    core.emerge_area({x=-12,y=-1,z=-7},{x=42,y=7,z=33},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(name)
        if current then view(current,views.survey) end
        core.log("action","FOREST_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showforest",{
  params="survey|landing|cut|second",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    if arg=="cut" then
      assert(core.get_node(harvest).name=="goodsart:forest_0_1_4")
      core.swap_node(harvest,{name="goodsart:cut"})
      core.log("action","FOREST_NATIVE_GFX17_MOUNTED")
    end
    view(p,views[arg]);return true
  end,
})
