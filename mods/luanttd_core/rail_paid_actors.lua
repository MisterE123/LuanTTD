-- SPDX-License-Identifier: GPL-2.0-only
-- Multiple real stock coaches on one passenger station clock. Actor
-- rows all use the same loading service as the original paid shuttle.
-- Dispatch remains the only owner of movement, visits and wagon poses.
return function(Service,key)
  local base=core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
  local CargoOrder=dofile(base.."/openttd/rail_order_cargo.lua")
  local Roster=dofile(base.."/openttd/rail_roster.lua")
  local A={}

  function A.gather(Rail,s)
    if not Rail then return {} end
    local found=Rail.paid_passengers and Rail.paid_passengers(s) or {Rail.current_paid(s)}
    local out,seen={},{}
    for _,r in ipairs(found) do
      if not r.freight then
        local id=key(r.paid_clock)
        assert(not seen[id],"Duplicate paid rail actor")
        out[#out+1]=r
        seen[id]=true
      end
    end
    return out
  end

  function A.current(actors,id)
    if not id then return actors[1] end
    for _,r in ipairs(actors) do if r.fleet_id==id then return r end end
  end

  -- State.rail_serial is the old singleton representation; migrate its
  -- identity, cargo row, loading order and clock in place. Withdrawal is
  -- only for an actor actually missing from the physical dispatcher.
  function A.reconcile(state,actors,ctx,first_tick,build_year,withdraw)
    local service=state.service
    local saved=state.rail_serials
    if not saved then
      saved={}
      if state.rail_serial~=nil then saved[state.rail_serial]=true end
    end
    local expected={}
    for _,r in ipairs(actors) do expected[key(r.paid_clock)]=r end
    local stale={}
    for id in pairs(saved) do
      if not expected[id] then stale[#stale+1]=id end
    end
    table.sort(stale)
    for _,id in ipairs(stale) do
      local v=assert(service.vehicles[id],"Missing saved commercial train")
      local events={}
      assert(Service.withdraw_vehicle(service,id,first_tick,ctx,events))
      withdraw(events,v.owner)
    end
    local live={}
    for _,r in ipairs(actors) do
      local id=key(r.paid_clock)
      local dmu=Roster.passenger_dmu(r.stock_engine)
      if not saved[id] then
        Service.vehicle(service,{id=id,mode="rail",owner=r.owner,length=r.total_length,
          cargo=r.town_parts and "mixed" or r.stock_wagon==28 and "mail" or "passenger",wagon=r.stock_wagon,town_parts=r.town_parts,
          engine=dmu and r.stock_engine or nil,coach=dmu and r.stock_wagon==27 or nil,
          dual_head=r.dual_head and not dmu,passenger_coaches=r.passenger_coaches,speed=r.max_track_speed,built=build_year(r)})
      else
        local v=service.vehicles[id]
        assert(v and v.owner==r.owner and v.mode=="rail" and v.total_length==r.total_length,
          "Saved train and paid passenger row disagree")
        assert(v.engine==(dmu and r.stock_engine or nil),"Saved train body schema disagrees with paid actor")
        if dmu then v.linked_heads=true end
        assert((v.cargo=="mail")== (not r.town_parts and r.stock_wagon==28),"Saved train Mail body disagrees with the purchased consist")
        assert(not not v.town_mixed==not not r.town_parts,"Saved town consist mode disagrees")
        if r.town_parts then
          for i,body in ipairs(r.town_parts) do
            local saved_part=v.carrying_parts[i]
            assert(saved_part.body_id==body.body_id and saved_part.stock==body.stock and saved_part.part==body.index,
              "Saved physical wagon identity disagrees with the train")
          end
        end
        if v.carrying_parts then
          assert(#v.carrying_parts==(r.town_parts and #r.town_parts or r.passenger_coaches or (r.stock_wagon==27 and 3 or 2)),
            "Saved physical railway formation disagrees")
        end
      end
      live[id]=true
    end
    state.rail_serials=live
    state.rail_serial=actors[1] and key(actors[1].paid_clock) or nil -- compatibility read of first actor
  end

  function A.controls(state,actors)
    local service=state.service
    for _,r in ipairs(actors) do
      local train=assert(service.vehicles[key(r.paid_clock)])
      train.stopped=r.phase=="blocked" or r.stopped or nil
      train.broken=r.breakdown or nil
      if r.load_type_update~=nil then
        local full,no_load,any=CargoOrder.load_flags(r.load_type_update)
        Service.update_load_type(train,full,no_load,any)
        r.load_type_update=nil
      end
    end
  end

  function A.callbacks(state,ready,ctx,tick,events)
    local service=state.service
    local function id(run)
      local n=key(run.paid_clock)
      assert(state.rail_serials[n],"Unregistered paid rail movement actor")
      return n
    end
    return {
      crash=function(r)
        local n=id(r)
        -- Remove pending platform loading, do not pay passenger fares
        -- for cargo destroyed in the train, and retain the stopped row
        -- until the usual vehicle roster reconciliation.
        local v=service.vehicles[n]
        if v then
          Service.crash_rail(service,n,tick,ctx,events)
        end
      end,
      leave=function(r,skip_order)
        local n=id(r)
        local row=assert(service.vehicles[n])
        return (skip_order or ready[n]) and Service.leave(service,n,row.visit,tick,ctx,events,skip_order) or false
      end,
      passengers=function(r)
        local v=service.vehicles[id(r)]
        if v.town_mixed then
          local riders=0
          for _,body in ipairs(v.carrying_parts) do if body.cargo=="passenger" then riders=riders+body.units end end
          return riders
        end
        return v.cargo=="passenger" and v.units or 0
      end,
      cargo_count=function(r)
        local v=service.vehicles[id(r)]
        local p=v.carrying_parts
        if p and (r.passenger_coaches or r.town_parts) then
          local counts={}
          for i,b in ipairs(p) do counts[i]=b.units end
          return v.units,nil,nil,nil,counts
        end
        if p then return v.units,p[1].units,p[#p].units,#p==3 and p[2].units or nil end
        return v.units
      end,
      arrive=function(r,wagon_tile,platform_tiles,cargo_tiles)
        local orders=r.paired or r.shuttle
        if not orders then return nil,"MISSING_PASSENGER_ORDERS" end
        local opts={platform_tiles=platform_tiles,cargo_tiles=cargo_tiles}
        if cargo_tiles then wagon_tile=cargo_tiles[1] end
        local current=r.orders and r.orders[r.order_cursor.real+1]
        if current and current.station==r.station then CargoOrder.arrival(current,opts) end
        if r.paired then
          if r.station==orders.second then opts.action="unload"
          elseif r.station~=orders.first then return nil,"UNORDERED_PASSENGER_PLATFORM" end
        end
        return Service.begin(service,id(r),key(r.station),orders.arrivals,wagon_tile,opts,tick,ctx,events)
      end,
    }
  end

  return A
end
