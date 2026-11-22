-- Isolated renderer fixture: actual Yate and existing stock harbour geometry.
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local function mesh(n,p,t)
  core.register_node("yate:"..n,{description=n,drawtype="mesh",mesh=p..".obj",tiles={t..".png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
end
local function entity(n,p,t,shade)
  core.register_entity("yate:"..n,{initial_properties={static_save=false,physical=false,
    pointable=false,visual="mesh",mesh=p..".obj",textures={t..".png"},shaded=shade,
    backface_culling=true,visual_size={x=1,y=1,z=1}}})
end
entity("ship","bl_yate_cargo_ship","bl_yate_cargo_ship_atlas",true)
for _,row in ipairs({"chamber_water","gate_lower_closed","gate_upper_closed"}) do
  entity(row,"bl_ship_lock_"..row,"bl_ship_lock_atlas",false)
end
for q=0,3 do
  for _,p in ipairs({"grass","water"}) do
    core.register_node("yate:"..p..q,{description=p,tiles={
      "bl_"..p..q..".png","bl_"..p.."0.png","bl_"..p.."_side.png"},
      pointable=false,walkable=false})
  end
end
mesh("approach","bl_ship_dock_ramp_1","bl_ship_facilities_atlas")
mesh("pier","bl_ship_dock_pier_1","bl_ship_facilities_atlas")
for j=0,1 do mesh("depot"..j,"bl_ship_depot_1_"..j,"bl_ship_facilities_atlas") end
for _,p in ipairs({"lower","middle","upper"}) do
  mesh(p,"bl_ship_lock_"..p.."_1","bl_ship_lock_atlas")
end
local function n(name,x,y,z)
  core.set_node({x=x,y=y,z=z},{name="yate:"..name})
end
local function e(name,x,y,z,turn)
  local o=assert(core.add_entity({x=x,y=y,z=z},"yate:"..name))
  assert(math.abs(o:get_pos().y-y)<.0001 and o:get_properties().visual_size.x==1,
      "Yate fixture has incorrect entity scale or water surface")
  o:set_rotation({x=0,y=turn or 0,z=0})
end
local function ground(kind,x,z,h)
  n(kind..((x*3+z*7+math.floor(x/3))%4),x,h,z)
end
local function place()
  for x=-8,33 do for z=-10,31 do
    if z<=4 then
      ground("grass",x,z,1)
      ground("grass",x,z,0)
    else
      ground("water",x,z,0)
    end
  end end
  -- Land slope starts behind the actual short pier; use standard even anchors.
  for x=6,7 do for z=5,7 do
    ground("grass",x,z,-1)
    core.remove_node({x=x,y=0,z=z})
  end end
  n("approach",6,1,6); n("pier",6,1,8)
  -- Open berth a full gameplay tile after the pier, rounded bow toward approach.
  e("ship",6.5,.5,10.5,0)
  n("depot0",12,1,8); n("depot1",12,1,10)
  -- Half inside a real Z-aligned depot portal, bow now toward +Z.
  e("ship",12.5,.5,7.94,math.pi)
  -- 3/8 stock lock ascent, actual closed native gate model on both ends.
  for x=20,21 do for z=10,15 do
    core.remove_node({x=x,y=0,z=z})
  end end
  for x=18,24 do for z=14,31 do ground("water",x,z,1) end end
  n("lower",20,1,8); n("middle",20,1,10); n("upper",20,2,12)
  -- Upper artist mesh includes inside water, don't overlay a full node.
  for x=20,21 do for z=12,13 do core.remove_node({x=x,y=1,z=z}) end end
  e("chamber_water",20.5,.875,10.5,0)
  e("gate_lower_closed",20.5,.5,9.385,0)
  e("gate_upper_closed",20.5,.5,11.615,0)
  e("ship",20.5,.875,10.5,math.pi)
end
local eye=1.47
local views={
  waterline={from={x=8.39,y=-.70,z=10.79},at={x=6.48,y=.785,z=10.49}},
  cabin={from={x=8.37,y=.31,z=9.68},at={x=6.50,y=.93,z=10.42}},
  harbour={from={x=11.21,y=2.14,z=13.33},at={x=7.51,y=.67,z=9.01}},
  depot={from={x=14.20,y=-.07,z=6.02},at={x=12.51,y=.94,z=8.20}},
  lock={from={x=22.10,y=3.01,z=8.35},at={x=20.49,y=1.25,z=10.46}},
}
local function view(p,v)
  p:set_pos(v.from)
  local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+eye,z=v.from.z})
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local ready,pending=false,false
core.register_on_joinplayer(function(p)
  local key=p:get_player_name()
  p:set_physics_override({gravity=0})
  p:override_day_night_ratio(.95)
  p:set_sky({type="plain",base_color="#bfd9e4",clouds=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  view(p,views.harbour)
  if not pending then
    pending=true
    core.emerge_area({x=-8,y=-1,z=-10},{x=33,y=5,z=31},function(_,_,left)
      if left==0 then
        place();ready=true
        local current=core.get_player_by_name(key)
        if current then view(current,views.harbour) end
        core.log("action","YATE_MESH_FIXTURE_READY")
      end
    end)
  end
end)
core.register_chatcommand("showyate",{
  params="waterline|cabin|harbour|depot|lock",
  func=function(name,arg)
    local player=core.get_player_by_name(name)
    if not player or not ready or not views[arg] then return false end
    view(player,views[arg]);return true
  end,
})
