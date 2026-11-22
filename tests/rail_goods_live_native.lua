-- Appended only to a private Luanti test copy; use the real Harbor
-- board, full authoritative stock day, one SQLite world, and real assets.
local owner,at="Harbor Goods QA",Sim.id
local function proof_goods()
  local Run,Build,View=assert(api.rail_dispatch_controller),assert(api.rail_build),assert(api.rail_dispatch_view)
  local Owned=assert(api.rail_owned)
  assert(S.harbor_valley and S.rail_goods_service and api.rail_goods_tools and
    Sim.road_timber_active(S) and View.goods_wagon_ready())
  Sim.mount_rail_goods(S,function() return false end)
  assert(not Sim.rail_goods_active(S))
  Sim.mount_rail_goods(S,View.goods_wagon_ready)
  assert(Sim.rail_goods_active(S))
  local c=Sim.company(S,owner)
  local qa=S.rail_goods_native_qa
  local depot=at(17,20)
  local function day()
    Sim.daily(S)
    local d=assert(Run.current(S))
    assert(not d.failure,d.failure)
    local st=assert(Sim.rail_goods_status(S))
    assert(st.tick==S.passenger_house_clock.counter and st.tick==S.stock_load_tick)
    return st
  end
  local function art(unit)
    local tile,td=Sim.rail_paid_pose(S,2,1,unit)
    assert(tile and td,"No carrying wagon position")
    api.rail_dispatch_view.step(.1,true,1)
    local x,z=Sim.xy(tile)
    local _,y=api.terrain.tile(tile)
    for _,obj in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=y+.614,z=2*z+.5},2.1)) do
      local e=obj:get_luaentity()
      if e and e.name=="bayline:dispatch_goods_van" then
        local p=obj:get_properties()
        assert(p.mesh=="bl_rail_goods_van.obj" and p.textures[1]=="bl_rail_goods_van.png")
        assert(math.abs(y+.614-obj:get_pos().y)<.002)
        return
      end
    end
    error("Missing physical stock covered wagon model")
  end
  if qa then
    local unit=assert(Owned.get(S,owner,qa.unit))
    local r=assert(Run.current_paid(S,unit.id))
    local first=assert(Sim.rail_goods_status(S))
    assert(first.onboard==qa.units and first.delivered==0 and first.loading and first.last_platform==qa.source)
    assert(c.cash==qa.cash and c.revenue==qa.revenue and c.expense==qa.expense)
    assert(not Owned.commit(S,owner,qa.quote))
    assert(unit.status=="dispatched" and r.stock_wagon==32 and r.freight.cargo=="goods")
    assert(not Sim.rail_coal_status(S) and not Sim.rail_oil_status(S) and not Sim.rail_paid_status(S))
    local charge,delivered,peak=0,0,0
    art(unit.id)
    local road_goods=qa.goods_truck and assert(S.fleet[qa.goods_truck])
    local function delivered_goods()
      local amount=0
      for _,town in ipairs(S.sites) do amount=amount+(town.received and town.received.goods or 0) end
      return amount
    end
    for _=1,360 do
      local phase=day()
      peak=math.max(peak,r.consist_mass)
      for _,e in ipairs(Sim.rail_goods_loading_events(S)) do
        if e.kind=="deliver" then
          assert(e.source_industry==qa.mill and e.distance>0 and e.tile==r.arrival.cargo_tile)
          delivered=delivered+e.units
        elseif e.kind=="fare" then charge=charge+e.amount end
      end
      if phase.delivered>=25 and (not road_goods or road_goods.delivered>0) then
        local truck=assert(S.fleet[qa.truck])
        local mill=S.stock_timber_industries[qa.mill]
        local town=S.sites[qa.town]
        local road_crates,road_money=road_goods and road_goods.delivered or 0,road_goods and road_goods.revenue or 0
        if road_goods then assert(road_crates>0 and road_money>0 and road_goods.expense>0) end
        assert(charge>0 and phase.fare==charge and delivered==phase.delivered and delivered%25==0 and peak==80)
        assert(phase.running_expense>0 and r.running_ticks_total>qa.ticks)
        assert(mill.wood_received>=25 and truck.delivered>0 and truck.revenue>0 and truck.expense>0)
        assert(town.received.goods>=delivered and delivered_goods()==delivered+road_crates)
        assert(c.paid_units==truck.delivered+delivered+road_crates and mill.wood_received>=delivered+road_crates)
        assert(c.revenue==truck.revenue+charge+road_money and
          qa.cash+(c.revenue-qa.revenue)-(c.expense-qa.expense)==c.cash)
        assert(not S.timber_transactions.open_station)
        art(unit.id)
        api.save()
        core.log("action",("RAIL_GOODS_LIVE_NATIVE_PASS crates=%d/$%d road_wood=%d/$%d road_goods=%d/$%d peak_mass=%d operating_cost=$%d"):
          format(delivered,charge,truck.delivered,truck.revenue,road_crates,road_money,peak,phase.running_expense))
        return core.request_shutdown("Stock forest-sawmill train paid after native SQLite restoration",false,0)
      end
    end
    local st=Sim.rail_goods_status(S)
    error(("Missing combined delivery: day=%d rail=%s aboard=%d delivered=%d rail_waiting=%s road=%s aboard=%s delivered=%s"):
      format(S.day,st.phase,st.onboard,st.delivered,tostring(Sim.rail_goods_stop_status(S,qa.source).waiting),
        tostring(road_goods and road_goods.status),tostring(road_goods and road_goods.units),tostring(road_goods and road_goods.delivered)))
  end
  local function checked(ticket,why)
    assert(ticket,why)
    local ok,note=Build.build(owner,ticket)
    assert(ok,note)
  end
  local function lay(x,z,u,v,track)
    checked(Build.quote_track(owner,at(x,z),at(u,v),track,false))
  end
  checked(Build.quote_track(owner,at(13,12),at(16,12),Track.X,false))
  lay(17,12,17,12,Track.RIGHT)
  lay(17,13,17,19,Track.Y)
  checked(Build.quote_depot(owner,depot,Track.NW))
  checked(Build.quote_platform(owner,at(17,16),at(17,18),Track.SE))
  checked(Build.quote_platform(owner,at(13,12),at(15,12),Track.SW))
  checked(Build.quote_signal(owner,at(17,15),Track.NW,false))
  checked(Build.quote_signal(owner,at(17,19),Track.SE,false))
  checked(Build.quote_signal(owner,at(16,12),Track.SW,false))
  local source=S.tiles[at(17,16)].rail_station_id
  local sink=S.tiles[at(13,12)].rail_station_id
  local a,z=assert(Sim.rail_goods_stop_status(S,source)),assert(Sim.rail_goods_stop_status(S,sink))
  assert(#a.sources==1 and not a.accepts and z.accepts and z.eighths==9)
  assert(not Sim.rail_goods_designate(S,owner,source,"unload"))
  assert(not Sim.rail_goods_designate(S,"Not the owner",source,"load"))
  assert(Sim.rail_goods_designate(S,owner,source,"load"))
  assert(Sim.rail_goods_designate(S,owner,sink,"unload"))
  assert(not Sim.rail_coal_designate(S,owner,source,"load"))

  local W=dofile(mod.."/timber_world.lua")(Sim,dofile(mod.."/openttd/terrain.lua"),Sim.timber_rules())
  local seed=assert(W.scenario_1751(S))
  local way=seed.road_waypoints[1]
  for i=2,#way do assert(Sim.build(S,owner,"road",Sim.line(way[i-1],way[i]))) end
  assert(Sim.build_truck_stop(S,owner,seed.forest_stop))
  assert(Sim.build_truck_stop(S,owner,seed.sawmill_stop))
  assert(Sim.build(S,owner,"road_depot",{seed.depot}))
  local truck=assert(Sim.purchase(S,owner,"wood_truck","wood",nil,seed.depot))
  assert(Sim.add_order(S,owner,truck,S.tiles[seed.forest_stop].station,"full"))
  assert(Sim.add_order(S,owner,truck,S.tiles[seed.sawmill_stop].station,"unload"))
  assert(Sim.toggle(S,owner,truck))
  local second_truck
  if core.settings:get_bool("bayline_native_rail_goods_competition",false) then
    -- Stay north of the rail corridor when closing the optional road
    -- turnaround loop; use the existing Mill loading spur.
    local mill_stop,town_stop=seed.mill_goods_stop,seed.goods_stop
    assert(Sim.build(S,owner,"road",seed.mill_goods_spur))
    assert(Sim.build(S,owner,"road",Sim.line(at(15,8),at(15,11))))
    assert(Sim.build(S,owner,"road",Sim.line(at(15,11),at(12,11))))
    assert(Sim.build_truck_stop(S,owner,mill_stop))
    assert(Sim.build_truck_stop(S,owner,town_stop))
    second_truck=assert(Sim.purchase(S,owner,"goods_truck","goods",nil,seed.depot))
    assert(Sim.add_order(S,owner,second_truck,S.tiles[mill_stop].station,"full"))
    assert(Sim.add_order(S,owner,second_truck,S.tiles[town_stop].station,"unload"))
    assert(Sim.toggle(S,owner,second_truck))
  end

  Sim.mount_rail_goods(S,function() return false end)
  assert(not Owned.quote(S,owner,depot,{0,32}))
  Sim.mount_rail_goods(S,View.goods_wagon_ready)
  assert(not Owned.quote(S,owner,depot,{0,32,32}))
  local q=assert(Owned.quote(S,owner,depot,{0,32}))
  assert(q.price==12421 and q.stats.weight==68 and q.stats.max_weight==80 and q.stats.freight_trains==1)
  local before=c.cash
  local unit=assert(Owned.commit(S,owner,q))
  assert(unit.price==12421 and c.cash==before-12421 and not Owned.commit(S,owner,q))
  assert(not Owned.start(S,owner,unit.id,source,sink))
  local ok,note,r=Owned.start_goods(S,owner,unit.id,source,sink)
  assert(ok,note)
  assert(r.freight.repeat_route and r.freight.cargo=="goods" and r.consist_mass==68)
  for _=1,420 do
    local phase=day()
    if phase.loading and phase.onboard>0 and phase.onboard<25 then
      art(unit.id)
      S.rail_goods_native_qa={unit=unit.id,units=phase.onboard,source=source,sink=sink,mill=a.sources[1],
        town=z.station.town,quote=q,truck=truck,goods_truck=second_truck,cash=c.cash,revenue=c.revenue,expense=c.expense,ticks=r.running_ticks_total}
      api.save()
      core.log("action","RAIL_GOODS_NATIVE_SAVE_LOADING")
      return core.request_shutdown("Stock physical Goods Van saved mid-loading",false,0)
    end
  end
  error("Actual stock Forest-to-Sawmill route did not load the Goods Van")
end
core.after(0,function()
  core.emerge_area({x=18,y=-1,z=20},{x=40,y=5,z=43},function(_,_,remaining)
    if remaining==0 then core.after(0,proof_goods) end
  end)
end)
