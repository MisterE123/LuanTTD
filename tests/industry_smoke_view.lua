local Sim={W=128,H=128}
function Sim.id(x,z) return (z-1)*Sim.W+x end
local s={tiles={},stock_coal_industries={[1]={}},stock_farm_industries={[1]={}},
  stock_oil_industries={[1]={}},stock_heavy_industries={[1]={}}}
local mounted={}
local function facility(x,z,style,dx,dz,chain,level)
  local id=Sim.id(x,z)
  s.tiles[id]={h=level,stock_industry={style=style,x=dx,z=dz,chain=chain,id=1}}
  mounted[id]={name=("luanttd_core:%s_%d_%d"):format(style,dx,dz)}
  return id
end
local power=facility(5,5,"power_station",1,1,nil,3)
local factory=facility(7,5,"industry_factory",1,0,"farm",0)
facility(10,5,"industry_oil_refinery",0,0,"oil",1)
facility(6,8,"industry_steel_mill",2,1,"heavy",0)
facility(8,8,"industry_steel_mill",3,1,"heavy",0)
facility(9,8,"industry_oil_well",0,0,"oil",0)
facility(9,9,"industry_farm",0,0,"farm",0)
local p={name="A",x=11,y=6,z=11}
local handles={}
local adds,deleted=0,0
local core={get_node_or_nil=function(pos)
  local id=Sim.id(pos.x/2,pos.z/2)
  if s.tiles[id] and pos.y==s.tiles[id].h+1 then return mounted[id] end
end,add_particlespawner=function(spec)
  assert(spec.playername and spec.time==0 and spec.texture.alpha_tween[2]==0)
  assert(spec.texture.scale_tween[2].x>spec.texture.scale_tween[1].x)
  adds=adds+1;handles[adds]=spec
  return adds
end,delete_particlespawner=function(h,name)
  assert(handles[h].playername==name);handles[h]=nil;deleted=deleted+1
end}
local V=dofile("mods/luanttd_core/industry_smoke_view.lua")(core,Sim,
  {tile=function(id) return 0,s.tiles[id].h end})
local function count(player)
  local n=0
  for _,spec in pairs(handles) do if not player or spec.playername==player then n=n+1 end end
  return n
end
V.step(.5,s,{p})
assert(adds==6 and count()==6) -- power, 2 factory, refiners, 2 steel
local rim
for _,spec in pairs(handles) do
  if math.abs((spec.pos.min.x+spec.pos.max.x)*.5-10.48)<.001 then rim=spec end
end
assert(rim and math.abs(rim.pos.min.y-6.914)<.001 and rim.size.max>2.9)
V.step(.5,s,{p,{name="Away",x=11,y=65,z=11}})
assert(adds==6 and count("Away")==0)
mounted[power]=nil
V.step(.5,s,{p})
assert(deleted==1 and count()==5)
s.tiles[factory]=nil   -- a worker sector unloads before (or during) repaint
V.step(.5,s,{p})
assert(deleted==3 and count()==3)
s.stock_heavy_industries[1].removed=true
V.step(.5,s,{p})
assert(deleted==5 and count()==1)
V.leave("A");assert(count()==0)
p.y=80;V.step(.5,s,{p});assert(count()==0)
p.y=6;V.step(.5,s,{p});assert(count()==1)

-- Never scale spawn cost with the number of industries in the map.
for z=10,15 do for x=10,15 do facility(x,z,"power_station",2,1,nil,0) end end
V.step(.5,s,{p})
assert(count()==16)
V.step(.5,s,{})
assert(count()==0)
print("PASS distinct native industry outlets, actual node validation, 3D per-viewer culling, stable handles, cap, and cleanup")
