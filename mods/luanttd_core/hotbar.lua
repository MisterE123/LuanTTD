-- Menu data and stack, deliberately independent of Luanti. A menu entry
-- is {id, label, icon}; section IDs match the destination menu key.
local H={size=10}
local function icon(s) return "bl_dispatch_"..s..".png" end
local function item(id,label,image) return {id,label,icon(image or id)} end
local back=item("back","Back")
local inspect=item("inspect","Inspect")
local bulldoze=item("clear","Bulldoze","bulldoze")
local jump=item("jump","Jump map")
H.teleport_tile=item("teleport_tile","Teleport above tile")
-- A shared display utility, not an authored navigation slot.
H.teleport_slot=H.size+1
local workbenches=item("workbench_index","Transport & World Guide","workbenches")
H.order_pick=item("order_pick","Pick stop","order_stop")
H.order_done=item("order_done","Done","order_done")
H.order_cancel=item("order_cancel","Cancel orders","back")
H.order_dispatch=item("order_dispatch","Dispatch","order_done")
H.order_review=item("order_review","Review orders","rail_order_review")
function H.order_overlay(slot,mode,label)
  if mode and mode~="road" then
    local pick=math.min(slot,3)
    local done=pick==1 and 2 or 1
    local cancel=6-pick-done
    local menu={title=label or "Route orders",[pick]=H.order_pick,[done]=H.order_dispatch,[cancel]=H.order_cancel}
    local layout={[pick]=1,[done]=8,[cancel]=9}
    if mode=="rail_sequence" then menu[4]=H.order_review;layout[4]=10 end
    return menu,done,layout,cancel
  end
  -- Luanti retains the physical wield index, clamped to the last visible
  -- slot on a shrink. Put Pick where it will land, never Done.
  local pick=slot>1 and 2 or 1
  local done=3-pick
  return {title="Vehicle orders",[pick]=H.order_pick,[done]=H.order_done},done,
    {[pick]=1,[done]=8}
end
local function section(id,label,asset) return item("section_"..id,label,asset) end
H.menus={
  home={title="Transport & construction",
    [1]=section("survey","Survey","survey_map"),
    [2]=section("roads","Roadworks","roadworks"),
    [3]=section("fleet","Fleet","fleet_garage"),
    [4]=section("company","Company","company_index"),
    [5]=section("navigation","Navigation","navigation_compass"),
    [6]=section("options","Controls","settings_menu"),
    [7]=section("terrain","Landscaping","terrain"),
  },
  survey={title="Survey",[1]=inspect,[2]=jump,[3]=workbenches,[8]=back},
  roads={title="Road Construction",[1]=inspect,[2]=item("road","AutoRoad: click or drag"),
    [3]=item("road_station","Bus stop","stop"),
    [4]=item("road_depot","Road depot","depot"),
    [7]=section("road_direction","Road Options","road_tools"),[8]=back},
  road_direction={title="Road Options",[1]=inspect,[8]=back},
  terrain={title="Landscaping",[1]=inspect,[2]=item("landscape_raise","Raise corner","raise"),
    [3]=item("landscape_lower","Lower corner","lower"),
    [4]=item("landscape_level","Level area","level"),[5]=item("landscape_raise_area","Raise area","raise_area"),
    [6]=item("landscape_lower_area","Lower area","lower_area"),[8]=back},
  fleet={title="Fleet",[1]=inspect,[3]=item("company","Road vehicles","fleet"),[8]=back},
  company={title="Company",[4]=item("finance","Finances"),
    [5]=item("pause","Pause","pause"),[6]=item("normal_speed","Normal speed","normal_speed"),
    [7]=item("fast","Fast forward","fast_forward"),[8]=back},
  navigation={title="Navigation",[1]=inspect,[5]=jump,[8]=back},
  options={title="Controls",[2]=workbenches,[6]=item("controls","Controls"),[8]=back},
}
local function build_utilities()
  for _,id in ipairs({"roads","road_direction","road_stops","terrain","structures","tramway",
      "harbor","waterworks","airfields","freight","railworks","railengineering","railpieces","railsignals","railtypes","railwaypoints"}) do
    if H.menus[id] then H.menus[id][9]=bulldoze end
  end
