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
local spread=dofile(fp.."rc1-native-climate-industry-live-trees.lua")
local toyland_live=dofile(fp.."rc1-native-climate-industry-live-toyland.lua").toyland
local wooded=dofile(fp.."rc1-native-climate-industry-live-wooded.lua")
local smooth=dofile(fp.."rc1-native-climate-industry-smooth-year.lua")
local smooth_open=dofile(fp.."rc1-native-climate-industry-smooth-opening.lua")
local smooth_close=dofile(fp.."rc1-native-climate-industry-smooth-closure.lua")
local smooth_bus=dofile(fp.."rc1-native-climate-industry-smooth-bus.lua")
local smooth_water=dofile(fp.."rc1-native-climate-industry-smooth-water.lua")
local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local function live_industries(s,Calendar,climate,w,settings,fixture,economy)
  economy=economy or "frozen"
  s.stock_extra_tree_placement=settings
  local industry_clock
  local water=fixture.water~=nil
  local transport=fixture.bus or fixture.water
  local owner="Tropic buses"
  local bus,near,far
  local motion,frames,visits=1,0,0
  local function mount()
    S.mount_road_bus_market(s,Calendar,1985,false,false)
    S.mount_stock_town_growth(s,Live,true)
    S.mount_coastal_flood(s)
    industry_clock=S.mount_climate_industry_clock(s,T,economy)
    if transport then
      if water then assert(S.mount_tropic_freight(s)) end
      S.mount_road_faults(s,o("road_breakdowns"),m("road_faults_runtime"),1,
        {kernel=o("road_depot_service"),interval=150,percent=false})
      s.road_regal_enabled,s.road_mail=true,true
    end
  end
  mount()
  local digest,ticks,maps,reopen,opens,closes=1,0,0,0,0,0
  local new_cells={}
  local function check(tick)
    assert(tick==1281+ticks)
    ticks=ticks+1
    local a,b=unpack(s.passenger_rating_rng)
    digest=fold(digest,tick,a,b,s.passenger_house_clock.head)
    if tick==fixture.opening_tick then
      for _,event in ipairs(fixture.openings) do
        local kind=event.before[1]
        eq("industry opening entry",{kind,unpack(s.passenger_rating_rng)},event.before)
        local firm=assert(industry_clock.open(kind),"Stock live industry site was not found")
        eq("industry opening receipt",{kind,firm.id,firm.x+firm.z*w,firm.width,firm.height,
          firm.town-1,firm.selected_layout,firm.counter,unpack(s.passenger_rating_rng)},event.after)
        local footprint={}
        for _,c in ipairs(firm.cells) do
          local id=S.id(c.x+1,c.z+1)
          assert(s.tiles[id].stock_industry.id==firm.id)
          footprint[#footprint+1]={firm.id,id-1,c.gfx,c.stage,c.construction_counter}
        end
        table.sort(footprint,function(x,y)return x[2]<y[2] end)
        assert(#footprint==#event.cells)
        for n,row in ipairs(footprint) do eq("industry opening tile "..n,row,event.cells[n]) end
        new_cells[firm.id]=footprint
        opens=opens+1
      end
    end
    local mark=fixture.close_mark
    if mark and mark[1]==tick then
      local found=0
      for _,f in ipairs(s.stock_worldgen_climate_firms) do
        if f.id==mark[2] or f.id==mark[3] then f.prod_level=0;found=found+1 end
      end
      assert(found==2)
    end
    if fixture.closures then
      for _,event in ipairs(fixture.closures) do
        local id=event[2]
        if tick==event[1] then
          local in_pool=false
          for _,f in ipairs(s.stock_worldgen_climate_firms) do if id==f.id then in_pool=true;break end end
          assert(in_pool,"Industry removed before the stock monthly boundary")
        elseif tick==event[1]+1 then
          for _,f in ipairs(s.stock_worldgen_climate_firms) do assert(f.id~=id,"Industry still active after monthly close") end
          for _,row in ipairs(assert(new_cells[id])) do assert(not s.tiles[row[2]+1].stock_industry) end
          closes=closes+1
        end
      end
      if tick==fixture.closures[1][1]+1 then
        local n,h,unowned=0,1,0
        for id=1,w*w do
          local f=s.stock_farm_fields[id]
          if f then
            n=n+1
            h=fold(h,id-1,f.industry or 65535)
            if f.industry==nil then unowned=unowned+1 end
          end
        end
        eq("native field ownership after farm closure",{n,h,unowned},fixture.farmland)
      end
    end
    if transport and tick==transport.tick then
      local function cell(x,z) return S.id(x+1,z+1) end
      local co=assert(S.open_company(s,owner))
      co.cash=80000000
      local function apply(quote,why)
        assert(quote,why)
        assert(S.apply_road_construction(s,owner,quote))
      end
      if water then
        for _,leg in ipairs({{55,30,55,52,1,6380},{55,52,66,52,0,2730},{66,52,66,62,1,1515}}) do
          local q,why=S.autoroad_plan(s,owner,cell(leg[1],leg[2]),cell(leg[3],leg[4]),leg[5],false,true)
          assert(q and not q.stopped_at,why or q and q.stop_reason)
          eq("stock road drag cost",{q.cost},{leg[6]})
          apply(q)
        end
      end
      local depot=water and cell(55,29) or cell(49,37)
      local direction=water and 1 or 0
      apply(S.stock_road_terminal_plan(s,owner,depot,{kind="depot",dir=direction}))
      local function stop(x,z)
        local id=cell(x,z)
        apply(S.stock_road_stop_area_plan(s,owner,id,id,{kind=water and "truck" or "bus",
          dir=direction,through=true,adjacent=true}))
        return assert(s.tiles[id].station)
      end
      if water then near,far=stop(55,32),stop(66,61) else near,far=stop(47,37),stop(43,37) end
      bus=assert(S.purchase(s,owner,water and "water_uhl" or "leopard_bus",water and "water" or "passenger",nil,depot))
      assert(S.add_order(s,owner,bus,water and near or far) and S.add_order(s,owner,bus,water and far or near))
      assert(S.toggle(s,owner,bus))
      eq("after depot, stops, purchased vehicle and orders",s.passenger_rating_rng,transport.rng)
    elseif bus then
      local v=assert(s.fleet[bus])
      local frame=S.road_motion_frame(s,v)
      local c=assert(v.road_speed_state or v.road_stop_motion)
      if frame then
        motion=fold(motion,tick,frame[4]-1,frame[1]-16,frame[2]-16,S.stock_road_frame_z(s,frame),frame[3],c.progress,
          v.road_speed_state and c.speed or 0,c.subspeed,v.units)
        if water then motion=fold(motion,0) end
      else
        assert(water and c.transit_hidden,"Unexpected missing vehicle frame")
        motion=fold(motion,tick,v.home_depot-1,-1,-1,-1,-1,c.progress,c.speed,c.subspeed,v.units,1)
      end
      frames=frames+1
      local receipt=transport.service[tick]
      if receipt then
        local function waiting(st)
          local n=0
          local queue=water and (st.stock_climate_freight or {}).water or (st.stock or {}).passenger
          for _,p in ipairs(queue or {}) do n=n+p.units end
          return n
        end
        local function rating(st)
          if water then return st.goods and st.goods.water and st.goods.water.rating or o("station_rating").initial end
          return st.passenger_rating_state.rating
        end
        local a,b=assert(s.stations[near]),assert(s.stations[far])
        local town_id=water and 9 or 1
        local town=assert(s.stock_town_growth.towns[town_id])
        local co=s.companies[owner]
        local delivered=co.paid_units+(v.load_state and v.load_state.payment and v.load_state.payment.delivered or 0)
        local facts={waiting(a),town_id-1,town.population,town.growing and 1 or 0,co.cash,delivered,rating(a),waiting(b),rating(b)}
        if water then
          local history=town.received[4] or {}
          facts[#facts+1]=history.new_act or 0
          facts[#facts+1]=history.old_act or 0
        end
        eq("player route service at "..tick,facts,receipt)
        visits=visits+1
      end
    end
    local expected=fixture.snapshots[tick]
    if not expected then return end
    local gh,hh,ih,wood,trees=1,1,1,1,0
    local physical={}
    local firms=s.stock_worldgen_climate_firms
    for _,f in ipairs(firms) do
      for _,t in ipairs(f.cells) do physical[S.id(t.x+1,t.z+1)]=t end
    end
    for id,c in ipairs(s.tiles) do
      local x,z=S.xy(id)
      local h=c.source_house
      local kind=c.stock_void and 7 or h and 3 or c.wood and 4 or c.terrain=="water" and 6
        or c.stock_industry and 8 or (transport and c.station) and 5
        or (c.build=="road" or transport and c.build=="road_depot") and 2
        or (c.road_bridge_id or c.road_tunnel_id) and 9 or 0
      gh=fold(gh,T.corner(s.corner_grid,x,z),kind)
      if kind==2 and c.build=="road" then gh=fold(gh,c.road_bits) end
      if h then hh=fold(hh,h.id,h.town-1,h.random_bits,h.stage) end
      if kind==4 then
        local t=c.wood
        wood=fold(wood,id-1,t.type,t.count,t.growth,t.ground,t.density)
        trees=trees+1
      end
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
    if expected[5] then eq(label.."tree species/age and surface state",{trees,wood},expected[5]) end
    if expected[6] then
      local bubbles=assert(s.stock_climate_bubbles)
      local order,bh={},1
      for id in pairs(bubbles) do order[#order+1]=id end
      table.sort(order)
      for _,id in ipairs(order) do
        local b=bubbles[id]
        bh=fold(bh,id,b.x,b.y,b.z,b.progress,b.movement,b.animation_state,b.direction,b.frame)
      end
      eq(label.."bubble vehicle pool and motion",{#order,bh},expected[6])
    end
    if expected.market then
      local market=assert(s.stock_climate_market)
      eq(label.."daily market clock",{math.floor(w*w/31),market.daily_counter,#firms},expected.market)
    end
    maps=maps+1
  end
  local days=fixture.days or 120
  for day=1,days do
    if day==32 or day==95 or day==250 then
      s=assert(Codec.decode(Codec.encode(s)))
      mount()
      reopen=reopen+1
    end
    S.daily(s,nil,check)
  end
  assert(ticks==days*74 and maps==(days==120 and 5 or 8) and reopen==(days==120 and 2 or 3))
  eq(climate.." full live RNG and landscape cursor",{digest},{fixture.trace})
  if fixture.openings then assert(opens==#fixture.openings) end
  if fixture.closures then assert(closes==#fixture.closures) end
  if transport then
    eq("Stock motion and loading on the generated map",{frames,motion,visits},
      {transport.frames,transport.motion,10})
    print(("PASS generated RC1 Tropic %s: %d service frames and %d payment/catchment checks")
      :format(water and "water tanker" or "bus",frames,visits))
  end
  print(("PASS live %s RC1 %s (tree setting %d): %d exact ticks, %d snapshots, %d reopens, %d test openings, %d test closures")
    :format(economy,climate,settings,ticks,maps,reopen,opens,closes))
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
    local woods=(i<=3) and wooded[climate]
    local industry_snapshot=woods and Codec.encode(s)
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
    if frozen[climate] and seed==1751 then
      local fresh=Codec.encode(s)
      live_industries(s,Calendar,climate,w,3,assert(frozen[climate]))
      live_industries(assert(Codec.decode(fresh)),Calendar,climate,w,2,assert(spread[climate]))
    elseif climate=="toyland" and seed==49832 then
      live_industries(s,Calendar,climate,w,2,toyland_live)
    end
    if woods then
      s=assert(Codec.decode(industry_snapshot))
      profile=s.stock_generated_profile
      s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
      s.road_junction_clearance,s.road_bay_build=true,true
      s.stock_extra_tree_placement=2
      S.mount_road_bus_market(s,Calendar,1985,false,false)
      S.mount_stock_town_growth(s,Live,true)
      S.mount_coastal_flood(s)
      profile.industry_rng=profile.climate_industry_rng
      eq("before forest",{profile.industry_rng[1],profile.industry_rng[2],profile.map_height_limit},woods.before)
      local result=Campaign.forests(S,T,s,Generator,o("tree_worldgen"),2)
      eq("after forest",result.rng_after,woods.after)
      local size,stamp=0,1
      for id,tile in ipairs(s.tiles) do
        local wood=tile.wood
        if wood then
          size=size+1
          stamp=fold(stamp,id-1,wood.type,wood.count,wood.growth,wood.ground,wood.density)
        end
      end
      eq("complete initial forest",{size,stamp},woods.forest)
      S.stock_world_launch(s,Calendar)
      local runtime,board=m("climate_startup_industry_visits_rc1")(S,T,s)
      local ticks,digest=0,1
      S.prepare_initial_landscape(s,Live,board,nil,runtime,function(tick,head)
        assert(tick==ticks)
        ticks=ticks+1
        digest=fold(digest,tick,s.passenger_rating_rng[1],s.passenger_rating_rng[2],head)
      end)
      eq("wooded pregame RNG and cursor",{ticks,digest},{1280,woods.pregame})
      s=assert(Codec.decode(Codec.encode(s)))
      print(("PASS wooded RC1 %s: %d initial trees and %d native pregame ticks"):format(climate,size,ticks))
      local smooth_start=climate=="tropic" and Codec.encode(s)
      live_industries(s,Calendar,climate,w,2,woods)
      if smooth_start then
        live_industries(assert(Codec.decode(smooth_start)),Calendar,climate,w,2,smooth,"smooth")
        live_industries(assert(Codec.decode(smooth_start)),Calendar,climate,w,2,smooth_open,"smooth")
        live_industries(assert(Codec.decode(smooth_start)),Calendar,climate,w,2,smooth_close,"smooth")
        live_industries(assert(Codec.decode(smooth_start)),Calendar,climate,w,2,smooth_bus,"smooth")
        live_industries(assert(Codec.decode(smooth_start)),Calendar,climate,w,2,smooth_water,"smooth")
      end
    end

  end
end
