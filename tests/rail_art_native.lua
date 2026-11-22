-- Isolated graphical mesh fixture. This is not the live gameplay port.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
for i=0,3 do
  core.register_node("railpreview:ground"..i,{description="Turf",pointable=false,tiles={"bl_grass"..i..".png","bl_grass"..i..".png","bl_grass_side.png"}})
end
for i=1,63 do
  core.register_node("railpreview:t"..i,{description="Stock track "..i,drawtype="mesh",
    mesh="bl_rail_track_"..i..".obj",tiles={"bl_rail_atlas.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
for i=1,4 do
  local slope=({3,12,6,9})[i]
  core.register_node("railpreview:s"..i,{description="Stock grade terrain",drawtype="mesh",
    mesh="bl_land_"..slope..".obj",tiles={"bl_grass1.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
  core.register_node("railpreview:g"..i,{description="Straight grade "..i,drawtype="mesh",
    mesh="bl_rail_grade_"..i..".obj",tiles={"bl_rail_atlas.png"},paramtype="light",
    sunlight_propagates=true,walkable=false,pointable=false})
end
core.register_entity("railpreview:loco",{
  initial_properties={physical=false,static_save=false,pointable=false,visual="mesh",
    mesh="bl_steam.obj",textures={"bl_vehicle_palette.png"}},
})
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="railpreview:"..n}) end
local views={
  turn={from={x=9,y=6.4,z=2.8},at={x=9.8,y=.5,z=8.3}},
  street={from={x=4,y=1.0,z=6.6},at={x=7.1,y=.3,z=8.5}},
  grade={from={x=5.4,y=2.2,z=18.2},at={x=7.0,y=.8,z=20.5}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function layout()
  for x=-16,38 do for z=-16,38 do
    node(x,0,z,"ground"..((math.floor(x/2)*7+math.floor(z/2)*17)%4))
  end end
  local function tile(x,z,mask) node(2*x,1,2*z,"t"..mask) end
  for i=0,9 do tile(i,4,1) end
  tile(4,4,5) -- stock upper branching from the main X piece
  tile(4,3,8) -- stock lower joins back to another east-west line
  tile(5,3,1);tile(6,3,3);tile(7,3,1);tile(8,3,1)
  for z=1,7 do
    if z~=3 and z~=4 then tile(6,z,2) end
  end
  tile(6,4,3) -- full-gauge diamond
  tile(2,6,32);tile(2,7,4);tile(1,6,1);tile(1,7,1) -- four-tile U
  -- One full world-unit rise, a level crest and its opposing descent.
  for x=2,12 do
    for z=19,22 do node(x,0,z,"ground1") end
  end
  for z=9,11 do
    node(4,1,2*z,"s1");node(8,1,2*z,"s2")
    for x=6,7 do
      for dz=0,1 do node(x,1,2*z+dz,"ground1") end
    end
  end
  node(2,1,20,"t1");node(4,2,20,"g1");node(6,2,20,"t1")
  node(8,2,20,"g2");node(10,1,20,"t1")
  -- Original train asset at an actual physical track height/gauge.
  local loco=core.add_entity({x=4.9,y=.612,z=8.5},"railpreview:loco")
  if loco then loco:set_rotation({x=0,y=math.pi/2,z=0}) end
end
local pending,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd5dd",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.turn)
  if not pending then
    pending=true
    core.emerge_area({x=-16,y=-1,z=-16},{x=39,y=4,z=39},function(_,_,remaining)
      if remaining==0 then
        layout();ready=true
        local active=core.get_player_by_name(name)
        if active then view(active,views.turn) end
        core.log("action","RAIL_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showrail",{
  params="turn|street|grade", description="Aim at track artwork",
  func=function(name,arg)
    local who=core.get_player_by_name(name)
    if not who or not ready or not views[arg] then return false end
    view(who,views[arg])
    return true
  end,
})
