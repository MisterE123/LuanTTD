-- SPDX-License-Identifier: GPL-2.0-only
-- Explicit owned train handoff. Procurement is independent of the preview
-- timetable. Coal is an explicit single delivery, not passenger stock.
return function(Fleet,Roster,Run,validate_coal,validate_oil,oil_wagon_ready,validate_goods,goods_wagon_ready,profile_hooks,mail_wagon_ready)
  local O={}
  local mod=(core and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Freight=dofile(mod.."/rail_freight_kinds.lua")
  local OrderList=dofile(mod.."/openttd/rail_order_list.lua")
  local CargoOrder=dofile(mod.."/openttd/rail_order_cargo.lua")
  local Guide=dofile(mod.."/rail_guideway_profiles.lua")
  local power_rules,advanced_models
  local railtypes=setmetatable({},{__mode="k"})
  function O.initialize(s,cfg)
    if not s.rail_owned_service then return nil,"OWNED_RAIL_DISABLED" end
    return Fleet.initialize(s,cfg)
  end
  function O.passenger_engine(id) return Run.owned_passenger_engine(id) end
  function O.freight_engine(id)
    return Roster.freight_engine(id) and Run.owned_passenger_engine(id)
  end
  function O.pair_passenger_engine(id)
    return not Roster.dual_head(id) and not Roster.electric_engine(id) and Run.owned_passenger_engine(id)
  end
  function O.mount_electric(Types) power_rules=Types end
  -- Only the production asset scanner can supply this host capability.
  -- It is not a save setting or a request field.
  function O.mount_advanced(Types,ready)
    if not (Run.mount_advanced_wagon and ready) then return false end
    local mounted={}
    for _,g in ipairs(Guide.gauges) do
      local p=Guide.by_gauge[g]
      if ready[p.engine] and ready[p.passenger] and ready[p.mail] then
        assert(Run.mount_owned_model(p.engine))
        assert(Run.mount_advanced_wagon(p.passenger));assert(Run.mount_advanced_wagon(p.mail))
        for _,id in ipairs(p.stocks) do mounted[id]=true end
        if ready[p.oil] then mounted[p.oil]=true;assert(Run.mount_advanced_wagon(p.oil)) end
      end
    end
    for _,id in ipairs(Guide.extra_engines) do
      if ready[id] and mounted[Guide.by_gauge[Guide.by_engine[id].gauge].engine] then
        assert(Run.mount_owned_model(id));mounted[id]=true
      end
    end
    if not next(mounted) then return false end
    advanced_models,power_rules=mounted,Types
    return true
  end
  function O.railtype_mask(s,owner,Types)
    -- There are no company-exclusive engines in this adapter yet. The
    -- existing public-sale table is the same for all current companies.
    -- Only cache the scalar answer, never availability on the saved world.
    if not s.companies[owner] then return 0 end
    local fleet,day,electric=s.stock_rail_fleet,s.day,s.stock_electrification
    local old=railtypes[s]
    if old and old.fleet==fleet and old.day==day and old.electric==electric and
        old.types==Types and old.advanced==advanced_models then return old.mask end
    local mask=Fleet.railtype_mask(s,owner,Types,advanced_models)
    railtypes[s]={fleet=fleet,day=day,electric=electric,types=Types,advanced=advanced_models,mask=mask}
    return mask
  end
  function O.catalog(s)
    local rows,why=Fleet.catalog(s,advanced_models)
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
    if id==12 and not Run.owned_passenger_engine(id) then return "DASH_MODEL_NOT_AVAILABLE" end
    if (id==13 or id==14) and not Run.owned_passenger_engine(id) then return "DIESEL_MODEL_NOT_AVAILABLE" end
    if id==15 and not Run.owned_passenger_engine(id) then return "FLOSS_MODEL_NOT_AVAILABLE" end
    if id==22 and not Run.owned_passenger_engine(id) then return "SH_125_MODEL_NOT_AVAILABLE" end
    if id==23 and not Run.owned_passenger_engine(id) then return "SH_30_MODEL_NOT_AVAILABLE" end
    if id==24 and not Run.owned_passenger_engine(id) then return "SH_40_MODEL_NOT_AVAILABLE" end
    if id==25 and not Run.owned_passenger_engine(id) then return "TIM_MODEL_NOT_AVAILABLE" end
    if id==26 and not Run.owned_passenger_engine(id) then return "ASIASTAR_MODEL_NOT_AVAILABLE" end
  end
  local function mounted_hooks(hooks)
    local out={}
    for k,v in pairs(hooks or {}) do out[k]=v end
    out.mail_wagon_ready=mail_wagon_ready
    out.oil_wagon_ready=oil_wagon_ready
    out.goods_wagon_ready=goods_wagon_ready
    out.profile_wagon_ready=profile_hooks and profile_hooks.active
    out.dmu_ready=function(id) return Run.owned_passenger_engine(id) end
    out.sh_125_ready=function() return Run.owned_passenger_engine(22) end
    out.electric_model_ready=function(id) return Run.owned_passenger_engine(id) end
    out.mounted_advanced=advanced_models
    if power_rules and not out.company_railtypes then
      out.company_railtypes=function(s,owner) return power_rules.flags(O.railtype_mask(s,owner,power_rules)) end
    end
    return out
  end
  local freight_stage=Freight.role
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
      (#unit.stock_ids==1 and Roster.passenger_dmu(id) or #unit.stock_ids==2 and unit.stock_ids[2]==27)
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
  function O.mixed_consist(s,owned)
    return Run.owned_mixed_consist and Run.owned_mixed_consist(s,owned) or false
  end
  function O.start_mixed(s,owner,id,first,second,hooks)
    if not s.rail_mixed_town_service then return false,"Mixed town rail is not mounted." end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    local ok,note,run=Run.start_owned_mixed(s,owner,unit,first,second)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_mail(s,owner,id,first,second,hooks)
    if not (mail_wagon_ready and mail_wagon_ready(s)) then return false,"Rail Mail service is not mounted." end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    local ok,note,run=Run.start_owned_mail(s,owner,unit,first,second)
    if not ok then return false,note end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,note,run
  end
  function O.start_order_list(s,owner,id,stations,hooks)
    if not (s.rail_owned_service and s.rail_paid_service and Run.start_owned_sequence) then
      return false,"This depot cannot give passenger orders."
    end
    local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
    if not unit then return false,why end
    if unit.stock_ids[2]==28 and #unit.stock_ids==2 and not (mail_wagon_ready and mail_wagon_ready(s)) then
      return false,"Rail Mail service is not mounted."
    end
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
    if not Run.owned_oil_consist(unit) then
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
  function O.profile_consist(s,unit,cargo)
    return Run.owned_profile_consist and Run.owned_profile_consist(s,unit,cargo) or false
  end
  for _,key in ipairs(Freight.profile_order) do
    local cargo,p=key,Freight.profiles[key]
    O["start_"..cargo]=function(s,owner,id,first,second,hooks)
      if not (profile_hooks and profile_hooks.active(s,cargo)) then return false,"Rail "..p.name.." service is unavailable." end
      local unit,why=Fleet.prepare_dispatch(s,owner,id,mounted_hooks(hooks))
      if not unit then return false,why end
      if not O.profile_consist(s,unit,cargo) then
        return false,"Choose a modeled locomotive with "..(p.max_wagons and "one or two matching " or "one ")..
          Roster.entry(p.wagon).name..(p.max_wagons and "s." or ".")
      end
      local valid,reason=profile_hooks.validate(s,cargo,owner,first,second)
      if not valid then return false,reason end
      local ok,note,run=Run.start_owned_profile(s,owner,unit,first,second,cargo)
      if not ok then return false,note end
      assert(Fleet.bind_dispatch(s,owner,id,id))
      return true,note,run
    end
  end
  local function parked(s,owner,id,depot)
    local r=Fleet.get(s,owner,id)
    local tile=depot and s.tiles[depot]
    if r and tile and tile.owner==owner and tile.rail_depot_dir~=nil and r.depot==depot and r.status=="depot"
        and Run.owned_town_consist and Run.owned_town_consist(s,r) then return r end
  end
  function O.can_edit_draft(s,owner,id,depot) return parked(s,owner,id,depot)~=nil end
  local function draft_revision(unit)
    return "rail-parked:"..(unit.order_draft and unit.order_draft.revision or 0)
  end
  local function snapshot(s,owner,r)
    if r.status=="dispatched" then return Run.copyable_orders(s,owner,r.id) end
    if r.order_draft and #r.order_draft.orders>0 then return r.order_draft.orders,draft_revision(r) end
  end
  local function copied(s,owner,src,dst)
    local orders,revision=snapshot(s,owner,src)
    if not orders or #orders==0 then return nil,"The source train has no compatible orders." end
    local d=dst.order_draft or {orders={},cursor={real=0,implicit=0}}
    local clone,cursor=OrderList.copy(orders,d.orders,d.cursor,function(o) return Run.usable_town_order(s,owner,o) end)
    if not clone then return nil,cursor end
    return clone,cursor,revision
  end
  function O.copy_order_sources(s,owner,id,depot)
    local dst=parked(s,owner,id,depot)
    if not dst then return nil,"Choose a parked passenger, Mail or Coach/Mail train in this depot." end
    local sources={}
    for _,u in ipairs(Fleet.list(s,owner)) do
      if u.id~=id and Run.owned_town_consist(s,u) then
        local orders,_,revision=copied(s,owner,u,dst)
        if orders then
          sources[#sources+1]={id=u.id,label="Train "..u.unit_number,cargo="Town rail",count=#orders,revision=revision}
        end
      end
    end
    return {vehicle=id,label="Train "..dst.unit_number,count=dst.order_draft and #dst.order_draft.orders or 0,
      revision=draft_revision(dst),sources=sources}
  end
  function O.copy_orders(s,owner,id,depot,source,source_revision,target_revision)
    local dst=parked(s,owner,id,depot)
    local src=source~=id and Fleet.get(s,owner,source)
    if not (dst and src and Run.owned_town_consist(s,src)) then return false,"Choose a different compatible owned train." end
    local orders,cursor,rev=copied(s,owner,src,dst)
    if not orders then return false,cursor end
    if rev~=source_revision or draft_revision(dst)~=target_revision then
      return false,"The orders changed. Review the latest lists and try again."
    end
    local ok,note=Fleet.write_order_draft(s,owner,id,depot,orders,cursor)
    return ok,ok and ("Copied %d orders. Open the train to review and start service."):format(#orders) or note
  end
  function O.start_draft_orders(s,owner,id,depot,revision)
    local dst=parked(s,owner,id,depot)
    local draft=dst and dst.order_draft
    if not draft or revision~=draft_revision(dst) then return false,"Review the latest orders before starting this train." end
    local unit,note=Fleet.prepare_dispatch(s,owner,id,mounted_hooks())
    if not unit then return false,note end
    local ok,why,run=Run.start_owned_orders(s,owner,unit,draft.orders)
    if not ok then return false,why end
    assert(Fleet.bind_dispatch(s,owner,id,id))
    return true,why,run
  end
  O.start_copied_orders=O.start_draft_orders
  function O.order_state(s,owner,id)
    local unit=Fleet.get(s,owner,id)
    if not unit then return end
    if unit.status=="dispatched" then return Run.order_state(s,owner,id) end
    if not parked(s,owner,id,unit.depot) then return nil,"Set up service from this train’s depot." end
    local d=unit.order_draft or {orders={}}
    local out={orders={},cargo={},stops=Run.order_destinations(s,owner,unit.depot),
      depot=unit.depot,revision=draft_revision(unit),parked=true,
      capabilities={add=true,move=true,remove=true,replace=true,load=true,unload=true,nonstop=true}}
    local manual=OrderList.manual_rows(d.orders)
    local ready=#manual>=2
    for i,o in ipairs(manual) do
      local previous=manual[i==1 and #manual or i-1]
      ready=ready and o.station~=previous.station
    end
    for i,o in ipairs(d.orders) do
      ready=ready and Run.usable_town_order(s,owner,o)
      out.orders[i]=o.station
      out.cargo[i]={load=o.load_type or 0,unload=o.unload_type or 0,nonstop=o.nonstop or 0,
        automatic=o.kind=="implicit",summary=CargoOrder.summary(o)}
    end
    out.can_start=not not ready
    out.reason=ready and "Orders saved. The train stays in the depot until you start service."
      or "Add at least two distinct stops. Consecutive stops, including the return, must differ."
    return out
  end
  local function edit_draft(s,owner,unit,revision,action,row,value)
    if not parked(s,owner,unit.id,unit.depot) then return false,"Choose a compatible parked train." end
    if revision~=draft_revision(unit) then return false,"Orders changed. Review the latest list and try again." end
    local orders,cursor={}, {real=0,implicit=0}
    if unit.order_draft then
      local d=unit.order_draft
      orders,cursor=OrderList.copy(d.orders,d.orders,d.cursor,function() return true end)
    end
    local slot=type(row)=="number" and row%1==0 and row-1 or nil
    local changed
    if slot and orders[slot+1] and orders[slot+1].kind=="implicit" and action~="remove" then
      return false,"An automatic stop cannot be edited as a manual order."
    end
    if action=="nonstop" and slot and orders[slot+1] then
      changed=CargoOrder.change_nonstop(orders[slot+1],value)
    elseif action=="add" or action=="replace" then
      local o=Run.station_order(value)
      if not Run.usable_town_order(s,owner,o) then return false,"Choose a compatible owned rail station." end
      if action=="add" then changed=OrderList.insert(orders,cursor,slot or #orders,o)
      elseif slot and orders[slot+1] and orders[slot+1].station~=value then
        orders[slot+1].station=value
        changed=true
      end
    elseif action=="move" and slot and type(value)=="number" and value%1==0 then
      changed=OrderList.move(orders,cursor,slot,value-1)
    elseif action=="remove" and slot then
      changed=OrderList.delete(orders,cursor,slot)
    elseif (action=="load" or action=="unload") and slot and orders[slot+1] then
      changed=CargoOrder.change(orders[slot+1],action,value)
    end
    if not changed then return false,"Choose a valid order edit." end
    return Fleet.write_order_draft(s,owner,unit.id,unit.depot,orders,cursor)
  end
  function O.edit_orders(s,owner,id,revision,action,row,value)
    local unit=Fleet.get(s,owner,id)
    if unit and unit.status=="depot" then return edit_draft(s,owner,unit,revision,action,row,value) end
    if not unit or unit.status~="dispatched" then return false,"Select an active owned train." end
    local view=Run.order_state(s,owner,id)
    local run=Run.current_paid(s,id)
    if view and run.freight and action=="replace" then
      local cargo=run.freight.cargo or "coal"
      local validators={coal=validate_coal,oil=validate_oil,goods=validate_goods}
      local validate=validators[cargo]
      if not validate and Freight.profiles[cargo] and profile_hooks then
        validate=function(s,owner,first,second) return profile_hooks.validate(s,cargo,owner,first,second) end
      end
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
      passengers=p.passengers_onboard,cargo=p.freight and (p.freight.cargo or "coal") or p.town_parts and "mixed" or p.stock_wagon==28 and "mail" or "passenger",
      units=p.freight and p.cargo_onboard or p.town_parts and ((p.passengers_onboard or 0)+(p.mail_onboard or 0)) or p.stock_wagon==28 and p.mail_onboard or p.passengers_onboard,running_ticks=ticks,running_year_fp=p.running_year_fp,
      running_expense=finance.expense or finance.running_expense or 0,
      charged_running_ticks=finance.charged_ticks or finance.charged_running_ticks or 0,
      running_cost_fp=finance.fixed,legacy_unbilled_running_ticks=finance.legacy_ticks,
      future_daily_rate_fp=Roster.day_running_charge(p.running_year_fp,Roster.DAY_TICKS)}
  end
  return O
end
