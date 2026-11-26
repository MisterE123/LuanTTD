local dir="mods/luanttd_core/"
local Field=dofile(dir.."ambient_weather_field.lua")
local storm=dofile(dir.."ambient_storms.lua")
local step,leave,clouddef
local effects,objects={},{}
local function player(name)
  local p={name=name,visible=true,at={x=0,y=6,z=5}}
  function p:get_player_name() return self.name end
  function p:get_pos() return self.at end
  return p
end
local a,b=player("builder"),player("spectator")
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
    local ref={at=at,name=name}
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
local function check_lifecycle(kind)
  local a,g,r,m=Field.lifecycle(0,kind)
  assert(a==0 and g==0 and r==0 and m==0)
  local dry,gd,rd=Field.lifecycle(30,kind)
  assert(dry>.99 and gd==0 and rd==0)
  local cloud,growth,rain,mist=Field.lifecycle(82,kind)
  assert(cloud==1)
  if kind=="storm" then assert(growth==1 and rain==1)
  elseif kind=="shower" then assert(growth==0 and rain>.5 and rain<.6)
  elseif kind=="mist" then assert(growth==0 and rain==0 and mist>.5)
  else assert(growth==0 and rain==0) end
  local late,gl,rl=Field.lifecycle(150,kind)
  assert(late==1 and gl==0 and rl==0,"A storm must weaken back into a dry cloud before dispersing")
  assert(Field.lifecycle(183,kind)==0)
end
for _,k in ipairs({"cloud","mist","shower","storm"}) do check_lifecycle(k) end
local c1=Field.cells(40,72,92,nil,825)
local c2=Field.cells(46,73,93,nil,825)
local found=false
for _,x in ipairs(c1) do for _,y in ipairs(c2) do
  if x.key==y.key then
    assert(y.x>x.x+.5 and y.x<x.x+1 and y.z>x.z and y.time==x.time+1)
    found=true
  end
end end
assert(found)
local px,pz,visibility=Field.builder_avoid(0,0,{x=0,z=0},false,1,.5)
assert(px==0 and pz==0 and visibility==1)
px,pz,visibility=Field.builder_avoid(0,0,{x=0,z=0},true,1,.5)
assert(px>0 and pz>0 and visibility<.1)

local clock=26
local ground_level=3
local function cells(_,_,t)
  local a,g,r,m=Field.lifecycle(t,"storm")
  if a==0 then return {} end
  return {{key="same-cell",x=52+t*.32,z=5+t*.14,dist=52,alpha=a,growth=g,rain=r,mist=m,
    time=t,kind="storm",size=1,skew=0}}
end
storm.start(core,function(p) return p.visible end,{
  clock=function() return clock end,cells=cells,ground=function() return ground_level end,
  spectator=function(p) return p==b end})
local prop=clouddef.initial_properties
assert(prop.visual=="mesh" and not prop.static_save and not prop.physical and not prop.pointable and
  not prop.collide_with_objects and prop.use_texture_alpha and not prop.is_visible)
local function adv(n,dt)
  for _=1,n do clock=clock+(dt or .3);step(dt or .3) end
end
local function part(p,asset)
  for _,r in ipairs(objects) do
    if r.at and r.name==p.name and r.properties.mesh=="bl_voxel_cloud_"..asset..".obj" then return r end
  end
end
adv(10)
local cloud=assert(part(a,"bank"))
local twin=assert(part(b,"bank"))
assert(cloud.at.x==twin.at.x and cloud.at.y==twin.at.y and not part(a,"column") and #effects==0)
assert(cloud.observers.builder and not cloud.observers.spectator)
local x,y=cloud.at.x,cloud.at.y
adv(165)
assert(part(a,"bank")==cloud and cloud.at.x>x+14)
assert(part(a,"column"))
local rain,bolt_seen,splash=0,0,0
for _,e in ipairs(effects) do
  assert(e.collisiondetection==false and (e.playername=="builder" or e.playername=="spectator"))
  if e.texture.name:find("rain") then assert(e.amount<=108 and e.maxvel.y<0);rain=rain+1
  elseif e.texture.name:find("spray") then assert(e.amount<=15);splash=splash+1
  else assert(e.texture.name:find("bolt") and e.glow<=13);bolt_seen=bolt_seen+1 end
end
assert(rain>0 and splash>0 and bolt_seen==42)
a.at={x=cloud.at.x,y=cloud.at.y,z=cloud.at.z}
b.at={x=twin.at.x,y=twin.at.y,z=twin.at.z}
adv(14)
assert(cloud.at.x>twin.at.x+10 and cloud.at.y==twin.at.y)
assert(cloud.properties.textures[1]:find("opacity",1,true))
assert(part(b,"bank")==twin,"A spectator keeps the same cloud on close approach")
assert(twin.at.y>y and twin.at.y<y+4)
ground_level=13
local previous=twin.at.y
adv(1)
assert(twin.at.y>previous and twin.at.y<previous+2,"Height follows terrain smoothly")
adv(38)
assert(twin.at.y>previous+8)
adv(200)
assert(part(b,"bank")==twin and not part(b,"column"),
  "Storm tower must dissipate back into the original cloud")
adv(120)
assert(not part(a,"bank") and not part(b,"bank"))
clock=24;adv(10)
local clean=assert(part(a,"bank"))
a.visible=false;adv(2);assert(not clean.at and part(b,"bank"))
leave(b);group={a};adv(2);assert(not part(b,"bank"))
print("PASS shared advecting sky: dry cloud, rain, thunder, mist, shared positions, terrain, smooth spectator clearance and cleanup")
