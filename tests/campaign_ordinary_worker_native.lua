-- Appended to a disposable copy of the regular generated game.
local qa_hooks={}
local authority_test=dofile(mod.."/campaign_authority_host.lua")(core,mod,qa_hooks)
local graphical=core.settings:get_bool("luanttd_worker_graphical_qa",false)
local function transfer_ordinary(viewer)
  local camera_origin,movement,camera_input
  assert(api.generated_world and S.road_stock_clock and S.rail_paid_service and S.ship_paid_service and S.air_paid_service)
  assert(S.stock_generated_profile.width==64 and S.stock_generated_profile.depth==64)
  local owner="OrdinaryWorker"
  Sim.company(S,owner)
  local x,z,level,initial_price
  for v=2,60 do
    for u=2,48 do
      local q=api.rail_build.quote_track(owner,Sim.id(u+1,v),Sim.id(u+14,v),0,false)
      if q and not q.crossing and #q.ids==14 then
        local mask,h=api.terrain.tile(Sim.id(u,v))
        for p=u,u+14 do
          local id=Sim.id(p,v)
          local shape,h2=api.terrain.tile(id)
          local t=S.tiles[id]
          if shape~=0 or h2~=h or t.terrain=="water" or t.wood or t.house or t.site or t.owner then mask=1;break end
        end
        if mask==0 then x,z,level,initial_price=u,v,h,q.price;break end
      end
    end
    if x then break end
  end
  assert(x,"ordinary map had no flat railway segment to build")
  local function tile(u) return Sim.id(u,z) end
  local depot,origin=tile(x),tile(x+1)
  local signal_tile,signal_level
  for v=math.max(2,z-5),math.min(60,z+5) do
    if v~=z then
      for u=x,math.min(60,x+14) do
        local id=Sim.id(u,v)
        local t=S.tiles[id]
        local mask,h=api.terrain.tile(id)
        if mask==0 and t.terrain~="water" and not (t.wood or t.house or t.site or t.owner or t.stock_industry) then
          signal_tile,signal_level=id,h;break
        end
      end
    end
    if signal_tile then break end
  end
  assert(signal_tile)
  local clock=S.passenger_house_clock
  local expected={day=S.day,cash=S.companies[owner].cash,loan=S.companies[owner].loan,speed=S.speed}
  -- The generated map already ran 1280 stock pregame tile-loop ticks.
  -- Carry that real offset on both the host and the detached owner.
  local tick_offset=(clock and clock.counter or S.day*74)-S.day*74
  local caps={autoplay=true,seconds_per_day=.16,durable_actions=true}
  for k,value in pairs(api.capabilities) do if caps[k]==nil then caps[k]=value end end
  assert(caps.air[215] and caps.ferry[206] and #caps.rail.engines>0)
  assert(api.rail_mixed_town_tools and caps.rail.mixed_town_engines[0],
    "Regular game did not derive mixed town rail from native assets")
  local filename="ordinary-worker-qa.chk"
  local disk=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),filename)
  local frozen=false
  function qa_hooks.freeze_host() frozen=true;api.authority_handoff=true end
  function qa_hooks.seal_checkpoint()
    assert(frozen)
    disk.write_state(S)
    return filename
  end
  local paint_started,painted,away,away_tick,reentered,opening_orders,orders_ready
  local train_id,painter,demolition_depot,signal_rendered,bus_id,arrival_news
  local function ask(request,done)
    request.player=owner
    assert(authority_test.query(request,done))
  end
  local function start_bus_graphically(show)
    local tip,stops,tail
    for v=4,60 do
      if math.abs(v-z)>3 then
        for u=2,51 do
          local h0,clear=nil,true
          for x_=u,u+8 do
            local cell=Sim.id(x_,v)
            local t=S.tiles[cell]
            local mask,h=api.terrain.tile(cell)
            if mask~=0 or h0 and h~=h0 or t.house or t.wood or t.site or t.owner or t.stock_industry
              or t.terrain=="water" or cell==demolition_depot or cell==signal_tile then clear=false;break end
            h0=h
          end
          if clear then
            tip,tail=Sim.id(u,v),Sim.id(u+8,v)
            stops={Sim.id(u+2,v),Sim.id(u+7,v)}
            break
          end
        end
      end
      if tip then break end
    end
    assert(tip)
    local function command(c,done)
      ask({kind="company"},function(company)
        c.revision=company.revision
        ask({kind="command",command=c},function(r) assert(r.ok,r.why);done(r) end)
      end)
    end
    command({kind="road_build",first=tip+1,last=tail},function()
      local actions={{tool="road_depot",first=tip},{tool="road_station",first=stops[1]},
        {tool="road_station",first=stops[2]}}
      local function construct(index)
        if not actions[index] then
          ask({kind="depot",mode="road",depot=tip},function(d)
            assert(d.ok,d.why)
            local ticket
            for _,o in ipairs(d.value.offers) do if o.request.cargo=="passenger" then ticket=o.request;break end end
            assert(ticket)
            command(ticket,function(r)
              bus_id=r.value
              local shown_button
              core.show_formspec=function(player,form,body)
                assert(player==owner and form=="luanttd_core:vehicle_details")
                show(player,form,body)
                if body:find("Pick in world",1,true) and not shown_button then
                  shown_button=true
                  assert(body:find("Add selected destination",1,true),"destination list should remain available")
                  core.log("action","NATIVE_PICK_BUS_PANEL")
                end
                if body:find("Start service",1,true) then core.log("action","NATIVE_PROJECTED_BUS_READY") end
                if body:find("Stop service",1,true) then
                  assert(disk.read().fleet[bus_id].running and not S.fleet[bus_id])
                  core.show_formspec=show
                  core.log("action","PASS NATIVE PROJECTED BUS: existing native orders panel starts an ordinary paid bus on the worker")
                  orders_ready=true
                end
              end
              assert(api.vehicle_ui.open(viewer,"road",bus_id))
              local function aim(i)
                assert(world.menu(viewer)=="vehicle_orders","picker modal unexpectedly closed")
                local tx,tz=Sim.xy(stops[i])
                viewer:set_pos({x=2*tx+.45,y=S.tiles[stops[i]].h+9,z=2*tz+.45})
                viewer:set_look_vertical(1.52)
                core.after(.75,function()
                  assert(world.target(viewer)==stops[i],"pointer did not intersect the real stop")
                  core.log("action","NATIVE_PICK_BUS_STOP_"..i)
                  local function watch_pick()
                    local current=disk.read()
                    local orders=current.fleet[bus_id].orders
                    if #orders<i then core.after(.12,watch_pick);return end
                    assert(#orders==i and orders[i].station==current.tiles[stops[i]].station)
                    if i==#stops then
                      assert(not S.fleet[bus_id])
                      core.log("action","PASS NATIVE WORLD STATION PICKER: two aimed clicks recorded authoritative bus orders")
                    else core.after(.20,aim,i+1) end
                  end
                  watch_pick()
                end)
              end
              local function wait_modal()
                if world.menu(viewer)~="vehicle_orders" then core.after(.12,wait_modal);return end
                aim(1)
              end
              core.after(.1,wait_modal)
            end)
          end)
          return
        end
        local req=actions[index]
        ask({kind="road_quote",request=req},function(q)
          assert(q.ok,q.why)
          ask({kind="command",command={kind="road_commit",revision=q.revision,request=req,quote=q.value}},function(r)
            assert(r.ok,r.why)
            construct(index+1)
          end)
        end)
      end
      construct(1)
    end)
  end
  local function demolition_graphical(show)
    local road_end
    for v=2,60 do
      if math.abs(v-z)>2 then
        for u=2,57 do
          local valid,base=true,nil
          for x_=u,u+3 do
            local id=Sim.id(x_,v)
            local t=S.tiles[id]
            local mask,h=api.terrain.tile(id)
            if mask~=0 or base and h~=base or t.terrain=="water" or
              t.wood or t.house or t.site or t.owner or t.stock_industry then valid=false;break end
            base=h
          end
          if valid then demolition_depot,road_end=Sim.id(u,v),Sim.id(u+3,v);break end
        end
      end
      if demolition_depot then break end
    end
    assert(demolition_depot)
    ask({kind="company"},function(c)
      ask({kind="command",command={kind="road_build",first=demolition_depot+1,last=road_end,revision=c.revision}},function(road)
        assert(road.ok,road.why)
        local req={tool="road_depot",first=demolition_depot}
        ask({kind="road_quote",request=req},function(offer)
          assert(offer.ok,offer.why)
          ask({kind="command",command={kind="road_commit",revision=offer.revision,request=req,quote=offer.value}},function(built)
            assert(built.ok,built.why)
            local cp=disk.read()
            assert(cp.tiles[demolition_depot].build=="road_depot")
            core.show_formspec=function(player,form,body)
              assert(player==owner and form=="luanttd_core:demolish_layers")
              assert(body:find("Remove road depot",1,true))
              assert(disk.read().tiles[demolition_depot].build=="road_depot","a quote removed the depot")
              core.show_formspec=show
              show(player,form,body)
              core.log("action","NATIVE_PROJECTED_DEMOLITION_READY")
              local function watch_demolition()
                if disk.read().tiles[demolition_depot].build=="road_depot" then core.after(.3,watch_demolition);return end
                assert(S.tiles[demolition_depot].build~="road_depot")
                core.log("action","PASS NATIVE PROJECTED DEMOLITION: worker confirmation removed the depot")
                start_bus_graphically(show)
              end
              core.after(.3,watch_demolition)
            end
            ui.select_tool(viewer,"clear")
            assert(ui.begin_demolition(viewer,demolition_depot))
            ui.end_demolition(viewer,demolition_depot,false)
          end)
        end)
      end)
    end)
  end
  local function apply(kind,req,check,done)
    ask({kind=kind.."_quote",request=req},function(offer)
      assert(offer.ok,offer.why)
      if check then check(offer.value) end
      ask({kind="command",command={kind=kind.."_commit",token=offer.value.token,revision=offer.revision}},function(r)
        assert(r.ok,r.why)
        done(r)
      end)
    end)
  end
  local function watch()
    if reentered then return end
    local pos=viewer and viewer:get_pos()
    if pos and camera_origin and not movement then
      local k=viewer:get_player_control()
      if (k.right or k.up) and not camera_input then
        camera_input=true
        core.log("action","NATIVE_PROJECTED_CLIENT_KEY_RECEIVED")
      end
      local dx,dz=pos.x-camera_origin.x,pos.z-camera_origin.z
      if dx*dx+dz*dz>=1 then
        movement=true
        core.log("action","PASS NATIVE PROJECTED WALK: graphical input moved while worker owns simulation")
      end
    end
    local focus=pos or {x=2*x,z=2*z}
    authority_test.step(.2,(away and not away_tick) and {} or {{x=focus.x,z=focus.z,name=owner}},1)
    if painter then painter.step() end
    core.after(.08,watch)
  end
  local function bodies()
    local count=0
    for _,ref in ipairs(core.get_objects_inside_radius({x=2*x+14,y=level+.7,z=2*z},20)) do
      local e=ref:get_luaentity()
      if e and (e.name=="luanttd_core:dispatch_steam" or e.name=="luanttd_core:dispatch_wagon") then count=count+1 end
    end
    return count
  end
  painter=dofile(mod.."/campaign_projection_painter.lua")(render,function(w,ok,why)
    -- The ordinary painter requeues a transient incomplete emerge.
    -- Only acknowledge stock geometry after materializing the target.
    if not ok and why=="Luanti could not emerge part of the starting area." then return end
    assert(ok,why)
    if x+1<w.x or x+1>=w.x+w.width or z<w.z or z>=w.z+w.height or painted then return end
    local block=core.get_node({x=(x+1)*2,y=level+1,z=z*2})
    assert(block.name=="luanttd_core:stock_rail_1","wrong projected node: "..block.name)
    assert(not S.tiles[origin].rail_tracks,"paint mutated the frozen simulation")
    painted=true
    core.log("action","PASS NATIVE PROJECTED PAINTER: stock rail mesh rendered at the worker track height")
  end)
  function qa_hooks.present(projected)
    local cell=projected.terrain(x+1,z)
    painter.present(projected)
    render.draw_worker_actors(projected)
    render.step_worker_actors(0)
    ui.use_worker_projection(projected)
    ui.hud()
    if cell and not paint_started then
      paint_started=true
      local ledger=assert(projected.company(owner))
      assert(ledger.world_day>expected.day and ledger.cash<expected.cash-initial_price and ledger.month>=1)
      core.log("action","PASS NATIVE PROJECTED HUD: worker calendar and exact company ledger reached the player's view")
      assert(cell.rail==1 and cell.surface.rail_tracks==1)
    end
    if painted and not signal_rendered then
      local xx,zz=Sim.xy(signal_tile)
      for _,object in ipairs(core.get_objects_inside_radius({x=2*xx+.5,y=signal_level+1,z=2*zz+.5},3)) do
        local data=object:get_luaentity()
        if data and data.name:match("^luanttd_core:dispatch_signal_") then
          signal_rendered=true
          core.log("action","PASS NATIVE PROJECTED SIGNAL: authoritative stock mast is present in the viewport")
          break
        end
      end
    end
    if painted and signal_rendered and not opening_orders and bodies()>=2 and (not viewer or movement) then
      opening_orders=true
      api.vehicle_ui.orders.rail=dofile(mod.."/campaign_authority_order_proxy.lua")(authority_test,"rail")
      local show=core.show_formspec
      core.show_formspec=function(player,form,body)
        assert(player==owner and form=="luanttd_core:vehicle_details")
        if viewer then show(player,form,body) end
        if body:find("Available destinations",1,true) then
          assert(body:find("Train 1",1,true) and body:find("Skip to selected order",1,true))
          if not viewer then
            core.show_formspec=show
            orders_ready=true
          elseif body:find("Train orders updated.",1,true) then
            core.show_formspec=show
            core.log("action","PASS NATIVE PROJECTED TRAIN EDIT: graphical order reorder applied by worker")
            core.after(.55,function()
              core.show_formspec=function(player,form,body)
                assert(player==owner and form=="luanttd_core:worker_finance")
                show(player,form,body)
                if body:find("Borrow $10,000",1,true) then
                  core.log("action","NATIVE_PROJECTED_FINANCE_READY "..(body:match("label%[%.45,0%.94;([^%]]*)") or "") )
                end
                if body:find("Borrowed ",1,true) then
                  core.show_formspec=show
                  core.log("action","PASS NATIVE PROJECTED FINANCE: real graphical loan reached only the worker ledger")
                  core.after(.55,function() demolition_graphical(show) end)
                end
              end
              assert(ui.open_finance(viewer))
            end)
          end
          core.log("action","PASS NATIVE PROJECTED TRAIN FORM: selected worker-owned train opens original destination and cargo controls")
        end
      end
      assert(api.vehicle_ui.open(viewer or {get_player_name=function() return owner end},"rail",train_id))
    end
    if orders_ready and not away and bodies()>=2 then
      away=true
      core.after(.04,function()
        authority_test.step(0,{},1)
        assert(bodies()==0,"unsubscribed train was still visible")
        local function cull_timer()
          ask({kind="clock"},function(q)
            core.after(viewer and .35 or 7.3,function()
              ask({kind="clock"},function(later)
                assert(later.tick>q.tick,"worker did not advance without a view")
                away_tick=later.tick
              end)
            end)
          end)
        end
        if not viewer then cull_timer();return end
        local show=core.show_formspec
        core.show_formspec=function(player,form,body)
          assert(player==owner)
          show(player,form,body)
          if form=="luanttd_core:worker_fleet" and body:find("Rail · Train 1",1,true) then
            core.log("action","NATIVE_PROJECTED_FLEET_READY")
          elseif form=="luanttd_core:vehicle_details" and body:find("Available destinations",1,true) then
            assert(not next(projected.actors()) and body:find("Train 1",1,true))
            core.show_formspec=show
            core.log("action","PASS NATIVE PROJECTED FLEET: orders opened from company roster with an empty viewport")
            cull_timer()
          end
        end
        assert(ui.open_company(viewer))
      end)
    elseif away_tick and not reentered and bodies()>=2 then
      reentered=true
      core.log("action","PASS NATIVE PROJECTED ROLLING STOCK: original steam and coach cull and return while the worker clock runs")
      local function read_news()
        ask({kind="news",page=1},function(reply)
          assert(reply.ok,reply.why)
          for _,row in ipairs(reply.value.items) do
            if row.kind=="arrival_player" and row.icon=="train" then arrival_news=row;break end
          end
          if not arrival_news then core.after(.2,read_news);return end
          assert(not S.stock_news_journal and not arrival_news.owner and arrival_news.economy>expected.day and arrival_news.tile)
          core.log("action","PASS NATIVE WORKER NEWSPAPER: real train arrival read through the authority mailbox")
          ask({kind="stop"},function() end)
        end)
      end
      read_news()
    end
  end
  local function run_plans(i,plans)
    if i==#plans+1 then return end
    local p=plans[i]
    apply(p[1],p[2],p[3],function(result)
      if p[4] then p[4](result) else run_plans(i+1,plans) end
    end)
  end
  function qa_hooks.ready(ready)
    assert(ready.ready and ready.day==expected.day)
    if viewer then
      camera_origin={x=2*x+14,y=level+11,z=2*z-12}
      viewer:set_pos(camera_origin)
      viewer:set_look_horizontal(0)
      viewer:set_look_vertical(.66)
      core.log("action","NATIVE_PROJECTED_CLIENT_READY")
    end
    core.after(.65,function()
      ask({kind="company"},function(first)
        assert(first.ok and first.day>expected.day and first.tick==tick_offset+first.day*74 and first.value.cash==expected.cash,("Initial settled company: ok=%s day=%s base=%s tick=%s cash=%s basecash=%s")
          :format(tostring(first.ok),tostring(first.day),tostring(expected.day),tostring(first.tick),
            tostring(first.value and first.value.cash),tostring(expected.cash)))
        ui.install_worker_controls(authority_test)
        local builder=viewer or {get_player_name=function() return owner end}
        api.on_worker_build=function(name,tiles,quote)
          assert(name==owner and #tiles==14 and quote.cost==initial_price)
          local committed=disk.read()
          assert(committed.tiles[origin].rail_tracks==1 and committed.companies[owner].cash==expected.cash-initial_price)
          core.log("action","PASS NATIVE WORKER DURABILITY: track and debit are durable before the native success receipt")
          api.on_worker_build=nil
          core.log("action","PASS NATIVE PROJECTED HOTBAR BUILD: stock Autorail release committed on the worker")
          run_plans(1,{
          {"rail",{tool="depot",first=depot,direction=2}},
          {"rail",{tool="station",first=tile(x+3),last=tile(x+5),axis=0,length=3,tracks=1}},
          {"rail",{tool="station",first=tile(x+10),last=tile(x+12),axis=0,length=3,tracks=1}},
          {"rail",{tool="track",first=signal_tile,track=0}},
          {"rail",{tool="signal",first=signal_tile,trackdir=0,kind=4}},
          {"transport",{mode="rail",operation="buy",depot=depot,parts={0,27}},nil,function(bought)
            train_id=bought.value.id
            ask({kind="depot",mode="rail",depot=depot},function(d)
              assert(d.ok,d.why)
              local mixed
              for _,item in ipairs(d.value.offers) do
                local p=item.request.parts
                if p and #p==3 and p[1]==0 and p[2]==27 and p[3]==28 then mixed=true;break end
              end
              assert(mixed,"Regular authority depot did not offer the verified mixed formation")
              core.log("action","PASS NATIVE DEFAULT MIXED RAIL CAPABILITY")
              ask({kind="command",command={kind="transport_start",mode="rail",vehicle=train_id,
                first=2,second=1,revision=d.revision}},function(started)
                assert(started.ok,started.why)
                watch()
              end)
            end)
          end},
          })
        end
        ui.select_tool(builder,"rail_autotrack")
        assert(ui.begin_autorail(builder,origin,{x=2*(x+1)+.5,z=2*z+.5}))
        local target,hit=tile(x+14),{x=2*(x+14)+.5,z=2*z+.5}
        local function release_when_priced(n)
          local cells,valid,note=ui.preview(builder,target,hit)
          if valid and #cells==14 then ui.end_autorail(builder,target,hit);return end
          assert(n<100,note or "Did not see the priced autorail ghost")
          core.after(.035,release_when_priced,n+1)
        end
        release_when_priced(0)
      end)
    end)
  end
  function qa_hooks.stopped(reason,seq,day,detail)
    assert(reason=="stopped" and seq>10 and day>expected.day and painted and reentered,detail or reason)
    assert(not viewer or movement,"expected graphical movement input")
    assert(S.speed==expected.speed and S.day==expected.day and (not clock or clock.counter==tick_offset+expected.day*74))
    local state=disk.read()
    assert(state.day==day and state.passenger_house_clock.counter==tick_offset+day*74 and state.stock_generated_profile.width==64)
    assert(state.tiles[origin].rail_tracks==1 and not S.tiles[origin].rail_tracks)
    local published=false
    for _,row in ipairs(assert(state.stock_news_journal).items) do
      if row.seq==assert(arrival_news).seq then published=true;break end
    end
    assert(published,"worker did not checkpoint the newspaper article")
    if viewer then assert(state.stock_rail_dispatch.runs[1].orders[1].station==1 and state.companies[owner].loan==expected.loan+10000
      and S.companies[owner].loan==expected.loan and not state.tiles[demolition_depot].build) end
    assert(state.companies[owner].cash<expected.cash-initial_price and S.companies[owner].cash==expected.cash)
    core.log("action","PASS NATIVE ORDINARY WORKER BUILD: stock track quote and debit committed only on worker")
    core.log("action",("PASS NATIVE ORDINARY HANDOFF: regular 64-square world advanced from day %d to %d on the worker, host day stayed %d")
      :format(expected.day,day,S.day))
    core.request_shutdown("Ordinary authority handoff proof passed",false,0)
  end
  assert(authority_test.start(caps,Sim.W,Sim.H))
end
if graphical then
  core.register_on_joinplayer(function(p)
    assert(p:get_player_name()=="OrdinaryWorker")
    core.after(.2,transfer_ordinary,p)
  end)
else core.after(.2,transfer_ordinary) end
