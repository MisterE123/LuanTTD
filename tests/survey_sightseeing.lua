-- Press the actual registered hotbar tool and secondary callbacks.
local path="mods/luanttd_core/"
local tools,stacks,stack_count,active,now={},{},0,1,1000000
local callbacks,selected,status,opened,actions={},{},nil,{},{}
local fake,keys,hangar_picked,riding,inventory_form
local function noop() end
core={
  registered_items=tools,
  get_modpath=function()return path:gsub("/$","")end,
  register_tool=function(id,def) assert(not tools[id]);tools[id]=def end,
  register_chatcommand=noop,register_allow_player_inventory_action=noop,
  show_formspec=function(_,form,fs)inventory_form={form,fs} end,
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
  set_inventory_formspec=function(_,fs)inventory_form=fs end,
  get_attach=function()return nil end,
  get_player_control=function()return keys or {} end,
  get_wield_index=function()return active end,get_wielded_item=function()return stacks[active] end,
  hud_set_hotbar_itemcount=function(_,n)stack_count=n end,
  get_inventory=function()return {set_size=noop,set_stack=function(_,_,i,it)stacks[i]=it end}end,
}
local cap_tile,target_vehicle=7,nil
local ray_picks=0
local roads={[7]={h=1,terrain="grass",build="road"},[8]={h=0,terrain="water",ship={kind="ship_depot"}}}
local api={road_first=true,s={tiles=roads},Sim={xy=function(id)return 3,id==7 and 2 or 3 end,id=function()end},
  render={uses_slope=function()return false end,
    pick_sightseeing_hangar=function()return hangar_picked end}}
local car,plane
local W
local near_road=false
api.car={walk_entry=function() return near_road and 7 or nil end,
  toggle_at=function(_,id,hit)
  assert(id==7)
  if hit then assert(hit.y==1.625 and hit.x==6.6)
  else assert(W.begin_avatar(fake,"car")) end
  car=(car or 0)+1;return true
end}
api.sightseeing_plane={board=function(p,id)
  assert(id==7)
  assert(W.begin_avatar(p,"plane"))
  plane=(plane or 0)+1;return true
end,toggle=function(p)return W.end_avatar(p,"plane") end}
api.vehicle_ui={
  following=function()return riding end,riding=function()return riding end,
  pick=function(_,distance)
    assert(distance==4.5 or distance==90);ray_picks=ray_picks+1
    return target_vehicle
  end,
  open=function(_,kind,id)opened[#opened+1]={kind,id} end,
  ride_toggle=function(_,mode,target)
    assert(target==target_vehicle and target.body)
    if mode=="cab" then assert(target.kind=="rail")
    else assert(mode=="ride") end
    actions[#actions+1]=mode..":"..target.id
    riding=true
    W.follow_hud(fake,true)
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
W=dofile(path.."world.lua")(api,ui)
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
assert(W.menu(fake)=="survey" and stack_count==7)
local expected={"back","teleport_tile","inspect","jump","workbench_index","survey_walk","survey_drive_car"}
for i,label in ipairs(expected) do assert(stacks[i]=="luanttd_core:menu_"..label) end
for _,id in ipairs({"survey_fly_plane","survey_train_cab","survey_ride_vehicle"}) do
  assert(not tools["luanttd_core:menu_"..id],id.." should not be a hotbar tool")
end
assert(tools[stacks[6]].description:find("dry ground",1,true))
press("survey_drive_car")
tools[stacks[7]].on_use(stacks[7],fake)
assert(car==1)
cap_tile=nil
press("survey_drive_car");assert(car==1 and status:find("Aim at a connected street",1,true))
press("survey_walk");assert(not W.avatar_state(fake) and status:find("Aim at open ground",1,true))
cap_tile=8
press("survey_walk");assert(not W.avatar_state(fake) and status:find("Choose open ground",1,true))
cap_tile=7
local builder=at
press("survey_walk")
local walking=W.avatar_state(fake)
assert(walking.mode=="walk" and not flags.hotbar and flags.crosshair and properties.mesh=="bl_street_pedestrian.glb")
assert(at.x==6.6 and at.y==1.545 and at.z==4.7)
assert(inventory_form:find("luanttd_scenic_exit",1,true))
press("survey_walk","on_secondary_use");assert(W.avatar_state(fake)==walking and #callbacks==0)
local function clicked(v)
  target_vehicle=v;now=now+300000
  return W.scenic_click(fake)
end
assert(not clicked(nil) and #actions==0)
for i,kind in ipairs({"road","air","ship"}) do
  assert(clicked({kind=kind,id=i,body=1}) and riding and W.avatar_state(fake)==walking)
  assert(actions[i]=="ride:"..i and not flags.hotbar)
  riding=false;W.follow_hud(fake,false)
  assert(W.avatar_state(fake)==walking and not flags.hotbar and flags.crosshair)
end
assert(clicked({kind="rail",id=19,body=3}))
assert(inventory_form[2]:find("Passenger seat") and inventory_form[2]:find("Driver's cab"))
assert(W.scenic_fields(fake,inventory_form[1],{cab=true}))
assert(actions[4]=="cab:19")
riding=false;W.follow_hud(fake,false)
assert(clicked({kind="rail",id=39,body=2}))
assert(W.scenic_fields(fake,inventory_form[1],{coach=true}) and actions[5]=="ride:39")
riding=false;W.follow_hud(fake,false)
local walk_pos=at
assert(type(inventory_form)~="string" or not inventory_form:find("luanttd_scenic_drive",1,true))
assert(W.scenic_fields(fake,"",{luanttd_scenic_drive=true}) and car==1)
near_road=true
W.finish_ride_landing(fake,{x=6.65,y=1.53,z=4.76},nil,.3,.12)
assert(at.x==6.65 and at.y==1.53 and yaw==.3 and pitch==.12)
assert(inventory_form:find("luanttd_scenic_drive",1,true))
near_road=false
assert(W.scenic_fields(fake,"",{luanttd_scenic_drive=true}) and car==1,"A stale road button cannot launch a car")
near_road=true
assert(W.scenic_fields(fake,"",{luanttd_scenic_drive=true}) and car==2)
assert(W.avatar_state(fake).mode=="car" and W.avatar_state(fake).previous==walking)
assert(W.end_avatar(fake,"car"))
table.remove(callbacks,1)()
assert(W.avatar_state(fake)==walking and inventory_form:find("luanttd_scenic_drive",1,true))
walk_pos=at
hangar_picked=7
assert(clicked(nil))
assert(plane==1 and W.avatar_state(fake).mode=="plane")
assert(inventory_form:find("Return to walking",1,true))
assert(W.scenic_fields(fake,"",{luanttd_scenic_exit=true}))
table.remove(callbacks,1)()
assert(W.avatar_state(fake)==walking and not flags.hotbar)
assert(at.x==walk_pos.x and at.y==walk_pos.y and at.z==walk_pos.z)
assert(W.scenic_fields(fake,"",{luanttd_scenic_exit=true}))
table.remove(callbacks,1)()
assert(not W.avatar_state(fake) and W.menu(fake)=="survey" and flags.hotbar and stack_count==7)
assert(at.x==builder.x and at.y==builder.y and at.z==builder.z)
press("survey_walk","on_secondary_use")
assert(context==1 and not W.avatar_state(fake))
press("back")
assert(W.menu(fake)=="home" and stack_count==7 and builds==0)
print("Survey Walk and Car tools, Walk boarding train/road/air/ferry, native hangar nesting, and Inventory exits without builders' right-click regressions")
