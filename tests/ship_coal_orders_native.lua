-- Native continuation test mounted into a disposable coastal campaign.
local function qa()
  local name="Yate QA"
  local deleting=core.settings:get("luanttd_qa_coal_orders")=="delete"
  local C=assert(api.ship_coal)
  local orders=assert(api.vehicle_orders.ship)
  if not S.yate_native_order_qa then
    local N=assert(api.shipyard.network)
    local a=assert(N.build(S,name,"dock",Sim.id(8,32)))
    local b=assert(N.build(S,name,"dock",Sim.id(5,32)))
    local depot=assert(N.build(S,name,"depot",Sim.id(12,34),0))
    assert(C.buy(name,depot.id))
    assert(C.refit(name))
    local p=assert(C.start(name,a.id,b.id))
    local initial=assert(orders.read(name,"coal"))
    assert(#initial.items==2 and #initial.targets==2)
    local appended,note=orders.edit(name,"coal",initial.revision,"append",nil,a.id)
    assert(appended,note)
    for _=1,900 do
      Sim.daily(S)
      C.take_events()
      local sk=C.status()
      assert(not sk.failure,sk.failure)
      if sk.loading and sk.onboard>0 and sk.onboard<160 and sk.last_dock==a.id then
        assert(S.stock_ship_coal.vehicle.load_state.full)
        local revision=orders.read(name,"coal").revision
        if deleting then
          assert(orders.edit(name,"coal",revision,"remove",1))
          assert(p.transport_cancel_full and p.vehicle.loading)
        else
          assert(orders.edit(name,"coal",revision,"skip",2))
          assert(p.transport_skip_loading and p.vehicle.loading)
        end
        assert(not orders.edit(name,"coal",revision,"up",2))
        S.yate_native_order_qa={first=a.id,second=b.id,onboard=sk.onboard,x=p.vehicle.x,y=p.vehicle.y}
        api.save()
        core.log("action","YATE_ORDERS_NATIVE_SAVED")
        core.request_shutdown("Saved pending loaded ship order skip",false,0)
        return
      end
    end
    error("No partly loaded Yate to edit")
  end
  local prior=S.yate_native_order_qa
  local report=orders.read(name,"coal")
  assert(report.active==(deleting and 1 or 2) and #report.items==(deleting and 2 or 3))
  local p=assert(S.stock_coal_ship_run)
  assert((deleting and p.transport_cancel_full or not deleting and p.transport_skip_loading)
    and C.status().onboard==prior.onboard and p.vehicle.x==prior.x and p.vehicle.y==prior.y)
  local left,arrived
  for _=1,900 do
    Sim.daily(S)
    local st=C.status()
    assert(not st.failure,st.failure)
    if deleting and st.loading and st.last_dock==prior.first and not left then
      assert(not S.stock_ship_coal.vehicle.load_state.full and not p.transport_cancel_full)
    end
    for _,e in ipairs(C.take_events()) do
      if e.kind=="leave" and e.station_local==prior.first then left=true end
      if e.kind=="arrive" and e.station_local==prior.second then arrived=true end
    end
    if st.delivered>0 then
      assert(left and arrived and not p.transport_skip_loading and (deleting or st.delivered<160) and st.fare>0)
      core.log("action",("YATE_ORDERS_NATIVE_PASS %s a genuine partly loaded order; after SQLite restart delivered %dt for $%d"):format(deleting and "deleted" or "skipped",st.delivered,st.fare))
      core.request_shutdown("Owned Yate orders passed",false,0)
      return
    end
  end
  error("No coal after selecting a different order")
end
core.after(0,qa)
