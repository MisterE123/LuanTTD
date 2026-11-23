return function(api)
  local S,Sim,R,W=api.s,api.Sim,api.render,api.world
  S.speed=0
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  local function id(x,z) return assert(Sim.id(x,z)) end
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x,z) return x>=13 and 1 or 0 end).levels
  -- This replaced the whole corner grid, so do not leave old generated
  -- structures with foundations that refer to the original terrain.
  for z=1,Sim.H do for x=1,Sim.W do
    S.tiles[id(x,z)]={terrain="grass",variant=(x+z)%4,h=x>=13 and 1 or 0}
  end end
  local owner="CarQA"
  local ok,why=Sim.build(S,owner,"road",Sim.line(id(9,11),id(17,11)))
  assert(ok,why)
  local grade,base=Sim.road_surface(S,id(12,11))
  assert(grade==3 and base==0,"native walking fixture is not on an actual grade")
  local function report(p,tag)
    local car=p:get_attach()
    local v=car and car:get_pos() or p:get_pos()
    local at=Sim.id(math.floor((v.x+.5)/2),math.floor((v.z+.5)/2))
    local mode=W.avatar_state(p)
    if mode and mode.leaving then return end
    local flags=p:hud_get_flags()
    local graphics=p:get_properties()
    if mode and mode.mode=="car" then
      assert(car and graphics.visual_size.y<.01 and graphics.textures[1]=="bl_sightseeing_hidden_player.png",
        "driver billboard visible while attached")
    else
      assert(graphics.eye_height>1 and graphics.mesh=="" and graphics.visual=="sprite",
        "car exit did not restore the builder camera")
      assert(graphics.visual_size.y<.01 and graphics.textures[1]=="bl_sightseeing_hidden_player.png",
        "car exit did not restore the invisible builder")
    end
    core.log("action",("CAR_QA %s %s %.3f %.3f %.3f %.4f %.4f %.3f %s %s %s"):format(
      tag,mode and mode.mode or "builder",v.x,v.y,v.z,p:get_look_horizontal(),p:get_look_vertical(),
      R.surface(at,v.x,v.z),tostring(flags.hotbar),tostring(W.menu(p)),tostring(S.topology)))
  end
  core.register_chatcommand("carprobe",{func=function(name,tag)
    local p=assert(core.get_player_by_name(name))
    report(p,tag)
    return true
  end})
  local elapsed,total,previous=0,0,nil
  core.register_globalstep(function(dt)
    total=total+dt
    elapsed=elapsed+dt
    if elapsed<.24 then return end
    elapsed=0
    local p=core.get_player_by_name(owner)
    if p and W.avatar_state(p) then
      report(p,"trace")
      local car=p:get_attach()
      if car then
        local v=car:get_pos()
        if previous then
          core.log("action",("CAR_QA_SPEED %.3f"):format((v.x-previous[1])/(total-previous[2])))
        end
        previous={v.x,total}
      end
    else previous=nil end
  end)
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~=owner then return end
    core.emerge_area({x=15,y=-1,z=15},{x=37,y=5,z=36},function(_,_,left)
      if left~=0 then return end
      core.after(.3,function()
        local dirty={}
        -- This replaced the whole corner grid, so do not leave old generated
  -- structures with foundations that refer to the original terrain.
  for z=1,Sim.H do for x=1,Sim.W do dirty[#dirty+1]=id(x,z) end end
        R.update(dirty)
        assert(core.get_node({x=24,y=1,z=22}).name=="luanttd_core:road_grade_3")
        W.go_menu(p,"roads") -- preserve a non-home section through the round trip
        p:set_look_horizontal(-math.pi/2);p:set_look_vertical(1.38)
        p:set_pos({x=20.5,y=5,z=22.67})
        report(p,"ready")
      end)
    end)
  end)
end
