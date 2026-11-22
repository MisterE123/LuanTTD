-- Test-only fixture appended on a disposable copy of the real game entry.
local function digest(skip_house)
  local a={}
  for i,t in ipairs(S.tiles) do
    local h=t.source_house
    a[i]=table.concat({t.h,t.terrain,t.stock_void and 1 or 0,t.coastal_water and 1 or 0,t.stock_clear_ground or 0,
      t.road_town or 0,t.road_bits or 0,not skip_house and h and h.id or 0,
      t.wood and t.wood.type or "-",t.wood and t.wood.count or 0,t.wood and t.wood.growth or 0,
      t.wood and t.wood.ground or 0,t.wood and t.wood.density or 0,
      t.stock_industry and t.stock_industry.id or 0,t.stock_industry and t.stock_industry.gfx or 0,
      t.stock_landmark and t.stock_landmark.kind or "-",t.stock_landmark and t.stock_landmark.random_bits or 0,
      t.stock_landmark and t.stock_landmark.colour or 0},",")
  end
  return core.sha256(table.concat(a,";"))
end
core.after(0,function()
  local profile=assert(S.stock_generated_profile)
  assert(api.generated_world and Sim.W==64 and Sim.H==64 and #S.tiles==4096)
  local mixed=not core.settings:get_bool("bayline_native_generation_coal_only",false)
  assert(not S.qa_coastal and #S.sites==(mixed and 6 or 5) and profile.towns==2)
  assert(not not profile.timber_generation==mixed and not not api.timber_tools==mixed)
  assert(Sim.road_coal_active(S) and api.stock_coal_scenery and api.freight_tools)
  assert(api.rail_coal_tools and (not not api.rail_goods_tools)==mixed)
  assert(api.coastal_flood_tools and api.structure_tools and api.rail_spans and api.crossing_tools and
    api.rail_owned_tools and api.rail_owned_pair_tools and api.electric_tools and api.oneway_tools and
    api.tram_tools and api.ship_tools and S.ship_paid_service and api.airport_tools and S.air_fleet_preview and
    S.air_paid_service and S.road_mail and api.road_bay_tools)
  assert(profile.industry_stats.target==4 and profile.industry_stats.shortfall==(mixed and 0 or 1)
    and profile.industry_stats.attempted==(mixed and 378 or 2479))
  assert(profile.industry_rng[1]==(mixed and 2133080791 or 1181048288) and
    profile.industry_rng[2]==(mixed and 2325212883 or 2079376494))
  local expected=mixed and {{47,41,6,"coal_mine",2},{30,28,8,"power_station",2},{23,42,8,"sawmill",1},
     {48,44,18,"forest",2}} or {{47,41,6,"coal_mine",2},{30,28,8,"power_station",2},{24,43,6,"coal_mine",1}}
  for i,e in ipairs(expected) do
    local item=assert(profile.industries[i])
    local registry=item.chain=="timber" and S.stock_timber_industries or S.stock_coal_industries
    local q=assert(registry[item.industry])
    assert(q.x+1==e[1] and q.z+1==e[2] and #q.tiles==e[3] and q.kind==e[4] and q.town==e[5] and q.layout==0)
    assert(S.sites[q.site].stock_industry==q.id and item.site==q.site)
    for _,tile in ipairs(q.tiles) do
      local mounted=S.tiles[Sim.id(tile.x+1,tile.z+1)].stock_industry
      assert(mounted.id==q.id and mounted.gfx==tile.gfx and tile.stage==2 and tile.construction_counter==3
        and not tile.completed and type(tile.random_bits)=="number")
    end
  end
  local phase=core.settings:get("bayline_native_generation_phase")
  local towns={}
  local streets,houses,relief=0,0,0
  local forest,stems,shore,eligible=0,0,0,nil
  local landmarks={lighthouse=0,transmitter=0}
  for i,t in ipairs(S.tiles) do
    if t.stock_clear_ground then relief=relief+1 end
    if t.road_town then assert(t.road_bits>0 and S.sites[t.road_town]);streets=streets+1 end
    if t.source_house then
      local home=t.source_house
      assert(S.sites[home.town] and home.town_growth and home.root)
      houses=houses+1
    end
    if t.stock_landmark then
      local q=t.stock_landmark
      assert(q.class==10 and api.terrain.tile(i)==0 and q.town>0 and S.sites[q.town].kind=="town")
      assert(not t.wood and not t.road_town and not t.stock_industry and t.terrain~="water")
      assert(not Sim.plan(S,"plant-test","clear",{i}) and not Sim.plan(S,"plant-test","road",{i}))
      local x,z=Sim.xy(i)
      assert(not Sim.landscape(S,"plant-test","raise",x,z))
      assert(not api.trackworks.piece_plan(S,"plant-test",i,0,false,0))
      landmarks[q.kind]=landmarks[q.kind]+1
    end
    if t.wood then
      local record=t.wood
      assert(record.class==4 and record.type>=0 and record.type<=11 and record.count>=1 and record.count<=4
        and record.growth>=0 and record.growth<=6 and record.density==3)
      assert(not t.road_town and not t.house and not t.stock_void and not t.stock_industry)
      forest,stems=forest+1,stems+record.count
      if record.ground==3 then
        assert(t.terrain=="water" and t.coastal_water and record.water_class=="sea")
        shore=shore+1
      elseif api.terrain.tile(i)==0 then
        eligible=eligible or i
      end
    end
  end
  local Names=dofile(mod.."/openttd/stock_town_name.lua")
  for _,town in ipairs(S.sites) do
    if town.kind=="town" then
      assert(town.name==Names.display(town.nameparts) and town.population>0)
      assert(S.stock_town_growth.towns[town.id].population==town.population)
      towns[#towns+1]=town.name..":"..town.population
    end
  end
  assert(streets>20 and houses>10 and relief>0)
  local stats=assert(profile.forest_stats)
  assert(profile.object_rng and profile.object_stats)
  assert(landmarks.lighthouse==profile.object_stats.placed.lighthouse and
    landmarks.transmitter==profile.object_stats.placed.transmitter)
  assert(stats.tree_placer==2 and stats.shore_tiles==shore and forest>100)
  if phase=="save" then
    assert(forest==stats.tiles and stems==stats.total_trees and shore>0)
    local target=assert(eligible)
    local company=Sim.company(S,"plant-test")
    local before=company.cash
    assert(Sim.build(S,"plant-test","clear",{target}))
    assert(not S.tiles[target].wood and company.cash<before)
    S.stock_generation_forest_clear={id=target,price=before-company.cash}
    S.stock_generation_qa={geometry=digest(false),towns=table.concat(towns,"|")}
    api.save()
  else
    local check=assert(S.stock_generation_qa)
    assert(check.geometry==digest(false))
    assert(check.towns==table.concat(towns,"|"))
    local clear=S.stock_generation_forest_clear
    assert(clear and clear.price>0 and not S.tiles[clear.id].wood and forest==stats.tiles-1)
  end
  core.log("action",("STOCK GENERATED NATIVE %s %s, streets=%d houses=%d rough/rocks=%d forest=%d stems=%d shore=%d industry=%d lighthouse=%d transmitter=%d")
    :format(phase,table.concat(towns," / "),streets,houses,relief,forest,stems,shore,#profile.industries,
      landmarks.lighthouse,landmarks.transmitter))
  core.request_shutdown("Generated world verification complete",false,0)
end)
