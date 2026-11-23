local observations,commands={},{}
local B=dofile("mods/luanttd_core/campaign_build_proxy.lua")({
  observe=function(req,done) observations[#observations+1]={req,done};return true end,
  query=function(req,done) commands[#commands+1]={req,done};return true end,
})
local first={tool="autotrack",start={x=18,z=20},finish={x=26,z=21}}
assert(not B.preview("Owner","rail",first,1) and #observations==1 and #commands==0 and observations[1][1].peek)
assert(not B.preview("Owner","rail",first,3) and #observations==1)
observations[1][2]({ok=true,value={cost=123,tiles={31}}})
assert(B.preview("Owner","rail",first,50).cost==123)
assert(B.commit("Owner","rail",first,function(ok) assert(ok) end))
assert(#commands==1 and not commands[1][1].peek)
commands[1][2]({ok=true,revision=1,value={token=8,cost=123,tiles={31}}})
assert(commands[2][1].command.token==8)
commands[2][2]({ok=true})
B.leave("Owner")
assert(not B.preview("Owner","rail",first,500) and #observations==2)
print("PASS construction previews are bounded read-only observations, not purchase tickets")
