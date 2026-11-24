-- SPDX-License-Identifier: GPL-2.0-only
-- Fixed-camera census and motion sampling; run against a baseline path with
-- --baseline to compare earlier ambient density on the very same map.
local baseline=arg[1]=="--baseline"
local source=baseline and assert(arg[2]) or "mods/luanttd_core/ambient_wildlife.lua"
local media={["bl_wildlife_atlas.png"]=true}
for _,k in ipairs{"whale","porpoise","seagull","eagle","fox"} do media["bl_wildlife_"..k..".obj"]=true end
local Sim={}
function Sim.id(x,z) if x>0 and x<=128 and z>0 and z<=128 then return (z-1)*128+x end end
function Sim.xy(id) return (id-1)%128+1,math.floor((id-1)/128)+1 end
local waterline=.5
local view={}
function view.host_tile(id)
  local x=Sim.xy(id)
  if x<50 then return {terrain="water",water_class="sea",h=0} end
  if x<54 then return {terrain="water",water_class="sea",coastal_water=true,h=0} end
  if x<=63 then return {terrain="grass",h=2} end
  return {terrain="grass",h=3,wood=x<=81}
end
function view.host_record(name,id)
  local x=Sim.xy(id)
  return name=="stock_farm_fields" and x>=54 and x<=63 and {}
end
function view.surface(id) return view.host_tile(id).h+.5 end
local function run(x,z)
  local state,settings,registered,live={},{},{},{}
  local p={get_player_name=function()return "viewport"end,get_pos=function()return{x=x,z=z,y=5}end}
  function p:get_meta()
    return {get_int=function(_,k)return settings[k] or 0 end,set_int=function(_,k,v)settings[k]=v end}
  end
  local core={get_player_by_name=function()return p end, get_connected_players=function()return {p}end}
  function core.register_entity(k,d) registered[k:match("wildlife_(.*)")]=d.initial_properties end
  function core.add_entity(pos,k)
    local ref={pos=pos,kind=k:match("wildlife_(.*)")}
    function ref:move_to(q,continuous)
      if not self.moved then self.initial_snap=not continuous;self.moved=true end
      self.pos=q
    end
    function ref:get_pos()return self.pos end
    function ref:remove()self.pos=nil;live[self]=nil end
    function ref:set_observers()end
    function ref:set_properties()end
    function ref:set_rotation(q)self.rot=q end
    live[ref]=true
    return ref
  end
  local blows=0
  function core.add_particlespawner(q)
    assert(q.pos.min.y>waterline,"submerged blowhole spray")
    blows=blows+1
  end
  local V=dofile(source)(core,Sim,view,media)
  local total=0
  for i=1,9000 do
    V.step(.2,{p})
    if not baseline then assert(V.count()<=7) end
    total=total+V.count()
    for a in pairs(live) do
      local h,r=a.pos.y-waterline,a.rot.x
      if a.kind=="porpoise" then
        if h>.62 and math.abs(r)<.56 then state.jump=true end
        if h<-.45 and math.abs(r)<.01 then state.swim=true end
        if h>-.25 and r<-.4 then state.nose_up=true end
        if h>-.25 and r>.4 then state.nose_down=true end
      elseif a.kind=="whale" then
        if h>.8 then state.breach=true end
        if h<-.95 and math.abs(r)<.01 then state.deep=true end
        if h>-.14 and h<-.085 and math.abs(r)<.035 then state.surface=true end
      elseif a.kind=="fox" then
        state.fox=true
        assert(math.abs(a.pos.y-(2.5+.012))<.0001)
      end
      if not baseline then assert(a.initial_snap,"scenic mesh interpolates from an incorrect spawn point") end
    end
  end
  if not baseline then
    assert(registered.fox.visual_size.x==.5 and registered.fox.visual_size.y==.5 and registered.fox.visual_size.z==.5)
  end
  return total/9000,state,blows
end
local mean=0
for _,set in ipairs{{"sea",40,91},{"coast",97,90},{"field",116,87},{"woods",177,91}} do
  local count,p,blows=run(set[2],set[3])
  if not baseline and set[1]=="sea" then
    assert(p.jump and p.swim and p.nose_up and p.nose_down)
    assert(p.breach and p.deep and p.surface and blows>0)
  elseif not baseline and set[1]=="field" then assert(p.fox) end
  mean=mean+count
  print(("%s: %.3f mean actors"):format(set[1],count))
end
print(("Four fixed-view habitats: %.3f mean actors"):format(mean/4))
if not baseline then
  assert(mean/4>1.90 and mean/4<2.35)
  print("PASS rare whale breaches, breathing/dive, natural porpoise arcs and half-size ground-following fox")
end
