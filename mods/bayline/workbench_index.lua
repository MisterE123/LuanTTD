-- Read-only native index. The campaign decides what is mounted; opening a
-- workbench changes only the player's hotbar. Startup settings never change here.
return function(api)
  local S,Sim=api.s,api.Sim
  local I={form="bayline:workbenches"}
  local tabs={
    {"road","Road & Buses"},{"rail","Rail & Signals"},{"airwater","Harbor & Air"},
    {"scenarios","Scenarios"},{"world","World & Survey"},
  }
  local labels={live="Active",preview="Available",off="Unavailable",fresh="Different map",separate="Separate world",
    saved="Saved only",setup="Setup needed"}
  local colors={live="#95DBAD",preview="#95DBAD",off="#A8B7BF",fresh="#C5BAFD",separate="#C5BAFD",
    saved="#E0B9AE",setup="#F2A099"}
  local pages,views={},{}
  local function setting(name)
    return core.settings and core.settings.get and core.settings:get(name)
  end
  local function flag(name,default)
    if core.settings and core.settings.get_bool then return core.settings:get_bool(name,default) end
    local v=setting(name)
    if v==nil then return default end
    return v=="true" or v=="yes" or v=="on" or v=="1"
  end
  local function native(k) return function() return api[k] end end
  local function active_stock_road() return Sim.road_stock_service_active and Sim.road_stock_service_active(S) end
  local function cfg(k,v) return "bayline_"..k.." = "..tostring(v==nil and true or v) end
  local function rows(group,list)
    pages[group]=list
    for i,r in ipairs(list) do
      r.id,r.title,r.menu,r.enabled,r.try,r.config,r.extra=r[1],r[2],r[3],r[4],r[5],r[6],r[7]
      assert(r.id and r.title and r.enabled and r.try,group..": incomplete workbench "..i)
    end
  end
  local function has_bus_market()
    if S.stock_bus_market and not active_stock_road() then return "setup" end
    return S.stock_bus_market
  end
  local function bus_details()
    if not S.stock_bus_market then return end
    local out={}
    local year=S.stock_bus_market.settings and S.stock_bus_market.settings.starting_year
    if year then out[#out+1]="This market started in "..year.."." end
    if Sim.foster_art_ready and not Sim.foster_art_ready(S) then out[#out+1]="Foster art is not available in this installation." end
    if Sim.stock_road_offer then
      for _,spec in ipairs({{"bus","Regal"},{"leopard_bus","Hereford"},{"foster_bus","Foster"}}) do
        local offer=Sim.stock_road_offer(S,spec[1])
        if offer then out[#out+1]=spec[2]..": "..(offer.public and "on sale" or (offer.status or "off sale"):gsub("_"," ")) end
      end
    end
    if #out>0 then return table.concat(out,"  ") end
  end
  local function bus_faults()
    return S.stock_bus_market and active_stock_road()
  end
  local function breakdown_setting() return api.bus_breakdowns or tonumber(setting("bayline_stock_bus_breakdowns")) or 0 end
  local function interval_setting() return api.bus_service_interval or tonumber(setting("bayline_stock_bus_service_interval")) or 0 end
  local function rail()
    return api.rail_build_tools and api.rail_build and api.rail_dispatch_controller
  end
  local function fleet_details()
    if not api.rail_owned or not api.rail_owned.catalog then return end
    local out={}
    for _,row in ipairs(api.rail_owned.catalog(S) or {}) do
      if row.passenger_model_ready and row.availability and row.availability.public then out[#out+1]=row.name end
    end
    return #out>0 and ("Public, modeled engines now: "..table.concat(out,", ")..".") or
      "No public, modeled passenger locomotive is on sale in the current stock market."
  end
  local function available_menu(r)
    return r.menu and api.world and api.world.has_menu and api.world.has_menu(r.menu)
  end

  rows("road",{
    {"bus_service","Passenger bus service","roads",function() return api.road_first and "live" end,
      "Build one road, two bus stops near houses, and a depot. Inspect the depot to buy a bus. Go to its Fleet card, choose both stops and Start service. The Fleet card also shows orders and earnings."},
    {"bay","Two-bay bus terminus","road_stops",native("road_bay_tools"),
      "Use Two-bay bus terminus. Leave one legal, clear road entrance and use separate buses on the two stock bays. They still share the entrance.",
      {cfg("road_bay_preview")},"Build availability reflects this world's mounted stock road clock; saved terminals may keep operating even when additional construction is off."},
    {"oneway","One-way roads","road_direction",native("oneway_tools"),
      "Drag a road from start to end in the travel direction. Inspect it for arrows, genuinely barred turns and no-entry ends.",
      {cfg("road_oneway_preview")},"Stock directional roads and physical signs remain on a save after new painting is disabled."},
    {"stock_loading","Stock road loading","fleet",function() return active_stock_road() end,
      "Use a bus or freight route: at an accepting stop, inspect changes across the original timed load/unload pulses. A stopped, empty bus at an accepting stop can be sent to a real owned depot from its Fleet card.",
      {cfg("preview_stock_road_loading")},"Requires stock road motion and corner terrain. The original bus market and some freight scenarios enable it themselves."},
    {"overtake","Stock road overtaking","roads",function() return active_stock_road() end,
      "Run a fast bus behind a slower vehicle on a suitable two-way straight, away from intersections. The faster bus can occupy the other lane and return when there is room.",
      {cfg("preview_stock_road_loading")},"Ordinary stock road rules still decide when a pass is legal. This preview does not add universal vehicle collision behavior."},
    {"clearance","Road junction clearance","roads",function()
      return active_stock_road() and S.road_junction_clearance and "live"
    end,"Send two vehicles through the same junction. The optional 3D guard lets the first vehicle physically clear the shared space before the next reaches it.",
      {cfg("road_3d_junction_clearance")},"Set false to compare the exact stock viewport behavior; the guard is a native presentation/safety option, not an original OpenTTD rule."},
    {"regal","Original Regal depot offer","roads",function() return S.road_regal_enabled and active_stock_road() end,
      "Inspect an owned road depot to see the 31-seat MPS Regal with original prices and running charges. This is a single timeless offer; use Original bus market for real dates.",
      {cfg("stock_regal_preview")}},
    {"stock_bus","Original three-bus market","roads",has_bus_market,
      "Inspect a road depot for the MPS Regal, Hereford Leopard and Foster. Only public, modeled vehicles are offered. Start in 1950 for the early lineup or try 1995 for the Foster.",
      {cfg("stock_bus_catalog"),cfg("stock_bus_start_year",1950)},nil,fresh=true,detail=bus_details},
    {"faults","Original bus breakdowns","fleet",function()
      if not bus_faults() then return "setup" end
      return breakdown_setting()>0
    end,"In the Original bus market, inspect a running bus for its reliability. A scheduled fault can stop it temporarily. When disabled, existing faults are still allowed to finish repair.",
      {cfg("stock_bus_catalog"),cfg("stock_bus_breakdowns",1)},"Difficulty: 0 off, 1 reduced, 2 normal. Enable the market in a fresh world; changing difficulty for an established market needs restart.",
      detail=function() return bus_faults() and ("Configured difficulty: "..breakdown_setting()..".") end},
    {"service","Automatic bus depot service","fleet",function()
      if not bus_faults() then return "setup" end
      if interval_setting()>0 and breakdown_setting()==0 then return "setup" end
      return interval_setting()>0
    end,"Use an original bus and a reachable owned depot. At an eligible settled stop a due bus can temporarily detour for service; this does not replace its saved passenger schedule.",
      {cfg("stock_bus_catalog"),cfg("stock_bus_breakdowns",1),cfg("stock_bus_service_interval",90)},"0 disables new detours. Days: 5–800. For a reliability drop percentage, set bayline_stock_bus_service_percent = true and use 5–90. Install the market in a fresh world; interval and difficulty need restart.",
      detail=function()
        return bus_faults() and ("Configured interval: "..interval_setting()..
          (flag("bayline_stock_bus_service_percent",false) and "%." or " days.")) or nil
      end},
    {"order_lists","Copy or share road orders","fleet",function() return api.road_first and "live" end,
      "Stop the receiving and source vehicles as required in the Fleet card. Open Orders, choose Copy or Share, and select the other route. Shared lists keep each vehicle's own progress; Stop sharing empties only this vehicle's list."},
    {"mail","Town mail & postal routes",nil,function() return S.road_mail and api.terrain end,
      "Build truck stops near house catchments with /truckstop X Z. Inspect a road depot for the postal van, add a pickup stop and a delivery stop, and check Mail acceptance before starting.",
      {cfg("mail_preview")}},
  })

  rows("rail",{
    {"railworks","Track, depots & platforms","railworks",rail,
      "Use AutoRail for ordinary track, build a depot at a clear rail end, or select both ends of a straight station. Rail Tools & Operations opens pilots and manual construction tools.",
      {cfg("rail_construction_preview")}},
    {"pbs","Path signals and dispatch","railsignals",rail,
      "Place forward-facing regular or one-way PBS heads. Rotate the fitting to reverse the direction. Two empty trains can contest a diamond and release their reservations only when the rear wagon clears.",
      {cfg("rail_construction_preview")},"Keep PBS heads and conventional block heads in separate pilot layouts."},
    {"block","Conventional signal blocks","railsignals",function() return api.rail_block_tools and rail() end,
      "Place conventional heads before and after the shared unsigned diamond on each flat one-way route. Order two empty depot-to-platform trains to watch one wait at red until the other's tail clears the outgoing head.",
      {cfg("rail_block_preview")},"Use a separate disposable railway with only conventional heads, not PBS. No paid freight or passenger switching in this pilot."},
    {"railspan","Rail bridge & tunnel","railworks",function() return api.rail_span_tools and rail() end,
      "Use Bridge (0) to select two bridgeheads, or Tunnel (6) to click the entry slope. Connect both portals, then use Run train through rail spans. A coupled train keeps the span reserved until its final wagon clears.",
      {cfg("rail_construction_preview"),cfg("rail_span_preview")}},
    {"railgrade","Stock rail grades","railworks",function() return S.rail_grade_enabled and rail() end,
      "Lay compatible straight tracks on supported slopes. Compare climbing versus descending with the stock position and speed models.",
      {cfg("rail_construction_preview"),cfg("rail_grade_preview")}},
    {"crossing","Road–rail level crossings","railengineering",function()
      if api.crossing_tools and rail() then return true end
      return api.crossings and "saved"
    end,"Build on a flat owned tile with perpendicular road and rail. Run both modes to watch the striped barriers and how road traffic already on the crossing clears before rail enters.",
      {cfg("rail_construction_preview"),cfg("rail_crossing_preview")},"Saved crossings continue to operate even when new crossing construction is off."},
    {"railmoney","Paid rail passenger shuttle","railops",function() return S.rail_paid_service and rail() end,
      "Build two owned platforms in house catchments, then use the paid two-platform shuttle order or order a purchased locomotive. Inspect waiting passengers and fares.",
      {cfg("rail_construction_preview"),cfg("preview_paid_rail")}},
    {"ownedrail","Owned rail depot roster","railworks",function() return api.rail_owned and rail() end,
      "Inspect an owned rail depot. Buy an available engine with a passenger carriage and select two platforms. The Kirby, Jubilee, Ginzu A4 and Floss 47 use their own stock numbers and models.",
      {cfg("rail_owned_preview")},"For a fresh 1966 Temperate market with the Floss, enable bayline_stock_bus_catalog = true and set bayline_stock_bus_start_year = 1966 before creating the campaign.",
      detail=fleet_details},
    {"electricrail","Electrified rail and SH '30'","railtypes",native("electric_tools"),
      "Convert your complete flat route, both platforms and depot from Rail Types. An SH '30' only routes along powered rail. Steam and diesel can use both types.",
      {cfg("electric_rail_preview"),cfg("stock_bus_start_year",1970)},"Use a fresh generated game starting in 1970 for the SH '30'. Slopes, spans and junction conversions are not available yet.",
      fresh=true},
    {"railpair","Paired paid passenger trains","railops",function() return api.rail_owned_pair_tools and S.rail_paid_service end,
      "Stage one supported owned passenger consist per depot. Use Order two owned passenger trains, then pick each depot, origin and final platform. They may share a loading platform but park at different destinations.",
      {cfg("rail_owned_preview"),cfg("rail_pair_preview")}},
    {"railcoal","Rail coal freight","railfreight",native("rail_coal_tools"),
      "Designate separate coal loading and unloading platforms at a real mine and power station. Buy a Kirby with the coal wagon and choose mine first, power station second. The train delivers coal, not Goods.",
      {cfg("rail_owned_preview"),cfg("rail_coal_preview")},"Use a fresh seed-1751 inland coal world for the supplied real industries.",fresh=true},
    {"railoil","Rail oil tanker & road Goods","railfreight",native("rail_oil_tools"),
      "Designate an Oil Wells loader and refinery unloader. Buy Kirby + 30,000 L Oil Tanker, then order wells before refinery. Use a separate road Goods truck from the refinery to a town that accepts Goods.",
      {cfg("rail_owned_preview"),cfg("rail_oil_preview"),cfg("scenario","oil")},"Already have the Oil scenario? Enable owned rail and Rail Oil and restart it. Otherwise create a separate fresh seed-1751 Oil world, not Farm or Timber."},
    {"railgoods","Rail Goods Van","railfreight",native("rail_goods_tools"),
      "Use a working Timber chain. Designate the sawmill's loading platform and a town platform accepting Goods. Buy a Kirby with its covered 25-crate Goods Van and order the sawmill first.",
      {cfg("road_timber_preview"),cfg("rail_goods_preview")}},
    {"tracksurvey","Trackworks geometry sandbox",nil,function()
      return api.trackworks_demo and flag("bayline_trackworks_preview",false)
    end,"In a disposable sandbox use /trackworks X Z x, /trackroute X1 Z1 X2 Z2 and /trackrun X1 Z1 X2 Z2. Geometry and route survey only; use Railworks for commercial orders.",
      {cfg("trackworks_preview")}},
  })

  rows("airwater",{
    {"harbor","Harbor, canals & locks","harbor",native("ship_tools"),
      "Build a dock and ship depot. Open Waterworks for a canal, lock or aqueduct. A lock changes the vessel's height while the gates control transit.",
      {cfg("ship_preview")}},
    {"ferry","Ferry & passenger fares","harbor_ops",function() return api.ship_tools end,
      "Pick one owned ship depot and two reachable docks. With the paid setting enabled and houses in both catchments, a ferry loads passengers and earns fares.",
      {cfg("ship_preview"),cfg("preview_paid_ferry")},"The ordinary ferry is an empty pilot if paid ferry service is off.",
      detail=function() return api.ship_tools and (S.ship_paid_service and "Passenger fares enabled." or "Passenger fares off; empty run only.") end},
    {"yate","Yate coal ship & refit","harbor_ops",native("ship_coal_tools"),
      "Buy the Yate at an owned depot, refit its hold to coal, then use Order Yate coal ship to pick the mine dock followed by the power dock.",
      {cfg("ship_coal_preview"),cfg("scenario","south_coast")},"Use the fresh South Coast Coal preset for the working water layout."},
    {"airfield","Country airfield & trimotor","airfields",native("airport_tools"),
      "Place a flat stock 4×3 country airfield and a second one with enough approach clearance. Use the airfield orders or inspect a real hangar in the owned workbench.",
      {cfg("airport_preview")}},
    {"airfares","Passenger trimotor fares","airfields",function() return api.airport_tools and S.air_paid_service end,
      "Place country airfields whose catchments include houses, then order a compatible trimotor between them. Inspect waiting passengers and actual boarding and fares.",
      {cfg("airport_preview"),cfg("preview_paid_air")}},
    {"airpaid","Paid aircraft & hangar market","airfields",function()
      return api.airport_tools and S.air_owned_preview and S.air_paid_service
    end,"Inspect an owned hangar to buy an available Sampson U52 or Coleman Count. Order between two airfields with eligible passenger catchments and inspect boarding, fares and costs.",
      {cfg("air_owned_preview")},"Turn on bayline_preview_paid_air if a saved configuration explicitly set it false."},
    {"airpair","Shared runway and paid aircraft","airfields",function()
      return api.airport_tools and S.air_fleet_preview and S.air_paid_service
    end,"Buy two supported Sampsons in distinct hangars. Give them distinct orders with a common country airfield and watch the stock runway and terminal blocks sequence them.",
      {cfg("air_fleet_preview")},"Use separate real hangars and the supported fixed-wing country-airfield layout."},
    {"tram","Electric tram pilot","tramway",native("tram_tools"),
      "Build a dedicated tram line, one depot and two through stops. Select Order test streetcar (0), then click the depot and both stops.",
      {cfg("tram_preview")},"Clear test streetcar (7) keeps your infrastructure. This runs a test vehicle, not a paid commercial tram fleet."},
  })

  rows("scenarios",{
    {"preset","Main stock workbench preset",nil,function()
      if api.stock_workbenches_active~=nil then return api.stock_workbenches_active end
      return flag("bayline_stock_workbenches",false)
    end,"A generated campaign opens compatible workbenches automatically. Each entry here reports what actually mounted in this world.",
      {cfg("stock_workbenches")},"Individual settings explicitly set false still win. The preset doesn't create Farm, Oil or Original terrain worlds."},
    {"coal","Coal mine → power by road","freight",function()
      return api.stock_coal_scenery and api.freight_tools and S.road_coal
    end,"Build freight stops near the provided real coal mine and power station. Buy the original coal tipper and add a mine pickup followed by a power-station delivery.",
      {cfg("seed",1751),cfg("preview_coal_industry")},"Use a fresh default seed 1751; a restart of a normal saved campaign does not plant industries.",fresh=true},
    {"timber","Forest → sawmill → town Goods","freight",native("timber_tools"),
      "Use a wood truck to bring logs to the sawmill; then carry its Goods to a town freight stop that accepts them. Each stage uses the original production and station rules.",
      {cfg("seed",1751),cfg("road_timber_preview")},"Available in the ordinary campaign. Farm and Oil use separate fresh worlds instead of the Timber Goods chain.",fresh=true},
    {"farm","Farm → factory → town Goods","freight",native("farm_tools"),
      "Build truck stops at farm, factory and town; buy original grain and livestock vehicles for the two farm inputs, then a Goods truck from the factory to town. Inspect changing crop stages and actual factory stock.",
      {cfg("seed",1751),cfg("scenario","farm")},"Use a separate fresh world. Keep Timber and Oil off.",fresh=true},
    {"oil","Oil Wells → refinery → town Goods","freight",native("oil_tools"),
      "Haul oil from the wells to the refinery in the original Witcombe tanker; then use a Goods truck from the refinery to a town stop that accepts Goods. The Rail Oil row gives the optional rail first leg.",
      {cfg("seed",1751),cfg("scenario","oil")},"Use a separate fresh world. Keep Farm and Timber off.",fresh=true},
    {"coastal_coal","South Coast Coal by ship","harbor",function()
      return S.stock_coal_scenario=="south_coast_1751" and api.ship_coal_tools
    end,"On the seeded South Coast route, try docks at 8,32 and 5,32 and the east–west depot at 12,34. Buy and refit the Yate; order mine first and power second.",
      {cfg("seed",1751),cfg("ship_coal_preview"),cfg("scenario","south_coast")},"A separate fresh world; this changes the seeded sites, not just the tool menu.",fresh=true},
    {"original","Original stock map survey",nil,function()return "separate" end,
      "In the separate survey world: fly without a company or vehicles. Try /terrain coast, /terrain transect, /terrain summit and /terrain inspect.",
      {cfg("original_terrain_exploration"),cfg("original_terrain_width",64),cfg("original_terrain_depth",64),cfg("original_terrain_seed",1751)},
      "New SQLite world. Before starting, put the verified original-mapgen.bin in its folder using tools/extract_original_terrain_masks.py and a local OpenGFX 7.1 installation. Each axis is a power of two from 64 to 4096. See docs/original-terrain-exploration.md."},
    {"coastal_flood","Coastal flooding","terrain",native("coastal_flood_tools"),
      "At sea level, connect a cut to the open sea and let the stock landscape clock advance. An isolated cut remains dry.",
      {cfg("scenario","coastal")},
      "This already runs on generated worlds. Only set this to try the separate coastal scenario.",
      fresh=true},
    {"generated_world","Stock generated playable world","roads",native("generated_world"),
      "Create a 64×64 or 128×128 temperate map with stock TerraGenesis relief, towns, freight and scenery. The river and industry settings affect where later sites are placed.",
      {cfg("scenario","generated"),cfg("generated_map_size",64),cfg("seed",1751),cfg("generated_rivers",0)},
      "No setting is required for these terrain rules. Optional map settings apply when creating a world. Industry placement can leave some sites unbuilt. This map does not use OpenGFX assets.",fresh=true},
  })

  rows("world",{
    {"survey","Company map & jump survey","navigation",function() return api.road_first and "live" end,
      "Use Jump Map to fly to a selected tile. Inspect land, track, stop catchments, and industries from the world. The separate Original map survey does not replace this campaign."},
    {"landscape","Corner terrain landscaping","terrain",function() return api.terrain and "live" end,
      "Raise or lower a single corner, use the area tools on a selection, or level terrain. Compare the shared corners, slopes and required foundations before building.",
      {cfg("preview_terrain")},"Hold Aux1 (usually E) on the second click for a diagonal selection."},
    {"bridges","Road bridges & road tunnels","roads",native("structure_tools"),
      "Choose Bridge (0) and mark both bridgeheads, or use Tunnel (6) on a compatible entry slope with a clear exit. Join both ends to roads to run a bus through the structure.",
      {cfg("bridge_construction_preview")}},
    {"growth","Original town house growth","roads",function()
      if api.town_growth and flag("bayline_stock_town_growth",true) then return true end
      return S.stock_town_growth and "saved"
    end,"Serve a real town along existing roads and inspect a newly started house. New occupants contribute passengers and mail after construction completes.",
      {cfg("stock_town_growth")},"Turning this off suspends new construction; already-started houses can finish."},
    {"offline","Offline company economy",nil,function()
      return (api.offline_economy or flag("bayline_offline_economy",false)) and "live"
    end,"For a server with a paid route, leave with no players connected, then rejoin and inspect changed time, cargo and finance. Pausing still stops time; empty demonstration pilots aren't simulated offscreen.",
      {cfg("offline_economy")}},
  })

  local function status(r)
    local state=r.enabled()
    if type(state)=="string" and labels[state] then return state end
    if state then
      if r.menu and not available_menu(r) then return "setup" end
      return "preview"
    end
    return r.fresh and "fresh" or "off"
  end
  local function openable(r,state)
    return (state=="live" or state=="preview") and available_menu(r)
  end
  local function category(key)
    local result={}
    for _,r in ipairs(pages[key]) do
      if not r.visible or r.visible() then result[#result+1]=r end
    end
    return result
  end
  local function selected(v,list)
    for i,r in ipairs(list) do if r.id==v.row then return r,i end end
    return list[1],1
  end
  local function esc(t) return core.formspec_escape(t) end

  function I.open(p)
    if not api.road_first then return false end
    local n=p:get_player_name()
    local v=views[n] or {tab="road"}
    v.open=true;views[n]=v
    local list=category(v.tab)
    local r,chosen=selected(v,list)
    v.row=r.id
    local state=status(r)
    local b={"formspec_version[7]size[15,9.8]bgcolor[#10212B;false]",
      "style_type[button;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA;noclip=false]",
      "style_type[label;textcolor=#E5ECEA]"}
    local function add(part) b[#b+1]=part end
    local function label(x,y,text) add(("label[%g,%g;%s]"):format(x,y,esc(text))) end
    local function button(x,y,width,name,text)
      add(("button[%g,%g;%g,.54;%s;%s]"):format(x,y,width,name,esc(text)))
    end
    label(.42,.38,"LuanTTD  /  Workbenches & Scenarios")
    label(.42,1.00,"What is playable in this world, where to find it, and how to set up separate worlds.")
    for i,tab in ipairs(tabs) do
      local key,title=tab[1],tab[2]
      if v.tab==key then add("style[wb_tab_"..key..";textcolor=#FFDB8F]") end
      button(.42+(i-1)*2.88,1.49,2.63,"wb_tab_"..key,title)
    end
    local names={}
    for _,entry in ipairs(list) do
      local st=status(entry)
      names[#names+1]=(colors[st] or "")..esc(labels[st].."  ·  "..entry.title)
    end
    add("textlist[.42,2.33;6.55,6.21;wb_rows;"..table.concat(names,",")..";"..chosen..";false]")
    label(7.24,2.37,r.title)
    label(7.24,2.93,labels[state].." in this world")
    local details={r.try}
    if r.detail then
      local text=r.detail()
      if text then details[#details+1]=text end
    end
    if r.extra then details[#details+1]=r.extra end
    if r.config then
      local title=(r.fresh or state=="fresh" or state=="separate") and "Fresh world configuration:" or
        "Config (restart required):"
      details[#details+1]=title.."\n"..table.concat(r.config,"\n")
    end
    if v.note then details[#details+1]=v.note end
    add("textarea[7.24,3.38;7.30,4.95;;;"..esc(table.concat(details,"\n\n")).."]")
    if openable(r,state) then
      button(7.24,8.12,7.30,"wb_open","Open "..(api.world.menu_title and api.world.menu_title(r.menu) or "workbench"))
    end
    label(.42,8.77,"Active and Available features are ready to use in this world.")
    button(.42,9.07,14.10,"wb_back","Back to world")
    core.show_formspec(n,I.form,table.concat(b))
    return true
  end

  function I.fields(p,f)
    local n=p:get_player_name()
    local v=views[n]
    if not v or not v.open then return true end
    if f.quit or f.wb_back or f.key_escape then
      v.open=false
      core.close_formspec(n,I.form)
      return true
    end
    for _,tab in ipairs(tabs) do
      if f["wb_tab_"..tab[1]] then
        v.tab,v.row,v.note=tab[1],nil,nil
        return I.open(p)
      end
    end
    local list=category(v.tab)
    if f.wb_rows then
      local event=core.explode_textlist_event(f.wb_rows)
      if event and (event.type=="CHG" or event.type=="DCL") and list[event.index] then
        v.row,v.note=list[event.index].id,nil
        -- Selecting an entry (including Enter/double-click on a textlist)
        -- never navigates, enables settings or issues an action by itself.
        return I.open(p)
      end
    end
    if f.wb_open then
      local r=selected(v,list)
      if openable(r,status(r)) and api.world.go_menu then
        local ok,why=api.world.go_menu(p,r.menu)
        if ok then
          v.open=false
          core.close_formspec(n,I.form)
          return true
        end
        v.note=why or "This workbench isn't available in the live hotbar."
        return I.open(p)
      end
    end
    return true
  end
  function I.leave(name) views[name]=nil end
  return I
end
