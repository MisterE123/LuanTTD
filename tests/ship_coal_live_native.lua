-- Appended only to disposable native test game init.lua.
local town_services=dofile(mod.."/town_station_services.lua")(Sim)
local function town_freight_clock(id)
  local row
  for _,entry in ipairs(town_services.view(S)) do
    if entry.mode=="ship" and entry.id==id then
      assert(not row,"Physical freight facility counted twice")
      row=entry
    end
  end
  assert(row and (row.time_since_load or 255)<=20,"Paid freight load missing from the town's station clock")
end
local owner,road_owner,ferry_owner="Yate QA","Tipper QA","Ferry QA"
local function qa()
  local C=assert(api.ship_coal)
  local N=assert(api.shipyard.network)
  local ferry_engine=tonumber(core.settings:get("luanttd_qa_ferry_year"))==1980 and 207 or 206
  local id=Sim.id
  assert(api.ship_coal_tools and S.stock_coal_scenario=="south_coast_1751")
  local mine,plant=S.stock_coal_industries[1],S.stock_coal_industries[2]
  assert(mine.x==11 and mine.z==26 and plant.x==4 and plant.z==27)
  local function day()
    Sim.daily(S)
    local st=C.status()
    if st.mine then
      assert(st.tick==S.stock_load_tick and st.tick==S.passenger_house_clock.counter,
        ("%s cargo=%s road=%s house=%s"):format(tostring(st.failure),tostring(st.tick),tostring(S.stock_load_tick),tostring(S.passenger_house_clock.counter)))
      assert(not st.failure,st.failure)
    end
    return st
  end
  if S.yate_native_qa then
    local saved=S.yate_native_qa
    local live=assert(S.stock_coal_ship_run)
    local v=assert(S.stock_ship_coal.vehicle)
    local before=C.status()
    town_freight_clock(saved.source)
    assert(before.onboard==saved.onboard and before.loading and before.last_berth==saved.tile)
    assert(live.vehicle.x==saved.x and live.vehicle.y==saved.y and before.tick==saved.tick)
    assert(v.load_state.reserved_units==saved.reserved)
    local c=S.companies[owner]
    assert(c.cash==saved.cash and c.expense==saved.expense and c.revenue==saved.revenue)
    assert(S.ship_pilot and S.ship_pilot.arrivals==saved.ferry_visits)
    assert(not C.set_stopped(ferry_owner,true) and C.set_stopped(owner,true))
    local age=v.cargo_age_counter
    for _=1,3 do
      local stopped=day()
      assert(stopped.stopped and stopped.onboard==saved.onboard and stopped.last_berth==saved.tile)
    end
    assert(v.cargo_age_counter~=age)
    assert(C.set_stopped(owner,false))
    local tons,paid,fares,visits=0,0,0,0
    local finished
    for _=1,900 do
      local st=day()
      for _,e in ipairs(C.take_events()) do
        assert(e.owner==owner and e.cargo=="coal" and e.tick<=st.tick)
        if e.kind=="arrive" and e.station_local==saved.sink then
          assert(e.tile~=S.stock_ship_stations[saved.sink].water);visits=visits+1
        elseif e.kind=="deliver" then
          assert(e.units<=10 and e.distance>0 and e.destination_industry==plant.id)
          assert(Sim.distance(saved.tile,e.tile)==e.distance)
          tons=tons+e.units
        elseif e.kind=="fare" then
          assert(e.units==160 and e.station_local==saved.sink)
          fares=fares+1;paid=paid+e.amount
        end
      end
      if st.delivered>=160 and st.visits>=3 then finished=st;break end
    end
    assert(finished and finished.delivered==160 and paid>0 and finished.fare==paid and fares==1 and tons==160 and visits==1)
    assert(c.cash==saved.cash+(c.revenue-saved.revenue)-(c.expense-saved.expense))
    assert(S.ship_pilot.arrivals>saved.ferry_visits and Sim.ferry_paid_status(S))
    local passenger=assert(Sim.ferry_paid_status(S))
    local receipt=assert(S.stock_owned_ferry)
    assert(S.ship_pilot.owned and receipt.engine_id==ferry_engine and passenger.owner==ferry_owner)
    assert(passenger.capacity==(ferry_engine==207 and 130 or 100) and receipt.expense>0)
    local name=ferry_engine==207 and "luanttd_core:stock_ffp_passenger_ferry" or "luanttd_core:stock_harbor_ferry"
    local asset=assert(core.registered_entities[name]).initial_properties.mesh
    assert(asset==(ferry_engine==207 and "bl_ffp_passenger_ferry.obj" or "bl_harbor_ferry.obj"))
    core.log("action",("OWNED_FERRY_SQLITE_PASS engine=%d seats=%d running_cost=$%d visits=%d"):format(
      ferry_engine,passenger.capacity,receipt.expense,S.ship_pilot.arrivals))

    local truck=S.fleet[saved.truck]
    assert(truck.revenue>0 and truck.delivered>0)
    assert(plant.was_cargo_delivered and plant.accepted.waiting==0)
    local received=S.sites[plant.site].received.coal
    assert(received==finished.delivered+truck.delivered,"Duplicated coal at the plant")
    assert(S.stock_coal_ship.expense>0 and c.paid_units==finished.delivered)
    core.log("action",("YATE_NATIVE_PASS coast=1751 ship=%dt/$%d road=%dt/$%d ferry_visits=%d running_expense=$%d"):format(
      finished.delivered,paid,truck.delivered,truck.revenue,S.ship_pilot.arrivals,S.stock_coal_ship.expense))
    api.save()
    core.request_shutdown("Stock owned Yate and mixed economy after SQLite reload",false,0)
    return
  end
  assert(#S.sites>=2 and S.seed==1751 and S.tiles[id(11,22)].house)
  local a=assert(N.build(S,owner,"dock",id(8,32)))
  local z=assert(N.build(S,owner,"dock",id(5,32)))
  local d=assert(N.build(S,owner,"depot",id(12,34),0))
  local conflict=assert(N.build(S,owner,"dock",id(6,32),nil,{adjacent=true}))
  local conflict_depot=assert(N.build(S,owner,"depot",id(15,34),0))
  assert(C.dock(a.id).sources[1]==mine.id and C.dock(z.id).accepts)
  -- North inlet passenger pilot remains a separate actor; its private
  -- catalogue and saved identity must not be overwritten by the Yate.
  local fa=assert(N.build(S,ferry_owner,"dock",id(29,3)))
  -- This test needs two orders, not two piers in one station.
  local fz=assert(N.build(S,ferry_owner,"dock",id(29,4),nil,{adjacent=true}))
  local fd=assert(N.build(S,ferry_owner,"depot",id(24,4),0))
  assert(not api.shipyard.start(ferry_owner,fd.id,fa.id,fz.id))
  local fc=Sim.company(S,ferry_owner)
  local before_ferry=fc.cash
  local panel
  local show=core.show_formspec
  core.show_formspec=function(_,form,body)
    assert(form=="luanttd_core:service");panel=body
  end
  local player={get_player_name=function() return ferry_owner end}
  ui.service(player,"harbor_status",fd.tiles[1])
  assert(panel:find("open_passenger_depot",1,true))
  assert(ui.fields(player,"luanttd_core:service",{open_passenger_depot=true}))
  local purchase="buy_passenger_ferry_"..ferry_engine
  assert(panel:find(purchase,1,true))
  assert(ui.fields(player,"luanttd_core:service",{[purchase]=true}))
  local vessel=assert(S.stock_owned_ferry)
  assert(panel:find("Choose passenger ferry orders",1,true))
  core.show_formspec=show
  assert(fc.cash==before_ferry-vessel.price and not api.passenger_ferry.buy(ferry_owner,fd.id,ferry_engine))
  assert(not api.ship_coal.buy(ferry_owner,fd.id))
  assert(api.shipyard.start(ferry_owner,fd.id,fa.id,fz.id))
  local company=S.companies[owner]
  local cash=company.cash
  assert(not C.buy(ferry_owner,d.id))
  local bought=assert(C.buy(owner,d.id))
  assert(bought.cost==32500 and bought.cargo==5 and company.cash==cash-32500)
  local removed,reason=N.remove(S,owner,id(12,34))
  assert(not removed and reason=="DEPOT_HAS_OWNED_SHIP" and C.status().depot==d.id)
  assert(not C.start(owner,a.id,z.id) and not C.buy(owner,d.id))
  local refit=assert(C.refit(owner))
  assert(refit.cost==507 and refit.cargo==1 and company.cash==cash-33007)
  assert(not C.refit(owner))
  assert(not C.start(owner,a.id,conflict.id),"Overlapping potential freight berths")
  local ship=assert(C.start(owner,a.id,z.id))
  assert(ship.vehicle.max_speed==48 and S.ship_pilot.owner==ferry_owner)
  assert(not api.shipyard.clear(ferry_owner))
  assert(not api.shipyard.start(owner,conflict_depot.id,conflict.id,z.id))
  -- Native truck on the same real coastal industry producer/consumer.
  local road_a,road_z,road_depot=id(10,27),id(6,27),id(7,26)
  local roads={{5,27,11,27},{11,27,11,25},{11,25,5,25},{5,25,5,27}}
  for _,a in ipairs(roads) do
    local ok,note=Sim.build(S,road_owner,"road",Sim.line(id(a[1],a[2]),id(a[3],a[4])))
    assert(ok,note)
  end
  assert(Sim.build_truck_stop(S,road_owner,road_a))
  assert(Sim.build_truck_stop(S,road_owner,road_z))
  assert(Sim.build(S,road_owner,"road_depot",{road_depot}))
  local source,sink=S.tiles[road_a].station,S.tiles[road_z].station
  local _,aok,_,report=Sim.coal_stop_status(S,S.stations[source]);assert(report.sources[1]==mine.id)
  local _,zok=Sim.coal_stop_status(S,S.stations[sink]);assert(zok)
  local truck=assert(Sim.purchase(S,road_owner,"coal_tipper","coal",nil,road_depot))
  assert(Sim.add_order(S,road_owner,truck,source,"full"))
  assert(Sim.add_order(S,road_owner,truck,sink))
  assert(Sim.toggle(S,road_owner,truck))
  for _=1,900 do
    local st=day()
    assert(api.ship_coal.pose(1) or st.phase=="depot")
    if st.loading and st.onboard>0 and st.onboard<160 and st.last_dock==a.id then
      local v=S.stock_ship_coal.vehicle
      assert(st.last_berth~=a.water and st.visits==1 and st.fare==0 and v.load_state.slice==10)
      assert(S.fleet[truck].running)
      town_freight_clock(a.id)
      S.yate_native_qa={source=a.id,onboard=st.onboard,tile=st.last_berth,x=ship.vehicle.x,y=ship.vehicle.y,
        tick=st.tick,reserved=v.load_state.reserved_units,truck=truck,sink=z.id,
        cash=company.cash,expense=company.expense,revenue=company.revenue,ferry_visits=S.ship_pilot.arrivals}
      api.save()
      core.log("action","YATE_SAVE_LOADING "..st.onboard.." reserved="..v.load_state.reserved_units)
      core.request_shutdown("Save live partly loaded stock Yate",false,0)
      return
    end
  end
  error("Yate never filled any coal from live industry")
end
core.after(0,qa)
