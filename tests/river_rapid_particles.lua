-- Use the same projected Luanti surface coordinate convention as terrain_view.
local slope=dofile("mods/luanttd_core/openttd/slope.lua")
local open={[3]={-1,0},[6]={0,-1},[9]={0,1},[12]={1,0}}
local W,H=20,20
local function id(x,z) if x>=1 and x<=W and z>=1 and z<=H then return x+W*(z-1) end end
local x0,z0=10,10
local tags,tiles,emitted,removed={},{},{},{}
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
  add_particlespawner=function(spec)
    emitted[#emitted+1]=spec
    return #emitted
  end,
  delete_particlespawner=function(id,player)
    assert(not removed[id] and player=="Player")
    removed[id]=true
  end,
}
local V={
  tile=function(t) return tags[t],0 end,
  sample=function(t,x,z)
    local a,b=xy(t)
    return .5+slope.surface((x-a*2+.5)/2,(z-b*2+.5)/2,tags[t])
  end,
}
local effect=dofile("mods/luanttd_core/river_rapid_particles.lua")(core,Sim)
local s={tiles=tiles}
local player={name="Player",x=2*x0,z=2*z0,y=0}
local remote={name="Different",x=0,z=0,y=200}
effect.step(.15,s,V,{remote})
assert(#emitted==0)
effect.step(.20,s,V,{player,remote})
assert(#emitted==40,"Five visible river tiles, four pairs of emitters each.")
local seen={}
for _,s in ipairs(emitted) do
  assert(s.playername=="Player" and s.time==0 and s.exptime.max<.75)
  local x=math.floor((s.pos.min.x+.5)/2)
  local z=math.floor((s.pos.min.z+.5)/2)
  local mask=assert(tags[id(x,z)])
  local flow=open[mask]
  local vx=(s.vel.min.x+s.vel.max.x)/2
  local vz=(s.vel.min.z+s.vel.max.z)/2
  local kind=s.texture.name:match("bl_river_(.*)%.png")
  seen[mask]=seen[mask] or {}
  seen[mask][kind]=true
  local speed=vx*flow[1]+vz*flow[2]
  if kind=="wake" then
    assert(math.abs(speed-.92)<1e-9,"foam should be carried downstream")
    local vy=(s.vel.min.y+s.vel.max.y)/2
    assert(vy>-.47 and vy<-.40,"wake should skim the exact slope")
  else
    assert(speed>.2 and speed<.7 and s.vel.min.y>0 and s.acc.y<0,"impact spray should rise, spread and fall")
  end
  assert(s.texture.alpha_tween[#s.texture.alpha_tween]==0)
end
for mask in pairs(open) do assert(seen[mask].spray and seen[mask].wake,mask) end
effect.step(.5,s,V,{player,remote})
assert(#emitted==40 and not next(removed),"reuses native emitters while in view")
effect.leave("Player")
for i=1,#emitted do assert(removed[i],i) end
effect.step(.5,s,V,{remote})
assert(#emitted==40)
print("PASS all four slopes: splash and wake, true downslope travel, distance cap, reuse and leave cleanup")
