-- Shared Luanti interaction for actual simulation vehicles. ObjectRefs are
-- presentation only: each action resolves the owner and vehicle again.
return function(api)
  local S,Sim=api.s,api.Sim
  local V={orders={}}
  local bodies=setmetatable({},{__mode="k"})
  local poses,panels,following={},{},{}
  local seq=0
  local now=0
  local projection
  local projected={}
  function V.use_worker_projection(view)
    projection=view
    projected=view and view.actors() or {}
  end
  local form="luanttd_core:vehicle_details"
  local anchor="luanttd_core:vehicle_camera"
  local esc=core.formspec_escape
  local box={road={-.48,-.28,-.64,.48,.55,.64},rail={-.45,-.32,-.59,.45,.66,.59},
    tram={-.48,-.32,-.75,.48,.58,.75},ship={-.90,-.45,-1.45,.90,1.05,1.45},
    air={-1.20,-.40,-1.00,1.20,.72,1.00}}
  local function key(kind,id) return kind..":"..id end
  local function own(record,name)
    return record and record.owner==name and record
  end
  local function get(n,kind,id)
    if projection then
      local row=projected[key(kind,id)]
      if not row or row.owner~=n then return end
      local depot=row.home_depot or row.depot
      return {kind=kind,id=id,label=row.label or ("Vehicle #"..id),source=row,
        depot=kind~="ship" and depot or nil,depot_key=depot}
    end
    local source,depot,depot_key,label
    if kind=="road" then
      source=own(S.fleet[id],n)
      if source then depot,label=source.home_depot or source.depot,source.name end
    elseif kind=="rail" and api.rail_owned then
      source=api.rail_owned.get(S,n,id)
      if source then depot,label=source.depot,"Train "..source.unit_number end
    elseif kind=="tram" and id==1 then
      source=own(S.tram_pilot,n)
      if source then depot,label=source.depot or source.legs[1].source,"Streetcar" end
    elseif kind=="ship" then
      source=own(id=="ferry" and S.stock_owned_ferry or id=="coal" and S.stock_coal_ship,n)
      if source then
        local record=S.stock_ship_depots and S.stock_ship_depots[source.depot]
        depot_key=source.depot
        depot=record and record.tiles[1]
        label=id=="coal" and "Yate Cargo Ship" or source.engine_id==207 and "FFP Passenger Ferry" or "MPS Passenger Ferry"
      end
    elseif kind=="air" then
      source=own((S.stock_owned_air_fleet or {})[id] or id==1 and S.stock_owned_aircraft,n)
      if source then
        local field=S.stock_small_airports and S.stock_small_airports[source.hangar]
        depot_key=source.hangar
        depot=field and field.origin
        label=(source.name or "Aircraft").." #"..id
      end
    end
    if source then return {kind=kind,id=id,source=source,label=label or ("Vehicle #"..id),depot=depot,depot_key=depot_key or depot} end
  end
  function V.track(kind,id,pos,ref,primary)
    if not id then return end
    if pos and primary~=false then poses[key(kind,id)]={pos=pos,time=now} end
    if ref and bodies[ref]==nil then
      local obj=ref:get_luaentity()
      if obj then
        local pick={kind=kind,id=id}
        obj.luanttd_vehicle=pick
        obj.on_rightclick=function(_,player)
          if api.world then api.world.select_vehicle(player,pick) end
        end
        bodies[ref]=pick
        ref:set_properties({pointable=true,selectionbox=box[kind]})
      end
    end
  end
  function V.pick(p,dist)
    local a=p:get_pos()
    if not a then return end
    local dir=p:get_look_dir()
    local o=p:get_properties().eye_height or 1.625
    a={x=a.x,y=a.y+o,z=a.z}
    local tail={x=a.x+dir.x*dist,y=a.y+dir.y*dist,z=a.z+dir.z*dist}
    for hit in core.raycast(a,tail,true,false) do
      if hit.type=="node" then return end
      local ref=hit.ref
      if ref and not ref:is_player() then
        local ent=ref:get_luaentity()
        local v=bodies[ref] or ent and ent.luanttd_vehicle
        if v then return v end
      end
    end
  end
  local function depotpos(v)
    local id=v.depot
    if not id then return end
    local x,z=Sim.xy(id)
    if not x then return end
    local row=projection and projection.terrain(x,z)
    local tile=not projection and S.tiles[id]
    local h=row and row.level or tile and tile.h
    if not h then return end
    return {x=2*x+.5,y=h+.75,z=2*z+.5}
  end
  local function position(v,last)
    local a=poses[key(v.kind,v.id)]
    if a and now-a.time<=.7 then return a.pos end
    -- A vehicle in a tunnel or temporarily hidden must not snap the
    -- camera back to its home depot. Follow resumes as soon as it emerges.
    return last or depotpos(v)
  end
  core.register_entity(anchor,{
    initial_properties={physical=false,collide_with_objects=false,pointable=false,
      static_save=false,is_visible=false,visual="sprite",textures={"blank.png"}},
  })
  local function close(p) core.close_formspec(p:get_player_name(),form) end
  function V.following(p) return following[p:get_player_name()]~=nil end
  function V.exit(p)
    local n=p:get_player_name()
    local f=following[n]
    if not f then return false end
    following[n]=nil
    if p:get_attach()==f.anchor then p:set_detach() end
    if f.anchor and f.anchor:get_pos() then f.anchor:remove() end
    p:set_pos(f.return_pos)
    p:set_look_horizontal(f.yaw);p:set_look_vertical(f.pitch)
    p:hud_remove(f.hud)
    if api.world and api.world.follow_hud then api.world.follow_hud(p,false) end
    if api.vehicle_status then api.vehicle_status(p,"Returned to the builder camera.") end
    return true
  end
  function V.follow(p,kind,id)
    local n=p:get_player_name()
    local v=get(n,kind,id)
    local pos=v and position(v)
    if not pos or p:get_attach() or following[n] then return false end
    local yaw=p:get_look_horizontal()
    local offset={x=2.8*math.sin(yaw),y=3.6,z=-2.8*math.cos(yaw)}
    local view={x=pos.x+offset.x,y=pos.y+offset.y,z=pos.z+offset.z}
    local camera=core.add_entity(view,anchor)
    if not camera then return false end
    local f={anchor=camera,kind=kind,id=id,return_pos=p:get_pos(),yaw=p:get_look_horizontal(),
      pitch=p:get_look_vertical(),last=view,vehicle_pos=pos,offset=offset}
    following[n]=f
    -- The unrotated anchor follows translation, never the vehicle mesh's roll or turns.
    p:set_attach(camera,"",{x=0,y=0,z=0},{x=0,y=0,z=0},false)
    p:set_look_vertical(1.08)
    if api.world and api.world.follow_hud then api.world.follow_hud(p,true) end
    f.hud=p:hud_add({type="text",position={x=.5,y=.88},alignment={x=0,y=0},
      text="Following "..v.label.."   ·   Right-click to return",number=0xffedbe,z_index=110})
    panels[n]=nil;close(p)
    return true
  end
  function V.step(dt)
    now=now+dt
    for _,p in ipairs(core.get_connected_players()) do
      local n=p:get_player_name()
      local f=following[n]
      if f then
        local v=get(n,f.kind,f.id)
        local pos=v and position(v,f.vehicle_pos)
        if not pos or not f.anchor:get_pos() or p:get_attach()~=f.anchor then V.exit(p)
        else
          f.vehicle_pos=pos
          local o=f.offset
          local x,y,z=pos.x+o.x,pos.y+o.y,pos.z+o.z
          if x~=f.last.x or y~=f.last.y or z~=f.last.z then
            f.last={x=x,y=y,z=z};f.anchor:move_to(f.last,true)
          end
        end
      end
    end
    for k,a in pairs(poses) do if now-a.time>2 then poses[k]=nil end end
  end
  function V.leave(p)
    local n=p:get_player_name()
    V.exit(p);panels[n]=nil
  end
  local function title(txt,height)
    return ("formspec_version[7]size[11,%g]bgcolor[#152334;false]"):format(height or 8)..
      "style_type[label;textcolor=#E5ECEA]"..
      "style_type[button;bgimg=bl_button.png;bgimg_middle=6;border=false;textcolor=#E5ECEA]"..
      "label[.45,.42;"..esc(txt).."]"
  end
  local function texts(rows,empty)
    local a={}
    for i,row in ipairs(rows) do a[i]=esc(row.label or tostring(row.id)) end
    return #a>0 and table.concat(a,",") or esc(empty)
  end
  local function show(p,panel,b)
    seq=seq+1;panel.token=seq
    panels[p:get_player_name()]=panel
    core.show_formspec(p:get_player_name(),form,b:gsub("V_TOKEN_",("v%d_"):format(seq)))
    return true
  end
  local function draw_orders(p,v,kind,id,back,prior,note,data,why)
    local cargo=data and data.cargo_rules
    local b=title(v.label,cargo and 9).."button[7.94,.22;2.61,.62;V_TOKEN_follow;Follow vehicle]"
    if note or data and data.summary then
      b=b..("textarea[.45,%g;10,.63;;;%s]"):format(cargo and 7.56 or 6.35,esc(note or data.summary))
    end
    if data then
      local items,targets=data.items or {},data.targets or {}
      local row=math.max(1,math.min(#items,prior and prior.row or 1))
      local target=math.max(1,math.min(#targets,prior and prior.target or 1))
      local labels={}
      for i,o in ipairs(items) do labels[i]={label=(data.active==i and "▶ " or "   ")..i..". "..(o.label or tostring(o.id))} end
      b=b.."label[.45,1.05;Orders]label[5.65,1.05;Available destinations]"..
        ("textlist[.45,1.30;4.98,3.72;V_TOKEN_row;%s;%d;false]"):format(texts(labels,"(No orders)"),row)..
        ("textlist[5.55,1.30;5,3.72;V_TOKEN_target;%s;%d;false]"):format(texts(targets,"(No destinations)"),target)
      if data.can_reorder~=false then
        b=b.."button[.45,5.16;1.53,.57;V_TOKEN_up;Move up]button[2.07,5.16;1.64,.57;V_TOKEN_down;Move down]"
      end
      if data.can_remove~=false then b=b.."button[3.80,5.16;1.63,.57;V_TOKEN_remove;Remove]" end
      if data.can_skip~=false then b=b.."button[.45,5.78;4.98,.53;V_TOKEN_skip;Skip to selected order]" end
      if data.can_insert~=false and #targets>0 then
        b=b.."button[5.55,5.16;5,.57;V_TOKEN_append;Add selected destination]"
      end
      if data.can_replace then
        b=b.."button[5.55,5.78;5,.53;V_TOKEN_replace;Replace selected order]"
      else b=b.."label[5.65,5.99;Select an order or a destination first.]" end
      if cargo and items[row] and items[row].cargo then
        local f=items[row].cargo
        b=b.."label[.45,6.53;Cargo rules for selected order]"
        for i,k in ipairs({"load","unload"}) do
          local x=i==1 and .45 or 5.55
          local rows,selected={},1
          for j,o in ipairs(cargo[k]) do
            rows[j]=esc(o.label)
            if o.value==f[k] then selected=j end
          end
          b=b..("dropdown[%g,6.86;3.32,.53;V_TOKEN_choose_%s;%s;%d;true]"):format(x,k,table.concat(rows,","),selected)
            ..("button[%g,6.86;1.53,.53;V_TOKEN_apply_%s;Apply]"):format(x+3.43,k)
        end
      end
      prior={row=row,target=target,revision=data.revision,targets=targets,item_count=#items,cargo=cargo}
    else
      b=b.."textarea[.45,1.22;10,1.35;;;"..esc(why or "Set initial orders from the depot. No editable orders are available for this vehicle yet.").."]"
      prior={}
    end
    local footer=cargo and 8.15 or 7.11
    if back then b=b..("button[.45,%g;4.98,.57;V_TOKEN_depot;Depot vehicles]"):format(footer) end
    b=b..("button_exit[5.55,%g;5,.57;V_TOKEN_close;Back to world]"):format(footer)
    prior.kind,prior.id,prior.back=kind,id,back
    return show(p,prior,b)
  end
  function V.open(p,kind,id,back,prior,note)
    local n=p:get_player_name()
    local v=get(n,kind,id)
    if not v then
      if api.vehicle_status then api.vehicle_status(p,"You can manage vehicles from your own company.") end
      return false
    end
    local a=V.orders[kind]
    if a and a.fetch then
      local pending={kind=kind,id=id,back=back,waiting=true}
      show(p,pending,title(v.label).."label[.45,1.20;Loading vehicle orders…]"..
        "button_exit[5.55,7.11;5,.57;V_TOKEN_close;Back to world]")
      local function loaded(data,why)
        if panels[n]~=pending then return end
        return draw_orders(p,v,kind,id,back,prior,note,data,why)
      end
      local queued,why=a.fetch(n,id,loaded)
      if not queued then loaded(nil,why or "Could not load vehicle orders.") end
      return true
    end
    local data,why
    if a then data,why=a.read(n,id) end
    return draw_orders(p,v,kind,id,back,prior,note,data,why)
  end
  function V.depot(p,kind,depot,return_)
    local n=p:get_player_name()
    local ids={}
    if projection then
      for _,row in pairs(projected) do if row.mode==kind and row.owner==n then ids[#ids+1]=row.id end end
    elseif kind=="road" then for id in pairs(S.fleet) do ids[#ids+1]=id end
    elseif kind=="rail" and api.rail_owned then for _,u in ipairs(api.rail_owned.list(S,n,depot)) do ids[#ids+1]=u.id end
    elseif kind=="ship" then ids={"ferry","coal"}
    elseif kind=="tram" then ids={1}
    elseif kind=="air" then
      if S.stock_owned_aircraft then ids[1]=1 end
      for id in pairs(S.stock_owned_air_fleet or {}) do ids[#ids+1]=id end
    end
    table.sort(ids)
    local rows={}
    for _,id in ipairs(ids) do
      local r=get(n,kind,id)
      if r and (r.depot_key==depot or kind=="road" and r.source.depot==depot) then rows[#rows+1]=r end
    end
    local b=title("Depot vehicles")..
      ("textlist[.45,1.14;10.10,4.61;V_TOKEN_row;%s;1;false]"):format(texts(rows,"No vehicles are assigned to this depot."))..
      "button[.45,6.12;4.98,.58;V_TOKEN_open;Open selected vehicle]"..
      "button[5.55,6.12;5,.58;V_TOKEN_follow;Follow selected vehicle]"..
      "button[.45,7.11;4.98,.57;V_TOKEN_return;Depot controls]"..
      "button_exit[5.55,7.11;5,.57;V_TOKEN_close;Back to world]"
    return show(p,{kind=kind,depot=depot,return_=return_,rows=rows,row=1},b)
  end
  core.register_on_player_receive_fields(function(p,name,f)
    if name~=form then return false end
    local n=p:get_player_name()
    local q=panels[n]
    if not q then return true end
    if f.quit then panels[n]=nil;return true end
    local function field(k) return f[("v%d_%s"):format(q.token,k)] end
    local function read(k,limit)
      local x=field(k)
      if not x then return end
      local event=core.explode_textlist_event(x)
      if event.index and event.index>=1 and (not limit or event.index<=limit) then q[k]=event.index end
    end
    local previous_row=q.row
    read("row",q.rows and #q.rows or q.item_count)
    read("target",q.targets and #q.targets)
    if q.rows then
      local v=q.rows[q.row]
      if field("return") and q.return_ then panels[n]=nil;close(p);q.return_()
      elseif field("open") and v then V.open(p,v.kind,v.id,q)
      elseif field("follow") and v then
        if not V.follow(p,v.kind,v.id) then
          V.open(p,v.kind,v.id,q,nil,"Follow is unavailable from the current camera mode.")
        end
      end
      return true
    end
    if field("depot") and q.back then return V.depot(p,q.kind,q.back.depot,q.back.return_) end
    if field("follow") then
      if not V.follow(p,q.kind,q.id) then V.open(p,q.kind,q.id,q.back,q,"Follow is unavailable from the current camera mode.") end
      return true
    end
    local a=V.orders[q.kind]
    if q.waiting or not a or not get(n,q.kind,q.id) then return true end
    local function change(op,value,is_cargo)
      if q.pending then return true end
      local function completed(ok,message)
        if panels[n]~=q then return true end
        q.pending=nil
        if ok then
          if op=="up" then q.row=q.row-1 elseif op=="down" then q.row=q.row+1 end
        end
        return V.open(p,q.kind,q.id,q.back,q,message or
          (is_cargo and (ok and "Cargo rule updated." or "Cargo rule not changed.")
           or (ok and "Orders updated." or "That order change was not accepted.")))
      end
      if a.submit then
        q.pending=true
        local queued,why=a.submit(n,q.id,q.revision,op,q.row,value,completed)
        if not queued then return completed(false,why) end
        return true
      end
      local ok,msg=a.edit(n,q.id,q.revision,op,q.row,value)
      if ok then api.save() end
      return completed(ok,msg)
    end
    for _,kind in ipairs({"load","unload"}) do
      if q.cargo and field("apply_"..kind) then
        local choice=q.cargo[kind][tonumber(field("choose_"..kind))]
        if not choice then return true end
        return change(kind,choice.value,true)
      end
    end
    for _,op in ipairs({"append","up","down","remove","skip","replace"}) do
      if field(op) then
        local target=q.targets and q.targets[q.target]
        return change(op,target and target.id,false)
      end
    end
    if q.cargo and q.row~=previous_row then return V.open(p,q.kind,q.id,q.back,q) end
    return true
  end)
  return V
end
