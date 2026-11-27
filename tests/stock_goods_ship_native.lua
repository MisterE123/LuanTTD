-- SPDX-License-Identifier: GPL-2.0-only
-- Native server and real graphical Luanti client. Exercise the normal
-- depot and vehicle form handlers, including tile-target Orders mode.
local goods_native_started=false
local function goods_native_scene(p)
  local cargo=assert(core.settings:get("luanttd_qa_other_ship_cargo"))
  local farm=cargo=="grain" or cargo=="livestock"
  local wood=cargo=="wood"
  local ore=cargo=="iron_ore"
  local heavy=ore or cargo=="steel"
  local bank=cargo=="valuables"
  local short_coast=heavy or bank
  local refitted=farm or wood or short_coast
  local cargo_id=({goods=5,grain=6,livestock=4,wood=7,iron_ore=8,steel=9,valuables=10})[cargo]
  local cargo_title=({goods="Goods",grain="Grain",livestock="Livestock",wood="Wood",iron_ore="Iron Ore",steel="Steel",valuables="Valuables"})[cargo]
  local source_label=ore and "Iron Ore Mine dock" or heavy and "Steel Mill dock" or
    farm and "Farm dock" or wood and "Forest dock" or bank and "Bank pickup dock" or "Goods producer dock"
  local sink_label=ore and "Steel Mill dock" or (heavy or farm) and "Factory dock" or
    wood and "Sawmill dock" or bank and "Bank delivery dock" or "Goods delivery dock"
  local destination=ore and "steel mill" or (heavy or farm) and "factory" or wood and "sawmill" or bank and "bank" or "town"
  local camera_x=ore and 38 or heavy and 72 or bank and 52 or refitted and 44 or 84
  assert(cargo_id and api.capabilities.ferry[211] and (refitted or api.capabilities.ferry[204]))
  local name=p:get_player_name()
  p:set_pos({x=camera_x,y=14,z=short_coast and 28 or 55})
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
  local plans=heavy and {{"dock",ore and 11 or 27,19},{"dock",ore and 27 or 46,19},{"depot",ore and 20 or 35,24}} or bank and {{"dock",10,19},{"dock",42,19},{"depot",26,24}} or refitted and {{"dock",12,32},{"dock",33,32},{"depot",20,36}} or
    {{"dock",12,32},{"dock",31,32},{"depot",17,35},{"dock",34,32},{"dock",51,32},{"depot",43,35}}
  local source,sink,home=refitted and 1 or 4,refitted and 2 or 5,refitted and 3 or 6
  local id,at={},{}
  local began,viewed,settled=false,false,false
  local prior=assert(OwnerCheckpoint.read())
  local saved=prior.stock_goods_ship_service and prior.stock_goods_ship_service.vehicle
  local restart=saved and saved.delivered or 0
  local function observe()
    local disk=assert(OwnerCheckpoint.read())
    local ship_pos
    for _,ref in ipairs(core.get_objects_inside_radius({x=camera_x,y=2,z=short_coast and 42 or 68},28)) do
      local actor=ref:get_luaentity()
      if actor and actor.name=="luanttd_core:stock_yate_cargo_ship" then
        assert(ref:get_properties().mesh=="bl_yate_cargo_ship.obj")
        viewed=true;ship_pos=ref:get_pos()
      end
    end
    local c=disk.companies[name]
    local v=disk.stock_goods_ship_service and disk.stock_goods_ship_service.vehicle
    if v and v.delivered>=restart+160 and viewed and settled then
      assert(disk.stock_coal_ship.engine==211 and disk.stock_coal_ship.cargo==cargo_id and disk.stock_coal_ship.refit==(refitted and 507 or 0))
      if farm then
        local factory=assert(disk.stock_farm_industries[0x2001])
        assert(factory.received[cargo]>=160)
        assert((factory.received[cargo=="grain" and "livestock" or "grain"] or 0)==0)
      elseif heavy then
        local mill=assert(disk.stock_heavy_industries[0x4001])
        local receiver=ore and mill or assert(disk.stock_farm_industries[0x2000])
        assert((receiver.received[cargo] or 0)>=160)
        if not ore then
          assert(disk.fleet[disk.qa_ore_supplier].delivered>0 and mill.received.iron_ore>0)
        end
      elseif bank then
        local a,b=disk.stock_bank_industries[0x5000],disk.stock_bank_industries[0x5001]
        assert(a.town~=b.town and ((a.received or {}).valuables or 0)==0 and b.received.valuables>=160)
      elseif wood then
        local mill=assert(disk.stock_timber_industries[0x1001])
        assert((mill.wood_received or (mill.received or {}).wood or 0)>=160,"Sawmill received no Wood")
      else assert(disk.sites[1].received.goods>=160) end
      assert(c.revenue>=v.revenue and v.revenue>0)
      if restart>0 then
        assert(disk.day>prior.day and c.revenue>=prior.companies[name].revenue)
        core.log("action",("PASS NATIVE DRY SHIP REOPEN: %d→%d units after the SQLite restart"):format(restart,v.delivered))
      else
        if ship_pos then
          p:set_pos({x=ship_pos.x,y=ship_pos.y+5,z=ship_pos.z-18})
          p:set_look_horizontal(0);p:set_look_vertical(.33)
        end
        core.log("action",("PASS NATIVE STOCK SHIP #211: depot %s, two world-picked docks, projected original hull, %d units/$%d"):format(cargo,v.delivered,v.revenue))
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
          assert(body:find("Yate Cargo Ship",1,true) and body:find(cargo_title,1,true))
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
              local _,_,_,eligible=V.world_order_preview(p,at[source])
              if not eligible then
                assert(attempt<60,"Loading dock frontage never projected as an eligible dock")
                return core.after(.12,click_when_present,attempt+1)
              end
              V.pick_world_order(p,at[source])
              local _,_,_,sink_eligible=V.world_order_preview(p,at[sink]);assert(sink_eligible,"Delivery dock not projected")
              V.pick_world_order(p,at[sink])
              V.finish_world_orders(p)
            end
            click_when_present(0)
          end)
        elseif start and began and not settled then
          assert(body:find(source_label,1,true) and body:find(sink_label,1,true))
          settled=true
          core.after(.3,use_fields,form,start)
        elseif settled and body:find("Deliver "..cargo_title.." to "..destination,1,true) then
          core.show_formspec=span
          core.after(.4,core.close_formspec,name,form)
          core.after(.25,observe)
        end
      end
    end
    assert(api.worker_depot.open(p,"ship",id[home],nil,function(mode,vehicle,back)
      assert(mode=="ship" and vehicle=="coal")
      return api.vehicle_ui.open(p,mode,vehicle,back)
    end,"coal"))
  end
  local function buy_yate()
    ask({kind="depot",mode="ship",depot=id[home]},function(d)
      local yate
      for _,offer in ipairs(d.value.offers) do if offer.request.engine==211 then yate=offer;break end end
      assert(yate and yate.price==32500 and yate.help.service:find("Goods",1,true))
      commit(yate.request,function(r)
        assert(r.value.id=="coal")
        if not refitted then return order_forms() end
        ask({kind="depot",mode="ship",depot=id[home]},function(refits)
          local choice
          for _,o in ipairs(refits.value.offers) do
            if o.request.operation=="refit" and o.request.cargo==cargo then choice=o;break end
          end
          assert(choice and choice.price==507)
          commit(choice.request,function(done)
            assert(done.value.id=="coal");order_forms()
          end)
        end)
      end)
    end)
  end
  local function build(i)
    local plan=plans[i]
    if not plan then
      if refitted then return buy_yate() end
      commit({mode="ship",operation="buy",depot=id[3],engine=204},function(tanker)
        ask({kind="command",command={kind="transport_start",mode="ship",vehicle=tanker.value.id,cargo="oil",
          depot=id[3],first=id[1],second=id[2],first_tile=at[1],second_tile=at[2],revision=tanker.revision}},buy_yate)
      end)
      return
    end
    at[i]=Sim.id(plan[2],plan[3])
    commit({mode="ship",operation="build",kind=plan[1],tile=at[i],axis=plan[1]=="depot" and 0 or nil},function(r)
      id[i]=assert(r.value.id);build(i+1)
    end)
  end
  if restart>0 then
    assert(saved.cargo==cargo and prior.stock_coal_ship_run.transport_orders)
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
