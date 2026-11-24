-- SPDX-License-Identifier: GPL-2.0-only
-- Integration at the scenic entry point: projected farm + real local paint
-- are both required before livestock may exist or move.
local S={W=512,H=512}
function S.id(x,z) return x>=1 and z>=1 and x<=S.W and z<=S.H and z*S.W+x or nil end
local tiles,farms,nodes={},{},{}
local function key(x,y,z) return x..":"..y..":"..z end
local function add_farm(x,z,farm,paint)
  local tx,tz=x+2,z+1
  tiles[S.id(tx,tz)]={stock_industry={id=farm,chain="farm",kind="farm",style="industry_farm",x=2,z=1}}
  farms[farm]={kind="farm"}
  if paint then
    nodes[key(tx*2,3,tz*2)]={name="luanttd_core:industry_farm_2_1"}
    nodes[key(tx*2,3,tz*2+2)]={name="luanttd_core:industry_farm_2_2"}
  end
end
local reg,all,reads={}, {},0
local core={
  register_entity=function(name,props) reg[name]=props.initial_properties end,
  get_node_or_nil=function(p) return nodes[key(p.x,p.y,p.z)] end,
  add_entity=function(pos,name)
    local def=assert(reg[name])
    local obj={at=pos,name=name,mesh=def.mesh,history={},before=pos}
    function obj:get_pos() return self.at end
    function obj:remove() self.at=nil end
    function obj:set_yaw(yaw) self.yaw=yaw end
    function obj:move_to(new,interpolate)
      assert(interpolate)
      self.before,self.at=self.at,new
    end
    function obj:set_properties(data)
      self.mesh=data.mesh
      self.history[data.mesh]=true
    end
    all[#all+1]=obj
    return obj
  end,
}
local view={
  host_tile=function(id) reads=reads+1;return tiles[id] end,
  host_record=function(name,id) assert(name=="stock_farm_industries");return farms[id] end,
  host_terrain_top=function(id) return tiles[id] and 2 end,
}
local base="mods/luanttd_core/"
local V=dofile(base.."farm_livestock_view.lua")(core,S,view)
for _,p in pairs(reg) do assert(not p.static_save and not p.physical and not p.pointable) end
local p={get_pos=function() return {x=26,y=4,z=27} end}
add_farm(10,11,1,false)
for _=1,10 do V.step(.2,{p}) end
assert(#all==0,"herd must wait for all farm mesh tiles")
add_farm(10,11,1,true)
local north={xlo=3.64+.295,xhi=5.33-.295,zlo=1.71+.295,zhi=3.35-.295}
local south={xlo=3.64+.295,xhi=5.33-.295,zlo=3.68+.295,zhi=5.34-.295}
local seen={}
for _=1,120 do
  V.step(.2,{p})
  for i,o in ipairs(all) do
    local a=o.at
    local px,pz=a.x-20,a.z-22
    local pig=o.name:match("_pig$")
    local pen=i<=2 and north or south
    local relax=pig and .095 or .028
    assert(px>=pen.xlo-relax and px<=pen.xhi+relax and pz>=pen.zlo-relax and pz<=pen.zhi+relax)
    assert(math.abs(a.y-2.526)<.000001)
    local travelled=math.sqrt((a.x-o.before.x)^2+(a.z-o.before.z)^2)
    assert(travelled<.08, "animal teleported")
    if travelled>.003 then
      local dx,dz=(a.x-o.before.x)/travelled,(a.z-o.before.z)/travelled
      assert(-math.sin(o.yaw)*dx+math.cos(o.yaw)*dz>.93,"backwards walk")
      seen[i]=true
    end
  end
end
assert(#all==5 and #seen==5)
for _,o in ipairs(all) do
  assert(o.history[o.name:gsub("luanttd_core:farm_livestock_","bl_farm_animal_").."_step_a.obj"])
  assert(o.history[o.name:gsub("luanttd_core:farm_livestock_","bl_farm_animal_").."_step_b.obj"])
  assert(o.history[o.name:gsub("luanttd_core:farm_livestock_","bl_farm_animal_").."_idle.obj"])
end
farms[1].removed=true
for _=1,5 do V.step(.2,{p}) end
for _,o in ipairs(all) do assert(not o.at,"removed farm must drop the herd") end
for i=2,8 do add_farm(8+i*2,13+(i%2)*4,i,true) end
local probes=reads
for _=1,15 do V.step(.2,{p}) end
assert(reads-probes<5000,"unbounded terrain discovery")
local alive=0
for _,o in ipairs(all) do if o.at then alive=alive+1 end end
assert(alive==20)
V.step(.1,{})
for _,o in ipairs(all) do assert(not o.at,"disconnected herd should not persist") end
print("PASS farm livestock: paint-gated wander, forward gait/pauses in both fenced pens, four-herd cap, cleanup")
