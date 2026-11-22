-- Verify authored routes remain intact when displayed as physical slots.
local H=dofile("mods/luanttd_core/hotbar.lua")
H.enable_structures(true);H.enable_trams();H.enable_ships();H.enable_airfields(true)
H.enable_freight();H.enable_railworks(true,true,true);H.enable_electric_rail();H.enable_rail_pair()
H.enable_rail_block();H.enable_ship_coal();H.enable_bay_termini();H.enable_oneway()
H.enable_rail_coal();H.enable_rail_goods()
for name,menu in pairs(H.menus) do
  local visible,map=H.compact(menu)
  local expected={}
  for i=1,H.size do if menu[i] then expected[i]=true end end
  local back,clear,teleport
  for i,entry in ipairs(visible) do
    local logical=map[i]
    if entry[1]=="teleport_tile" then
      assert(logical==H.teleport_slot and entry==H.teleport_tile,name)
      teleport=i
    else
      assert(expected[logical] and entry==menu[logical],name)
      expected[logical]=nil
    end
    if entry[1]=="back" then back=i end
    if entry[1]=="clear" then clear=i end
  end
  for logical in pairs(expected) do
    assert(#visible==H.size and menu[logical][1]=="inspect",name)
  end
  assert(#map==#visible and #visible<=H.size,name)
  if back then
    assert(back==1 and teleport==(clear and 3 or 2),name)
    local _,_,help=H.legend(assert(H.path(name)),teleport,true,visible)
    assert(help:find("Right-click to inspect",1,true),name)
  else assert(not teleport,name) end
  if clear then assert(clear==(back and 2 or 1),name) end
  local path=assert(H.path(name),name)
  local _,focus,help=H.legend(path,1,false,visible)
  if back then assert(focus=="1  Back" and help:find("1 Back",1,true),name) end
  if clear then assert(help:find(tostring(clear).." Bulldoze",1,true),name) end
end
for slot=1,H.size do
  local overlay,done,map=H.order_overlay(slot)
  local selected=math.min(slot,2)
  assert(#overlay==2 and #map==2 and overlay[done]==H.order_done)
  assert(overlay[selected]==H.order_pick and selected~=done)
  assert(map[selected]==1 and map[done]==8)
end

-- Exercise the real world controller against an engine-shaped inventory.
local registered,stacks={},{}
local now,index,cap,main,order=1000000,1,0,0,false
local builds,picks,finishes,teleports,inspections=0,0,0,0,0
local cancel_pending=false
core={
  register_tool=function(id,def) registered[id]=def end,
  get_modpath=function() return "mods/luanttd_core" end,
  get_us_time=function() return now end,
  register_chatcommand=function() end,
  register_allow_player_inventory_action=function() end,
  registered_items=registered,
}
local function noop() end
function ItemStack(id) return {get_name=function() return id end} end
local p={
  is_player=function()return true end,get_player_name=function()return "Alex" end,
  set_pos=noop,set_look_horizontal=noop,set_look_vertical=noop,set_physics_override=noop,hud_set_flags=noop,
  get_pos=function()return {x=2.25,y=6,z=3.25} end,
  get_properties=function()return {}end,
  get_look_dir=function()return {x=.1,y=-1,z=.2} end,
  get_wield_index=function()return index end,
  get_wielded_item=function()return stacks[index] end,
  get_inventory=function()return {
    set_size=function(_,list,size)assert(list=="main");main=size end,
    set_stack=function(_,list,i,item)assert(list=="main");stacks[i]=item end,
  }end,
  hud_set_hotbar_itemcount=function(_,count)assert(count<=main);cap=count end,
  hud_add=function()return 1 end,hud_change=noop,
}
local api={
  s={tiles={[515]={h=4}}},Sim={},road_first=true,rail_build_tools=true,rail_span_tools=true,structure_tools=true,bridge_picker={},
  terrain={pick=function()return 515,1.25 end},
  render={uses_slope=noop},selector={show=noop,area=noop},
}
local W
local ui={
  select_tool=noop, inventory=noop, is_world_tool=function(id)return id~=nil end,
  world_status=function()return "", "" end, guide=function() return "" end, phase=function()return 7 end,
  anchor=noop, inspect=function(_,tile) assert(tile==515);inspections=inspections+1 end,
  teleport_tile=function(_,tile,hit) assert(tile==515 and hit.x==2.375);teleports=teleports+1 end,
  cancel_build_selection=function() local old=cancel_pending;cancel_pending=false;return old end,
  build_world=function() builds=builds+1 end,
  order_picking=function()return order end,
  choose_order_stop=function()picks=picks+1 end,
  finish_order_pick=function()finishes=finishes+1;order=false;W.end_order_selection(p) end,
}
W=dofile("mods/luanttd_core/world.lua")(api,ui)
W.spawn(p)
local function at(name)
  for i=1,cap do if stacks[i]:get_name()=="luanttd_core:menu_"..name then return i end end
  error("Not present: "..name)
end
local function press(slot,last,method)
  index=slot
  local item=stacks[slot]
  local callback=registered[(last or item):get_name()]
  assert(callback)
  callback[method or "on_use"](last or item,p)
end
local function tick() now=now+200000 end
local function click(name) tick();press(at(name)) end
assert(main==10 and W.menu(p)=="home" and cap==8)
local map=W.hotbar_layout(p)
assert(map[8]==8); map[1]=99; assert(W.hotbar_layout(p)[1]==1)
click("section_railworks")
assert(W.menu(p)=="railworks" and at("back")==1 and at("clear")==2)
assert(W.hotbar_layout(p)[1]==8 and W.hotbar_layout(p)[2]==9)
assert(cap==10 and at("teleport_tile")==3)
click("teleport_tile"); assert(teleports==1 and builds==0 and W.menu(p)=="railworks")
cancel_pending=true
tick(); press(at("teleport_tile"),nil,"on_secondary_use"); assert(not cancel_pending and inspections==0)
tick(); press(at("teleport_tile"),nil,"on_secondary_use"); assert(inspections==1 and teleports==1)
click("section_railops")
local stale=stacks[at("rail_order_span")]
local stale_index=at("rail_order_span")
click("back")
-- A callback carrying the previous layout's ItemStack must not run the
-- new slot's tool, even after the pressed-click debounce expires.
tick();press(stale_index,stale);assert(builds==0 and W.menu(p)=="railworks")
click("back"); click("section_company")
assert(cap==6 and at("back")==1 and at("teleport_tile")==2)
for i=cap+1,main do assert(stacks[i]:get_name()=="") end
tick();press(8,stale);assert(builds==0 and W.menu(p)=="company")
for initial=1,10 do
  index=initial
  order=true
  W.begin_order_selection(p)
  assert(cap==2 and W.menu(p)=="vehicle_orders")
  for i=3,main do assert(stacks[i]:get_name()=="") end
  tick()
  if initial>2 then press(initial,stale); assert(picks==initial-1 and finishes==initial-1) end
  press(math.min(initial,2))
  assert(picks==initial and finishes==initial-1)
  click("order_done")
  -- Menu restoration does not consume the same triggering click.
  assert(finishes==initial and cap==6 and W.menu(p)=="company")
end
assert(builds==0)
print("PASS: compact utilities, active legends, stable logical map, stale clicks, and both modal selections")
