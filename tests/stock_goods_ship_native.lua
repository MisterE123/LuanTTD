-- SPDX-License-Identifier: GPL-2.0-only
-- Native server and real graphical Luanti client. Exercise the normal
-- depot and vehicle form handlers, including tile-target Orders mode.
local goods_native_started=false
local function goods_native_scene(p)
  assert(api.capabilities.ferry[211] and api.capabilities.ferry[204])
  local name=p:get_player_name()
  p:set_pos({x=84,y=14,z=55})
  p:set_look_horizontal(0);p:set_look_vertical(.38)
  local function ask(req,done)
    req.player=name
    local ok,why=authority.query(req,function(r) assert(r.ok,req.kind..": "..tostring(r.why));done(r) end)
    assert(ok,why)
  end
  local function commit(req,done)
    ask({kind="transport_quote",request=req},function(r)
      ask({kind="command",command={kind="transport_commit",revision=r.revision,token=r.value.token}},done)
    end)
  end
  local plans={{"dock",12,32},{"dock",31,32},{"depot",17,35},{"dock",34,32},{"dock",51,32},{"depot",43,35}}
  local id,at={},{}
  local began,viewed,settled=false,false,false
  local prior=assert(OwnerCheckpoint.read())
  local saved=prior.stock_goods_ship_service and prior.stock_goods_ship_service.vehicle
  local restart=saved and saved.delivered or 0
  local function observe()
    local disk=assert(OwnerCheckpoint.read())
    local ship_pos
    for _,ref in ipairs(core.get_objects_inside_radius({x=85,y=2,z=68},28)) do
      local actor=ref:get_luaentity()
      if actor and actor.name=="luanttd_core:stock_yate_cargo_ship" then
        assert(ref:get_properties().mesh=="bl_yate_cargo_ship.obj")
        viewed=true;ship_pos=ref:get_pos()
      end
    end
    local c=disk.companies[name]
    local v=disk.stock_goods_ship_service and disk.stock_goods_ship_service.vehicle
    if v and v.delivered>=restart+160 and viewed and settled then
      assert(disk.stock_coal_ship.engine==211 and disk.stock_coal_ship.cargo==5 and disk.stock_coal_ship.refit==0)
      assert(disk.sites[1].received.goods>=160 and c.revenue>=v.revenue and v.revenue>0)
      if restart>0 then
        assert(disk.day>prior.day and c.revenue>=prior.companies[name].revenue)
        core.log("action",("PASS NATIVE GOODS SHIP REOPEN: %d→%d crates after the SQLite restart"):format(restart,v.delivered))
      else
        if ship_pos then
          p:set_pos({x=ship_pos.x,y=ship_pos.y+5,z=ship_pos.z-18})
          p:set_look_horizontal(0);p:set_look_vertical(.33)
        end
        core.log("action",("PASS NATIVE STOCK SHIP #211: depot Goods buy, two world-picked docks, projected original hull, %d crates/$%d"):format(v.delivered,v.revenue))
      end
      return
    end
    core.after(.2,observe)
  end
  local function use_fields(form,field)
    for _,resolve in ipairs(core.registered_on_player_receive_fields) do
      if resolve(p,form,{[field]=true}) then return end
    end
    error("Unhandled native Goods form: "..form.." "..field)
  end
  local function order_forms()
    local span=core.show_formspec
    core.show_formspec=function(who,form,body)
      span(who,form,body)
      if who~=name then return end
      if form=="luanttd_core:worker_depot" then
        local f=body:match("(d%d+_orders);Open selected vehicle")
        if f then
          assert(body:find("Yate Cargo Ship",1,true) and body:find("Goods",1,true))
          core.after(.15,use_fields,form,f)
        end
      elseif form=="luanttd_core:vehicle_details" then
        local pick=body:match("(v%d+_initial_world);Pick both destinations in world")
        local start=body:match("(v%d+_initial_start);Start service")
        if pick and not began then
          began=true
          core.after(.2,function()
            use_fields(form,pick)
            local V=api.vehicle_ui
            local function click_when_present(attempt)
              local _,_,_,eligible=V.world_order_preview(p,at[4])
              if not eligible then
                assert(attempt<60,"Goods producer frontage never projected as an eligible dock")
                return core.after(.12,click_when_present,attempt+1)
              end
              V.pick_world_order(p,at[4])
              local _,_,_,sink=V.world_order_preview(p,at[5]);assert(sink,"Goods sink not projected")
              V.pick_world_order(p,at[5])
              V.finish_world_orders(p)
            end
            click_when_present(0)
          end)
        elseif start and began and not settled then
          assert(body:find("Goods producer dock",1,true) and body:find("Goods delivery dock",1,true))
          settled=true
          core.after(.3,use_fields,form,start)
        elseif settled and body:find("Deliver Goods to town",1,true) then
          core.show_formspec=span
          core.after(.4,core.close_formspec,name,form)
          core.after(.25,observe)
        end
      end
    end
    assert(api.worker_depot.open(p,"ship",id[6],nil,function(mode,vehicle,back)
      assert(mode=="ship" and vehicle=="coal")
      return api.vehicle_ui.open(p,mode,vehicle,back)
    end,"coal"))
  end
  local function build(i)
    local plan=plans[i]
    if not plan then
      commit({mode="ship",operation="buy",depot=id[3],engine=204},function(tanker)
        ask({kind="command",command={kind="transport_start",mode="ship",vehicle=tanker.value.id,cargo="oil",
          depot=id[3],first=id[1],second=id[2],first_tile=at[1],second_tile=at[2],revision=tanker.revision}},function()
          ask({kind="depot",mode="ship",depot=id[6]},function(d)
            local yate
            for _,offer in ipairs(d.value.offers) do if offer.request.engine==211 then yate=offer;break end end
            assert(yate and yate.price==32500 and yate.help.service:find("Goods",1,true))
            commit(yate.request,function(r) assert(r.value.id=="coal");order_forms() end)
          end)
        end)
      end)
      return
    end
    at[i]=Sim.id(plan[2],plan[3])
    commit({mode="ship",operation="build",kind=plan[1],tile=at[i],axis=plan[1]=="depot" and 0 or nil},function(r)
      id[i]=assert(r.value.id);build(i+1)
    end)
  end
  if restart>0 then
    assert(saved.cargo=="goods" and prior.stock_coal_ship_run.transport_orders)
    settled=true;observe()
  else build(1) end
end
local function goods_native_begin()
  local p=core.get_player_by_name("ShipReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not goods_native_started then goods_native_started=true;goods_native_scene(p) end
  else core.after(.22,goods_native_begin) end
end
core.after(.22,goods_native_begin)
