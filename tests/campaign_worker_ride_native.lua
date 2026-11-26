-- Full ordinary generated campaign; only the transport fixtures are scripted.
-- The two players are real graphical Luanti clients and the rider's sight,
-- steering attempts, seat selection and exits are actual native input.
local rider_name,witness_name="RideQA","RideWitness"
local function invariant(p,x)
  local ref=p:get_attach()
  return ref and ref==x
end
local function wait_for(label,check,done,n)
  local result=check()
  if result then done(result)
  elseif (n or 0)<145 then core.after(.16,function() wait_for(label,check,done,(n or 0)+1) end)
  else error("Timed out waiting for "..label) end
end
local function get_players()
  local rider,witness=core.get_player_by_name(rider_name),core.get_player_by_name(witness_name)
  return rider and witness and #world.hotbar_layout(rider)>0 and #world.hotbar_layout(witness)>0 and {rider,witness}
end
local function together(points)
  local first,last,depot,z
  for v=4,58 do
    for u=2,62-points do
      local flat,base=true
      for i=0,points do
        local id=Sim.id(u+i,v)
        local t=S.tiles[id]
        local mask,h=api.terrain.tile(id)
        if mask~=0 or base and h~=base or t.wood or t.house or t.site or t.owner or
            t.stock_industry or t.terrain=="water" or api.render.host_tile(id) and api.render.host_tile(id).owner then
          flat=false;break
        end
        base=h
      end
      if flat then
        depot,first,last,z=Sim.id(u,v),Sim.id(u+1,v),Sim.id(u+points,v),v
        return {first=first,last=last,depot=depot,level=base,x=u,z=z}
      end
    end
  end
end
local function ask(req,done)
  req.player=rider_name
  assert(authority.query(req,function(r) assert(r.ok,r.why);done(r) end))
end
local function commit(c,done)
  ask({kind="company"},function(r)
    c.revision=r.revision;ask({kind="command",command=c},done)
  end)
end
local function build(domain,request,done)
  ask({kind=domain.."_quote",request=request},function(r)
    ask({kind="command",command={kind=domain.."_commit",revision=r.revision,request=request,
      token=r.value.token,quote=r.value}},done)
  end)
