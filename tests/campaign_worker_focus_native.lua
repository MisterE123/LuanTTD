-- Appended only in the disposable native singleplayer test. The marker
-- changes test phases, not the simulation clock or the worker's state.
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  local path=core.get_worldpath()
  local stat_id,at_return
  local function load_id()
    local f=io.open(path.."/native-focus-bus","r")
    if not f then return end
    local id=f:read("*n");f:close();return id
  end
  local function ask(request,next)
    request.player=name
    assert(authority.query(request,function(r)
      assert(r.ok,r.why)
      if next then next(r) end
    end))
  end
  local function commit(c,done)
    ask({kind="company"},function(r)
      c.revision=r.revision
      ask({kind="command",command=c},done)
    end)
  end
  local waypoints=core.settings:get_bool("luanttd_native_waypoint",false)
  local fixed=core.settings:get_bool("luanttd_native_explicit_road_facilities",false)
  local function build(request,done)
    if fixed and request.tool=="road_depot" then
      request={tool="stock_terminal",first=request.first,kind="depot",direction=1}
    elseif fixed and request.tool=="road_station" then
      request={tool="stock_terminal",first=request.first,kind="bus",direction=0,through=true}
    end
    ask({kind="road_quote",request=request},function(r)
      ask({kind="command",command={kind="road_commit",revision=r.revision,request=request,
        token=r.value.token,quote=r.value}},done)
    end)
  end
  local function bus_layout()
    local f=assert(io.open(path.."/native-focus-layout","r"))
    local depot,first,last,station_a,station_b,sw,se,west,approach=f:read("*n","*n","*n","*n","*n","*n","*n","*n","*n")
    f:close()
    if core.settings:get_bool("luanttd_native_focus_terminal_depot",false) then
      return {depot=west,station_a=station_a,station_b=station_b,loop={{first,last}}}
    end
    local legs={{west,last},{approach,first}}
    if not core.settings:get_bool("luanttd_native_focus_dead_end",false) then
      legs[3],legs[4],legs[5]={last,se},{se,sw},{sw,first}
    end
    return {depot=depot,station_a=station_a,station_b=station_b,loop=legs}
  end
  local function arm(ready)
    stat_id=load_id()
    if stat_id then return ready() end
    local q=bus_layout()
    local function roadway(i,done)
      if not q.loop[i] then return done() end
      local a,b=unpack(q.loop[i])
      commit({kind="road_build",first=a,last=b},function() roadway(i+1,done) end)
    end
    roadway(1,function()
      build({tool="road_depot",first=q.depot},function()
        build({tool="road_station",first=q.station_a},function()
          build({tool="road_station",first=q.station_b},function()
            ask({kind="depot",mode="road",depot=q.depot},function(list)
              local request
              for _,row in ipairs(list.value.offers) do
                if row.request.cargo=="passenger" then request=row.request;break end
              end
              commit(assert(request),function(r)
                stat_id=r.value
                local s=assert(OwnerCheckpoint.read())
                local a,b=s.tiles[q.station_a].station,s.tiles[q.station_b].station
                commit({kind="road_order_add",vehicle=stat_id,station=a},function()
                  local function finish()
                    commit({kind="road_order_add",vehicle=stat_id,station=b},function()
                      commit({kind="road_toggle",vehicle=stat_id},function()
                        assert(core.safe_file_write(path.."/native-focus-bus",tostring(stat_id)))
                        ready()
                      end)
                    end)
                  end
                  if not waypoints then return finish() end
                  local target=q.station_a+2
                  build({tool="road_waypoint",first=target,axis=0},function()
                    ask({kind="orders",mode="road",vehicle=stat_id},function(list)
                      commit({kind="vehicle_order",mode="road",vehicle=stat_id,tile=target,
                        order_revision=list.value.revision,operation="append"},function(applied)
                        assert(applied.value.count==2)
                        finish()
                      end)
                    end)
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end
  local function receipt(label)
    ask({kind="company"},function(r)
      stat_id=stat_id or load_id()
      local s=assert(OwnerCheckpoint.read())
      local v=assert(stat_id and s.fleet[stat_id])
      assert(v.owner==name and v.running and #v.orders==(waypoints and 3 or 2))
      if waypoints then assert(v.orders[2].action=="via") end
      if fixed then
        local b=bus_layout()
        assert(s.tiles[b.depot].depot_dir==3 and s.tiles[b.depot].road_terminal_level)
        assert(s.tiles[b.station_a].stop_axis==10 and s.tiles[b.station_b].stop_axis==10)
        assert(s.tiles[b.station_a].road_terminal_level and s.tiles[b.station_b].road_terminal_level)
      end
      local delivered,revenue=v.delivered or 0,v.revenue or 0
      if label=="focus-return" then at_return=delivered end
      if label=="reopen" and core.settings:get_bool("luanttd_native_town_fund",false) then
        local f=assert(io.open(path.."/native-focus-funded-town","r"))
        local id=f:read("*n"); f:close()
        local t=assert(s.stock_town_growth.towns[id])
        assert(t.growing and t.fund_buildings_months>=1 and t.fund_buildings_months<=3)
        core.log("action","FOCUS_NATIVE_FUND_REOPEN_PASS town funding and paid service restored")
      end
      core.log("action",("FOCUS_NATIVE_RECEIPT %s day=%d cash=%d bus=%d delivered=%d revenue=%d")
        :format(label,r.day,r.value.cash,stat_id,delivered,revenue))
    end)
  end
  -- The fixture points the camera; only real client input selects and
  -- releases the two tools. The road is separate from the paid service.
  local road_qa
  local tram_places,tram_purchase_quotes=0,0
  local function observe_tram_placements()
    local client=assert(api.worker_bridge_client)
    local real_query=client.query
    client.query=function(req,callback)
      if req.kind=="road_place" and req.request and req.request.tool=="tram_facility" then tram_places=tram_places+1 end
      if req.kind=="transport_quote" and req.request and req.request.mode=="tram" then tram_purchase_quotes=tram_purchase_quotes+1 end
      return real_query(req,callback)
    end
  end
  local function road_test(player,label)
    if not road_qa then
      local x,z=Sim.xy(bus_layout().station_a)
      local first=Sim.id(x+3,z-3)
      local last=Sim.id(x+6,z-3)
      road_qa={x=x+3,z=z-3,first=first,last=last,tx=x+2,tz=z+1}
    end
    local q=road_qa
    local function aim(x,z,offset)
      local snapshot=assert(OwnerCheckpoint.read())
      local t=snapshot.tiles[Sim.id(x,z)]
      player:set_pos({x=x*2+offset,y=t.h+7.5,z=z*2+.5})
      player:set_look_vertical(math.pi/2-.002)
      player:set_look_horizontal(0)
    end
    local function ready(which,logical,x,z,offset)
      assert(world.go_menu(player,"road_direction"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==logical then slot=i end end
      assert(slot and slot<=9)
      aim(x,z,offset)
      core.log("action","NATIVE_ROAD_GESTURE_"..which.." slot="..slot)
    end
    if label=="x-start" then
      if core.settings:get_bool("luanttd_native_stock_road_price",false) then
        local snapshot=assert(OwnerCheckpoint.read())
        local expected=6*95
        for id=q.first,q.last do
          local t=snapshot.tiles[id]
          assert(not (t.build or t.house or t.site or t.tram) and t.terrain~="water")
          if t.wood then expected=expected+20*(type(t.wood)=="table" and t.wood.count or 1)
          elseif t.stock_clear_ground==2 then expected=expected+200
          elseif t.stock_clear_ground==3 or snapshot.stock_farm_fields and snapshot.stock_farm_fields[id] then
            expected=expected+500
          elseif (t.stock_clear_ground or 0)>0 then expected=expected+40
          elseif t.stock_clear_density~=0 then expected=expected+20 end
        end
        local client=assert(api.worker_bridge_client)
        local query=client.query
        client.query=function(req,done)
          if req.kind=="road_place" and req.request.tool=="drag" and req.request.first==q.first then
            return query(req,function(result)
              assert(result.ok,result.why)
              assert((result.why or ""):find("$"..expected.." spent on 4 tiles",1,true),result.why)
              q.stock_cost=expected
              return done(result)
            end)
          end
          return query(req,done)
        end
      end
      ready("X",5,q.x,q.z,.12)
    elseif label=="x-end" then
      aim(q.x+3,q.z+1,.75) -- aim outside the locked row
      core.log("action","NATIVE_ROAD_GESTURE_X_RELEASE")
    elseif label=="check-x" then
      local snapshot=assert(OwnerCheckpoint.read())
      for id=q.first,q.last do assert(snapshot.tiles[id].build=="road") end
      assert(not snapshot.tiles[Sim.id(q.x+3,q.z+1)].build)
      assert(snapshot.tiles[q.first+1].road_bits==10)
      if core.settings:get_bool("luanttd_native_stock_road_price",false) then
        assert(q.stock_cost)
        core.log("action","NATIVE_ROAD_GESTURE_X_PRICE_PASS stock base cost $"..q.stock_cost)
      end
      core.log("action","NATIVE_ROAD_GESTURE_X_PASS")
    elseif label=="waypoint" or label=="erase-waypoint" then
      assert(world.go_menu(player,"road_stops"))
      local slot
      local logical=label=="waypoint" and 5 or 6
      for i,j in ipairs(world.hotbar_layout(player)) do if j==logical then slot=i end end
      assert(slot and slot<=9)
      aim(q.x+1,q.z,.12)
      core.log("action","NATIVE_ROAD_GESTURE_"..(logical==5 and "WAYPOINT" or "ERASE_WAYPOINT").." slot="..slot)
    elseif label=="waypoint-done" or label=="erase-waypoint-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local tile=Sim.id(q.x+1,q.z)
      local target,hit=world.target(player)
      local desc,note=ui.world_status(player,target,true,hit)
      assert((snapshot.tiles[tile].road_waypoint_id~=nil)==(label=="waypoint-done"),
        ("wanted %d, hit %s, tool %s, status %s"):format(tile,tostring(target),tostring(desc),tostring(note)))
      assert(snapshot.tiles[tile].road_bits==10)
      if label=="waypoint-done" then
        local id=snapshot.tiles[tile].road_waypoint_id
        if q.was_waypoint then
          assert(id==q.was_waypoint,"Rebuilding the nearby recently removed waypoint must preserve its identity")
          core.log("action","NATIVE_ROAD_GESTURE_WAYPOINT_REBUILD_PASS")
        end
        q.was_waypoint=id
      end
      core.log("action","NATIVE_ROAD_GESTURE_"..(label=="waypoint-done" and "WAYPOINT_PASS" or "ERASE_WAYPOINT_PASS"))
    elseif label=="tram-facility-depot" or label=="tram-facility-platform" then
      assert(world.go_menu(player,"tramway"))
      local depot=label=="tram-facility-depot"
      if depot then observe_tram_placements() end
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==(depot and 4 or 3) then slot=i end end
      assert(slot)
      aim(q.x+(depot and 1 or 2),q.z+1,.5)
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_"..(depot and "DEPOT" or "PLATFORM").." slot="..(slot==10 and 0 or slot))
    elseif label=="tram-facility-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local a,b=snapshot.tiles[Sim.id(q.x+1,q.z+1)],snapshot.tiles[Sim.id(q.x+2,q.z+1)]
      assert(a.tram and a.tram.kind=="depot")
      assert(b.tram and b.tram.kind=="drive_stop")
      assert(tram_places==2 and tram_purchase_quotes==0,("Expected two placements and no purchase quotes; got %d and %d"):format(tram_places,tram_purchase_quotes))
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_FACILITY_PASS two normal tool clicks, two worker transactions")
    elseif label=="tram-lay-start" then
      assert(world.go_menu(player,"tramway"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==2 then slot=i end end
      assert(slot)
      aim(q.x+1,q.z,.12)
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_LAY slot="..(slot==10 and 0 or slot))
    elseif label=="tram-lay-end" then
      aim(q.x+2,q.z,.75)
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_LAY_RELEASE")
    elseif label=="tram-remove-start" then
      local a,b=Sim.id(q.x+1,q.z),Sim.id(q.x+2,q.z)
      local function ready()
        local snapshot=assert(OwnerCheckpoint.read())
        for _,id in ipairs{a,b} do assert(snapshot.tiles[id].tram and snapshot.tiles[id].road_bits==10) end
        assert(snapshot.tiles[a].tram.tram_bits==2 and snapshot.tiles[b].tram.tram_bits==8)
        assert(world.go_menu(player,"tramway"))
        local slot
        for i,j in ipairs(world.hotbar_layout(player)) do if j==10 then slot=i end end
        assert(slot)
        aim(q.x+1,q.z,.12)
        core.log("action","NATIVE_ROAD_GESTURE_TRAM_REMOVE slot="..(slot==10 and 0 or slot))
      end
      if core.settings:get_bool("luanttd_native_tram_drag",false) then ready()
      else
        local request={mode="tram",operation="build",kind="road",cells={a,b}}
        ask({kind="transport_quote",request=request},function(r)
          ask({kind="command",command={kind="transport_commit",revision=r.revision,token=r.value.token}},ready)
        end)
      end
    elseif label=="tram-remove-end" then
      aim(q.x+2,q.z,.75)
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_REMOVE_RELEASE")
    elseif label=="tram-remove-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      for x=q.x+1,q.x+2 do
        local t=snapshot.tiles[Sim.id(x,q.z)]
        assert(t.build=="road" and t.road_bits==10 and t.tram==nil)
      end
      core.log("action","NATIVE_ROAD_GESTURE_TRAM_REMOVE_PASS")
    elseif label=="tree-road" then
      local snapshot=assert(OwnerCheckpoint.read())
      local corners=dofile(mod.."/openttd/terrain.lua")
      local bus=bus_layout()
      local served_a=snapshot.stations[snapshot.tiles[bus.station_a].station].site
      local served_b=snapshot.stations[snapshot.tiles[bus.station_b].station].site
      local terrain,town
      for z=2,Sim.H-1 do for x=2,Sim.W-1 do
        local id=Sim.id(x,z)
        local t=snapshot.tiles[id]
        if t.wood and not (t.build or t.house or t.site or t.tram or t.stock_void) and
            corners.tile(snapshot.corner_grid,x,z)==0 then
          local pick,dist=Sim.nearest_town(snapshot,id)
          local before=snapshot.companies[name].stock_town_authority_ratings
          if pick and dist<20 and pick.id~=served_a and pick.id~=served_b and (not before or not before[pick.id]) then
            terrain={id=id,x=x,z=z,count=type(t.wood)=="table" and t.wood.count or 1}
            town=pick.id
            break
          end
        end
      end if terrain then break end end
      assert(terrain,"Default campaign has no unserved wooded tile near a town.")
      q.tree=terrain
      local client=assert(api.worker_bridge_client)
      local query=client.query
      client.query=function(req,done)
        if req.kind=="road_place" and req.request.tool=="drag" and req.request.first==terrain.id then
          return query(req,function(result)
            local expected=95+20*terrain.count
            assert(result.ok and (result.why or ""):find("$"..expected.." spent on 1 tile",1,true),result.why)
            assert(result.why:find("local authority rating",1,true),result.why)
            local after=assert(OwnerCheckpoint.read())
            assert(after.companies[name].stock_town_authority_ratings[town]==465)
            q.tree_town=town
            return done(result)
          end)
        end
        return query(req,done)
      end
      ready("TREE_ROAD",5,terrain.x,terrain.z,.12)
    elseif label=="tree-road-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local t=snapshot.tiles[q.tree.id]
      assert(q.tree_town and t.build=="road" and not t.wood)
      core.log("action","NATIVE_ROAD_GESTURE_TREE_ROAD_PASS actual tree removal and 35-point town authority penalty")
    elseif label=="town-fund-loans" then
      local function borrow()
        ask({kind="company"},function(r)
          if r.value.cash>=212000 then
            -- Freeze the in-game clock just for the receipt comparison,
            -- so the bus cannot add a daily operating cost between reads.
            ask({kind="command",command={kind="speed",speed=0,revision=r.revision}},function()
              core.log("action","NATIVE_ROAD_GESTURE_TOWN_FUND_LOANS")
            end)
          else
            ask({kind="command",command={kind="company_loan",amount=10000,revision=r.revision}},borrow)
          end
        end)
      end
      borrow()
    elseif label=="town-fund-done" then
      local state=assert(OwnerCheckpoint.read())
      assert(q.funded and state.stock_town_growth.towns[q.tree_town].fund_buildings_months==3)
      assert(core.safe_file_write(path.."/native-focus-funded-town",tostring(q.tree_town)))
      ask({kind="company"},function(r)
        ask({kind="command",command={kind="speed",speed=1,revision=r.revision}},function()
          core.log("action","NATIVE_ROAD_GESTURE_TOWN_FUND_PASS paid $207031 and funded real town growth")
        end)
      end)
    elseif label=="town-authority" then
      assert(q.tree_town and world.go_menu(player,"survey"))
      local state=assert(OwnerCheckpoint.read())
      local found
      for id,t in pairs(state.tiles) do
        if t.road_town==q.tree_town and t.build=="road" then found=id;break end
      end
      assert(found,"No town street for the authority inspection")
      local x,z=Sim.xy(found)
      aim(x,z,.5)
      if core.settings:get_bool("luanttd_native_town_fund",false) then
        local client=assert(api.worker_bridge_client)
        local query=client.query
        client.query=function(req,done)
          if req.kind=="command" and req.command.kind=="town_fund_buildings" then
            local before=assert(OwnerCheckpoint.read()).companies[name].expense
            return query(req,function(result)
              assert(result.ok,result.why)
              local after=assert(OwnerCheckpoint.read())
              assert(after.companies[name].expense==before+207031,("Expected $207031 expense; got $%d"):format(after.companies[name].expense-before))
              local town=after.stock_town_growth.towns[q.tree_town]
              assert(town.fund_buildings_months==3 and town.growing)
              q.funded=true
              return done(result)
            end)
          end
          return query(req,done)
        end
      end
      local show=core.show_formspec
      core.show_formspec=function(who,form,body)
        if who==name and form=="luanttd_core:town_authority" then
          assert(body:find("Very good (+465)",1,true),body)
          assert(body:find(state.sites[q.tree_town].name,1,true),body)
          if core.settings:get_bool("luanttd_native_town_fund",false) then
            assert(body:find("fund_buildings;",1,true) and body:find(core.formspec_escape("$207,031"),1,true),body)
          end
          core.log("action","NATIVE_ROAD_GESTURE_TOWN_PANEL_PASS authoritative rating 465 shown through Inspect")
          core.show_formspec=show
        end
        return show(who,form,body)
      end
      core.log("action","NATIVE_ROAD_GESTURE_TOWN_PANEL")
    elseif label=="remove-start" then ready("REMOVE",7,q.x,q.z,.12)
    elseif label=="remove-end" then
      aim(q.x+3,q.z,.75)
      core.log("action","NATIVE_ROAD_GESTURE_REMOVE_RELEASE")
    elseif label=="check-remove" then
      local snapshot=assert(OwnerCheckpoint.read())
      for id=q.first,q.last do assert(snapshot.tiles[id].build==nil) end
      assert(snapshot.fleet[load_id()].running and snapshot.fleet[load_id()].revenue>0)
      core.log("action","NATIVE_ROAD_GESTURE_REMOVE_PASS")
    elseif label=="layout" then
      assert(world.go_menu(player,"roads"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==4 then slot=i end end
      assert(slot and slot<=9)
      aim(q.x,q.z+1,.12)
      local show=core.show_formspec
      core.show_formspec=function(user,form,body)
        if user==name and form=="luanttd_core:road_terminal_layout" then
          assert(body:find("Road depot layout",1,true) and body:find("door_2;East",1,true))
          core.log("action","NATIVE_ROAD_GESTURE_LAYOUT_OPEN")
          core.show_formspec=show
        end
        return show(user,form,body)
      end
      core.log("action","NATIVE_ROAD_GESTURE_LAYOUT slot="..slot)
    elseif label=="layout-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local depot=snapshot.tiles[Sim.id(q.x,q.z+1)]
      assert(depot.build=="road_depot" and depot.depot_dir==2 and depot.road_terminal_level)
      core.log("action","NATIVE_ROAD_GESTURE_LAYOUT_PASS")
    elseif label=="stop-layout" then
      assert(world.go_menu(player,"road_stops"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==2 then slot=i end end
      assert(slot and slot<=9)
      aim(q.x+1,q.z,.25)
      local show=core.show_formspec
      core.show_formspec=function(user,form,body)
        if user==name and form=="luanttd_core:road_terminal_layout" then
          assert(body:find("through_0;East",1,true))
          core.log("action","NATIVE_ROAD_GESTURE_STOP_LAYOUT_OPEN")
          core.show_formspec=show
        end
        return show(user,form,body)
      end
      core.log("action","NATIVE_ROAD_GESTURE_STOP_LAYOUT slot="..slot)
    elseif label=="stop-end" then
      aim(q.x+2,q.z,.25)
      core.log("action","NATIVE_ROAD_GESTURE_STOP_RELEASE")
    elseif label=="stop-preview" then
      local target,hit=world.target(player)
      local cells,ok,hint=ui.preview(player,target,hit)
      assert(ok and #cells==2 and hint:find("2 tiles",1,true),tostring(hint))
      assert(cells[1]==q.first+1 and cells[2]==q.first+2)
      core.log("action","NATIVE_ROAD_GESTURE_STOP_PREVIEW_PASS "..hint)
    elseif label=="stop-done" or label=="stop-erase-done" then
      local s=assert(OwnerCheckpoint.read())
      local a,b=s.tiles[q.first+1],s.tiles[q.first+2]
      assert(b.station and b.build=="road_station" and b.stop_axis==10)
      local st=assert(s.stations[b.station])
      assert(st.road_members[q.first+2]=="bus")
      if label=="stop-done" then
        assert(a.station==b.station and st.road_members[q.first+1]=="bus")
        assert(st.road_stop_areas.bus.w==2)
        assert(world.go_menu(player,"road_stops"))
        local slot
        for i,j in ipairs(world.hotbar_layout(player)) do if j==4 then slot=i end end
        assert(slot and slot<=9)
        aim(q.x+1,q.z,.25)
        core.log("action","NATIVE_ROAD_GESTURE_STOP_ERASE slot="..slot)
      else
        assert(not a.station and a.build=="road" and a.road_bits==10)
        assert(st.tile==q.first+2 and not st.road_members[q.first+1])
        core.log("action","NATIVE_ROAD_GESTURE_STOP_ERASE_PASS")
      end
    elseif label=="stop-join" then
      assert(world.go_menu(player,"road_stops"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==2 then slot=i end end
      assert(slot and slot<=9)
      aim(q.x+4,q.z,.25)
      local snapshot=assert(OwnerCheckpoint.read())
      local joining=assert(snapshot.stations[snapshot.tiles[q.first+2].station])
      local show=core.show_formspec
      core.show_formspec=function(user,form,body)
        if user==name and form=="luanttd_core:road_join_picker" then
          assert(body:find("New station",1,true) and body:find(core.formspec_escape(joining.name),1,true))
          core.log("action","NATIVE_ROAD_GESTURE_STOP_JOIN_OPEN")
          core.show_formspec=show
        end
        return show(user,form,body)
      end
      core.log("action","NATIVE_ROAD_GESTURE_STOP_JOIN slot="..slot)
    elseif label=="stop-join-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local base=assert(snapshot.tiles[q.first+2].station)
      local dest=Sim.id(q.x+4,q.z)
      assert(snapshot.tiles[dest].station==base,"The separate road platform should have joined the selected station")
      assert(snapshot.stations[base].road_members[dest]=="bus")
      core.log("action","NATIVE_ROAD_GESTURE_STOP_JOIN_PASS")
    elseif label=="stop-mix" then
      assert(world.go_menu(player,"freight"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==3 then slot=i end end
      assert(slot and slot<=9)
      aim(q.x+5,q.z,.25)
      if not core.settings:get_bool("luanttd_native_road_stop_auto",false) then
        local show=core.show_formspec
        core.show_formspec=function(user,form,body)
          if user==name and form=="luanttd_core:road_terminal_layout" then
            assert(body:find("Truck stop layout",1,true))
            core.log("action","NATIVE_ROAD_GESTURE_STOP_MIX_OPEN")
            core.show_formspec=show
          end
          return show(user,form,body)
        end
      end
      core.log("action","NATIVE_ROAD_GESTURE_STOP_MIX slot="..slot)
    elseif label=="stop-mix-done" then
      local snapshot=assert(OwnerCheckpoint.read())
      local bus,truck=Sim.id(q.x+4,q.z),Sim.id(q.x+5,q.z)
      local st=assert(snapshot.stations[snapshot.tiles[bus].station])
      local target,hit=world.target(player)
      local desc,status=ui.world_status(player,target,true,hit)
      assert(snapshot.tiles[truck].station==st.id and st.road_members[truck]=="truck" and st.road_members[bus]=="bus",
        ("target=%s expected=%d station=%s wanted=%d | %s | %s"):format(tostring(target),truck,
          tostring(snapshot.tiles[truck].station),st.id,tostring(desc),tostring(status)))
      assert(st.truck_tile==truck and st.road_stop_areas.bus and st.road_stop_areas.truck)
      local function model(i)
        local x,z=Sim.xy(i)
        local t=snapshot.tiles[i]
        return core.get_node({x=x*2,y=t.road_terminal_level+1,z=z*2}).name
      end
      local aa,bb=model(bus),model(truck)
      assert(aa~=bb and not aa:find("freight",1,true) and bb:find("freight",1,true),aa.." and "..bb)
      core.log("action","NATIVE_ROAD_GESTURE_STOP_MIX_PASS "..aa.." + "..bb)
    elseif label=="town-start" then ready("TOWN",7,q.tx,q.tz,.12)
    elseif label=="town-end" then
      aim(q.tx+2,q.tz,.75)
      core.log("action","NATIVE_ROAD_GESTURE_TOWN_RELEASE")
    elseif label=="check-town" then
      local snapshot=assert(OwnerCheckpoint.read())
      for ix=q.tx,q.tx+2 do assert(snapshot.tiles[Sim.id(ix,q.tz)].road_town==nil) end
      local ratings=snapshot.companies[name].stock_town_authority_ratings
      assert(ratings and next(ratings))
      core.log("action","NATIVE_ROAD_GESTURE_TOWN_PASS")
    elseif label=="reopen" then
      local snapshot=assert(OwnerCheckpoint.read())
      if core.settings:get_bool("luanttd_native_municipal_road",false) then
        for ix=q.tx,q.tx+2 do assert(snapshot.tiles[Sim.id(ix,q.tz)].road_town==nil) end
        assert(next(snapshot.companies[name].stock_town_authority_ratings))
      end
      local area=core.settings:get_bool("luanttd_native_road_stop_area",false)
      for id=q.first,q.last do
        if not area or id~=q.first+1 and id~=q.first+2 then assert(snapshot.tiles[id].build==nil) end
      end
      if area then
        local a,b=snapshot.tiles[q.first+1],snapshot.tiles[q.first+2]
        local st=assert(snapshot.stations[b.station])
        assert(not a.station and a.road_bits==10 and st.tile==q.first+2 and st.road_members[q.first+2]=="bus")
        if core.settings:get_bool("luanttd_native_road_stop_join",false) then
          local dest=Sim.id(q.x+4,q.z)
          assert(snapshot.tiles[dest].station==b.station and st.road_members[dest]=="bus")
          if core.settings:get_bool("luanttd_native_road_stop_mix",false) then
            local truck=Sim.id(q.x+5,q.z)
            assert(snapshot.tiles[truck].station==b.station and st.truck_tile==truck and st.road_members[truck]=="truck")
            core.log("action","NATIVE_ROAD_GESTURE_STOP_MIX_REOPEN_PASS")
          end
          core.log("action","NATIVE_ROAD_GESTURE_STOP_JOIN_REOPEN_PASS")
        end
        core.log("action","NATIVE_ROAD_GESTURE_STOP_REOPEN_PASS")
      end
      if fixed and core.settings:get_bool("luanttd_native_explicit_road_ui",false) then
        local depot=snapshot.tiles[Sim.id(q.x,q.z+1)]
        assert(depot.build=="road_depot" and depot.depot_dir==2)
      end
      core.log("action","NATIVE_ROAD_GESTURE_REOPEN_PASS")
    end
  end
  local function probe()
    local live=core.get_player_by_name(name)
    if not live then return end
    local pos=live:get_pos()
    if pos and authority and authority.status()=="owned" then
      core.log("action",("FOCUS_NATIVE_POSITION %.4f %.4f %.4f"):format(pos.x,pos.y,pos.z))
      local stage=path.."/native-focus-step"
      local f=io.open(stage,"r")
      if f then
        local label=f:read("*l");f:close();os.remove(stage)
        if label:sub(1,5)=="road-" then road_test(live,label:sub(6))
        elseif label=="initial" then arm(function() receipt(label) end)
        elseif label=="focus-return" or label=="reopen" then receipt(label)
        elseif label=="set-rejoin" then
          core.log("action","FOCUS_NATIVE_REJOIN_MOVE")
          live:set_look_horizontal(1.34)
          live:set_look_vertical(.42)
          local height=core.settings:get_bool("luanttd_native_town_fund",false) and 48.25 or 13.25
          live:set_pos({x=42.75,y=height,z=31.50})
          core.after(.55,function() core.log("action","FOCUS_NATIVE_REJOIN_SET") end)
        elseif label=="check-rejoin" then
          local height=core.settings:get_bool("luanttd_native_town_fund",false) and 48.25 or 13.25
          assert(math.abs(pos.x-42.75)<.08 and math.abs(pos.y-height)<.08 and math.abs(pos.z-31.50)<.08,
            "Reopen did not restore the position the player left")
          assert(math.abs(live:get_look_horizontal()-1.34)<.05 and math.abs(live:get_look_vertical()-.42)<.05,
            "Reopen did not restore the direction the player was looking")
          core.log("action","FOCUS_NATIVE_REJOIN_PASS exact bookmarked position and view after the process restarted")
        end
      end
      if at_return~=nil then
        local s=OwnerCheckpoint.read()
        local v=s and s.fleet[stat_id]
        if v and v.delivered>at_return then
          assert(v.running and v.revenue>0 and s.companies[name].revenue==v.revenue)
          if waypoints then
            assert(v.last_road_waypoint==1 and v.orders[2].station=="waypoint:1")
            core.log("action","NATIVE_ROAD_WAYPOINT_PAID")
          end
          core.log("action",("FOCUS_NATIVE_PAID bus=%d delivered=%d revenue=%d"):format(stat_id,v.delivered,v.revenue))
          at_return=nil
        end
      end
    end
    core.after(.16,probe)
  end
  core.after(.16,probe)
end)
