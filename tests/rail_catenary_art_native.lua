-- Isolated native check of actual assets at the stock mount coordinates.
local A=dofile(core.get_modpath("wireart").."/rail_catenary_art.lua")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
core.register_node("wireart:ground",{
  description="Fixture meadow",tiles={"bl_grass1.png","bl_grass1.png","bl_grass_side.png"},
  pointable=false,
})
local function mesh(name,file,png)
  core.register_node("wireart:"..name,{
    description=name,drawtype="mesh",mesh=file..".obj",tiles={png..".png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,
  })
end
local function node(x,y,z,n) core.set_node({x=x,y=y,z=z},{name="wireart:"..n}) end
for _,m in ipairs({1,2,4,8,16,32}) do
  mesh("track"..m,"bl_rail_track_"..m,"bl_rail_atlas")
  for p=0,1 do
    local n="rail_catenary_"..m.."_"..p
    mesh(n,"bl_"..n,"bl_rail_catenary_atlas")
  end
end
for i,slope in ipairs({3,12,6,9}) do
  mesh("ground"..i,"bl_land_"..slope,"bl_grass1")
  mesh("grade"..i,"bl_rail_grade_"..i,"bl_rail_atlas")
  for p=0,1 do
    local n="rail_catenary_grade_"..i.."_"..p
    mesh(n,"bl_"..n,"bl_rail_catenary_atlas")
  end
end
for i=1,2 do
  mesh("platform"..i,"bl_rail_platform_"..i,"bl_rail_architecture_atlas")
end
core.register_entity("wireart:sh30",{
  initial_properties={physical=false,pointable=false,static_save=false,visual="mesh",
    mesh="bl_rail_sh_30.obj",textures={"bl_rail_sh_30.png"},backface_culling=true,
    visual_size={x=1,y=1,z=1}},
})
local function rail(x,z,b,m,grade,kind,mast)
  local a=A.overlay(m,grade,kind,x/2,z/2,mast)
  assert(a and a.offset==(grade==0 and 2 or 3))
  if grade>0 then
    node(x,b+1,z,"ground"..grade)
    node(x,b+2,z,"grade"..grade)
  else
    node(x,b+1,z,kind=="platform" and ("platform"..m) or ("track"..m))
  end
  node(x,b+a.offset,z,a.name)
  assert(core.get_node({x=x,y=b+a.offset,z=z}).name=="wireart:"..a.name)
end
local views={
  platform_x={from={x=7.0,y=.42,z=12.1},at={x=8.54,y=1.05,z=8.48}},
  platform_z={from={x=14.7,y=.43,z=12.8},at={x=18.5,y=1.06,z=9.5}},
  curve={from={x=13.2,y=1.85,z=18.2},at={x=16.32,y=.92,z=16.90}},
  grade_x={from={x=5.1,y=.78,z=17.2},at={x=7.0,y=1.43,z=20.5}},
  grade_z={from={x=21.7,y=.52,z=19.0},at={x=24.47,y=1.27,z=21.7}},
  shoe={from={x=8.61,y=.29,z=9.73},at={x=8.71,y=1.29,z=8.51}},
}
local function look(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function layout()
  for x=-2,31 do for z=-2,33 do node(x,0,z,"ground") end end
  for x=2,14,2 do rail(x,8,0,1,0,(x==6 or x==8) and "platform" or "plain") end
  local sh=assert(core.add_entity({x=8.70,y=.614,z=8.50},"wireart:sh30"))
  sh:set_rotation({x=0,y=math.pi/2,z=0})
  for z=4,14,2 do rail(18,z,0,2,0,(z==8 or z==10) and "platform" or "plain") end
  local other=assert(core.add_entity({x=18.50,y=.614,z=9.40},"wireart:sh30"))
  other:set_rotation({x=0,y=0,z=0})
  rail(12,16,0,1,0,"plain")
  rail(14,16,0,1,0,"plain")
  rail(16,16,0,32,0,"plain")
  rail(16,18,0,2,0,"plain")
  rail(16,20,0,2,0,"plain",true)
  -- Both rise orientations per stock axis, with exact ordinary crest.
  for x=6,7 do for z=20,21 do node(x,1,z,"ground") end end
  rail(2,20,0,1,0,"plain")
  rail(4,20,0,1,1,"plain")
  rail(6,20,1,1,0,"plain")
  rail(8,20,0,1,2,"plain")
  rail(10,20,0,1,0,"plain",true)
  for x=24,25 do for z=22,23 do node(x,1,z,"ground") end end
  rail(24,18,0,2,0,"plain",true)
  rail(24,20,0,2,3,"plain")
  rail(24,22,1,2,0,"plain")
  rail(24,24,0,2,4,"plain")
  rail(24,26,0,2,0,"plain",true)
end
local pending,ready=false,false
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.97)
  p:set_sky({type="plain",base_color="#bad5df",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  look(p,views.platform_x)
  if not pending then
    pending=true
    core.emerge_area({x=-2,y=-1,z=-2},{x=32,y=5,z=34},function(_,_,n)
      if n==0 then
        layout();ready=true
        local player=core.get_player_by_name(name)
        if player then look(player,views.platform_x) end
        core.log("action","RAIL_CATENARY_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("viewwire",{
  params="platform_x|platform_z|curve|grade_x|grade_z|shoe",
  func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not p or not ready or not views[arg] then return false end
    look(p,views[arg]);return true
  end,
})