end
local function stock_bus(q,done)
  local first,second=q.depot+3,q.last-1
  commit({kind="road_build",first=q.first,last=q.last},function()
    build("road",{tool="road_depot",first=q.depot},function()
      build("road",{tool="road_station",first=first},function()
        build("road",{tool="road_station",first=second},function()
          ask({kind="depot",mode="road",depot=q.depot},function(list)
            local buy
            for _,offer in ipairs(list.value.offers) do
              if offer.request.cargo=="passenger" then buy=offer.request;break end
            end
            assert(buy)
            commit(buy,function(r)
              local bus=r.value
              local state=assert(OwnerCheckpoint.read())
              local a,b=state.tiles[first].station,state.tiles[second].station
              commit({kind="road_order_add",vehicle=bus,station=b},function()
                commit({kind="road_order_add",vehicle=bus,station=a},function()
                  commit({kind="road_toggle",vehicle=bus},function() done(bus) end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end
local function stock_train(q,done)
  local stock={kind="rail",axis=0,length=3,tracks=1}
  local first={tool="station",first=q.depot+3,last=q.depot+5}
  local second={tool="station",first=q.last-4,last=q.last-2}
  for k,v in pairs(stock) do first[k],second[k]=v,v end
  build("rail",{tool="track",first=q.first,last=q.last,track=0},function()
    build("rail",{tool="depot",first=q.depot,direction=2},function()
      build("rail",first,function()
        build("rail",second,function()
          build("transport",{mode="rail",operation="buy",depot=q.depot,parts={0,27,28}},function(r)
            local train=r.value.id
            local state=assert(OwnerCheckpoint.read())
            local a,b=state.tiles[first.first].rail_station_id,state.tiles[second.first].rail_station_id
            commit({kind="transport_start",mode="rail",vehicle=train,first=b,second=a,cargo="mixed"},function() done(train) end)
          end)
        end)
      end)
    end)
  end)
end
local function route_center(p,w,g)
  p:set_pos({x=2*g.x+7,y=g.level+6,z=2*g.z-2})
  p:set_look_horizontal(.36);p:set_look_vertical(.17)
  w:set_pos({x=2*g.x+11,y=g.level+5,z=2*g.z-3})
  w:set_look_horizontal(0);w:set_look_vertical(.35)
end
local function nearby(anchor,type_,pred)
  if not anchor then return end
  for _,ref in ipairs(core.get_objects_inside_radius(anchor,32)) do
    local e=ref:get_luaentity()
    if e and (not type_ or e.name==type_) and (not pred or pred(e,ref)) then return ref end
  end
end
local function inspect(phase,mode,q,rider,witness,id,next_)
  route_center(rider,witness,q)
  local cabin="luanttd_core:ride_"..(phase=="bus" and "bus_interior" or phase=="cab" and "train_cab" or "train_interior")
  local exterior=function(e)
    local r=e.luanttd_vehicle
    if not r or r.kind~=mode or r.id~=id then return false end
    if mode=="road" then return true end
    return phase=="cab" and e.name=="luanttd_core:dispatch_steam" or phase~="cab" and e.name=="luanttd_core:dispatch_wagon"
  end
  wait_for(phase.." exterior",function() return nearby(rider:get_pos(),nil,exterior) end,function()
    -- Same preserved target as selecting/opening this specific real
    -- vehicle in its details. The native client runs the actual command.
    api.vehicle_ui.remember(rider,{kind=mode,id=id})
    local state
    local entry=api.vehicle_ui.ride_toggle
    api.vehicle_ui.ride_toggle=function(p,action,target)
      if p==rider and not api.vehicle_ui.riding(p) then
        state={pos=p:get_pos(),yaw=p:get_look_horizontal(),pitch=p:get_look_vertical(),
          inventory=p:get_inventory_formspec()}
      end
      local ok,why=entry(p,action,target)
      core.log("action","RIDE_REQUEST "..tostring(action).." "..tostring(ok).." "..tostring(why))
      return ok,why
    end
    assert(api.authority_handoff and authority.status()=="owned")
    local t=q.first
    local x,z=Sim.xy(t)
    assert(world.toggle_walk_at(rider,t,{x=x*2+.5,y=q.level+.5,z=z*2+.5}))
    local opened=false
    local show=core.show_formspec
    core.show_formspec=function(name,form,body)
      show(name,form,body)
      if name==rider_name and form=="luanttd_core:scenic_train_seat" then
        opened=true
        core.show_formspec=show
        core.log("action","RIDE_TRAIN_SEAT "..phase)
      end
    end
    local announced=false
    local function aim_to_board()
      if opened or api.vehicle_ui.riding(rider) then core.show_formspec=show;return end
      local ref=nearby(witness:get_pos(),nil,exterior)
      if ref then
        local at=ref:get_pos()
        local feet={x=at.x,y=q.level+.52,z=at.z-1.25}
        local eye=rider:get_properties().eye_height
        rider:set_look_horizontal(0)
        rider:set_look_vertical(math.atan2(feet.y+eye-at.y-.13,1.25))
        rider:set_pos(feet)
        local hit=api.vehicle_ui.pick(rider,4.5)
        if hit and hit.kind==mode and hit.id==id and not announced then
          announced=true;core.log("action","RIDE_READY "..phase)
        end
      end
      core.after(.18,aim_to_board)
    end
    core.after(.4,aim_to_board)
    wait_for(phase.." camera",function() return rider:get_attach() end,function(anchor)
      local inside,actual
      local function exists()
        inside=nearby(anchor:get_pos(),cabin)
        actual=nearby(anchor:get_pos(),nil,exterior)
        return inside and actual and api.vehicle_ui.riding(rider)
      end
      local function phase_ready()
        if not exists() then return end
        local original=inside:get_effective_observers()
        assert(original and original[rider_name] and not original[witness_name])
        local ex=actual:get_effective_observers()
        assert(ex and not ex[rider_name] and ex[witness_name])
        assert(invariant(rider,anchor) and inside:get_attach()==anchor,"cabin and seat must share a client transform")
        if mode=="rail" then
          local consist_bodies=0
          for _,peer in ipairs(core.get_objects_inside_radius(anchor:get_pos(),8)) do
            local entity=peer:get_luaentity()
            local pick=entity and entity.luanttd_vehicle
            if pick and pick.kind=="rail" and pick.id==id then
              local visible=peer:get_effective_observers()
              assert((not visible or visible[witness_name]) and (not visible or not not visible[rider_name])==(peer~=actual),
                "Only the occupied body should be hidden from the rider")
              consist_bodies=consist_bodies+1
            end
          end
          -- A sector can attach the cab before delivering the trailing
          -- coach. Wait for the complete projected consist, not a subset.
          if consist_bodies<3 then return end
        end
        return true
      end
      wait_for(phase.." complete private and witnessed vehicle",phase_ready,function()
      local inside_origin=inside:get_pos()
      local camera_origin=anchor:get_pos()
      assert(math.abs(inside_origin.x-camera_origin.x)<.45 and
        math.abs(inside_origin.y-camera_origin.y)<2 and math.abs(inside_origin.z-camera_origin.z)<.45)
      local start,yaw,pitch=anchor:get_pos(),rider:get_look_horizontal(),rider:get_look_vertical()
      core.log("action","RIDE_VISIBLE "..phase)
      wait_for(phase.." freelook and physical travel",function()
        if not invariant(rider,anchor) then error("Translation input broke seating") end
        local pos=anchor:get_pos()
        local change=math.abs((rider:get_look_horizontal()-yaw+math.pi)%(2*math.pi)-math.pi)
          +math.abs(rider:get_look_vertical()-pitch)
        return change>.16 and math.abs(pos.x-start.x)+math.abs(pos.z-start.z)>.10
      end,function()
        assert(exists())
        core.log("action","RIDE_SIDE_VIEW "..phase)
        local landing=world.finish_ride_landing
        local planned
        world.finish_ride_landing=function(p,at,...) planned=at;return landing(p,at,...) end
        wait_for(phase.." local disembark",function()
          if api.vehicle_ui.riding(rider) or not planned then return end
          local at=rider:get_pos()
          return math.abs(at.x-planned.x)+math.abs(at.z-planned.z)<.2 and math.abs(at.y-planned.y)<.20
        end,function()
          api.vehicle_ui.ride_toggle=entry
          world.finish_ride_landing=landing
          assert(not rider:get_attach() and not nearby(state.pos,cabin) and not anchor:get_pos())
          assert(rider:get_inventory_formspec():find("luanttd_scenic_exit",1,true))
          assert(world.avatar_state(rider).mode=="walk" and not rider:hud_get_flags().hotbar)
          assert(not actual:get_pos() or not actual:get_observers())
          core.log("action","PASS NATIVE PRIVATE RIDE "..phase)
          assert(world.exit_avatar(rider))
          core.after(.48,next_)
        end)
      end)
      end)
    end)
  end)
end
core.after(.2,function()
  wait_for("two builders",get_players,function(ps)
    local road=together(12)
    assert(road,"No ordinary flat road stretch")
    stock_bus(road,function(bus)
      inspect("bus","road",road,ps[1],ps[2],bus,function()
        local track=together(16)
        assert(track,"No ordinary flat rail stretch")
        stock_train(track,function(train)
          inspect("cab","rail",track,ps[1],ps[2],train,function()
            inspect("coach","rail",track,ps[1],ps[2],train,function()
              core.log("action","PASS NATIVE ALL SEATED MODES")
            end)
          end)
        end)
      end)
    end)
  end)
end)
