-- Appended only to the isolated test copy of init.lua. Two actual
-- Luanti processes, one native save, actual purchased train and truck.
local owner,truck_owner="Coal Kirby QA","Coal Truck QA"
local function place_tile(x) return Sim.id(x,15) end
local mode=core.settings:get("bayline_rail_coal_qa_mode") or "legacy"
assert(mode=="legacy" or mode=="repeat" or mode=="fault")
local function stamp()
  local owned,Run=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  assert(api.rail_coal_tools and Sim.rail_coal_active(S) and Sim.road_coal_active(S))
  local qa=S.rail_coal_native_qa
  local function day()
    Sim.daily(S)
    local d=Run.current(S)
    assert(not (d and d.failure),d and d.failure)
    if S.stock_rail_coal then
      assert(S.stock_rail_coal.post_tick==S.passenger_house_clock.counter,"Coal used a second clock")
    end
  end
  if qa then
    local v=assert(owned.get(S,owner,qa.unit))
    local r=assert(Run.current_paid(S))
    local before=assert(Sim.rail_coal_status(S))
    local company=S.companies[owner]
    assert(v.status=="dispatched" and r.fleet_id==qa.unit and r.stock_engine==0 and r.stock_wagon==29)
    assert(before.onboard==qa.onboard and before.loading and before.running_ticks==qa.ticks)
    assert(company.cash==qa.cash and company.revenue==qa.revenue and company.expense==qa.expense)
    assert(not owned.commit(S,owner,qa.quote) and not Sim.rail_paid_status(S))
    assert(r.freight and not r.shuttle)
    assert(before.repeating==(mode~="legacy") and before.cycles==(mode=="legacy" and 0 or 1))
    assert(before.last_platform==qa.mine and r.station==qa.mine)
    if mode=="fault" then
      -- Simulate the source industry closing in the next world update.
      -- Neither saved cargo/reservations nor physical train are erased.
      local old_head=r.consist.parts[1].tile
      local old_steps=r.stock_steps
      local vstate=S.stock_rail_coal.vehicles[qa.unit]
      local reserved=vstate.load_state.reserved_units
      S.stock_coal_industries[2].removed=true
      Sim.daily(S)
      local broken=Sim.rail_coal_status(S)
      assert(broken.phase=="blocked" and broken.failure:find("no longer accepts coal",1,true))
      assert(Run.current(S).failure==broken.failure and r.consist.parts[1].tile==old_head and r.stock_steps==old_steps)
      assert(broken.onboard==before.onboard and vstate.load_state.reserved_units==reserved and company.revenue==qa.revenue)
      assert(#Sim.rail_coal_loading_events(S)==0)
      local after_block=broken.running_ticks
      Sim.daily(S)
      assert(Sim.rail_coal_status(S).running_ticks==after_block and r.consist.parts[1].tile==old_head)
      core.log("action","RAIL_COAL_FAULT_NATIVE_PASS")
      core.request_shutdown("Closing industry held the real coal train without payment or deletion",false,0)
      return
    elseif mode=="repeat" then
      assert(not Run.park_coal(S,"Other company",qa.unit,true))
      assert(Run.park_coal(S,owner,qa.unit,true))
      assert(Sim.rail_coal_status(S).parking)
    end
    local delivered,fare,first_unit_fee=0,0,nil
    for _=1,190 do
      day()
      for _,e in ipairs(Sim.rail_coal_loading_events(S)) do
        if e.kind=="arrive" and e.station_local==qa.sink then
          assert(e.head==place_tile(41) and e.tile==place_tile(41))
          assert(r.consist.parts[1].pose.td==8 and r.consist.parts[2].pose.td==8)
          local order=S.stock_rail_coal.vehicles[qa.unit].load_state
          assert(order.no_load and not order.full)
        elseif e.kind=="deliver" then
          assert(e.station_local==qa.sink and e.destination_industry==S.stock_coal_industries[2].id)
          assert(e.tile==r.arrival.cargo_tile and e.distance>0 and e.age>=0)
          delivered=delivered+e.units
        elseif e.kind=="fare" then fare=fare+e.amount;first_unit_fee=first_unit_fee or e.amount end
      end
      if Sim.rail_coal_status(S).finished then break end
    end
    local final=assert(Sim.rail_coal_status(S))
    assert(final.finished and final.phase=="freight_complete" and final.running_expense>0)
    local cycles=mode=="repeat" and 2 or 1
    assert(final.delivered==cycles*30 and delivered==30 and fare==final.fare-before.fare and first_unit_fee>0 and final.onboard==0)
    assert(final.boarded==cycles*30 and final.cycles==cycles and r.freight.visits==cycles*2 and r.freight.reversals==cycles*2-1)
    assert(company.cash==qa.cash+(company.revenue-qa.revenue)-(company.expense-qa.expense))
    assert(company.revenue-qa.revenue==fare and company.paid_units==cycles*30)
    local plant=S.stock_coal_industries[2]
    assert(plant.accepted.waiting==0 and plant.was_cargo_delivered)
    local freight_ticks=final.running_ticks
    for _=1,4 do day() end
    assert(Sim.rail_coal_status(S).running_ticks==freight_ticks)
    assert(not owned.toggle(S,owner,qa.unit) and not Run.clear(S,owner))
    local truck=S.fleet[qa.truck]
    assert(truck.delivered>0 and truck.revenue>0)
    local delivery=S.sites[plant.site].received.coal
    assert(delivery==truck.delivered+final.delivered, "Plant received duplicate or synthetic coal")
    local d=Run.current(S)
    assert(d.life.claims[place_tile(41)][Track.X]==r.id)
    core.log("action",("RAIL_COAL_LIVE_NATIVE_PASS mode=%s cycles=%d wagon=%dt/$%d first_fare=$%d second_or_only_fare=$%d truck=%dt/$%d rail_running_expense=$%d"):
      format(mode,cycles,final.delivered,final.fare,before.fare,fare,truck.delivered,truck.revenue,Sim.rail_coal_status(S).running_expense))
    core.request_shutdown("Native coal train and road competition passed restart",false,0)
    return
  end

  local c=Sim.company(S,owner);Sim.company(S,truck_owner)
  local construction=assert(api.rail_build)
  local function build(quote,why)
    assert(quote,why)
    local ok,note=construction.build(owner,quote)
    assert(ok,note)
  end
  -- Actual stock-seed grass, terrain and publicly callable quote/build.
  build(construction.quote_track(owner,place_tile(30),place_tile(43),Track.X,false))
  build(construction.quote_depot(owner,place_tile(44),Track.NE))
  build(construction.quote_platform(owner,place_tile(30),place_tile(32),Track.SW))
  build(construction.quote_platform(owner,place_tile(39),place_tile(41),Track.SW))
  local mine=S.tiles[place_tile(30)].rail_station_id
  local sink=S.tiles[place_tile(39)].rail_station_id
  -- The through power platform needs a stock safe waiting point
  -- before the already-owned depot. Two-way PBS faces east.
  build(construction.quote_signal(owner,place_tile(42),Track.SW,false))
  assert(Sim.rail_coal_stop_status(S,mine).sources[1]==S.stock_coal_industries[1].id)
  assert(not Sim.rail_coal_stop_status(S,mine).accepts and Sim.rail_coal_stop_status(S,sink).accepts)
  assert(not Sim.rail_coal_stop_status(S,mine).role and not Sim.rail_coal_stop_status(S,sink).role)
  assert(not Sim.rail_coal_designate(S,owner,mine,"unload"))
  assert(not Sim.rail_coal_designate(S,"Other company",mine,"load"))
  assert(Sim.rail_coal_designate(S,owner,mine,"load"))
  assert(Sim.rail_coal_designate(S,owner,sink,"unload"))
  assert(Sim.rail_coal_stop_status(S,mine).role=="load" and Sim.rail_coal_stop_status(S,sink).role=="unload")

  local from,dest,at=Sim.id(31,14),Sim.id(41,14),Sim.id(33,13)
  assert(Sim.build(S,truck_owner,"road",Sim.line(from,dest)))
  assert(Sim.build_truck_stop(S,truck_owner,from))
  assert(Sim.build_truck_stop(S,truck_owner,dest))
  assert(Sim.build(S,truck_owner,"road_depot",{at}))
  local truck=assert(Sim.purchase(S,truck_owner,"coal_tipper","coal",nil,at))
  assert(Sim.add_order(S,truck_owner,truck,S.tiles[from].station,"full"))
  assert(Sim.add_order(S,truck_owner,truck,S.tiles[dest].station))
  local driven,reason=Sim.toggle(S,truck_owner,truck);assert(driven,reason)

  local q=assert(owned.quote(S,owner,place_tile(44),{0,29}))
  local prior=c.cash
  local v=assert(owned.commit(S,owner,q))
  assert(v.stock_ids[1]==0 and v.stock_ids[2]==29 and c.cash==prior-v.price and not owned.commit(S,owner,q))
  assert(not owned.start(S,owner,v.id,mine,sink))
  assert(not owned.start_coal(S,owner,v.id,sink,mine))
  local ok,note,r=owned.start_coal(S,owner,v.id,mine,sink);assert(ok,note)
  assert(r.freight and r.freight.repeat_route and not r.shuttle and r.consist_mass==65 and r.max_track_speed==64)
  -- Absence of the repeat-order marker represents an already-saved
  -- one-delivery preview; it must still park after that original order.
  if mode=="legacy" then r.freight.repeat_route=nil end
  local first_fare,back_from_plant,visits=0,false,{}
  for _=1,240 do
    day()
    local state=assert(Sim.rail_coal_status(S))
    local load=S.stock_rail_coal.vehicles[v.id].load_state
    for _,e in ipairs(Sim.rail_coal_loading_events(S)) do
      if e.kind=="fare" then first_fare=first_fare+e.amount
      elseif e.kind=="arrive" then
        visits[#visits+1]=e.station_local
        if e.station_local==mine then
          assert(e.head==place_tile(30) and e.tile==place_tile(30))
          assert(r.consist.parts[1].pose.td==0 and r.consist.parts[2].pose.td==0 and load.full and not load.no_load)
        else
          assert(e.station_local==sink and e.head==place_tile(41) and e.tile==place_tile(41))
          assert(r.consist.parts[1].pose.td==8 and r.consist.parts[2].pose.td==8 and load.no_load and not load.full)
        end
      elseif e.kind=="leave" and e.station_local==sink then back_from_plant=true end
    end
    if state.loading and state.last_platform==mine and state.onboard>0 and (mode=="legacy" or state.cycles==1) then
      if mode~="legacy" then
        assert(state.onboard<30 and state.boarded==30+state.onboard)
        assert(state.delivered==30 and state.fare==first_fare and first_fare>0 and back_from_plant)
        assert(r.freight.reversals==2 and #visits==3 and visits[1]==mine and visits[2]==sink and visits[3]==mine)
      end
      assert(state.mine==mine and state.power==sink and state.platform_tiles==3 and state.running_expense>0)
      assert(state.cargo_tile==r.consist.parts[2].tile and state.head_tile==r.consist.parts[1].tile)
      local a,td,t=Sim.rail_paid_pose(S,2,1)
      assert(a==state.cargo_tile and td and t)
      S.rail_coal_native_qa={unit=v.id,quote=q,mine=mine,sink=sink,truck=truck,onboard=state.onboard,
        ticks=state.running_ticks,cash=c.cash,revenue=c.revenue,expense=c.expense}
      api.save()
      core.log("action","RAIL_COAL_SAVE_LOADING")
      core.request_shutdown("Saved a real loaded Kirby coal service",false,0)
      return
    end
  end
  error("No real owned coal wagon boarded")
end
core.after(0,function() core.after(0,stamp) end)