end
build_utilities()
-- The same key never opens a different transport mode based on which
-- features mounted first. Transport tools live under their own mode,
-- not in Navigation. Slots 8/9 have one role within construction menus.
local gates={
  railworks=section("railworks","Rail Construction","railworks"),
  structures=section("structures","Bridge Types","structure_index"),
  tramway=section("tramway","Tramways","tramways"),
  harbor=section("harbor","Harbors","harbor_index"),
  airfields=section("airfields","Airfields","airfields_index"),
  freight=section("freight","Road Freight","freight"),
  portair=section("portair","Sea & Air","port_air"),
}
local function sync_sections()
  build_utilities()
  local menus=H.menus
  menus.home[8]=menus.railworks and gates.railworks or nil
  if menus.harbor or menus.airfields then
    menus.portair={title="Sea & Air", [2]=menus.harbor and gates.harbor or nil,
      [3]=menus.airfields and gates.airfields or nil,[8]=back}
    menus.home[10]=gates.portair
  end
  menus.roads[5]=menus.freight and gates.freight or nil
  menus.road_direction[3]=menus.structures and menus.roads[10][1]~="section_structures" and gates.structures or nil
  menus.road_direction[4]=menus.tramway and gates.tramway or nil
  menus.road_direction[6]=menus.tramway and item("bend","Switch tram bend") or nil
  menus.roads[7]=(menus.road_direction[2] or menus.road_direction[3] or menus.road_direction[4])
    and section("road_direction","Road Options","road_tools") or nil
end
sync_sections()
function H.enable_structures(picker)
  H.menus.roads[10]=picker and item("road_bridge_picker","Build road bridge","road_bridge_picker") or
    gates.structures
  H.menus.roads[6]=item("structure_tunnel","Build road tunnel","tunnel")
  H.menus.structures={title="Bridge Types",[1]=inspect,
    [2]=item("structure_wood","Timber bridge","bridge"),
    [3]=item("structure_steel","Steel girder","girder"),
    [5]=item("structure_concrete","Concrete bridge","concrete"),[8]=back}
  sync_sections()
end
function H.enable_trams()
  H.menus.tramway={title="Electric Tramways",[1]=inspect,
    [2]=item("tram_track","Lay tramway","tram"),[3]=item("tram_stop","Through platform","tram_stop"),
    [4]=item("tram_depot","Tram depot","tram_depot"),[5]=item("tram_bit","Tramway half-piece","tram_half"),
    [6]=item("tram_rotate","Rotate direction","tram_rotate"),
    [7]=item("tram_clear","Clear test streetcar","tram_clear"),[8]=back,
    [10]=item("tram_order","Order test streetcar","tram_order")}
  sync_sections()
end
function H.enable_ships()
  H.menus.harbor={title="Harbor Construction",[1]=inspect,
    [2]=item("ship_dock","Build dock","harbor"),[3]=item("ship_depot","Ship depot","ship_depot"),
    [4]=section("waterworks","Waterworks","waterworks"),
    [5]=item("ship_remove","Dismantle facility","ship_remove"),[6]=item("ship_rotate","Rotate ship depot","ship_rotate"),
    [7]=section("harbor_ops","Ferry Operations","harbor_ops"),[8]=back}
  H.menus.harbor_ops={title="Ferry Operations",[1]=inspect,
    [2]=item("ship_order","Order ferry","ferry"),[7]=item("ship_clear","Clear ferry pilot","ship_clear"),[8]=back}
  H.menus.waterworks={title="Waterworks",[1]=inspect,
    [2]=item("ship_canal","Dig canal","canal"),[3]=item("ship_lock","Ship lock","lock"),
    [4]=item("ship_aqueduct","Aqueduct","aqueduct"),[5]=item("ship_remove","Dismantle facility","ship_remove"),
    [6]=item("ship_buoy","Place public buoy","ship_buoy"),
    [7]=item("ship_buoy_remove","Remove buoy, keep water","ship_buoy_remove"),[8]=back}
  sync_sections()
