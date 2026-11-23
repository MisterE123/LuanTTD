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
  local clock=S.passenger_house_clock
  local expected={day=S.day,cash=S.companies[owner].cash,speed=S.speed}
  local caps={autoplay=true,seconds_per_day=.16}
  for k,value in pairs(api.capabilities) do if caps[k]==nil then caps[k]=value end end
  assert(caps.air[215] and caps.ferry[206] and #caps.rail.engines>0)
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
  local train_id
  local function ask(request,done)
    request.player=owner
    assert(authority_test.query(request,done))
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
  function qa_hooks.present(projected)
    local cell=projected.terrain(x+1,z)
    render.use_worker_projection(projected)
    render.draw_worker_actors(projected,.2)
    ui.use_worker_projection(projected)
    ui.hud()
    if cell and not paint_started then
      paint_started=true
      local ledger=assert(projected.company(owner))
      assert(ledger.world_day>expected.day and ledger.cash<expected.cash-initial_price and ledger.month>=1)
      core.log("action","PASS NATIVE PROJECTED HUD: worker calendar and exact company ledger reached the player's view")
      assert(cell.rail==1 and cell.surface.rail_tracks==1)
      render.place_projected(x,z,15,1,function(ok,why)
        assert(ok,why)
        local block=core.get_node({x=(x+1)*2,y=cell.level+1,z=z*2})
        assert(block.name=="luanttd_core:stock_rail_1","wrong projected node: "..block.name)
        assert(not S.tiles[origin].rail_tracks,"paint mutated the frozen simulation")
        painted=true
        core.log("action","PASS NATIVE PROJECTED PAINTER: stock rail mesh rendered at the worker track height")
      end)
    end
    if painted and not opening_orders and bodies()>=2 and (not viewer or movement) then
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
            core.after(.45,function() orders_ready=true end)
            core.log("action","PASS NATIVE PROJECTED TRAIN EDIT: graphical order reorder applied by worker")
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
        ask({kind="clock"},function(q)
          core.after(.35,function()
            ask({kind="clock"},function(later)
              assert(later.tick>q.tick,"worker did not advance without a view")
              away_tick=later.tick
            end)
          end)
        end)
      end)
    elseif away_tick and not reentered and bodies()>=2 then
      reentered=true
      core.log("action","PASS NATIVE PROJECTED ROLLING STOCK: original steam and coach cull and return while the worker clock runs")
      ask({kind="stop"},function() end)
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
        assert(first.ok and first.day>expected.day and first.tick==first.day*74 and first.value.cash==expected.cash)
        api.worker_build=dofile(mod.."/campaign_build_proxy.lua")(authority_test)
        local builder=viewer or {get_player_name=function() return owner end}
        api.on_worker_build=function(name,tiles,quote)
          assert(name==owner and #tiles==14 and quote.cost==initial_price)
          api.on_worker_build=nil
          core.log("action","PASS NATIVE PROJECTED HOTBAR BUILD: stock Autorail release committed on the worker")
          run_plans(1,{
          {"rail",{tool="depot",first=depot,direction=2}},
          {"rail",{tool="station",first=tile(x+3),last=tile(x+5),axis=0,length=3,tracks=1}},
          {"rail",{tool="station",first=tile(x+10),last=tile(x+12),axis=0,length=3,tracks=1}},
          {"transport",{mode="rail",operation="buy",depot=depot,parts={0,27}},nil,function(bought)
            train_id=bought.value.id
            ask({kind="command",command={kind="transport_start",mode="rail",vehicle=train_id,
              first=2,second=1,revision=bought.revision}},function(started)
              assert(started.ok,started.why)
              watch()
            end)
          end},
          })
        end
        ui.select_tool(builder,"rail_autotrack")
        assert(ui.begin_autorail(builder,origin,{x=2*(x+1)+.5,z=2*z+.5}))
        ui.end_autorail(builder,tile(x+14),{x=2*(x+14)+.5,z=2*z+.5})
      end)
    end)
  end
  function qa_hooks.stopped(reason,seq,day,detail)
    assert(reason=="stopped" and seq>10 and day>expected.day and painted and reentered,detail or reason)
    assert(not viewer or movement,"expected graphical movement input")
    assert(S.speed==expected.speed and S.day==expected.day and (not clock or clock.counter==expected.day*74))
    local state=disk.read()
    assert(state.day==day and state.passenger_house_clock.counter==day*74 and state.stock_generated_profile.width==64)
    assert(state.tiles[origin].rail_tracks==1 and not S.tiles[origin].rail_tracks)
    if viewer then assert(state.stock_rail_dispatch.runs[1].orders[1].station==1) end
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
