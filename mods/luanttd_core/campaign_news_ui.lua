-- Native news view. An incoming bulletin is a non-modal HUD so it
-- cannot steal aim from a build, erase orders, or replace another form.
return function(core,mod,client,formatted_date,sound)
  local News=dofile(mod.."/openttd/news.lua")
  local U={form="luanttd_core:newspaper"}
  local esc=core.formspec_escape
  local local_state={}
  local paper="#EADDC0FF"
  local function state(p)
    local name=p:get_player_name()
    if not local_state[name] then
      local meta=p:get_meta()
      local modes={}
      for _,c in ipairs(News.categories) do modes[c[1]]=tonumber(meta:get_string("luanttd_news_"..c[1])) end
      local a,b=meta:get_int("luanttd_news_ticker"),meta:get_int("luanttd_news_paper")
      local_state[name]={meta=meta,prefs=modes,read={ticker=a,paper=b},received=math.min(a,b),queue={},active={}}
    end
    return local_state[name],name
  end
  local function date(r) return formatted_date(r.year,r.month,r.day) end
  local function now() return core.get_us_time()/1000000 end
  local function headline(text,width,lines)
    local rows,line={},""
    for word in text:gmatch("%S+") do
      if #line>0 and #line+#word>=width then
        rows[#rows+1]=line
        if #rows==lines then rows[#rows]=rows[#rows].."…";return rows end
        line=""
      end
      line=line..(#line>0 and " " or "")..word
    end
    if #line>0 then rows[#rows+1]=line end
    return rows
  end
  local function remove(p,v,lane)
    local active=v.active[lane]
    if not active then return end
    for _,id in ipairs(active.hud) do p:hud_remove(id) end
    v.active[lane]=nil
  end
  local function status(p,row,mode)
    local text=mode==News.OFF and "• New item in the newspaper" or (table.concat(headline(row.headline,92,1)).."   ·   Newspaper")
    return {p:hud_add({type="text",position={x=.50,y=.09},offset={x=0,y=0},alignment={x=0,y=0},
      text=text,number=0xFFE9B3,z_index=101})}
  end
  local function bulletin(p,row)
    local out={}
    local position={x=1,y=.13}
    -- Right aligned under the controls; headline and location never
    -- compete with the center reticle or lower build bar.
    local function image(texture,x,y)
      out[#out+1]=p:hud_add({type="image",position=position,alignment={x=-1,y=1},offset={x=x,y=y},
        text=texture,scale={x=1,y=1},z_index=110})
    end
    local function text(s,x,y,color)
      out[#out+1]=p:hud_add({type="text",position=position,alignment={x=1,y=1},offset={x=x,y=y},
        text=s,number=color,z_index=111})
    end
    image("bl_newspaper_bulletin.png",-18,0)
    text("TRANSPORT GAZETTE",-322,10,0x203842)
    text(date(row),-322,27,0x6A543C)
    for i,line in ipairs(headline(row.headline,40,2)) do text(line,-322,43+(i-1)*16,0x1E2729) end
    text("Inventory → Newspaper",-322,82,0x6A543C)
    return out
  end
  local function mark(v,lane,cursor)
    if v.read[lane]~=cursor then
      v.read[lane]=cursor
      v.meta:set_int("luanttd_news_"..lane,cursor)
    end
  end
  local function pump(p,v)
    if not v.economy then return end
    local name=p:get_player_name()
    for _,lane in ipairs({"paper","ticker"}) do
      local a=v.active[lane]
      if a and now()>=a.until_ then remove(p,v,lane) end
      if not v.active[lane] then
        local row,cursor,mode=News.next_auto(v.queue,v.read[lane],lane,v.economy,v.prefs)
        mark(v,lane,row and cursor or math.max(cursor,v.received))
        if row then
          local length=mode==News.FULL and News.DURATION or mode==News.OFF and 3 or 7
          if sound then
            -- RC1 news_gui.cpp: summary uses the ticker cue, full
            -- news plays its type's effect, off/status is silent.
            local fx=mode==News.SUMMARY and "NEWS_TICKER"
              or mode==News.FULL and ((row.kind=="arrival_player" or row.kind=="arrival_other") and
                "APPLAUSE" or row.kind=="new_vehicles" and "NEW_ENGINE")
            if fx then sound(fx,{player=name}) end
          end
          local hud=lane=="paper" and bulletin(p,row) or status(p,row,mode)
          local item={hud=hud,row=row,until_=now()+length}
          v.active[lane]=item
          if lane=="paper" then v.current,v.forced=row.seq,nil end
          core.after(length,function()
            local live=core.get_player_by_name(name)
            if live and local_state[name]==v and v.active[lane]==item then
              remove(live,v,lane)
              if not v.cinematic then pump(live,v) end
            end
          end)
        end
      end
    end
    local min=math.min(v.read.ticker,v.read.paper)
    while v.queue[1] and v.queue[1].seq<=min do table.remove(v.queue,1) end
  end
  function U.observe(p,stats)
    if not stats or not stats.news_head then return end
    local v,n=state(p)
    v.economy=stats.world_day
    if stats.news_head<v.received then
      -- A crash can restore a prior checkpoint; don't let a persisted UI
      -- cursor suppress future headlines from the restored simulation.
      v.received=stats.news_head
      for _,lane in ipairs({"paper","ticker"}) do mark(v,lane,math.min(v.read[lane],v.received));remove(p,v,lane) end
      v.queue={}
    end
    if not v.cinematic then pump(p,v) end
    if stats.news_head<=v.received or v.fetch and v.fetch.deadline>now() or v.cinematic then return end
    local ticket={deadline=now()+2.0}
    v.fetch=ticket
    -- A best-effort read, not a deferred command: construction and other
    -- player actions always retain the worker mailbox priority.
    local read=client.observe or client.query
    local sent=read({kind="news",player=n,after=v.received},function(r)
      if local_state[n]~=v or v.fetch~=ticket then return end
      v.fetch=nil
      if not r.ok then return end
      v.economy=r.value.economy
      v.received=r.value.cursor
      for _,row in ipairs(r.value.items) do v.queue[#v.queue+1]=row end
      if not v.cinematic then pump(p,v) end
    end)
    if not sent then v.fetch=nil end
  end
  function U.cinematic(p,active)
    local v=state(p)
    v.cinematic=active
    if active then for lane in pairs(v.active) do remove(p,v,lane) end end
  end
  function U.leave(n) local_state[n]=nil end

  local function button(b,x,y,w,key,t,exit)
    b[#b+1]=("%s[%g,%g;%g,.59;%s;%s]"):format(exit and "button_exit" or "button",x,y,w,key,esc(t))
  end
  local function label(b,x,y,t,color)
    if color then t=core.colorize(color,t) end
    b[#b+1]=("label[%g,%g;%s]"):format(x,y,esc(t))
  end
  local function base(w,h)
    return {("formspec_version[7]size[%g,%g]bgcolor[#152334;false]"):format(w,h)}
  end
  local function show(n,b) core.show_formspec(n,U.form,table.concat(b)) end
  local function buttons(b)
    button(b,.43,7.87,3.29,"history","History")
    button(b,3.88,7.87,3.29,"last","Last message")
    button(b,7.33,7.87,3.29,"settings","News settings")
    button(b,.43,8.64,4.04,"dismiss","Dismiss alerts")
    button(b,6.58,8.64,4.04,"close","Back to world",true)
  end
  local function history(n,q)
    local b=base(11.05,9.53)
    label(b,.44,.43,"TRANSPORT GAZETTE  /  MESSAGE HISTORY","#F4D79E")
    label(b,.44,.92,q.note or "Newest first. Choose a headline to read the paper.","#D2E3E9")
    for i,row in ipairs(q.rows or {}) do
      label(b,.51,1.47+(i-1)*.68,date(row),"#B8CDD4")
      button(b,2.41,1.19+(i-1)*.68,8.18,"read_"..i,table.concat(headline(row.headline,57,1)))
    end
    if not q.rows or #q.rows==0 then label(b,.47,1.70,q.pending and "Reading the newspaper…" or "No news yet.") end
    local pages=math.max(1,math.ceil((q.count or 0)/8))
    if q.page>1 then button(b,.44,6.90,2.02,"prev","Previous") end
    label(b,4.71,7.18,("Page %d of %d"):format(q.page,pages))
    if q.page<pages then button(b,8.57,6.90,2.02,"next","Next") end
    buttons(b)
    show(n,b)
  end
  local function newspaper(n,v,q,row)
    q.article=row
    local b=base(11.05,9.53)
    b[#b+1]="box[.43,.39;10.19,7.07;"..paper.."]box[.44,1.75;10.16,.04;#7B6849]box[.44,6.96;10.16,.02;#A39171]"
    b[#b+1]="style_type[label;font=bold;font_size=+6]"
    label(b,.87,.92,"TRANSPORT GAZETTE","#152C33")
    b[#b+1]="style_type[label;font=normal;font_size=+0]"
    label(b,.89,1.43,date(row).."   /   "..News.category(row.kind)[4],"#59503E")
    b[#b+1]="style_type[label;font=bold;font_size=+3]"
    for i,line in ipairs(headline(row.headline,52,3)) do label(b,.89,2.17+(i-1)*.40,line,"#19282D") end
    b[#b+1]="style_type[label;font=normal;font_size=+0]"
    for i,line in ipairs(headline(row.body or row.headline,72,7)) do
      label(b,.90,3.53+(i-1)*.31,line,"#263436")
    end
    if row.tile then button(b,.89,5.85,3.59,"location","Go to this location") end
    label(b,.89,7.20,"CAMPAIGN EDITION   •   TRANSPORT & INDUSTRY","#66543C")
    buttons(b)
    show(n,b)
  end
  local function settings(n,v,q)
    local b=base(11.05,9.53)
    label(b,.44,.43,"Newspaper settings","#F4D79E")
    label(b,.44,.94,"Status only shows a reminder; Summary shows a headline; Full shows a bulletin.")
    for i,c in ipairs(News.categories) do
      local x=(i-1)%2*5.14+.45
      local y=1.23+math.floor((i-1)/2)*.69
      label(b,x,y+.25,c[4])
      b[#b+1]=("dropdown[%g,%g;2.05,.54;mode_%s;Status only,Summary,Full;%d;true]"):format(x+2.62,y,c[1],News.mode(v.prefs,c[1])+1)
    end
    button(b,.44,7.38,3.0,"reset","Restore defaults")
    button(b,3.67,7.38,3.0,"save","Save")
    button(b,7.57,7.38,3.0,"history","Back to history")
    button(b,6.57,8.64,4.04,"close","Back to world",true)
    show(n,b)
  end
  function U.open(p,page,note)
    local v,n=state(p)
    local q={page=page or 1,pending=true,note=note}
    v.panel=q
    history(n,q)
    local ok,why=client.query({kind="news",player=n,page=q.page},function(r)
      if local_state[n]~=v or v.panel~=q then return end
      q.pending=nil
      if r.ok then q.rows,q.count=r.value.items,r.value.count
      else q.note=r.why or "Could not read the newspaper." end
      history(n,q)
    end)
    if not ok then q.pending=nil;q.note=why or "Could not read the newspaper.";history(n,q) end
    return true
  end
  function U.fields(p,f)
    local v,n=state(p)
    local q=v.panel
    if not q then return true end
    if f.quit or f.close then v.panel=nil;return true end
    if f.history then return U.open(p,q.page) end
    if f.dismiss then
      for _,lane in ipairs({"paper","ticker"}) do remove(p,v,lane) end
      return U.open(p,q.page,"Alerts dismissed. Earlier items remain in history.")
    end
    if f.settings then q.settings=true;settings(n,v,q);return true end
    if q.settings then
      if f.reset then
        for _,c in ipairs(News.categories) do v.prefs[c[1]]=nil;v.meta:set_string("luanttd_news_"..c[1],"") end
        settings(n,v,q)
      elseif f.save then
        for _,c in ipairs(News.categories) do
          local i=tonumber(f["mode_"..c[1]])
          if i and i%1==0 and i>=1 and i<=3 then v.prefs[c[1]]=i-1;v.meta:set_string("luanttd_news_"..c[1],tostring(i-1)) end
        end
        return U.open(p,q.page,"News settings saved.")
      end
      return true
    end
    if q.pending then return true end
    if f.last then
      q.pending=true
      local sent,why=client.query({kind="news",player=n,action="last",current=v.current,forced=v.forced,
        shown=v.active.paper~=nil,modes=v.prefs},function(r)
        if local_state[n]~=v or v.panel~=q then return end
        q.pending=nil
        local row=r.ok and r.value and r.value.article
        if row then v.forced=row.seq;newspaper(n,v,q,row)
        else q.note=r.why or "No recent bulletin to show.";history(n,q) end
      end)
      if not sent then q.pending=nil;q.note=why;history(n,q) end
      return true
    end
    if q.article and f.location and q.article.tile then
      q.pending=true
      local sent,why=client.query({kind="jump_tile",player=n,tile=q.article.tile},function(r)
        if local_state[n]~=v or v.panel~=q then return end
        q.pending=nil
        if r.ok then
          v.panel=nil;core.close_formspec(n,U.form)
          p:set_pos({x=r.value.x,y=r.value.y,z=r.value.z})
        else q.note=r.why;history(n,q) end
      end)
      if not sent then q.pending=nil;q.note=why;history(n,q) end
      return true
    end
    if f.prev and q.page>1 then return U.open(p,q.page-1) end
    if f.next and q.page*8<(q.count or 0) then return U.open(p,q.page+1) end
    for i,row in ipairs(q.rows or {}) do
      if f["read_"..i] then v.forced=row.seq;newspaper(n,v,q,row);break end
    end
    return true
  end
  return U
end
