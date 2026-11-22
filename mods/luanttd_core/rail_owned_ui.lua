-- Native depot transaction/panel for the real purchased steam consist.
-- Financial and motion state is owned by the stock depot/dispatch adapters.
return function(api,status)
  local S=api.s
  local U={}
  local panels,orders={},{}
  local form="luanttd_core:rail_fleet"
  local esc=core.formspec_escape
  local model_short={[0]="Kirby",[8]="Jubilee",[9]="Ginzu A4",[10]="SH 8P",[11]="Manley–Morel",[15]="Floss 47",[23]="SH '30'",[24]="SH '40'"}
  local orderable={{id=8,key="purchase_jubilee"},{id=9,key="purchase_a4"},{id=10,key="purchase_sh_8p"},{id=11,key="purchase_manley",dmu=true},{id=15,key="purchase_floss"},
    {id=23,key="purchase_sh_30",electric=true},{id=24,key="purchase_sh_40",electric=true}}
  local function money(n) return "$"..string.format("%d",math.floor(n)) end
  local function litres(units)
    return ("%.0f"):format((units or 0)*1000):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","").." L"
  end
  local commercial={
    oil={wagon=30,title="Oil",noun="oil",source="Oil Wells",sink="Oil Refinery",unit=litres,
      name="Kirby Paul Tank + 30,000 L Oil Tanker",short="Kirby + Oil Tanker",parked="Parked at refinery",
      tip="Rail Freight: designate an Oil Wells loader and an Oil Refinery unloader before ordering this train."},
    goods={wagon=32,title="Goods",noun="Goods",source="Sawmill",sink="town Goods",sink_state="Unloading in town",
      unit=function(n) return string.format("%d crates",n or 0) end,
      name="Kirby Paul Tank + 25-crate Goods Van",short="Kirby + Goods Van",parked="Parked in town",
      tip="Rail Freight: designate a Sawmill loading platform and a town Goods unloading platform."},
  }
  local function cargo_of(u)
    local id=u.stock_ids[2]
    return id==30 and "oil" or id==32 and "goods" or nil
  end
  local function available(cargo) return api["rail_"..cargo.."_tools"] end
  local function can_order(u,cargo)
    return available(cargo) and api.rail_owned["start_"..cargo] and #u.stock_ids==2 and u.stock_ids[1]==0
  end
  local function commercial_status(u,cargo)
    local get=api.Sim["rail_"..cargo.."_status"]
    local c=get and get(S)
    if c and c.fleet_id==u.id and (not c.owner or c.owner==u.owner) then return c end
  end
  local errors={
    RAIL_FLEET_UNAVAILABLE="The stock rail roster hasn't started yet.",
    RAIL_VEHICLE_NOT_AVAILABLE="This stock locomotive is not currently available.",
    JUBILEE_MODEL_NOT_AVAILABLE="This installation is missing the Jubilee model.",
    GINZU_MODEL_NOT_AVAILABLE="This installation is missing the Ginzu 'A4' model.",
    SH_8P_MODEL_NOT_AVAILABLE="This installation is missing the SH '8P' model.",
    MANLEY_MODEL_NOT_AVAILABLE="This installation is missing the Manley–Morel DMU model.",
    FLOSS_MODEL_NOT_AVAILABLE="This installation is missing the Floss '47' model.",
    SH_30_MODEL_NOT_AVAILABLE="This installation is missing the SH '30' electric model.",
    SH_40_MODEL_NOT_AVAILABLE="This installation is missing the SH '40' electric model.",
    OIL_MODEL_NOT_AVAILABLE="This installation is missing the stock Oil Tanker model.",
    RAIL_OIL_MODEL_NOT_AVAILABLE="This installation is missing the stock Oil Tanker model.",
    RAIL_VEHICLE_NOT_MOUNTED="This train is not available in this workbench.",
    OWNED_RAIL_DISABLED="Turn on purchased rail in this world's settings.",
    INVALID_OWNED_DEPOT="Choose a rail depot owned by your company.",
    INCOMPATIBLE_DEPOT_RAIL="The depot does not supply power to that locomotive.",
    STALE_RAIL_FLEET_QUOTE="The depot or ledger changed. Review the new price.",
    NOT_ENOUGH_MONEY="Your company cannot afford this train.",
    NOT_ENOUGH_CASH="Your company cannot afford this train.",
  }
  local function message(why)
    return errors[why] or tostring(why or "The stock rail command did not go through.")
  end
  local function owned_depot(n,id)
    local t=id and S.tiles[id]
    return t and t.rail_depot_dir~=nil and t.owner==n
  end
  local function stage(q)
    if q.pending then return "Final platform selected. Choose Dispatch to start, or pick a different platform." end
    if q.pair then
      local a=q.choices[q.index]
      local tag="Train "..q.index..": "
      if not a.id then return tag.."click an owned depot with exactly one staged passenger train." end
      if not a.first then return tag.."click its first passenger platform." end
      return tag.."click its last passenger platform."
    end
    if q.coal then
      return q.first and "Click the designated power-station unloading platform." or "Click the designated coal mine loading platform."
    end
    if q.cargo then
      local profile=commercial[q.cargo]
      return q.first and "Click your designated "..profile.sink.." unloading platform." or
        "Click your designated "..profile.source.." loading platform first."
    end
    if q.first and api.rail_build and api.rail_build.quote_waypoint then
      return q.via_tile and "Waypoint selected. Pick the second platform." or
        "Click a waypoint to route through it, or click the second platform."
    end
    return q.first and "Click the second owned rail platform." or "Click the first owned rail platform."
  end
  function U.open(p,id,note)
    local n=p:get_player_name()
    if not owned_depot(n,id) then return false end
    local owned=api.rail_owned
    local panel={depot=id}
    panels[n]=panel
    local catalogue={}
    for _,row in ipairs(owned.catalog and owned.catalog(S) or {}) do
      if row.passenger_model_ready then catalogue[row.stock_id]=row end
    end
    local alternatives={}
    if api.rail_coal_tools then alternatives[1]={key="purchase_coal",ids={0,29},name="Kirby Paul Tank + 30-ton coal wagon"} end
    for _,cargo in ipairs({"oil","goods"}) do
      local f=commercial[cargo]
      if available(cargo) then
        alternatives[#alternatives+1]={key="purchase_"..cargo,cargo=cargo,ids={0,f.wagon},name=f.name,tip=f.tip}
      end
    end
    for _,design in ipairs(orderable) do
      local row=catalogue[design.id]
      if row and (not row.availability or row.availability.public) and
          (not design.electric or (api.electric_tools and S.tiles[id].rail_type==1)) then
        alternatives[#alternatives+1]={key=design.key,ids=design.dmu and {design.id} or {design.id,27},
          name=design.dmu and model_short[design.id].." DMU" or model_short[design.id].." + coach",
          tip=design.dmu and row.name..": two powered bodies, 76 seats."
            or row.name.." with a 40-seat passenger carriage.",
          speed=row.speed}
        if design.dmu then
          alternatives[#alternatives+1]={key="purchase_manley_coach",ids={design.id,27},
            name=model_short[design.id].." + coach",speed=row.speed,
            tip=row.name.." with two powered bodies plus an intermediate carriage, 116 seats."}
        end
      end
    end
    local extras=#alternatives
    local height=math.max(0,extras-1)*.65
    local b={("formspec_version[7]size[10,%g]bgcolor[#152334;false]"):format(7.2+height),
      "style_type[button;bgimg=bl_button.png;bgimg_middle=6;border=false;textcolor=#E5ECEA]",
      "style_type[label;textcolor=#E5ECEA]"}
    local function lab(x,y,text) b[#b+1]=("label[%g,%g;%s]"):format(x,y,esc(text)) end
    local function button(y,key,text,x,w)
      b[#b+1]=("button[%g,%g;%g,.58;%s;%s]"):format(x or .42,y,w or 9.16,key,esc(text))
    end
    local x,z=api.Sim.xy(id)
    lab(.42,.45,("%s  ·  %d,%d"):format(S.tiles[id].rail_type==1 and "Electric rail depot" or "Rail depot",x,z))
    local units=owned.list(S,n,id)
    local limit=extras>0 and 2 or 3
    local q,why
    if #units<limit then q,why=owned.quote(S,n,id,{0,27})
    else why="This preview's depot list is full." end
    if q then
      panel.quote=q
      lab(.42,1.04,"Temperate stock fleet  ·  Kirby 64 km/h  ·  40-seat carriage")
      button(1.50,"purchase","Buy Kirby Paul Tank + passenger carriage   /   "..money(q.price))
    else
      lab(.42,1.14,why=="RAIL_VEHICLE_NOT_AVAILABLE" and "Kirby Paul Tank is not on sale this year." or message(why))
    end
    panel.alternatives={}
    if #units<limit then
      for i,spec in ipairs(alternatives) do
        local offer,why=owned.quote(S,n,id,spec.ids)
        local y=2.14+(i-1)*.65
        if offer then
          panel.alternatives[spec.key]=offer
          local speed=spec.speed and ("   /   "..spec.speed.." km/h") or ""
          button(y,spec.key,"Buy "..spec.name..speed.."   /   "..money(offer.price))
          if spec.tip then b[#b+1]="tooltip["..spec.key..";"..esc(spec.tip).."]" end
        elseif spec.cargo then
          lab(.42,y+.26,commercial[spec.cargo].title..": "..message(why))
        end
      end
    end
    for i=1,math.min(#units,limit) do
      local u=units[i]
      panel["unit_"..u.id]=u.id
      local shift=2.27+extras*.65+(i-1)*.86
      local run=owned.running(S,n,u.id)
      local coal=u.stock_ids[2]==29
      local cargo=cargo_of(u)
      local f=cargo and commercial[cargo]
      if f and u.status=="dispatched" then
        local c=commercial_status(u,cargo)
        lab(.42,shift,("%s train %d  ·  %s aboard  ·  %s delivered"):format(
          f.title,u.unit_number,f.unit(c and c.onboard),f.unit(c and c.delivered)))
        local state=not available(cargo) and "Disabled in settings" or not c and f.title.." service status unavailable" or
          c.finished and f.parked or c.failure and "Blocked" or c.paused and "Disabled in settings" or
          run and run.stopped and "Stopped" or c.loading and c.last_platform==c.mine and "Loading at "..f.source or
          c.loading and c.last_platform==c.power and (f.sink_state or "Unloading at "..f.sink) or "In service"
        lab(.42,shift+.38,state.."   /   "..money(c and c.fare or 0).." earned   /   "..
          money(c and c.running_expense or run and run.running_expense or 0).." operating costs")
        if available(cargo) and run and c and not (c.finished or c.paused or c.failure) then
          button(shift-.03,"unit_"..u.id,(run.stopped and "Resume " or "Stop ")..f.noun.." train",6.8,2.78)
        end
      elseif coal and u.status=="dispatched" then
        local c=api.Sim.rail_coal_status and api.Sim.rail_coal_status(S)
        -- The runtime accessor is world-wide; don't attach another
        -- company's status (or a different fleet ID) to this receipt.
        if c and c.fleet_id~=u.id then c=nil end
        local income=c and c.fare or 0
        local esp=run and run.running_expense or c and c.running_expense or 0
        lab(.42,shift,("Train %d  ·  %d t aboard  ·  %d t delivered"):format(
          u.unit_number,c and c.onboard or 0,c and c.delivered or 0))
        local state=c and c.finished and "Parked" or c and c.failure and "Blocked" or c and c.paused and "Disabled in settings"
          or run and run.stopped and "Stopped" or "In service"
        lab(.42,shift+.38,state.."   /   "..money(income).." earned   /   "..money(esp).." operating costs")
        if run and c and not (c.finished or c.paused or c.failure) then
          button(shift-.03,"unit_"..u.id,run.stopped and "Resume coal train" or "Stop coal train",6.8,2.78)
          if c.repeating and api.rail_dispatch_controller then
            panel.park={id=u.id,on=not c.parking}
            button(4.95+height,"park_coal",c.parking and "Keep repeating after this delivery" or "Park after the next power station delivery")
          end
        end
      elseif run then
        local paid=api.Sim.rail_paid_status(S,u.id)
        local model=model_short[u.stock_ids[1]] or "Stock engine"
        lab(.42,shift,("Train %d (%s)  ·  %d aboard  ·  %s in fares"):format(u.unit_number,model,run.passengers or 0,money(paid and paid.fare or 0)))
        if run.running_expense~=nil then
          lab(.42,shift+.38,((paid and paid.finished) and "Parked at destination" or run.stopped and "Stopped" or "In service")..
            "   /   "..money(run.running_expense).." operating costs")
        end
        if not (paid and paid.finished) then
          button(shift-.03,"unit_"..u.id,run.stopped and "Resume this shuttle" or "Pause this shuttle",6.8,2.78)
        end
      else
        local stock=coal and "Kirby + coal wagon" or f and f.short or
          u.stock_ids[1]==11 and (u.stock_ids[2]==27 and "Manley–Morel DMU + carriage (116 seats)" or "Manley–Morel DMU (76 seats)") or
          (model_short[u.stock_ids[1]] or "Stock engine").." + carriage"
        lab(.42,shift,("Train %d  ·  %s  ·  %s"):format(u.unit_number,stock,money(u.price)))
        if f then
          if can_order(u,cargo) then
            button(shift+.27,"unit_"..u.id,"Choose "..f.source.." and "..f.sink.." orders")
          else lab(.42,shift+.38,f.title.." orders are unavailable for this train.") end
        elseif not coal or api.rail_coal_tools then
          button(shift+.27,"unit_"..u.id,coal and "Choose mine and power-station orders" or "Choose its two platform orders")
        end
      end
    end
    if #units>limit then lab(.42,5.18+height,"Additional consists remain saved in this depot.") end
    if note then lab(.42,5.64+height,note) end
    button(6.38+height,"back","Back to world")
    core.show_formspec(n,form,table.concat(b))
    return true
  end
  local function candidate(q,id)
    local t=id and S.tiles[id]
    local st=t and t.rail_station_id
    if not st or st==q.first then return end
    local raw=S.stock_rail_stations and S.stock_rail_stations[st]
    if q.cargo then
      local f=commercial[q.cargo]
      if not available(q.cargo) then return nil,"Rail "..f.title.." service is unavailable in this world." end
      local role=q.first and "unload" or "load"
      if not raw or raw.owner~=t.owner or raw.coal_role or raw[q.cargo.."_role"]~=role then return end
      local other=q.cargo=="oil" and "goods_role" or "oil_role"
      if raw[other] then return end
      local get=api.Sim["rail_"..q.cargo.."_stop_status"]
      local r=get and get(S,st)
      if role=="load" and (not r or #(r.sources or {})==0) then return nil,"This platform no longer covers a working "..f.source.." source." end
      if role=="unload" and (not r or not r.accepts) then return nil,"This platform no longer accepts "..f.noun.."." end
    elseif raw and (raw.oil_role or raw.goods_role) then
      return nil,raw.oil_role and "That platform is dedicated to Rail Oil." or "That platform is dedicated to Rail Goods."
    elseif q.coal then
      local r=api.Sim.rail_coal_stop_status and api.Sim.rail_coal_stop_status(S,st)
      if not r or r.role~=(q.first and "unload" or "load") then return end
    end
    return st
  end
  local function pair_candidate(n,q,id)
    local a=q.choices[q.index]
    local t=id and S.tiles[id]
    if not t or t.owner~=n then return end
    if not a.id then
      if not owned_depot(n,id) or q.index==2 and id==q.choices[1].depot then return end
      local found
      for _,u in ipairs(api.rail_owned.list(S,n,id)) do
        local engine=u.stock_ids[1]
        local supported=api.rail_owned.pair_passenger_engine(engine)
        if u.depot==id and u.status=="depot" and supported and u.stock_ids[2]==27 and #u.stock_ids==2 then
          if found then return nil,"That depot has two staged passenger consists. Choose an unambiguous depot." end
          found=u.id
        end
      end
      return found
    end
    local st=t.rail_station_id
    local record=S.stock_rail_stations and S.stock_rail_stations[st]
    if not record or record.owner~=n or record.coal_role or record.oil_role or record.goods_role then return end
    if st==a.first or a.first and q.index==2 and st==q.choices[1].second then
      return nil,"Choose a different final platform; each train parks at its own destination."
    end
    return st
  end
  function U.begin_pair(p)
    if not (api.rail_owned_pair_tools and api.rail_owned and api.rail_owned.start_pair) then
      status(p,"Paired passenger dispatch is unavailable in this world.")
      return false
    end
    local n=p:get_player_name()
    local q={pair=true,index=1,choices={{},{}}}
    orders[n]=q
    status(p,stage(q).." Right-click to cancel.")
    return true
  end
  function U.active(p) return orders[p:get_player_name()]~=nil end
  local function via_candidate(n,q,t)
    if not q.pair and not q.cargo and not q.coal and q.first and t and t.owner==n and t.rail_waypoint_id then
      local waypoint=S.stock_rail_waypoints and S.stock_rail_waypoints[t.rail_waypoint_id]
      return waypoint and waypoint.owner==n
    end
  end
  function U.preview(p,id)
    local n=p:get_player_name()
    local pick=orders[n]
    if not pick then return end
    if pick.pair then
      local value,why=pair_candidate(n,pick,id)
      return {id},not not value,why or stage(pick)
    end
    local tile=id and S.tiles[id]
    if not tile or tile.owner~=n then return {id},false,stage(pick) end
    if via_candidate(n,pick,tile) then return {id},true,"Click to route through this waypoint without stopping." end
    local valid,why=candidate(pick,id)
    return {id},not not valid,why or stage(pick)
  end
  function U.ready(p)
    local q=orders[p:get_player_name()]
    return q and q.pending~=nil
  end
  function U.confirm(p)
    local q=orders[p:get_player_name()]
    if not q then return false end
    if not q.pending then status(p,stage(q));return true end
    local tile=q.pending
    q.pending=nil
    U.pick(p,tile,false)
    if orders[p:get_player_name()]==q then q.pending=tile end
    return true
  end
  function U.pick(p,id,stage_only)
    local n=p:get_player_name()
    local q=orders[n]
    if not q then return false end
    if q.pair then
      local value,why=pair_candidate(n,q,id)
      if not value then status(p,why or stage(q));return true end
      local a=q.choices[q.index]
      if not a.id then a.id,a.depot=value,id
      elseif not a.first then a.first=value
      elseif q.index==1 then a.second=value;q.index=2
      else
        if stage_only then q.pending=id;status(p,stage(q));return true end
        local ok,note=api.rail_owned.start_pair(S,n,q.choices[1],{id=a.id,first=a.first,second=value})
        if not ok then status(p,message(note).." Choose another final platform or right-click to cancel.");return true end
        orders[n]=nil;status(p,note);api.save()
        return true
      end
      status(p,stage(q));return true
    end
    local t=id and S.tiles[id]
    if not t or t.owner~=n then status(p,stage(q));return true end
    if via_candidate(n,q,t) then q.via_tile=id;status(p,stage(q));return true end
    local st,detail=candidate(q,id)
    if not st then status(p,detail or stage(q));return true end
    if not q.first then q.first=st;status(p,stage(q));return true end
    if stage_only then q.pending=id;status(p,stage(q));return true end
    local command
    if q.cargo then command=api.rail_owned["start_"..q.cargo]
    elseif q.coal then command=api.rail_owned.start_coal
    else command=api.rail_owned.start end
    if not command then status(p,"This rail service is unavailable in this world.");return true end
    local ok,why=command(S,n,q.unit,q.first,st,nil,q.via_tile)
    if not ok then status(p,message(why));return true end
    orders[n]=nil;status(p,why);api.save()
    return true
  end
  function U.cancel(p)
    local n=p:get_player_name()
    if not orders[n] then return false end
    orders[n]=nil;status(p,"Rail orders canceled before start.")
    return true
  end
  core.register_on_player_receive_fields(function(p,key,f)
    if key~=form then return false end
    local n=p:get_player_name()
    local a=panels[n]
    if f.quit or f.back then panels[n]=nil;core.close_formspec(n,form);return true end
    if not a or not owned_depot(n,a.depot) then return true end
    local receipt=f.purchase and a.quote
    if not receipt then
      for key,quote in pairs(a.alternatives or {}) do
        if f[key] and (key~="purchase_oil" or available("oil")) and
            (key~="purchase_goods" or available("goods")) then receipt=quote;break end
      end
    end
    if receipt then
      local unit,why=api.rail_owned.commit(S,n,receipt)
      if unit then api.save() end
      U.open(p,a.depot,unit and ("Purchased train "..unit.unit_number.." for "..money(unit.price)..".") or message(why))
      return true
    end
    if f.park_coal and a.park then
      local unit=api.rail_owned.get(S,n,a.park.id)
      if unit and unit.depot==a.depot then
        local ok,why=api.rail_dispatch_controller.park_coal(S,n,unit.id,a.park.on)
        if ok then api.save() end
        U.open(p,a.depot,message(why))
      end
      return true
    end
    for key,unit_id in pairs(a) do
      if type(key)=="string" and key:match("^unit_%d+$") and f[key] then
        local unit=api.rail_owned.get(S,n,unit_id)
        if not unit or unit.depot~=a.depot then return true end
        local cargo=cargo_of(unit)
        if unit.status=="depot" then
          local coal=unit.stock_ids[2]==29
          if (cargo and not can_order(unit,cargo)) or (coal and not api.rail_coal_tools) then return true end
          orders[n]={unit=unit.id,coal=coal,cargo=cargo}
          status(p,stage(orders[n]))
          panels[n]=nil;core.close_formspec(n,form)
          if api.world and api.world.begin_order_selection then
            api.world.begin_order_selection(p,"rail",coal and "Coal train orders" or cargo and "Freight train orders" or "Passenger train orders")
          end
        else
          if cargo then
            local c=commercial_status(unit,cargo)
            if not available(cargo) or not c or c.finished or c.paused or c.failure or
                not api.rail_owned.running(S,n,unit.id) then return true end
          end
          local ok,why=api.rail_owned.toggle(S,n,unit.id)
          if ok then api.save() end
          U.open(p,a.depot,message(why))
        end
        return true
      end
    end
    return true
  end)
  core.register_on_leaveplayer(function(p)
    local n=p:get_player_name();panels[n],orders[n]=nil,nil
  end)
  return U
end
