-- SPDX-License-Identifier: GPL-2.0-only
-- Explicit owned train handoff. Procurement is independent of the preview
-- timetable. Coal is an explicit single delivery, not passenger stock.
return function(Fleet,Roster,Run,validate_coal,validate_oil,oil_wagon_ready,validate_goods,goods_wagon_ready)
  local O={}
  local power_rules
  function O.initialize(s,cfg)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    return Fleet.initialize(s,cfg)
  end
  function O.passenger_engine(id) return Run.owned_passenger_engine(id) end
  function O.freight_engine(id)
    return Roster.freight_engine(id) and Run.owned_passenger_engine(id)
  end
  function O.pair_passenger_engine(id)
    return id~=11 and not Roster.electric_engine(id) and Run.owned_passenger_engine(id)
  end
  function O.mount_electric(Types) power_rules=Types end
  function O.railtype_mask(s,owner,Types) return Fleet.railtype_mask(s,owner,Types) end
  function O.catalog(s)
    local rows,why=Fleet.catalog(s)
    if not rows then return nil,why end
    for _,row in ipairs(rows) do
      if row.kind=="engine" then row.passenger_model_ready=Run.owned_passenger_engine(row.stock_id) end
    end
    return rows
  end
  local function missing_model(parts)
    if type(parts)~="table" then return end
    local id=parts[1]
    if id==8 and not Run.owned_passenger_engine(id) then return "JUBILEE_MODEL_NOT_AVAILABLE" end
    if id==9 and not Run.owned_passenger_engine(id) then return "GINZU_MODEL_NOT_AVAILABLE" end
    if id==10 and not Run.owned_passenger_engine(id) then return "SH_8P_MODEL_NOT_AVAILABLE" end
    if id==11 and not Run.owned_passenger_engine(id) then return "MANLEY_MODEL_NOT_AVAILABLE" end
    if (id==13 or id==14) and not Run.owned_passenger_engine(id) then return "DIESEL_MODEL_NOT_AVAILABLE" end
    if id==15 and not Run.owned_passenger_engine(id) then return "FLOSS_MODEL_NOT_AVAILABLE" end
    if id==23 and not Run.owned_passenger_engine(id) then return "SH_30_MODEL_NOT_AVAILABLE" end
    if id==24 and not Run.owned_passenger_engine(id) then return "SH_40_MODEL_NOT_AVAILABLE" end
  end
  local function mounted_hooks(hooks)
    local out={}
    for k,v in pairs(hooks or {}) do out[k]=v end
    out.oil_wagon_ready=oil_wagon_ready
    out.goods_wagon_ready=goods_wagon_ready
    out.manley_ready=function() return Run.owned_passenger_engine(11) end
    out.electric_model_ready=function(id) return Run.owned_passenger_engine(id) end
    if power_rules and not out.company_railtypes then
      out.company_railtypes=function(s,owner) return power_rules.flags(Fleet.railtype_mask(s,owner,power_rules)) end
    end
    return out
  end
  local function freight_stage(platform) return platform and (platform.coal_role or platform.oil_role or platform.goods_role) end
  function O.quote(s,owner,depot,parts,hooks)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    local q,why,index=Fleet.quote(s,owner,depot,parts,mounted_hooks(hooks))
    local missing=q and missing_model(q.stock_ids)
    if missing then return nil,missing end
    return q,why,index
  end
  function O.quote_part(s,owner,depot,stock_id,hooks)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    local q,why=Fleet.quote_part(s,owner,depot,stock_id,mounted_hooks(hooks))
    local missing=q and missing_model(q.stock_ids)
    if missing then return nil,missing end
    return q,why
  end
  function O.loose_wagons(s,owner,depot) return Fleet.loose(s,owner,depot) end
  function O.move_wagon(s,owner,depot,from,to,tail,revision,hooks)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    return Fleet.move_wagon(s,owner,depot,from,to,tail,revision,hooks)
  end
  function O.passenger_consist(unit)
    if Run.owned_passenger_consist then return Run.owned_passenger_consist(unit) end
    local id=unit.stock_ids[1]
    return Run.owned_passenger_engine(id) and
      (#unit.stock_ids==1 and id==11 or #unit.stock_ids==2 and unit.stock_ids[2]==27)
  end
  function O.commit(s,owner,quote,hooks)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    local missing=type(quote)=="table" and missing_model(quote.stock_ids)
    if missing then return nil,missing end
    return Fleet.commit(s,owner,quote,mounted_hooks(hooks))
  end
  function O.get(s,owner,id) return Fleet.get(s,owner,id) end
  function O.list(s,owner,depot) return Fleet.list(s,owner,depot) end
  function O.occupies_depot(s,id) return Fleet.occupies_depot(s,id) end
  function O.start(s,owner,id,first,second,hooks,via_tile)
    if not (s.rail_owned_service and s.rail_paid_service) then
      return false,"Enable purchased rail and the shared paid rail clock first."
    end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,hooks)
    if not unit then return false,why end
    if not O.passenger_consist(unit) then
      return false,"Choose a supported passenger consist with its original model."
    end
    local map=s.stock_rail_stations or {}
    if freight_stage(map[first]) or freight_stage(map[second]) then
      return false,"Choose passenger platforms, not dedicated freight stages."
    end
    local ok,note,run=Run.start_owned(s,owner,unit,first,second,via_tile)
    if not ok then return false,note end
    -- Use the persistent purchased unit ID, not the reusable pilot
    -- ordinal or transient commercial table's subtype-specific index.
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_order_list(s,owner,id,stations,hooks)
    if not (s.rail_owned_service and s.rail_paid_service and Run.start_owned_sequence) then
      return false,"This depot cannot give passenger orders."
    end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    local ok,note,run=Run.start_owned_sequence(s,owner,unit,stations)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_pair(s,owner,a,b,hooks)
    if not s.rail_owned_pair_enabled then return false,"Enable the paired owned passenger preview first." end
    local function prepare(spec)
      if not spec or not spec.id or not spec.first or not spec.second then return nil,"Choose both ordered platforms." end
      local unit,why=Fleet.prepare_dispatch(s,owner,spec.id,hooks)
      if not unit then return nil,why end
      if Roster.electric_engine(unit.stock_ids[1]) then return nil,"Use the single owned shuttle for electric locomotives." end
      local map=s.stock_rail_stations or {}
      if freight_stage(map[spec.first]) or freight_stage(map[spec.second]) then
        return nil,"Choose passenger platforms, not dedicated freight stages."
      end
      return {unit=unit,first=spec.first,second=spec.second}
    end
    local pa,why=prepare(a)
    if not pa then return false,why end
    local pb,note=prepare(b)
    if not pb then return false,note end
    for _,id in ipairs({a.id,b.id}) do
      local ready,reason=Fleet.can_bind_dispatch(s,owner,id,id)
      if not ready then return false,reason end
    end
    local ok,text,runs=Run.start_owned_pair(s,owner,pa,pb)
    if not ok then return false,text end
    assert(Fleet.bind_dispatch(s,owner,a.id,a.id))
    assert(Fleet.bind_dispatch(s,owner,b.id,b.id))
    return true,text,runs
  end
  function O.start_coal(s,owner,id,mine,power,hooks)
    if not validate_coal or not s.rail_coal_service then return false,"Rail Coal service is disabled." end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,hooks)
    if not unit then return false,why end
    if #unit.stock_ids~=2 or not O.freight_engine(unit.stock_ids[1]) or unit.stock_ids[2]~=29 then
      return false,"Choose a modeled locomotive and one Coal Truck."
    end
    local valid,reason=validate_coal(s,owner,mine,power)
    if not valid then return false,reason end
    local ok,note,run=Run.start_owned_coal(s,owner,unit,mine,power)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_oil(s,owner,id,wells,refinery,hooks)
    if not (validate_oil and s.rail_oil_service and oil_wagon_ready and oil_wagon_ready(s)) then
      return false,"Rail Oil service and its tanker model are required."
    end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    if #unit.stock_ids~=2 or not O.freight_engine(unit.stock_ids[1]) or unit.stock_ids[2]~=30 then
      return false,"Choose a modeled locomotive and one Oil Tanker."
    end
    local valid,reason=validate_oil(s,owner,wells,refinery)
    if not valid then return false,reason end
    local ok,note,run=Run.start_owned_oil(s,owner,unit,wells,refinery)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_goods(s,owner,id,mill,town,hooks)
    if not (validate_goods and s.rail_goods_service and goods_wagon_ready and goods_wagon_ready(s)) then
      return false,"Rail Goods service and its Goods Van model are required."
    end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    if #unit.stock_ids~=2 or not O.freight_engine(unit.stock_ids[1]) or unit.stock_ids[2]~=32 then
      return false,"Choose a modeled locomotive and one stock Goods Van."
    end
    local valid,reason=validate_goods(s,owner,mill,town)
    if not valid then return false,reason end
    local ok,note,run=Run.start_owned_goods(s,owner,unit,mill,town)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.order_state(s,owner,id)
    local unit=Fleet.get(s,owner,id)
    if not unit or unit.status~="dispatched" then return end
    return Run.order_state(s,owner,id)
  end
  function O.edit_orders(s,owner,id,revision,action,row,value)
    local unit=Fleet.get(s,owner,id)
    if not unit or unit.status~="dispatched" then return false,"Select an active owned train." end
    local view=Run.order_state(s,owner,id)
    local run=Run.current_paid(s,id)
    if view and run.freight and action=="replace" then
      local cargo=run.freight.cargo or "coal"
      local validators={coal=validate_coal,oil=validate_oil,goods=validate_goods}
      local validate=validators[cargo]
      if (row~=1 and row~=2) or type(value)~="number" or not validate then
        return false,"Choose an existing freight order and a compatible station."
      end
      local ok,note=validate(s,owner,row==1 and value or run.freight.mine,row==2 and value or run.freight.power)
      if not ok then return false,note end
    end
    return Run.edit_orders(s,owner,id,revision,action,row,value)
  end
  function O.toggle(s,owner,id)
    local unit=Fleet.get(s,owner,id)
    if not unit or unit.status~="dispatched" then return false,"Select an active owned rail fleet unit." end
    return Run.toggle_owned(s,owner,id)
  end
  function O.running(s,owner,id)
    local p=Run.current_paid(s,id)
    if not p or p.owner~=owner then return end
    local ticks=p.running_ticks_total or 0
    local finance=p.freight or p.passenger_finance or {}
    return {phase=p.phase,stopped=not not p.stopped,speed=p.speed,mass=p.consist_mass,
      passengers=p.passengers_onboard,cargo=p.freight and (p.freight.cargo or "coal") or "passenger",
      units=p.freight and p.cargo_onboard or p.passengers_onboard,running_ticks=ticks,running_year_fp=p.running_year_fp,
      running_expense=finance.expense or finance.running_expense or 0,
      charged_running_ticks=finance.charged_ticks or finance.charged_running_ticks or 0,
      running_cost_fp=finance.fixed,legacy_unbilled_running_ticks=finance.legacy_ticks,
      future_daily_rate_fp=Roster.day_running_charge(p.running_year_fp,Roster.DAY_TICKS)}
  end
  return O
end