end
function H.enable_airfields(owned)
  H.menus.airfields={title="Airfields",[1]=inspect,[2]=item("airfield_build","Build country airfield","airfield"),
    [3]=item("airfield_order",owned and "Order aircraft" or "Order trimotor","trimotor"),
    [5]=item("airfield_remove","Dismantle airfield","airfield_remove"),
    [7]=not owned and item("airfield_clear","Clear flight pilot","airfield_clear") or nil,[8]=back}
  sync_sections()
end
function H.enable_ship_coal()
  if H.menus.harbor_ops then
    H.menus.harbor[7]=section("harbor_ops","Vessel Operations","harbor_ops")
    H.menus.harbor_ops.title="Vessel Operations"
    H.menus.harbor_ops[3]=item("ship_coal_order","Order Yate coal ship","ship_coal_order")
  end
end
function H.enable_railworks(spans,crossings,picker)
  local engineering=section("railengineering","Rail Engineering","rail_engineering")
  local bridge=picker and item("rail_bridge_picker","Build rail bridge","rail_bridge_picker") or item("rail_span_bridge","Build timber rail bridge","rail_span_bridge")
  H.menus.railworks={title="Rail Construction",[1]=inspect,[2]=item("rail_autotrack","AutoRail","rail_auto"),
    [3]=item("rail_platform","Rail station","rail_platform"),[4]=item("rail_depot_tool","Rail depot","rail_depot"),
    [5]=section("railsignals","Rail signals","rail_signals"),
    [6]=spans and item("rail_span_tunnel","Build rail tunnel","rail_tunnel") or engineering,
    [7]=section("railops","Rail Tools & Operations","rail_ops"),[8]=back,[10]=spans and bridge or nil}
  H.menus.railops={title="Rail Tools & Operations",[1]=engineering,[2]=item("rail_order_one","Order a depot-to-platform pilot","rail_order_one"),
    [3]=item("rail_order_shuttle","Order a two-platform shuttle","rail_shuttle"),
    [7]=item("rail_clear_run","Clear rail pilot","rail_clear_run"),[8]=back}
  local tools={title="Rail Engineering",[1]=inspect,
    [6]=item("rail_rotate","Rotate railway fitting","rail_rotate"),
    [7]=section("railpieces","Manual track pieces","rail_pieces"),[8]=back}
  H.menus.railengineering=tools
  if spans then
    tools[2]=bridge
    tools[3]=item("rail_span_tunnel","Build rail tunnel","rail_tunnel")
    tools[5]=item("rail_span_clear","Remove rail span","rail_span_clear")
    H.menus.railops[4]=item("rail_order_span","Run train through rail spans","rail_order_span")
  end
  if crossings then tools[4]=item("rail_crossing_tool","Road / rail level crossing","level_crossing") end
  H.menus.railpieces={title="Manual Track Pieces",[1]=item("rail_track_x","East–West straight","rail_x"),
    [2]=item("rail_track_y","North–South straight","rail_y"),[3]=item("rail_track_upper","Upper curve","rail_upper"),
    [4]=item("rail_track_lower","Lower curve","rail_lower"),[5]=item("rail_track_left","Left curve","rail_left"),
    [6]=item("rail_track_right","Right curve","rail_right"),[7]=item("rail_piece_remove","Toggle piece removal","rail_piece_remove"),[8]=back}
  H.menus.railsignals={title="Rail Signals",[1]=inspect,[2]=item("rail_signal_pbs","Path signal","rail_signal"),
    [3]=item("rail_signal_oneway","One-way path signal","rail_oneway"),
    [5]=item("rail_signal_remove","Remove rail signal","rail_signal_remove"),[6]=item("rail_rotate","Rotate railway fitting","rail_rotate"),[8]=back}
  sync_sections()
