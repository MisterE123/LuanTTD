local mod="mods/luanttd_core"
local P=dofile(mod.."/campaign_authority_projection.lua")()
local cb,req
local client={query=function(request,callback) req,cb=request,callback;return true end}
local paints=0
local I=dofile(mod.."/campaign_authority_interest.lua")(client,P,4096,4096,function() paints=paints+1 end)
local function reply(sequence,id)
  local windows={}
  for i,w in ipairs(req.windows) do
    windows[i]={x=w.x,z=w.z,width=w.w,height=w.h,actors=i==1 and {{key="road:"..id}} or {}}
  end
  cb({ok=true,seq=sequence,tick=sequence*74,value=windows})
end
I.update({{x=80,z=80},{x=88,z=89}})
assert(I.step(0,.5) and #req.windows==9 and req.fraction==.5)
I.update({{x=7999,z=7999}})
reply(1,1)
assert(not P.actors()["road:1"])
assert(I.step(.2,1) and #req.windows==9 and req.windows[1].x>3500)
reply(2,1)
assert(P.actors()["road:1"])
I.update({})
assert(not P.actors()["road:1"] and not I.step(.2,1))
assert(paints==4)
print("PASS overlapping viewport requests are bounded, and late sectors cannot respawn an offscreen actor")

local view=dofile(mod.."/campaign_authority_projection.lua")()
local types={}
local clocked={}
local seq=0
local observer={query=function(request,callback)
  seq=seq+1
  types[#types+1]=request.kind
  local w=assert(request.windows[1])
  local area={x=w.x,z=w.z,width=w.w,height=w.h,actors={{key="road:1",tile=seq}}}
  if request.kind=="snapshots" then
    area.scene=10
    area.tiles={{id=31}}
  else
    assert(request.players==nil and w.after_boarding==nil)
  end
  callback({ok=true,seq=seq,tick=3,actor_us=1000+seq,value={area}})
  return true
end}
local i=dofile(mod.."/campaign_authority_interest.lua")(observer,view,32,32,function(p,fast)
  if fast then clocked[#clocked+1]=p.actor_clock() end
end)
i.update({{x=24,z=24,name="Observer"}})
assert(i.step(0,0))
for _=1,24 do i.step(.05,0) end
local slow,fast=0,0
for _,kind in ipairs(types) do
  if kind=="snapshots" then slow=slow+1 else fast=fast+1 end
end
assert(slow>=5 and slow<=7 and fast>=slow-1 and fast==#clocked)
assert(view.terrain(1,1).id==31 and view.scene("1:1")==10 and view.actors()["road:1"].tile==seq)
print("PASS motion polls are independent of terrain, never replay structural/HUD callbacks, and preserve scene identity")
