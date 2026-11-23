local mod=core.get_modpath(core.get_current_modname())
local storage=core.get_mod_storage()
local Sim=dofile(mod.."/sim.lua")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local Codec=dofile(mod.."/packed_campaign.lua")
local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
local Checkpoint=Checkpoints(core,Codec)
local Prepared=Checkpoints(core,Codec,"luanttd-prepared-campaign.chk")
local settings=core.settings
-- Native tests can inject explicit fixtures into disposable game copies.
local qa={}
local qa_path=mod.."/qa_layout.lua"
local qa_file=io.open(qa_path,"r")
if qa_file then qa_file:close();qa=dofile(qa_path)(settings,mod) end
local fixture=qa.enabled
local WorldSetup=dofile(mod.."/world_setup.lua")
local world_options=WorldSetup.read(core,storage)
local scenario=qa.scenario or (world_options and world_options.scenario) or "generated"
-- Normal generated worlds always use a separate owner. Fixed historical
-- replay fixtures can still exercise the legacy code in their private
-- game copy, not by a setting exposed to players.
local worker_boot=qa.authoritative_boot==true or not fixture and not qa.local_replay and scenario=="generated"
local owner_filename="luanttd-campaign-owner.chk"
local OwnerCheckpoint=worker_boot and Checkpoints(core,Codec,owner_filename) or nil
local resumed_owner=OwnerCheckpoint and OwnerCheckpoint.read()
local checkpoint=not resumed_owner and Checkpoint.read()
local saved=resumed_owner or checkpoint or storage:get_string("campaign")
local fresh=saved==""
if fresh and not fixture and not world_options and core.is_singleplayer() then
  local prepare=dofile(mod.."/campaign_generation_async.lua")(core,mod)
  WorldSetup.mount(core,storage,prepare)
  return
end
if scenario=="original" or qa.explorer then
  dofile(mod.."/original_terrain_explorer.lua").start(core,mod,storage,
    scenario=="original" and world_options or nil)
  return
end
local request_farm=scenario=="farm"
local request_oil=scenario=="oil"
local request_coast=scenario=="coastal"
local request_south=scenario=="south_coast"
local generated_world=fresh and not (fixture or request_farm or request_oil or request_coast or request_south)
local S
if saved~="" then
  S=type(saved)=="table" and saved or core.deserialize(saved,true)
  if type(S)=="table" then Prepared.clear() end
elseif generated_world then
  S=world_options and Prepared.read()
  if S then
    core.log("action","LuanTTD opened the prepared campaign without regenerating.")
  else S=dofile(mod.."/campaign_generation.lua")(core,mod,Sim,WorldSetup).run(world_options) end
else
  S=Sim.new(fixture and tonumber(settings:get("bayline_seed")) or 1751)
end
if type(S)~="table" or S.version~=1 then error("Unsupported LuanTTD save; use a fresh world.") end
local profile=S.stock_generated_profile
local world_area=profile and profile.width*profile.depth or 0
assert(not checkpoint or world_area>=128^2,
  "The campaign checkpoint does not describe a wide campaign.")
