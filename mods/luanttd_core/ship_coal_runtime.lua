-- SPDX-License-Identifier: GPL-2.0-only
-- Stock dry-cargo hull. Coal joins the coal economy; other mounted
-- cargoes share the industry ledger and the same stock motion actor.
return function(Sim,Service,Roster,Rating,debit,credit,receive,Calendar,Goods,Mail)
  local M={}
  local bindings=setmetatable({},{__mode="k"})
  local frames=setmetatable({},{__mode="k"})
  local function depot(s,id) return s.stock_ship_depots and s.stock_ship_depots[id] end
  local function frame(s)
    if not frames[s] then frames[s]={events={}} end
    return frames[s]
  end
  local function live_docks(board,a,z,allow_intersection)
    local out={}
    for _,id in ipairs({a,z}) do
      local tiles=board.station_dock_tiles(id)
      if #tiles==0 then return nil end
      for _,tile in ipairs(tiles) do
        if out[tile] and not allow_intersection then return nil end
        out[tile]=true
      end
    end
    return out
  end
  local function docks(run)
    if not run.transport_orders then return {run.first,run.second} end
    local ids={}
    for _,o in ipairs(run.transport_orders) do
      if o.kind=="station" then ids[#ids+1]=o.id end
    end
    if run.vehicle.loading and run.last_dock then ids[#ids+1]=run.last_dock end
    return ids
  end
  local function check_pair(board,dep,a,z,other)
    if not other then return true end
    if dep==other.depot then return false,"FERRY_FREIGHT_SHARED_DEPOT" end
    local our=live_docks(board,a,z,true)
    if not our then return false,"DOCK_BERTHS_OVERLAP_OR_MISSING" end
    for _,id in ipairs(docks(other)) do
      if id==a or id==z then return false,"FERRY_FREIGHT_SHARED_BERTH" end
      for _,tile in ipairs(board.station_dock_tiles(id)) do
        if our[tile] then return false,"FERRY_FREIGHT_SHARED_BERTH" end
      end
    end
    return true
  end
  function M.mount(s,Run,Passenger,Network,art)
    bindings[s]={run=Run,passenger=Passenger,network=Network,ready=art,calendar={}}
    Run.start_guard=function(w,dep,a,z,board)
      if not live_docks(board,a,z) then return false,"DOCK_BERTHS_OVERLAP_OR_MISSING" end
      return check_pair(board,dep,a,z,Passenger.current(w))
    end
    local function order_guard(w,p,list,board,other)
      if not other then return true end
      for _,o in ipairs(list) do
        if o.kind=="station" then
          local ok,why=check_pair(board,p.depot,o.id,o.id,other)
          if not ok then return nil,why end
        end
      end
      return true
    end
    Run.order_guard=function(w,p,list,board)
      local ids,berths={},{}
      for _,o in ipairs(list) do
        if o.kind=="station" and not ids[o.id] then
          local tiles=board.station_dock_tiles(o.id)
          if #tiles==0 then return false,"A coal dock has no water berth." end
          for _,tile in ipairs(tiles) do
            if berths[tile] then return false,"Coal docks need separate water berths." end
            berths[tile]=true
          end
          ids[o.id]=true
        end
      end
      return order_guard(w,p,list,board,Passenger.current(w))
    end
    Passenger.order_guard=function(w,p,list,board) return order_guard(w,p,list,board,Run.current(w)) end
    Passenger.start_guard=function(w,dep,a,z,board)
      local craft=w.stock_coal_ship
      if craft and craft.depot==dep then return false,"FERRY_FREIGHT_SHARED_DEPOT" end
      return check_pair(board,dep,a,z,Run.current(w))
    end
  end
  local function coal_active(s)
    return s.stock_coal_industries and next(s.stock_coal_industries)~=nil
  end
  local coal_profile={name="Coal",load="Coal mine",unload="Power plant",sink="power station"}
  local function refit_profile(cargo)
    if cargo=="coal" then return coal_profile end
    if cargo=="mail" then return Mail and Mail.profile end
    return Goods and Goods.refit_profile(cargo)
  end
  function M.cargo_profile(s,cargo)
    if cargo=="coal" then return coal_active(s) and coal_profile or nil end
    if cargo=="mail" then return Mail and Mail.enabled(s) and Mail.profile or nil end
    return Goods and Goods.profile(s,cargo)
  end
  function M.goods(s)
    return M.cargo_profile(s,"goods")~=nil
  end
  function M.refit_choices()
    local out={}
    for _,row in ipairs(Roster.refit_catalog()) do
      local profile=refit_profile(row.cargo)
      if profile then out[#out+1]={id=row.id,cargo=row.cargo,name=profile.name} end
    end
    return out
  end
  local function industry_cargo(s)
    local craft=s.stock_coal_ship
    local cargo=craft and Roster.cargo_key(craft.cargo)
    if cargo and cargo~="coal" and cargo~="mail" and M.cargo_profile(s,cargo) then return cargo end
  end
  function M.active(s)
    return not not (bindings[s] and s.ship_coal_service and s.road_stock_house_supply and
      (s.stock_coal_industries or M.goods(s) or M.cargo_profile(s,"mail")) and Sim.road_stock_service_active(s))
  end
  function M.goods_stations(s)
    if not industry_cargo(s) then return end
    local spec=bindings[s]
    if spec then return Goods.stations(s,spec.run,spec.network) end
  end
  function M.goods_running(s,station)
    if not industry_cargo(s) then return false end
    local spec=bindings[s]
    local voyage=spec and spec.run.current(s)
    return voyage and (not station or spec.run.ordered_dock(voyage,station)) or false
  end
  function M.mail(s)
    local spec=bindings[s]
    local craft=s.stock_coal_ship
    if not (spec and craft and Roster.cargo_key(craft.cargo)=="mail" and M.active(s)) then return end
    local p=spec.run.current(s)
    if not (p and p.paid_clock and (not spec.ready or spec.ready(craft.engine))) then return end
    return p,spec.run,Mail.id(p),craft
  end
  function M.mail_charge(s,craft)
    local fixed=Roster.running_fixed(craft.mail_running_ticks or 0,s.stock_ship_running_base,craft.engine)
    craft.mail_running_ticks=0
    if fixed==0 then return end
    local company=Sim.company(s,craft.owner)
    local old=company.stock_money_fraction or 0
    local rem=(old-fixed%256)%256
    company.stock_money_fraction=rem
    local whole=math.floor(fixed/256)+(rem>old and 1 or 0)
    if whole>0 then
      debit(company,whole,"ship_run")
      craft.expense=(craft.expense or 0)+whole
      if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,craft,-whole) end
    end
  end
  function M.cargo_key(s)
    local craft=s.stock_coal_ship
    return craft and Roster.cargo_key(craft.cargo)
  end
  local function model(s,preview)
    local spec=bindings[s]
    if not spec then return end
    local order=not preview and spec.run.current(s)
    local archive=not preview and s.stock_ship_coal or Service.new()
    if not archive then return end
    local function comm(st)
      local c=s.stock_ship_commercial
      return s.ship_paid_service and c and c.service.stations[st.host_id] or nil
    end
    local view=frame(s)
    local b=Service.bind(s,archive,{board=spec.network.board(s),
      dock_filter=order and function(i) return spec.run.ordered_dock(order,i) end,
      current_payment=s.stock_coal_payment,stationwide=comm,received=receive,
      credit=function(world,owner,amount,n)
        local company=Sim.company(world,owner)
        credit(company,amount)
        if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(world,world.stock_coal_ship,amount) end
        company.units,company.paid_units=company.units+n,company.paid_units+n
        if Sim.stock_economy_delivered then Sim.stock_economy_delivered(company,"coal",n) end
      end,
      charge_fixed=function(world,owner,fixed)
        local company=Sim.company(world,owner)
        local old=company.stock_money_fraction or 0
        local remainder=(old-fixed%256)%256
        company.stock_money_fraction=remainder
        local whole=math.floor(fixed/256)+(remainder>old and 1 or 0)
        if whole>0 then debit(company,whole,"ship_run") end
        if world.stock_coal_ship then
          local craft=world.stock_coal_ship
          craft.expense=(craft.expense or 0)+whole
          if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(world,craft,-whole) end
        end
      end,
      station_at=function(id) return s.stations[id] end,
      emit=function(e)
        e.day=s.day
        if e.kind=="fare" then archive.vehicle.last_fare=e.amount end
        if e.kind=="board" then archive.vehicle.boarded=(archive.vehicle.boarded or 0)+e.units end
        view.events[#view.events+1]=e
        if #view.events>4096 then table.remove(view.events,1) end
      end})
    return b,archive,comm
  end
  M.catalog=Roster.order
  M.model=Roster.model
  function M.offer(s,id)
    if not M.active(s) then return end
    local model=Roster.model(id)
    if not model then return end
    local host=bindings[s]
    if host.ready and not host.ready(model.id) then return end
    local market=s.stock_bus_market
    if not (market and Calendar) then return model.id==211 and model or nil end
    if not host.calendar[model.id] then
      host.calendar[model.id]=assert(Calendar.prepare_original(model,market.settings))
    end
    return Calendar.snapshot(host.calendar[model.id],market.epoch+s.day).public and model or nil
  end
  function M.quote(s,owner,dep,id)
    if not M.active(s) then return nil,"STOCK_COAL_SHIP_DISABLED" end
    if s.stock_coal_ship then return nil,"ONE_STOCK_COAL_SHIP_ONLY" end
    local d=depot(s,dep)
    if not d or d.owner~=owner then return nil,"OWN_SHIP_DEPOT_REQUIRED" end
    local p=bindings[s].passenger.current(s) or s.stock_owned_ferry
    if p and p.depot==dep then return nil,"FERRY_FREIGHT_SHARED_DEPOT" end
    if s.stock_owned_oil_ship and s.stock_owned_oil_ship.depot==dep then return nil,"TANKER_USES_THIS_DEPOT" end
    local model=M.offer(s,id or 211)
    if not model then return nil,"CARGO_SHIP_NOT_AVAILABLE" end
    return Roster.quote(Roster.default_cargo,s.stock_ship_purchase_base,nil,model.id)
  end
  function M.buy(s,owner,dep,id)
    local q,why=M.quote(s,owner,dep,id)
    if not q then return nil,why end
    local c=Sim.company(s,owner)
    if c.cash<q.purchase then return nil,"NOT_ENOUGH_MONEY" end
    debit(c,q.purchase)
    local v={id=1,engine=id or Roster.id,owner=owner,depot=dep,built=Sim.date(s),purchase_day=s.day,
      cargo=Roster.default_cargo,purchase=q.purchase,refit=0,expense=0}
    s.stock_coal_ship=v
    return {id="coal",engine=v.engine,cost=v.purchase,cargo=v.cargo,capacity=q.capacity}
  end
  function M.refit_quote(s,owner,dep,cargo)
    if not M.active(s) then return nil,"STOCK_COAL_SHIP_DISABLED" end
    local v=s.stock_coal_ship
    local d=v and depot(s,v.depot)
    if not (d and d.owner==owner and v.owner==owner and (dep==nil or dep==v.depot)) or bindings[s].run.current(s) then
      return nil,"OWN_SHIP_IN_DEPOT_REQUIRED"
    end
    cargo=cargo or "coal"
    local id=Roster.cargo_id(cargo)
    if not id or not refit_profile(cargo) then return nil,"CARGO_NOT_REFITTABLE" end
    if v.cargo==id then return nil,cargo=="coal" and "SHIP_ALREADY_COAL_REFITTED" or "SHIP_ALREADY_CARRIES_CARGO" end
    return Roster.quote(id,s.stock_ship_purchase_base,v.cargo,v.engine)
  end
  function M.refit(s,owner,dep,cargo)
    local q,why=M.refit_quote(s,owner,dep,cargo)
    if not q then return nil,why end
    local v=s.stock_coal_ship
    local c=Sim.company(s,owner)
    if c.cash<q.refit then return nil,"NOT_ENOUGH_MONEY" end
    debit(c,q.refit)
    v.cargo,v.refit=q.cargo,q.refit
    return {id="coal",engine=v.engine,cost=v.refit,cargo=v.cargo,capacity=q.capacity}
  end
  function M.start(s,owner,a,z)
    if not M.active(s) then return nil,"STOCK_COAL_SHIP_DISABLED" end
    local spec=bindings[s]
    local v=s.stock_coal_ship
    if not v or v.owner~=owner then return nil,"OWN_DRY_CARGO_SHIP_REQUIRED" end
    local cargo=Roster.cargo_key(v.cargo)
    local profile=M.cargo_profile(s,cargo)
    if not profile then return nil,cargo=="goods" and "NO_GOODS_INDUSTRY_AUTHORITY" or "UNSUPPORTED_SHIP_CARGO" end
    if a==z or not a or not z then return nil,"OWN_DEPOT_AND_TWO_DOCKS_REQUIRED" end
    local candidate,why=spec.run.quote(s,owner,v.depot,a,z,nil,v.engine)
    if not candidate then return nil,why end
    local source,dest=M.order_report(s,a),M.order_report(s,z)
    if not source or #source.sources==0 then
      return nil,cargo=="coal" and "DOCK_NEEDS_COAL_MINE" or ("Choose a loading dock serving a "..profile.load..".")
    end
    if not dest or not dest.accepts then
      return nil,cargo=="coal" and "DOCK_NEEDS_POWER_STATION" or ("Choose a dock where "..profile.name.." is accepted.")
    end
    local run,why2=spec.run.start(s,owner,v.depot,a,z,nil,v.engine)
    if not run then return nil,why2 end
    if cargo=="mail" then return run,"Mail ship dispatched." end
    if cargo~="coal" then
      Goods.install(s,v,cargo)
      return run,profile.name.." ship dispatched."
    end
    s.stock_ship_coal=Service.new()
    local live=model(s)
    assert(live.vehicle(v))
    return run
  end
  function M.set_stopped(s,owner,stopped)
    if not M.active(s) then return nil,"STOCK_COAL_SHIP_DISABLED" end
    local run=bindings[s].run.current(s)
    if not run or run.owner~=owner then return nil,"OWN_COAL_SHIP_REQUIRED" end
    if run.failure then return nil,run.failure end
    run.stopped=not not stopped
    return true
  end
  function M.busy(s)
    -- A dispatched vessel reserves its topology while sailing, moored
    -- or stopped. An undispatched purchase only protects its depot.
    return s.stock_coal_ship_run~=nil
  end
  function M.order_report(s,id,cargo)
    cargo=cargo or M.cargo_key(s) or "coal"
    if cargo~="coal" then
      local spec=bindings[s]
      if cargo=="mail" then return Mail and spec and Mail.report(s,spec.network,id) end
      return Goods and spec and Goods.report(s,spec.network,id,cargo)
    end
    if not s.stock_coal_industries then return end
    local b=model(s,true)
    return b and b.report(id)
  end
  function M.report(s,id)
    if not M.active(s) or type(id)~="number" or id<0 or id>=0x4000 or id%1~=0 then return end
    if M.cargo_key(s)~="coal" and s.stock_coal_ship then return M.order_report(s,id,"coal") end
    local b=model(s)
    local report=b and b.report(id)
    if report then
      local v=s.stock_ship_coal and s.stock_ship_coal.vehicle
      local loading=v and v.load_state
      local reserved=loading and loading.station==report.station.id and loading.reserved_units or 0
      report.available,report.reserved=report.waiting,reserved
      report.waiting=report.waiting+reserved
    end
    if not report then report=model(s,true).report(id) end
    return report
  end
  local function sample(Run,p)
    local pos,yaw=Run.pose(p)
    return pos and {pos=pos,yaw=yaw} or false
  end
  function M.day(s,first_tick,live,refresh)
    if not M.active(s) then return end
    local spec=bindings[s]
    local run=spec.run.current(s)
    if not run or s.stock_coal_ship.cargo~=Roster.coal or spec.ready and not spec.ready(s.stock_coal_ship.engine) then return end
    local b,state,common=model(s)
    if state.loading_tick and state.loading_tick<first_tick-1 then
      state.loading_tick,state.post_tick=first_tick-1,first_tick-1
    end
    if not refresh then b.economy_day(s.day) end
    if not run.failure then
      for _,o in ipairs(run.transport_orders or {{id=run.first,cargo_order="full"},{id=run.second,cargo_order="no_load"}}) do
        local dock=b.report(o.id)
        if o.cargo_order=="full" and (not dock or #dock.sources==0) then run.failure="COAL_SOURCE_NO_LONGER_AVAILABLE"
        elseif o.cargo_order=="no_load" and (not dock or dock.eighths<8) then run.failure="COAL_SINK_NO_LONGER_AVAILABLE" end
      end
      if run.failure then run.phase="blocked" end
    end
    local view=frame(s)
    if not refresh then view.samples=not live and {sample(spec.run,run)} or nil end
    local function before(tick)
      if run.transport_cancel_full then b.cancel_full();run.transport_cancel_full=nil end
      local ok,why=b.loading_tick(tick,run.stopped or run.phase=="blocked",run.dock_forced_leave)
      if not ok and why then run.failure,run.phase=why,"blocked" end
      return ok
    end
    local function after(tick,ready)
      if ready then
        spec.run.advance_paid(s,{
          leave=function(q,force) return b.leave(q.arrivals,tick,force) end,
          arrive=function(q)
            local order=q.transport_orders and q.transport_orders[q.transport_order_cursor.real+1]
            local policy=order and order.cargo_order or (q.last_dock==q.first and "full" or "no_load")
            local l,why=b.arrive(q.last_dock,q.arrivals,tick,q.last_berth,policy)
            return not not l,why
          end,
        })
        b.after_motion(tick)
      end
      if view.samples then view.samples[#view.samples+1]=sample(spec.run,run) end
    end
    local function rating(tick)
      for _,st in ipairs(b.stations) do
        local shared=common(st)
        if shared then
          if shared.rating_phase==0 then b.rating(st,tick) end
        else
          local phase,events=Rating.advance_clock(st.rating_phase,1)
          st.rating_phase=phase
          if events>0 then
            Rating.increment_station_timers(st)
            b.rating(st,tick)
          end
        end
        if (tick+st.id)%250==0 then
          st.goods.coal.accepted_bigtick=nil
          b.update_acceptance(st)
        end
      end
    end
    return {extend=b.extend,before=before,after=after,rating=rating}
  end
  function M.goods_day(s,pipe,first_tick,live,refresh)
    if not industry_cargo(s) then return end
    local spec=bindings[s]
    local run=spec and spec.run.current(s)
    if not run or spec.ready and not spec.ready(s.stock_coal_ship.engine) then return end
    local view=frame(s)
    if not refresh then view.samples=not live and {sample(spec.run,run)} or nil end
    return Goods.day(s,spec.run,pipe,first_tick,live,function()
      view.samples[#view.samples+1]=sample(spec.run,run)
    end,function(e)
      view.events[#view.events+1]=e
      if #view.events>4096 then table.remove(view.events,1) end
    end,refresh)
  end
  function M.status(s)
    local craft=s.stock_coal_ship
    if not craft then return end
    local b=bindings[s]
    local p=b and b.run.current(s)
    local c=craft.cargo==Roster.coal and s.stock_ship_coal or s.stock_goods_ship_service
    local v=c and c.vehicle
    local post=c and (c.post_tick or c.post)
    if Roster.cargo_key(craft.cargo)=="mail" then
      local service=s.stock_ship_commercial and s.stock_ship_commercial.service
      v=p and p.paid_clock and service and service.vehicles[Mail.id(p)]
      post=service and service.post_tick
    end
    local mine,power
    if p and p.transport_orders then
      for _,o in ipairs(p.transport_orders) do
        if not mine and o.cargo_order=="full" then mine=o.id end
        if not power and o.cargo_order=="no_load" then power=o.id end
      end
    end
    return {id=craft.id,owner=craft.owner,engine=craft.engine,cargo=craft.cargo,name=Roster.model(craft.engine).name,
      phase=p and p.phase or "purchased",capacity=Roster.model(craft.engine).capacity,onboard=v and v.units or 0,
      delivered=v and v.delivered or 0,boarded=v and v.boarded or 0,fare=v and (v.revenue or v.route_profit) or 0,
      last_fare=v and (type(v.last_fare)=="table" and v.last_fare.amount or v.last_fare),purchase=craft.purchase,refit=craft.refit,running_expense=craft.expense,
      depot=craft.depot,mine=mine or p and p.first,power=power or p and p.second,last_dock=p and p.last_dock,
      last_berth=p and p.last_berth,loading=v and v.load_state~=nil,
      visits=p and p.arrivals or 0,stopped=p and p.stopped or false,failure=p and p.failure,
      paused=not M.active(s),tick=post}
  end
  function M.pose(s,f,live)
    local b=bindings[s]
    if not b then return end
    local p=b.run.current(s)
    if not p then return end
    local view=frames[s]
    local samples=view and view.samples
    if live or not samples or #samples<2 or not M.active(s) then return b.run.pose(p) end
    local x=math.max(0,math.min(1,f or 1))*(#samples-1)
    local i=math.floor(x)+1
    local a,z=samples[i],samples[i+1]
    if not (a and z) then return a and a.pos,a and a.yaw end
    local t=x%1
    local from,to=a.pos,z.pos
    local arc=(z.yaw-a.yaw+math.pi)%(2*math.pi)-math.pi
    return {x=from.x+(to.x-from.x)*t,y=from.y+(to.y-from.y)*t,z=from.z+(to.z-from.z)*t},a.yaw+arc*t
  end
  function M.take(s)
    local f=frame(s)
    local out=f.events;f.events={}
    return out
  end
  return M
end
