-- Worker-backed depot read/purchase UI used when the host no longer owns S.
return function(core,client,build,money)
  local D={form="luanttd_core:worker_depot"}
  local panels={}
  local serial=0
  local function draw(n,p,note)
    local data=p.data or {}
    local offers,units,targets={},{},{}
    for i,q in ipairs(data.offers or {}) do offers[i]=core.formspec_escape(q.name.."  ·  "..money(q.price)) end
    for i,u in ipairs(data.vehicles or {}) do units[i]=core.formspec_escape(u.label) end
    for i,t in ipairs(data.targets or {}) do targets[i]=core.formspec_escape(t.label) end
    local stem="d"..p.serial.."_"
    local b={"formspec_version[7]size[10.8,8.35]bgcolor[#152334;false]",
      "label[.45,.42;Company depot]","label[.45,1.05;Purchase offers]","label[5.55,1.05;Owned vehicles]",
      ("textlist[.45,1.35;4.8,3.30;%soffer;%s;%d;false]"):format(stem,table.concat(offers,","),p.offer or 1),
      ("textlist[5.55,1.35;4.8,3.30;%sunit;%s;%d;false]"):format(stem,table.concat(units,","),p.unit or 1)}
    if #offers>0 then b[#b+1]="button[.45,4.84;4.8,.59;"..stem.."buy;Buy selected vehicle]" end
    if #units>0 then b[#b+1]="button[5.55,4.84;4.8,.59;"..stem.."orders;Open selected vehicle]" end
    if #targets>=2 and #units>0 then
      if p.mode~="air" then
        b[#b+1]=("dropdown[.45,5.62;3.18,.57;%sfrom;%s;%d;true]"):format(stem,table.concat(targets,","),p.from or 1)
      end
      b[#b+1]=("dropdown[3.74,5.62;3.15,.57;%sto;%s;%d;true]"):format(stem,table.concat(targets,","),p.to or 2)
      b[#b+1]="button[7.06,5.62;3.3,.57;"..stem.."start;Start service]"
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
    for kind,list in pairs({offer=p.data.offers,unit=p.data.vehicles}) do
      local key=stem..kind
      if f[key] then
        local i=core.explode_textlist_event(f[key]).index
        if i and list[i] then p[kind]=i end
      end
    end
    if f[stem.."orders"] and p.vehicle_handler then
      local u=p.data.vehicles[p.unit or 1]
      if u then p.vehicle_handler(p.mode,u.id) end
      return true
    end
    if f[stem.."start"] then
      local unit=p.data.vehicles[p.unit or 1]
      local targets=p.data.targets or {}
      local first=targets[tonumber(f[stem.."from"]) or p.from or 1]
      local last=targets[tonumber(f[stem.."to"]) or p.to or 2]
      if not (unit and first and last) then return true end
      p.pending=true
      local sent,why=client.query({kind="command",player=n,command={kind="transport_start",mode=p.mode,
        vehicle=unit.id,depot=p.depot,first=p.mode=="air" and p.depot or first.id,second=last.id,
        revision=p.revision}},
        function(r) if panels[n]==p then D.open(player,p.mode,p.depot,r.why or (r.ok and "Service dispatched." or
          "Service could not start."),p.vehicle_handler) end end)
      if not sent then p.pending=nil;draw(n,p,why) end
      return true
    end
    if not f[stem.."buy"] then return true end
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
