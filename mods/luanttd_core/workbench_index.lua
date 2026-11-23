-- Read-only native index. The campaign decides what is mounted; opening a
-- workbench changes only the player's hotbar. Startup settings never change here.
return function(api)
  local S,Sim=api.s,api.Sim
  local I={form="luanttd_core:workbenches"}
  local tabs={
    {"road","Road & Buses"},{"rail","Rail & Signals"},{"airwater","Harbor & Air"},
    {"scenarios","Scenarios"},{"world","World & Survey"},
  }
  local labels={live="Active",preview="Available",off="Unavailable",fresh="Different map or year",separate="Separate world",
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
  local function rows(group,list)
    pages[group]=list
    for i,r in ipairs(list) do
      r.id,r.title,r.menu,r.enabled,r.try,r.extra=r[1],r[2],r[3],r[4],r[5],r[7]
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
      nil,"Both bays can operate independently while sharing the same entrance."},
    {"oneway","One-way roads","road_direction",native("oneway_tools"),
      "Drag a road from start to end in the travel direction. Inspect it for arrows, genuinely barred turns and no-entry ends.",
      nil,"Reverse the drag to change the allowed direction."},
    {"stock_loading","Stock road loading","fleet",function() return active_stock_road() end,
      "Use a bus or freight route: at an accepting stop, inspect changes across the original timed load/unload pulses. A stopped, empty bus at an accepting stop can be sent to a real owned depot from its Fleet card.",
      nil,"Wait at a loading stop to see these pulses on the vehicle card."},
    {"overtake","Stock road overtaking","roads",function() return active_stock_road() end,
      "Run a fast bus behind a slower vehicle on a suitable two-way straight, away from intersections. The faster bus can occupy the other lane and return when there is room.",
      nil,"Ordinary stock road rules still decide when a pass is legal. This preview does not add universal vehicle collision behavior."},
    {"clearance","Road junction clearance","roads",function()
      return active_stock_road() and S.road_junction_clearance and "live"
    end,"Send two vehicles through the same junction. The 3D guard lets the first vehicle physically clear the shared space before the next reaches it.",
      nil,"The guard is a LuanTTD adaptation for the 3D vehicles."},
    {"stock_bus","Original three-bus market","roads",has_bus_market,
      "Inspect a road depot for the MPS Regal, Hereford Leopard and Foster. Only public, modeled vehicles are offered. Start in 1950 for the early lineup or try 1995 for the Foster.",
      nil,nil,fresh=true,detail=bus_details},
    {"faults","Original bus breakdowns","fleet",function()
      if not bus_faults() then return "setup" end
      return breakdown_setting()>0
    end,"In the Original bus market, inspect a running bus for its reliability. A scheduled fault can stop it temporarily. When disabled, existing faults are still allowed to finish repair.",
      nil,"Difficulty: 0 off, 1 reduced, 2 normal. Change Vehicle breakdown difficulty in the OpenTTD options.",
      detail=function() return bus_faults() and ("Configured difficulty: "..breakdown_setting()..".") end},
    {"service","Automatic bus depot service","fleet",function()
      if not bus_faults() then return "setup" end
      if interval_setting()>0 and breakdown_setting()==0 then return "setup" end
      return interval_setting()>0
    end,"Use an original bus and a reachable owned depot. At an eligible settled stop a due bus can temporarily detour for service; this does not replace its saved passenger schedule.",
      nil,"0 disables new detours. Days: 5–800. For a reliability drop percentage, use the OpenTTD service interval unit and choose 5–90.",
      detail=function()
        return bus_faults() and ("Configured interval: "..interval_setting()..
          (flag("bayline_stock_bus_service_percent",false) and "%." or " days.")) or nil
      end},
    {"order_lists","Copy or share road orders","fleet",function() return api.road_first and "live" end,
      "Stop the receiving and source vehicles as required in the Fleet card. Open Orders, choose Copy or Share, and select the other route. Shared lists keep each vehicle's own progress; Stop sharing empties only this vehicle's list."},
    {"mail","Town mail & postal routes","freight",function() return S.road_mail and api.terrain end,
      "In Road Construction → Road Freight, use Truck stop near houses. Inspect a road depot for the postal van, add a pickup stop and a delivery stop, and check Mail acceptance before starting.",
    },
  })

  rows("rail",{
    {"railworks","Track, depots & platforms","railworks",rail,
      "Use AutoRail for ordinary track, build a depot at a clear rail end, or select both ends of a straight station. Rail Tools & Operations opens pilots and manual construction tools.",
    },
    {"pbs","Path signals and dispatch","railsignals",rail,
      "Place forward-facing regular or one-way PBS heads. Rotate the fitting to reverse the direction. Two empty trains can contest a diamond and release their reservations only when the rear wagon clears.",
      nil,"Keep PBS heads and conventional block heads in separate pilot layouts."},
    {"block","Conventional signal blocks","railsignals",function() return api.rail_block_tools and rail() end,
      "Place conventional heads before and after the shared unsigned diamond on each flat one-way route. Order two empty depot-to-platform trains to watch one wait at red until the other's tail clears the outgoing head.",
      nil,"Use a separate disposable railway with only conventional heads, not PBS. No paid freight or passenger switching in this pilot."},
    {"railspan","Rail bridge & tunnel","railworks",function() return api.rail_span_tools and rail() end,
      "Use Bridge (0) to select two bridgeheads, or Tunnel (6) to click the entry slope. Connect both portals, then use Run train through rail spans. A coupled train keeps the span reserved until its final wagon clears.",
    },
    {"railgrade","Stock rail grades","railworks",function() return S.rail_grade_enabled and rail() end,
      "Lay compatible straight tracks on supported slopes. Compare climbing versus descending with the stock position and speed models.",
    },
    {"crossing","Road–rail level crossings","railengineering",function()
      if api.crossing_tools and rail() then return true end
      return api.crossings and "saved"
    end,"Build on a flat owned tile with perpendicular road and rail. Run both modes to watch the striped barriers and how road traffic already on the crossing clears before rail enters.",
      nil,"Road and rail vehicles obey the same crossing gate."},
    {"railmoney","Paid rail passenger shuttle","railops",function() return S.rail_paid_service and rail() end,
      "Build two owned platforms in house catchments, then use the paid two-platform shuttle order or order a purchased locomotive. Inspect waiting passengers and fares.",
    },
    {"ownedrail","Owned rail depot roster","railworks",function() return api.rail_owned and rail() end,
      "Inspect an owned rail depot. Buy an available engine with a passenger carriage and select two platforms. The depot uses each locomotive’s stock speed, power, costs and model.",
      nil,"The engines on sale depend on the game's year.",
      detail=fleet_details},
    {"electricrail","Electrified rail and SH '30'","railtypes",native("electric_tools"),
      "Convert your complete flat route, both platforms and depot from Rail Types. An SH '30' only routes along powered rail. Steam and diesel can use both types.",
      nil,"Use a fresh generated game starting in 1970 for the SH '30'. Slopes, spans and junction conversions are not available yet.",
      fresh=true},
    {"railpair","Paired paid passenger trains","railops",function() return api.rail_owned_pair_tools and S.rail_paid_service end,
      "Stage one supported owned passenger consist per depot. Use Order two owned passenger trains, then pick each depot, origin and final platform. They may share a loading platform but park at different destinations.",
    },
    {"railcoal","Rail coal freight","railfreight",native("rail_coal_tools"),
      "Designate separate coal loading and unloading platforms at a real mine and power station. Buy a Kirby with the coal wagon and choose mine first, power station second. The train delivers coal, not Goods.",
      nil,"Find a coal mine and power station on the map.",fresh=true},
    {"railoil","Rail oil tanker & road Goods","railfreight",native("rail_oil_tools"),
      "Designate an Oil Wells loader and refinery unloader. Buy Kirby + 30,000 L Oil Tanker, then order wells before refinery. Use a separate road Goods truck from the refinery to a town that accepts Goods.",
      nil,"Choose Oil and Refinery when creating a world for a guaranteed route."},
    {"railmetals","Rail Iron Ore Hopper & Steel Truck","rail_metal_freight",
      function() return api.rail_iron_ore_tools or api.rail_steel_tools end,
      "Use separate loading and unloading platforms for each cargo. Deliver Iron Ore from the Iron Ore Mine to the Steel Mill, then take Steel from the mill to a Factory. Buy or assemble the appropriate wagon in an owned rail depot.",
    },
    {"railfarm","Farm & Factory trains","rail_farm_freight",
      function() return api.rail_grain_tools or api.rail_livestock_tools end,
      "Connect a Farm and Factory by rail. Use separate platforms for Grain and Livestock, designate their loading and delivery stages, then assemble the matching hopper or van at your rail depot.",
    },
    {"railbank","Bank Valuables by Rail","rail_bank_freight",native("rail_valuables_tools"),
      "Fund Banks in two qualifying towns. Connect an owned rail depot and two banks by rail. Designate a Valuables loading platform and a delivery platform at a different Bank, then buy an Armoured Van and order pickup first.",
      nil,"A Bank requires two adjacent house tiles and a town population of at least 1,200."},
    {"railwood","Forest-to-Sawmill Wood Truck","rail_goods_freight",native("rail_wood_tools"),
      "Designate a Wood loading platform at a Forest and a receiving platform at a Sawmill. Buy or assemble a locomotive and Wood Truck. Schedule the Forest first and the Sawmill second.",
      nil,"The same Timber & Goods section includes a separate Goods route from the sawmill to town."},
    {"railgoods","Rail Goods Van","railfreight",native("rail_goods_tools"),
      "Use a working Timber chain. Designate the sawmill's loading platform and a town platform accepting Goods. Buy a Kirby with its covered 25-crate Goods Van and order the sawmill first.",
    },
  })

  rows("airwater",{
    {"harbor","Harbor, canals & locks","harbor",native("ship_tools"),
      "Build a dock and ship depot. Open Waterworks for a canal, lock or aqueduct. A lock changes the vessel's height while the gates control transit.",
    },
    {"ferry","Ferry & passenger fares","harbor_ops",function() return api.ship_tools end,
      "Inspect a ship depot and buy a passenger ferry. Select two reachable docks with houses nearby, then Dispatch. Inspect the depot for fares, running costs, and stop or resume.",
      nil},
    {"yate","Yate coal ship & refit","harbor_ops",native("ship_coal_tools"),
      "Buy the Yate at an owned depot, refit its hold to coal, then use Order Yate coal ship to pick the mine dock followed by the power dock.",
      nil,"Use the fresh South Coast Coal preset for the working water layout."},
    {"airfield","Country airfield & trimotor","airfields",native("airport_tools"),
      "Place a flat stock 4×3 country airfield and a second one with enough approach clearance. Use the airfield orders or inspect a real hangar in the owned workbench.",
    },
    {"airfares","Passenger trimotor fares","airfields",function() return api.airport_tools and S.air_paid_service end,
      "Place country airfields whose catchments include houses, then order a compatible trimotor between them. Inspect waiting passengers and actual boarding and fares.",
    },
    {"airpaid","Paid aircraft & hangar market","airfields",function()
      return api.airport_tools and S.air_owned_preview and S.air_paid_service
    end,"Inspect an owned hangar to buy an available Sampson U52 or Coleman Count. Order between two airfields with eligible passenger catchments and inspect boarding, fares and costs.",
      nil,"The year determines which aircraft are sold."},
    {"airpair","Shared runway and paid aircraft","airfields",function()
      return api.airport_tools and S.air_fleet_preview and S.air_paid_service
    end,"Buy two supported Sampsons in distinct hangars. Give them distinct orders with a common country airfield and watch the stock runway and terminal blocks sequence them.",
      nil,"Use separate real hangars and the supported fixed-wing country-airfield layout."},
    {"tram","Electric tram pilot","tramway",native("tram_tools"),
      "Build a dedicated tram line, one depot and two through stops. Select Order test streetcar (0), then click the depot and both stops.",
      nil,"Clear test streetcar (7) keeps your infrastructure. This runs a test vehicle, not a paid commercial tram fleet."},
  })

  rows("scenarios",{
    {"coal","Coal mine → power by road","freight",function()
      return api.stock_coal_scenery and api.freight_tools and S.road_coal
    end,"Build freight stops near the provided real coal mine and power station. Buy the original coal tipper and add a mine pickup followed by a power-station delivery.",
      nil,"Industry density affects whether these sites appear on generated maps.",fresh=true},
    {"timber","Forest → sawmill → town Goods","freight",native("timber_tools"),
      "Use a wood truck to bring logs to the sawmill; then carry its Goods to a town freight stop that accepts them. Each stage uses the original production and station rules.",
      nil,"Look for a forest and sawmill on generated maps.",fresh=true},
    {"farm","Farm → factory → town Goods","freight",native("farm_tools"),
      "Build truck stops at farm, factory and town; buy original grain and livestock vehicles for the two farm inputs, then a Goods truck from the factory to town. Inspect changing crop stages and actual factory stock.",
      nil,"Choose Farm and Factory when creating a world.",fresh=true},
    {"oil","Oil Wells → refinery → town Goods","freight",native("oil_tools"),
      "Haul oil from the wells to the refinery in the original Witcombe tanker; then use a Goods truck from the refinery to a town stop that accepts Goods. The Rail Oil row gives the optional rail first leg.",
      nil,"Choose Oil and Refinery when creating a world.",fresh=true},
    {"coastal_coal","South Coast Coal by ship","harbor",function()
      return S.stock_coal_scenario=="south_coast_1751" and api.ship_coal_tools
    end,"On the seeded South Coast route, try docks at 8,32 and 5,32 and the east–west depot at 12,34. Buy and refit the Yate; order mine first and power second.",
      nil,"Choose South Coast Coal when creating a world for a tested shipping channel.",fresh=true},
    {"coastal_flood","Coastal flooding","terrain",native("coastal_flood_tools"),
      "At sea level, connect a cut to the open sea and let the stock landscape clock advance. An isolated cut remains dry.",
      nil,
      "Runs on generated maps; Coastal Landscaping provides a fixed test coast.",
      fresh=true},
    {"generated_world","Stock generated playable world","roads",native("generated_world"),
      "Create a 64×64 or 128×128 temperate map with stock TerraGenesis relief, towns, freight and scenery. The river and industry settings affect where later sites are placed.",
      nil,
      "Industry placement can leave some sites unbuilt.",fresh=true},
  })

  rows("world",{
    {"survey","Company map & jump survey","navigation",function() return api.road_first and "live" end,
      "Use Jump Map to fly to a selected tile. Inspect land, track, stop catchments, and industries from the world. "},
    {"landscape","Corner terrain landscaping","terrain",function() return api.terrain and "live" end,
      "Raise or lower a single corner, use the area tools on a selection, or level terrain. Compare the shared corners, slopes and required foundations before building.",
      nil,"Hold Aux1 (usually E) on the second click for a diagonal selection."},
    {"bridges","Road bridges & road tunnels","roads",native("structure_tools"),
      "Choose Bridge (0) and mark both bridgeheads, or use Tunnel (6) on a compatible entry slope with a clear exit. Join both ends to roads to run a bus through the structure.",
    },
    {"growth","Original town house growth","roads",function()
      return api.town_growth and "live"
    end,"Serve a real town along existing roads and inspect a newly started house. New occupants contribute passengers and mail after construction completes.",
      nil,"Growth follows the town's road network."},
    {"offline","Offline company economy",nil,function()
      return api.offline_economy and "live"
    end,"For a server with a paid route, leave with no players connected, then rejoin and inspect changed time, cargo and finance. Pausing still stops time; empty demonstration pilots aren't simulated offscreen.",
    },
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
    label(.42,.38,"LuanTTD  /  Transport & World Guide")
    label(.42,1.00,"Find the tools and learn how to start a service.")
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
    if v.note then details[#details+1]=v.note end
    add("textarea[7.24,3.38;7.30,4.95;;;"..esc(table.concat(details,"\n\n")).."]")
    if openable(r,state) then
      button(7.24,8.12,7.30,"wb_open","Open "..(api.world.menu_title and api.world.menu_title(r.menu) or "workbench"))
    end
    label(.42,8.77,"Routes may require specific industries, terrain or vehicles.")
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
