-- Worker-backed depot read/purchase UI used when the host no longer owns S.
return function(core,client,build,money,assembly)
  local D={form="luanttd_core:worker_depot"}
  local panels={}
  local serial=0
  local function routes(p)
    local data=p.data or {}
    local unit=data.vehicles and data.vehicles[p.unit or 1]
    local cargo=unit and unit.cargo
    local first,last={},{}
    for _,r in ipairs(data.targets or {}) do
      if r.cargo==cargo and (not cargo or r.role=="load") then first[#first+1]=r end
      if r.cargo==cargo and (not cargo or r.role=="unload") then last[#last+1]=r end
    end
    return first,last,cargo
  end
  local function draw(n,p,note)
    local data=p.data or {}
    local offers,units,from,to={},{},{},{}
    for i,q in ipairs(data.offers or {}) do offers[i]=core.formspec_escape(q.name.."  ·  "..money(q.price)) end
    for i,u in ipairs(data.vehicles or {}) do units[i]=core.formspec_escape(u.label) end
    local first,last,cargo=routes(p)
    for i,t in ipairs(first) do from[i]=core.formspec_escape(t.label) end
    for i,t in ipairs(last) do to[i]=core.formspec_escape(t.label) end
    local stem="d"..p.serial.."_"
    local b={"formspec_version[7]size[10.8,8.35]bgcolor[#152334;false]",
      "label[.45,.42;Company depot]","label[.45,1.05;Purchase offers]","label[5.55,1.05;Owned vehicles]",
      ("textlist[.45,1.35;4.8,3.30;%soffer;%s;%d;false]"):format(stem,table.concat(offers,","),p.offer or 1),
      ("textlist[5.55,1.35;4.8,3.30;%sunit;%s;%d;false]"):format(stem,table.concat(units,","),p.unit or 1)}
    if #offers>0 then b[#b+1]="button[.45,4.84;4.8,.59;"..stem.."buy;Buy selected vehicle]" end
    if #units>0 then b[#b+1]="button[5.55,4.84;4.8,.59;"..stem.."orders;Open selected vehicle]" end
    local route_ok=cargo and #first>0 and #last>0 or not cargo and #first>=2
    if route_ok and #units>0 then
      if p.mode~="air" then
        b[#b+1]=("dropdown[.45,5.62;3.18,.57;%sfrom;%s;%d;true]"):format(stem,table.concat(from,","),p.from or 1)
      end
      b[#b+1]=("dropdown[3.74,5.62;3.15,.57;%sto;%s;%d;true]"):format(stem,table.concat(to,","),p.to or (cargo and 1 or 2))
      b[#b+1]="button[7.06,5.62;3.3,.57;"..stem.."start;Start service]"
    end
    if cargo and not route_ok then
      b[#b+1]="label[.45,5.62;Designate a loading and unloading platform for this cargo.]"
    end
    if p.mode=="rail" and assembly and p.data then
      b[#b+1]="button[.45,7.41;4.8,.58;"..stem.."assemble;Assemble wagons]"
    end
    b[#b+1]="label[.45,6.67;"..core.formspec_escape(note or "").."]"
    b[#b+1]="button_exit[5.55,7.41;4.8,.58;close;Back to world]"
    core.show_formspec(n,D.form,table.concat(b))
  end
  function D.open(player,mode,depot,note,vehicle_handler)
    local name=player:get_player_name()
    serial=serial+1
    local p={serial=serial,mode=mode,depot=depot,vehicle_handler=vehicle_handler}
    panels[name]=p
    draw(name,p,note or "Reading the depot…")
    local sent,why=client.query({kind="depot",player=name,mode=mode,depot=depot},function(reply)
      if panels[name]~=p then return end
      if reply.ok then p.data,p.revision=reply.value,reply.revision end
      draw(name,p,note or reply.why)
    end)
    if not sent then draw(name,p,why) end
    return true
  end
  function D.fields(player,f)
    local n=player:get_player_name()
    local p=panels[n]
    if not p then return true end
    if f.quit then panels[n]=nil;return true end
    if not p.data or p.pending then return true end
    local stem="d"..p.serial.."_"
    local selected_before=p.unit
    for kind,list in pairs({offer=p.data.offers,unit=p.data.vehicles}) do
      local key=stem..kind
      if f[key] then
        local i=core.explode_textlist_event(f[key]).index
        if i and list[i] then p[kind]=i end
      end
    end
    if p.mode=="rail" and f[stem.."assemble"] and assembly then return assembly(player,p.depot) end
    if f[stem.."orders"] and p.vehicle_handler then
      local u=p.data.vehicles[p.unit or 1]
      if u then p.vehicle_handler(p.mode,u.id) end
      return true
    end
    if f[stem.."start"] then
      local unit=p.data.vehicles[p.unit or 1]
      local sources,sinks,cargo=routes(p)
      local first=sources[tonumber(f[stem.."from"]) or p.from or 1]
      local last=sinks[tonumber(f[stem.."to"]) or p.to or (cargo and 1 or 2)]
      if not (unit and first and last) then return true end
      p.pending=true
      local sent,why=client.query({kind="command",player=n,command={kind="transport_start",mode=p.mode,
        vehicle=unit.id,depot=p.depot,first=p.mode=="air" and p.depot or first.id,second=last.id,cargo=cargo,
        revision=p.revision}},
        function(r) if panels[n]==p then D.open(player,p.mode,p.depot,r.why or (r.ok and "Service dispatched." or
          "Service could not start."),p.vehicle_handler) end end)
      if not sent then p.pending=nil;draw(n,p,why) end
      return true
    end
    if not f[stem.."buy"] then
      if selected_before~=p.unit and p.mode=="rail" then p.from,p.to=nil,nil;draw(n,p) end
      return true
    end
    local q=p.data.offers[p.offer or 1]
    if not q then return true end
    p.pending=true
    local function bought(ok,note)
      if panels[n]==p then D.open(player,p.mode,p.depot,note or (ok and "Vehicle purchased." or "Not purchased."),p.vehicle_handler) end
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
