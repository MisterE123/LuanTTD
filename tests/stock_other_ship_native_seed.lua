-- Disposable fixture only. Create real source oil industries beside a
-- controlled coastline, then let the normal boot reopen the checkpoint.
return function(core,Sim,checkpoint,mod)
  if not checkpoint or checkpoint.read() then return end
  local T=dofile(mod.."/openttd/terrain.lua")
  local s=Sim.new(1751)
  s.stock_generated_profile={version=1,width=64,depth=64,terrain="native stock ship contract"}
  local cargo=core.settings:get("luanttd_qa_other_ship_cargo")
  local heavy=cargo=="iron_ore" or cargo=="steel"
  local bank=cargo=="valuables"
  local coast=(heavy or bank) and 20 or 33
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function(_,z) return z<coast and 1 or 0 end)
  for z=1,64 do for x=1,64 do
    s.tiles[Sim.id(x,z)]={h=z<coast and 1 or 0,variant=1,terrain=z<coast and "grass" or "water",
      water_class=z>=coast and "sea" or nil}
  end end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.ship_paid_service=true
  local stock=tonumber(core.settings:get("luanttd_qa_other_ship")) or 212
  local cal=dofile(mod.."/openttd/stock_engine_calendar.lua")
  local year=tonumber(core.settings:get("bayline_stock_bus_start_year")) or 1950
  if heavy then
    Sim.mount_road_bus_market(s,cal,year,true,true,{iron_mps=true})
    local Q=dofile(mod.."/qa_dry_heavy_fixture.lua")
    Q.place(Sim,T,s)
    if cargo=="steel" then s.qa_ore_supplier=Q.supply(Sim,s) end
    s.speed=4
  elseif bank then
    s.ship_coal_service=true
    local Q=dofile(mod.."/qa_dry_bank_fixture.lua")
    Q.houses(Sim,s,dofile(mod.."/openttd/town_growth.lua"))
    local cap={temperate_bank=true,oil_tanker=true,
      road={start_year=year,foster=true,breakdowns=0,service_interval=0},ferry={[211]=true},air={}}
    local R=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,cap)
    Q.fund(Sim,s,dofile(mod.."/campaign_authority_endpoint.lua")(Sim,R))
    s.speed=4
  elseif cargo=="grain" or cargo=="livestock" then
    s.ship_coal_service,s.road_farm,s.stock_farm_frozen=true,true,true
    local W,rng=Sim.mount_farm_world(s,T,true)
    assert(W.seed(s,Sim.id(10,25),Sim.id(32,27),rng))
    s.speed=4
  elseif cargo=="wood" then
    s.ship_coal_service,s.road_timber=true,true
    local W=dofile(mod.."/timber_world.lua")(Sim,T,Sim.timber_rules())
    for name,p in pairs(W.facilities) do Sim.facilities[name]=p end
    assert(W.seed(s,Sim.id(10,25),Sim.id(32,27)))
    s.speed=4
  elseif cargo=="goods" then
    s.ship_coal_service,s.road_oil=true,true
    local W=assert(Sim.mount_oil_world(s,T,true))
    assert(W.place(s,assert(W.plan(s,12,28,31,28))))
    local tc=Sim.id(51,28)
    s.sites[1]={id=1,kind="town",name="Port Town",population=400,tile=tc,stock={},produced={},received={},service=0}
    s.tiles[tc].house,s.tiles[tc].source_house=true,{id=18,town=1,completed=true}
    s.speed=4
  elseif stock==208 then
    for i,x in ipairs({12,31}) do
      local id=Sim.id(x,28)
      s.sites[i]={id=i,tile=id,kind="town",name=i==1 and "North Wharf" or "South Wharf",
        population=250,service=0,stock={},produced={},received={}}
      s.tiles[id].site=i
      for z=27,30 do for u=x-2,x+3 do
        local t=s.tiles[Sim.id(u,z)]
        if not t.site then t.house,t.source_house=true,{id=4,town=i,completed=true} end
      end end
    end
  else
    s.ship_coal_service,s.road_coal=true,true
    local p=dofile(mod.."/openttd/passengers.lua")
    local r=dofile(mod.."/openttd/station_rating.lua")
    local inc=dofile(mod.."/openttd/income.lua")
    local catch=dofile(mod.."/openttd/station_catchment.lua")(p,r)
    local coal=dofile(mod.."/openttd/coal_industry.lua")(p,r,catch,inc)
    local world=dofile(mod.."/coal_industry_world.lua")(Sim,T,coal)
    assert(world.seed(s,Sim.id(12,28),Sim.id(31,28)))
  end
  if not heavy then Sim.mount_road_bus_market(s,cal,year,true) end
  checkpoint.write_state(s)
end
