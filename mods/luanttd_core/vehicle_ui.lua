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
  local worker
  local remote,pickers={},{}
  local path=(core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local order_target=dofile(path.."/campaign_order_target.lua")
  local ride=dofile(path.."/vehicle_ride.lua")(core,api,path)
  local selected={}
  V.ride_track=ride.track
  V.riding=ride.active
  V.ride_controls=ride.controls
  function V.install_worker(client) worker=client end
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
    if projection or worker then
      local row=projected[key(kind,id)]
      local known=remote[n]
      if known and (known.mode~=kind or known.id~=id) then known=nil end
      if not row then row=known end
      if not row or row.owner~=n then return end
      local depot=known and known.depot or kind~="ship" and (row.home_depot or row.depot) or nil
      return {kind=kind,id=id,label=row.label or ("Vehicle #"..id),source=row,
        depot=depot,depot_key=known and known.depot_key or row.home_depot or row.depot}
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
        label=id=="coal" and "Yate Cargo Ship" or source.engine_id==208 and "Bakewell 300 Hovercraft" or source.engine_id==207 and "FFP Passenger Ferry" or "MPS Passenger Ferry"
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
  function V.track(kind,id,pos,ref,primary,body)
    if not id then return end
    if pos and primary~=false then poses[key(kind,id)]={pos=pos,time=now} end
    if ref and bodies[ref]==nil then
      local obj=ref:get_luaentity()
      if obj then
        local pick={kind=kind,id=id,body=body}
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
  function V.following(p) return following[p:get_player_name()]~=nil or ride.active(p) end
  function V.remember(p,pick)
    selected[p:get_player_name()]={kind=pick.kind,id=pick.id,body=pick.body}
  end
  function V.exit(p)
    if ride.active(p) then return ride.exit(p) end
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
  function V.ride_toggle(p,mode,target)
    if ride.active(p) then return ride.exit(p) end
    if V.following(p) then return false,"Leave the follow camera before boarding." end
    local n=p:get_player_name()
    if not target then
      local aimed=V.pick(p,42)
      target=aimed and ride.capable(aimed.kind,mode) and aimed or selected[n]
    end
    local ok,why=ride.enter(p,mode,target)
    if ok then panels[n]=nil;close(p) end
    return ok,why
  end
  if core.register_chatcommand then
    for command,mode in pairs({train="cab",ride="ride"}) do
      core.register_chatcommand(command,{
        description=mode=="cab" and "Sit in the cab of a selected running train" or "Ride a selected passenger bus or train",
        func=function(n)
          local p=core.get_player_by_name(n)
          if not p then return false,"Join the campaign before boarding." end
          return V.ride_toggle(p,mode)
        end})
    end
  end
  local function follow_at(p,kind,id,v,pos)
    local n=p:get_player_name()
    if not pos or p:get_attach() or following[n] then return false end
    local yaw=p:get_look_horizontal()
    local offset={x=2.8*math.sin(yaw),y=3.6,z=-2.8*math.cos(yaw)}
    local view={x=pos.x+offset.x,y=pos.y+offset.y,z=pos.z+offset.z}
    local camera=core.add_entity(view,anchor)
    if not camera then return false end
    local f={anchor=camera,kind=kind,id=id,return_pos=p:get_pos(),yaw=p:get_look_horizontal(),
      pitch=p:get_look_vertical(),last=view,vehicle_pos=pos,offset=offset,owner_row=worker and v}
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
  function V.follow(p,kind,id)
    local n=p:get_player_name()
    local v=get(n,kind,id)
    if p:get_attach() or following[n] or not v then return false end
    local a=poses[key(kind,id)]
    if not worker or a and now-a.time<=.7 then return follow_at(p,kind,id,v,position(v)) end
    local panel=panels[n]
    if panel and panel.locating then return true end
    if panel then panel.locating=true end
    local sent=worker.query({kind="vehicle",player=n,mode=kind,vehicle=id,locate=true},function(r)
      if panel and panels[n]~=panel then return end
      if panel then panel.locating=nil end
      if r.ok and r.value.position then
        remote[n]=r.value
        follow_at(p,kind,id,v,r.value.position)
      elseif api.vehicle_status then api.vehicle_status(p,"No visible position for this vehicle yet.") end
    end)
    if not sent and panel then panel.locating=nil end
    return not not sent
  end
  function V.step(dt)
    now=now+dt
    local players=core.get_connected_players()
    ride.step(dt,players)
    for _,p in ipairs(players) do
      local n=p:get_player_name()
      local f=following[n]
      if f then
        local v=get(n,f.kind,f.id) or f.owner_row
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
    V.exit(p);panels[n]=nil;remote[n]=nil;pickers[n]=nil;selected[n]=nil
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
    local adapter=V.orders[kind]
    local toggle=adapter and adapter.toggle and data and data.can_toggle
    local extended=cargo or toggle
    local b=title(v.label,extended and 9).."button[7.94,.22;2.61,.62;V_TOKEN_follow;Follow vehicle]"
    if ride.capable(kind,"ride") and (kind~="road" or v.source.passenger~=false and
        (v.source.cargo==nil or v.source.cargo=="passenger")) then
      b=b.."button[5.93,.22;1.80,.62;V_TOKEN_ride;Ride]"
    end
    if ride.capable(kind,"cab") then
      b=b.."button[4.06,.22;1.63,.62;V_TOKEN_cab;Cab view]"
    end
    if note or data and data.summary then
      b=b..("textarea[.45,%g;10,.63;;;%s]"):format(cargo and 7.56 or 6.35,esc(note or data.summary))
    end
    if data then
      local items,targets=data.items or {},data.targets or {}
      local row=math.max(1,math.min(#items,prior and prior.row or 1))
      local target=math.max(1,math.min(#targets,prior and prior.target or 1))
      local labels={}
      local pick_append=not not (adapter and adapter.submit_tile and data.can_insert~=false)
      local pick_replace=not not (adapter and adapter.submit_tile and data.can_replace and items[row])
      for i,o in ipairs(items) do labels[i]={label=(data.active==i and "▶ " or "   ")..i..". "..(o.label or tostring(o.id))} end
      b=b.."label[.45,1.05;Orders]label[5.65,1.05;Available destinations]"..
        ("textlist[.45,1.30;4.98,3.72;V_TOKEN_row;%s;%d;false]"):format(texts(labels,"(No orders)"),row)..
        ("textlist[5.55,1.30;5,%g;V_TOKEN_target;%s;%d;false]"):format(
          (pick_append or pick_replace) and 3.08 or 3.72,texts(targets,"(No destinations)"),target)
      if pick_append then
        b=b..("button[5.55,4.43;%g,.57;V_TOKEN_pick_world;Pick in world]"):format(pick_replace and 2.37 or 5)
      end
      if pick_replace then
        b=b..(pick_append and "button[8.0,4.43;2.55,.57;V_TOKEN_replace_world;Pick replacement]" or
          "button[5.55,4.43;5,.57;V_TOKEN_replace_world;Pick replacement in world]")
      end
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
      local eligible
      if (pick_append or pick_replace) and data.target_count==#targets then
        eligible={}
        for _,o in ipairs(targets) do eligible[o.id]=o.label end
      end
      prior={row=row,target=target,revision=data.revision,targets=targets,item_count=#items,cargo=cargo,
        pick_append=pick_append,pick_replace=pick_replace,eligible=eligible}
    else
      b=b.."textarea[.45,1.22;10,1.35;;;"..esc(why or "Set initial orders from the depot. No editable orders are available for this vehicle yet.").."]"
      prior={}
    end
    if toggle then
      b=b.."button[.45,6.68;10.10,.57;V_TOKEN_toggle;"..(data.running and "Stop service" or "Start service").."]"
    end
    prior.can_toggle=not not toggle
    local footer=extended and 8.15 or 7.11
    if back then b=b..("button[.45,%g;4.98,.57;V_TOKEN_depot;%s]"):format(footer,
      back.directory and "Company fleet" or "Depot vehicles") end
    b=b..("button_exit[5.55,%g;5,.57;V_TOKEN_close;Back to world]"):format(footer)
    prior.kind,prior.id,prior.back=kind,id,back
    return show(p,prior,b)
  end
  function V.open(p,kind,id,back,prior,note)
    local n=p:get_player_name()
    local v=get(n,kind,id)
    if not v and worker then
      local pending={kind=kind,id=id,back=back,waiting=true}
      show(p,pending,title("Vehicle").."label[.45,1.20;Loading vehicle…]"..
        "button_exit[5.55,7.11;5,.57;V_TOKEN_close;Back to world]")
      local function load(r)
        if panels[n]~=pending then return end
        if r.ok then
          remote[n]=r.value
          return V.open(p,kind,id,back,prior,note)
        end
        panels[n]=nil;close(p)
        if api.vehicle_status then api.vehicle_status(p,r.why or "Vehicle is unavailable.") end
        if back and back.return_ then back.return_() end
      end
      local ok,why=worker.query({kind="vehicle",player=n,mode=kind,vehicle=id},load)
      if not ok then load({ok=false,why=why}) end
      return true
    end
    if not v then
      if api.vehicle_status then api.vehicle_status(p,"You can manage vehicles from your own company.") end
      return false
    end
    local old=selected[n]
    if not old or old.kind~=kind or old.id~=id then V.remember(p,{kind=kind,id=id}) end
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
  -- The modal keeps only the selected vehicle and current order revision.
  -- Each click is sent as a tile, not as a guessed or projected station ID.
  function V.world_order_preview(p,tile)
    local n=p:get_player_name()
    local q=pickers[n]
    if not q then return end
    if q.pending then return "Saving selection…",q.note end
    local render=api.render
    local t=tile and render and render.host_tile and render.host_tile(tile)
    local id,label=order_target(q.kind,q.id,n,tile,t,function(registry,id)
      return render.host_record and render.host_record(registry,id)
    end)
    local phrase=q.replace and "Choose a replacement on the map" or "Aim at a stop and click to add it"
    if not id then return phrase,q.note,tile and {tile},false end
    if q.panel.eligible then
      if not q.panel.eligible[id] then return "This stop is not in the vehicle's destination list",q.note,{tile},false end
      label=q.panel.eligible[id]
    end
    return (q.replace and "Replace with: " or "Add stop: ")..label,q.note,{tile},true
  end
  function V.finish_world_orders(p)
    local n=p:get_player_name()
    local q=pickers[n]
    if not q then return end
    if q.pending then q.finish=true;return end
    pickers[n]=nil
    api.world.end_order_selection(p)
    V.open(p,q.kind,q.id,q.panel.back,q.panel,q.note)
  end
  function V.pick_world_order(p,tile)
    local n=p:get_player_name()
    local q=pickers[n]
    if not q or q.pending then return end
    if not tile then q.note="Aim at a station tile before picking.";return end
    q.pending=true
    local function completed(ok,why,result)
      if pickers[n]~=q then return end
      q.pending=nil
      q.note=why or (ok and "Destination saved." or "This destination could not be added.")
      if ok then
        q.revision=result and result.order_revision or q.revision
        if result and result.count then q.panel.item_count=result.count end
      end
      if why=="STALE_COMMAND" then
        q.note="The campaign changed. Click the stop again to retry."
      end
      if q.finish or (ok and (q.replace or not result or result.order_revision==nil)) or
          (why and why:lower():find("order",1,true) and why:lower():find("changed",1,true)) then
        return V.finish_world_orders(p)
      end
      if api.world.hud then api.world.hud(p) end
    end
    local sent,why=V.orders[q.kind].submit_tile(n,q.id,q.revision,q.replace and "replace" or "append",
      q.panel.row,tile,completed)
    if not sent then completed(false,why) end
  end
  local function begin_world_orders(p,q,replace)
    local n=p:get_player_name()
    if q.pending or pickers[n] or not api.world or not api.world.begin_order_selection or
        not (replace and q.pick_replace or not replace and q.pick_append) then return true end
    local state={kind=q.kind,id=q.id,revision=q.revision,panel=q,replace=replace}
    pickers[n]=state
    if not api.world.begin_order_selection(p,"vehicle",replace and "Replace an order" or "Pick destinations") then
      pickers[n]=nil
      return true
    end
    panels[n]=nil
    close(p)
    if api.world.hud then api.world.hud(p) end
    return true
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
    if name=="" and f.luanttd_leave_ride and ride.active(p) then return V.exit(p) end
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
    if field("depot") and q.back then
      if q.back.directory and q.back.return_ then panels[n]=nil;return q.back.return_() end
      return V.depot(p,q.kind,q.back.depot,q.back.return_)
    end
    if field("ride") or field("cab") then
      local saved=selected[n]
      local ok,why=V.ride_toggle(p,field("cab") and "cab" or "ride",
        {kind=q.kind,id=q.id,body=saved and saved.kind==q.kind and saved.id==q.id and saved.body or nil})
      if not ok then V.open(p,q.kind,q.id,q.back,q,why) end
      return true
    end
    if field("follow") then
      if not V.follow(p,q.kind,q.id) then V.open(p,q.kind,q.id,q.back,q,"Follow is unavailable from the current camera mode.") end
      return true
    end
    local a=V.orders[q.kind]
    if q.waiting or not a or not get(n,q.kind,q.id) then return true end
    if field("pick_world") or field("replace_world") then
      return begin_world_orders(p,q,not not field("replace_world"))
    end
    if field("toggle") and q.can_toggle and a.toggle then
      if q.pending then return true end
      q.pending=true
      local sent,why=a.toggle(n,q.id,function(ok,msg)
        if panels[n]~=q then return end
        V.open(p,q.kind,q.id,q.back,q,msg or (ok and "Service updated." or "Service not changed."))
      end)
      if not sent then q.pending=nil;V.open(p,q.kind,q.id,q.back,q,why) end
      return true
    end
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
