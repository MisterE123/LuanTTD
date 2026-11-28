-- Native stock Found Town review. The window holds the aimed tile
-- fixed, then the authority quotes and rechecks the actual placement.
return function(core,client,money,aim,open_finance)
  local M={form="luanttd_core:found_town"}
  local views,serial={},0
  local layouts={"original","better","grid2","grid3","random"}
  local layout_labels={"Original","Better roads","2 x 2 grid","3 x 3 grid","Random"}
  local sizes={"small","medium","random"}
  local why={
    TOWN_FOUNDING_FORBIDDEN="Town founding is disabled in this world.",
    INVALID_TOWN_LOCATION="Aim at a flat, clear tile before opening Finance.",
    TOO_CLOSE_TO_EDGE="Choose a site at least 12 tiles from the map edge.",
    TOO_CLOSE_TO_ANOTHER_TOWN="This site is too close to another town.",
    SITE_UNSUITABLE="The town needs a flat, clear site. Ordinary trees are allowed.",
    NAME_MUST_BE_UNIQUE="That name is already in use. Try another.",
    INVALID_TOWN_NAME="Use a name shorter than 32 characters or leave it blank.",
    NOT_ENOUGH_MONEY="The company cannot afford to found this town.",
    STALE_COMMAND="The world changed. Review the price and site again.",
    TOWN_FOUNDING_PRICE_CHANGED="The price changed. Review it again.",
  }
  local function pos(values,value)
    for i,k in ipairs(values) do if k==value then return i end end
    return 1
  end
  local function player(p) return p:get_player_name() end
  local function draw(name,v,message)
    local a=v.request
    local id="t"..v.id.."_"
    local esc=core.formspec_escape
    local function label(x,y,text) return ("label[%g,%g;%s]"):format(x,y,esc(text)) end
    local function btn(x,y,w,key,text) return ("button[%g,%g;%g,.6;%s%s;%s]"):format(x,y,w,id,key,esc(text)) end
    local b={"formspec_version[7]size[8.9,5.62]bgcolor[#152334;false]",label(.45,.44,"Found a town")}
    b[#b+1]=label(.45,.99,v.site)
    if v.finished then
      b[#b+1]=label(.45,1.74,"Founded "..v.finished.name.." for "..money(v.finished.cost)..".")
      b[#b+1]=label(.45,2.34,("Starting population: %d"):format(v.finished.population))
    elseif v.plan then
      local q=v.plan
      b[#b+1]=label(.45,1.64,q.name)
      b[#b+1]=label(.45,2.16,(q.city and "City" or "Town").." · "..layout_labels[pos(layouts,q.resolved_layout)])
      b[#b+1]=label(.45,2.77,"Founding cost: "..money(q.cost))
      if q.affordable then b[#b+1]=btn(4.64,3.8,3.75,"confirm","Found "..(q.city and "city" or "town"))
      else b[#b+1]=label(.45,3.38,"The company does not have enough cash.") end
      b[#b+1]=btn(.45,3.8,3.75,"edit","Edit options")
    elseif a.tile then
      b[#b+1]=("field[.45,1.48;7.9,.63;%sname;Name (blank for a stock name);%s]"):format(id,esc(a.name or ""))
      b[#b+1]=("field_close_on_enter[%sname;false]"):format(id)
      b[#b+1]=label(.45,2.30,"Starting size")
      b[#b+1]=("dropdown[.45,2.54;3.65,.53;%ssize;Small,Medium,Random;%d;true]"):format(id,pos(sizes,a.size))
      b[#b+1]=("checkbox[4.63,2.71;%scity;City;%s]"):format(id,tostring(a.city))
      if v.policy==2 then
        b[#b+1]=label(.45,3.38,"Street layout")
        b[#b+1]=("dropdown[.45,3.62;3.65,.57;%slayout;%s;%d;true]"):format(id,table.concat(layout_labels,","),pos(layouts,a.layout))
      else
        b[#b+1]=label(.45,3.72,"Street layout: "..layout_labels[pos(layouts,a.layout)])
      end
      b[#b+1]=btn(4.64,3.62,3.75,"review","Review price and site")
    end
    if message then b[#b+1]=label(.45,4.55,why[message] or message) end
    b[#b+1]=btn(.45,4.83,3.75,"back","Back to finance")
    b[#b+1]="button_exit[4.64,4.83;3.75,.6;close;Back to world]"
    core.show_formspec(name,M.form,table.concat(b))
  end
  function M.open(p,policy,layout)
    local name=player(p)
    local tile,x,z=aim(p)
    serial=serial+1
    local r=core.get_us_time and core.get_us_time() or serial
    local v={id=serial,policy=policy,request={tile=tile,size="small",city=false,layout=layout,nameparts=r%4294967296},
      site=tile and ("Site: tile %d, %d"):format(x,z) or "No terrain tile selected. Aim at flat land and reopen Finance."}
    views[name]=v
    draw(name,v)
    return true
  end
  function M.fields(p,f)
    local name=player(p)
    local v=views[name]
    if not v then return true end
    if f.quit then views[name]=nil;return true end
    if v.pending then return true end
    local id="t"..v.id.."_"
    if f[id.."back"] then views[name]=nil;return open_finance(p) end
    if f[id.."edit"] then v.plan=nil;draw(name,v);return true end
    local request,command
    if v.plan then
      if not f[id.."confirm"] or not v.plan.affordable then return true end
      request={kind="command",player=name,command={kind="town_found",request=v.request,
        cost=v.plan.cost,revision=v.revision}}
      command=true
    elseif not v.finished and v.request.tile then
      local a=v.request
      local size,layout=tonumber(f[id.."size"]),tonumber(f[id.."layout"])
      if sizes[size] then a.size=sizes[size] end
      if v.policy==2 and layouts[layout] then a.layout=layouts[layout] end
      if f[id.."city"]=="true" or f[id.."city"]=="false" then a.city=f[id.."city"]=="true" end
      if f[id.."name"]~=nil then a.name=f[id.."name"] end
      if not f[id.."review"] then return true end
      request={kind="town_found_quote",player=name,request=a}
    else return true end
    v.pending=true
    local queued,error_=client.query(request,function(reply)
      if views[name]~=v then return end
      v.pending=nil
      if command then
        v.plan=nil
        if reply.ok then v.finished=reply.value end
      elseif reply.ok then v.plan,v.revision=reply.value,reply.revision end
      draw(name,v,not reply.ok and reply.why or nil)
    end)
    if not queued then v.pending=nil;draw(name,v,error_) end
    return true
  end
  function M.leave(name) views[name]=nil end
  return M
end
