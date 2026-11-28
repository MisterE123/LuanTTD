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
local frozen=dofile(fp.."rc1-native-climate-industry-live-frozen.lua")
local function live_frozen(s,Calendar,climate,w)
  local fixture=assert(frozen[climate])
  local function mount()
    S.mount_road_bus_market(s,Calendar,1985,false,false)
    S.mount_stock_town_growth(s,Live,true)
    S.mount_coastal_flood(s)
    S.mount_frozen_climate_clock(s,T)
  end
  mount()
  local function fold(h,...)
    for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
    return h
  end
  local digest,ticks,maps,reopen=1,0,0,0
  local function check(tick)
    assert(tick==1281+ticks)
    ticks=ticks+1
    local a,b=unpack(s.passenger_rating_rng)
    digest=fold(digest,tick,a,b,s.passenger_house_clock.head)
    local expected=fixture.snapshots[tick]
    if not expected then return end
    local gh,hh,ih=1,1,1
    local physical={}
    local firms=s.stock_worldgen_climate_firms
    for _,f in ipairs(firms) do
      for _,t in ipairs(f.cells) do physical[S.id(t.x+1,t.z+1)]=t end
    end
    for id,c in ipairs(s.tiles) do
      local x,z=S.xy(id)
      local h=c.source_house
      local kind=c.stock_void and 7 or h and 3 or c.terrain=="water" and 6 or c.wood and 4
        or c.stock_industry and 8 or c.build=="road" and 2 or (c.road_bridge_id or c.road_tunnel_id) and 9 or 0
      gh=fold(gh,T.corner(s.corner_grid,x,z),kind)
      if kind==2 then gh=fold(gh,c.road_bits) end
      if h then hh=fold(hh,h.id,h.town-1,h.random_bits,h.stage) end
      if kind==8 then
        local t=assert(physical[id])
        ih=fold(ih,t.gfx,t.stage,t.construction_counter,t.animation_frame or 0,t.animated and 1 or 0)
      end
    end
    local label=climate.." at tick "..tick.." "
    eq(label.."map, house and animated tile states",{gh,hh,ih},expected[1])
    local towns=assert(s.stock_town_growth)
    local th,fh,ph,np=1,1,1,0
    for _,id in ipairs(towns.order) do
      local t=assert(towns.towns[id])
      th=fold(th,t.stock_id or id-1,(t.z-1)*w+t.x-1,t.population,t.num_houses,
        t.grow_counter,t.growth_rate,t.growing and 1 or 0,t.time_until_rebuild)
    end
    for _,f in ipairs(firms) do
      fh=fold(fh,f.id,f.type,f.counter,f.prod_level)
      for _,pr in ipairs(f.produced) do
        np=np+1
        ph=fold(ph,f.id,pr.id,pr.rate,pr.waiting,pr.current_production or 0,pr.last_production)
      end
    end
    eq(label.."town growth",{#towns.order,th},expected[2])
    eq(label.."industry pool",{#firms,fh},expected[3])
    eq(label.."industry production",{np,ph},expected[4])
    maps=maps+1
  end
  for day=1,120 do
    if day==32 or day==95 then
      s=assert(Codec.decode(Codec.encode(s)))
      mount()
      reopen=reopen+1
    end
    S.daily(s,nil,check)
  end
  assert(ticks==8880 and maps==5 and reopen==2)
  eq(climate.." full live RNG and landscape cursor",{digest},{fixture.trace})
  print(("PASS live frozen RC1 %s: %d exact ticks, %d map/town/industry snapshots, %d reopens")
    :format(climate,ticks,maps,reopen))
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
    if frozen[climate] and seed==1751 then live_frozen(s,Calendar,climate,w) end

  end
end