local wide_checkpoint=world_area>=128^2
local compact_checkpoint=world_area>128^2
if S.stock_generated_profile then
  local p=S.stock_generated_profile
  local generated=dofile(mod.."/generated_campaign.lua")
  assert(p.version==1 and generated.supports_size(p.width,p.depth) and S.corner_grid.width==p.width and
    S.corner_grid.depth==p.depth and #S.tiles==p.width*p.depth and
    #S.corner_grid.levels==(p.width+1)*(p.depth+1),"Unsupported generated campaign dimensions")
  local clock=S.passenger_house_clock
  local width_log,depth_log=WorldSetup.axis_log(p.width),WorldSetup.axis_log(p.depth)
  assert(not clock or (clock.log_x==width_log and clock.log_y==depth_log and
    type(clock.head)=="number" and clock.head%1==0 and clock.head>=1 and clock.head<p.width*p.depth),
    "Saved landscape clock does not cover the generated region")
  Sim.W,Sim.H=p.width,p.depth
  generated_world=true
end
Sim.restore_road_orders(S)
local simulation_bindings=dofile(mod.."/campaign_simulation_bindings.lua")(Sim,mod)
local api={Sim=Sim,s=S,generated_world=generated_world,road_first=true,
  capabilities={air={},ferry={},rail={engines={},ready={},split={}}},
  interest=dofile(mod.."/presentation_interest.lua").new()}
local farm_profile=not generated_world and (S.stock_farm_industries~=nil or fresh and request_farm)
local oil_profile=not generated_world and (S.stock_oil_industries~=nil or fresh and not farm_profile and request_oil)
local coast_profile=not generated_world and (S.stock_coastal_profile and not S.qa_coastal or
  fresh and not (farm_profile or oil_profile) and request_coast)
local yate_profile=not generated_world and (S.stock_coal_scenario=="south_coast_1751" or
  fresh and not (farm_profile or oil_profile or coast_profile) and request_south)
local special_profile=generated_world or farm_profile or oil_profile or coast_profile or yate_profile
function api.world_origin()
  if S.stock_generated_profile then
    return ("TerraGenesis (OpenTTD 14.1), %d×%d, seed %d"):format(Sim.W,Sim.H,S.seed)
  end
  if farm_profile or oil_profile or coast_profile or yate_profile then
    local name=farm_profile and "Farm" or oil_profile and "Oil" or coast_profile and "Coastal" or "South Coast"
    return "Explicit "..name.." scenario"
  end
  return fixture and "Test scenario" or "LuanTTD"
end

do
  S.road_stock_clock,S.road_stock_house_supply,S.road_stock_loading=true,true,true
  S.road_junction_clearance=true
  S.road_coal=not (generated_world or farm_profile or oil_profile or coast_profile)
  S.road_timber=not special_profile
  S.rail_goods_service=S.road_timber
  S.road_farm=farm_profile
  S.road_oil=oil_profile
  S.rail_oil_service=S.road_oil
  S.rail_coal_service=S.road_coal
  S.ship_coal_service=S.road_coal
  S.road_bay_build,S.road_regal_enabled,S.road_mail=true,true,true
  local files={}
  for _,part in ipairs({"models","textures"}) do
    for _,name in ipairs(core.get_dir_list(mod.."/"..part,false)) do files[name]=true end
  end
  api.bus_breakdowns=tonumber(settings:get("bayline_stock_bus_breakdowns")) or 2
  api.bus_service_interval=tonumber(settings:get("bayline_stock_bus_service_interval")) or 150
  local capabilities={
    start_year=world_options and world_options.year or tonumber(settings:get("bayline_stock_bus_start_year")) or 1950,
    foster=files["bl_foster_bus.obj"] and files["bl_foster_bus_atlas.png"],
    extra=dofile(mod.."/road_stock_media.lua").scan(files),
    craighead=files["bl_craighead_goods_truck.obj"] and files["bl_craighead_goods_truck_atlas.png"],
    breakdowns=api.bus_breakdowns,service_interval=api.bus_service_interval,
    service_percent=settings:get_bool("bayline_stock_bus_service_percent",false),
  }
  api.capabilities.road=capabilities
  simulation_bindings.road(S,capabilities)
  if saved=="" then
    if not generated_world then dofile(mod.."/town_layout.lua")(Sim,S) end
    S.road_economy=true
  end
end
-- A campaign keeps its shared-corner grid across restarts.
do
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local grid=S.corner_grid or dofile(mod.."/terrain_preview.lua")(Sim,Terrain,S)
  if api.road_first and saved=="" and not generated_world then
    if qa.terrain and not special_profile then
      grid=qa.terrain(Sim,Terrain,S,grid)
    elseif coast_profile then
      grid,S.stock_coastal_profile=dofile(mod.."/terrain_coastal_seed.lua")(Sim,Terrain,S,grid)
    end
  end
  S.corner_grid=grid
  if simulation_bindings.flood(S) then api.coastal_flood_tools=true end
  local Landscape=dofile(mod.."/openttd/landscaping.lua")(Terrain)
  function api.landscape_tiles(x,z,u,v,diagonal)
    local ids={}
    for a,b in Landscape.points(grid,u,v,x,z,diagonal) do
      local id=Sim.id(a,b)
      if id then ids[#ids+1]=id end
    end
    return ids
  end
  api.slope=dofile(mod.."/openttd/slope.lua")
  api.terrain=dofile(mod.."/terrain_view.lua")(Sim,Terrain,grid)
end
api.town_growth=simulation_bindings.towns(S)
if generated_world or S.road_farm then
  assert(api.terrain,"The farm world requires corner terrain.")
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local assets=dofile(mod.."/farm_visual_assets.lua")
  local missing=assets.missing(core,mod)
  assert(not missing,"The farm workbench is missing the asset "..tostring(missing))
  local mounted,rng=Sim.mount_farm_world(S,Terrain,true)
  api.farm_world=assert(mounted,rng)
  local heavy=Sim.mount_heavy_world(S,Terrain)
  if dofile(mod.."/iron_steel_visual_assets.lua").ready(core,mod,heavy) then api.heavy_world=heavy;api.capabilities.heavy_industry=true end
  do
    local files={}
    for _,part in ipairs({"models","textures"}) do
      for _,asset in ipairs(core.get_dir_list(mod.."/"..part,false)) do files[asset]=true end
    end
    api.capabilities.temperate_bank=not not (generated_world and files["bl_industry_temperate_bank_0_0.obj"] and
      files["bl_industry_temperate_bank_1_0.obj"] and files["bl_industry_temperate_bank_atlas.png"])
  end
  api.farm_visual_assets=assets
  if saved=="" and not generated_world then
    local seeded,why=api.farm_world.default_1751(S,rng)
    assert(seeded,"No clean farm/factory corridor: "..tostring(why))
  end
  api.farm_view=dofile(mod.."/farm_field_view.lua")(api,Terrain)
end
if generated_world or S.road_oil then
  assert(api.terrain,"Stock oil freight requires corner terrain.")
  local files={}
  for _,folder in ipairs({"models","textures"}) do
    for _,name in ipairs(core.get_dir_list(mod.."/"..folder,false)) do files[name]=true end
  end
  api.capabilities.oil_tanker=files["bl_witcombe_oil_tanker.obj"] and files["bl_witcombe_oil_tanker_atlas.png"]
  local oil,why=Sim.mount_oil_world(S,dofile(mod.."/openttd/terrain.lua"),api.capabilities.oil_tanker)
  assert(oil,why)
  for style,parts in pairs(oil.visual_sources()) do
    assert(files["bl_"..style.."_atlas.png"],"Missing oil industry atlas "..style)
    for _,piece in ipairs(parts) do
      local file=("bl_%s_%d_%d.obj"):format(style,piece[1],piece[2])
      assert(files[file],"Missing stock oil site mesh: "..file)
    end
  end
  api.oil_world=oil
  if saved=="" and not generated_world then
    local good,error_=oil.default_1751(S)
    assert(good,"No untouched oil corridor in this world: "..tostring(error_))
  end
end
if generated_world then
  -- Industry geography controls available cargo, not a scenario toggle.
  local function present(registry,kind)
    for _,row in pairs(registry or {}) do if row.kind==kind and not row.removed then return true end end
    return false
  end
  -- Stock road engines go on sale by date even on an island or a
  -- funding-only map that has no current producer for their cargo.
  S.road_heavy=api.heavy_world~=nil
  if S.road_heavy then S.stock_heavy_industries=S.stock_heavy_industries or {} end
  if api.capabilities.temperate_bank then S.road_bank=true;S.stock_bank_industries=S.stock_bank_industries or {} end
  S.road_farm=not not (present(S.stock_farm_industries,"farm") or present(S.stock_farm_industries,"factory"))
  S.road_oil=not not (present(S.stock_oil_industries,"oil_well") or present(S.stock_oil_industries,"oil_refinery") or present(S.stock_oil_industries,"oil_rig"))
  S.rail_oil_service=S.road_oil
  local mine,power
  for _,industry in pairs(S.stock_coal_industries or {}) do
    mine=mine or industry.kind=="coal_mine" and not industry.removed
    power=power or industry.kind=="power_station" and not industry.removed
  end
  if mine and power then
    S.road_coal,S.rail_coal_service,S.ship_coal_service=true,true,true
  end
  local forest,mill
  for _,industry in pairs(S.stock_timber_industries or {}) do
    forest=forest or industry.kind=="forest" and not industry.removed
    mill=mill or industry.kind=="sawmill" and not industry.removed
  end
  if forest and mill then
    S.road_timber,S.rail_goods_service=true,true
  end
end
api.road_bay_tools=Sim.road_stock_service_active(S)
api.structure_tools,api.tram_tools,api.ship_tools,api.airport_tools=true,true,true,true
S.tram_enabled,S.ship_enabled,S.airport_enabled=true,true,true
S.air_fleet_preview,S.air_owned_preview=true,true
api.airframe_art,api.capabilities.city_airport=dofile(mod.."/airport_manifest.lua")(core,mod)
api.rail_owned_tools=true
do
  local files={}
  for _,folder in ipairs({"models","textures"}) do
    for _,name in ipairs(core.get_dir_list(mod.."/"..folder,false)) do files[name]=true end
  end
  local art=dofile(mod.."/rail_catenary_art.lua")
  local ready=files[art.atlas] and files["bl_rail_sh_30.obj"] and files["bl_rail_sh_30.png"]
  for _,mask in ipairs({1,2,4,8,16,32}) do
    ready=ready and files["bl_rail_catenary_"..mask.."_0.obj"] and files["bl_rail_catenary_"..mask.."_1.obj"]
  end
  if ready then
    S.stock_electrification=true
    api.electric_art,api.electric_tools=art,true
    -- Render support is independent of command and moving traction
    -- readiness. The production span conversion remains unmounted.
    local bridge=dofile(mod.."/rail_bridge_catenary_art.lua")
    local deck_ready=true
    for _,part in ipairs({"head_flat","head_ramp"}) do
      for endpoint=0,3 do deck_ready=deck_ready and files[bridge.overlay(part,endpoint).mesh] end
    end
    for axis=0,1 do
      for i=1,2 do deck_ready=deck_ready and files[bridge.overlay("span",axis,i,3).mesh] end
    end
    if deck_ready then api.rail_bridge_wire_art=bridge end
  else
    error("This electric railway needs the original SH '30' and wire meshes and textures.")
  end
end
api.rail_owned_pair_tools,S.rail_owned_pair_enabled=true,true
S.rail_block_preview,api.rail_block_tools,api.rail_build_tools=true,true,true
function api.save()
  if api.authority_handoff then return false end -- the handoff owns durable state
  if compact_checkpoint then
    Checkpoint.write_state(S)
    return
  end
  local payload=core.serialize(S)
  -- Commit before the callback reports a successful company action.
  -- SQLite remains a compatibility mirror, never the authority when the
  -- checkpoint exists. Regular smaller worlds keep their existing path.
  if wide_checkpoint then Checkpoint.write(payload) end
  storage:set_string("campaign",payload)
end
if api.terrain and not generated_world and (S.road_coal or S.rail_coal_service or S.ship_coal_service) then
  if saved=="" then
    local source=mod.."/openttd/"
    local P=dofile(source.."passengers.lua")
    local Rating=dofile(source.."station_rating.lua")
    local Catchment=dofile(source.."station_catchment.lua")(P,Rating,function()return 0 end,function()return 0 end)
    local Coal=dofile(source.."coal_industry.lua")(P,Rating,Catchment,dofile(source.."income.lua"))
    local World=dofile(mod.."/coal_industry_world.lua")(Sim,dofile(source.."terrain.lua"),Coal)
    local coast=S.ship_coal_service and yate_profile
    local result,reason
    if coast and S.seed~=1751 then reason="The South Coast Coal scenario requires seed 1751"
    elseif coast then
      result,reason=World.seed(S,Sim.id(12,27),Sim.id(5,28))
      if result then S.stock_coal_scenario="south_coast_1751" end
    else result,reason=World.seed(S,Sim.id(30,11),Sim.id(40,12)) end
    if not result then core.log("warning","LuanTTD: no clear coal corridor in this seed: "..tostring(reason)) end
  end
end
api.stock_coal_scenery=not not (api.terrain and S.stock_coal_industries)
if api.terrain and (S.road_timber or S.stock_timber_industries) then
  api.timber_rules=Sim.timber_rules()
  api.timber_world=dofile(mod.."/timber_world.lua")(Sim,dofile(mod.."/openttd/terrain.lua"),api.timber_rules)
  if saved=="" and S.road_timber and not generated_world then
    local seeded,why=api.timber_world.default_1751(S)
    if not seeded then core.log("warning","LuanTTD timber scenario unavailable: "..tostring(why)) end
  end
end
api.stock_timber_scenery=not not (api.timber_world and S.stock_timber_industries)
api.timber_tools=api.stock_timber_scenery and Sim.road_timber_active(S)
api.farm_tools=api.farm_world and Sim.road_farm_active(S)
api.oil_tools=api.oil_world and Sim.road_oil_active(S)
api.freight_tools=(api.stock_coal_scenery and S.road_coal) or api.timber_tools or api.farm_tools or api.oil_tools or (api.heavy_world and Sim.road_heavy_active(S))
local networks=simulation_bindings.networks(S,api.slope,api.terrain.tile,
  function() return not api.trackworks_demo or api.trackworks_demo.is_clear() end)
local Track,Follow,RailCost,RailSearch=networks.track,networks.follow,networks.cost,networks.search
api.trackworks,api.rail_spans,api.crossings,api.oneway=networks.lab,networks.spans,networks.crossings,networks.oneway
api.rail_span_tools,api.crossing_tools,api.oneway_tools=true,true,true
api.vehicle_ui=dofile(mod.."/vehicle_ui.lua")(api)
api.vehicle_orders=api.vehicle_ui.orders
local render=dofile(mod.."/render.lua")(api)
api.render=render
if api.structure_tools or api.rail_spans then
  api.bridge_picker=dofile(mod.."/bridge_picker.lua")(api)
  core.register_on_player_receive_fields(api.bridge_picker.fields)
  core.register_on_leaveplayer(function(p) api.bridge_picker.leave(p:get_player_name()) end)
end
api.crowd=dofile(mod.."/passenger_crowd.lua")(api)
if api.road_first then api.selector=dofile(mod..'/tile_selector.lua')(api) end
local ui=dofile(mod.."/ui.lua")(api)
api.vehicle_status=ui.status
local world=dofile(mod.."/world.lua")(api,ui)
api.world=world
local interval=qa.interval or 1.25
interval=math.max(0.05,math.min(15,interval))
api.capabilities.seconds_per_day=interval
local auxiliary={}
local function pilot_clock(active,tick)
  auxiliary[#auxiliary+1]=dofile(mod.."/aux_transport_clock.lua")(S,interval,active,tick)
end
if api.tram_tools then
  local Network,Run,clock=simulation_bindings.tram(S,api.slope,interval)
  api.tram_clock=clock
  local Pose=dofile(mod.."/road_motion_presentation.lua")(dofile(mod.."/road_lanes.lua"))
  api.tram_view=dofile(mod.."/tram_preview_view.lua")(api,Run,Pose,dofile(mod.."/road_motion.lua"))
  dofile(mod.."/tram_preview_commands.lua")(api,Network,Run)
end
local water_order_run, coal_order_run, coal_order_runtime, air_order_run
if api.ship_tools then
  local source=mod.."/openttd/"
  local art={}
  local missing={}
  for _,key in ipairs(core.get_dir_list(mod.."/models",false)) do missing[key]=true end
  for _,key in ipairs(core.get_dir_list(mod.."/textures",false)) do missing[key]=true end
  art[206]=missing["bl_harbor_ferry_palette.png"] and missing["bl_harbor_ferry.obj"]
  art[207]=missing["bl_harbor_ferry_palette.png"] and missing["bl_ffp_passenger_ferry.obj"]
  for id,stem in pairs({[204]="stock_mps_oil_tanker",[205]="stock_cs_inc_oil_tanker"}) do
    local mesh,atlas="bl_"..stem..".obj","bl_"..stem.."_atlas.png"
    if missing[mesh] and missing[atlas] then
      art[id]=true
      core.register_entity("luanttd_core:"..stem,{initial_properties={
        physical=false,pointable=false,static_save=false,visual="mesh",mesh=mesh,textures={atlas},
        collide_with_objects=false,shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}}})
    end
  end
  art[208]=missing["bl_stock_bakewell_300_hovercraft.obj"] and missing["bl_stock_bakewell_300_hovercraft_atlas.png"]
  art[211]=missing["bl_yate_cargo_ship.obj"] and missing["bl_yate_cargo_ship_atlas.png"]
  art[212]=missing["bl_stock_bakewell_cargo_ship.obj"] and missing["bl_stock_bakewell_cargo_ship_atlas.png"]
  api.capabilities.ferry=art
  local Terrain,Water,Network,Roster,Run,Depot,cargo_run,C=simulation_bindings.water(S,Track,
    function(id) return art[id] end)
  water_order_run=Run
  api.passenger_ferry={
    catalog=Roster.order,quote=function(n,depot,id) return Depot.quote(S,n,depot,id) end,
    model=Roster.model,
    buy=function(n,depot,id) local v,msg=Depot.buy(S,n,depot,id);if v then api.save() end;return v,msg end,
    staged=function(n,depot) return Depot.staged(S,n,depot) end,
    start=function(n,depot,a,b,via) return Depot.start(S,n,depot,a,b,via) end,
    stop=function(n,stop) local ok,msg=Depot.stop(S,n,stop);if ok then api.save() end;return ok,msg end,
  }
  if C then
    coal_order_run,coal_order_runtime=cargo_run,C
    local function asset(dir,filename)
      for _,name in ipairs(core.get_dir_list(mod.."/"..dir,false)) do
        if name==filename then return true end
      end
      return false
    end
    local art_ready=asset("models","bl_yate_cargo_ship.obj") and asset("textures","bl_yate_cargo_ship_atlas.png")
    local coal_messages={
      STOCK_COAL_SHIP_DISABLED="The stock coal ship workbench needs a coal industry and stock clock.",
      OWN_SHIP_DEPOT_REQUIRED="Choose a ship depot you own.",
      OWN_SHIP_IN_DEPOT_REQUIRED="Refit your Yate while it is in its depot, before dispatch.",
      ONE_STOCK_COAL_SHIP_ONLY="This workbench supports one Yate.",
      SHIP_ALREADY_COAL_REFITTED="The Yate is already refitted to coal.",
      OWN_YATE_REFITTED_TO_COAL_REQUIRED="Buy a Yate and refit it to coal first.",
      DOCK_NEEDS_COAL_MINE="Choose a dock in a coal mine's catchment.",
      DOCK_NEEDS_POWER_STATION="Choose a dock that accepts coal at a power station.",
      OWN_DEPOT_AND_TWO_DOCKS_REQUIRED="Choose two distinct docks you own.",
      NO_CHANNEL_TO_FIRST_DOCK="No navigable water route from the depot to the mine dock.",
      NO_RETURN_CHANNEL="The ship cannot navigate both directions between these docks.",
      DOCK_BERTHS_OVERLAP_OR_MISSING="Both docks need distinct reachable water berths.",
      FERRY_FREIGHT_SHARED_BERTH="The ferry and coal ship need separate water berths.",
      FERRY_FREIGHT_SHARED_DEPOT="The ferry and coal ship need separate depots.",
      NOT_ENOUGH_MONEY="Your company cannot afford this action.",
    }
    local function coal_note(reason) return coal_messages[reason] or reason end
    api.ship_coal_tools=art_ready and Sim.ship_coal_active(S)
    api.ship_coal={
      buy=function(owner,depot)
        if not art_ready then return nil,"The native Yate model is missing." end
        local v,why=C.buy(S,owner,depot);if v then api.save() end
        return v,v and ("Yate purchased for $"..v.cost..". It carries Goods until refitted.") or coal_note(why)
      end,
      refit=function(owner)
        local v,why=C.refit(S,owner);if v then api.save() end
        return v,v and ("Yate refitted to coal for $"..v.cost..".") or coal_note(why)
      end,
      start=function(owner,mine,power)
        if not art_ready then return nil,"The native Yate model is missing." end
        local v,why=C.start(S,owner,mine,power);if v then api.save() end
        return v,v and "Yate dispatched: full load at the mine, unload at the power station." or coal_note(why)
      end,
      set_stopped=function(owner,stopped)
        local v,why=C.set_stopped(S,owner,stopped);if v then api.save() end
        return v,v and (stopped and "Yate stopped." or "Yate resumed.") or coal_note(why)
      end,
      status=function() return C.status(S) end,dock=function(id) return C.report(S,id) end,
      pose=function(t) return C.pose(S,t) end,take_events=function() return C.take(S) end,
      busy=function() return C.busy(S) end,
    }
    if art_ready then api.ship_coal_view=dofile(mod.."/ship_coal_view.lua")(api,dofile(mod.."/road_motion.lua")) end
    if api.ship_coal_tools then world.enable_ship_coal() end
  end
  local Bridge=dofile(source.."road_bridge.lua")(api.slope)
  local Aqua=dofile(source.."aqueduct.lua")(Bridge)
  api.aqueduct=dofile(mod.."/ship_aqueduct_world.lua")(Sim,Terrain,Aqua)
  local Construction=dofile(source.."water_construction.lua")(Track,Water)
  api.waterworks=dofile(mod.."/ship_water_world.lua")(Sim,Network,Construction)
  api.ship_lock_view=dofile(mod.."/ship_lock_view.lua")(api,dofile(mod.."/ship_lock_presentation.lua"))
  api.ship_view=dofile(mod.."/ship_preview_view.lua")(api,Run,dofile(mod.."/road_motion.lua"))
  pilot_clock(function()
    local p=Run.current(S)
    return p and not p.paid_clock and (p.engine_id==nil or art[p.engine_id]) and
      (not Run.paid_art_ready or Run.paid_art_ready(S,p))
  end,function(n) Run.tick(S,n) end)
  dofile(mod.."/ship_preview_commands.lua")(api,Network,Run)
end
if api.airport_tools then
  local art=api.airframe_art
  for id in pairs(art) do api.capabilities.air[id]=true end
  local Network,Run,Owned,Roster=simulation_bindings.air(S,api.slope,function(id) return art[id]~=nil end,
    api.capabilities.city_airport)
  air_order_run=Run
  api.airport_view=dofile(mod.."/airport_preview_view.lua")(api,Run,dofile(mod.."/road_motion.lua"),art)
  pilot_clock(function()
    local p=Run.current(S)
    return p and not p.paid_clock
  end,function(n) Run.tick(S,n,api.airport_view.observe) end)
  dofile(mod.."/airport_preview_commands.lua")(api,Network,Run,Owned,Roster)
end
local ground_orders=dofile(mod.."/road_vehicle_orders.lua")(api)
api.vehicle_orders.road,api.vehicle_orders.tram=ground_orders.road,ground_orders.tram
local water_air_orders=dofile(mod.."/water_air_orders.lua")(S,Sim,
  dofile(mod.."/openttd/rail_order_list.lua"),water_order_run,coal_order_run,coal_order_runtime,air_order_run)
api.vehicle_orders.ship,api.vehicle_orders.air=water_air_orders.ship,water_air_orders.air
if api.stock_coal_scenery then api.coal_view=dofile(mod.."/coal_industry_view.lua")(api) end
local placement_key="world_setup_terrain_placed_v1"
local placement=world_options
  and storage:get_string(placement_key)~="placed" and "pending" or nil
local authority
local save_elapsed,hud_elapsed=0,0
local headless=true
api.offline_economy=headless
local landscape=dofile(mod.."/campaign_landscape_async.lua").new(core,mod)
local campaign=dofile(mod.."/campaign_step.lua").new(S,interval,{
  persist_fraction=true,
  prepare=landscape.prepare,take=landscape.take,
  advance=Sim.daily,capture=render.capture,refresh=render.update_near,
  discard_effects=function()
    Sim.road_loading_events(S)
    Sim.rail_loading_events(S);Sim.rail_paid_motion_events(S);Sim.rail_coal_loading_events(S)
    Sim.ferry_loading_events(S);Sim.air_loading_events(S);Sim.air_paid_motion_events(S)
    if api.ship_coal then api.ship_coal.take_events() end
    S.offscreen_presentation_dirty=true
  end,
})
core.register_globalstep(function(dt)
  if placement then return end
  world.step(dt)
  if api.authority_handoff then
    -- Leave flight, targeting and engine presentation on the host,
    -- but prevent its former stepper, pilots and autosave from running.
    if api.authority_frame then api.authority_frame(dt) end
    api.vehicle_ui.step(dt)
    return
  end
  if api.trackworks_demo then api.trackworks_demo.step(dt) end
  local players=core.get_connected_players()
  local online=#players>0
  api.interest.refresh(players)
  if api.farm_view then api.farm_view.step(dt) end
  render.step_ambient_particles(dt)
  render.step_lighthouse_beams(dt)
  if online then render.refresh_interest() else render.remove_vehicle_views() end
  if api.rail_platform_view then api.rail_platform_view.step(dt,online) end

  for _,tick in ipairs(auxiliary) do tick(dt) end
  if api.tram_clock then api.tram_clock(dt) end
  if api.tram_view then api.tram_view.step(dt,online) end
  if not online then
    campaign.step(dt,false,headless)
    if api.airport_view then api.airport_view.step(dt,false,1) end
    if api.ship_view then api.ship_view.step(dt,false,1) end
    if api.ship_coal_view then api.ship_coal_view.step(dt,false,1) end
    if api.ship_lock_view then api.ship_lock_view.step(false,1) end
    if api.coal_view then api.coal_view.step(dt,false) end
    if api.rail_dispatch_view then api.rail_dispatch_view.step(dt,false,1) end
    if headless then
      save_elapsed=save_elapsed+dt
      if save_elapsed>=8 then api.save();save_elapsed=0 end
    end
    return
  end
  if S.offscreen_presentation_dirty then
    render.prime_service_activity()
    S.offscreen_presentation_dirty=nil
  end
  save_elapsed=save_elapsed+dt
  hud_elapsed=hud_elapsed+dt
  local fraction,n=campaign.step(dt,true,headless)
  if api.rail_dispatch_view then api.rail_dispatch_view.step(dt,online,fraction) end
  if api.crossings then render.crossing_gates() end
  if api.ship_view then api.ship_view.step(dt,online,fraction) end
  if api.ship_coal_view then api.ship_coal_view.step(dt,online,fraction) end
  if api.airport_view then api.airport_view.step(dt,online,fraction) end
  if api.ship_lock_view then api.ship_lock_view.step(online,fraction) end
  if api.coal_view then api.coal_view.step(dt,online) end
  render.frame(dt,fraction)
  api.vehicle_ui.step(dt)
  -- Purchases and construction still change balance while time is paused.
  -- The HUD caches its unchanged text, so a lightweight poll needn't
  -- send recurring packets while the company stands still.
  if n>0 or hud_elapsed>=.23 then ui.hud();hud_elapsed=0 end
  if save_elapsed>=8 then api.save();save_elapsed=0 end
end)
core.register_on_shutdown(function() landscape.close();api.save() end)
local solar=dofile(mod.."/campaign_solar_clock.lua")
local local_solar=solar.new(Sim,S,interval)
local atmosphere=dofile(mod.."/atmosphere.lua").start(core,function()
  if placement then return end
  local now=core.get_us_time()
  if authority then
    local sample=authority.solar_clock()
    if sample then return solar.phase(sample,now) end
  else return solar.phase(local_solar(now),now) end
end)
local function open_campaign_player(p)
  local name=p:get_player_name()
  if not authority then Sim.company(S,name) end
  core.close_formspec(name,"luanttd_core:opening_worker")
  world.spawn(p)
  atmosphere(p)
  api.save()
  core.after(0.6,function()
    local who=core.get_player_by_name(name)
    if who then ui.hud();world.hud(who) end
  end)
end
-- Register the async worker while the engine is loading this mod. The
-- actual job starts only after the opening terrain is ready.
if worker_boot then
  authority=dofile(mod.."/campaign_worker_session.lua")(core,mod,api,ui,render,OwnerCheckpoint,owner_filename,
    not resumed_owner,{open=open_campaign_player,connection=function(p,note) ui.status(p,note) end,wait=function(p,note)
      local message=core.formspec_escape(note)
      core.show_formspec(p:get_player_name(),"luanttd_core:opening_worker",
        "formspec_version[7]size[10,2.2]textarea[.5,.6;9,1.3;;;"..message.."]")
    end})
  api.authority_frame=authority.step
end
local authority_started
local function start_authority()
  if not authority or authority_started then return end
  authority_started=true
  local cap={autoplay=true,seconds_per_day=interval,durable_actions=true}
  for k,value in pairs(api.capabilities) do if cap[k]==nil then cap[k]=value end end
  authority.start(cap,Sim.W,Sim.H)
end
local placement_form="luanttd_core:placing_terrain"
local placement_percent,placement_stage=90,"Loading the starting area"
local retries=0
local function show_placement(p)
  local n=p:get_player_name()
  p:set_physics_override({speed=0,jump=0,gravity=0})
  p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false})
  local detail=placement=="failed" and "Placement needs another attempt. Your world is saved."
  local form=WorldSetup.progress_form(core,"Opening your generated world",placement_percent,placement_stage,detail)
  if placement=="failed" then form=form.."button[5.96,2.53;3.2,.50;retry;Try placement again]" end
  core.show_formspec(n,placement_form,form)
