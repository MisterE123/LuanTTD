-- Compact paged company fleet, independent of what the 3D engine loaded.
return function(core,client,units)
  local F={form="luanttd_core:worker_fleet"}
  local panels,serial={},0
  local heading={road="Road",rail="Rail",ship="Ship",air="Air",tram="Tram"}
  local filters={"all","road","rail","ship","air","tram"}
  local index={all=1,road=2,rail=3,ship=4,air=5,tram=6}
  local function draw(n,p,note)
    local m=p.data or {}
    local stem="f"..p.id.."_"
    local status_y=p.confirm and ".95" or "1.60"
    local b={"formspec_version[7]size[10.8,7.25]bgcolor[#152334;false]",
      "label[.43,.42;"..(p.mode=="tram" and "Company streetcars" or "Company fleet").."]",
      "label[.43,"..status_y..";"..core.formspec_escape(note or
        p.note or (m.total and ("%d vehicles · Page %d / %d"):format(m.total,m.page,m.pages) or "Loading your fleet…")).."]"}
    if not p.confirm then
      b[#b+1]=("tabheader[.43,1.36;%sfilter;All,Road,Rail,Water,Air,Tram;%d;false;false]"):format(stem,index[p.mode or "all"] or 1)
    end
    if p.confirm then
      b[#b+1]="label[.43,1.45;"..core.formspec_escape("Retire "..p.confirm.label.."?").."]"
      b[#b+1]="label[.43,2.03;The service ends. Tracks and stops remain. There is no resale credit.]"
      if not p.pending then
        b[#b+1]="button[.43,3.1;4.22,.64;"..stem.."confirm;Retire this vehicle]"
        b[#b+1]="button[4.95,3.1;4.1,.64;"..stem.."cancel;Keep it running]"
      end
    elseif m.records and #m.records>0 then
      local rows={}
      for i,r in ipairs(m.records) do rows[i]=core.formspec_escape((heading[r.mode] or "?").." · "..r.label) end
      b[#b+1]=("textlist[.43,1.97;9.94,3.13;%srow;%s;%d;false]"):format(stem,table.concat(rows,","),p.index or 1)
      b[#b+1]="button[.43,5.33;6.15,.53;"..stem.."open;Open vehicle and orders]"
      if p.mode=="tram" then
        b[#b+1]="button[6.76,5.33;3.59,.53;"..stem.."retire;Retire selected]"
      end
      if m.page>1 then b[#b+1]="button[.43,6.22;2.65,.53;"..stem.."prev;Previous]" end
      if m.page<m.pages then b[#b+1]="button[3.16,6.22;2.65,.53;"..stem.."next;Next]" end
    elseif m.records then
      b[#b+1]="label[.43,2.22;"..(p.mode=="tram" and "No streetcars. Use Streetcar orders to start one." or
        "Buy a vehicle at a depot to manage it here.").."]"
    end
    b[#b+1]="button_exit[7.47,6.22;2.9,.53;close;Back to world]"
    core.show_formspec(n,F.form,table.concat(b))
  end
  function F.open(p,page,mode,note)
    local n=p:get_player_name()
    serial=serial+1
    local view={id=serial,mode=mode,note=note}
    panels[n]=view
    draw(n,view)
    local sent,why=client.query({kind="company_fleet",player=n,page=page or 1,mode=mode},function(reply)
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
    local stem="f"..view.id.."_"
    local pick=not view.confirm and filters[tonumber(f[stem.."filter"])]
    if pick and pick~=(view.mode or "all") then
      return F.open(p,1,pick~="all" and pick or nil)
    end
    local data=view.data
    if not data then return true end
    if view.confirm then
      if view.pending then return true end
      if f[stem.."cancel"] then view.confirm=nil;draw(n,view);return true end
      if f[stem.."confirm"] then
        local target=view.confirm
        view.pending=true
        draw(n,view,"Retiring selected streetcar…")
        local function finish(result)
          if panels[n]~=view then return end
          if result.ok then return F.open(p,data.page,view.mode,result.why or "Streetcar retired.") end
          view.pending,view.confirm=nil,nil
          draw(n,view,result.why or "Streetcar could not be retired.")
        end
        local sent,why=client.query({kind="company",player=n},function(company)
          if panels[n]~=view then return end
          if not company.ok then finish(company);return end
          local ok,note=client.query({kind="command",player=n,command={
            kind="transport_start",mode="tram",clear=true,vehicle=target.id,
            retirement=target.retirement,revision=company.revision}},finish)
          if not ok then finish({why=note}) end
        end)
        if not sent then finish({why=why}) end
      end
      return true
    end
    if f[stem.."row"] then
      local e=core.explode_textlist_event(f[stem.."row"])
      if data.records[e.index] then view.index=e.index end
    end
    if f[stem.."prev"] and data.page>1 then return F.open(p,data.page-1,view.mode) end
    if f[stem.."next"] and data.page<data.pages then return F.open(p,data.page+1,view.mode) end
    if f[stem.."retire"] and view.mode=="tram" then
      local row=data.records[view.index or 1]
      if row and row.mode=="tram" and row.retirement then
        view.confirm=row
        draw(n,view)
      end
      return true
    end
    if f[stem.."open"] then
      local row=data.records[view.index or 1]
      if row then
        return units.open(p,row.mode,row.id,{return_=function() F.open(p,data.page,view.mode) end,directory=true})
      end
    end
    return true
  end
  function F.leave(n) panels[n]=nil end
  return F
end
