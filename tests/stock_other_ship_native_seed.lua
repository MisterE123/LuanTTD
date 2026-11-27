-- Disposable fixture only. Create real source oil industries beside a
-- controlled coastline, then let the normal boot reopen the checkpoint.
return function(core,Sim,checkpoint,mod)
  if not checkpoint or checkpoint.read() then return end
  local T=dofile(mod.."/openttd/terrain.lua")
  local s=Sim.new(1751)
  s.stock_generated_profile={version=1,width=64,depth=64,terrain="native tanker contract"}
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
  for z=1,64 do for x=1,64 do
    s.tiles[Sim.id(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
      water_class=z>=33 and "sea" or nil}
  end end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.ship_paid_service=true
  local stock=tonumber(core.settings:get("luanttd_qa_other_ship")) or 212
  if core.settings:get("luanttd_qa_other_ship_cargo")=="goods" then
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
  local cal=dofile(mod.."/openttd/stock_engine_calendar.lua")
  local year=tonumber(core.settings:get("bayline_stock_bus_start_year")) or 1950
  Sim.mount_road_bus_market(s,cal,year,true)
  checkpoint.write_state(s)
end
