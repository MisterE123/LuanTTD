return function(api)
  local S,R,Sim=api.s,api.render,api.Sim
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.speed=0
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function()return 1 end).levels
  local dirty={}
  for z=8,15 do for x=7,15 do
    local id=Sim.id(x,z)
    local t={terrain="grass",h=1,variant=0}
    S.tiles[id]=t;dirty[#dirty+1]=id
    if x>=9 and x<13 and z>=11 and z<14 then
      t.airfield={airport=1,x=x-9,z=z-11,layout="country"}
    end
  end end
  local sock={x=17.718,y=2.411,z=23.815}
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=13,y=-1,z=15},{x=31,y=5,z=32},function(_,_,left)
      if left~=0 then return end
      core.after(.4,function()
        R.update(dirty)
        p:set_pos({x=17.96,y=2.50,z=21.93})
        p:set_properties({eye_height=.10})
        p:set_physics_override({gravity=0,jump=0})
        p:set_look_horizontal(-.08)
        p:set_look_vertical(.10)
        if api.cinematic and api.cinematic.active and not api.cinematic.active(p) then
          api.cinematic.toggle(p)
        end
        p:set_clouds({density=0})
        assert(core.get_node({x=18,y=2,z=24}).name=="luanttd_core:small_airport_0_1")
        R.step_local_optics(.31,{p:get_pos()})
        local function find()
          for _,ref in ipairs(core.get_objects_inside_radius(sock,.025)) do
            local ent=ref:get_luaentity()
            if ent and ent.name=="luanttd_core:airport_windsock" then return ref end
          end
        end
        local ref=assert(find(),"the painted airport mast must have its cloth at the swivel")
        local rows,rate=ref:get_animation()
        assert(rows.x==0 and rows.y==60 and rate>11 and ref:get_yaw()<0)
        local yaw=ref:get_yaw()
        core.log("action","WINDSOCK_NATIVE_READY")
        core.after(4.8,function()
          assert(find()==ref and math.abs(ref:get_yaw()-yaw)>.01,"same animated ObjectRef turns with the wind")
          S.tiles[Sim.id(9,12)].airfield=nil
          R.step_local_optics(.31,{p:get_pos()})
          assert(not find(),"cleared airport must remove the nonpersistent windsock")
          core.log("action","WINDSOCK_NATIVE_PASS")
        end)
      end)
    end)
  end)
end
