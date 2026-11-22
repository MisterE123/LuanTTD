local H=dofile("mods/luanttd_core/hotbar.lua")
local markup,opened,closed,launches
local config={}
core={settings={
  get=function(_,key)return config[key] end,
  set=function()error("the index is not a settings editor")end,
  write=function()error("the index must not write configuration")end,
},get_modpath=function()return "mods/luanttd_core" end,formspec_escape=function(s)return s end,
  show_formspec=function(n,key,b) assert(n=="Alex");opened=key;markup=b end,
  close_formspec=function(n,key)assert(n=="Alex");closed=key end,
  explode_textlist_event=function(spec)local typ,i=spec:match("^(%a+):(%d+)$")
    return {type=typ,index=tonumber(i)} end,
}
local p={get_player_name=function()return "Alex" end}
local S={tiles={}}
local last_menu,waiting_orders
local api={
  s=S,road_first=true,save=function()error("the index must not change the campaign save")end,
  world={
    has_menu=function(id)return H.path(id)~=nil end,
    menu_title=function(id)return H.menus[id].title end,
    go_menu=function(_,id)
      assert(H.path(id))
      if waiting_orders then return false,"Finish the current rail orders first." end
      launches=launches+1;last_menu=id;return true
    end,
  },
  Sim={
    id=function(x,z)return x+32*z end,
    road_stock_service_active=function()return S.clock end,
    foster_art_ready=function()return true end,
    stock_road_offer=function(_,id)
      if id=="foster_bus" then return {public=true} end
      if id=="bus" then return {status="retired"} end
    end,
  },
}
local function has(s) assert(markup:find(s,1,true),s) end
local function lacks(s) assert(not markup:find(s,1,true),s) end
local u=dofile("mods/luanttd_core/ui.lua")(api)
local form="luanttd_core:workbenches"
local function f(fields)return u.fields(p,form,fields)end
launches=0
assert(u.open_workbenches(p) and opened==form)
has("Transport & World Guide");has("Active  ·  Passenger bus service");has("Different map or year  ·  Original three-bus market")
has("Unavailable  ·  Two-bay bus terminus");has("Open Road Construction")
assert(f({wb_rows="CHG:2"}));lacks("bayline_road_bay_preview");lacks("wb_open;")
f({wb_open=true});assert(launches==0)
api.road_bay_tools=true
f({wb_rows="CHG:2"});has("Setup needed  ·  Two-bay bus terminus") -- flag alone is not a menu
H.enable_bay_termini()
f({wb_rows="DCL:2"});has("Available  ·  Two-bay bus terminus");has("Open Bus Stops");assert(launches==0)
waiting_orders=true;f({wb_open=true});has("Finish the current rail orders first.");assert(launches==0)
waiting_orders=false;f({wb_open=true})
assert(last_menu=="road_stops" and closed==form and launches==1)
f({wb_open=true});assert(launches==1) -- stale network form submission

S.stock_bus_market={settings={starting_year=1995}};S.clock=true
u.open_workbenches(p)
-- ID based row selection survives vanished/hidden features without launching any action.
f({wb_rows="CHG:7"});has("This market started in 1995.");has("Foster: on sale")
f({wb_rows="CHG:8"});has("Configured difficulty: 0.");lacks("wb_open;")
config.bayline_stock_bus_breakdowns="2"
f({wb_rows="CHG:8"});has("Configured difficulty: 2.");has("Open Fleet")
config.bayline_stock_bus_service_interval="90"
f({wb_rows="CHG:9"});has("Configured interval: 90 days.");has("Open Fleet")
config.bayline_stock_bus_service_percent="true"
f({wb_rows="CHG:9"});has("Configured interval: 90%.")
assert(launches==1)

f({wb_tab_scenarios=true});has("Different map or year  ·  Farm");has("Different map or year  ·  Oil Wells")
has("Different map or year  ·  Coastal flooding")
f({wb_rows="CHG:3"});has("Choose Farm and Factory");lacks("bayline_");lacks("wb_open;")
f({wb_rows="CHG:4"});has("Choose Oil and Refinery");lacks("bayline_");lacks("wb_open;")
f({wb_open=true});assert(launches==1)
api.coastal_flood_tools=true
f({wb_tab_scenarios=true});has("Available  ·  Coastal flooding")
f({wb_rows="CHG:6"});has("Runs on generated maps");has("Open Landscaping")
api.coastal_flood_tools=false
f({wb_rows="DCL:6"});assert(launches==1)
api.oil_tools=true;H.enable_freight()
f({wb_rows="CHG:4"});has("Open Road Freight")
f({wb_open=true});assert(last_menu=="freight" and launches==2)

u.open_workbenches(p)
f({wb_tab_rail=true});has("Unavailable  ·  Track, depots");lacks("wb_open;")
api.rail_build_tools,api.rail_build,api.rail_dispatch_controller=true,{},{}
H.enable_railworks(true,true);api.rail_span_tools=true;api.crossing_tools=true
f({wb_rows="CHG:4"});has("Open Rail Construction");f({wb_open=true})
assert(last_menu=="railworks" and launches==3 and closed==form)
local path=H.path(last_menu)
assert(table.concat(path,",")=="home,railworks")
assert(select(2,H.choose(path,8))=="home")
assert(not H.path("airfields"))

u.open_workbenches(p);f({key_escape=true});assert(closed==form and launches==3)
u.open_controls(p);assert(opened=="luanttd_core:service");has("service_workbenches;Transport & World Guide")
assert(u.fields(p,"luanttd_core:service",{service_workbenches=true}) and opened==form)
f({wb_back=true});assert(closed==form and launches==3)
u.leave("Alex")
f({wb_open=true});assert(launches==3)
print("PASS: discoverable workbench index, actual mount/readiness, fresh profiles, no configuration changes, explicit Open and Back")
