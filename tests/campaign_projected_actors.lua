local mod="mods/luanttd_core/"
local live={}
local n=0
local engine={add_entity=function(pos,name)
  n=n+1
  local ref={name=name,pos=pos}
  live[n]=ref
  function ref:get_pos() return self.pos end
  function ref:remove() self.pos=nil end
  function ref:move_to(p) self.pos=p end
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
local lamps={["8:0"]={model="light_red",pos={x=8,y=3,z=4},rotation={x=0,y=1,z=0}}}
A.render(rows,.5,lamps)
local mast=live[n]
assert(mast.name=="luanttd_core:dispatch_signal_light_red")
lamps["8:0"].model="light_green";A.render(rows,.5,lamps)
assert(not mast.pos and live[n].name=="luanttd_core:dispatch_signal_light_green" and ref.pos)
A.render({},.5)
assert(not live[n].pos)
print("PASS projected rail aspects switch models and cull independently of rolling stock")
