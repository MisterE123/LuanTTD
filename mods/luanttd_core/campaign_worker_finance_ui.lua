-- Native control-desk finance, entirely backed by the campaign owner.
return function(core,client,fmt,money)
  local M={form="luanttd_core:worker_finance"}
  local open={}
  local serial=0
  local function draw(player,v,note)
    local t=v.data or {}
    local function label(y,txt) return ("label[.45,%g;%s]"):format(y,core.formspec_escape(txt)) end
    local b={"formspec_version[7]size[8.9,5.7]bgcolor[#152334;false]",label(.4,"Finance"),
      label(.94,note or (t.year and fmt(t.year,t.month,t.day_of_month) or "Reading company ledger…"))}
    if t.cash then
      b[#b+1]=label(1.48,"Cash: "..money(t.cash).."   ·   Loan: "..money(t.loan))
      b[#b+1]=label(2,"Revenue this month: "..money(t.month_revenue or 0))
      b[#b+1]=label(2.44,"Costs this month: "..money(t.month_expense or 0))
      b[#b+1]=("button[.45,3.06;4,0.58;f%d_borrow;Borrow $10,000]button[4.55,3.06;3.86,.58;f%d_repay;Repay $10,000]")
        :format(v.id,v.id)
      if t.can_speed or core.check_player_privs and core.check_player_privs(player,{server=true}) then
        for i,speed in ipairs({0,1,2,4}) do
          b[#b+1]=("button[%g,3.77;1.9,.55;f%d_speed_%d;%s]"):format(.45+2*(i-1),v.id,speed,
            speed==0 and "Pause" or tostring(speed).."×")
        end
      end
    end
    b[#b+1]="button_exit[4.55,4.77;3.86,.58;close;Back to world]"
    core.show_formspec(player,M.form,table.concat(b))
  end
  function M.show(p,note)
    local name=p:get_player_name()
    serial=serial+1
    local v={id=serial}
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
    local command
    if f[stem.."borrow"] or f[stem.."repay"] then
      command={kind="company_loan",amount=f[stem.."borrow"] and 10000 or -10000}
    end
    for _,speed in ipairs({0,1,2,4}) do
      if f[stem.."speed_"..speed] then
        command={kind="speed",speed=speed,admin=core.check_player_privs and core.check_player_privs(name,{server=true})}
        break
      end
    end
    if not command then return true end
    command.revision=v.revision
    v.pending=true
    local queued,why=client.query({kind="command",player=name,command=command},function(r)
      if open[name]==v then M.show(p,r.why) end
    end)
    if not queued then v.pending=nil;draw(name,v,why) end
    return true
  end
  function M.leave(name) open[name]=nil end
  return M
end
