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
    assert(core.settings:get("bayline_stock_generated_world")==nil and core.settings:get("bayline_harbor_valley")==nil
      and core.settings:get("bayline_seed")==nil and core.settings:get("bayline_stock_coastal_flood")==nil)
    local profile=assert(S.stock_generated_profile)
    assert(api.generated_world and S.seed==1751 and Sim.W==64 and Sim.H==64 and #S.corner_grid.levels==65^2
      and not S.harbor_valley and profile.terrain=="terragenesis-14.1" and profile.towns==2)
    assert(api.terrain and api.coastal_flood_tools and S.stock_coastal_flood and api.structure_tools and api.road_bay_tools
      and api.rail_build_tools and api.rail_owned_tools and api.ship_tools and api.airport_tools and api.freight_tools)
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
    assert(core.settings:get_bool("bayline_harbor_valley",false) and api.generated_world and not S.harbor_valley)
    assert(core.sha256(string.char(unpack(S.corner_grid.levels)))==persisted)
    assert(S.tiles[Sim.id(2,2)].coastal_water and api.coastal_flood_tools)
    report("saved stock world and new coast retained despite explicit Harbor setting")
  elseif key=="harbor" then
    if persisted=="" then
      assert(S.harbor_valley and not api.generated_world and Sim.W==48 and Sim.H==36 and S.stock_coastal_flood)
      local slopes,peak,water,shore=counts()
      local bank0={}
      for i,t in ipairs(S.tiles) do
        local m,b=api.terrain.tile(i)
        if m==0 and b==0 and t.terrain~="water" then bank0[i]=true end
      end
      local old=S.passenger_house_clock.counter
      for _=1,16 do Sim.daily(S) end
      assert(S.passenger_house_clock.counter==old+16*74)
      local _,_,water2,shore2=counts()
      local flooded=0
      for i in pairs(bank0) do if S.tiles[i].terrain=="water" then flooded=flooded+1 end end
      storage:set_string("default-terrain-proof","harbor")
      api.save()
      report(("authored 48x36, exact supported stock coastal clock %d ticks: water %d -> %d; graded shore %d -> %d; formerly dry flat-zero tiles newly wet %d")
        :format(16*74,water,water2,shore,shore2,flooded))
    else
      assert(core.settings:get("bayline_harbor_valley")==nil and S.harbor_valley and not api.generated_world and Sim.W==48)
      assert(api.archived_map and api.world_origin():match("Archived authored map"))
    report("saved authored world kept and explicitly identified as archived")
    end
  elseif key=="obsolete" then
    assert(core.settings:get_bool("bayline_harbor_valley",false)
      and core.settings:get_bool("bayline_stock_generated_world",true)==false)
    assert(api.generated_world and S.stock_generated_profile.terrain=="terragenesis-14.1" and not S.harbor_valley)
    assert(api.world_origin():match("TerraGenesis") and S.sites[1].name~="Port Alder")
    report("obsolete map and feature flags cannot silently select an authored island")
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
    assert(api.generated_world and not api.archived_map and not S.harbor_valley)
    report("unrecognized scenario resolves to generated terrain, not an authored fallback")
  elseif key=="farm" then
    assert(not api.generated_world and not S.harbor_valley and api.farm_tools and Sim.W==48)
    report("explicit Farm wins over generated world")
  elseif key=="oil" then
    assert(not api.generated_world and not S.harbor_valley and api.oil_tools and Sim.W==48)
    report("explicit Oil wins over generated world")
  elseif key=="coast" then
    assert(not api.generated_world and not S.harbor_valley and api.coastal_flood_tools and Sim.W==48)
    report("explicit Coastal Landscaping wins over generated world")
  elseif key=="south" then
    assert(not api.generated_world and not S.harbor_valley and S.stock_coal_scenario=="south_coast_1751" and Sim.W==48)
    report("explicit South Coast Coal wins over generated world")
  elseif key=="lab" then
    assert(not api.generated_world and not api.road_first and not S.harbor_valley and Sim.W==48)
    report("explicit Development Lab wins over generated world")
  else error("Bad terrain proof world: "..tostring(key)) end
  core.request_shutdown("Default terrain qualified",false,0)
end)
