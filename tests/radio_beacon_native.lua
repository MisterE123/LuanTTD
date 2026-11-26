return function(api)
  local S,R,Sim=api.s,api.render,api.Sim
  local T=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.speed=0
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function()return 1 end).levels
  local dirty={}
  for z=8,16 do for x=7,17 do
    local id=Sim.id(x,z)
    S.tiles[id]={terrain="grass",h=1,variant=0}
    dirty[#dirty+1]=id
  end end
  local stock=Sim.id(9,12)
  S.tiles[stock].stock_landmark={kind="transmitter"}
  S.tiles[Sim.id(12,12)].airfield={airport=1,x=1,z=0,layout="country"}
  S.tiles[Sim.id(15,12)].airfield={airport=2,x=0,z=3,layout="city"}
  local pos={x=18.5,y=3.941,z=24.5}
  local function find(at)
    local found
    for _,ref in ipairs(core.get_objects_inside_radius(at,.025)) do
      local e=ref:get_luaentity()
      if e and e.name=="luanttd_core:radio_beacon" then
        assert(not found,"Duplicate beacon on one mast")
        found=ref
      end
    end
    return found
  end
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=13,y=-1,z=15},{x=34,y=8,z=32},function(_,_,left)
      if left~=0 then return end
      core.after(.4,function()
        R.update(dirty)
        p:set_pos({x=18.50,y=3.65,z=22.07})
        p:set_properties({eye_height=.10})
        p:set_physics_override({gravity=0,jump=0})
        p:set_look_horizontal(0)
        p:set_look_vertical(-.08)
        if api.cinematic and api.cinematic.active and not api.cinematic.active(p) then
          api.cinematic.toggle(p)
        end
        p:set_clouds({density=0})
        assert(core.get_node({x=18,y=2,z=24}).name=="luanttd_core:stock_transmitter")
        R.step_local_optics(.51,{p:get_pos()})
        local ref=assert(find(pos),"stock radio tower lens lacks its flash")
        assert(find({x=24.24,y=3.222,z=24.233}),"country airport missing its obstruction flash")
        assert(find({x=30.47,y=3.359,z=24.38}),"city airport missing its west tower flash")
        assert(not ref:get_properties().static_save and not ref:get_properties().pointable)
        local on,off=false,false
        core.log("action","RADIO_BEACON_NATIVE_READY")
        local function sample(i)
          assert(find(pos)==ref,"Flash keeps its ObjectRef between blinks")
          if ref:get_properties().is_visible then on=true else off=true end
          if i>0 then return core.after(.12,function() sample(i-1) end) end
          assert(on and off,"Nearby native obstruction light must blink")
          R.step_local_optics(.51,{{x=pos.x,y=pos.y+60,z=pos.z}})
          assert(not find(pos),"Elevation distance must cull tower light")
          R.step_local_optics(.51,{p:get_pos()})
          assert(find(pos),"Tower light must return after approaching")
          S.tiles[stock].stock_landmark=nil
          R.step_local_optics(.51,{p:get_pos()})
          assert(not find(pos),"Demolishing landmark must remove its light")
          core.log("action","RADIO_BEACON_NATIVE_PASS")
        end
        sample(47)
      end)
    end)
  end)
end
