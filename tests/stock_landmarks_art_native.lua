-- Minimal cloud graphical fixture, same native even-anchor mounting as game.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
core.register_node("landmarkart:grass",{
  description="Stock-art meadow",tiles={"bl_grass2.png","bl_grass0.png","bl_grass_side.png"},
  walkable=false,pointable=false,
})
for _,name in ipairs({"lighthouse","transmitter"}) do
  core.register_node("landmarkart:"..name,{
    description=name,drawtype="mesh",mesh="bl_stock_"..name..".obj",
    tiles={"bl_stock_landmarks_atlas.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false,
  })
end
local views={
  pair={from={x=12.16,y=1.42,z=13.93},at={x=10.47,y=1.57,z=8.45}},
  light={from={x=8.43,y=-.05,z=11.47},at={x=8.45,y=1.31,z=8.50}},
  mast={from={x=14.58,y=.10,z=11.50},at={x=12.49,y=1.75,z=8.49}},
}
local function look(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x^2+d.z^2)))
end
local function place()
  for x=0,23 do for z=0,23 do
    core.set_node({x=x,y=0,z=z},{name="landmarkart:grass"})
  end end
  for x,n in pairs({[8]="lighthouse",[12]="transmitter"}) do
    local p={x=x,y=1,z=8}
    core.set_node(p,{name="landmarkart:"..n})
    assert(core.get_node(p).name=="landmarkart:"..n,"wrong native node anchor")
  end
end
local pending,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(1)
  p:set_sky({type="plain",base_color="#bcd9df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  look(p,views.pair)
  if not pending then
    pending=true
    core.emerge_area({x=0,y=-1,z=0},{x=24,y=4,z=24},function(_,_,areas)
      if areas==0 then
        place();ready=true
        local player=core.get_player_by_name(name)
        if player then look(player,views.pair) end
        core.log("action","STOCK_LANDMARKS_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("viewlandmark",{
  params="pair|light|mast",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    look(p,views[arg]);return true
  end,
})
