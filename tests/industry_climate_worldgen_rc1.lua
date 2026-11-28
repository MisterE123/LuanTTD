-- Entire fresh stock climate industry phase, using real terrain and towns.
local native_path,fixture_dir,selection=...
local p=type(fixture_dir)=="string" and native_path or "mods/luanttd_core/"
local fp=type(fixture_dir)=="string" and fixture_dir or "tests/fixtures/"
local function m(n) return dofile(p..n..".lua") end
local function o(n) return m("openttd/"..n) end
local S,T,Slope=m("sim"),o("terrain"),o("slope")
local TG=o("terragenesis")(Slope)
local Climate,Tree=o("town_climate_landscape_rc1"),o("tree_climate_rc1")
local River=o("river_worldgen")(Slope,o("river_landscape_rc1"),o("river_yapf_rc1"),
  o("tree_lifecycle_temperate")(o("tree_worldgen"),Tree))
local Raster=o("stock_climate_raster_rc1")(Climate,River,Slope)
local Clear=o("terragenesis_clear_rc1")
local G=o("town_growth")
local Catalog=o("town_growth_houses_all_rc1")
local B=o("town_growth_build")(G,o("town_growth_houses"),Catalog)
local World=o("town_worldgen")(G,B)
local Campaign=m("generated_campaign")
local Names=o("stock_town_name")
local Codec=m("packed_campaign")
local floor=math.floor
local roots={}
for _,r in ipairs(Catalog) do
  roots[r[1]]={width=r[6]*r[7]>1 and r[6] or nil,depth=r[7],unique=r[8]}
