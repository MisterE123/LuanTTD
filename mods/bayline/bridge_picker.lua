-- OpenTTD construction flow: select a span, then choose an available
-- bridge type and confirm the exact purchase. Geometry, availability,
-- prices and mutations still belong to the source-based span hosts.
return function(api)
  local W,S,Sim={form="bayline:bridge_picker"},api.s,api.Sim
  local pending,latest,serial={},{},0
  local styles={[0]="Timber",[1]="Concrete",[2]="Steel girder"}
  local function valid(id)
    return type(id)=="number" and id%1==0 and id>=1 and id<=Sim.W*Sim.H and S.tiles[id]
  end
  local function evaluate(mode,n,a,b)
    if not valid(a) or not valid(b) or a==b then return nil,"Choose two distinct bridgeheads." end
    if not S.companies[n] then return nil,"Create your company first." end
    local offers,why={}
    for style=0,mode=="road" and 2 or 0 do
      local plan,reason
      if mode=="road" and api.structure_tools then
        local ok,cost,p=Sim.road_bridge(S,n,a,b,style,true)
        if ok then plan=p else reason=cost end
      elseif mode=="rail" and api.rail_spans then
        plan,reason=api.rail_spans.quote_bridge(S,n,a,b)
      else return nil,"Bridge construction is not available in this world." end
      if plan then
        offers[#offers+1]={style=style,name=styles[style],price=plan.price,
          speed=plan.spec and plan.spec.speed or nil,plan=plan}
      else why=why or reason end
    end
    if #offers==0 then return nil,why or "No available bridge fits this span." end
    local p=offers[1].plan
    local ids={p.start}
    for _,i in ipairs(p.middle) do ids[#ids+1]=i end
    ids[#ids+1]=p["end"]
    local minimum=offers[1].price
    for i=2,#offers do minimum=math.min(minimum,offers[i].price) end
    return {ids=ids,minimum=minimum,offers=offers}
  end
  function W.quote(mode,n,a,b) return evaluate(mode,n,a,b) end
  local function buy(n,ticket,style)
    if S.topology~=ticket.topology or not S.corner_grid or S.corner_grid.revision~=ticket.corners then
      return false,"The span changed. Select both bridgeheads again."
    end
    local updated,reason=evaluate(ticket.mode,n,ticket.a,ticket.b)
    if not updated then return false,reason end
    local offer
    for _,o in ipairs(updated.offers) do if o.style==style then offer=o;break end end
    if not offer then return false,"That bridge is no longer available. Select the span again." end
    if ticket.prices[style]~=offer.price then return false,"The bridge price changed. Select the span again." end
    local ok,note,dirty,deck
    if ticket.mode=="road" then ok,note,dirty,deck=Sim.road_bridge(S,n,ticket.a,ticket.b,style)
    else ok,note,dirty,deck=api.rail_spans.commit(S,n,offer.plan) end
    if ok then
      latest[n]=latest[n] or {}
      latest[n][ticket.mode]=style
      api.render.raise_bound(deck)
      api.render.update(dirty)
      api.save()
    end
    return ok,note
  end
  local function money(amount)
    return "$"..tostring(amount):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
  end
  function W.open(player,mode,a,b,callback)
    local n=player:get_player_name()
    local proposal,why=evaluate(mode,n,a,b)
    if not proposal then return nil,why end
    serial=serial+1
    local ticket={n=serial,mode=mode,a=a,b=b,prices={},topology=S.topology,
      corners=S.corner_grid.revision,callback=callback}
    for _,o in ipairs(proposal.offers) do ticket.prices[o.style]=o.price end
    local controls=player:get_player_control()
    local last=latest[n] and latest[n][mode]
    if controls and controls.aux1 and last and ticket.prices[last] then
      pending[n]=nil
      local ok,msg=buy(n,ticket,last)
      if callback then callback(ok,msg) end
      return true
    end
    pending[n]=ticket
    local esc=core.formspec_escape
    local size=2.8+#proposal.offers*.8
    local bspec={("formspec_version[7]size[10,%g]bgcolor[#152334;false]"):format(size),
      "style_type[button;bgimg=bl_button.png;bgimg_middle=6;border=false;textcolor=#E5ECEA]",
      "style_type[label;textcolor=#E5ECEA]",
      ("label[.45,.47;Choose a %s bridge]"):format(mode=="road" and "road" or "railway"),
      ("label[.45,.95;%d tiles including both ramps]"):format(#proposal.ids)}
    for i,o in ipairs(proposal.offers) do
      local label=o.name..(o.speed and ("  ·  %d km/h"):format(o.speed) or "").."  ·  "..money(o.price)
      bspec[#bspec+1]=("button_exit[.45,%g;9.1,.66;bridge_%d_%d;%s]"):format(1.24+(i-1)*.8,serial,o.style,esc(label))
    end
    bspec[#bspec+1]=("button_exit[.45,%g;9.1,.65;cancel;Cancel]"):format(size-.85)
    core.show_formspec(n,W.form,table.concat(bspec))
    return true
  end
  function W.fields(player,form,fields)
    if form~=W.form then return false end
    local n=player:get_player_name()
    local ticket=pending[n]
    if not ticket then return true end
    local selected
    for name in pairs(fields) do
      local issue,style=name:match("^bridge_(%d+)_(%d+)$")
      if tonumber(issue)==ticket.n and ticket.prices[tonumber(style)] then selected=tonumber(style);break end
    end
    if selected~=nil then
      pending[n]=nil
      local ok,msg=buy(n,ticket,selected)
      if ticket.callback then ticket.callback(ok,msg) end
    elseif fields.quit or fields.cancel then
      pending[n]=nil
      if ticket.callback then ticket.callback(false,"Bridge selection canceled.") end
    end
    return true
  end
  function W.leave(n) pending[n],latest[n]=nil,nil end
  return W
end
