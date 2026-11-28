-- Headless worker parity, never a world-selector entry or asset fallback.
local p="mods/luanttd_core/"
local function m(n)return dofile(p..n..".lua") end
local function o(n)return m("openttd/"..n) end
local S,T,Sl=m("sim"),o("terrain"),o("slope")
local Floor=math.floor
local TG=o("terragenesis")(Sl)
local Climate,Tree=o("town_climate_landscape_rc1"),o("tree_climate_rc1")
local River=o("river_worldgen")(Sl,o("river_landscape_rc1"),o("river_yapf_rc1"),
  o("tree_lifecycle_temperate")(o("tree_worldgen"),Tree))
local Raster=o("stock_climate_raster_rc1")(Climate,River,Sl)
local Clear,Calendar=o("terragenesis_clear_rc1"),o("stock_engine_calendar")
local G,Roots=o("town_growth"),o("town_growth_houses_all_rc1")
local B=o("town_growth_build")(G,o("town_growth_houses"),Roots)
local World=o("town_worldgen")(G,B)
local Campaign=m("generated_campaign")
local Names=o("stock_town_name")
local shapes={}
for _,r in ipairs(Roots) do shapes[r[1]]={width=r[6]*r[7]>1 and r[6] or nil,depth=r[7],unique=r[8]} end
local growth=m("town_growth_runtime")(S,T,G,B,o("town_passengers"),shapes)
local Mount=m("campaign_authority_runtime")
local cases=dofile("tests/fixtures/rc1-climate-live-year.lua")
local Codec=m("packed_campaign")
local function fold(h,v) return (h*65599+v)%2147483647 end
local function equal(label,tick,a,b)
  assert(#a==#b)
  for i=1,#a do
    assert(a[i]==b[i],("%s tick %d field %d: %s != %s"):format(label,tick,i,tostring(a[i]),tostring(b[i])))
  end
end
for _,r in ipairs(cases) do
  local climate,seed,coverage,w,relief,amount,digest,snapshots=unpack(r)
  local Map={next_random=TG.next_random,describe=Clear.describe}
  function Map.generate(opts)
    local raw=TG.generate(opts)
    local raster=Raster.prepare(raw,{desert_coverage=coverage,snow_coverage=coverage})
    local river,stats=River.generate(raster,TG.next_random,{terrain=T,rc1=true,original=false,
      terrain_type=relief,tree_placer=0,amount_of_rivers=amount,climate_rules=Climate})
    return Clear.generate(river,TG.next_random),stats
  end
  local s=Campaign.landscape(S,T,Map,{width=w,depth=w,seed=seed,terrain_type=relief,
    quantity_sea_lakes=0,tgen_smoothness=1,water_borders=0,variety=0,freeform_edges=true,
    landscape=climate,rng_state=TG.startup_rng(seed)})
  s.stock_world_animations=o("world_animation_rc1").new()
  s.stock_pool_authority=true
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.road_junction_clearance,s.road_bay_build,s.road_regal_enabled,s.road_mail=true,true,true,true
  s.stock_extra_tree_placement=3
  S.mount_road_bus_market(s,Calendar,1985,false,false)
  S.mount_coastal_flood(s)
  assert(Campaign.towns(S,T,s,Map,World,Names,G,B,{layout="original",growth_setting=2,
    cargo_mode=1,difficulty=3,custom_count=1,larger_towns=4,separation=20,initial_city_size=2,year=1985},shapes))
  local Farm,error_,farm_rules=S.mount_farm_world(s,T,true)
  assert(Farm,error_)
  local Oil,msg=S.mount_oil_world(s,T,true);assert(Oil,msg)
  local P,Rating=o("passengers"),o("station_rating")
  local Cat=o("station_catchment")(P,Rating,function()return 0 end,function()return 0 end)
  local Coal=o("coal_industry")(P,Rating,Cat,o("income"))
  local Timber=S.timber_rules()
  local Industry=o("industry_worldgen")(Coal,Timber,S.oil_rules(),farm_rules,false,{})
  Campaign.industries(S,T,s,Map,Industry,m("coal_industry_world")(S,T,Coal),0,nil,
    m("timber_world")(S,T,Timber),Oil,Farm)
  Campaign.forests(S,T,s,Map,o("tree_worldgen"),0)
  S.mount_stock_town_growth(s,growth,true)
  S.stock_world_launch(s,Calendar)
  S.prepare_initial_landscape(s,growth,Farm)
  local cap={road={start_year=1985,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
  local function mount()
    local owner=Mount(S,p:sub(1,-2),s,cap)
    S.mount_stock_town_growth(s,growth,true)
    s.stock_economy_subsidies.duration=0
    return owner
  end
  local owner=mount()

  local combined,seen,maps,reopens=1,0,0,0
  local function check(tick)
    local a,b=unpack(s.passenger_rating_rng)
    assert(tick==1281+seen)
    seen=seen+1
    combined=fold(fold(fold(fold(combined,tick),a),b),s.passenger_house_clock.head)
    local snap=snapshots[tick]
    if not snap then return end
    local gh,hh=1,1
    for id,cell in ipairs(s.tiles) do
      local x,z=S.xy(id)
      local h=cell.source_house
      local kind=cell.stock_void and 7 or h and 3 or cell.terrain=="water" and 6 or cell.wood and 4
        or cell.build=="road" and 2 or (cell.road_bridge_id or cell.road_tunnel_id) and 9 or 0
      gh=fold(fold(gh,T.corner(s.corner_grid,x,z)),kind)
      if kind==2 then gh=fold(gh,cell.road_bits) end
      if h then hh=fold(fold(fold(fold(hh,h.id),h.town-1),h.random_bits),h.stage) end
    end

    equal(climate.." map",tick,{gh,hh},snap.map)
    local towns=s.stock_town_growth
    assert(#towns.order==#snap)
    for i,id in ipairs(towns.order) do
      local t=towns.towns[id]
      equal(climate.." town "..i,tick,{t.stock_id or id-1,(t.z-1)*w+t.x-1,t.population,t.num_houses,
        t.grow_counter,t.growth_rate,t.growing and 1 or 0,t.time_until_rebuild},snap[i])
    end
    maps=maps+1
  end
  for day=1,365 do
    if day==32 or day==189 or day==290 then
      s=assert(Codec.decode(Codec.encode(s)))
      owner=mount()
      reopens=reopens+1
    end
    owner.day(check)
  end
  assert(seen==27010 and combined==digest and maps==6 and reopens==3,climate.." live year")
  print(("PASS RC1 %s live year: %d matching RNG and cursor ticks, %d maps and %d reopens"):
    format(climate,seen,maps,reopens))
end
