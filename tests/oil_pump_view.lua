local path="mods/luanttd_core/"
local Sim=dofile(path.."sim.lua")
Sim.W,Sim.H=64,64
local id=Sim.id(7,4)
local cameras={{x=10,y=6,z=10}}
local painted="luanttd_core:industry_oil_well_0_0"
local refs={}
local core={
  register_entity=function(name,def)
    assert(name=="luanttd_core:oil_well_pump" and not def.initial_properties.static_save and not def.initial_properties.physical)
  end,
  get_connected_players=function()
    local viewers={}
    for i,pos in ipairs(cameras) do viewers[i]={get_pos=function()return pos end} end
    return viewers
  end,
  get_node_or_nil=function(pos)
    assert(pos.x==14 and pos.z==8 and pos.y==6)
    return {name=painted}
  end,
  add_entity=function(pos,name)
    assert(name=="luanttd_core:oil_well_pump")
    local r={writes=0,pos=pos,
      get_pos=function(self)return self.pos end,
      remove=function(self)self.pos=nil end,
      set_properties=function(self,p)self.writes=self.writes+1; self.mesh=p.mesh end}
    refs[#refs+1]=r;return r
  end,
}
local V=dofile(path.."oil_pump_view.lua")(core,Sim,{[painted]=true})
local w={tiles={[id]={h=5,stock_industry={id=123,chain="oil",gfx=29}}}}
local function set(base,site,phase)
  V.observe({[id]={base=base,site=site,oil=phase}})
  V.step(.12,w)
end
set(4,123,1);set(5,122,1);set(5,123,12)
assert(#refs==0,"Reject old site/grade and invalid phase")
set(5,123,0)
assert(#refs==1 and refs[1].mesh:match("pose_00"))
set(5,123,2);set(5,123,2)
assert(#refs==1 and refs[1].writes==2 and refs[1].mesh:match("pose_02"))
cameras={{x=900,y=0,z=900},{x=52,y=18,z=33}}
set(5,123,10)
assert(#refs==1 and refs[1].writes==3)
painted="air"
set(5,123,11)
assert(not refs[1].pos and not V.witness(id))
painted="luanttd_core:industry_oil_well_0_0"
set(5,123,1)
assert(#refs==2)
V.observe({})
V.step(.08,w)
assert(not refs[2].pos,"Closure or dropping subscription cleans up the actor")
print("PASS stationary oil meshes keep identity, update only on source phases, and require live site, painted pad and a local viewer")
