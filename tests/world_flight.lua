-- Exercise actual world-step physics + simultaneous diagonal demolition.
local keys,now,override,physics_calls={},0,{},0
local contents,index={},1
local velocity={x=0,y=0,z=0}
local pos={x=3,y=20,z=3}
local spawn_moves,diagonal,demolishing=0,nil,false
local status=""
local next_hud=0
local function noop() end
local p={
  get_player_name=function()return "Pilot" end,is_player=function()return true end,
  get_player_control=function()return keys end,
  get_pos=function()return pos end,
  set_pos=function()spawn_moves=spawn_moves+1 end,
  set_look_horizontal=noop,set_look_vertical=noop,
  get_look_dir=function()return {x=0,y=-1,z=0} end,
  get_properties=function()return {} end,
  get_velocity=function()return velocity end,
  add_velocity=function(_,delta)
    assert(delta.x==0 and delta.z==0,"server must not steer horizontal flight")
    velocity.y=velocity.y+delta.y
  end,
  set_physics_override=function(_,change)
    physics_calls=physics_calls+1
    for k,v in pairs(change) do override[k]=v end
  end,
  get_wield_index=function()return index end,
  get_wielded_item=function()return contents[index] end,
  get_inventory=function()return {set_stack=function(_,_,i,item)contents[i]=item end,set_size=noop} end,
  hud_set_flags=noop,hud_set_hotbar_itemcount=noop,hud_change=noop,hud_remove=noop,
  hud_add=function()next_hud=next_hud+1;return next_hud end,
}
core={
  get_modpath=function()return "mods/luanttd_core" end,get_us_time=function()return now end,
  get_connected_players=function()return {p} end,
  register_tool=noop,register_chatcommand=noop,register_allow_player_inventory_action=noop,
}
ItemStack=function(name)return name end
local ui={
  inventory=noop,select_tool=noop,phase=function()return 7 end,guide=function()return "" end,
  is_world_tool=function(tool)return tool=="clear" end,
  world_status=function()return "aim",status end,anchor=noop,
  status=function(_,note)status=note end,
  begin_demolition=function(_,id)assert(id==1);demolishing=true;return true end,
  end_demolition=function(_,id,is_diagonal)assert(demolishing and id==1);diagonal=is_diagonal;demolishing=false end,
}
local W=dofile("mods/luanttd_core/world.lua")({
  road_first=true,
  s={tiles={{h=1}},sites={},stations={},corner_grid={}},
  Sim={id=function()return 1 end,xy=function()return 1,1 end},
  terrain={pick=function()return 1,1 end},
  render={uses_slope=function()return false end},
},ui)
local function step(count)
  for _=1,count or 3 do now=now+100000;W.step(.1) end
end
W.spawn(p)
index=2 -- entering Roadworks carries the physical slot onto Bulldoze
W.go_menu(p,"roads")
for physical,authored in ipairs(W.hotbar_layout(p)) do
  if authored==9 then index=physical;break end
end
assert(contents[index]=="luanttd_core:menu_clear","find Bulldoze in the compact layout")
step(2) -- model the client settling after the menu's inventory update
assert(override.speed_walk==2 and override.speed_crouch==5.9 and physics_calls==1)
keys={dig=true};step()
assert(not demolishing and status:find("armed",1,true),"inherited Bulldoze must not dig on its first press")
step()
assert(not demolishing and diagonal==nil,"holding the first press never clears")
keys={};step()
keys={aux1=true,dig=true};step()
assert(demolishing and diagonal==nil and velocity.y==0,"E alone must not move vertically")
assert(override.speed_walk>4 and override.speed_crouch>12 and override.gravity==0 and physics_calls==2)
keys={aux1=true};step()
assert(diagonal==true and physics_calls==2,"E must reach build release and not resend identical physics")
keys={aux1=true,jump=true};step()
assert(velocity.y>13)
keys={jump=true};step()
assert(override.speed_walk==2 and override.speed_crouch==5.9 and velocity.y==6.3 and physics_calls==3)
keys={sneak=true,aux1=true};step()
assert(velocity.y<-13)
pos.y=3.4;step()
assert(velocity.y<0 and velocity.y>-.38,"boosted descent still brakes near the ground")
pos.y=65.9
keys={jump=true,aux1=true};step()
assert(velocity.y>0 and velocity.y<.38,"boosted ascent still brakes at the ceiling")
keys={};step()
assert(override.speed_walk==2 and physics_calls==5 and velocity.y==0 and spawn_moves==1,
  "release stops boost without absolute camera correction")
print("PASS: E flight boost and release, bounded lift, no camera resets, diagonal on build release")