end
local Live=m("town_growth_runtime")(S,T,G,B,o("town_passengers"),roots)
local function eq(d,a,b)
  assert(#a==#b,d)
  for i=1,#a do assert(a[i]==b[i],("%s field %d: %.0f != %.0f"):format(d,i,a[i],b[i])) end
end
local proper=selection or arg and tonumber(arg[1]) or 0
for i,r in ipairs(dofile(fp.."rc1-climate-town-start.lua")) do
  if proper==0 or i==proper then
    local climate,seed,coverage,w,relief,amount,pre,post,map,towns=unpack(r)
    local Generator={next_random=TG.next_random,describe=Clear.describe}
    function Generator.generate(opts)
      local raw=TG.generate(opts)
      local prepared=Raster.prepare(raw,{desert_coverage=coverage,snow_coverage=coverage})
      local river,stats=River.generate(prepared,TG.next_random,{rc1=true,original=false,terrain=T,
        terrain_type=relief,amount_of_rivers=amount,tree_placer=0,climate_rules=Climate})
      return Clear.generate(river,TG.next_random),stats
    end
    local s=Campaign.landscape(S,T,Generator,{width=w,depth=w,seed=seed,terrain_type=relief,
      quantity_sea_lakes=0,tgen_smoothness=1,water_borders=0,variety=0,freeform_edges=true,
      landscape=climate,rng_state=TG.startup_rng(seed)})
    local profile=s.stock_generated_profile
    eq(climate.." before towns",
      {s.stock_climate.snowline or 10,unpack(profile.terrain_rng)},{pre[4],pre[5],pre[6]})
    s.stock_world_animations=o("world_animation_rc1").new()
    s.stock_pool_authority=true
    local made,why=Campaign.towns(S,T,s,Generator,World,Names,G,B,{layout="original",
      growth_setting=2,difficulty=3,custom_count=1,larger_towns=4,separation=20,
      initial_city_size=2,year=1985},roots)
    assert(made,why)

    local ref=dofile(fp.."rc1-native-climate-generated-industries.lua")[i]
    assert(climate==ref.climate and seed==ref.seed)
    eq("actual industry phase entry",{w,w,profile.initial_land_count,unpack(profile.town_rng)},ref.before)
    local out=m("generated_climate_industry_phase_rc1")(S,T,TG.next_random).generate(s,{town_runtime=Live})
    eq("actual industry phase exit",profile.climate_industry_rng,ref.after)
    assert(#out.selections==#ref.selected and #out.firms==#ref.firms)
    s=assert(Codec.decode(Codec.encode(s)))
    eq("packed industry phase exit",s.stock_generated_profile.climate_industry_rng,ref.after)
    assert(#s.stock_worldgen_climate_firms==#ref.firms)
    local n=0
    for i,g in ipairs(out.selections) do
      eq("choice "..i,{g[1],g[2] and 1 or 0,g[3] and 1 or 0,g[4],g[5]},ref.selected[i])
    end
    for i,g in ipairs(s.stock_worldgen_climate_firms) do
      local want=ref.firms[i]
      eq("firm "..i,{g.id,g.type,g.x+g.z*w,g.width,g.height,g.town-1,s.sites[g.town].population,
        g.selected_layout,g.prod_level,g.counter,g.random_colour,g.random,
        g.before_rng[1],g.before_rng[2],0},{unpack(want,1,15)})
      eq("after tile RNG "..i,g.after_tiles_rng,want[16])
      assert(#g.produced==#want[17] and #g.accepted==#want[18] and #g.cells==#want[19])
      for j,p in ipairs(g.produced) do eq("output",{p.id,p.rate,p.waiting,p.last_production},want[17][j]) end
      for j,p in ipairs(g.accepted) do eq("input",{p.id,p.waiting},want[18][j]) end
      local cells={}
      for _,c in ipairs(g.cells) do
        local x,z=c.x+1,c.z+1
        local id=S.id(x,z)
        assert(s.tiles[id].stock_industry.id==i-1 and not s.tiles[id].house)
        local slope=T.tile(s.corner_grid,x,z)
        cells[#cells+1]={id-1,c.gfx,c.random_bits,c.stage,c.construction_counter,
          T.corner(s.corner_grid,x,z),slope}
      end
      table.sort(cells,function(a,b)return a[1]<b[1] end)
      for j,row in ipairs(cells) do eq("physical cell "..i.."/"..j,row,want[19][j]);n=n+1 end
    end
    print(("PASS automatic RC1 %s generation: %d source-exact placements, %d reopened physical tiles and complete shared RNG"):format(climate,#out.firms,n))
    local pregame=dofile(fp.."rc1-native-climate-industry-settle.lua")[i]
    assert(pregame.climate==climate and pregame.seed==seed)
    local Calendar=o("stock_engine_calendar")
    profile=s.stock_generated_profile
    s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
    s.road_junction_clearance,s.road_bay_build=true,true
    s.stock_pool_authority=true
    s.stock_extra_tree_placement=3
    S.mount_road_bus_market(s,Calendar,1985,false,false)
    S.mount_stock_town_growth(s,Live,true)
    S.mount_coastal_flood(s)
    profile.industry_rng=profile.climate_industry_rng
    Campaign.forests(S,T,s,Generator,o("tree_worldgen"),0)
    S.stock_world_launch(s,Calendar)
    local function cursor()
      return {s.passenger_rating_rng[1],s.passenger_rating_rng[2],s.passenger_house_clock.head}
    end
    eq("pregame entry",cursor(),pregame.start)
    local Machines,Field=m("climate_startup_industry_visits_rc1")(S,T,s)
    local digest,ticks=1,0
    local function roll(v) digest=(65599*digest+v)%2147483647 end
    S.prepare_initial_landscape(s,Live,Field,nil,Machines,function(tick,head)
      assert(tick==ticks);ticks=ticks+1
      roll(tick);roll(s.passenger_rating_rng[1]);roll(s.passenger_rating_rng[2]);roll(head)
    end)
    assert(ticks==1280 and digest==pregame.trace,"Different pregame RNG or landscape cursor")
    eq("pregame exit",cursor(),pregame.finish)
    s=assert(Codec.decode(Codec.encode(s)))
    eq("reopened pregame exit",cursor(),pregame.finish)
    local checked=0
    for _,firm in ipairs(s.stock_worldgen_climate_firms) do
      for _,f in ipairs(firm.cells) do
        local id=S.id(f.x+1,f.z+1)-1
        eq("pregame industry tile "..id,{firm.id,f.gfx,f.stage,f.construction_counter,f.completed and 1 or 0,
          f.animation_frame or 0,f.animation_loop or 0,f.animated and 1 or 0},assert(pregame.cells[id]))
        checked=checked+1
      end
    end
    assert(checked==n)
    print(("PASS active RC1 %s pregame: %d exact landscape ticks and %d reopened industry tiles"):format(climate,ticks,n))

  end
end
