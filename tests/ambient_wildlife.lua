-- SPDX-License-Identifier: GPL-2.0-only
local registered,spawned,players={}, {},{}
local core={
  register_entity=function(k,d) registered[k]=d.initial_properties end,
  add_entity=function(pos,k)
    local a={pos=pos,kind=k}
    function a:get_pos() return self.pos end
    function a:remove() self.pos=nil end
    function a:move_to(p) self.pos=p end
    function a:set_observers(q) self.observers=q end
    function a:set_properties() end
    function a:set_rotation(q) self.rotation=q end
    spawned[#spawned+1]=a;return a
  end,
  get_connected_players=function() return players end,
}
local Sim={}
function Sim.id(x,z) if x>0 and x<=128 and z>0 and z<=128 then return (z-1)*128+x end end
function Sim.xy(id) return (id-1)%128+1,math.floor((id-1)/128)+1 end
local reads=0
local mode="normal"
local view={}
function view.host_tile(id)
  reads=reads+1
  local x,z=Sim.xy(id)
  if mode=="void" then return {stock_void=true,terrain="water",h=0} end
  if x>=54 and x<70 then return {terrain="grass",h=2,x=x,z=z,wood=x>63} end
  if x>=70 then return {terrain="grass",h=3,x=x,z=z} end
  if x>=42 and x<50 then return {terrain="water",water_class="river",h=1} end
  if x>=50 then return {terrain="water",water_class="sea",coastal_water=true,h=0} end
  return {terrain="water",water_class="sea",h=0}
end
function view.host_record(k,id)
  local x=Sim.xy(id)
  return k=="stock_farm_fields" and x>=54 and x<=63 and {}
end
function view.surface(id) return view.host_tile(id).h+.5 end
local media={["bl_wildlife_atlas.png"]=true}
local species={"whale","porpoise","seagull","eagle","fox"}
for _,k in ipairs(species) do media["bl_wildlife_"..k..".obj"]=true end
local V=dofile("mods/luanttd_core/ambient_wildlife.lua")(core,Sim,view,media)
for _,d in pairs(registered) do assert(not d.static_save and not d.physical and not d.pointable) end
assert(V.habitat("whale",49,81) and V.habitat("porpoise",49,81))
assert(not V.habitat("whale",92,81) and not V.habitat("porpoise",92,81),"river is not open sea")
assert(not V.habitat("porpoise",104,81),"shallows are not safe for swimmers")
assert(V.habitat("seagull",104,81) and V.habitat("eagle",136,81))
assert(V.habitat("fox",120,81) and not V.habitat("fox",145,81))
mode="void";assert(not V.habitat("whale",49,81));mode="normal"
local function player(n,x,z)
  local values={}
  return {get_player_name=function()return n end,get_pos=function()return{x=x,y=5,z=z}end,
    get_meta=function()return {get_int=function(_,k)return values[k] or 0 end,set_int=function(_,k,v) values[k]=v end}end}
end
local a,b,c=player("shore",80,88),player("field",120,87),player("ocean",42,90)
players={a,b,c}
reads=0
local seen={}
for _=1,120 do
  V.step(.25,players)
  assert(V.count()<=28)
  for _,a in ipairs(spawned) do
    if a.pos then seen[a.kind:match("wildlife_(.+)")] = true end
  end
end
for _,s in ipairs(species) do assert(seen[s],s) end
assert(reads<23500,"ambient scanned an unbounded extent")
assert(V.toggle(a) and not V.enabled(a) and V.enabled(b))
for _,o in ipairs(spawned) do
  if o.pos then assert(not o.observers.shore and o.observers.field and o.observers.ocean) end
end
V.step(.2,{})
assert(V.count()==0,"scenic actors remain without viewers")
print("PASS species habitats, nonpersistent local actors, bounded activity and independent /candy observers")
