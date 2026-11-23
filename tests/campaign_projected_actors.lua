local mod="mods/luanttd_core/"
local live={}
local n=0
local engine={add_entity=function(pos,name)
  n=n+1
  local ref={name=name,pos=pos}
  live[n]=ref
  function ref:get_pos() return self.pos end
  function ref:remove() self.pos=nil end
  function ref:move_to(p) self.pos=p;self.snapped=false end
  function ref:set_pos(p) self.pos=p;self.snapped=true end
  function ref:set_rotation(r) self.rotation=r end
  function ref:set_properties(p) self.mesh=p.mesh end
  return ref
end}
local A=dofile(mod.."campaign_projected_actors.lua")(engine,{},dofile(mod.."road_motion.lua"),
  {bus="town_flyer",wood_truck="witcombe_wood_truck"},{[215]=dofile(mod.."airport_airframe_art.lua").sampson})
local rows={["road:1"]={mode="road",id=1,engine="bus",pos={x=1,y=2,z=3},yaw=0},
  ["ship:ferry"]={mode="ship",id="ferry",engine=206,pos={x=4,y=2,z=3},dir=1},
  ["air:1"]={mode="air",id=1,engine=215,pos={x=6,y=2,z=3},dir=2,airborne=true}}
A.render(rows,.5)
assert(n==3)
rows["road:1"].pos={x=2,y=2,z=3}
A.render(rows,.5);assert(n==3)
A.render({},.5)
for _,ref in ipairs(live) do assert(not ref.pos) end
A.render(rows,.5);assert(n==6)
local expected={["luanttd_core:vehicle_bus"]=true,["luanttd_core:stock_harbor_ferry"]=true,
  ["luanttd_core:stock_bayshore_trimotor"]=true}
for i=4,6 do assert(expected[live[i].name] and live[i].rotation) end
print("PASS projected existing models spawn, move, despawn and reenter without any controller")
rows={["rail:5"]={mode="rail",id=5,parts={
  {body_index=1,index=1,kind="steam",pos={x=8,y=3,z=3},rotation={x=0,y=1,z=0},flip=false},
  {body_index=2,index=2,kind="wagon",pos={x=7,y=3,z=3},rotation={x=0,y=1,z=0},flip=false},
}}}
A.render(rows,.5)
local ref=live[7]
function ref:set_pos(p) self.pos=p;self.snapped=true end
rows["rail:5"].parts[1].flip=true
A.render(rows,.5)
assert(ref.snapped and ref.name=="luanttd_core:dispatch_steam")
print("PASS projected train keeps the original locomotive and wagon identity at a reversal")
local parts=rows["rail:5"].parts
parts[1].pos={x=9,y=3,z=3};parts[2].pos={x=8,y=3,z=3}
A.render(rows,.5)
assert(not live[7].snapped and not live[8].snapped,"Connected moving train should interpolate")
parts[1].pos={x=10,y=3,z=3};parts[2].pos={x=9,y=3,z=3}
parts[3]={body_index=3,index=3,kind="sh_125",pos={x=8,y=3,z=3},rotation={x=0,y=1,z=0},flip=false}
A.render(rows,.5)
assert(live[7].snapped and live[8].snapped and live[9].snapped,"Snap all bodies when the rear becomes visible")
parts[1].flip=false
A.render(rows,.5)
assert(live[7].snapped and live[8].snapped and live[9].snapped,"Snap all bodies together on a reversal")
print("PASS rail engine, coaches and linked rear snap together after changes without discarding normal interpolation")

local lamps={["8:0"]={model="light_red",pos={x=8,y=3,z=4},rotation={x=0,y=1,z=0}}}
A.render(rows,.5,lamps)
local mast=live[n]
assert(mast.name=="luanttd_core:dispatch_signal_light_red")
lamps["8:0"].model="light_green";A.render(rows,.5,lamps)
assert(not mast.pos and live[n].name=="luanttd_core:dispatch_signal_light_green" and ref.pos)
A.render({},.5)
assert(not live[n].pos)
print("PASS projected rail aspects switch models and cull independently of rolling stock")

-- Run the timestamped playout regression with the existing CI render checks.
dofile("tests/campaign_actor_buffer.lua")

