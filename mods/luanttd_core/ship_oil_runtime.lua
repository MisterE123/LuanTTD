-- SPDX-License-Identifier: GPL-2.0-only
-- Stock oil-tanker lifecycle over the shared OpenTTD ship controller and
-- the same industry authority used by trucks and trains.
return function(Sim,Service,Roster,Calendar,Rules,Catchment,debit)
  local M={}
  local mount=setmetatable({},{__mode="k"})
  local views=setmetatable({},{__mode="k"})
  local function get(s) return assert(mount[s]) end
  local function model(s,id)
    local row=Roster.model(id)
    local market=s.stock_bus_market
    if not (row and market) then return nil end
    local cache=get(s).calendar
    if not cache[id] then cache[id]=assert(Calendar.prepare_original(row,market.settings)) end
    return Calendar.snapshot(cache[id],market.epoch+s.day),row
  end
  local function owns(s,id,owner)
    local d=s.stock_ship_depots and s.stock_ship_depots[id]
    return d and d.owner==owner
  end
  local function overlaps(board,a,b,other)
    if not other then return false end
    local covered={}
    for _,id in ipairs({a,b}) do
      for _,tile in ipairs(board.station_dock_tiles(id)) do covered[tile]=true end
    end
    local orders=other.transport_orders or {{kind="station",id=other.first},{kind="station",id=other.second}}
    for _,o in ipairs(orders) do
      if o.kind=="station" then
        if o.id==a or o.id==b then return true end
        for _,tile in ipairs(board.station_dock_tiles(o.id)) do if covered[tile] then return true end end
      end
    end
    return false
  end
  function M.mount(s,net,run,ready,ferry,coal)
    mount[s]={net=net,run=run,ready=ready,calendar={}}
    local function own_guard(w,dep,a,b,board)
      for _,other in ipairs({ferry,coal or false}) do
        if other then
          local q=other.current(w)
          if q and (q.depot==dep or overlaps(board,a,b,q)) then return false,"TANKER_REQUIRES_DISTINCT_BERTHS" end
        end
      end
      local tiles={}
      for _,dock in ipairs({a,b}) do
        local berth=board.station_dock_tiles(dock)
        if #berth==0 then return false,"TANKER_REQUIRES_WATER_BERTH" end
        for _,tile in ipairs(berth) do
          if tiles[tile] then return false,"TANKER_REQUIRES_DISTINCT_BERTHS" end
          tiles[tile]=true
        end
      end
      return true
    end
    run.start_guard=own_guard
    run.order_guard=function(w,p,list,board)
      local tiles,seen={},{}
      for _,o in ipairs(list) do
        if not seen[o.id] then
          seen[o.id]=true
          for _,other in ipairs({ferry,coal or false}) do
            if other and overlaps(board,o.id,o.id,other.current(w)) then return false,"That dock serves another ship." end
          end
          local cells=board.station_dock_tiles(o.id)
          if #cells==0 then return false,"Choose a real oil berth." end
          for _,tile in ipairs(cells) do
            if tiles[tile] then return false,"This order overlaps another water berth." end
            tiles[tile]=true
          end
        end
      end
      return true
    end
    for _,other in ipairs({ferry,coal or false}) do
      if other then
        local prior,prior_orders=other.start_guard,other.order_guard
        other.start_guard=function(w,dep,a,b,board)
          local tank=run.current(w)
          if w.stock_owned_oil_ship and w.stock_owned_oil_ship.depot==dep or overlaps(board,a,b,tank) then
            return false,"PASSENGER_AND_FREIGHT_NEED_DISTINCT_BERTHS"
          end
          if prior then return prior(w,dep,a,b,board) end
          return true
        end
        other.order_guard=function(w,p,list,board)
          local tank=run.current(w)
          for _,o in ipairs(list) do
            if o.kind=="station" and overlaps(board,o.id,o.id,tank) then return false,"Tanker already uses this berth." end
          end
          if prior_orders then return prior_orders(w,p,list,board) end
          return true
        end
      end
    end
  end
  M.catalog=Roster.order
  M.model=Roster.model
  function M.active(s)
    return mount[s] and Sim.road_oil_active(s) and Sim.road_stock_service_active(s)
  end
  function M.quote(s,owner,dep,id)
    if not M.active(s) then return nil,"NO_OIL_INDUSTRY_AUTHORITY" end
    local meta=get(s)
    if not meta.ready(id) then return nil,"TANKER_MEDIA_NOT_AVAILABLE" end
    local span=model(s,id)
    if not (span and span.public) then return nil,"TANKER_NOT_AVAILABLE_IN_THIS_YEAR" end
    if s.stock_owned_oil_ship then return nil,"ONE_OWNED_OIL_SHIP" end
    if not owns(s,dep,owner) then return nil,"OWN_SHIP_DEPOT_REQUIRED" end
    if s.stock_owned_ferry and s.stock_owned_ferry.depot==dep or
        s.stock_coal_ship and s.stock_coal_ship.depot==dep then return nil,"SHIP_DEPOT_ALREADY_IN_USE" end
    local q=Roster.quote(id,s.stock_ship_purchase_base)
    local c=s.companies[owner]
    if c and q.price>c.cash then return nil,"NOT_ENOUGH_MONEY" end
    return q
  end
  function M.buy(s,owner,dep,id)
    local q,why=M.quote(s,owner,dep,id)
    if not q then return nil,why end
    local c=Sim.company(s,owner)
    debit(c,q.price)
    local craft={id="oil",owner=owner,depot=dep,engine=id,built=Sim.date(s),price=q.price,expense=0}
    s.stock_owned_oil_ship=craft
    return craft
  end
  function M.report(s,dock)
    if not M.active(s) then return end
    local map=get(s).net.board(s)
    local _,items=Service.bind_stations(s,{stations={}},map,function(id)return id==dock end)
    local st=items[dock]
    if not st then return end
    local inds=s.stock_oil_industries
    local covered=Catchment.build(st,Sim.W,Sim.H)
    local r=Rules.acceptance(st,covered,"oil",inds)
    r.sources={}
    for _,i in ipairs(Rules.ordered(inds)) do
      if not i.removed and Rules.output(i,"oil") then
        for _,t in ipairs(i.tiles) do
          if Catchment.contains(covered,t.x,t.z) then r.sources[#r.sources+1]=i.id;break end
        end
      end
    end
    return r
  end
  function M.start(s,owner,dep,a,b)
    if not M.active(s) then return nil,"NO_OIL_INDUSTRY_AUTHORITY" end
    local craft=s.stock_owned_oil_ship
    if not (craft and craft.owner==owner and craft.depot==dep) then return nil,"OWN_TANKER_REQUIRED" end
    local run=get(s).run
    if run.current(s) then return nil,"TANKER_ALREADY_DISPATCHED" end
    local from,to=M.report(s,a),M.report(s,b)
    if not from or #from.sources==0 then return nil,"DOCK_NEEDS_OIL_SOURCE" end
    if not to or not to.accepts then return nil,"DOCK_NEEDS_OIL_REFINERY" end
    local p,why=run.start(s,owner,dep,a,b,nil,craft.engine)
    if not p then return nil,why end
    s.stock_oil_ship_service=Service.new(craft)
    return p,"Oil tanker dispatched."
  end
  function M.run(s) return mount[s] and get(s).run end
  function M.toggle(s,owner)
    local run=M.run(s)
    local p=run and run.current(s)
    if not p or p.owner~=owner then return false,"Choose your dispatched tanker." end
    if p.failure then return false,p.failure end
    p.stopped=not p.stopped
    return true,p.stopped and "Oil tanker stopped." or "Oil tanker resumed."
  end
  function M.stations(s)
    local meta=mount[s]
    local state=s.stock_oil_ship_service
    local p=meta and meta.run.current(s)
    if not (p and state) then return end
    local map=meta.net.board(s)
    local list,by=Service.bind_stations(s,state,map,function(id) return meta.run.ordered_dock(p,id) end)
    return list,by,map
  end
  function M.day(s,pipe,first_tick)
    if not (M.active(s) and pipe and pipe.oil_ship_binding) then return end
    local meta=get(s)
    local p=meta.run.current(s)
    local state=s.stock_oil_ship_service
    if not (p and state) then return end
    local binding=pipe.oil_ship_binding
    if state.tick and state.tick<first_tick-1 then state.tick,state.post=first_tick-1,first_tick-1 end
    local opts={gradual=s.stock_gradual_loading~=false,charge_fixed=function(owner,fixed)
      local c=Sim.company(s,owner)
      local old=c.stock_money_fraction or 0
      local rem=(old-fixed%256)%256
      c.stock_money_fraction=rem
      local cost=math.floor(fixed/256)+(rem>old and 1 or 0)
      if cost>0 then
        debit(c,cost)
        local craft=s.stock_owned_oil_ship
        craft.expense=craft.expense+cost
      end
    end}
    local v=Service.bind(state,pipe,state.stations,binding.by,binding.map,opts)
    if not p.failure then
      for _,o in ipairs(p.transport_orders or {{id=p.first,cargo_order="full"},{id=p.second,cargo_order="no_load"}}) do
        local report=v.report(o.id)
        if o.cargo_order=="full" and (not report or #report.sources==0) then p.failure="OIL_SOURCE_NO_LONGER_AVAILABLE"
        elseif o.cargo_order=="no_load" and (not report or not report.accepts) then p.failure="OIL_REFINERY_NO_LONGER_AVAILABLE" end
      end
      if p.failure then p.phase="blocked" end
    end
    v.settle(s.day,s.stock_ship_running_base)
    local points={}
    local function sample()
      local pos,yaw=meta.run.pose(p)
      points[#points+1]=pos and {pos=pos,yaw=yaw} or false
    end
    sample();views[s]=points
    return {before=function(tick)
      if p.transport_cancel_full then v.cancel_full();p.transport_cancel_full=nil end
      local ready,why=v.loading(tick,p.stopped or p.phase=="blocked")
      if why then p.failure,p.phase=why,"blocked" end
      return ready
    end,after=function(tick,ready)
      if ready then
        meta.run.advance_paid(s,{
          leave=function(q,force) return v.leave(q.arrivals,tick,force) end,
          arrive=function(q)
            local order=q.transport_orders and q.transport_orders[q.transport_order_cursor.real+1]
            local policy=order and order.cargo_order or (q.last_dock==q.first and "full" or "no_load")
            local l,why=v.arrive(q.last_dock,q.arrivals,tick,q.last_berth,policy)
            return not not l,why
          end,
        })
        v.after(tick)
      end
      v.rating(tick);sample()
    end}
  end
  function M.status(s)
    local craft=s.stock_owned_oil_ship
    if not craft then return end
    local run=M.run(s)
    local p=run and run.current(s)
    local v=s.stock_oil_ship_service and s.stock_oil_ship_service.vehicle
    local model=Roster.model(craft.engine)
    return {id="oil",owner=craft.owner,cargo="oil",engine=craft.engine,name=model.name,depot=craft.depot,
      first=p and p.first,second=p and p.second,capacity=model.capacity,phase=p and p.phase or "purchased",
      onboard=v and v.units or 0,delivered=v and v.delivered or 0,revenue=v and v.revenue or 0,
      expense=craft.expense,stopped=p and p.stopped or false,visits=p and p.arrivals or 0, failure=p and p.failure}
  end
  function M.pose(s,f)
    local run=M.run(s)
    local p=run and run.current(s)
    if not p then return end
    local samples=views[s]
    if not samples or #samples<2 then return run.pose(p) end
    local x=math.max(0,math.min(1,f or 1))*(#samples-1)
    local i=math.floor(x)+1
    local a,z=samples[i],samples[i+1]
    if not (a and z) then return a and a.pos,a and a.yaw end
    local t=x%1
    local src,dst=a.pos,z.pos
    local arc=(z.yaw-a.yaw+math.pi)%(2*math.pi)-math.pi
    return {x=src.x+(dst.x-src.x)*t,y=src.y+(dst.y-src.y)*t,z=src.z+(dst.z-src.z)*t},a.yaw+arc*t
  end
  return M
end