end
function H.enable_rail_waypoints()
  if not H.menus.railops then return end
  H.menus.railops[9]=section("railwaypoints","Rail Waypoints","rail_waypoints")
  H.menus.railwaypoints={title="Rail Waypoints",[1]=inspect,
    [2]=item("rail_waypoint_place","Place railway waypoint","rail_waypoint"),
    [3]=item("rail_waypoint_remove","Remove waypoint, keep rail","rail_waypoint_remove"),[8]=back}
  build_utilities()
end
function H.enable_electric_rail()
  if not H.menus.railengineering then return end
  H.menus.railengineering[1]=section("railtypes","Rail Types","rail_types")
  H.menus.railtypes={title="Rail Types",[1]=inspect,
    [2]=item("rail_electrify","Electrify railway","rail_electrify"),
    [3]=item("rail_deelectrify","Convert to ordinary rail","rail_deelectrify"),[8]=back}
  build_utilities()
end
local function rail_freight_menu()
  if not H.menus.railops then return end
  H.menus.railops[5]=section("railfreight","Rail Freight","rail_freight")
  local menu=H.menus.railfreight or {title="Rail Freight",[1]=inspect,[8]=back}
  H.menus.railfreight=menu
  return menu
end
function H.enable_rail_coal()
  local menu=rail_freight_menu()
  if not menu then return end
  menu[2]=item("rail_coal_load","Designate coal loading stage","coal_load")
  menu[3]=item("rail_coal_unload","Designate coal unloading stage","coal_unload")
  menu[6]=item("rail_coal_flip","Switch platform side","coal_flip")
end
function H.enable_rail_goods()
  local menu=rail_freight_menu()
  if not menu or menu[4] or menu[5] then return end
  menu[4]=item("rail_goods_load","Sawmill: designate Goods loading platform","goods_load")
  menu[5]=item("rail_goods_unload","Town: designate Goods delivery platform","goods_unload")
end
function H.enable_rail_oil()
  local menu=rail_freight_menu()
  if not menu then return end
  menu[4]=item("rail_oil_load","Oil wells: designate loading platform","oil_load")
  menu[5]=item("rail_oil_unload","Oil refinery: designate unloading platform","oil_unload")
end
function H.enable_rail_pair()
  if H.menus.railops then
    H.menus.railops[6]=item("rail_order_pair","Order two owned passenger trains","rail_pair")
  end
end
function H.enable_rail_block()
  if not H.menus.railsignals then return end
  H.menus.railsignals[4]=item("rail_signal_block","Conventional block signal","block_signal")
  H.menus.railsignals[7]=item("rail_order_block","Order a conventional block-signal pilot","rail_order_block")
end
function H.enable_oneway()
  H.menus.road_direction[2]=item("oneway_drag","Paint a one-way route","oneway_road")
  sync_sections()
end
function H.enable_bay_termini()
  H.menus.roads[3]=section("road_stops","Bus Stops","bus_stops")
  H.menus.road_stops={title="Bus Stops",[1]=inspect,
    [2]=item("road_station","Roadside bus stop","stop"),
    [3]=item("road_bay_pair","Two-bay bus terminus","bus_terminus"),[8]=back}
  build_utilities()
end
function H.enable_freight()
  H.menus.freight={title="Road Freight",[1]=inspect,[2]=item("road","AutoRoad: click or drag"),
    [3]=item("truck_stop_tool","Truck stop","truck_stop"),[4]=item("road_depot","Road depot","depot"),
    [8]=back}
  sync_sections()
