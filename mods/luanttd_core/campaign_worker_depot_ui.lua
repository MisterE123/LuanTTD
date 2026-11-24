-- Worker-backed depot read/purchase UI used when the host no longer owns S.
return function(core,client,build,money,assembly)
  local mod=core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
  local Help=dofile(mod.."/depot_vehicle_help.lua")
  local Route=dofile(mod.."/initial_vehicle_route.lua")
  local esc=core.formspec_escape
  local D={form="luanttd_core:worker_depot"}
  local panels={}
  local serial=0
  local function routes(p)
    local data=p.data or {}
    local unit=data.vehicles and data.vehicles[p.unit or 1]
    return Route.targets(p.mode,data,unit)
  end
  local function draw(n,p,note)
    local data=p.data or {}
    local offers,units,from,to=data.offers or {},data.vehicles or {},{},{}
    local first,last,cargo=routes(p)
    for i,t in ipairs(first) do from[i]=core.formspec_escape(t.label) end
    for i,t in ipairs(last) do to[i]=core.formspec_escape(t.label) end
    local stem="d"..p.serial.."_"
    local title=p.mode=="rail" and (data.railtype==3 and "Maglev depot" or data.railtype==2 and "Monorail depot")
      or data.hangar_label or ({rail="Rail depot",air="Airport hangar",ship="Ship depot",road="Road depot"})[p.mode] or "Company depot"
    local b={"formspec_version[7]size[11.4,10.03]bgcolor[#152334;false]",
      "label[.45,.42;"..esc(title).."]", "label[.45,.86;Hover for vehicle details, or tap or click a row.]",
      "label[.45,1.30;Purchase offers]","label[5.82,1.30;Owned vehicles]"}
    local function info(row)
      local req=row.request or {}
      return row.help or Help.describe(p.mode,row.cargo or req.cargo,row.name or row.label)
    end
    Help.rows(b,esc,{x=.45,y=1.57,w=5.12,h=3.57,items=offers,prefix=stem.."offer_",
      scroll=p.offer_scroll,selected=p.offer or 1,help=info,
      label=function(q)
        local model,cargo=q.name:match("^(.-) · (.+)$")
        return model or q.name,(cargo and cargo.." · " or "")..money(q.price)
      end})
    Help.rows(b,esc,{x=5.82,y=1.57,w=5.12,h=3.57,items=units,prefix=stem.."unit_",
      scroll=p.unit_scroll,selected=p.unit or 1,help=info,
      label=function(u) return u.label,info(u).service end})
    if #offers==0 then b[#b+1]="label[.5,1.89;No vehicles currently on sale.]" end
    if #units==0 then b[#b+1]="label[5.87,1.89;No vehicles assigned here.]" end
    if #offers>0 then
      local chosen=data.offers[p.offer or 1]
      local action=(chosen.request.operation=="refit" and "Refit" or "Buy").." for "..money(chosen.price)
      b[#b+1]="button[.45,5.42;5.12,.59;"..stem.."buy;"..action.."]"
    end
    local active=units[p.unit or 1]
    if #units>0 then
      if p.mode=="road" or p.mode=="rail" and active and active.order_copy then
        b[#b+1]="button[5.82,5.42;2.54,.59;"..stem.."orders;"..(active and active.copied and "Review orders" or "Open vehicle").."]"
        b[#b+1]="button[8.47,5.42;2.47,.59;"..stem.."copy;Copy orders…]"
        b[#b+1]="tooltip["..stem.."copy;Copy an independent order list from another vehicle to the selected vehicle.]"
      else b[#b+1]="button[5.82,5.42;5.12,.59;"..stem.."orders;Open selected vehicle]" end
    end
    local route_ok=Route.possible(first,last)
    local origin=p.mode=="air" and p.depot or (first[p.from or 1] or {}).id
    local default_to=last[1] and last[1].id==origin and 2 or 1
    if p.mode=="rail" and active and active.copied then
      b[#b+1]="label[.45,6.47;"..active.copied.." copied station orders. Start when the route is ready.]"
      b[#b+1]="button[7.50,6.17;3.44,.57;"..stem.."start_copied;Start copied orders]"
    elseif route_ok and #units>0 then
      if p.mode~="air" then
        b[#b+1]=("dropdown[.45,6.17;3.39,.57;%sfrom;%s;%d;true]"):format(stem,table.concat(from,","),p.from or 1)
      end
      b[#b+1]=("dropdown[3.98,6.17;3.38,.57;%sto;%s;%d;true]"):format(stem,table.concat(to,","),p.to or default_to)
      b[#b+1]="button[7.50,6.17;3.44,.57;"..stem.."start;Start service]"
    end
    if units[p.unit or 1] and units[p.unit or 1].unsupported then
      b[#b+1]="label[.45,6.45;Unsupported freight formation. Rearrange its wagons in the depot.]"
    elseif active and not route_ok and (p.mode=="rail" or p.mode=="ship") and not active.copied then
      b[#b+1]="textarea[.45,6.15;10.49,.69;;;"..esc(Route.notice(p.mode,active)).."]"
    end
    local chosen=p.focus~="offer" and units[p.unit or 1] or offers[p.offer or 1]
    chosen=chosen or offers[p.offer or 1]
    Help.card(b,esc,.45,6.98,10.49,1.72,chosen and info(chosen))
    if p.mode=="rail" and assembly and p.data then
      b[#b+1]="button[.45,9.09;5.12,.58;"..stem.."assemble;Assemble wagons]"
    end
    b[#b+1]="label[.45,8.88;"..esc(Help.fit(note,61)).."]"
    b[#b+1]="button_exit[5.82,9.09;5.12,.58;close;Back to world]"
    core.show_formspec(n,D.form,table.concat(b))
  end
  function D.open(player,mode,depot,note,vehicle_handler,selected_vehicle,prior,hangar_tile)
    local name=player:get_player_name()
    serial=serial+1
    local p={serial=serial,mode=mode,depot=depot,hangar_tile=hangar_tile,vehicle_handler=vehicle_handler,focus="offer"}
    panels[name]=p
    draw(name,p,note or "Reading the depot…")
    local sent,why=client.query({kind="depot",player=name,mode=mode,depot=depot,hangar_tile=hangar_tile},function(reply)
      if panels[name]~=p then return end
      if reply.ok then
        p.data,p.revision=reply.value,reply.revision
        for i,row in ipairs(p.data.vehicles or {}) do
          if row.id==selected_vehicle then p.unit,p.focus=i,"unit";break end
        end
        if prior then
          p.offer_scroll,p.unit_scroll=prior.offer_scroll,prior.unit_scroll
          for i,q in ipairs(p.data.offers) do if q.name==prior.offer_name then p.offer=i;break end end
          if p.unit then
            local first,last=routes(p)
            local _,i=Route.find(first,prior.first);p.from=i
            _,i=Route.find(last,prior.second);p.to=i
          end
        elseif mode=="road" then
          for i,q in ipairs(p.data.offers) do
            if q.request.cargo=="passenger" then p.offer=i;p.offer_scroll=Help.scroll_to(i);break end
          end
        end
      end
      draw(name,p,note or reply.why)
    end)
    if not sent then draw(name,p,why) end
    return true
  end
  local function named_vehicle(label,id)
    label=label or "Vehicle"
    local number="#"..id
    return label:sub(-#number)==number and label or label.." "..number
  end
  local function draw_copy(n,p,c,note)
    local stem="dc"..c.token.."_"
    local data=c.data or {}
    local b={"formspec_version[7]size[11.4,8.20]bgcolor[#152334;false]",
      "label[.45,.42;Copy orders]",
      "label[.45,.92;To: "..esc(Help.fit(named_vehicle(c.label,c.vehicle),59)).."]",
      "label[.45,1.42;Choose a source vehicle from your company.]",
      "label[.45,1.85;Copying replaces the destination orders with an independent list.]"}
    if data.sources and #data.sources>0 then
      Help.rows(b,esc,{x=.45,y=2.20,w=10.49,h=3.85,items=data.sources,
        prefix=stem.."source_",scroll=c.scroll,selected=c.selected,
        help=function(row) return {model=named_vehicle(row.label,row.id),service=row.cargo or "Vehicle",
          connections=("Copy all %d orders in their current sequence."):format(row.count)} end,
        label=function(row) return named_vehicle(row.label,row.id),(row.cargo or "Vehicle").." · "..row.count.." orders" end})
    end
    b[#b+1]="textarea[.48,6.19;10.27,.68;;;"..esc(note or "").."]"
    b[#b+1]="button[.45,7.08;5.10,.66;"..stem.."back;Back to depot]"
    if c.selected and data.sources and data.sources[c.selected] and not c.pending then
      b[#b+1]="button[5.82,7.08;5.12,.66;"..stem.."apply;Copy selected orders]"
    end
    core.show_formspec(n,D.form,table.concat(b))
  end
  local function read_copy(n,p,c,notice,previous)
    draw_copy(n,p,c,notice or "Reading compatible vehicles…")
    local sent,why=client.query({kind="depot_order_sources",player=n,mode=p.mode,
      vehicle=c.vehicle,depot=p.depot},function(r)
      if panels[n]~=p or p.copy~=c then return end
      c.data,c.revision,c.pending,c.selected=nil,nil,nil,nil
      local note=notice or r.why
      if r.ok then
        c.data,c.revision=r.value,r.revision
        for i,v in ipairs(c.data.sources) do if v.id==previous then c.selected=i;break end end
        if #c.data.sources<1 then note="No compatible vehicles with orders. Set up another vehicle first."
        else
          c.selected=c.selected or 1
          note=note or (c.data.count>0 and ("This replaces the destination's "..c.data.count.." existing orders.") or nil)
        end
      end
      draw_copy(n,p,c,note)
    end)
    if not sent then c.pending=nil;draw_copy(n,p,c,why) end
  end
  local function copy_fields(n,p,c,f,player)
    local stem="dc"..c.token.."_"
    if f[stem.."back"] then p.copy=nil;draw(n,p);return true end
    if not c.data or c.pending then return true end
    c.scroll=Help.scroll_fields(core,f,stem.."source_scroll",c.scroll)
    local row=Help.selected(f,stem.."source_row",#c.data.sources)
    if row then c.selected=row;draw_copy(n,p,c);return true end
    local source=c.data.sources[c.selected]
    if not (source and f[stem.."apply"]) then return true end
    c.pending=true
    local sent,why=client.query({kind="command",player=n,command={kind="depot_copy_orders",mode=p.mode,
      vehicle=c.vehicle,depot=p.depot,source=source.id,source_revision=source.revision,
      target_revision=c.data.revision,revision=c.revision}},function(r)
      if panels[n]~=p or p.copy~=c then return end
      if not r.ok then
        local note=r.why=="STALE_COMMAND" and "The campaign changed. Review the latest orders and try again." or r.why
        return read_copy(n,p,c,note,source.id)
      end
      if p.mode=="rail" then
        return D.open(player,p.mode,p.depot,r.why or "Orders copied.",p.vehicle_handler,c.vehicle)
      end
      p.copy=nil;p.revision=r.revision
      draw(n,p,r.why or "Orders copied.")
    end)
    if not sent then c.pending=nil;draw_copy(n,p,c,why)
    elseif p.copy==c and c.pending then draw_copy(n,p,c,"Copying orders…") end
    return true
  end
  function D.fields(player,f)
    local n=player:get_player_name()
    local p=panels[n]
    if not p then return true end
    if f.quit then panels[n]=nil;return true end
    if p.copy then return copy_fields(n,p,p.copy,f,player) end
    if not p.data or p.pending then return true end
    local stem="d"..p.serial.."_"
    local update,unit_changed=false,false
    for kind,list in pairs({offer=p.data.offers,unit=p.data.vehicles}) do
      local key=stem..kind.."_"
      local field=kind.."_scroll"
      p[field]=Help.scroll_fields(core,f,key.."scroll",p[field])
      local i=Help.selected(f,key.."row",#list)
      if i then
        unit_changed=kind=="unit" and (p.unit or 1)~=i
        p[kind],p.focus,update=i,kind,true
      end
    end
    if unit_changed then p.from,p.to=nil,nil
    else
      p.from=tonumber(f[stem.."from"]) or p.from
      p.to=tonumber(f[stem.."to"]) or p.to
    end
    if f[stem.."copy"] then
      local u=p.data.vehicles[p.unit or 1]
      if u and (p.mode=="road" or p.mode=="rail" and u.order_copy) then
        serial=serial+1
        local c={vehicle=u.id,label=u.label,token=serial}
        p.copy=c
        read_copy(n,p,c)
      end
      return true
    end
    if p.mode=="rail" and f[stem.."assemble"] and assembly then return assembly(player,p.depot) end
    if f[stem.."orders"] and p.vehicle_handler then
      local u=p.data.vehicles[p.unit or 1]
      if u then
        local first,last=routes(p)
        local offer=p.data.offers[p.offer or 1]
        local prior={offer_name=offer and offer.name,offer_scroll=p.offer_scroll,unit_scroll=p.unit_scroll,
          first=first[p.from or 0] and first[p.from].id,second=last[p.to or 0] and last[p.to].id}
        local back={depot=p.depot,initial=Route.context(client,player,p.mode,p.depot,u,p.data,p.from,p.to)}
        function back.return_(selection)
          if selection then prior.first,prior.second=selection.first,selection.second end
          return D.open(player,p.mode,p.depot,nil,p.vehicle_handler,u.id,prior,p.hangar_tile)
        end
        panels[n]=nil
        return p.vehicle_handler(p.mode,u.id,back)
      end
      return true
    end
    if p.mode=="rail" and f[stem.."start_copied"] then
      local u=p.data.vehicles[p.unit or 1]
      if not (u and u.copied and u.draft_revision) then return true end
      p.pending=true
      local sent,why=client.query({kind="command",player=n,command={kind="transport_start",mode="rail",
        vehicle=u.id,depot=p.depot,copied=true,draft_revision=u.draft_revision,revision=p.revision}},
        function(r)
          if panels[n]==p then return D.open(player,p.mode,p.depot,r.why,p.vehicle_handler,u.id,nil,p.hangar_tile) end
        end)
      if not sent then p.pending=nil;draw(n,p,why) end
      return true
    end
    if f[stem.."start"] then
      local unit=p.data.vehicles[p.unit or 1]
      local sources,sinks,cargo=routes(p)
      local first=p.mode=="air" and Route.find(sources,p.depot) or sources[p.from or 1]
      local default_to=sinks[1] and first and sinks[1].id==first.id and 2 or 1
      local last=sinks[p.to or default_to]
      if not (unit and first and last and first.id~=last.id) then
        draw(n,p,"Choose two different destinations.");return true
      end
      p.pending=true
      local sent,why=client.query({kind="command",player=n,command={kind="transport_start",mode=p.mode,
        vehicle=unit.id,depot=p.depot,first=p.mode=="air" and p.depot or first.id,second=last.id,cargo=cargo,
        revision=p.revision}},
        function(r) if panels[n]==p then D.open(player,p.mode,p.depot,r.why or (r.ok and "Service dispatched." or
          "Service could not start."),p.vehicle_handler,nil,nil,p.hangar_tile) end end)
      if not sent then p.pending=nil;draw(n,p,why) end
      return true
    end
    if not f[stem.."buy"] then
      if update then draw(n,p) end
      return true
    end
    local q=p.data.offers[p.offer or 1]
    if not q then return true end
    p.pending=true
    local function bought(ok,note)
      local applied=q.request.operation=="refit" and "Refit applied." or "Vehicle purchased."
      if panels[n]==p then D.open(player,p.mode,p.depot,note or (ok and applied or "Depot action did not go through."),p.vehicle_handler,nil,nil,p.hangar_tile) end
    end
    local sent,why
    if q.request.kind=="road_buy" then
      q.request.revision=p.revision
      sent,why=client.query({kind="command",player=n,command=q.request},function(r) bought(r.ok,r.why) end)
    else
      sent,why=build.commit(n,"transport",q.request,bought)
    end
    if not sent then p.pending=nil;draw(n,p,why) end
    return true
  end
  function D.leave(n) panels[n]=nil end
  return D
end