end
local function broadcast_placement()
  for _,p in ipairs(core.get_connected_players()) do show_placement(p) end
end
local attempt_placement
attempt_placement=function()
  placement="placing"
  render.place_world(function(ok,why)
    if not ok then
      core.log("warning","LuanTTD starting-area placement: "..tostring(why))
      retries=retries+1
      placement=retries<=3 and "retrying" or "failed"
      placement_stage=retries<=3 and "Retrying the starting area…" or "Starting area could not be placed"
      broadcast_placement()
      if retries<=3 then core.after(1.5,attempt_placement) end
      return
    end
    placement_percent=100;placement_stage="World ready"
    broadcast_placement()
    api.save()
    storage:set_string(placement_key,"placed")
    placement=nil
    start_authority()
    for _,p in ipairs(core.get_connected_players()) do
      core.close_formspec(p:get_player_name(),placement_form)
      if authority then authority.join(p) else open_campaign_player(p) end
    end
  end,function(f,stage)
    if placement~="placing" then return end
    local percent=math.min(99,90+math.floor(9*f))
    if percent>placement_percent or placement_stage~=stage then
      placement_percent=math.max(placement_percent,percent);placement_stage=stage
      broadcast_placement()
    end
  end)
end
core.register_on_joinplayer(function(p)
  if placement then show_placement(p)
  elseif worker_boot then
    start_authority()
    authority.join(p)
  else open_campaign_player(p) end
end)
core.register_on_player_receive_fields(function(p,key,f)
  if key~=placement_form then return false end
  if f.retry and placement=="failed" then
    retries=0
    attempt_placement()
  elseif f.quit and placement then
    local name=p:get_player_name()
    core.after(.12,function()
      local player=core.get_player_by_name(name)
      if placement and player then show_placement(player) end
    end)
  end
  return true
end)
if placement then core.after(0,attempt_placement) elseif worker_boot then core.after(0,start_authority) end
core.register_on_leaveplayer(function(p) render.leave_ambient_particles(p:get_player_name());api.vehicle_ui.leave(p);ui.leave(p:get_player_name());world.leave(p:get_player_name());if authority then authority.leave(p:get_player_name()) end;if api.trackworks_demo then api.trackworks_demo.leave(p:get_player_name()) end;api.save() end)
core.register_on_player_receive_fields(ui.fields)
core.register_chatcommand("dispatch",{description="Open LuanTTD dispatcher",func=function(name)
  local p=core.get_player_by_name(name)
  if p then ui.open_company(p);return true end
end})
core.register_chatcommand("tools",{description="Return to the LuanTTD section hotbar",func=function(name)
  local p=core.get_player_by_name(name)
  if p then
    if api.road_first then world.home_menu(p) else ui.context(p,world.target(p)) end
    return true
  end
end})
core.register_chatcommand("world_origin",{description="Show how the current LuanTTD world was created",
  func=function()return true,api.world_origin() end})
