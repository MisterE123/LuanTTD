-- Drive the actual registered world tool callbacks without engine rendering.
local tools={}
local now=0
core={
  register_tool=function(id,def)assert(not tools[id]);tools[id]=def end,
  get_modpath=function()return "mods/luanttd_core" end,
  get_us_time=function()return now end,
  register_chatcommand=function()end,
  register_allow_player_inventory_action=function()end,
  registered_items=tools,
}
function ItemStack(name)return name end
local contents,selected,hud={},{},{}
local nilhit,flat=false,false
local index=1
local look={x=.1,y=-1,z=.2}
local p={
  get_player_name=function()return "Alex" end,
  is_player=function()return true end,
  get_pos=function()return {x=2.25,y=6,z=3.25} end,
  get_properties=function()return {}end,
  get_look_dir=function()return look end,
  get_wield_index=function()return index end,
  get_wielded_item=function()return contents[index] end,
  get_inventory=function()return {
    set_stack=function(_,list,i,it)assert(list=="main");contents[i]=it end,
    set_size=function(_,list,n)assert(list=="main" and n==10)end,
  }end,
  hud_add=function(_,details)hud[#hud+1]=details.text;return #hud end,
  hud_change=function(_,id,field,value)assert(field=="text");hud[id]=value end,
}
for _,k in ipairs({"set_pos","set_look_horizontal","set_look_vertical","set_physics_override","hud_set_flags","hud_set_hotbar_itemcount"}) do
  p[k]=function()end
end
local action_count,context_count,cancel_count,preview_count,orders_canceled=0,0,0,0,0
local pending,owned,fixed=false,false,false
local rail_picks,rail_commits,fixed_picks,fixed_commits=0,0,0,0
local last_build
local overlays={}
local ui={
  begin_fixed_route=function(_,tool)
    if tool=="ship_order" then fixed=true;return "Ferry orders" end
  end,
  fixed_route_active=function() return fixed end,
  fixed_route_ready=function() return fixed_picks>0 end,
  confirm_fixed_route=function()
    if fixed_picks>0 then fixed_commits=fixed_commits+1;fixed=false end
  end,
  cancel_fixed_route=function() fixed=false end,
  select_tool=function(_,tool)selected[#selected+1]=tool end,
  inventory=function()end,
  is_world_tool=function(tool)return tool=="rail_autotrack" or tool=="inspect" or tool=="clear" or (tool and tool:match("bridge_picker$")) end,
  world_status=function()return "aim","status"end,
  anchor=function()end,
  phase=function()return 7 end,
  guide=function()return ""end,
  inspect=function()end,
  build_world=function(_,id)assert(id==515);if fixed then fixed_picks=fixed_picks+1;return end;action_count=action_count+1;last_build=selected[#selected];pending=true end,
  cancel_rail_selection=function()
    if not pending then return false end
    pending=false;cancel_count=cancel_count+1;return true
  end,
  context=function(_,id)assert(id==515);context_count=context_count+1 end,
  rail_overlay=function(_,id)
    preview_count=preview_count+1
    if selected[#selected]=="rail_autotrack" and id then return {id=id} end
  end,
}
local api={
  s={tiles={[515]={h=4}}},Sim={id=function()if flat then return 515 end end},road_first=true,ship_tools=true,rail_build_tools=true,rail_span_tools=true,structure_tools=true,bridge_picker={},
  terrain={pick=function()if not nilhit then return 515,1.25 end end},
  render={uses_slope=function()end},
  selector={show=function()end,area=function()end,rail=function(_,preview)overlays[#overlays+1]=preview or false end},
  owned_rail_ui={active=function()return owned end,pick=function(_,id,stage)
      assert(id==515 and stage);rail_picks=rail_picks+1
    end,
    ready=function() return rail_picks>0 end,
    confirm=function()
      if rail_picks>0 then rail_commits=rail_commits+1;owned=false end
    end,
    cancel=function()orders_canceled=orders_canceled+1;owned=false end},
}
local W=dofile("mods/luanttd_core/world.lua")(api,ui)
W.spawn(p)
local function physical(slot)
  for at,authored in ipairs(W.hotbar_layout(p)) do if authored==slot then return at end end
  error("missing logical slot "..slot)
end
local function stack(slot)return contents[physical(slot)]end
local function use(slot,which)
  index=physical(slot);now=now+200000
  local item=contents[index]
  assert(tools[item],tostring(item))
  tools[item][which or "on_use"](item,p)
end
local t,hit=W.target(p)
assert(t==515 and hit.x==2.375 and hit.y==6.375 and hit.z==3.50)
look.y=0
assert(not W.target(p) and not select(2,W.target(p)))
look.y=-1
assert(stack(8)=="luanttd_core:menu_section_railworks")
use(8)
assert(W.menu(p)=="railworks" and stack(2)=="luanttd_core:menu_rail_autotrack")
assert(contents[3]=="luanttd_core:menu_teleport_tile" and stack(6)=="luanttd_core:menu_rail_span_tunnel")
assert(stack(9)=="luanttd_core:menu_clear" and stack(10)=="luanttd_core:menu_rail_bridge_picker")
assert(action_count==0,"menu navigation used a build tool")
use(2)
assert(action_count==1 and pending and overlays[#overlays].id==515)
local item=stack(2)
tools[item].on_use(item,p) -- duplicate notification from the same physical click
assert(action_count==1)
use(2,"on_place")
assert(cancel_count==1 and context_count==0 and not pending)
tools[item].on_secondary_use(item,p) -- duplicate right-click must not open context
assert(cancel_count==1 and context_count==0)
use(2,"on_place")
assert(cancel_count==1 and context_count==1)
nilhit=true
W.hud(p)
assert(not overlays[#overlays],"latest rail outline should clear without a target")
flat=true
local flat_tile,flat_hit=W.target(p)
assert(flat_tile==515 and flat_hit.x==2.5625 and flat_hit.y==4.5 and flat_hit.z==3.875)
nilhit,flat=false,false
use(7);assert(W.menu(p)=="railops")
use(1);assert(W.menu(p)=="railengineering")
use(7);assert(W.menu(p)=="railpieces")
use(8);assert(W.menu(p)=="railengineering")
use(8);assert(W.menu(p)=="railops")
use(8);assert(W.menu(p)=="railworks")
use(8);assert(W.menu(p)=="home")
assert(contents[#W.hotbar_layout(p)+1]=="")
use(2);assert(W.menu(p)=="roads" and stack(10)=="luanttd_core:menu_road_bridge_picker")
index=physical(2);now=now+200000;W.hud(p) -- explicitly leave the inherited Bulldoze
use(9);assert(last_build=="clear")
use(8);assert(W.menu(p)=="home")
use(2);use(7);use(3);assert(W.menu(p)=="structures")
assert(table.concat(hud," "):find("Road Options  ›  Bridge Types",1,true))
use(8);assert(W.menu(p)=="road_direction")
use(8);assert(W.menu(p)=="roads")
use(8);assert(W.menu(p)=="home")
use(5);assert(W.menu(p)=="navigation")
owned=true;W.begin_order_selection(p,"rail","Train orders")
assert(W.menu(p)=="vehicle_orders" and not W.go_menu(p,"railworks"))
use(8);assert(rail_commits==0 and owned,"incomplete dispatch did not keep the picker open")
use(1)
assert(rail_picks==1 and rail_commits==0 and action_count==2)
local duplicate=stack(1)
tools[duplicate].on_use(duplicate,p)
assert(rail_picks==1 and rail_commits==0)
use(8);assert(rail_commits==1 and not owned and W.menu(p)=="navigation")
owned=true;W.begin_order_selection(p,"rail","Train orders")
use(1,"on_place");assert(not owned and orders_canceled==1 and context_count==1)
assert(W.go_menu(p,"harbor_ops"))
use(2);assert(W.menu(p)=="vehicle_orders" and fixed and fixed_picks==0)
use(1);assert(fixed_picks==1 and fixed_commits==0 and fixed)
use(9);assert(not fixed and fixed_commits==0 and W.menu(p)=="harbor_ops")
use(2);use(1);use(8)
assert(fixed_commits==1 and W.menu(p)=="harbor_ops")
assert(W.go_menu(p,"railworks") and action_count==2 and preview_count>0)
use(8);assert(W.menu(p)=="home")
print("PASS: world hotbar navigation, exact picked tile, modal Pick/Dispatch/Cancel, duplicates and safe return")
