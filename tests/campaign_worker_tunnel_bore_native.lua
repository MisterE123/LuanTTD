-- Ordinary worker-built tunnels and physical Luanti navigation.
local function bore_native()
  local player="TunnelBoreQA"
  local p=core.get_player_by_name(player)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,bore_native);return
  end
  local base=3
  local function ask(message,ready)
    message.player=player
    assert(authority.query(message,function(result)
      assert(result.ok,result.why);ready(result)
    end))
  end
  local function pose(x,y,z,yaw,pitch)
    p:set_pos({x=x,y=y,z=z});p:set_look_horizontal(yaw);p:set_look_vertical(pitch)
  end
  local function wait_for(predicate,then_,why,n)
    if predicate() then then_()
    elseif n<85 then core.after(.15,function() wait_for(predicate,then_,why,n+1) end)
    else error(why) end
  end
  local function construct(mode,id,ready)
    ask({kind="transport_quote",request={mode=mode,operation="tunnel",tile=id}},function(q)
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},ready)
    end)
  end
  local function demolish(which,id,ready)
    ask({kind="demolition",tile=id},function(q)
      local found=false
      for _,v in ipairs(q.value.options) do if v.key==which and v.ok then found=true end end
      assert(found,"The established layer removal tool did not see the bore")
      ask({kind="command",command={kind="demolition",token=q.value.token,revision=q.revision,layer=which}},ready)
    end)
  end
  local stock=function(pos) return core.get_node(pos).name end
  local roadroof={x=64,y=base+1,z=40}
  local railroof={x=130,y=base+1,z=64}
  local baseline=core.settings:get_bool("luanttd_qa_bore_baseline",false)
  local function cleared(end_,mode)
    local n=stock(end_)
    return baseline and not n:find("tunnel_bore",1,true) and n~="air" and n~="ignore" or
      n:find("tunnel_bore_",1,true) and
      n:find("_"..mode.."_",1,true)
  end
  local function collision_gap(pos,axis)
    local boxes=core.get_node_boxes("collision_box",pos)
    assert(#boxes>1,"Bore remained a solid voxel")
    -- The tunnel side must accept a small real body at y=bottom+.35,
    -- while keeping the original top and the solid terrain outside.
    local lateral=axis==0 and 3 or 1
    for _,b in ipairs(boxes) do
      assert(not (b[lateral]<.342 and b[lateral+3]>.342 and b[2]<-.15 and b[5]>-.15),
        "Collision still fills the bore")
    end
    assert(boxes[1][2]==-.5 and boxes[1][5]==.5)
  end
  -- Compare the actual completed house node, including its orientation,
  -- before and after tunnelling. Stock art can supersede the generic
  -- scenery house; an unpainted/air/cover node is never a valid baseline.
  local completed_house
  local function house_at()
    for z=40,41 do for x=68,69 do
      local pos={x=x,y=base+2,z=z}
      local node=core.get_node(pos)
      if node.name:find("^luanttd_core:scenery_house_%d$") or
          node.name:find("^luanttd_core:town_stock_1a$") or node.name:find("^luanttd_core:town_stock_1a_%d$") then
        return {pos=pos,node=node}
      end
    end end
  end
  local function check_house()
    local at=house_at()
    assert(at and vector.equals(at.pos,completed_house.pos) and at.node.name==completed_house.node.name
      and at.node.param2==completed_house.node.param2,"House on the ridge was overwritten or moved")
  end
  local function rail_and_demolition()
    pose(130.5,base+3,59,0,0)
    wait_for(function() return cleared(railroof,"rail") end,function()
      if not baseline then
        collision_gap(railroof,1)
        assert(stock({x=130,y=base,z=64}):find("tunnel_floor_rail_1_0",1,true))
        assert(stock({x=130,y=base+2,z=64}):find("stock_rail_1",1,true),
          "Surface railway was overwritten by an underground rail")
      end
      -- Street-height native eye inside the unoccupied rail barrel.
      core.after(1.35,function()
        p:set_properties({eye_height=.48,collisionbox={-.064,0,-.064,.064,.32,.064}})
        pose(130.5,base+.52,60.75,0,0)
        core.after(.9,function()
          local at=p:get_pos()
          assert(baseline or math.abs(at.x-130.5)<.10 and math.abs(at.y-(base+.52))<.17 and math.abs(at.z-60.75)<.10,
            "Native collision ejected the camera from a nominally open rail bore")
          core.log("action","TUNNEL_BORE_QA_RAIL_INSIDE")
        end)
        core.after(3.8,function()
          pose(128,base+7,67,3.11,.85)
          core.log("action","TUNNEL_BORE_QA_SURFACE")
          core.after(2.8,function()
          demolish("rail_tunnel",Sim.id(65,32),function()
            wait_for(function() return stock(railroof)=="luanttd_core:grass2" end,function()
              assert(stock({x=130,y=base+2,z=64}):find("stock_rail_1",1,true))
              pose(65,base+6,42,3.14,.8)
              demolish("road_tunnel",Sim.id(32,20),function()
                wait_for(function() return stock(roadroof):find("^luanttd_core:road_5_plain") end,function()
                  local live=assert(OwnerCheckpoint.read())
                  assert(not next(live.tunnel_below or {}) and not next(live.rail_tunnel_below or {}))
                  assert(live.tiles[Sim.id(32,20)].road_bits==5 and live.tiles[Sim.id(34,20)].house)
                  assert(live.tiles[Sim.id(65,32)].rail_tracks==1)
                  check_house()
                  core.log("action","PASS NATIVE TUNNEL BORES: real road ride, rail bore, two axes and demolition restoring intact surface")
                end,"Road roof pavement was not restored after removal",1)
              end)
            end,"Rail cover did not refill after removal",1)
          end)
          end)
        end)
      end)
    end,"Rail bore did not reach its native node layer",1)
  end
  pose(58,base+5,42,3*math.pi/2,.4)
  wait_for(house_at,function()
    completed_house=assert(house_at())
    construct("road",Sim.id(26,20),function()
    construct("rail",Sim.id(65,26),function()
      pose(49,base+2,43,-math.pi/2,.37)
      wait_for(function() return cleared(roadroof,"road") end,function()
        if not baseline then
          collision_gap(roadroof,0)
          assert(stock({x=64,y=base,z=40}):find("tunnel_floor_road_0_0",1,true))
          check_house()
        end
        core.log("action","TUNNEL_BORE_QA_OUTSIDE")
        core.after(2.8,function()
          pose(48.5,base+.55,40.5,3*math.pi/2,0)
          assert(api.car.toggle(p))
          local attached=assert(p:get_attach())
          core.log("action","TUNNEL_BORE_QA_CAR_READY")
          wait_for(function()
            local pos=attached:get_pos()
            return pos and pos.x>61 and pos.x<70 and math.abs(pos.y-(base+.52))<.05
          end,function()
            core.log("action","TUNNEL_BORE_QA_CAR_INSIDE")
            wait_for(function() return attached:get_pos() and attached:get_pos().x>77 end,function()
              assert(api.car.toggle(p))
              core.log("action","TUNNEL_BORE_QA_CAR_EXITED")
              rail_and_demolition()
            end,"Sightseeing car could not exit the rebuilt bore",1)
          end,"Sightseeing car did not enter the actual underpass",1)
        end)
      end,"Road bore did not reach its native node layer",1)
    end)
    end)
  end,"Completed stock house did not paint before tunnel construction",1)
end
core.after(.2,bore_native)
