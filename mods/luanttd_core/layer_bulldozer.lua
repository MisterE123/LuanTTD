-- Single-choice, server-authoritative confirmation. This is not an area
-- demolisher or a second infrastructure write path.
return function(api,clear_structure,status)
  local S,Sim,R=api.s,api.Sim,api.render
  local B={form="luanttd_core:demolish_layers"}
  local pending,serial={},0
  local mod=(core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  B.choices=dofile(mod.."/demolition_layer_choices.lua")(api,clear_structure)
  local function show(p,id,choices,remote)
    local n=p:get_player_name()
    local x,z=Sim.xy(id)
    serial=serial+1
    pending[n]={id=id,topology=S.topology,options=choices,token=serial,remote=remote}
    local h=2.20+#choices*1.09
    local esc=core.formspec_escape
    local b={("formspec_version[7]size[12.4,%g]bgcolor[#152334;false]"):format(h),
      "style_type[label;textcolor=#E5ECEA]style_type[button;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA]",
      ("label[.42,.47;Bulldozer / tile %d, %d]"):format(x,z),
      "label[.42,.96;Confirm the layer you intend to remove. Nothing has changed yet.]"}
    for i,o in ipairs(choices) do
      local y=1.25+(i-1)*1.09
      if o.ok then b[#b+1]=("button[.42,%g;11.56,.47;bulldoze_%d_%d;%s]"):format(y,serial,i,esc(o.title))
      else b[#b+1]=("label[.42,%g;%s]"):format(y+.24,esc(o.title.." / unavailable")) end
      b[#b+1]=("textarea[.42,%g;11.56,.64;;;%s]"):format(y+.49,esc(o.detail))
    end
    b[#b+1]=("button_exit[.42,%g;11.56,.51;cancel_layers;Cancel]"):format(h-.68)
    core.show_formspec(n,B.form,table.concat(b))
    return true
  end
  local fetching={}
  function B.open(p,id,empty)
    local n=p:get_player_name()
    if api.authority_handoff then
      local client=api.worker_layer_client
      if not client then status(p,"The campaign worker is not ready.");return true end
      local request={}
      pending[n]=nil
      fetching[n]=request
      local ok,why=client.query({kind="demolition",player=n,tile=id},function(r)
        if fetching[n]~=request then return end
        fetching[n]=nil
        if not r.ok then status(p,r.why);return end
        if #r.value.options==0 then
          if empty then empty() else status(p,"No removable layers here.") end
          return
        end
        show(p,id,r.value.options,{token=r.value.token,revision=r.revision})
      end)
      if not ok then fetching[n]=nil;status(p,why) end
      return true
    end
    local choices=B.choices(n,id)
    if #choices==0 then return false end
    return show(p,id,choices)
  end
  function B.fields(p,f)
    local n=p:get_player_name()
    local q=pending[n]
    if not q then return true end
    if f.quit or f.cancel_layers then pending[n]=nil;status(p,"Demolition canceled.");return true end
    local index
    for key in pairs(f) do
      local a,b=key:match("^bulldoze_(%d+)_(%d+)$")
      if tonumber(a)==q.token then
        if index then return true end
        index=tonumber(b)
      end
    end
    local prior=index and q.options[index]
    if not prior or not prior.ok then return true end
    pending[n]=nil
    core.close_formspec(n,B.form)
    if q.remote then
      local client=api.worker_layer_client
      local ok,why=client.query({kind="command",player=n,command={kind="demolition",token=q.remote.token,
        revision=q.remote.revision,layer=prior.key}},function(r)
        status(p,r.why or (r.ok and "Layer removed." or "Layer removal canceled."))
      end)
      if not ok then status(p,why) end
      return true
    end
    local fresh
    if q.topology==S.topology then
      for _,o in ipairs(B.choices(n,q.id)) do
        if o.key==prior.key and o.ok and o.detail==prior.detail then fresh=o;break end
      end
    end
    if not fresh then status(p,"The tile or quote changed. Select it again.");return true end
    local _,ids,note,level=fresh.apply()
    status(p,note or "Layer removal canceled.")
    if ids then
      if level then R.raise_bound(level) end
      if #ids>0 then R.update(ids);api.save() end
    end
    return true
  end
  function B.leave(n) pending[n]=nil;fetching[n]=nil end
  return B
end
