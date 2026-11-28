-- Native control-desk finance, entirely backed by the campaign owner.
return function(core,client,fmt,money,view_hq,found_town)
  local M={form="luanttd_core:worker_finance"}
  local open={}
  local growth_names="None,Slow,Normal,Fast,Very fast"
  local cargo_modes="Quadratic (original),Linear"
  local founding_modes="Forbidden,Allowed,Custom layout"
  local serial=0
  local function draw(player,v,note)
    local t=v.data or {}
    local function label(y,txt) return ("label[.45,%g;%s]"):format(y,core.formspec_escape(txt)) end
    local admin=core.check_player_privs and core.check_player_privs(player,{server=true})
    local growth=t.world_town_growth
    local world_controls=growth~=nil and (t.can_speed or admin)
    if world_controls and v.in_found_rules and t.town_founding~=nil then
      local b={"formspec_version[7]size[8.9,4.40]bgcolor[#152334;false]",label(.4,"Town founding rules"),
        label(.96,"Allowed uses the world's road layout."),
        label(1.40,"Custom layout lets each company choose its own."),
        ("dropdown[.45,1.77;5.55,.63;f%d_founding;%s;%d;true]")
          :format(v.id,founding_modes,(v.selected_founding or t.town_founding)+1),
        ("button[6.2,1.77;2.2,.58;f%d_apply_founding;Apply]"):format(v.id),
        label(2.76,note or "These rules do not change towns that already exist."),
        ("button[.45,3.42;4,.58;f%d_back_rules;Back to world rules]"):format(v.id),
        "button_exit[4.55,3.42;3.86,.58;close;Back to world]"}
      core.show_formspec(player,M.form,table.concat(b))
      return
    end
    if world_controls and v.in_rules then
      local b={"formspec_version[7]size[8.9,5.03]bgcolor[#152334;false]",label(.4,"World rules"),
        label(.99,"Town growth (all towns)"),
        ("dropdown[.45,1.25;5.55,.63;f%d_growth;%s;%d;true]"):format(v.id,growth_names,(v.selected_growth or growth)+1),
        ("button[6.2,1.25;2.2,.58;f%d_apply_growth;Apply]"):format(v.id)}
      if t.world_town_cargo~=nil then
        b[#b+1]=label(2.08,"Town cargo generation")
        b[#b+1]=("dropdown[.45,2.34;5.55,.63;f%d_cargo;%s;%d;true]")
          :format(v.id,cargo_modes,(v.selected_cargo or t.world_town_cargo)+1)
        b[#b+1]=("button[6.2,2.34;2.2,.58;f%d_apply_cargo;Apply]"):format(v.id)
      end
      if t.town_founding~=nil then
        b[#b+1]=("button[.45,3.02;4,.43;f%d_founding_rules;Town founding rules]"):format(v.id)
      end
      b[#b+1]=label(3.49,note or "Changes affect future updates, not existing cargo.")
      b[#b+1]=("button[.45,4.08;4,.58;f%d_back_finance;Back to finance]"):format(v.id)
      b[#b+1]="button_exit[4.55,4.08;3.86,.58;close;Back to world]"
      core.show_formspec(player,M.form,table.concat(b))
      return
    end
    local b={"formspec_version[7]size[8.9,6.65]bgcolor[#152334;false]",label(.4,"Finance"),
      label(.94,note or (t.year and fmt(t.year,t.month,t.day_of_month) or "Reading company ledger…"))}
    if t.cash then
      b[#b+1]=label(1.48,"Cash: "..money(t.cash).."   ·   Loan: "..money(t.loan))
      b[#b+1]=label(2,"Revenue this month: "..money(t.month_revenue or 0))
      b[#b+1]=label(2.44,"Costs this month: "..money(t.month_expense or 0))
      b[#b+1]=("button[.45,3.06;4,0.58;f%d_borrow;Borrow $10,000]button[4.55,3.06;3.86,.58;f%d_repay;Repay $10,000]")
        :format(v.id,v.id)
      if t.can_speed or admin then
        for i,speed in ipairs({0,1,2,4}) do
          b[#b+1]=("button[%g,3.77;1.9,.55;f%d_speed_%d;%s]"):format(.45+2*(i-1),v.id,speed,
            speed==0 and "Pause" or tostring(speed).."×")
        end
      end
    end
    if t.hq then
      b[#b+1]=label(4.55,("Company value: %s  ·  Performance: %d / 1000"):format(money(t.hq.value),t.hq.score))
      if t.hq.tile and view_hq then
        b[#b+1]=("button[.45,5.26;4,.55;f%d_view_hq;View headquarters]"):format(v.id)
      elseif not t.hq.tile then
        b[#b+1]=label(5.28,"Place your HQ from the Company hotbar.")
      end
    end
    if found_town and (t.town_founding or 0)>0 then
      b[#b+1]=("button[4.55,5.09;3.86,.58;f%d_found_town;Found town here]"):format(v.id)
      b[#b+1]=("tooltip[f%d_found_town;Aim at a flat site before opening Finance.]"):format(v.id)
    end
    if world_controls then
      b[#b+1]=("button[.45,5.74;4,.58;f%d_world_rules;World rules]"):format(v.id)
    end
    b[#b+1]="button_exit[4.55,5.74;3.86,.58;close;Back to world]"
    core.show_formspec(player,M.form,table.concat(b))
  end
  function M.show(p,note,in_rules,in_found_rules)
    local name=p:get_player_name()
    serial=serial+1
    local v={id=serial,in_rules=in_rules,in_found_rules=in_found_rules}
    open[name]=v
    draw(name,v,note)
    local queued,why=client.query({kind="company",player=name},function(r)
      if open[name]~=v then return end
      if r.ok then v.data,v.revision=r.value,r.revision end
      draw(name,v,note or r.why)
    end)
    if not queued then draw(name,v,why) end
    return true
  end
  function M.fields(p,f)
    local name=p:get_player_name()
    local v=open[name]
    if not v then return true end
    if f.quit then open[name]=nil;return true end
    if v.pending or not v.revision then return true end
    local stem="f"..v.id.."_"
    if f[stem.."view_hq"] and v.data.hq and v.data.hq.tile and view_hq then
      open[name]=nil
      core.close_formspec(name,M.form)
      view_hq(p,v.data.hq.tile)
      return true
    end
    if f[stem.."found_town"] and found_town and (v.data.town_founding or 0)>0 then
      open[name]=nil
      return found_town(p,v.data.town_founding,v.data.town_layout)
    end
    local command
    local admin=core.check_player_privs and core.check_player_privs(name,{server=true})
    if v.data.world_town_growth~=nil and (v.data.can_speed or admin) then
      if f[stem.."world_rules"] and not v.in_rules then
        v.in_rules=true
        draw(name,v)
        return true
      end
      if v.in_found_rules then
        if f[stem.."back_rules"] then
          v.in_found_rules,v.selected_founding=nil,nil
          draw(name,v)
          return true
        end
        local selected=tonumber(f[stem.."founding"])
        if selected==1 or selected==2 or selected==3 then v.selected_founding=selected-1 end
        if f[stem.."apply_founding"] and v.selected_founding~=nil and v.data.town_founding~=nil then
          command={kind="town_founding_setting",policy=v.selected_founding,admin=admin}
        else return true end
      elseif v.in_rules then
        if f[stem.."founding_rules"] and v.data.town_founding~=nil then
          v.in_found_rules=true
          draw(name,v)
          return true
        end
        if f[stem.."back_finance"] then
          v.in_rules,v.selected_growth,v.selected_cargo=nil,nil,nil
          draw(name,v)
          return true
        end
        local selection=tonumber(f[stem.."growth"])
        if selection and selection%1==0 and selection>=1 and selection<=5 then v.selected_growth=selection-1 end
        local cargo=tonumber(f[stem.."cargo"])
        if cargo==1 or cargo==2 then v.selected_cargo=cargo-1 end
        if f[stem.."apply_cargo"] and v.selected_cargo~=nil and v.data.world_town_cargo~=nil then
          command={kind="town_cargo_setting",mode=v.selected_cargo,admin=admin}
        elseif f[stem.."apply_growth"] and v.selected_growth~=nil then
          command={kind="town_growth_setting",rate=v.selected_growth,admin=admin}
        else return true end
      end
    end
    if f[stem.."borrow"] or f[stem.."repay"] then
      command={kind="company_loan",amount=f[stem.."borrow"] and 10000 or -10000}
    end
    for _,speed in ipairs({0,1,2,4}) do
      if f[stem.."speed_"..speed] then
        command={kind="speed",speed=speed,admin=admin}
        break
      end
    end
    if not command then return true end
    command.revision=v.revision
    v.pending=true
    local queued,why=client.query({kind="command",player=name,command=command},function(r)
      if open[name]==v then
        local founding=command.kind=="town_founding_setting"
        local rules=founding or command.kind=="town_growth_setting" or command.kind=="town_cargo_setting"
        M.show(p,r.why,rules,founding)
      end
    end)
    if not queued then v.pending=nil;draw(name,v,why) end
    return true
  end
  function M.leave(name) open[name]=nil end
  return M
end
