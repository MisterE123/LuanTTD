-- Test-only startup overlay. Select probe by disposable world directory,
-- not by adding any LuanTTD settings to the ordinary launch.
core.after(0,function()
  local key=core.get_worldpath():match("[^/]+$")
  local function report(s) core.log("action","DEFAULT STOCK TERRAIN "..key.." "..s) end
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local F=dofile(mod.."/openttd/water_flood.lua")
  local W=dofile(mod.."/water_flood_world.lua")(Sim,Terrain,F)
  local B=W.board(S)
  local function counts()
    local slopes,peak,water,shore,void=0,0,0,0,0
    for id,t in ipairs(S.tiles) do
      local mask,base,top=api.terrain.tile(id)
      assert(mask and type(base)=="number" and type(top)=="number")
      if not t.stock_void then
        if mask~=0 then slopes=slopes+1 end
        peak=math.max(peak,top)
      end
      if t.stock_void then void=void+1
      elseif t.coastal_water then shore=shore+1
      elseif t.terrain=="water" then water=water+1 end
    end
    return slopes,peak,water,shore,void
  end

  local persisted=storage:get_string("default-terrain-proof")
  if key=="plain" and persisted=="" then
    assert(core.settings:get("bayline_stock_generated_world")==nil
      and core.settings:get("bayline_seed")==nil and core.settings:get("bayline_stock_coastal_flood")==nil)
    local profile=assert(S.stock_generated_profile)
    assert(api.generated_world and S.seed==1751 and Sim.W==64 and Sim.H==64 and #S.corner_grid.levels==65^2
      and not S.qa_coastal and profile.terrain=="terragenesis-14.1" and profile.towns==2)
    assert(api.terrain and api.coastal_flood_tools and S.stock_coastal_flood and api.structure_tools and api.road_bay_tools
      and api.rail_build_tools and api.rail_owned_tools and api.ship_tools and api.airport_tools and api.freight_tools)
    local kinds={}
    for _,ind in ipairs(profile.industries) do kinds[ind.kind]=(kinds[ind.kind] or 0)+1 end
    for _,kind in ipairs({"coal_mine","power_station","forest","sawmill","farm","factory","oil_well","oil_refinery"}) do
      assert(kinds[kind],"Default generation did not place "..kind)
    end
    assert(api.farm_tools and api.oil_tools and api.timber_tools and api.rail_oil_tools)
    for _,engine in ipairs({"grain_truck","livestock_van","oil_tanker","wood_truck","goods_truck","coal_tipper"}) do
      assert(Sim.vehicle_available(S,engine),engine)
    end
    for _,engine in ipairs({"iron_mps","steel_balogh","valuables_balogh"}) do
      assert(Sim.vehicle_available(S,engine),"Stock 1950 lorry missing from the ordinary market: "..engine)
    end
    report("all eight original supported industry types on the same plain map, with ordinary additional stock lorry offers")
    local slopes,peak,water,shore,void=counts()
    assert(slopes>60 and peak>=2 and water>30 and shore>15 and void==252)
    -- Stock generation is initially stable here. Clearing + raising a
    -- real sea-edge corner through the native game command creates a
    -- legitimate graded target, and a *void* tile admits the sea again.
    local hit=Sim.id(2,2)
    assert(S.tiles[hit].terrain=="water" and not S.tiles[hit].coastal_water and S.tiles[Sim.id(2,1)].stock_void)
    local quoted,price,plan=Sim.landscape(S,"Coastal QA","raise",3,3,nil,nil,nil,"footprint")
    assert(not quoted and plan==nil and type(price)=="string") -- footprint quote cannot open a company
    local c=Sim.company(S,"Coastal QA")
    local before=c.cash
    local ok,msg,dirt=Sim.landscape(S,"Coastal QA","raise",3,3)
    assert(ok,msg);assert(#dirt==4 and before-c.cash==40250)
    assert(S.tiles[hit].terrain=="grass" and not S.tiles[hit].coastal_water)
    local will=false
    for _,q in ipairs(F.visit(B,2,1)) do if q.x==2 and q.z==2 and q.kind=="coast" then will=true end end
    assert(will)
    local old=S.passenger_house_clock.counter
    local event
    for day=1,4 do
      Sim.daily(S)
      if S.tiles[hit].coastal_water then event=S.passenger_house_clock.counter;break end
    end
    assert(event and event>old and S.tiles[hit].water_class=="sea" and S.tiles[hit].terrain=="water")
    local cor=core.sha256(string.char(unpack(S.corner_grid.levels)))
    storage:set_string("default-terrain-proof",cor)
    api.save()
    report(("%s %dx%d; %d slope tiles (peak %d), %d sea, %d shore, %d void; real $40250 raise then void-fed coast by tick %d; ordinary workbenches active")
      :format(profile.terrain,Sim.W,Sim.H,slopes,peak,water,shore,void,event))
  elseif key=="plain" then
    assert(core.settings:get("bayline_scenario")=="coastal" and api.generated_world and not S.qa_coastal)
    assert(core.sha256(string.char(unpack(S.corner_grid.levels)))==persisted)
    assert(S.tiles[Sim.id(2,2)].coastal_water and api.coastal_flood_tools)
    assert(api.farm_tools and api.oil_tools and api.timber_tools and api.rail_oil_tools)
    report("saved stock world and new coast retained despite a different scenario setting")
  elseif key=="obsolete" then
    assert(core.settings:get_bool("luanttd_qa_coastal_layout",false) and core.settings:get_bool("luanttd_qa_plain_layout",false) and core.settings:get_bool("bayline_stock_generated_world",true)==false)
    assert(api.generated_world and S.stock_generated_profile.terrain=="terragenesis-14.1" and not S.qa_coastal)
    assert(api.world_origin():match("TerraGenesis"))
    report("test layout flags are ignored without QA support")
  elseif key=="all_on" then
    assert(api.generated_world and S.stock_bus_market and S.road_mail and
      S.road_stock_loading and S.road_junction_clearance and S.stock_town_growth and api.offline_economy)
    for _,field in ipairs({"road_bay_tools","structure_tools","oneway_tools","rail_build_tools","rail_span_tools",
        "rail_owned_tools","rail_owned_pair_tools","rail_block_tools","crossing_tools","electric_tools",
        "ship_tools","ship_coal_tools","tram_tools","airport_tools","freight_tools","rail_coal_tools","rail_goods_tools",
        "farm_tools","oil_tools","rail_oil_tools"}) do
      assert(api[field],"Missing ordinary feature: "..field)
    end
    assert(S.ship_paid_service and S.rail_paid_service and S.air_paid_service and S.air_owned_preview and S.air_fleet_preview)
    for _,name in ipairs({"roads","road_stops","railworks","railsignals","railfreight","rail_oil_freight","harbor","harbor_ops","tramway","airfields"}) do
      assert(api.world.has_menu(name),"Missing ordinary hotbar: "..name)
    end
    report("former opt-outs ignored; core modes, paid services and freight tools mounted without opt-in")
  elseif key=="archipelago" then
    assert(api.generated_world and S.seed==23 and #S.sites>=2)
    local seen,areas={},{}
    for id,t in ipairs(S.tiles) do
      if not seen[id] and t.terrain~="water" then
        local q,k={id},1
        seen[id]=true
        while q[k] do
          local tile=q[k];k=k+1
          for d=1,4 do
            local j=Sim.adjacent(tile,d)
            if j and not seen[j] and S.tiles[j].terrain~="water" then
              seen[j]=true
              q[#q+1]=j
            end
          end
        end
        areas[#areas+1]=#q
      end
    end
    table.sort(areas,function(a,b)return a>b end)
    assert(areas[1]==817 and areas[2]==281 and areas[3]==199)
    report(("TerraGenesis seed 23 / sea High: separate 817, 281 and 199 land-tile islands with real towns"))
  elseif key=="invalid" then
    assert(api.generated_world and not S.qa_coastal)
    report("unrecognized scenario resolves to generated terrain")
  elseif key=="farm" then
    assert(not api.generated_world and not S.qa_coastal and api.farm_tools and api.ship_tools and api.rail_build_tools and api.airport_tools and Sim.W==48)
    report("explicit Farm wins over generated world")
  elseif key=="oil" then
    assert(not api.generated_world and not S.qa_coastal and api.oil_tools and api.rail_oil_tools and api.ship_tools and api.airport_tools and Sim.W==48)
    report("explicit Oil wins over generated world")
  elseif key=="coast" then
    assert(not api.generated_world and not S.qa_coastal and api.coastal_flood_tools and Sim.W==48)
    report("explicit Coastal Landscaping wins over generated world")
  elseif key=="south" then
    assert(not api.generated_world and not S.qa_coastal and S.stock_coal_scenario=="south_coast_1751" and Sim.W==48)
    report("explicit South Coast Coal wins over generated world")
  else error("Bad terrain proof world: "..tostring(key)) end
  core.request_shutdown("Default terrain qualified",false,0)
end)
