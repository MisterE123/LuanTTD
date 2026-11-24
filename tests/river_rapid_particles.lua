-- Use the same projected Luanti surface coordinate convention as terrain_view.
local slope=dofile("mods/luanttd_core/openttd/slope.lua")
local open={[3]={-1,0},[6]={0,-1},[9]={0,1},[12]={1,0}}
local W,H=20,20
local function id(x,z) if x>=1 and x<=W and z>=1 and z<=H then return x+W*(z-1) end end
local x0,z0=10,10
local tags,tiles,emitted={},{},{}
local Sim={id=id,W=W,H=H}
local function xy(t) return (t-1)%W+1,math.floor((t-1)/W)+1 end
for i,mask in ipairs({3,6,9,12,3,3,3,3}) do
  local t=id(x0+i-3,z0)
  tags[t]=mask
  tiles[t]={water_class="river"}
end
local core={
  get_node_or_nil=function(p)
    local mask=tags[id(p.x/2,p.z/2)]
    if mask then return {name="luanttd_core:stock_river_"..mask.."_east"} end
  end,
  add_particlespawner=function(spec) emitted[#emitted+1]=spec end,
}
local V={
  tile=function(t) return tags[t],0 end,
  sample=function(t,x,z)
    local a,b=xy(t)
    return .5+slope.surface((x-a*2+.5)/2,(z-b*2+.5)/2,tags[t])
  end,
}
local effect=dofile("mods/luanttd_core/river_rapid_particles.lua")(core,Sim)
effect.step(.21,{tiles=tiles},V,{{name="Different",x=0,z=0,y=200}})
assert(#emitted==0)
effect.step(.21,{tiles=tiles},V,{{name="Player",x=2*x0,z=2*z0,y=0},
  {name="Different",x=0,z=0,y=200}})
assert(#emitted==24,"Six visible river tiles, four finite spawners each.")
local seen={}
for _,s in ipairs(emitted) do
  assert(s.playername=="Player" and s.time>0 and s.exptime.max<=.45)
  local x=math.floor((s.pos.min.x+.5)/2)
  local z=math.floor((s.pos.min.z+.5)/2)
  local mask=assert(tags[id(x,z)])
  seen[mask]=true
  local flow=open[mask]
  local vx=(s.vel.min.x+s.vel.max.x)/2
  local vz=(s.vel.min.z+s.vel.max.z)/2
  assert(math.abs(vx*flow[1]+vz*flow[2]-.84)<1e-9,"must go downhill")
  assert(s.texture.alpha_tween[2]==0)
end
for mask in pairs(open) do assert(seen[mask],mask) end
print("PASS all four rapids produce localized, finite downhill foam; distant viewers receive none")
