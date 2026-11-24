return function(api)
  local S,R,Sim,W=api.s,api.render,api.Sim,api.world
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.speed=0
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function()return 1 end).levels
  local dirty={}
  for z=8,24 do for x=8,24 do
    local id=Sim.id(x,z)
    local t={terrain="grass",h=1,variant=0}
    S.tiles[id]=t;dirty[#dirty+1]=id
    for j,f in ipairs({{9,11,4,3,"country"},{15,14,6,6,"city"}}) do
      if x>=f[1] and z>=f[2] and x<f[1]+f[3] and z<f[2]+f[4] then
        t.airfield={airport=j,x=x-f[1],z=z-f[2],layout=f[5]}
      end
    end
  end end
  local viewpoints={
    country={x=24.945,y=1.51,z=24.53,tile=Sim.id(12,11),airport=1},
    city={x=40.945,y=1.51,z=30.53,tile=Sim.id(20,14),airport=2},
  }
  local function see(p,name,shot)
    local camera=viewpoints[name]
    p:set_properties({eye_height=.263})
    p:set_physics_override({gravity=0,jump=0})
    p:set_pos(camera);p:set_look_horizontal(math.pi);p:set_look_vertical(.07)
    if shot then
      core.after(.18,function()
        local id,a=R.pick_sightseeing_hangar(p)
        assert(id==camera.tile and a==camera.airport,"must identify the loaded displayed plane")
        local airfield=S.tiles[id].airfield
        local x,z=Sim.xy(id)
        assert(core.get_node({x=x*2+1,y=2,z=z*2}).name=="luanttd_core:airport_hangar_ga")
        assert(airfield.airport==a and not R.host_record("stock_small_airports",a),"no company aircraft created")
        core.log("action","PASS GA SCREEN "..name)
      end)
    end
  end
  core.register_chatcommand("gaview",{func=function(n,param)
    local p=assert(core.get_player_by_name(n))
    if viewpoints[param] then see(p,param,true);return true end
    if param=="city-walk" then
      assert(not W.avatar_state(p))
      p:set_pos({x=42.42,y=5,z=29.91})
      p:set_look_horizontal(math.pi/2);p:set_look_vertical(1.567)
      return true
    end
    if param=="walkcheck" then
      assert(W.avatar_state(p) and W.avatar_state(p).mode=="walk")
      assert(p:get_pos().x<41.62 and p:get_pos().x>40.56,
        "native W must reach the hangar from the plot east; x="..p:get_pos().x)
      local foot=p:get_pos()
      local dx,dz=40.945-foot.x,28.68-foot.z
      local dy=1.66-foot.y-p:get_properties().eye_height
      p:set_look_horizontal(math.atan2(-dx,dz))
      p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
      core.after(.2,function()
        local id,a=R.pick_sightseeing_hangar(p)
        assert(id==viewpoints.city.tile and a==2,"Walk ray missed: "..core.pos_to_string(p:get_pos()).." "..core.pos_to_string(p:get_look_dir()))
        core.log("action","PASS GA WALK APPROACH")
      end)
      return true
    end
  end})
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=14,y=-1,z=14},{x=50,y=5,z=50},function(_,_,left)
      if left~=0 then return end
      core.after(.4,function()
        R.update(dirty)
        p:set_clouds({density=0})
        see(p,"country",false)
        core.log("action","GA_QA ready")
      end)
    end)
  end)
end