core.register_chatcommand("survey",{description="Close dispatcher and look at a map tile (X Z)",params="[X Z]",func=function(name,args)
  local p=core.get_player_by_name(name)
  local x,z=args:match("^(%d+)%s+(%d+)$")
  if not p then return false end
  if args~="" and (not x or not Sim.id(tonumber(x),tonumber(z))) then return false,("Use coordinates inside 1–%d, 1–%d."):format(Sim.W,Sim.H) end
  ui.survey(p,x and Sim.id(tonumber(x),tonumber(z)))
  return true,"WASD flies. Right-click for the build menu."
end})
if api.terrain then
  core.register_chatcommand("landscape",{
    description="Raise, lower or level actual shared terrain corners",
    params="raise|lower|level X Z [END_X END_Z [diagonal]]",
    func=function(name,args)
      local mode,x,z,extra=args:match("^(%a+)%s+(%d+)%s+(%d+)%s*(.-)%s*$")
      if mode~="raise" and mode~="lower" and mode~="level" then
        return false,"Use /landscape raise|lower|level X Z [END_X END_Z [diagonal]]."
      end
      local u,v,diag
      if extra~="" then
        u,v,diag=extra:match("^(%d+)%s+(%d+)%s*(%a*)$")
        if not u or (diag~="" and diag~="diagonal") then return false,"Use two end coordinates and optionally diagonal." end
      end
      local ok,msg,changed,peak=Sim.landscape(S,name,mode,tonumber(x),tonumber(z),tonumber(u),tonumber(v),diag=="diagonal")
      if ok then
        render.raise_bound(peak);render.update(changed);api.save()
      end
      return ok,msg
    end,
  })
