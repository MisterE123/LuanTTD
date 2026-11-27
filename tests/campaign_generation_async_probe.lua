local mod=core.get_modpath(core.get_current_modname())
local Setup=dofile(mod.."/world_setup.lua")
local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
local Codec=dofile(mod.."/packed_campaign.lua")
local heavy_layouts=dofile(mod.."/openttd/iron_steel_data.lua").layout
local prepare=dofile(mod.."/campaign_generation_async.lua")(core,mod)
local prepared=Checkpoints(core,Codec,"luanttd-prepared-campaign.chk")
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local cfg=assert(Setup.parse(Setup.defaults(core.settings),{setup_growth_rate="1"}))
assert(cfg.width==128 and cfg.depth==64 and cfg.rivers==1)
local expected=dofile(mod.."/campaign_generation.lua")(core,mod,dofile(mod.."/sim.lua"),Setup).run(cfg)
local function compare(a,b)
  local left,right={},{}
  local function match(x,y,key)
    assert(type(x)==type(y),key)
    if type(x)~="table" then assert(x==y,key);return end
    if left[x] or right[y] then assert(left[x]==y and right[y]==x,key);return end
    left[x],right[y]=y,x
    for k,v in pairs(x) do match(v,y[k],key.."."..tostring(k)) end
    for k in pairs(y) do assert(x[k]~=nil,key.."."..tostring(k)) end
  end
  match(a,b,"state")
end
local heartbeats,progress_seen=0,0
core.register_globalstep(function() heartbeats=heartbeats+1 end)
core.register_on_mods_loaded(function()
  local last=0
  assert(not prepared.read())
  assert(prepare(cfg,function(pct,stage)
    assert(pct>=last and type(stage)=="string" and #stage<100)
    last=pct
    progress_seen=progress_seen+1
  end,function(ok,why,unexpected_table)
    assert(ok,why)
    assert(not unexpected_table and progress_seen>0 and last==90 and heartbeats>1)
    local actual=assert(prepared.read(),"Worker success without durable result")
    compare(expected,actual)
    assert(actual.stock_generated_profile.town_settings.growth_setting==0)
    local G=dofile(mod.."/openttd/town_growth.lua")
    for _,town in pairs(actual.stock_town_growth.towns) do
      -- None affects live growth, not the existence of founding houses.
      assert(town.num_houses>0 and town.growth_rate==G.normal_rate(town,0,0))
    end
    core.log("action","PASS NATIVE TOWN GROWTH OPTION: None reached the generator and survived the prepared checkpoint")
    local age=dofile(mod.."/openttd/town_rebuild.lua").age
    local complete=0
    for _,tile in ipairs(actual.tiles) do
      local house=tile.house and tile.source_house
      if house and house.completed then
        assert(house.age_epoch==cfg.year and age(house,cfg.year)==0 and age(house,cfg.year+1)==1)
        complete=complete+1
      end
    end
    assert(complete>0,"Opening towns should contain completed buildings")
    core.log("action",("PASS NATIVE TOWN BUILDING AGES: %d completed tiles retained their original year through checkpoint"):format(complete))
    local found,mill_layouts={},{}
    for _,site in ipairs(actual.stock_generated_profile.industries) do
      if site.chain=="heavy" then
        local record=assert(actual.stock_heavy_industries[site.industry])
        local placement=assert(actual.stock_heavy_placements[site.industry])
        local layout=assert(heavy_layouts[site.kind][record.layout])
        local style="industry_"..site.kind..(record.layout==1 and "_l1" or "")
        assert(record.kind==site.kind and placement.layout==record.layout and placement.style==style
          and #placement.cells==#layout and #record.tiles==#layout)
        for i,cell in ipairs(placement.cells) do
          local row,source=layout[i],record.tiles[i]
          assert(cell.offset_x==row[1] and cell.offset_z==row[2] and cell.gfx==row[3])
          assert(source.x==cell.x-1 and source.z==cell.z-1 and source.gfx==cell.gfx)
          local part=assert(actual.tiles[cell.id].stock_industry)
          assert(part.id==record.id and part.style==style and part.gfx==cell.gfx)
        end
        found[site.kind]=(found[site.kind] or 0)+1
        if site.kind=="steel_mill" then mill_layouts[record.layout]=true end
      end
    end
    assert(found.iron_mine and found.steel_mill,("No complete heavy chain in async map: %s mine / %s mill"):format(tostring(found.iron_mine),tostring(found.steel_mill)))
    local layouts={}
    for layout=0,1 do if mill_layouts[layout] then layouts[#layouts+1]=tostring(layout) end end
    core.log("action",("PASS NATIVE TEMPERATE HEAVY WORLDGEN: %d ore mines, %d steel mills (layouts %s), exact source footprints")
      :format(found.iron_mine,found.steel_mill,table.concat(layouts,",")))
    local steps=heartbeats
    -- Obstruct the exact atomic destination, not the source or existing
    -- world. The worker must not report success for lost prepared data.
    prepared.clear()
    local custom=assert(Setup.parse(cfg,{setup_towns="5",setup_custom_towns="3",
      setup_larger_towns="1",setup_initial_city_size="3",setup_town_min_distance="28"}))
    assert(prepare(custom,function() end,function(custom_ok,custom_error)
      assert(custom_ok,custom_error)
      local custom_state=assert(prepared.read())
      local town_opts=custom_state.stock_generated_profile.town_settings
      assert(town_opts.custom_count==3 and town_opts.larger_towns==1 and
        town_opts.initial_city_size==3 and town_opts.separation==28)
      local settlements=custom_state.stock_town_growth.towns
      assert(#custom_state.stock_town_growth.order==3)
      for id,town in pairs(settlements) do
        assert(town.larger_town and town.num_houses>0)
        for other_id,other in pairs(settlements) do
          if other_id~=id then assert(math.abs(town.x-other.x)+math.abs(town.z-other.z)>=28) end
        end
      end
      core.log("action","PASS NATIVE TOWN PLACEMENT OPTIONS: three cities, requested starting size, distances and target persisted")
      prepared.clear()
      assert(core.mkdir(core.get_worldpath().."/luanttd-prepared-campaign.chk"))
      assert(prepare(cfg,function() end,function(saved,err)
        assert(not saved and type(err)=="string" and err:find("Could not commit",1,true),tostring(err))
        assert(not prepared.read())
        core.log("action",("PASS NATIVE GENERATION: exact %d×%d campaign and shared graph; %d server steps during job; blocked checkpoint failed closed; only progress/status across threads")
          :format(cfg.width,cfg.depth,steps))
        core.request_shutdown("Async generation parity passed",false,0)
      end))
    end))
  end))
  assert(not prepare(cfg,function()error("duplicate progress")end,function()error("duplicate reply")end))
end)
