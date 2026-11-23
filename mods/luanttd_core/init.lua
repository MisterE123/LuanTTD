local mod=core.get_modpath(core.get_current_modname())
local storage=core.get_mod_storage()
local Sim=dofile(mod.."/sim.lua")
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
local Checkpoint=dofile(mod.."/campaign_checkpoint.lua")(core)
local checkpoint=Checkpoint.read()
local saved=checkpoint or storage:get_string("campaign")
local settings=core.settings
local fresh=saved==""
-- Native QA can inject fixtures into its disposable installation.
local qa={}
local qa_path=mod.."/qa_layout.lua"
local qa_file=io.open(qa_path,"r")
if qa_file then qa_file:close();qa=dofile(qa_path)(settings,mod) end
local fixture=qa.enabled
local WorldSetup=dofile(mod.."/world_setup.lua")
local world_options=WorldSetup.read(core,storage)
if fresh and not fixture and not world_options and core.is_singleplayer() then
  WorldSetup.mount(core,storage)
  return
end
local scenario=qa.scenario or (world_options and world_options.scenario) or "generated"
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
local Generated,Generator,Terrain
local S
if saved~="" then
  S=core.deserialize(saved,true)
elseif generated_world then
  local source=mod.."/openttd/"
  Generated=dofile(mod.."/generated_campaign.lua")
  Terrain=dofile(source.."terrain.lua")
  local Slope=dofile(source.."slope.lua")
  local TG=dofile(source.."terragenesis.lua")(Slope)
  local Clear=dofile(source.."terragenesis_clear.lua")
  local Rivers=dofile(source.."river_worldgen.lua")(Slope)
  Generator={generate=function(o)
      local base=TG.generate(o)
      local river,stats=Rivers.generate(base,TG.next_random,{original=false,terrain=Terrain,
        amount_of_rivers=o.amount_of_rivers,min_river_length=o.min_river_length})
      return Clear.generate(river,TG.next_random),stats
    end,
    next_random=TG.next_random,describe=Clear.describe}
  local seed=world_options and world_options.seed or tonumber(core.settings:get("bayline_seed")) or 1751
  local size=world_options and world_options.size or tonumber(core.settings:get("bayline_generated_map_size")) or Generated.size
  S=Generated.landscape(Sim,Terrain,Generator,{
    width=size,depth=size,seed=seed,rng_state=TG.startup_rng(seed),
    terrain_type=world_options and world_options.relief or tonumber(core.settings:get("bayline_generated_relief")) or 1,
    quantity_sea_lakes=world_options and world_options.sea or tonumber(core.settings:get("bayline_generated_sea")) or 0,
    amount_of_rivers=world_options and world_options.rivers or tonumber(core.settings:get("bayline_generated_rivers")) or 0,
    min_river_length=tonumber(core.settings:get("bayline_generated_min_river_length")) or 16,
    tgen_smoothness=world_options and world_options.smooth or tonumber(settings:get("bayline_generated_smoothness")) or 1,
    water_borders=world_options and world_options.coast or tonumber(settings:get("bayline_generated_coasts")) or 15,
    variety=world_options and world_options.variety or tonumber(settings:get("bayline_generated_variety")) or 0,
    freeform_edges=true,
  })
else
  S=Sim.new(fixture and tonumber(settings:get("bayline_seed")) or 1751)
end
if type(S)~="table" or S.version~=1 then error("Unsupported LuanTTD save; use a fresh world.") end
assert(not checkpoint or (S.stock_generated_profile and S.stock_generated_profile.width==128),
  "The wide campaign checkpoint does not describe a wide campaign.")
