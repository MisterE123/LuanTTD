-- Worker-backed depot read/purchase UI used when the host no longer owns S.
return function(core,client,build,money,assembly)
  local mod=core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core"
  local Help=dofile(mod.."/depot_vehicle_help.lua")
  local esc=core.formspec_escape
  local page_size=5
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
    local offers,units,from,to=data.offers or {},data.vehicles or {},{},{}
    local first,last,cargo=routes(p)
    for i,t in ipairs(first) do from[i]=core.formspec_escape(t.label) end
    for i,t in ipairs(last) do to[i]=core.formspec_escape(t.label) end
    local stem="d"..p.serial.."_"
    local title=({rail="Rail depot",air="Airport hangar",ship="Ship depot",road="Road depot"})[p.mode] or "Company depot"
    local b={"formspec_version[7]size[11.4,10.03]bgcolor[#152334;false]",
      "label[.45,.42;"..title.."]", "label[.45,.86;Hover for vehicle details, or tap or click a row.]",
      "label[.45,1.30;Purchase offers]","label[5.82,1.30;Owned vehicles]"}
    local function info(row)
      local req=row.request or {}
      return row.help or Help.describe(p.mode,row.cargo or req.cargo,row.name or row.label)
    end
    Help.rows(b,esc,{x=.45,y=1.57,w=5.12,items=offers,prefix=stem.."offer_",count=page_size,
      page=p.offer_page or 1,selected=p.offer or 1,help=info,
      label=function(q) return q.name.."  ·  "..money(q.price) end})
    Help.rows(b,esc,{x=5.82,y=1.57,w=5.12,items=units,prefix=stem.."unit_",count=page_size,
      page=p.unit_page or 1,selected=p.unit or 1,help=info,label=function(u) return u.label end})
    if #offers==0 then b[#b+1]="label[.5,1.89;No vehicles currently on sale.]" end
    if #units==0 then b[#b+1]="label[5.87,1.89;No vehicles assigned here.]" end
    if #offers>0 then
      local chosen=data.offers[p.offer or 1]
      local action=chosen.request.operation=="refit" and "Apply selected refit" or "Buy selected vehicle"
      b[#b+1]="button[.45,5.42;5.12,.59;"..stem.."buy;"..action.."]"
    end
    if #units>0 then b[#b+1]="button[5.82,5.42;5.12,.59;"..stem.."orders;Open selected vehicle]" end
    local route_ok=cargo and #first>0 and #last>0 or not cargo and #first>=2
    if route_ok and #units>0 then
      if p.mode~="air" then
        b[#b+1]=("dropdown[.45,6.17;3.39,.57;%sfrom;%s;%d;true]"):format(stem,table.concat(from,","),p.from or 1)
      end
      b[#b+1]=("dropdown[3.98,6.17;3.38,.57;%sto;%s;%d;true]"):format(stem,table.concat(to,","),p.to or (cargo and 1 or 2))
      b[#b+1]="button[7.50,6.17;3.44,.57;"..stem.."start;Start service]"
    end
    if cargo and not route_ok then
      b[#b+1]="label[.45,6.45;No matching loading and unloading stops. See the vehicle details.]"
    end
    local chosen=p.focus~="offer" and units[p.unit or 1] or offers[p.offer or 1]
    chosen=chosen or offers[p.offer or 1]
    Help.card(b,esc,.45,6.98,10.49,1.72,chosen and info(chosen))
    if p.mode=="rail" and assembly and p.data then
      b[#b+1]="button[.45,9.09;5.12,.58;"..stem.."assemble;Assemble wagons]"
    end
    b[#b+1]="label[.45,8.88;"..esc(note or "").."]"
    b[#b+1]="button_exit[5.82,9.09;5.12,.58;close;Back to world]"
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
    local update,unit_changed=false,false
    for kind,list in pairs({offer=p.data.offers,unit=p.data.vehicles}) do
      local key=stem..kind.."_"
      local page_key=kind.."_page"
      local page=p[page_key] or 1
      if f[key.."prev"] and page>1 then p[page_key]=page-1;update=true
      elseif f[key.."next"] and page*page_size<#list then p[page_key]=page+1;update=true
      else
        for i=(page-1)*page_size+1,math.min(page*page_size,#list) do
          if f[key.."row"..i] then
            unit_changed=kind=="unit" and (p.unit or 1)~=i
            p[kind],p.focus,update=i,kind,true
            break
          end
        end
      end
    end
    if unit_changed then p.from,p.to=nil,nil
    else
      p.from=tonumber(f[stem.."from"]) or p.from
      p.to=tonumber(f[stem.."to"]) or p.to
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
      if update then draw(n,p) end
      return true
    end
    local q=p.data.offers[p.offer or 1]
    if not q then return true end
    p.pending=true
    local function bought(ok,note)
      local applied=q.request.operation=="refit" and "Refit applied." or "Vehicle purchased."
      if panels[n]==p then D.open(player,p.mode,p.depot,note or (ok and applied or "Depot action did not go through."),p.vehicle_handler) end
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
