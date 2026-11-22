-- Native disposable world proof on the expanded generated board. Reload
-- uses size 64 in config deliberately: saved geometry is authoritative.
local function geometry_digest()
  local p=assert(S.stock_generated_profile)
  local a={p.width,p.depth,p.river_rng_cursor}
  for _,level in ipairs(S.corner_grid.levels) do a[#a+1]=level end
  for i,t in ipairs(S.tiles) do
    a[#a+1]=table.concat({i,t.h,t.terrain,t.water_class or "-",t.stock_river_bits or "-",
      t.stock_industry and t.stock_industry.id or "-",t.road_bits or 0,t.station or 0},":")
  end
  return core.sha256(table.concat(a,";"))
end
core.after(0,function()
  local p=assert(S.stock_generated_profile)
  local c=assert(S.passenger_house_clock)
  assert(Sim.W==128 and Sim.H==128 and p.width==128 and p.depth==128)
  assert(#S.tiles==16384 and #S.corner_grid.levels==16641 and p.river_stats.rivers==2)
  assert(S.tiles[16384].stock_void and p.towns==8 and #p.industries==13)
  assert(c.log_x==7 and c.log_y==7 and c.head==p.river_rng_cursor and c.head>4095)
  local phase=core.settings:get("bayline_native_generation_phase")
  local name="ScaleQA"
  local first,last=Sim.id(103,70),Sim.id(110,70)
  assert(first==8935 and last==8942 and not Sim.id(129,70))
  if phase=="save" then
    local company=Sim.company(S,name)
    local before=company.cash
    assert(Sim.build(S,name,"road",Sim.line(Sim.id(102,70),Sim.id(111,70))))
    assert(Sim.build(S,name,"road_station",{first,last}))
    assert(company.cash<before)
    S.generated_scale_qa={digest=geometry_digest(),paid=before-company.cash}
    api.save()
  else
    assert(S.generated_scale_qa.digest==geometry_digest())
    assert(S.generated_scale_qa.paid==100000-Sim.company(S,name).cash)
  end
  local a,b=S.stations[S.tiles[first].station],S.stations[S.tiles[last].station]
  local path,td,cost,frames=Sim.path(S,a,b,"road",name)
  assert(path and path[1]==first and path[#path]==last and td and cost>0 and #frames==113)
  core.log("action",("STOCK GENERATED NATIVE %s scale=128x128 towns=%d industries=%d cursor=%d far=%d->%d road-frames=%d paid=%d")
    :format(phase,p.towns,#p.industries,c.head,first,last,#frames,S.generated_scale_qa.paid))
  core.request_shutdown("Generated scale verification complete",false,0)
end)
