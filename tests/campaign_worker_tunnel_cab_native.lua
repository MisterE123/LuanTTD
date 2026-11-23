-- Native integration-only check: cabin follows authoritative paid train
-- into and out of real rendered tunnel, without leaving the seat.
local name="TunnelBoreQA"
local function wait_for(pred,callback,why,n)
  local value=pred()
  if value then callback(value)
  elseif (n or 0)<225 then core.after(.12,function() wait_for(pred,callback,why,(n or 0)+1) end)
  else error(why) end
end
local function ask(request,callback)
  request.player=name
  assert(authority.query(request,function(r)
    assert(r.ok,tostring(r.why).." ("..request.kind.." / "..tostring(request.request and request.request.tool)..")")
    callback(r)
  end))
end
local function build(domain,request,done)
  ask({kind=domain.."_quote",request=request},function(r)
    ask({kind="command",command={kind=domain.."_commit",revision=r.revision,request=request,token=r.value.token}},done)
  end)
end
local function commit(command,done)
  ask({kind="company"},function(r)
    command.revision=r.revision
    ask({kind="command",command=command},done)
  end)
end
local function run()
  wait_for(function()
    local p=core.get_player_by_name(name)
    return p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 and p
  end,function(p)
    local id=function(z) return Sim.id(65,z) end
    local function station(front,last)
      return {tool="station",first=id(front),last=id(last),kind="rail",axis=1,length=last-front+1,tracks=1}
    end
    p:set_pos({x=129,y=10,z=45});p:set_look_horizontal(0);p:set_look_vertical(.2)
    build("transport",{mode="rail",operation="tunnel",tile=id(26)},function()
      build("rail",{tool="track",first=id(17),last=id(25),track=1},function()
        build("rail",{tool="track",first=id(39),last=id(48),track=1},function()
          build("rail",{tool="depot",first=id(16),direction=1},function()
            build("rail",station(20,22),function()
              build("rail",station(43,45),function()
                build("transport",{mode="rail",operation="buy",depot=id(16),parts={0,27}},function(r)
                  local train=r.value.id
                  local w=assert(OwnerCheckpoint.read())
                  local a,b=w.tiles[id(20)].rail_station_id,w.tiles[id(43)].rail_station_id
                  commit({kind="transport_start",mode="rail",vehicle=train,first=b,second=a},function()
                    api.vehicle_ui.remember(p,{kind="rail",id=train})
                    wait_for(function()
                      for _,ref in ipairs(core.get_objects_inside_radius(p:get_pos(),32)) do
                        local e=ref:get_luaentity()
                        if e and e.name=="luanttd_core:dispatch_steam" and e.luanttd_vehicle and e.luanttd_vehicle.id==train then
                          return ref
                        end
                      end
                    end,function(locomotive)
                      core.log("action","TUNNEL_BORE_QA_BOARD")
                      local joined, why = core.registered_chatcommands.train.func(name, "")
                      assert(joined,tostring(why))
                      wait_for(function() return p:get_attach() end,function(anchor)
                        local forced_pause=core.settings:get_bool("luanttd_qa_tunnel_pause",false)
                        local function at()
                          assert(p:get_attach()==anchor and api.vehicle_ui.riding(p),"Cab ceased to track the paid train")
                          if not forced_pause then
                            assert(locomotive:get_pos(),"Paid locomotive projection blinked before the opposite portal")
                          end
                          return assert(anchor:get_pos())
                        end
                        wait_for(function() return at().z>=46 and at().z<52 end,function()
                          local first=at()
                          p:set_look_horizontal(0);p:set_look_vertical(.10)
                          core.log("action","TUNNEL_BORE_QA_APPROACH")
                          wait_for(function() return at().z>=60 and at().z<73 end,function()
                            local here=at()
                            local eye=here.y+p:get_properties().eye_height
                            assert(here.z-first.z>5 and eye>3.6 and eye<4.36 and math.abs(here.x-130.5)<.2,
                              "Cab moved at the wrong height: "..core.pos_to_string(here).." eye "..eye)
                            assert(core.get_node({x=130,y=4,z=math.floor(here.z+.5)}).name:find("_rail_"))
                            core.log("action","TUNNEL_BORE_QA_MOVING_CAB")
                            local function await_exit()
                              wait_for(function() return at().z>=78 end,function()
                                core.log("action","TUNNEL_BORE_QA_EXIT")
                                core.after(1.2,function() core.log("action","PASS NATIVE MOVING TRAIN CAB THROUGH BORES") end)
                              end,"Cab never came out the other real portal")
                            end
                            if not forced_pause then await_exit();return end
                            -- Drop just the engine's presentation stream,
                            -- not the running owner or its route. Force a
                            -- real native ObjectRef removal and resume.
                            local draw=api.render.step_worker_actors
                            api.render.step_worker_actors=function() end
                            locomotive:remove()
                            core.after(1.65,function()
                              local frozen=at()
                              assert(math.abs(here.z-frozen.z)<.07,"Lost-actor grace must not extrapolate through terrain")
                              api.render.step_worker_actors=draw
                              core.log("action","TUNNEL_BORE_QA_HOLD_RECOVERY")
                              await_exit()
                            end)
                          end,"Cab never entered the rail tunnel")
                        end,"Cab was not boarded before tunnel approach")
                      end,"Luanti never seated the native player through /train")
                    end,"Paid train exterior missing before approach")
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end,"ordinary worker startup")
end
core.after(.2,run)