end
if api.terrain and (S.road_mail or api.freight_tools) then
  core.register_chatcommand("truckstop",{
    description="Build a stock truck loading stop",
    params="X Z",
    func=function(name,args)
      local x,z=args:match("^(%d+)%s+(%d+)$")
      local id=x and Sim.id(tonumber(x),tonumber(z))
      if not id then return false,"Use /truckstop X Z on a road tile." end
      local ok,msg,changed=Sim.build_truck_stop(S,name,id)
      if not ok then return ok,msg end
      render.update(changed);api.save()
      local st=S.stations[S.tiles[id].station]
      if api.freight_tools then
        st.freight_art=true;st.coal_art=Sim.road_coal_active(S) or nil
        render.update(changed);api.save()
        if api.oil_tools then
          local _,oil=Sim.oil_stop_status(S,st,"oil")
          local _,goods=Sim.oil_stop_status(S,st,"goods")
          return true,msg..(oil.accepts and " Accepts oil." or "")..(goods.accepts and " Accepts Goods." or "")
        end
        if api.timber_tools then
          local _,wood=Sim.timber_stop_status(S,st,"wood")
          local _,goods=Sim.timber_stop_status(S,st,"goods")
          return true,msg..(wood.accepts and " Accepts wood." or "")..(goods.accepts and " Accepts goods." or "")
        end
        local _,accepted=Sim.coal_stop_status(S,st)
        return true,msg..(accepted and " A nearby power station accepts coal." or " Coal can be collected near a mine.")
      end
      local _,accept=Sim.mail_stop_status(S,st)
      return true,msg..(accept and " This stop accepts mail." or " Not enough nearby buildings to accept mail.")
    end,
  })
