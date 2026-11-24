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
  local function build(request,done)
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
                  commit({kind="road_order_add",vehicle=stat_id,station=b},function()
                    commit({kind="road_toggle",vehicle=stat_id},function()
                      assert(core.safe_file_write(path.."/native-focus-bus",tostring(stat_id)))
                      ready()
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
      assert(v.owner==name and v.running and #v.orders==2)
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
      road_qa={x=x+3,z=z-3,first=first,last=last}
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
    elseif label=="remove-start" then ready("REMOVE",7,q.x,q.z,.12)
    elseif label=="remove-end" then
      aim(q.x+3,q.z,.75)
      core.log("action","NATIVE_ROAD_GESTURE_REMOVE_RELEASE")
    elseif label=="check-remove" then
      local snapshot=assert(OwnerCheckpoint.read())
      for id=q.first,q.last do assert(snapshot.tiles[id].build==nil) end
      assert(snapshot.fleet[load_id()].running and snapshot.fleet[load_id()].revenue>0)
      core.log("action","NATIVE_ROAD_GESTURE_REMOVE_PASS")
    elseif label=="reopen" then
      local snapshot=assert(OwnerCheckpoint.read())
      for id=q.first,q.last do assert(snapshot.tiles[id].build==nil) end
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
          core.log("action",("FOCUS_NATIVE_PAID bus=%d delivered=%d revenue=%d"):format(stat_id,v.delivered,v.revenue))
          at_return=nil
        end
      end
    end
    core.after(.16,probe)
  end
  core.after(.16,probe)
end)
