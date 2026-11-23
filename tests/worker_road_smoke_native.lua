-- Native visual check. An RC1 scheduled fault starts and expires naturally;
-- the only test injection is the deterministic starting countdown.
local m=core.get_modpath(core.get_current_modname()).."/"
local project=dofile(m.."campaign_actor_projection.lua")
local motion=dofile(m.."road_motion.lua")
local K=dofile(m.."openttd/road_breakdowns.lua")
local renderer_engine=setmetatable({},{__index=core})
local emitted=0
function renderer_engine.add_particle(d)
  emitted=emitted+1
  return core.add_particle(d)
end
local renderer=dofile(m.."campaign_projected_actors.lua")(renderer_engine,{},motion,{bus="town_flyer"},{})
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.register_node("luanttd_core:ground",{tiles={"bl_vehicle_palette.png^[colorize:#64715E:255"},groups={cracky=1}})
core.register_entity("luanttd_core:vehicle_bus",{initial_properties={physical=false,pointable=false,
  static_save=false,visual="mesh",mesh="bl_town_flyer.obj",textures={"bl_vehicle_palette.png"},
  visual_size=dofile(m.."road_lanes.lua").visual_size("bus")}})
core.set_timeofday(.5)
core.register_on_joinplayer(function(p)
  p:set_properties({visual_size={x=0,y=0}})
  p:set_sky({type="plain",base_color="#738D9B",clouds=false})
  p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false,basic_debug=false})
  p:set_physics_override({speed=0,jump=0,gravity=0})
  p:set_pos({x=4,y=.52,z=-.5})
  p:set_look_horizontal(0)
  p:set_look_vertical(.19)
  core.emerge_area({x=-8,y=0,z=-8},{x=15,y=1,z=15},function(_,action,left)
    if left==0 then
      for x=-8,15 do for z=-8,15 do core.set_node({x=x,y=0,z=z},{name="luanttd_core:ground"}) end end
    end
  end)
  local state=K.new(50000,80,5475,0,0)
  local bus={engine="bus",road_fault=state,running=true}
  local sim={position=function() return 2 end,xy=function()return 2,2 end,
    road_motion_frame=function()return {0,0,0,0,0} end}
  local runtime={world={speed=1,fleet={[1]=bus}},
    road_pose=function()return {x=4,y=.60,z=4},math.pi/2,0 end}
  local phase="healthy"
  local function tick()
    if phase=="break" then
      K.tick(state,{cur_speed=14,front=true})
      if state.breakdown_ctr==0 then
        phase="recovered"
        assert(emitted>2)
        core.log("action","NATIVE ROAD SMOKE RECOVERED "..emitted)
        local done=emitted
        core.after(2.2,function()
          assert(emitted==done);phase="done";core.log("action","NATIVE ROAD SMOKE COMPLETE")
        end)
      end
    end
    local row=assert(project(sim,runtime,1,1,8,8,1)[1])
    renderer.render({[row.key]=row},.05)
    if phase~="done" then core.after(.05,tick) end
  end
  tick()
  core.after(1.7,function()core.log("action","NATIVE ROAD SMOKE HEALTHY") end)
  core.after(4.5,function()
    assert(emitted==0)
    state.breakdown_ctr,state.breakdown_delay=2,56
    phase="break"
    core.after(.6,function()assert(emitted>0);core.log("action","NATIVE ROAD SMOKE ACTIVE")end)
  end)
end)