-- Run a real RC1 road failure through the worker packet boundary and the
-- regular projected renderer. Recovery/occlusion cannot leave a smoke emitter.
local K=dofile(mod.."openttd/road_breakdowns.lua")
local project=dofile(mod.."campaign_actor_projection.lua")
local fault=K.new(50000,80,5475,0,0)
fault.breakdown_ctr,fault.breakdown_delay=2,130
local vehicle={engine="bus",road_fault=fault,running=true,road_speed_state={}}
local sim={position=function() return 12 end,xy=function()return 2,2 end,
  road_motion_frame=function()return {0,0,0,0,0} end}
local world={speed=1,fleet={[7]=vehicle}}
local under_cover=false
local view={world=world,road_pose=function()return {x=4,y=1,z=4},0,0,under_cover end}
local particles={}
local function player(n,x)
  return {get_player_name=function()return n end,get_pos=function()return {x=x,y=1,z=4} end}
end
engine.get_connected_players=function()return {player("near",4),player("distant",80)} end
engine.add_particle=function(p)particles[#particles+1]=p end
local visual=dofile(mod.."campaign_projected_actors.lua")(engine,{},dofile(mod.."road_motion.lua"),{bus="town_flyer"},{})
local function frame(dt)
  local r=assert(project(sim,view,1,1,8,8,1)[1])
  visual.render({[r.key]=r},dt or .05)
  assert(not r.road_fault and not r.breakdown_delay)
  return r.breakdown_smoke
end
assert(not frame() and #particles==0,"scheduled but not broken down")
assert(K.tick(fault,{cur_speed=15,front=true}).started)
assert(frame() and #particles==1 and particles[1].playername=="near")
assert(frame(.1) and #particles==1,"throttle")
vehicle.road_speed_state.depot_wait=true
assert(not frame(.4) and #particles==1)
vehicle.road_speed_state.depot_wait=nil
world.speed=0
assert(not frame(.4) and #particles==1)
world.speed=1
under_cover=true
assert(not frame(.4) and #particles==1,"a visible native tunnel must not change stock smoke guards")
under_cover=false
vehicle.crashed=true
assert(not frame(.4) and #particles==1)
vehicle.crashed=nil
assert(frame() and #particles==2)
visual.render({},.07)
assert(frame() and #particles==3,"viewport reentry must not inherit old delay")
while fault.breakdown_ctr~=0 do K.tick(fault,{cur_speed=0,front=true}) end
assert(not frame(.8) and #particles==3,"no new particles after stock recovery")
print("PASS real stock road fault projects viewer-local smoke and clears it on recovery, pause, depot and cull")
local tracked,auxiliary=0,0
local project_gear=dofile(mod.."campaign_projected_actors.lua")(engine,{vehicle_ui={
  track=function()tracked=tracked+1 end,
  ride_track=function(_,_,_,_,_,part)
    if part.auxiliary then auxiliary=auxiliary+1 end
  end,
}},dofile(mod.."road_motion.lua"),{}, {})
local before=n
local mono={mode="rail",id=7,parts={{
  body_index=1,index=1,kind="x2001",pos={x=8,y=2,z=2},
  rotation={x=0,y=1,z=0},flip=false,bogies={
    {pos={x=8.259,y=2,z=2},rotation={x=0,y=.9,z=0}},
    {pos={x=7.754,y=2,z=2},rotation={x=0,y=1.1,z=0}},
  },
}}}
project_gear.render({["rail:7"]=mono},.05)
assert(n==before+3 and tracked==1 and auxiliary==2)
assert(live[before+1].name=="luanttd_core:dispatch_x2001_body")
assert(live[before+2].name=="luanttd_core:dispatch_mono_bogie" and live[before+2].rotation.y==.9)
assert(live[before+3].name=="luanttd_core:dispatch_mono_bogie" and live[before+3].rotation.y==1.1)
mono.parts[1].flip=true
project_gear.render({["rail:7"]=mono},.05)
for j=1,3 do assert(live[before+j].snapped) end
project_gear.render({},.05)
for j=1,3 do assert(not live[before+j]:get_pos()) end
print("PASS projected monorail articulated body and gears appear, snap and cull together; only body is selectable")
