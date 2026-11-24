local m=core.get_modpath("luanttd_core")
for _,a in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..a,"air") end
core.register_node("luanttd_core:water",{tiles={"bl_ride_ferry_interior.png^[colorize:#387D9E:255"}})
core.register_node("luanttd_core:grass",{tiles={"bl_ride_ferry_interior.png^[colorize:#4A6B4A:255"}})
local Pedestrian=dofile(m.."/pedestrian.lua")
local V
local state={}
local labels={air="Aircraft",ship="Ferry"}
local names={air="luanttd_core:test_airliner",ship="luanttd_core:test_ferry"}
local mesh={air="bl_bayshore_trimotor.obj",ship="bl_harbor_ferry.obj"}
local textures={air="bl_bayshore_trimotor_palette.png",ship="bl_harbor_ferry_palette.png"}
for _,kind in ipairs({"air","ship"}) do
  core.register_entity(names[kind],{initial_properties={physical=false,pointable=true,static_save=false,
    visual="mesh",mesh=mesh[kind],textures={textures[kind]},visual_size={x=1,y=1,z=1}}})
end
V=dofile(m.."/vehicle_ui.lua")({s={},Sim={},world={may_board=function()return true end,
  follow_hud=function(p,active) p:hud_set_flags({hotbar=not active,crosshair=not active,wielditem=not active}) end}})
local targets={air={kind="air",id=8},ship={kind="ship",id="ferry"}}
local first,mode,start
core.set_timeofday(.5)
core.register_on_joinplayer(function(p)
  Pedestrian.hide_builder(p)
  p:set_physics_override({gravity=0,speed=0,jump=0})
  p:set_pos({x=1,y=11,z=-4});p:set_look_horizontal(.30);p:set_look_vertical(.20)
  p:hud_set_flags({healthbar=false,wielditem=false,basic_debug=false})
  if first then return end
  first=true
  core.emerge_area({x=-42,y=0,z=-35},{x=66,y=2,z=72},function(_,_,left)
    if left~=0 then return end
    for x=-42,66 do for z=-35,72 do
      core.set_node({x=x,y=0,z=z},{name=x>13 and "luanttd_core:grass" or "luanttd_core:water"})
    end end
    state.air=core.add_entity({x=6,y=14,z=7},names.air)
    state.ship=core.add_entity({x=6,y=.5,z=7},names.ship)
    core.log("action","RIDE_AIR_FERRY_NATIVE_READY")
  end)
end)
local t=0
core.register_globalstep(function(dt)
  if not state.air then return end
  t=t+dt
  for _,kind in ipairs({"air","ship"}) do
    local y=kind=="air" and 14+math.min(t,20)*.14 or .5
    local p={x=6+math.sin(t*.18)*2.5,y=y,z=7+math.sin(t*.14)*3}
    local rot={x=kind=="air" and -.08 or 0,y=math.pi+math.sin(t*.3)*.14,z=0}
    local actor=state[kind]
    actor:move_to(p,true);actor:set_rotation(rot)
    V.track(kind,targets[kind].id,p,actor)
    V.ride_track(kind,targets[kind].id,actor,p,rot,{running=true,passenger=true,mesh=mesh[kind]})
  end
  V.step(dt)
end)
core.register_chatcommand("rideprobe",{func=function(n,v)
  local p=core.get_player_by_name(n)
  if targets[v] then
    assert(not V.riding(p))
    start,mode=p:get_pos(),v
    assert(V.ride_toggle(p,"ride",targets[v]))
    assert(V.riding(p) and p:get_attach() and p:get_properties().zoom_fov==24)
    core.log("action","RIDE_AIR_FERRY_NATIVE_"..v)
    return true
  elseif v=="active" then
    assert(V.riding(p) and p:get_attach() and p:get_properties().zoom_fov==24)
    assert(vector.distance(p:get_attach():get_pos(),state[mode]:get_pos())<1.65)
    assert(not state[mode]:get_observers()[n])
    core.log("action","RIDE_AIR_FERRY_NATIVE_ACTIVE_"..mode)
    return true
  elseif v=="left" then
    assert(not V.riding(p) and not p:get_attach() and not state[mode]:get_observers())
    assert(vector.distance(start,p:get_pos())<.07 and p:get_properties().zoom_fov==24)
    core.log("action","RIDE_AIR_FERRY_NATIVE_LEFT_"..mode)
    return true
  end
end})
