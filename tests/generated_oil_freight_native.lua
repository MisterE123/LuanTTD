-- Appended only to a disposable installation's real init.lua. Start the
-- ordinary generated campaign; build a road service without scenario flags,
-- fabricated freight, altered terrain or injected industries.
core.after(0,function()
  local owner="Generated Oil QA"
  local at=Sim.id
  local profile=assert(S.stock_generated_profile)
  assert(api.generated_world and Sim.W==64 and Sim.H==64 and S.seed==1751)
  assert(api.oil_tools and api.rail_oil_tools and api.farm_tools and api.timber_tools and api.ship_coal_tools,
    "Not all ordinary freight systems mounted together")
  local refinery,wells
  for _,r in ipairs(profile.industries) do
    if r.kind=="oil_refinery" then refinery=r elseif r.kind=="oil_well" then wells=r end
  end
  assert(refinery and refinery.tile==at(48,35) and wells and wells.tile==at(24,28),
    "Default seed oil geography changed; update the planned road corridor")
  assert(core.settings:get("bayline_scenario")==nil)
  local saved=S.generated_oil_freight_test
  if not saved then
    local function road(x,z,u,v)
      local ok,note=Sim.build(S,owner,"road",Sim.line(at(x,z),at(u,v)))
      assert(ok,("Road at (%d, %d) to (%d, %d): %s"):format(x,z,u,v,tostring(note)))
    end
    -- An ordinary paved circuit by the wells leads across the ridge,
    -- then down the coast past the refinery to the new town's north side.
    for _,r in ipairs({{25,29,52,29},{25,29,25,30},{25,30,28,30},{28,30,28,29},
        {52,29,52,39},{52,39,50,39},{50,39,50,42},{50,42,51,42}}) do road(unpack(r)) end
    local function stop(x,z)
      local id=at(x,z)
      local built,why=Sim.build_truck_stop(S,owner,id)
      assert(built,("Loading stop (%d,%d): %s"):format(x,z,tostring(why)))
      return assert(S.stations[S.tiles[id].station])
    end
    local a,b,c=stop(26,29),stop(52,38),stop(52,43)
    local depot=at(40,30)
    assert(Sim.build(S,owner,"road_depot",{depot}))
    local _,well_catch=Sim.oil_stop_status(S,a,"oil")
    local _,crude_catch=Sim.oil_stop_status(S,b,"oil")
    local _,refinery_catch=Sim.oil_stop_status(S,b,"goods")
    local _,town=Sim.oil_stop_status(S,c,"goods")
    assert(well_catch.sources[1]==wells.industry and crude_catch.accepts and crude_catch.eighths>=8 and
      #refinery_catch.sources==1 and refinery_catch.sources[1]==refinery.industry and town.accepts,
      core.serialize({well_catch,crude_catch,refinery_catch,town}))
    local function buy(engine,cargo,a,b)
      local id=assert(Sim.purchase(S,owner,engine,cargo,nil,depot))
      local v=S.fleet[id]
      assert(Sim.path(S,a,b,"road",owner,nil,v) and Sim.path(S,b,a,"road",owner,nil,v))
      assert(Sim.add_order(S,owner,id,a.id) and Sim.add_order(S,owner,id,b.id))
      assert(Sim.toggle(S,owner,id))
      return v
    end
    local tanker=buy("oil_tanker","oil",a,b)
    local goods=buy("goods_truck","goods",b,c)
    for _=1,350 do
      Sim.daily(S)
      if tanker.delivered>0 and goods.delivered==0 then
        local ledger=assert(S.stock_oil_industries[refinery.industry])
        assert(ledger.received.oil==tanker.delivered)
        S.generated_oil_freight_test={oil=tanker.id,goods=goods.id,liters=tanker.delivered,refinery=b.id,town=c.id}
        api.save()
        core.log("action","GENERATED_OIL_FREIGHT_SAVED")
        core.request_shutdown("Generated oil tanker delivered to its stock refinery",false,0)
        return
      end
    end
    error("The native generated oil tanker made no first crude delivery")
  end
  local tanker,goods=S.fleet[saved.oil],S.fleet[saved.goods]
  assert(tanker.delivered==saved.liters and goods.delivered==0)
  for _=1,500 do
    Sim.daily(S)
    if tanker.delivered>saved.liters and goods.delivered>0 then
      local company=S.companies[owner]
      assert(company.revenue==tanker.revenue+goods.revenue)
      assert(company.paid_units==tanker.delivered+goods.delivered and S.passenger_house_clock.counter==S.stock_load_tick)
      local firm=assert(S.stock_oil_industries[refinery.industry])
      assert(firm.received.oil==tanker.delivered and tanker.expense>0 and goods.expense>0)
      core.log("action",("GENERATED_OIL_FREIGHT_PASS stock default seed: %d thousand L/$%d plus %d Goods/$%d after SQLite restart")
        :format(tanker.delivered,tanker.revenue,goods.delivered,goods.revenue))
      core.request_shutdown("Generated oil refinery paid delivered Goods",false,0)
      return
    end
  end
  error(("Generated oil route did not repeat: crude=%d %s, Goods=%d %s")
    :format(tanker.delivered,tanker.status,goods.delivered,goods.status))
end)
