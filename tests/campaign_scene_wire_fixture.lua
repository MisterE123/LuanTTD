local root=assert(core.get_modpath("luanttd_core")).."/"
local Sim=dofile(root.."sim.lua")
Sim.W,Sim.H=128,128
local s=Sim.new(1751)
local T=dofile(root.."openttd/terrain.lua")
s.corner_grid=T.new(128,128,function(x,z)return math.floor((x+z)/41) end)
local Projection=dofile(root.."campaign_terrain_projection.lua")
local A=dofile(root.."campaign_authority_endpoint.lua")
local P=dofile(root.."campaign_authority_projection.lua")
local benchmark={}
for _,want in ipairs({false,true}) do
 local api=A(Sim,{world=s,terrain=T,terrain_projection=Projection,versioned_terrain=true})
 local windows,sub,view={}, {},P()
 for z=1,65,32 do for x=1,65,32 do
  local key=x..":"..z
  windows[#windows+1]={x=x,z=z,w=32,h=32,delta_tiles=want}
  sub[#sub+1]={key=key,token=view.subscribe(key)}
 end end
 benchmark[#benchmark+1]={api=api,windows=windows,sub=sub,view=view,seq=0}
end
local function observe(b)
 local r=b.api.snapshots(b.windows,.4,nil,true)
 assert(r.ok)
 b.seq=b.seq+1;r.seq=b.seq
 assert(b.view.accept_batch(b.sub,r))
 for i,p in ipairs(r.value) do b.windows[i].scene=p.scene end
 return r
end
observe(benchmark[1]);observe(benchmark[2])
local function edit(i)
 for _,w in ipairs(benchmark[1].windows) do
  local t=s.tiles[Sim.id(w.x+i%30,w.z+(i*2)%30)]
  t.variant=((t.variant or 0)+1)%7
 end
end
local function equal(a,b)
 if a==b then return true end
 if type(a)~="table" or type(b)~="table" then return false end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local full,delta
for i=1,12 do
 edit(i)
 full,delta=observe(benchmark[1]),observe(benchmark[2])
 assert(equal(benchmark[1].view.windows(),benchmark[2].view.windows()))
 for _,r in ipairs(delta.value) do assert(r.scene_base and #r.tile_patch==1) end
end
return full,delta
