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
      core.log("action",("FOCUS_NATIVE_RECEIPT %s day=%d cash=%d bus=%d delivered=%d revenue=%d")
        :format(label,r.day,r.value.cash,stat_id,delivered,revenue))
    end)
  end
  -- The fixture points the camera; only real client input selects and
  -- releases the two tools. The road is separate from the paid service.
  local road_qa
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
    if label=="x-start" then ready("X",5,q.x,q.z,.12)
    elseif label=="x-end" then
      aim(q.x+3,q.z+1,.75) -- aim outside the locked row
      core.log("action","NATIVE_ROAD_GESTURE_X_RELEASE")
    elseif label=="check-x" then
      local snapshot=assert(OwnerCheckpoint.read())
      for id=q.first,q.last do assert(snapshot.tiles[id].build=="road") end
      assert(not snapshot.tiles[Sim.id(q.x+3,q.z+1)].build)
      assert(snapshot.tiles[q.first+1].road_bits==10)
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
      core.log("action","NATIVE_ROAD_GESTURE_"..(label=="waypoint-done" and "WAYPOINT_PASS" or "ERASE_WAYPOINT_PASS"))
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
          live:set_pos({x=42.75,y=13.25,z=31.50})
          core.after(.55,function() core.log("action","FOCUS_NATIVE_REJOIN_SET") end)
        elseif label=="check-rejoin" then
          assert(math.abs(pos.x-42.75)<.08 and math.abs(pos.y-13.25)<.08 and math.abs(pos.z-31.50)<.08,
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
