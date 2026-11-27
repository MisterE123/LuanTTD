-- SPDX-License-Identifier: GPL-2.0-only
-- Binds the dry ship's default Goods cargo to the one live industry
-- ledger. Route, hull motion and berth rules remain in the stock driver.
return function(Sim,Service,Timber,Catchment,debit)
  local M={}
  local registries={"timber","farm","oil","heavy","bank"}
  function M.enabled(s)
    for _,kind in ipairs(registries) do
      if Sim["road_"..kind.."_active"](s) then return true end
    end
    return false
  end
  function M.stations(s,run,net)
    local voyage=run and run.current(s)
    local ledger=s.stock_goods_ship_service
    if not (voyage and ledger and M.enabled(s)) then return end
    local map=net.board(s)
    local list,by=Service.bind_stations(s,ledger,map,function(id)
      return run.ordered_dock(voyage,id)
    end)
    return list,{by=by,map=map}
  end
  function M.install(s,craft)
    s.stock_goods_ship_service=Service.new(craft)
  end
  function M.report(s,net,id)
    if not M.enabled(s) then return end
    local _,st=Service.bind_stations(s,{stations={}},net.board(s),function(i)return i==id end)
    st=st[id]
    if not st then return end
    local cover=Catchment.build(st,Sim.W,Sim.H,s.stock_modified_catchment)
    local function house(x,z)
      local tile=s.tiles[Sim.id(x+1,z+1)]
      return tile and tile.house and tile.source_house or nil
    end
    local accepted=Timber.acceptance(st,cover,"goods",{},house)
    local sources={}
    for _,kind in ipairs(registries) do
      if Sim["road_"..kind.."_active"](s) then
        for key,i in pairs(s["stock_"..kind.."_industries"] or {}) do
          local output=i.produced or {}
          local provides=output.cargo=="goods"
          if not output.cargo then
            for _,p in ipairs(output) do if p.cargo=="goods" then provides=true;break end end
          end
          if not i.removed and provides then
            for _,t in ipairs(i.tiles) do
              if Catchment.contains(cover,t.x,t.z) then sources[#sources+1]=key;break end
            end
          end
        end
      end
    end
    table.sort(sources)
    accepted.sources=sources
    return accepted
  end
  function M.day(s,Run,pipe,first_tick,live,sample,emit)
    local b=pipe and pipe.goods_ship_binding
    local state=s.stock_goods_ship_service
    local p=Run.current(s)
    if not (b and state and p) then return end
    if state.tick and state.tick<first_tick-1 then state.tick,state.post=first_tick-1,first_tick-1 end
    local craft=s.stock_coal_ship
    local D=Service.bind(state,pipe,state.stations,b.by,b.map,{
      gradual=s.stock_gradual_loading~=false,
      charge_fixed=function(owner,fixed)
        local c=Sim.company(s,owner)
        local old=c.stock_money_fraction or 0
        local rem=(old-fixed%256)%256
        c.stock_money_fraction=rem
        local whole=math.floor(fixed/256)+(rem>old and 1 or 0)
        if whole>0 then
          debit(c,whole,"ship_run")
          craft.expense=(craft.expense or 0)+whole
          if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,craft,-whole) end
        end
      end,
      emit=function(kind,st,v,data)
        if kind=="board" then v.boarded=(v.boarded or 0)+data.units end
        if kind=="fare" then
          v.last_fare=data.amount
          if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,craft,data.amount) end
        end
        emit({kind=kind,cargo="goods",mode="ship",station=st.id,station_local=st.host_id,
          owner=v.owner,vehicle=v.id,day=s.day,units=data.units,amount=data.amount})
      end,
    })
    D.settle(s.day,s.stock_ship_running_base)
    if not p.failure then
      for _,o in ipairs(p.transport_orders or {{id=p.first,cargo_order="full"},{id=p.second,cargo_order="no_load"}}) do
        local report=D.report(o.id)
        if o.cargo_order=="full" and (not report or #report.sources==0) then
          p.failure="GOODS_SOURCE_NO_LONGER_AVAILABLE"
        elseif o.cargo_order=="no_load" and (not report or not report.accepts) then
          p.failure="GOODS_DESTINATION_NO_LONGER_ACCEPTS"
        end
      end
      if p.failure then p.phase="blocked" end
    end
    return {
      before=function(tick)
        if p.transport_cancel_full then D.cancel_full();p.transport_cancel_full=nil end
        local ready,why=D.loading(tick,p.stopped or p.phase=="blocked",p.dock_forced_leave)
        if why then p.failure,p.phase=why,"blocked" end
        return ready
      end,
      after=function(tick,ready)
        if ready then
          Run.advance_paid(s,{
            leave=function(q,force) return D.leave(q.arrivals,tick,force) end,
            arrive=function(q)
              local o=q.transport_orders and q.transport_orders[q.transport_order_cursor.real+1]
              local policy=o and o.cargo_order or (q.last_dock==q.first and "full" or "no_load")
              local arrived,why=D.arrive(q.last_dock,q.arrivals,tick,q.last_berth,policy)
              return not not arrived,why
            end,
          })
          D.after(tick)
        end
        D.rating(tick)
        if not live then sample() end
      end,
    }
  end
  return M
end
