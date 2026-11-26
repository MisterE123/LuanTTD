-- Fixture appended to a disposable real Luanti campaign. It uses the
-- production painter plus the normal player avatar, not fake collision.
local function RailWalkQA()
  local S,Sim,R,W=api.s,api.Sim,api.render,api.world
  local T=dofile(mod.."/openttd/terrain.lua")
  local function id(x,z) return assert(Sim.id(x,z)) end
  S.speed=0
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x) return x>=13 and 2 or 1 end).levels
  local dirty={}
  for z=8,18 do for x=8,19 do
    local key=id(x,z)
    dirty[#dirty+1]=key
    local t={terrain="grass",variant=(x+z)%4,h=x>=13 and 2 or 1}
    S.tiles[key]=t
    if S.stock_farm_fields then S.stock_farm_fields[key]=nil end
  end end
  local function track(x,z,bits)
    local t=S.tiles[id(x,z)]
    t.rail_tracks,t.rail_type,t.owner=bits,0,"WalkQA"
  end
  for x=9,11 do track(x,10,1) end
  S.tiles[id(9,10)].rail_ground=4
  for x=10,15 do track(x,11,1) end
  track(14,13,8);track(15,13,4);track(15,12,8)
  S.tiles[id(15,15)].level_crossing={railtype=0,rail_axis=0,road_axis=1,top=2,foundation="none",phase="clear"}
  local p
  local owner="WalkQA"
  local case
  local locations={
    flat_across={20.5,19.84,0,10,10},
    flat_along={19.82,20.5,-math.pi/2,10,10},
    grade_along={23.18,22.5,-math.pi/2,11,11},
    grade_across={24.67,21.77,0,12,11},
    diagonal_along={29.59,26.41,-3*math.pi/4,15,13},
    diagonal_across={29.94,25.19,-math.pi/4,15,13},
    crossing={30.5,29.58,0,15,15},
    fence={18.5,19.45,0,9,10},
  }
  local function presence(pos,expected)
    local n=core.get_node(pos).name
    assert(n=="luanttd_core:"..expected,n.." is not "..expected)
    local d=assert(core.registered_nodes[n])
    assert(d.walkable and d.collision_box and d.collision_box.type=="fixed",expected.." is non-solid")
  end
  core.register_chatcommand("railwalkqa",{func=function(name,param)
    assert(name==owner)
    if param=="unchanged_fence" then
      local pos=p:get_pos()
      assert(pos.z<19.60,"walker went through the fence without jumping")
      core.log("action","RAIL_WALK_FENCE_STOPS_PLAYER")
      return true
    elseif param=="stop" then
      local v=p:get_pos()
      core.log("action",("RAIL_WALK_FINISH %s %.4f %.4f %.4f"):format(case,v.x,v.y,v.z))
      return true
    end
    local c=assert(locations[param],param)
    case=param
    local x,z,yaw,u,v=unpack(c)
    local uid=id(u,v)
    local floor=R.surface(uid,x,z)
    local entering=not W.avatar_state(p)
    if entering then
      assert(W.toggle_walk_at(p,uid,{x=x,y=floor,z=z}))
      assert(math.abs(p:get_pos().y-1.616)<.001,"Walk entered inside the straight ballast")
    end
    assert(W.avatar_state(p).mode=="walk")
    local velocity=p:get_velocity()
    p:add_velocity({x=-velocity.x,y=-velocity.y,z=-velocity.z})
    p:set_look_horizontal(yaw);p:set_look_vertical(.24)
    if not entering then p:set_pos({x=x,y=floor+.13,z=z}) end
    core.log("action",("RAIL_WALK_BEGIN %s %.4f %.4f %.4f"):format(case,x,floor,z))
    return true
  end})
  local elapsed=0
  core.register_globalstep(function(dt)
    if not (case and p and W.avatar_state(p)) then return end
    elapsed=elapsed+dt
    if elapsed<.15 then return end
    elapsed=0
    local v=p:get_pos()
    core.log("action",("RAIL_WALK_STEP %s %.4f %.4f %.4f"):format(case,v.x,v.y,v.z))
  end)
  core.register_on_joinplayer(function(player)
    if player:get_player_name()~=owner then return end
    p=player
    core.emerge_area({x=15,y=0,z=15},{x=40,y=7,z=39},function(_,_,left)
      if left~=0 then return end
      core.after(.3,function()
        R.update(dirty)
        presence({x=20,y=2,z=20},"stock_rail_1")
        presence({x=19,y=2,z=20},"rail_ground_fence_4_0")
        presence({x=24,y=3,z=22},"stock_rail_grade_1")
        presence({x=30,y=3,z=26},"rail_eased_4_3")
        presence({x=30,y=3,z=30},"level_crossing_0_open")
        p:set_pos({x=20.5,y=5,z=20.5})
        core.log("action","RAIL_WALK_READY")
      end)
    end)
  end)
end
RailWalkQA()
