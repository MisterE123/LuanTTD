-- Appended only in the disposable graphical singleplayer fixture. Terrain
-- is the stock QA corridor; construction, dispatch, and fares use the worker.
local native_paid_form=core.show_formspec
core.show_formspec=function(owner,form,spec)
  if form=="luanttd_core:tram_service_offer" then
    core.log("action","TRAM_PAID_NATIVE_OFFER "..spec)
  end
  return native_paid_form(owner,form,spec)
end
core.register_on_joinplayer(function(player)
  local owner=player:get_player_name()
  local path=core.get_worldpath()
  local source=assert(io.open(path.."/native-focus-layout","r"))
  local _,first,last,a,b=source:read("*n","*n","*n","*n","*n");source:close()
  local x,z=Sim.xy(a)
  local depot=Sim.id(x+2,z-1)
  local function ask(q,fn)
    q.player=owner
    assert(authority.query(q,function(r)
      assert(r.ok,r.why)
      if fn then fn(r) end
    end))
  end
  local function command(c,done)
    ask({kind="company"},function(r)
      c.revision=r.revision
      ask({kind="command",command=c},done)
    end)
  end
  local function road(request,done)
    command({kind="road_place",request=request},done)
  end
  local function chain(list,index,done)
    if not list[index] then return done() end
    list[index](function()chain(list,index+1,done)end)
  end
  local function stop(id)
    return function(done)
      road({tool="stock_stop_area",kind="bus",first=id,last=id,axis=0,direction=0,through=true},done)
    end
  end
  local function geom(firsts)
    for _,id in ipairs(firsts) do
      local cell=assert(api.render.host_tile(id))
      assert(cell.tram and cell.tram.kind=="drive_stop" and cell.tram.shared_station)
    end
  end
  local function aim(tile,far)
    local u,v=Sim.xy(tile)
    local y=select(2,api.terrain.tile(tile))
    local dx,dz=far and 4 or .16,far and 6 or .22
    local c={x=2*u+.5+dx,y=y+(far and 4.7 or 5.8),z=2*v+.5+dz}
    player:set_pos(c)
    player:set_look_horizontal(math.atan2(dx,-dz))
    player:set_look_vertical(math.atan2(c.y+1.625-y,math.sqrt(dx*dx+dz*dz)))
  end
  local loaded=OwnerCheckpoint.read()
  if loaded and loaded.tram_pilot and loaded.tram_pilot.carrier then
    local carrier=loaded.tram_pilot.carrier
    assert(carrier.delivered>0 and carrier.revenue>0)
    aim(a,true)
    core.log("action","FOCUS_NATIVE_POSITION returning paid tram")
    core.log("action",("TRAM_PAID_NATIVE_REOPEN %d riders, $%d"):format(carrier.delivered,carrier.revenue))
    return
  end
  core.after(1,function()
    chain({
      function(done) command({kind="road_build",first=Sim.id(x-2,z),last=Sim.id(x+9,z)},done) end,
      stop(a),stop(b),
      function(done) road({tool="tram_lay",axis=0,first=first,last=last},done) end,
      function(done) road({tool="tram_facility",kind="depot",first=depot,direction=1},done) end,
    },1,function()
      assert(world.go_menu(player,"tram_operations"))
      local slot
      for i,j in ipairs(world.hotbar_layout(player)) do if j==2 then slot=i end end
      assert(slot and slot<=9)
      aim(depot)
      core.log("action","TRAM_PAID_NATIVE_SLOT "..slot)
      core.log("action","FOCUS_NATIVE_POSITION native paid route ready in the normal worker")
      local seen
      local function poll()
        local f=io.open(path.."/native-focus-step","r")
        if f then
          local step=f:read("*l");f:close()
          if step~=seen then
            seen=step
            if step=="first" then aim(a)
            elseif step=="second" then
              aim(b)
              for i,j in ipairs(world.hotbar_layout(player)) do
                if j==8 then core.log("action","TRAM_PAID_NATIVE_DISPATCH "..i) end
              end
            elseif step=="scenery" then aim(b,true)
              local p=assert(OwnerCheckpoint.read()).tram_pilot
              assert(p and p.carrier,"the native modal did not buy a real vehicle")
            end
            core.log("action","TRAM_PAID_NATIVE_STAGE "..tostring(step))
          end
        end
        local snapshot=OwnerCheckpoint.read()
        local p=snapshot and snapshot.tram_pilot
        if p and p.carrier and p.carrier.delivered>0 and p.carrier.revenue>0 then
          geom({a,b})
          local leg=p.legs[p.leg]
          local frame=leg and leg.frames[p.index]
          if frame then aim(frame[4],true) end
          core.log("action",("TRAM_PAID_NATIVE_FARE %d riders, $%d"):format(p.carrier.delivered,p.carrier.revenue))
          return
        end
        core.after(.32,poll)
      end
      poll()
    end)
  end)
end)
