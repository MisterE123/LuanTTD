-- Production worker endpoint, unchanging camera, full 3x3 interest window.
-- lua tests/campaign_snapshot_bench.lua [alternate_endpoint.lua] [batches] [alternate_projection.lua]
local function benchmark(mod,source,count,projection,clock)
  local Sim=dofile(mod.."/sim.lua")
  Sim.W,Sim.H=128,128
  local T=dofile(mod.."/openttd/terrain.lua")
  local s=Sim.new(1751)
  s.corner_grid=T.new(Sim.W,Sim.H,function(x,z) return math.floor((x+z)/30) end)
  for i,t in ipairs(s.tiles) do
    if i%61==0 then
      t.house=true
      t.source_house={id=i%28,completed=i%2==0,stage=i%4, render_parcel=i%9==0 and "shop" or nil}
    end
    if i%43==0 then t.wood={type=i%6,count=i%4+1,ground=1} end
  end
  local R=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,{
    road={start_year=1950,breakdowns=0,service_interval=150},
  })
  for i=1,192 do
    local az=5+(i*7)%120
    local ax=5+(i*31)%120
    local a,b=Sim.id(ax,az),Sim.id(ax+1,az)
    s.fleet[i]={id=i,owner="Bench",engine="bus",route={a,b},progress=1.5,
      running=true,cargo="passenger",units=i%30,orders={}}
  end
  if projection then R.terrain_projection=dofile(projection) end
  local A=dofile(source or mod.."/campaign_authority_endpoint.lua")(Sim,R)
  local windows={}
  for z=1,65,32 do for x=1,65,32 do windows[#windows+1]={x=x,z=z,w=32,h=32} end end
  local first=assert(A.snapshots(windows,.2).value)
  local actors=0
  for i,p in ipairs(first) do windows[i].scene=p.scene;actors=actors+#p.actors end
  if collectgarbage then collectgarbage("collect") end
  local t=clock()
  for batch=1,count do
    local r=A.snapshots(windows,(batch%10)/10)
    assert(r.ok and #r.value==9)
    for i,p in ipairs(r.value) do assert(p.scene==windows[i].scene and not p.tiles) end
  end
  local d=clock()-t
  return 1000*d/count,actors
end
if core then return benchmark end
local count=tonumber(arg[2]) or 50
local ms,visible=benchmark("mods/luanttd_core",arg[1],count,arg[3],os.clock)
print(("128² camera; 9 × 32² sectors; 192 active roads (%d visible); %d unchanged batches: %.3f ms/batch"):format(visible,count,ms))
