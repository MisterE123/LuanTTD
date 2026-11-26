local mod="mods/luanttd_core"
local clock,job,finish={},nil,nil
core={get_worldpath=function()return "/test-world" end,
  register_async_dofile=function()end,register_on_shutdown=function()end,
  handle_async=function(_,done) job=true;finish=done;return true end,
  ipc_set=function(k,v) clock[k]=v end,ipc_get=function(k)return clock[k]end,
}
local callbacks={}
core.after=function(t,f) callbacks[#callbacks+1]=f end
local function pump()
  local f=table.remove(callbacks,1)
  assert(f)
  f()
end
local notes={}
local function add(s) notes[#notes+1]=s end
local H=dofile(mod.."/campaign_authority_host.lua")(core,mod,{
  freeze_host=function() add("frozen") end,
  seal_checkpoint=function() assert(notes[1]=="frozen");add("sealed");return "owned.chk" end,
  ready=function(receipt) assert(receipt.day==7);add("ready") end,
  stopped=function(why) add(why) end,
  present=function() add("view") end,
})
assert(not H.query({kind="clock"},function()end))
assert(H.start({},64,64) and H.status()=="opening" and job)
assert(table.concat(notes,",")=="frozen,sealed")
clock["luanttd_core:authority:1:reply"]={ready=true,seq=0,day=7}
pump()
assert(H.status()=="owned" and notes[3]=="ready")
assert(H.step(.25,{{x=30,z=80}},.5))
assert(clock["luanttd_core:authority:1:request"].kind=="snapshots")
finish("network_failed",1,7)
assert(H.status()=="failed" and notes[#notes]=="network_failed")
assert(not H.query({kind="clock"},function()end))
print("PASS handoff freezes before sealing, releases only ready views, and never resumes an obsolete writer")
local got
local J=dofile(mod.."/campaign_authority_client.lua")(core,mod)
callbacks={}
assert(J.start({},function()end,function()end,"owned.chk"))
local session="luanttd_core:authority:1:"
clock[session.."reply"]={seq=0,ready=true}
pump()
assert(J.query({kind="snapshots"},function()end))
assert(J.defer({kind="command"},function(r) got=r end))
assert(not J.query({kind="snapshots"},function()end))
assert(clock[session.."request"].kind=="snapshots")
clock[session.."reply"]={seq=1,ok=true}
pump()
assert(clock[session.."request"].kind=="command")
clock[session.."reply"]={seq=2,ok=true}
pump()
assert(got and got.seq==2)
print("PASS deliberate forms wait behind one in-flight viewport then outrank the next paint")
local parked=dofile(mod.."/campaign_authority_host.lua")(core,mod,{
  freeze_host=function()end,seal_checkpoint=function()return "owned.chk" end,
  ready=function()end,present=function()end,stopped=function()end,
})
callbacks={}
assert(parked.start({},64,64))
clock[session.."reply"]={seq=0,ready=true}
pump()
parked.step(1.2,{},{})
parked.step(1.0,{},{})
assert(clock[session.."request"].kind=="clock","empty world must renew the lease without sending terrain")
print("PASS host keeps its simulation lease with no viewers and no terrain traffic")

-- Run the deterministic worker clock and mailbox order checks in this suite.
dofile("tests/campaign_step.lua")
