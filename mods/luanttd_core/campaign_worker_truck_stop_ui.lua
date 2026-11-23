-- Read physical catchment and waiting stock from the authoritative worker.
return function(core,client,number)
  local U={form="luanttd_core:worker_truck_stop"}
  local open={}
  local esc=core.formspec_escape
  local function paint(name,data,message)
    local cargo=data and data.cargo or {}
    local height=math.max(2.85,1.88+#cargo*.54)
    local form={("formspec_version[7]size[10.9,%g]bgcolor[#152334;false]"):format(height)}
    local function label(x,y,text) form[#form+1]=("label[%g,%g;%s]"):format(x,y,esc(text)) end
    label(.42,.42,data and data.name or "Truck stop")
    for i,row in ipairs(cargo) do
      label(.42,.43+i*.54,row.name)
      label(3.66,.43+i*.54,number(row.waiting).." waiting")
      label(6.13,.43+i*.54,row.collects and (row.accepts and "Collects and accepts" or "Collects") or
        (row.accepts and "Accepts deliveries" or "Waiting for pickup"))
      if row.rating then label(9.62,.43+i*.54,math.floor(row.rating*100/255+.5).."%") end
    end
    if #cargo==0 then label(.42,1.04,message or "No freight supplier or receiver is in this stop's catchment.") end
    form[#form+1]=("button_exit[.42,%g;10.06,.55;close;Back to world]"):format(height-.87)
    core.show_formspec(name,U.form,table.concat(form))
  end
  function U.open(player,tile)
    local n=player:get_player_name()
    local req={kind="truck_stop",player=n,tile=tile}
    open[n]=req
    paint(n,nil,"Reading the catchment…")
    local sent,why=(client.defer or client.query)(req,function(reply)
      if open[n]==req then paint(n,reply.value,reply.why) end
    end)
    if not sent then paint(n,nil,why) end
    return true
  end
  function U.fields(player,f)
    if f.quit or f.close then open[player:get_player_name()]=nil end
    return true
  end
  return U
end