end
if api.structure_tools then
  core.register_chatcommand("roadtunnel",{
    description="Bore a stock road tunnel through a hill",
    params="X Z [remove]",
    func=function(name,args)
      local x,z,extra=args:match("^(%d+)%s+(%d+)%s*(%a*)$")
      local id=x and Sim.id(tonumber(x),tonumber(z))
      if not id or (extra~="" and extra~="remove") then return false,"Use /roadtunnel X Z [remove]." end
      local ok,msg,changed
      if extra=="remove" then ok,msg,changed=Sim.remove_road_tunnel(S,name,id)
      else ok,msg,changed=Sim.road_tunnel(S,name,id) end
      if ok then render.update(changed);api.save() end
      return ok,msg
    end,
  })
  local function bridge_tool(command,style,kind)
    core.register_chatcommand(command,{
      description="Construct a stock "..kind.." road bridge",
      params="X Z END_X END_Z | X Z remove",
      func=function(name,args)
        local x,z,tail=args:match("^(%d+)%s+(%d+)%s+(.+)$")
        local first=x and Sim.id(tonumber(x),tonumber(z))
        if not first then return false,"Use /"..command.." X Z END_X END_Z or X Z remove." end
        local ok,msg,changed,deck
        if tail=="remove" then ok,msg,changed,deck=Sim.remove_wood_bridge(S,name,first)
        else
          local a,b=tail:match("^(%d+)%s+(%d+)$")
          local last=a and Sim.id(tonumber(a),tonumber(b))
          if not last then return false,"Select the other bridgehead." end
          ok,msg,changed,deck=Sim.road_bridge(S,name,first,last,style)
        end
        if ok then render.raise_bound(deck);render.update(changed);api.save() end
        return ok,msg
      end,
    })
  end
  bridge_tool("woodbridge",0,"timber")
  bridge_tool("girderbridge",2,"steel girder")
  bridge_tool("concretebridge",1,"concrete")
end
core.register_chatcommand("bayline_help",{description="List LuanTTD’s key commands",func=function()
  return true,"WASD flies; Space/Shift changes altitude; hold E to fly faster; left click uses your tool; right click opens the palette. Open Inventory for company operations or Jump map for navigation."
end})

