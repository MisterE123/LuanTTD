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
  s.ship_paid_service,s.road_oil=true,true
  local W=assert(Sim.mount_oil_world(s,T,true))
  assert(W.place(s,assert(W.plan(s,12,28,31,28))))
  local cal=dofile(mod.."/openttd/stock_engine_calendar.lua")
  local year=tonumber(core.settings:get("bayline_stock_bus_start_year")) or 1950
  Sim.mount_road_bus_market(s,cal,year,true)
  checkpoint.write_state(s)
end
