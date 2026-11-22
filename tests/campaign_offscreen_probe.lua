-- Loaded only in a temporary dedicated Luanti test world.
return function(api)
  local S,Sim=api.s,api.Sim
  local stage=assert(tonumber(core.settings:get("bayline_offline_fixture_stage")))
  local out=assert(core.settings:get("bayline_offline_fixture_result"))
  local q=S.qa_offline_economy
  local name="OffscreenQA"
  local oil=api.oil_tools
  if not q then
    assert(stage==1)
    local function stop(x,z)
      local id=assert(Sim.id(x,z))
      assert(Sim.build_truck_stop(S,name,id))
      return S.tiles[id].station
    end
    local function purchase(engine,cargo,depot,a,b)
      local id=assert(Sim.purchase(S,name,engine,cargo,nil,depot))
      assert(Sim.add_order(S,name,id,a))
      assert(Sim.add_order(S,name,id,b))
      assert(Sim.toggle(S,name,id))
      return id
    end
    if oil then
      local paths={
        {{12,4},{16,4},{16,7},{15,7},{15,8},{12,8},{12,14},{14,14},{14,16},{18,16}},
        {{12,4},{12,5},{16,5}},{{15,8},{15,12},{12,12}},{{18,16},{18,15},{14,15}},
      }
      local function id(p) return assert(Sim.id(p[1],p[2])) end
      for _,p in ipairs(paths) do for i=2,#p do
        assert(Sim.build(S,name,"road",Sim.line(id(p[i-1]),id(p[i]))))
      end end
      local a,b,c=stop(13,4),stop(16,16),stop(14,8)
      local depot=Sim.id(11,12)
      assert(Sim.build(S,name,"road_depot",{depot}))
      local v= purchase("oil_tanker","oil",depot,a,b)
      local w=purchase("goods_truck","goods",depot,b,c)
      q={ids={v,w},kind="oil"}
    else
      local a,b,d=Sim.id(9,12),Sim.id(18,12),Sim.id(10,13)
      assert(Sim.build(S,name,"road",Sim.line(a,b)))
      assert(Sim.build(S,name,"road_station",{a,b}))
      assert(Sim.build(S,name,"road_depot",{d}))
      q={ids={purchase("bus","passenger",d,S.tiles[a].station,S.tiles[b].station)},kind="passenger"}
    end
    S.qa_offline_economy=q
    S.speed=4
    api.save()
  end
  local function money()
    local amount,units,counters=0,0,{}
    for i,id in ipairs(q.ids) do
      local v=S.fleet[id]
      amount=amount+v.revenue;units=units+v.delivered;counters[i]=v.delivered
    end
    return amount,units,counters
  end
  local _,paid,counters=money()
  local init={day=S.day,paid=paid,by_vehicle=counters,clock=S.passenger_house_clock and S.passenger_house_clock.counter or 0}
  local start=core.get_us_time()
  local finished=false
  core.register_globalstep(function()
    assert(#core.get_connected_players()==0,"Offscreen test accidentally had a viewer")
    if finished then return end
    local dollars,paid,counters=money()
    local fare_tick=0
    if stage==3 then
      if core.get_us_time()-start<1000000 then return end
      assert(S.day==init.day and paid==init.paid,"Opt-out continued running without players")
    else
      for i,n in ipairs(counters) do if n<=init.by_vehicle[i] then return end end
      assert(S.day>init.day)
      for _,id in ipairs(q.ids) do
        local v=S.fleet[id]
        assert(v.last_fare.tick>init.clock and v.expense>0)
        fare_tick=math.max(fare_tick,v.last_fare.tick)
      end
      assert(S.stock_load_tick==S.passenger_house_clock.counter)
      assert(S.companies[name].paid_units==paid and S.companies[name].revenue==dollars)
    end
    local received
    if oil then
      received=assert(S.stock_oil_industries[0x3001].received.oil)
      assert(received==counters[1])
    end
    local report={stage=stage,day=S.day,paid=paid,dollars=dollars,clock=S.stock_load_tick or 0,
      fare_tick=fare_tick,viewport_clients=0,from=init,kind=q.kind,by_vehicle=counters,received_oil=received}
    local f=assert(io.open(out,"w"));f:write(core.write_json(report));f:close()
    api.save();finished=true
    core.log("action","NATIVE OFFSCREEN ECONOMY PASS stage="..stage)
    core.request_shutdown("Offscreen campaign economy verified",false,0)
  end)
end
