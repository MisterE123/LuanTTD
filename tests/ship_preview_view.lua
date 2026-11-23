-- Reproduce Luanti 5.18's ObjectRef still being present after its Lua
-- entity is gone, exactly where the old renderer dereferenced .name.
local created,definitions={},{}
core={register_entity=function(name,def) definitions[name]=def end}
local player={get_pos=function()return {x=5,y=5,z=5} end}
function core.get_connected_players() return {player} end
function core.add_entity(pos,name)
  local ref={pos=pos,entity={name=name}}
  function ref:get_pos()return self.pos end
  function ref:get_luaentity()return self.entity end
  function ref:remove()self.pos,self.entity=nil,nil end
  function ref:move_to(p) assert(self.pos);self.pos=p end
  function ref:set_rotation(r) assert(self.pos);self.rotation=r end
  created[#created+1]=ref
  return ref
end
local course={engine_id=206,paid_clock=9,first=1,second=2}
local S={speed=1}
local pose={x=5,y=.5,z=5}
local function get() return pose,0 end
local Run={current=function()return course end}
local api={s=S,Sim={ferry_paid_pose=get}}
local V=dofile("mods/luanttd_core/ship_preview_view.lua")(api,Run,{
  nose_yaw=function(d)return d end,turn=function(_,d)return d end},1)
local function step() V.step(.1,true,.5) end
step();assert(#created==1 and created[1].entity.name=="luanttd_core:stock_harbor_ferry")
-- The ObjectRef reports a position but get_luaentity() yields nil.
created[1].entity=nil
step()
assert(#created==2 and not created[1].pos and created[2].rotation.y==0)
-- Also cover a fully deactivated ObjectRef and rebinding to the late hull.
created[2].entity=nil;created[2].pos=nil
step()
assert(#created==3 and created[3].pos)
course.engine_id=207
step()
assert(#created==4 and created[4].entity.name=="luanttd_core:stock_ffp_passenger_ferry")
assert(definitions[created[4].entity.name].initial_properties.mesh=="bl_ffp_passenger_ferry.obj")
V.step(.1,false,.5);assert(not created[4].pos)
step();assert(#created==5 and created[5].pos)
assert(course.paid_clock==9 and course.first==1 and course.second==2)
print("PASS ferry ObjectRef can lose Lua entity without interrupting a paid voyage; both meshes recover")
