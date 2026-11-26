-- The same deterministic campaign pipeline for interactive setup and
-- dedicated server startup. Progress callbacks never consume RNG.
return function(core,mod,Sim,Settings)
  local src=mod.."/openttd/"
  local Campaign=dofile(mod.."/generated_campaign.lua")
  local Terrain=dofile(src.."terrain.lua")
  local TG=dofile(src.."terragenesis.lua")(dofile(src.."slope.lua"))
  local Clear=dofile(src.."terragenesis_clear_rc1.lua")
  local Rivers=dofile(src.."river_worldgen.lua")(dofile(src.."slope.lua"))
  local Calendar=dofile(src.."stock_engine_calendar.lua")
  local G=dofile(src.."town_growth.lua")
  local B=dofile(src.."town_growth_build.lua")(G,dofile(src.."town_growth_houses.lua"))
  local C={}
  function C.run(cfg,progress)
    progress=progress or function() end
    local settings=core.settings
    local function option(key,setting,fallback)
      return cfg and cfg[key] or tonumber(settings:get(setting)) or fallback
    end
    local width,depth=Settings.dimensions(settings,cfg)
    local seed=option("seed","bayline_seed",1751)
    local Gen={next_random=TG.next_random,describe=Clear.describe}
    function Gen.generate(opts)
      progress(5,"Shaping the landscape")
      opts.progress=function(f,stage) progress(5+math.floor(30*f),stage,true) end
      local m=TG.generate(opts)
      progress(36,"Carving rivers and shorelines")
      local river,stats=Rivers.generate(m,TG.next_random,{original=false,terrain=Terrain,
        amount_of_rivers=opts.amount_of_rivers,min_river_length=opts.min_river_length,
        progress=function(i,n)
          progress(36+math.floor(11*i/math.max(1,n)),"Carving rivers and shorelines",true)
        end})
      progress(48,"Preparing the ground")
      return Clear.generate(river,TG.next_random,function() progress(48,"Preparing the ground",true) end),stats
    end
    local S=Campaign.landscape(Sim,Terrain,Gen,{
      width=width,depth=depth,seed=seed,rng_state=TG.startup_rng(seed),
      terrain_type=option("relief","bayline_generated_relief",1),
      quantity_sea_lakes=option("sea","bayline_generated_sea",0),
      amount_of_rivers=option("rivers","bayline_generated_rivers",2),
      min_river_length=tonumber(settings:get("bayline_generated_min_river_length")) or 16,
      tgen_smoothness=option("smooth","bayline_generated_smoothness",1),
      water_borders=option("coast","bayline_generated_coasts",15),
      variety=option("variety","bayline_generated_variety",0),freeform_edges=true,
      corner_progress=function(f) progress(49+math.floor(3*f),"Building the shared-corner grid",true) end,
      host_progress=function(f) progress(52+math.floor(9*f),"Preparing playable tiles",true) end,
    })
    S.road_stock_loading,S.road_stock_clock,S.road_stock_house_supply,S.road_economy=true,true,true,true
    S.road_junction_clearance,S.road_bay_build,S.road_regal_enabled,S.road_mail=true,true,true,true
    Sim.mount_road_bus_market(S,Calendar,option("year","bayline_stock_bus_start_year",1950),false,false)
    Sim.mount_coastal_flood(S)
    progress(62,"Building towns and roads")
    local towns,why=Campaign.towns(Sim,Terrain,S,Gen,dofile(src.."town_worldgen.lua")(G,B),
      dofile(src.."stock_town_name.lua"),G,B,{
      layout=cfg and cfg.layout or settings:get("bayline_generated_town_layout") or "original",
      difficulty=option("towns","bayline_generated_towns",2),larger_towns=4,initial_city_size=2,year=Sim.date(S),
      progress=function(i,n) progress(62+math.floor(9*i/math.max(1,n)),"Building towns and roads",true) end,
    })
    assert(towns,why)
    Sim.mount_stock_town_growth(S,dofile(mod.."/town_growth_runtime.lua")(Sim,Terrain,G,B,dofile(src.."town_passengers.lua")),true)
    progress(72,"Placing industries")
    local Farm,error_,farm_rules=Sim.mount_farm_world(S,Terrain,true)
    assert(Farm,error_)
    local Oil,msg=Sim.mount_oil_world(S,Terrain,true)
    assert(Oil,msg)
    local P,Rating=dofile(src.."passengers.lua"),dofile(src.."station_rating.lua")
    local Cat=dofile(src.."station_catchment.lua")(P,Rating,function()return 0 end,function()return 0 end)
    local Coal=dofile(src.."coal_industry.lua")(P,Rating,Cat,dofile(src.."income.lua"))
    local Timber=Sim.timber_rules()
    local heavy=Sim.mount_heavy_world(S,Terrain)
    local ready=heavy and dofile(mod.."/iron_steel_visual_assets.lua").ready(core,mod,heavy)
    local industry_layouts=dofile(mod.."/industry_layout_art.lua").available(core,mod)
    local Industry=dofile(src.."industry_worldgen.lua")(Coal,Timber,Sim.oil_rules(),farm_rules,ready,industry_layouts)
    Campaign.industries(Sim,Terrain,S,Gen,Industry,dofile(mod.."/coal_industry_world.lua")(Sim,Terrain,Coal),
      option("industries","bayline_generated_industries",4),tonumber(settings:get("bayline_generated_industry_count")),
      dofile(mod.."/timber_world.lua")(Sim,Terrain,Timber),Oil,Farm,
      function(i,n) progress(72+math.floor(6*i/math.max(1,n)),"Placing industries",true) end,ready and heavy or nil)
    progress(79,"Adding landmarks and forests")
    Campaign.landmarks(Sim,Terrain,S,Gen,dofile(src.."scenery_object_rc1.lua")(Clear,Calendar),Calendar.date(Sim.date(S)))
    Campaign.forests(Sim,Terrain,S,Gen,dofile(src.."tree_worldgen.lua"),option("trees","bayline_generated_tree_placer",2),
      function() progress(79,"Adding landmarks and forests",true) end)
    return S
  end
  return C
end
