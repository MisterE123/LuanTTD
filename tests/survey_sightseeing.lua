-- Press the actual registered hotbar tool and secondary callbacks.
local path="mods/luanttd_core/"
local tools,stacks,stack_count,active,now={},{},0,1,1000000
local callbacks,selected,status,opened,actions={},{},nil,{},{}
local fake,keys
local function noop() end
core={
  registered_items=tools,
  get_modpath=function()return path:gsub("/$","")end,
  register_tool=function(id,def) assert(not tools[id]);tools[id]=def end,
  register_chatcommand=noop,register_allow_player_inventory_action=noop,
  get_us_time=function()return now end,
  get_player_by_name=function()return fake end,
  after=function(_,cb)callbacks[#callbacks+1]=cb end,
}
function ItemStack(name)return name end
local at={x=6.6,y=10.0,z=4.7}
local yaw,pitch=.25,.94
local properties={eye_height=1.625}
local physics={gravity=0}
local flags={hotbar=true,crosshair=true}
fake={
  get_pos=function()return at end,set_pos=function(_,v)at=v end,
  get_player_name=function()return "Surveyor" end,is_player=function()return true end,
  get_look_horizontal=function()return yaw end,set_look_horizontal=function(_,x)yaw=x end,
  get_look_vertical=function()return pitch end,set_look_vertical=function(_,x)pitch=x end,
  get_look_dir=function()return {x=0,y=-1,z=0} end,
  get_properties=function()return properties end,
  set_properties=function(_,v)for k,value in pairs(v) do properties[k]=value end end,
  get_eye_offset=function()return {x=0,y=0,z=0}end,set_eye_offset=noop,
  get_velocity=function()return {x=0,y=0,z=0}end,
  get_physics_override=function()return physics end,set_physics_override=function(_,v)physics=v end,
  hud_get_flags=function()return flags end,hud_set_flags=function(_,v)flags=v end,
  hud_add=function()return 1 end,hud_change=noop,hud_remove=noop,
  set_inventory_formspec=noop,
  get_player_control=function()return keys or {} end,
  get_wield_index=function()return active end,get_wielded_item=function()return stacks[active] end,
  hud_set_hotbar_itemcount=function(_,n)stack_count=n end,
  get_inventory=function()return {set_size=noop,set_stack=function(_,_,i,it)stacks[i]=it end}end,
}
local cap_tile,target_vehicle=7,nil
local ray_picks=0
local roads={[7]={h=1,terrain="grass",build="road"},[8]={h=0,terrain="water",ship={kind="ship_depot"}}}
local api={road_first=true,s={tiles=roads},Sim={xy=function(id)return 3,id==7 and 2 or 3 end,id=function()end},
  render={uses_slope=function()return false end}}
local car,plane
api.car={toggle_at=function(_,id,hit)
  assert(id==7 and hit.y==1.625 and hit.x==6.6)
  car=(car or 0)+1;return true
end}
api.sightseeing_plane={board=function(_,id)
  assert(id==7)
  plane=(plane or 0)+1;return true
end}
api.vehicle_ui={
  following=function()return false end,
  pick=function(_,distance)
    assert(distance==42 or distance==90);ray_picks=ray_picks+1
    return target_vehicle
  end,
  open=function(_,kind,id)opened[#opened+1]={kind,id} end,
  ride_toggle=function(_,mode,target)
    assert(target==target_vehicle and target.body)
    if mode=="cab" then assert(target.kind=="rail")
    else assert(mode=="ride" and target.kind=="road") end
    actions[#actions+1]=mode..":"..target.id
    return true
  end,
}
local context,builds=0,0
local ui={
  guide=function()return "" end,phase=function()return 7 end,
  status=function(_,s)status=s end,
  inventory=noop,anchor=noop,
  is_world_tool=function(k)return k=="inspect"end,
  select_tool=function(_,tool)selected[#selected+1]=tool end,
  world_status=function() return "","" end,
  context=function()context=context+1 end,
  build_world=function()builds=builds+1 end,
}
local W=dofile(path.."world.lua")(api,ui)
function W.target()
  return cap_tile,cap_tile and {x=6.6,y=1.625,z=4.7}
end
W.spawn(fake)
local function press(id,method)
  local tool="luanttd_core:menu_"..id
  for i=1,stack_count do
    if stacks[i]==tool then
      active=i; now=now+200000
      tools[tool][method or "on_use"](tool,fake)
      return
    end
  end
  error("Missing tool "..id.." in installed hotbar")
end
press("section_survey")
assert(W.menu(fake)=="survey" and stack_count==10)
local expected={"back","teleport_tile","inspect","jump","workbench_index","survey_walk","survey_drive_car",
                "survey_fly_plane","survey_train_cab","survey_ride_vehicle"}
for i,label in ipairs(expected) do assert(stacks[i]=="luanttd_core:menu_"..label) end
assert(tools[stacks[6]].description:find("dry ground",1,true))
press("survey_drive_car")
tools[stacks[7]].on_use(stacks[7],fake) -- duplicate engine/controller event must be ignored
assert(car==1)
press("survey_fly_plane");assert(plane==1)
target_vehicle={kind="rail",id=19,body=3}
press("survey_train_cab");assert(actions[1]=="cab:19")
target_vehicle={kind="road",id=27,body=1}
press("survey_train_cab");assert(#actions==1 and status:find("Aim at the train",1,true))
press("survey_ride_vehicle");assert(actions[2]=="ride:27")
press("survey_ride_vehicle","on_place") -- ordinary right-click is still vehicle inspection
assert(#actions==2 and #opened==1 and opened[1][1]=="road" and opened[1][2]==27)
target_vehicle=nil
press("survey_ride_vehicle");assert(ray_picks==5 and #actions==2 and status:find("Aim at a passenger train or bus",1,true))
cap_tile=nil
press("survey_fly_plane");assert(plane==1 and status:find("Aim at an airport",1,true))
press("survey_drive_car");assert(car==1 and status:find("Aim at a connected street",1,true))
press("survey_walk");assert(not W.avatar_state(fake) and status:find("Aim at open ground",1,true))
cap_tile=8
press("survey_walk");assert(not W.avatar_state(fake) and status:find("Choose open ground",1,true))
cap_tile=7
local previous_x,previous_y,previous_z=at.x,at.y,at.z
press("survey_walk")
assert(W.avatar_state(fake).mode=="walk" and not flags.hotbar and properties.mesh=="bl_street_pedestrian.glb")
assert(at.x==6.6 and at.y==1.545 and at.z==4.7)
press("survey_walk","on_secondary_use")
for _,f in ipairs(callbacks) do f() end
assert(not W.avatar_state(fake) and W.menu(fake)=="survey" and flags.hotbar and stack_count==10)
assert(at.x==previous_x and at.y==previous_y and at.z==previous_z)
press("survey_walk","on_secondary_use")
assert(context==1 and not W.avatar_state(fake))
press("back")
assert(W.menu(fake)=="home" and stack_count==7 and builds==0)
print("Survey hotbar: all five explicit targets, strict miss behavior, right-click inspect/return, no chat or build action")