local wide_checkpoint=S.stock_generated_profile and S.stock_generated_profile.width==128
if S.stock_generated_profile then
  local p=S.stock_generated_profile
  local generated=Generated or dofile(mod.."/generated_campaign.lua")
  assert(p.version==1 and generated.supports_size(p.width,p.depth) and S.corner_grid.width==p.width and
    S.corner_grid.depth==p.depth and #S.tiles==p.width*p.depth and
    #S.corner_grid.levels==(p.width+1)*(p.depth+1),"Unsupported generated campaign dimensions")
  local clock=S.passenger_house_clock
  local width_log=p.width==128 and 7 or 6
  assert(not clock or (clock.log_x==width_log and clock.log_y==width_log and
    type(clock.head)=="number" and clock.head%1==0 and clock.head>=1 and clock.head<p.width*p.depth),
    "Saved landscape clock does not cover the generated region")
  Sim.W,Sim.H=p.width,p.depth
  generated_world=true
end
Sim.restore_road_orders(S)
local api={Sim=Sim,s=S,generated_world=generated_world,road_first=true}
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
  Sim.mount_road_bus_market(S,dofile(mod.."/openttd/stock_engine_calendar.lua"),
    world_options and world_options.year or tonumber(settings:get("bayline_stock_bus_start_year")) or 1950,
    files["bl_foster_bus.obj"] and files["bl_foster_bus_atlas.png"],
    files["bl_craighead_goods_truck.obj"] and files["bl_craighead_goods_truck_atlas.png"])
  api.bus_breakdowns=tonumber(settings:get("bayline_stock_bus_breakdowns")) or 2
  api.bus_service_interval=tonumber(settings:get("bayline_stock_bus_service_interval")) or 150
  Sim.mount_road_faults(S,dofile(mod.."/openttd/road_breakdowns.lua"),
    dofile(mod.."/road_faults_runtime.lua"),api.bus_breakdowns,
    {kernel=dofile(mod.."/openttd/road_depot_service.lua"),
     interval=api.bus_service_interval,percent=settings:get_bool("bayline_stock_bus_service_percent",false)})
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
  if S.stock_coastal_profile then
    S.road_stock_house_supply=true
    Sim.mount_coastal_flood(S)
    api.coastal_flood_tools=true
  end
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
do
  S.road_stock_loading,S.road_stock_clock,S.road_stock_house_supply,S.road_economy=true,true,true,true
  local src=mod.."/openttd/"
  local G=dofile(src.."town_growth.lua")
  local B=dofile(src.."town_growth_build.lua")(G,dofile(src.."town_growth_houses.lua"))
  if Generated then
    local layout=world_options and world_options.layout or core.settings:get("bayline_generated_town_layout") or "original"
    local Worldgen=dofile(src.."town_worldgen.lua")(G,B)
    local Names=dofile(src.."stock_town_name.lua")
    local generated,why=Generated.towns(Sim,Terrain,S,Generator,Worldgen,Names,G,B,{
      layout=layout,difficulty=world_options and world_options.towns or tonumber(core.settings:get("bayline_generated_towns")) or 2,
      larger_towns=4,initial_city_size=2,year=Sim.date(S),
    })
    assert(generated,why)
  end
  api.town_growth=dofile(mod.."/town_growth_runtime.lua")(Sim,dofile(src.."terrain.lua"),G,B,
    dofile(src.."town_passengers.lua"))
  Sim.mount_stock_town_growth(S,api.town_growth,true)
end
if Generated then
  local src=mod.."/openttd/"
  local P,Rating=dofile(src.."passengers.lua"),dofile(src.."station_rating.lua")
  local Cat=dofile(src.."station_catchment.lua")(P,Rating,function()return 0 end,function()return 0 end)
  local Coal=dofile(src.."coal_industry.lua")(P,Rating,Cat,dofile(src.."income.lua"))
  local Timber=Sim.timber_rules()
  local Industry=dofile(src.."industry_worldgen.lua")(Coal,Timber or nil)
  local World=dofile(mod.."/coal_industry_world.lua")(Sim,Terrain,Coal)
  local TimberWorld=Timber and dofile(mod.."/timber_world.lua")(Sim,Terrain,Timber)
  Generated.industries(Sim,Terrain,S,Generator,Industry,World,
    world_options and world_options.industries or tonumber(core.settings:get("bayline_generated_industries")) or 4,
    tonumber(core.settings:get("bayline_generated_industry_count")),TimberWorld)
  local calendar=Sim.engine_calendar or dofile(src.."stock_engine_calendar.lua")
  Generated.landmarks(Sim,Terrain,S,Generator,dofile(src.."scenery_object_worldgen.lua"),calendar.date(Sim.date(S)))
  local mode=world_options and world_options.trees or tonumber(core.settings:get("bayline_generated_tree_placer")) or 2
  Generated.forests(Sim,Terrain,S,Generator,dofile(src.."tree_worldgen.lua"),mode)
end
if generated_world then
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
if S.road_farm then
  assert(api.terrain and S.seed==1751,"The farm workbench requires a fresh 1751 scenario and corner terrain.")
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local assets=dofile(mod.."/farm_visual_assets.lua")
  local missing=assets.missing(core,mod)
  assert(not missing,"The farm workbench is missing the asset "..tostring(missing))
  local mounted,rng=Sim.mount_farm_world(S,Terrain,true)
  api.farm_world=assert(mounted,rng)
  api.farm_visual_assets=assets
  if saved=="" then
    local seeded,why=api.farm_world.default_1751(S,rng)
    assert(seeded,"No clean farm/factory corridor: "..tostring(why))
  end
  api.farm_view=dofile(mod.."/farm_field_view.lua")(api,Terrain)
end
api.farm_tools=api.farm_world and Sim.road_farm_active(S)
if S.road_oil then
  assert(api.terrain and S.seed==1751,"Stock oil freight requires a fresh seed-1751 corner terrain world.")
  local files={}
  for _,folder in ipairs({"models","textures"}) do
    for _,name in ipairs(core.get_dir_list(mod.."/"..folder,false)) do files[name]=true end
  end
  local oil,why=Sim.mount_oil_world(S,dofile(mod.."/openttd/terrain.lua"),
    files["bl_witcombe_oil_tanker.obj"] and files["bl_witcombe_oil_tanker_atlas.png"])
  assert(oil,why)
  for style,parts in pairs(oil.visual_sources()) do
    assert(files["bl_"..style.."_atlas.png"],"Missing oil industry atlas "..style)
    for _,piece in ipairs(parts) do
      local file=("bl_%s_%d_%d.obj"):format(style,piece[1],piece[2])
      assert(files[file],"Missing stock oil site mesh: "..file)
    end
  end
  api.oil_world=oil
  if saved=="" then
    local good,error_=oil.default_1751(S)
    assert(good,"No untouched oil corridor in this world: "..tostring(error_))
  end
end
api.oil_tools=api.oil_world and Sim.road_oil_active(S)
api.freight_tools=(api.stock_coal_scenery and S.road_coal) or api.timber_tools or api.farm_tools or api.oil_tools
local Track=dofile(mod.."/openttd/rail_track.lua")
local Follow=dofile(mod.."/openttd/rail_follow.lua")(Track)
local RailCost=dofile(mod.."/openttd/rail_yapf_cost.lua")(Track,Follow)
local RailSearch=dofile(mod.."/openttd/rail_yapf_search.lua")(Track,Follow,RailCost)
api.trackworks=dofile(mod.."/trackworks.lua")(Sim,Track,Follow,api.slope or dofile(mod.."/openttd/slope.lua"),
  RailCost,RailSearch,api.terrain and api.terrain.tile)
do
  local source=mod.."/openttd/"
  S.rail_span_enabled=true
  api.rail_span_tools=true
  local H=dofile(source.."rail_height.lua")(Track,api.slope)
  local Q=dofile(source.."rail_construction.lua")(Track,dofile(source.."rail_signals.lua")(Track),H)
  local Site=dofile(source.."rail_span_site.lua")
  local B=dofile(source.."rail_bridge.lua")(dofile(source.."road_bridge.lua")(api.slope),Q,Site)
  local T=dofile(source.."rail_tunnel.lua")(dofile(source.."road_tunnel.lua"),Q,Site,Track)
  api.rail_spans=dofile(mod.."/rail_span_world.lua")(Sim,dofile(source.."terrain.lua"),H,B,T,Track)
end
do
  local source=mod.."/openttd/"
  local kernel=dofile(source.."level_crossing.lua")(Track)
  local adapter=dofile(mod.."/level_crossing_world.lua")(Sim,dofile(source.."terrain.lua"),kernel,Track)
  api.crossings=dofile(mod.."/level_crossing_runtime.lua")(Sim,adapter)
  S.level_crossing_enabled,api.crossing_tools=true,true
  adapter.reindex(S)
  Sim.mount_crossings(S,api.crossings,function(s)
    local live=api.rail_dispatch_controller
    return live and live.board(s) or api.trackworks.board(s)
  end,function() return not api.trackworks_demo or api.trackworks_demo.is_clear() end)
end
do
  local source=mod.."/openttd/"
  local RoadFollow=dofile(source.."yapf_road_follow.lua")
  local Rules=dofile(source.."road_oneway.lua")(dofile(source.."road_slope.lua"),RoadFollow)
  local OneWay=dofile(mod.."/road_oneway_world.lua")(Sim,dofile(source.."terrain.lua"),RoadFollow,Rules)
  api.oneway,api.oneway_tools=OneWay,true
  Sim.mount_road_oneway(S,OneWay)
end
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
if api.tram_tools then
  local source=mod.."/openttd/"
  local Terrain=dofile(source.."terrain.lua")
  local Bridge=dofile(source.."road_bridge.lua")(api.slope)
  local Construct=dofile(source.."tram_construction.lua")(dofile(source.."road_slope.lua"),Bridge.roadtypes)
  local Network=dofile(mod.."/tram_network.lua")(Sim,Construct,Terrain)
  local RoadMotion=dofile(source.."road_motion.lua")(dofile(source.."road_motion_data.lua"))
  local Motion=dofile(source.."tram_motion.lua")(dofile(source.."tram_motion_data.lua"),RoadMotion)
  local F=dofile(source.."yapf_road_follow.lua")
  local C=dofile(source.."yapf_road_cost.lua")(F)
  local Y=dofile(source.."yapf_road_search.lua")(F,C)
  local Trip=dofile(mod.."/tram_trip.lua")(F,C,Y,Motion)
  local Run=dofile(mod.."/tram_preview_run.lua")(Network,Trip,dofile(source.."road_speed.lua"))
  local Pose=dofile(mod.."/road_motion_presentation.lua")(dofile(mod.."/road_lanes.lua"))
  api.tram_view=dofile(mod.."/tram_preview_view.lua")(api,Run,Pose,dofile(mod.."/road_motion.lua"),interval)
  dofile(mod.."/tram_preview_commands.lua")(api,Network,Run)
end
local water_order_run, coal_order_run, coal_order_runtime, air_order_run
if api.ship_tools then
  local source=mod.."/openttd/"
  local Water=dofile(source.."ship_follow.lua")(Track)
  local Y=dofile(source.."ship_yapf.lua")(Track,Water,dofile(source.."yapf_road_search.lua"))
  local Terrain=dofile(source.."terrain.lua")
  local Facilities=dofile(source.."ship_facilities.lua")(Track,Water)
  local Network=dofile(mod.."/ship_network.lua")(Sim,Terrain,Water,Facilities)
  local Motion=dofile(source.."ship_motion.lua")(Track,Water)
  local Regions=dofile(source.."ship_regions.lua")
  local Roster=dofile(source.."passenger_ship_roster.lua")
  local Calendar=dofile(source.."stock_engine_calendar.lua")
  local Run=dofile(mod.."/ship_preview_run.lua")(Network,Track,Water,Y,Motion,Regions,
    {width=Sim.W,height=Sim.H,x0=1,z0=1},{engine=Roster.model(206),engine_for=Roster.model,validate_both=true})
  water_order_run=Run
  local art={}
  local missing={}
  for _,key in ipairs(core.get_dir_list(mod.."/models",false)) do missing[key]=true end
  for _,key in ipairs(core.get_dir_list(mod.."/textures",false)) do missing[key]=true end
  art[206]=missing["bl_harbor_ferry_palette.png"] and missing["bl_harbor_ferry.obj"]
  art[207]=missing["bl_harbor_ferry_palette.png"] and missing["bl_ffp_passenger_ferry.obj"]
  local Depot=dofile(mod.."/passenger_ship_depot.lua")(Sim,Roster,Calendar,Run,function(id) return art[id] end)
  Run.settle_owned_day,Run.count_owned_tick,Run.paid_art_ready=Depot.settle,Depot.count_tick,Depot.ready
  api.passenger_ferry={
    catalog=Roster.order,quote=function(n,depot,id) return Depot.quote(S,n,depot,id) end,
    model=Roster.model,
    buy=function(n,depot,id) local v,msg=Depot.buy(S,n,depot,id);if v then api.save() end;return v,msg end,
    staged=function(n,depot) return Depot.staged(S,n,depot) end,
    start=function(n,depot,a,b,via) return Depot.start(S,n,depot,a,b,via) end,
    stop=function(n,stop) local ok,msg=Depot.stop(S,n,stop);if ok then api.save() end;return ok,msg end,
  }
  S.ship_paid_service=true
  Sim.mount_paid_ferry(S,Run)
  if S.ship_coal_service or S.stock_coal_ship then
    local cargo_run=dofile(mod.."/ship_preview_run.lua")(Network,Track,Water,Y,Motion,Regions,
      {width=Sim.W,height=Sim.H,x0=1,z0=1},{engine=dofile(source.."ship_roster.lua"),
        key="stock_coal_ship_run",serial="next_stock_coal_ship_run",paid=function() return true end,
        validate_both=true})
    local C=Sim.mount_coal_ship(S,cargo_run,Run,Network)
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
  api.ship_view=dofile(mod.."/ship_preview_view.lua")(api,Run,dofile(mod.."/road_motion.lua"),interval)
  dofile(mod.."/ship_preview_commands.lua")(api,Network,Run)
end
if api.airport_tools then
  local source=mod.."/openttd/"
  local Terrain=dofile(source.."terrain.lua")
  local Small=dofile(source.."airport_small.lua")
  local Motion=dofile(source.."airport_motion.lua")(Small)
  local Network=dofile(mod.."/airport_network.lua")(Sim,Terrain,Small)
  local Roster=dofile(source.."airport_roster.lua")
  local Run=dofile(mod.."/airport_preview_run.lua")(Sim,Network,Small,Motion,Terrain,api.slope,Roster)
  air_order_run=Run
  S.air_paid_service=true
  Sim.mount_paid_air(S,Run)
  api.airport_view=dofile(mod.."/airport_preview_view.lua")(api,Run,dofile(mod.."/road_motion.lua"),interval)
  Run.paid_art_ready=function(p) return not p or not p.engine_id or api.airport_view.has(p.engine_id) end
  local Owned=dofile(mod.."/airport_owned.lua")(Sim,Run,Roster,api.airport_view.has)
  dofile(mod.."/airport_preview_commands.lua")(api,Network,Run,Owned,Roster)
end
local ground_orders=dofile(mod.."/road_vehicle_orders.lua")(api)
api.vehicle_orders.road,api.vehicle_orders.tram=ground_orders.road,ground_orders.tram
if api.rail_owned then
  local flags=dofile(mod.."/openttd/rail_order_cargo.lua")
  api.vehicle_orders.rail={
    read=function(owner,id)
      local d,note=api.rail_owned.order_state(S,owner,id)
      if not d then return d,note end
      local labels,items={},{}
      for _,x in ipairs(d.stops or {}) do labels[x.id]=x.label end
      for i,x in ipairs(d.orders or {}) do
        local f=d.cargo and d.cargo[i]
        items[i]={id=x,label=(labels[x] or ("Station #"..x))..(f and f.summary or ""),cargo=f}
      end
      local c=d.capabilities or {}
      return {items=items,targets=d.stops,active=d.active,revision=d.revision,can_insert=c.add,
        can_reorder=c.move,can_remove=c.remove,can_skip=c.skip,can_replace=c.replace,summary=d.reason,
        cargo_rules=c.load and flags or nil}
    end,
    edit=function(owner,id,rev,op,i,dest)
      local verbs={append="add",up="move",down="move"}
      local val=op=="up" and i-1 or op=="down" and i+1 or dest
      if op=="append" then i=nil end
      return api.rail_owned.edit_orders(S,owner,id,rev,verbs[op] or op,i,val)
    end,
  }
end
local water_air_orders=dofile(mod.."/water_air_orders.lua")(S,Sim,
  dofile(mod.."/openttd/rail_order_list.lua"),water_order_run,coal_order_run,coal_order_runtime,air_order_run)
api.vehicle_orders.ship,api.vehicle_orders.air=water_air_orders.ship,water_air_orders.air
if api.stock_coal_scenery then api.coal_view=dofile(mod.."/coal_industry_view.lua")(api) end
local placement_key="world_setup_terrain_placed_v1"
local placement=world_options
  and storage:get_string(placement_key)~="placed" and "pending" or nil
local save_elapsed,hud_elapsed=0,0
local headless=true
api.offline_economy=headless
local campaign=dofile(mod.."/campaign_step.lua").new(S,interval,{
  advance=Sim.daily,capture=render.capture,refresh=render.update,
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
  if api.farm_view then api.farm_view.step(dt) end
  if api.trackworks_demo then api.trackworks_demo.step(dt) end
  local online=#core.get_connected_players()>0
  if api.rail_platform_view then api.rail_platform_view.step(dt,online) end

  if api.tram_view then api.tram_view.step(dt,online) end
  if not online then
    campaign.step(dt,false,headless)
    if api.airport_view then api.airport_view.step(dt,false,1) end
    if api.ship_view then api.ship_view.step(dt,false,1) end
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
core.register_on_shutdown(api.save)
local atmosphere=dofile(mod.."/atmosphere.lua").start(core,function()
  return not placement and S.speed or 0
end)
local function open_campaign_player(p)
  local name=p:get_player_name()
  Sim.company(S,name)
  world.spawn(p)
  atmosphere(p)
  api.save()
  core.after(0.6,function()
    local who=core.get_player_by_name(name)
    if who then ui.hud();world.hud(who) end
  end)
end
local function show_placement(p)
  local n=p:get_player_name()
  p:set_physics_override({speed=0,jump=0,gravity=0})
  p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false})
  core.show_formspec(n,"luanttd_core:placing_terrain",
    "formspec_version[7]size[9.6,2.45]bgcolor[#111F2C;both;#111F2C]"..
    "style_type[label;textcolor=#EEE6C9]label[.5,.70;"..
    (placement=="failed" and "Terrain placement did not finish. Reopen this world to retry." or
      "Placing your landscape…").."]label[.5,1.55;Your saved generator options will be kept.]")
end
core.register_on_joinplayer(function(p)
  if placement then show_placement(p) else open_campaign_player(p) end
end)
if placement then
  core.after(0,function()
    render.place_world(function(ok)
      if not ok then
        placement="failed"
        core.log("error","LuanTTD could not emerge the full terrain area; placement will retry on reopen.")
        for _,p in ipairs(core.get_connected_players()) do show_placement(p) end
        return
      end
      placement=nil
      storage:set_string(placement_key,"placed")
      api.save()
      for _,p in ipairs(core.get_connected_players()) do
        core.close_formspec(p:get_player_name(),"luanttd_core:placing_terrain")
        open_campaign_player(p)
      end
    end)
  end)
end
core.register_on_leaveplayer(function(p) api.vehicle_ui.leave(p);ui.leave(p:get_player_name());world.leave(p:get_player_name());if api.trackworks_demo then api.trackworks_demo.leave(p:get_player_name()) end;api.save() end)
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
  api.rail_platform_view=dofile(mod.."/rail_platform_view.lua")(api,Run,Pose,interval)
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
    local PBS=dofile(source.."rail_reservation.lua")(Track,Follow,RailCost)
    local Life=dofile(source.."rail_consist_reservation.lua")(Track,Follow,PBS)
    local Signal=dofile(source.."rail_signals.lua")(Track)
    local Consist=dofile(source.."rail_consist_motion.lua")(Track,RailMotion,Follow,Life)
    local dispatch_motion,dispatch_life=Consist,Life
    if api.rail_spans then
      dispatch_motion=dofile(mod.."/rail_span_consist.lua")(Track,RailMotion,Follow,Consist,Life)
      dispatch_life=dofile(mod.."/rail_span_life.lua")(Track,PBS,Life)
    end
    local Dispatch=dofile(mod.."/rail_consist_dispatch.lua")(dispatch_motion,dispatch_life)
    local Reverse=dofile(source.."rail_reverse.lua")(Track,RailMotion,Consist,Life,Signal,Follow,PBS)
    local height,presentation
    local graded=true
    if graded or api.rail_spans then
      if graded then S.rail_grade_enabled=true end
      local H=dofile(source.."rail_height.lua")(Track,api.slope)
      local pixel,profile=H.bind(Lab.board(S),api.terrain.tile)
      if graded then
        height=function(id,x,y)
          local crossing=api.crossings and api.crossings.world.record(S,id)
          return crossing and crossing.top*8 or pixel(id,x,y)
        end
      end
      presentation=function(id,td,f,part)
        local crossing=api.crossings and api.crossings.world.record(S,id)
        if crossing then return crossing.top,0 end
        if api.rail_spans then
          local level,tilt=api.rail_spans.presentation(S,id,td,f,part)
          if level~=nil then return level,tilt end
        end
        local data=profile(id)
        if data then return H.render(data,td,f) end
      end
    end
    local Roster=api.rail_owned_tools and dofile(source.."rail_roster.lua") or nil
    local Block=dofile(source.."rail_block_signals.lua")(Track,Signal)
    local Pilot=dofile(mod.."/rail_dispatch_run.lua")(Track,Follow,RailCost,RailSearch,PBS,dispatch_life,Signal,
      dispatch_motion,Dispatch,RailSpeed,Lab,height,Reverse,api.rail_spans,api.crossings,Roster,Block)
    if Roster then
      local Depot=dofile(mod.."/rail_depot_fleet.lua")(Sim,Lab,Roster)
      api.rail_owned=dofile(mod.."/rail_owned_service.lua")(Depot,Roster,Pilot,Sim.rail_coal_validate,Sim.rail_oil_validate,
        function() return api.rail_oil_tools==true end,Sim.rail_goods_validate,Sim.rail_goods_active)
      Lab.owned_depot_occupied=api.rail_owned.occupies_depot
      S.rail_owned_service=true
      if not S.stock_rail_fleet then
        local seed=math.floor(math.abs(S.seed or 1751))%4294967296
        local start_year=Sim.date(S,0)
        assert(api.rail_owned.initialize(S,{starting_year=start_year,climate="temperate",
          generation_seed=seed,startup_random=(seed*1664525+1013904223)%4294967296}))
      end
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
        if S.tiles[id] and S.tiles[id].rail_type==1 then return nil,"ELECTRIC_CROSSING_NOT_MOUNTED" end
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
    if rail_build_enabled then
      local Height=dofile(source.."rail_height.lua")(Track,api.slope)
      local Q=dofile(source.."rail_construction.lua")(Track,Signal,Height)
      local function value(plan,why)
        if plan then return plan.cost end
        return nil,why
      end
      local prices={
        track=function(tile,p,o)
          if p.remove then return Q.rail_clear_price(0,o) end
          return value(Q.piece(tile,p.track,o))
        end,
        station_area=function(tiles,axis,tracks,length,o) return value(Q.station(tiles,axis,tracks,length,o)) end,
        depot=function(tile,d,o) return value(Q.depot(tile,d,o)) end,
        signal=function(tile,d,oneway,o)
          return value(Q.signal(tile,d%2,{kind=oneway and Signal.PBS_ONEWAY or Signal.PBS},o))
        end,
        signal_track=function(tile,track,kind,o) return value(Q.signal(tile,track,{kind=kind},o)) end,
        clear_signal=function()return Q.base_prices().clear_signal end,
      }
      api.rail_build=dofile(mod.."/rail_construction_tools.lua")(api,Lab,Track,Pilot,prices)
    end
    local bridge_profile=api.rail_bridge_wire_art and api.rail_spans and dofile(mod.."/rail_bridge_wire_profile.lua")(
      Sim,api.rail_spans,api.rail_bridge_wire_art,Track,function(id,mask)
        local slope,height=api.terrain.tile(id)
        local slope_index,level=Lab.surface(slope,height,mask)
        if slope_index==0 then return level end
      end)
    api.rail_dispatch_view=dofile(mod.."/rail_dispatch_view.lua").create(api,Pilot,Track,Pose,
      dofile(mod.."/rail_signal_art.lua"),interval,presentation,bridge_profile,height)
    Pilot.mount_bridge_collectors(api.rail_dispatch_view.split_electric_ready)
    if S.rail_goods_service then
      Sim.mount_rail_goods(S,api.rail_dispatch_view.goods_wagon_ready)
      api.rail_goods_tools=Sim.rail_goods_active(S)
      if api.rail_goods_tools then world.enable_rail_goods() end
    end
    if S.rail_oil_service then
      if not api.rail_dispatch_view.oil_wagon_ready() then
        core.log("warning","Rail Oil paused: missing the stock Oil Tanker assets.")
        S.rail_oil_service=false
      else
        api.rail_oil_tools=Sim.rail_oil_active and Sim.rail_oil_active(S) or false
        if api.rail_oil_tools then world.enable_rail_oil() end
      end
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