end
-- Keep the authored slots stable for gates and workbench routes. Present
-- common utilities first and pack feature-dependent tools in authored order.
function H.compact(menu)
  local visible,map={title=menu.title},{}
  local function add(slot, entry)
    visible[#visible+1] = entry
    map[#map+1] = slot
  end
  local function utility(id)
    for slot=1,H.size do
      local entry=menu[slot]
      if entry and entry[1]==id then add(slot,entry) end
    end
  end
  utility("back")
  utility("clear")
  local submenu = visible[1] and visible[1][1]=="back"
  local count=0
  for slot=1,H.size do if menu[slot] then count=count+1 end end
  -- Where the authored row is already full, Inspect remains available
  -- through Teleport's secondary click instead of requiring an 11th key.
  local alternate_inspect=submenu and count==H.size
  if submenu then add(H.teleport_slot,H.teleport_tile) end
  for slot=1,H.size do
    local entry=menu[slot]
    if entry and entry[1]~="back" and entry[1]~="clear"
        and not (alternate_inspect and entry[1]=="inspect") then add(slot,entry) end
  end
  assert(#visible<=H.size,"Full hotbar needs an Inspect alternate: "..menu.title)
  return visible,map
end

-- Search the mounted menu graph, not a static list of assumed features.
-- Returns a fresh canonical path for the ordinary Back action.
function H.path(target)
  if not H.menus[target] then return end
  local queue,seen={{"home"}},{home=true}
  local i=1
  while i<=#queue do
    local path=queue[i]
    local at=path[#path]
    if at==target then return path end
    for slot=1,H.size do
      local item=H.menus[at][slot]
      local key=item and item[1]:match("^section_(.+)$")
      if key and not seen[key] and H.menus[key] then
        seen[key]=true
        local next_path={}
        for j,v in ipairs(path) do next_path[j]=v end
        next_path[#next_path+1]=key
        queue[#queue+1]=next_path
      end
    end
    i=i+1
  end
end

function H.active(stack)
  return stack[#stack] or "home"
end
function H.shortcut(slot)
  return slot==H.size and "0" or tostring(slot)
end

function H.legend(stack,slot,is_world_tool,visible)
  local active=H.active(stack)
  local menu=visible or H.menus[active]
  local selected=menu[slot]
  local title=menu.title
  if active~="home" and #stack>2 then
    title=H.menus[stack[#stack-1]].title.."  ›  "..title
  end
  local focus=selected and (H.shortcut(slot).."  "..selected[2]) or "Select a tool or section"
  local help={}
  if selected then
    local id=selected[1]
    if id=="back" then
      help[1]="Left-click to return"
    elseif id:match("^section_") then
      help[1]="Left-click to open"
    elseif id=="teleport_tile" then
      help[1]="Left-click to teleport"
      help[2]="Right-click to inspect"
    elseif is_world_tool then
      help[1]=(id=="road" or id=="clear" or id=="oneway_drag")
        and "Click or drag in the world" or "Left-click to use"
      if id~="inspect" then help[#help+1]="Right-click to cancel" end
    else
      help[1]="Left-click to activate"
    end
  else
    help[1]="Number keys or wheel to select"
  end
  for i=1,H.size do
    local entry=menu[i]
    if entry and (entry[1]=="back" or entry[1]=="clear") then
      help[#help+1]=H.shortcut(i).." "..entry[2]
    end
  end
  return title, focus, table.concat(help,"   ·   ")
end

function H.choose(stack,slot)
  local e=H.menus[H.active(stack)][slot]
  if not e then return end
  local id=e[1]
  if id=="back" then
    if #stack>1 then table.remove(stack) end
    return "menu",H.active(stack)
  end
  local next_menu=id:match("^section_(.+)$")
  if next_menu and H.menus[next_menu] then
    stack[#stack+1]=next_menu
    return "menu",next_menu
  end
  return "action",id
end
return H
