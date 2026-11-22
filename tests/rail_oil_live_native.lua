-- Appended only to a native test copy. Actual paid rail and road
-- movement on the original seed, not calls into a stand-alone loader.
local owner="Oil Rail QA"
local at=Sim.id
local RosterOilQA=dofile(mod.."/openttd/rail_roster.lua")
local function test_rail_oil()
  local Run,Owned,Build=assert(api.rail_dispatch_controller),assert(api.rail_owned),assert(api.rail_build)
  assert(api.rail_oil_tools and Sim.rail_oil_active(S) and api.rail_dispatch_view.oil_wagon_ready())
  local v,qa=Sim.company(S,owner),S.rail_oil_native_qa
  local function day()
    Sim.daily(S)
    local d=Run.current(S)
    assert(d and not d.failure,d and d.failure)
    assert(S.stock_load_tick==S.passenger_house_clock.counter,"Road and house clocks diverged")
  end
  if qa then
    local phase=assert(Sim.rail_oil_status(S))
    local train=assert(Run.current_paid(S,qa.unit))
    local unit=assert(Owned.get(S,owner,qa.unit))
    local goods=assert(S.fleet[qa.truck])
    assert(unit.status=="dispatched" and train.stock_wagon==30 and train.freight.cargo=="oil")
    assert(phase.onboard==qa.onboard and phase.loading and phase.last_platform==qa.wells)
    assert(v.cash==qa.cash and v.revenue==qa.revenue and v.expense==qa.expense)
    assert(not Owned.commit(S,owner,qa.quote))
    local refinery=S.stock_oil_industries[0x3001]
    assert((refinery.received and refinery.received.oil or 0)==0 and goods.delivered==0)
    local peak_mass=0
    for _=1,800 do
      day()
      local current=assert(Sim.rail_oil_status(S))
      peak_mass=math.max(peak_mass,train.consist_mass)
      if current.delivered>=30 and goods.delivered>0 then
        assert(current.fare>0 and goods.revenue>0 and current.running_expense>0 and goods.expense>0)
        assert(peak_mass==101,"Full Oil wagon plus Kirby should weigh 101t")
        assert(refinery.received.oil==current.delivered and refinery.was_cargo_delivered)
        assert(v.revenue==current.fare+goods.revenue,"Income cannot be duplicated or paid by a nonmoving source")
        assert(qa.cash+(v.revenue-qa.revenue)-(v.expense-qa.expense)==v.cash)
        assert(v.paid_units==current.delivered+goods.delivered)
        assert(not Sim.rail_paid_status(S) and not Sim.rail_coal_status(S))
        assert(train.stock_steps>qa.steps and train.freight.reversals>0)
        api.save()
        core.log("action",("RAIL_OIL_LIVE_NATIVE_PASS wagon=%d000L/$%d goods=%d/$%d peak=%dt native_stock_moves=%d"):format(
          current.delivered,current.fare,goods.delivered,goods.revenue,peak_mass,train.stock_steps))
        return core.request_shutdown("Actual rail oil and Goods paid after SQLite restore",false,0)
      end
    end
    local current=Sim.rail_oil_status(S)
    error(("No combined delivery. day=%d rail=%s %d/%d wells=%s refining=%d goods=%s %d/%d"):format(
      S.day,current.phase,current.onboard,current.delivered,tostring(Sim.rail_oil_stop_status(S,qa.wells).waiting),
      refinery.received and refinery.received.oil or 0,goods.status,goods.units,goods.delivered))
  end

  local wells,sink,goods=dofile(mod.."/rail_oil_live_layout.lua")(api,owner,true)
  local wl,rf=assert(Sim.rail_oil_stop_status(S,wells)),assert(Sim.rail_oil_stop_status(S,sink))
  assert(wl.sources[1]==0x3000 and not wl.accepts and rf.accepts and not wl.role and not rf.role)
  assert(not Sim.rail_oil_designate(S,owner,wells,"unload"))
  assert(not Sim.rail_oil_designate(S,"Other company",wells,"load"))
  assert(Sim.rail_oil_designate(S,owner,wells,"load"))
  assert(Sim.rail_oil_designate(S,owner,sink,"unload"))


  local q=assert(Owned.quote(S,owner,at(14,5),{0,30}))
  assert(q.price==RosterOilQA.purchase_price(0)+RosterOilQA.purchase_price(30) and q.stats.weight==71)
  assert(not Owned.quote(S,owner,at(14,5),{0,30,30}))
  local cash_before=v.cash
  local unit=assert(Owned.commit(S,owner,q))
  assert(v.cash==cash_before-q.price and not Owned.commit(S,owner,q))
  assert(not Owned.start(S,owner,unit.id,wells,sink))
  assert(not Owned.start_oil(S,owner,unit.id,sink,wells))
  local ok,note,train=Owned.start_oil(S,owner,unit.id,wells,sink)
  assert(ok,note)
  assert(train.freight.repeat_route and train.freight.cargo=="oil" and train.consist_mass==71)
  for _=1,360 do
    day()
    local phase=assert(Sim.rail_oil_status(S))
    if phase.loading and phase.onboard>0 then
      assert(phase.onboard<30 and phase.last_platform==wells and phase.delivered==0)
      local wagon,td=Sim.rail_paid_pose(S,2,1,unit.id)
      assert(wagon==train.consist.parts[2].tile and td)
      S.rail_oil_native_qa={unit=unit.id,wells=wells,sink=sink,truck=goods,quote=q,onboard=phase.onboard,steps=train.stock_steps,
        cash=v.cash,revenue=v.revenue,expense=v.expense}
      api.save()
      core.log("action","RAIL_OIL_SAVE_LOADING")
      return core.request_shutdown("Saved native partially filled Oil Tanker",false,0)
    end
  end
  error("Native train did not pick up oil")
end
core.after(0,function() core.after(0,test_rail_oil) end)
