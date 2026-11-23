return function(api)
  local S,Sim,R,W=api.s,api.Sim,api.render,api.world
  S.speed=0
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  local function id(x,z) return assert(Sim.id(x,z)) end
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x,z) return x>=13 and 1 or 0 end).levels
  for z=8,18 do for x=8,19 do
    S.tiles[id(x,z)]={terrain="grass",variant=(x+z)%4,h=x>=13 and 1 or 0}
  end end
  local owner="WalkQA"
  local ok,why=Sim.build(S,owner,"road",Sim.line(id(9,11),id(17,11)))
  assert(ok,why)
  local grade,base=Sim.road_surface(S,id(12,11))
  assert(grade==3 and base==0,"native walking fixture is not on an actual grade")
  local initial_visual
  local function check_hidden(properties)
    assert(properties.visual=="sprite" and properties.mesh==""
      and properties.textures[1]=="bl_sightseeing_hidden_player.png"
      and properties.visual_size.y<.01 and properties.eye_height>1,
      "builder body is visible or builder eye height was changed")
  end
  local function report(p,tag)
    local v=p:get_pos()
    local at=Sim.id(math.floor((v.x+.5)/2),math.floor((v.z+.5)/2))
    local mode=W.avatar_state(p)
    local flags=p:hud_get_flags()
    local properties=p:get_properties()
    if tag=="before" then
      initial_visual=properties
      check_hidden(properties)
    end
    if tag=="entered" then
      assert(math.abs(properties.eye_height-.26334)<.001 and properties.visual=="mesh"
        and math.abs(properties.visual_size.x-.57)<.001
        and math.abs(properties.visual_size.y-.57)<.001 and math.abs(properties.visual_size.z-.57)<.001,
        "street camera did not get the proper human-scale eyes and mesh")
      assert(properties.mesh=="bl_street_pedestrian.glb" and properties.textures[1]=="bl_street_pedestrian_atlas.png")
      local i,walk=p:get_local_animation()
      assert(i.x==0 and i.y==1 and walk.x==2 and walk.y==14)
      core.log("action",("WALK_AVATAR %.3f %s"):format(properties.eye_height,properties.mesh))
    elseif tag=="doorway" then
      local glasses=1.5+.05+.335*.69 -- from the original house model
      assert(math.abs(v.y+properties.eye_height-glasses)<.030,"eye above or below door glazing")
      assert(math.abs(p:get_look_vertical())<.02)
      core.log("action",("WALK_DOOR_EYE %.3f GLASS %.3f"):format(v.y+properties.eye_height,glasses))
    elseif tag=="returned" then
      check_hidden(properties)
      assert(properties.visual==initial_visual.visual and properties.mesh==initial_visual.mesh
        and properties.textures[1]==initial_visual.textures[1]
        and properties.eye_height==initial_visual.eye_height,"builder visual did not restore")
    end
    core.log("action",("WALK_QA %s %s %.3f %.3f %.3f %.4f %.4f %.3f %s %s %s"):format(
      tag,mode and mode.mode or "builder",v.x,v.y,v.z,p:get_look_horizontal(),p:get_look_vertical(),
      R.surface(at,v.x,v.z),tostring(flags.hotbar),tostring(W.menu(p)),tostring(S.topology)))
  end
  core.register_chatcommand("walkprobe",{func=function(name,tag)
    local p=assert(core.get_player_by_name(name))
    if tag=="doorway" then
      assert(W.avatar_state(p) and W.avatar_state(p).mode=="walk")
      p:set_look_vertical(0)
      p:set_pos({x=28.8,y=1.5,z=22.67})
    end
    report(p,tag)
    return true
  end})
  local elapsed=0
  core.register_globalstep(function(dt)
    elapsed=elapsed+dt
    if elapsed<.24 then return end
    elapsed=0
    local p=core.get_player_by_name(owner)
    if p and W.avatar_state(p) then report(p,"trace") end
  end)
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~=owner then return end
    core.emerge_area({x=15,y=-1,z=15},{x=37,y=5,z=36},function(_,_,left)
      if left~=0 then return end
      core.after(.3,function()
        local dirty={}
        for z=8,18 do for x=8,19 do dirty[#dirty+1]=id(x,z) end end
        R.update(dirty)
        assert(core.get_node({x=24,y=1,z=22}).name=="luanttd_core:road_grade_3")
        core.set_node({x=31,y=2,z=22},{name="luanttd_core:scenery_house_0",param2=3})
        W.go_menu(p,"roads") -- preserve a non-home section through the round trip
        p:set_look_horizontal(-math.pi/2);p:set_look_vertical(1.38)
        p:set_pos({x=20.5,y=5,z=22.67})
        report(p,"ready")
      end)
    end)
  end)
end
