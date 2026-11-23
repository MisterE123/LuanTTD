-- Appended only to a disposable copy of the real campaign game.
return function(api)
  local S,Sim,R,W=api.s,api.Sim,api.render,api.world
  local name="PilotQA"
  S.speed=0
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function() return 0 end).levels
  local function id(x,z) return assert(Sim.id(x,z)) end
  local safe={}
  for z=1,Sim.H do for x=1,Sim.W do
    local k=id(x,z)
    S.tiles[k]={terrain="grass",variant=(x+z)%4,h=0}
    if z<=33 and x<=35 then safe[#safe+1]=k end
  end end
  local country=assert(api.airfield.network.build(S,name,id(17,10),"country"))
  local city=assert(api.airfield.network.build(S,name,id(23,22),"city"))
  local cash,topology=Sim.company(S,name).cash,S.topology
  local flags={country.flags,city.flags}
  local prior,tag,ready
  local loops,fades,touchdowns={},0,0
  local flight,before_landing
  core.luanttd_qa_flight=function(q) flight=q end
  local play,fade,stop=core.sound_play,core.sound_fade,core.sound_stop
  core.sound_play=function(asset,params,...)
    local handle=play(asset,params,...)
    if type(asset)=="string" and asset:find("^bl_plane_") then
      assert(params.to_player==name)
      if params.loop and handle then loops[handle]=asset end
      if asset=="bl_plane_touchdown" then touchdowns=touchdowns+1 end
    end
    return handle
  end
  core.sound_fade=function(handle,...)
    if loops[handle] then fades=fades+1 end
    return fade(handle,...)
  end
  core.sound_stop=function(handle,...)
    loops[handle]=nil
    return stop(handle,...)
  end
  local function point(p,which)
    local x,z=which=="city" and 24 or which=="miss" and 15 or 18,which=="city" and 27 or 12
    p:set_pos({x=2*x+.50,y=11,z=2*z+.00})
    p:set_look_horizontal(.02);p:set_look_vertical(1.533)
    W.go_menu(p,"navigation")
    prior={pos=p:get_pos(),yaw=p:get_look_horizontal(),pitch=p:get_look_vertical()}
    tag=which
  end
  local function verify(p,phase)
    local av=W.avatar_state(p)
    local attached=p:get_attach()
    local n=p:get_player_name()
    local q=(attached or p):get_pos()
    local r=attached and attached:get_rotation()
    assert(S.companies[n].cash==cash and S.topology==topology and country.flags==flags[1] and city.flags==flags[2])
    if phase=="start" then
      assert(W.target(p) and not av and not attached)
    elseif phase=="takeoff" or phase=="bank" or phase=="board" or phase=="reset" or phase=="landed" then
      assert(av and av.mode=="plane" and attached and not p:hud_get_flags().hotbar)
      assert(attached:get_luaentity().name=="luanttd_core:sightseeing_plane_cockpit")
      assert(attached:get_properties().mesh=="bl_sightseeing_plane_cockpit.obj")
      assert(attached:get_effective_observers()[n],"Pilot cannot see the cockpit mesh")
      local found
      for _,obj in ipairs(core.get_objects_inside_radius(q,2)) do
        local e=obj:get_luaentity()
        if e and e.name=="luanttd_core:sightseeing_plane" then
          found=true
          local body=obj:get_pos()
          assert(vector.distance(q,body)>.40 and vector.distance(q,body)<.58,"Eye anchor is not inside the plane")
          q=body
          assert(not obj:get_observers()[n],"An opaque exterior hid the pilot's windows")
          assert(obj:get_properties().mesh=="bl_bayshore_trimotor.obj")
        end
      end
      assert(found,"No stock exterior aircraft")
      if phase=="board" or phase=="reset" or phase=="landed" then
        assert(math.abs(q.y-.52)<.03,("Not on gear datum: x=%.3f y=%.3f z=%.3f mode=%s speed=%.3f pitch=%.3f"):
          format(q.x,q.y,q.z,flight.mode,flight.speed,flight.pitch))
      end
      if phase=="landed" then
        assert(flight.mode=="ready" and flight.speed<.01 and touchdowns==before_landing+1,
          ("Manual landing/one touchdown sound failed (%s at %.2f, sounds %d→%d)"):
            format(flight.mode,flight.speed,before_landing,touchdowns))
      end
      if phase=="takeoff" then assert(q.y>1.35,("Failed to lift off %g"):format(q.y)) end
      if phase=="bank" then assert(math.abs(r.z)>.15,("Not banking %g"):format(r.z)) end
    elseif phase=="returned" then
      assert(next(loops)==nil,"Plane sound survived cockpit teardown")
      if tag~="miss" then assert(fades>=1,"Flight audio never reacted to speed/power") end
      assert(not av and not attached and p:hud_get_flags().hotbar and W.menu(p)=="navigation")
      local d=vector.distance(p:get_pos(),prior.pos)
      assert(d<.14 and math.abs(p:get_look_horizontal()-prior.yaw)<.04 and math.abs(p:get_look_vertical()-prior.pitch)<.04,
        "The native player did not recover the pre-flight builder pose")
      assert(p:get_physics_override().speed==1 and p:get_properties().eye_height>1)
    end
    core.log("action",("PLANE_QA %s %s %.3f %.3f %.3f %.3f"):
      format(tag or "?",phase,q.x,q.y,q.z,r and r.z or 0))
  end
  local rec
  core.register_globalstep(function()
    local p=core.get_player_by_name(name)
    local ref=p and p:get_attach()
    if tag=="country" and not rec and ref and p:get_player_control().right then
      if math.abs(ref:get_rotation().z)>.15 then rec=true;verify(p,"bank") end
    end
  end)
  core.register_chatcommand("planetrace",{func=function(n,command)
    local p=assert(core.get_player_by_name(n))
    if command=="city" or command=="country" or command=="miss" then
      point(p,command)
      core.after(.2,function() verify(p,"start") end)
    elseif command=="short_final" then
      -- Test-only initial conditions before touching down. Native Shift
      -- still controls the descent; production validates the real
      -- runway and executes the landing, brake roll and audio cue.
      assert(W.avatar_state(p).mode=="plane" and flight.mode=="ready")
      local r=flight.runway
      flight.pos={x=r.x+r.dx*.25,y=r.y+.25,z=r.z+r.dz*.25+.08}
      flight.heading,flight.pitch,flight.bank=r.heading,-.06,0
      flight.throttle,flight.speed,flight.mode=.26,4.6,"air"
      before_landing=touchdowns
      core.log("action",("PLANE_QA %s short final"):format(tag))
    else
      verify(p,command)
    end
    return true
  end})
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~=name or ready then return end
    ready=true
    core.emerge_area({x=13,y=-1,z=10},{x=70,y=15,z=74},function(_,_,left)
      if left~=0 then return end
      core.after(.3,function()
        R.update(safe)
        assert(core.get_node({x=36,y=1,z=24}).name:find("small_airport",1,true))
        assert(core.get_node({x=48,y=1,z=54}).name:find("city_airport",1,true))
        point(p,"miss")
        core.log("action","PLANE_QA READY")
      end)
    end)
  end)
end
