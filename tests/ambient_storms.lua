local storm=dofile("mods/luanttd_core/ambient_storms.lua")
local step,leave,clouddef
local effects,objects={},{}
local function player(name,x)
  local p={name=name,visible=true,at={x=x,y=6,z=5},aim={x=1,y=.14,z=0}}
  function p:get_player_name() return self.name end
  function p:get_pos() return self.at end
  function p:get_look_dir() return self.aim end
  return p
end
local a,b=player("a",0),player("b",0)
local group={a,b}
local core={
  add_particle=function(d) effects[#effects+1]=d end,
  add_particlespawner=function(d) effects[#effects+1]=d end,
  register_globalstep=function(f) step=f end,
  register_on_leaveplayer=function(f) leave=f end,
  get_connected_players=function() return group end,
  get_player_by_name=function(n)
    for _,p in ipairs(group) do if p.name==n then return p end end
  end,
  register_entity=function(name,def) assert(name=="luanttd_core:voxel_cloud");clouddef=def end,
  add_entity=function(at,kind,name)
    assert(kind=="luanttd_core:voxel_cloud")
    local ref={at=at}
    function ref:get_pos() return self.at end
    function ref:remove() self.at=nil end
    function ref:set_observers(q) self.observers=q end
    function ref:set_properties(q)
      self.properties=self.properties or {}
      for k,v in pairs(q) do self.properties[k]=v end
    end
    function ref:move_to(q,continuous) assert(continuous);self.at=q end
    clouddef.on_activate({object=ref},name)
    objects[#objects+1]=ref
    return ref
  end,
}
storm.start(core,function(p) return p.visible end)
local prop=clouddef.initial_properties
assert(prop.visual=="mesh" and not prop.static_save and not prop.physical and not prop.pointable and not prop.collide_with_objects)
b.visible=false
step(59);assert(#effects==0 and #objects==0,"calm between showers")
for i=1,2 do step(1) end
local ref=assert(objects[1]);local x=ref.at.x
local feeder,anvil=objects[2],objects[4]
local feeder_y,width=feeder.at.y,anvil.properties.visual_size.x
assert(#objects==4 and ref.observers.a and not ref.observers.b)
assert(ref.properties.mesh=="bl_voxel_cloud_storm.obj")
a.aim={x=0,y=.2,z=1} -- once spawned, never turns with the camera
for i=1,10 do step(1) end
assert(#objects==4 and ref.at.x>x+4 and ref.at.x<x+7 and ref.at.z<16)
assert(feeder.at.y>feeder_y+3 and anvil.properties.visual_size.x>width)
local rainfall,bolt=0,0
for _,e in ipairs(effects) do
  assert(e.playername=="a" and e.collisiondetection==false)
  local n=e.texture.name
  if n:find("rain") then
    rainfall=rainfall+1
    assert(e.amount<=94 and e.minpos.x>=45 and e.maxvel.y<0 and e.maxexptime<=1)
  else
    assert(n:find("bolt") and e.expirationtime<=.7 and e.glow<14)
    bolt=bolt+1
  end
end
assert(rainfall>0 and rainfall<=12 and bolt==22,"no cloud billboards and one isolated strike")
effects={}
a.at.x=40
step(1);assert(#effects==0 and not ref.at,"cannot stay inside the approaching cloud")
a.at.x=0;a.visible=false
step(1);assert(#effects==0,"scenery opt-out remains individual")
b.visible=true
step(1);assert(#effects>0 and effects[1].playername=="b","other viewers still see weather")
local other=objects[5]
assert(other.observers.b and not other.observers.a)
effects={}
leave(b);group={a}
step(20);assert(#effects==0 and not other.at,"leave/cycle cleanup")
b.at.x=0
group={b};effects={}
step(230)
for i=1,12 do step(1) end
assert(#effects>0 and objects[9].properties.mesh=="bl_voxel_cloud_shower.obj")
for _,e in ipairs(effects) do assert(e.amount and e.amount<=44 and not e.texture.name:find("bolt")) end
effects={}
step(245)
for i=1,12 do step(1) end
assert(#effects==0 and not objects[9].at and objects[10].properties.mesh=="bl_voxel_cloud_wisp.obj")
b.visible=false
step(.25)
assert(not objects[10].at)
print("PASS private noncolliding voxel scenery, stable wind advection, radius, rain budget, isolated lightning and cleanup")