local rail_build_enabled=true
do
  local Lab=api.trackworks
  local RailMotion=dofile(mod.."/openttd/rail_motion.lua")(Track)
  api.trackworks_demo=dofile(mod.."/trackworks_demo.lua")(api,Track,RailMotion,dofile(mod.."/openttd/road_speed.lua"),
    api.slope or dofile(mod.."/openttd/slope.lua"))
  local RailSpeed=dofile(mod.."/openttd/rail_station_speed.lua")(Track,Follow)
  local Run=dofile(mod.."/rail_platform_run.lua")(Sim,Track,RailMotion,RailSpeed,Lab)
  api.rail_platform_run=Run
  local Pose=dofile(mod.."/rail_pose.lua")(Track)
  api.rail_platform_view=dofile(mod.."/rail_platform_view.lua")(api,Run,Pose)
  pilot_clock(function() return Run.current(S) end,function(n) Run.tick(S,n) end)
  local function dispatch_active()
    local dispatch=S.stock_rail_dispatch
    return dispatch and #dispatch.runs>0
  end
  local function dispatch_signal(id)
    local dispatch=S.stock_rail_dispatch
    return dispatch and dispatch.signals.records[id]~=nil
  end
  do
    local source=mod.."/openttd/"
    local Pilot,Signal,Roster,height,H,profile=simulation_bindings.rail(S,{
      track=Track,follow=Follow,cost=RailCost,search=RailSearch,lab=Lab,motion=RailMotion,speed=RailSpeed,
      slope=api.slope,terrain_tile=api.terrain.tile,spans=api.rail_spans,crossings=api.crossings,
      owned=api.rail_owned_tools,
    })
    local function presentation(id,td,f,part)
      local crossing=api.crossings and api.crossings.world.record(S,id)
      if crossing then return crossing.top,0 end
      if api.rail_spans then
        local level,tilt=api.rail_spans.presentation(S,id,td,f,part)
        if level~=nil then return level,tilt end
      end
      local data=profile(id)
      if data then return H.render(data,td,f) end
    end
    if Roster then
      api.rail_owned=simulation_bindings.owned_rail(S,Lab,Roster,Pilot,
        function() return api.rail_oil_tools==true end)
      api.vehicle_orders.rail=dofile(mod.."/rail_vehicle_orders.lua")(S,api.rail_owned,
        dofile(source.."rail_order_cargo.lua"))
      if api.electric_tools then
        local Types=dofile(source.."rail_types.lua")
        api.rail_owned.mount_electric(Types)
        local Wire=dofile(mod.."/rail_electrification_world.lua")(Sim,dofile(source.."terrain.lua"),Track,Types,api.rail_spans)
        local function mask(owner) return api.rail_owned.railtype_mask(S,owner,Types) end
        local ctx={availability=function(_,owner) return mask(owner) end,
          is_clear=function() return not api.trackworks_demo or api.trackworks_demo.is_clear() end}
        ctx.span_art_ready=function(_,span)
          return span.kind=="bridge" and api.rail_bridge_wire_art and api.rail_dispatch_view and
            api.rail_dispatch_view.split_electric_ready()
        end
        api.electric_available=function(owner) return Types.available(1,mask(owner),0) end
        api.electric_quote=function(owner,ids,target) return Wire.quote(S,owner,ids,target,ctx) end
        api.electric_commit=function(owner,ticket)
          local ok,price,ids=Wire.commit(S,owner,ticket,ctx)
          if ok then render.update(ids);api.save() end
          return ok,price,ids
        end
      end
      api.owned_rail_ui=dofile(mod.."/rail_owned_ui.lua")(api,ui.status)
    end
    if api.crossings then
      api.crossings.refresh(S,Lab.board(S))
      function api.crossing_quote(owner,id,request)
        local gauge=S.tiles[id] and S.tiles[id].rail_type or 0
        if gauge~=0 then return nil,gauge==1 and "ELECTRIC_CROSSING_NOT_MOUNTED" or "GUIDEWAY_CROSSING_NOT_MOUNTED" end
        if api.trackworks_demo and not api.trackworks_demo.is_clear() then return nil,"CLEAR_SURVEYED_TRAIN" end
        return api.crossings.quote(S,owner,id,request,Lab.board(S))
      end
      function api.crossing_commit(owner,quote)
        if api.trackworks_demo and not api.trackworks_demo.is_clear() then return false,"CLEAR_SURVEYED_TRAIN" end
        local ok,price,ids,record=api.crossings.commit(S,owner,quote,Lab.board(S))
        if ok then render.update(ids);api.save() end
        return ok,price,ids,record
      end
    end
    if api.rail_spans then
      function api.rail_spans.start(state,owner,depot,station)
        if api.trackworks_demo and not api.trackworks_demo.is_clear() then
          return false,"Clear the surveyed train first."
        end
        local ok,note,run=Pilot.start_span(state,owner,depot,station)
        if ok then api.save() end
        return ok,note,run
      end
    end
    S.rail_paid_service=true
    Sim.mount_paid_rail(S,Pilot)
    api.rail_coal_tools=Sim.rail_coal_active(S)
    if api.rail_coal_tools then world.enable_rail_coal() end
    api.rail_dispatch_controller=Pilot
    networks.dispatch=Pilot
    if rail_build_enabled then api.rail_build=simulation_bindings.rail_build(api,networks,Pilot,Signal) end
    local bridge_profile=api.rail_bridge_wire_art and api.rail_spans and dofile(mod.."/rail_bridge_wire_profile.lua")(
      Sim,api.rail_spans,api.rail_bridge_wire_art,Track,function(id,mask)
        local slope,height=api.terrain.tile(id)
        local slope_index,level=Lab.surface(slope,height,mask)
        if slope_index==0 then return level end
      end)
    local rail_art=dofile(mod.."/rail_dispatch_manifest.lua").scan(mod,S.stock_electrification,bridge_profile~=nil)
    rail_art.bridge_wire=bridge_profile~=nil
    Sim.mount_rail_mail(S,rail_art.ready.mail_van,rail_art.mixed_town_engines)
    api.rail_mixed_town_tools=S.rail_mixed_town_service
    api.rail_mail_tools=Sim.rail_mail_active(S)
    api.capabilities.rail=rail_art
    if rail_art.advanced[54] and world.mount_guideway_picker then world.mount_guideway_picker() end
    simulation_bindings.rail_media(Pilot,rail_art)
    api.rail_dispatch_view=dofile(mod.."/rail_dispatch_view.lua").create(api,Pilot,Track,Pose,
      dofile(mod.."/rail_signal_art.lua"),interval,presentation,bridge_profile,height,rail_art)
    pilot_clock(function()
      local d=Pilot.current(S)
      return d and not (d.runs[1] and d.runs[1].paid_clock)
    end,function(n)
      local events=Pilot.tick(S,n)
      local observe=api.rail_dispatch_view.observe
      if observe then observe(events) end
    end)
    if S.rail_goods_service then
      Sim.mount_rail_goods(S,function() return rail_art.ready.goods_van==true end)
      api.rail_goods_tools=Sim.rail_goods_active(S)
      if api.rail_goods_tools then world.enable_rail_goods() end
    end
    if S.rail_oil_service then
      if not rail_art.ready.oil_tanker then
        core.log("warning","Rail Oil paused: missing the stock Oil Tanker assets.")
        S.rail_oil_service=false
      else
        api.rail_oil_tools=Sim.rail_oil_active and Sim.rail_oil_active(S) or false
        if api.rail_oil_tools then world.enable_rail_oil() end
      end
    end
    Sim.mount_rail_freight_profiles(S,rail_art.ready)
    api.rail_iron_ore_tools=Sim.rail_profile_active(S,"iron_ore")
    api.rail_steel_tools=Sim.rail_profile_active(S,"steel")
    api.rail_valuables_tools=Sim.rail_profile_active(S,"valuables")
    if api.rail_valuables_tools then world.enable_rail_valuables() end
    api.rail_livestock_tools=Sim.rail_profile_active(S,"livestock")
    api.rail_grain_tools=Sim.rail_profile_active(S,"grain")
    api.rail_wood_tools=Sim.rail_profile_active(S,"wood")
    if api.rail_wood_tools then world.enable_rail_wood() end
    if api.rail_livestock_tools or api.rail_grain_tools then
      world.enable_rail_farm(api.rail_livestock_tools,api.rail_grain_tools)
    end
    if api.rail_iron_ore_tools or api.rail_steel_tools then
      world.enable_rail_metals(api.rail_iron_ore_tools,api.rail_steel_tools)
    end
    dofile(mod.."/rail_dispatch_commands.lua")(api,Pilot,Track,Signal)
  end
  core.register_chatcommand("railtrial",{
    description="Run a single test locomotive from a real depot to a real platform",
    params="DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z | status | clear",
    func=function(name,args)
      local current=Run.current(S)
      if args=="status" or args=="" then
        if not current or current.owner~=name then return false,"No rail pilot for your company." end
        return true,("Pilot %s • station #%d • %d stock steps%s"):format(current.phase,current.station,
          current.stock_steps,current.failure and (" • "..current.failure) or "")
      elseif args=="clear" then
        local ok,msg=Run.clear(S,name)
        if ok then api.save() end
        return ok,msg
      end
      local a,b,c,d=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local from=a and Sim.id(tonumber(a),tonumber(b))
      local goal=c and Sim.id(tonumber(c),tonumber(d))
      if not from or not goal then return false,"Use /railtrial DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z." end
      local station=S.tiles[goal].rail_station_id
      if not station then return false,"Build or select a real rail platform first." end
      if dispatch_active() then return false,"Clear the coupled rail dispatch first." end
      if not api.trackworks_demo.is_clear() then return false,"Wait for or clear the surveyed-route demonstration first." end
      local ok,msg=Run.start(S,name,from,station)
      if ok then api.save() end
      return ok,msg
    end,
  })
  core.register_chatcommand("trackworks",{
    description="Inspect or build a stock track piece",
    params="X Z [x|y|upper|lower|left|right] [remove]",
    func=function(name,args)
      local x,z,remainder=args:match("^(%d+)%s+(%d+)%s*(.-)%s*$")
      local id=x and Sim.id(tonumber(x),tonumber(z))
      if not id then return false,"Use /trackworks X Z [piece] [remove]." end
      if remainder~="" then
        if dispatch_active() then return false,"Clear the coupled pilot before editing its railway." end
        if dispatch_signal(id) then return false,"Cannot edit track beneath a path signal in this preview." end
        local word,action=remainder:match("^(%a+)%s*(%a*)$")
        local track=Lab.piece(word)
        if not track or (action~="" and action~="remove") then
          return false,"Pieces: x, y, upper, lower, left, right. Optionally add remove."
        end
        if api.rail_build then
          local quote,why=api.rail_build.quote_track(name,id,id,track,action=="remove")
          if not quote then return false,why end
          local ok,note=api.rail_build.build(name,quote)
          if not ok then return false,note end
        else
          local shape=api.terrain and api.terrain.tile(id) or 0
          local ok,msg=Lab.change(S,name,id,track,action=="remove",shape)
          if not ok then return false,msg end
          render.update({id});api.save()
        end
      end
      local bits,exits=Lab.inspect(S,id,name)
      return true,bits and ("Track mask %d; %d connected travel directions. Scheduled train service is not enabled in Trackworks."):format(bits,exits)
        or "No Trackworks pieces on this tile."
    end,
  })
  core.register_chatcommand("trackfacility",{
    description="Install a rail platform or depot on existing Trackworks track",
    params="X Z platform X2 Z2 | X Z depot east|west|north|south | X Z remove",
    func=function(name,args)
      local x,z,kind,tail=args:match("^(%d+)%s+(%d+)%s+(%a+)%s*(.-)%s*$")
      local id=x and Sim.id(tonumber(x),tonumber(z))
      if not id then return false,"Use /trackfacility X Z platform X2 Z2, depot DIRECTION, or remove." end
      if dispatch_active() then return false,"Clear the coupled pilot before editing its facilities." end
      if dispatch_signal(id) then return false,"The tile has a path signal." end
      local ok,msg,changed
      if kind=="platform" then
        local a,b=tail:match("^(%d+)%s+(%d+)$")
        local last=a and Sim.id(tonumber(a),tonumber(b))
        if not last then return false,"Supply the coordinates of the other platform end." end
        for _,cell in ipairs(Sim.line(id,last)) do if dispatch_signal(cell) then return false,"A platform cannot cover a path signal." end end
        if api.rail_build then
          local p,reason=api.rail_build.quote_platform(name,id,last,2)
          if not p then return false,reason end
          return api.rail_build.build(name,p)
        end
        ok,msg,changed=Lab.station(S,name,id,last)
      elseif kind=="depot" then
        local dir=({west=Track.NE,south=Track.SE,east=Track.SW,north=Track.NW})[tail]
        if not dir then return false,"Choose a depot direction: east, west, north or south." end
        if api.rail_build then
          local p,reason=api.rail_build.quote_depot(name,id,dir)
          if not p then return false,reason end
          return api.rail_build.build(name,p)
        end
        ok,msg,changed=Lab.depot(S,name,id,dir)
      elseif kind=="remove" and tail=="" then
        ok,msg,changed=Lab.remove_facility(S,name,id)
      else return false,"Use /trackfacility X Z platform X2 Z2, depot DIRECTION, or remove." end
      if ok then render.update(changed);api.save() end
      return ok,msg
    end,
  })
  core.register_chatcommand("trackroute",{
    description="Survey a rail route with the ported OpenTTD YAPF planner",
    params="X1 Z1 X2 Z2",
    func=function(name,args)
      local a,b,c,d=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local first=a and Sim.id(tonumber(a),tonumber(b))
      local last=c and Sim.id(tonumber(c),tonumber(d))
      if not first or not last then return false,"Use /trackroute X1 Z1 X2 Z2." end
      local path,cost=Lab.plan(S,first,last,name)
      if not path then return false,"No route to a flat straight test platform at that Trackworks destination." end
      local where={}
      for i=1,math.min(#path,10) do
        local x,z=Sim.xy(path[i].tile)
        where[#where+1]=("%d,%d"):format(x,z)
      end
      return true,("YAPF route: %d tiles, cost %d. %s%s"):format(#path,cost,
        table.concat(where,"  /  "),#path>10 and "  /  …" or "")
    end,
  })

  core.register_chatcommand("trackrun",{
    description="Run one 3D test locomotive along the surveyed route",
    params="X1 Z1 X2 Z2",
    func=function(name,args)
      local a,b,c,d=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local first=a and Sim.id(tonumber(a),tonumber(b))
      local last=c and Sim.id(tonumber(c),tonumber(d))
      if args=="clear" then api.trackworks_demo.leave(name);return true,"Surveyed-route demonstration cleared." end
      if Run.current(S) then return false,"Clear the depot-to-platform pilot first." end
      if dispatch_active() then return false,"Clear the coupled rail dispatch first." end
      if not first or not last then return false,"Use /trackrun X1 Z1 X2 Z2." end
      return api.trackworks_demo.start(name,first,last)
    end,
  })

end

-- Old debug commands captured the initial Sim table. Keep only engine-
-- side navigation shortcuts live while this process is not the owner.
if worker_boot then
  local native_only={walk=true,car=true,plane=true,train=true,ride=true,tools=true,dispatch=true,bayline_help=true,world_origin=true}
  for name,definition in pairs(core.registered_chatcommands) do
    if definition.mod_origin=="luanttd_core" and not native_only[name] then
      local prior=definition.func
      core.override_chatcommand(name,{func=function(player,args)
        if api.authority_handoff then return false,"Use the native construction or company controls in this world." end
        return prior(player,args)
      end})
    end
  end
end
