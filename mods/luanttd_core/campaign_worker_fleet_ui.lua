-- Compact paged company fleet, independent of what the 3D engine loaded.
return function(core,client,units)
  local F={form="luanttd_core:worker_fleet"}
  local panels,serial={},0
  local heading={road="Road",rail="Rail",ship="Ship",air="Air",tram="Tram"}
  local function draw(n,p,note)
    local m=p.data or {}
    local stem="f"..p.id.."_"
    local b={"formspec_version[7]size[10.8,7.25]bgcolor[#152334;false]",
      "label[.43,.42;Company fleet]",
      "label[.43,.95;"..core.formspec_escape(note or
        (m.total and ("%d vehicles · Page %d / %d"):format(m.total,m.page,m.pages) or "Loading your fleet…")).."]"}
    if m.records and #m.records>0 then
      local rows={}
      for i,r in ipairs(m.records) do rows[i]=core.formspec_escape((heading[r.mode] or "?").." · "..r.label) end
      b[#b+1]=("textlist[.43,1.25;9.94,3.84;%srow;%s;%d;false]"):format(stem,table.concat(rows,","),p.index or 1)
      b[#b+1]="button[.43,5.33;6.95,.53;"..stem.."open;Open vehicle and orders]"
      if m.page>1 then b[#b+1]="button[.43,6.22;2.65,.53;"..stem.."prev;Previous]" end
      if m.page<m.pages then b[#b+1]="button[3.16,6.22;2.65,.53;"..stem.."next;Next]" end
    elseif m.records then
      b[#b+1]="label[.43,1.55;Buy a vehicle at a depot to manage it here.]"
    end
    b[#b+1]="button_exit[7.47,6.22;2.9,.53;close;Back to world]"
    core.show_formspec(n,F.form,table.concat(b))
  end
  function F.open(p,page)
    local n=p:get_player_name()
    serial=serial+1
    local view={id=serial}
    panels[n]=view
    draw(n,view)
    local sent,why=client.query({kind="company_fleet",player=n,page=page or 1},function(reply)
      if panels[n]~=view then return end
      if reply.ok then view.data=reply.value end
      draw(n,view,reply.why)
    end)
    if not sent then draw(n,view,why) end
    return true
  end
  function F.fields(p,f)
    local n=p:get_player_name()
    local view=panels[n]
    if not view then return true end
    if f.quit or f.close then panels[n]=nil;return true end
    local data=view.data
    if not data then return true end
    local stem="f"..view.id.."_"
    if f[stem.."row"] then
      local e=core.explode_textlist_event(f[stem.."row"])
      if data.records[e.index] then view.index=e.index end
    end
    if f[stem.."prev"] and data.page>1 then return F.open(p,data.page-1) end
    if f[stem.."next"] and data.page<data.pages then return F.open(p,data.page+1) end
    if f[stem.."open"] then
      local row=data.records[view.index or 1]
      if row then
        return units.open(p,row.mode,row.id,{return_=function() F.open(p,data.page) end,directory=true})
      end
    end
    return true
  end
  function F.leave(n) panels[n]=nil end
  return F
end
