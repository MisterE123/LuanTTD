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
