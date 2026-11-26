local observations,commands={},{}
local B=dofile("mods/luanttd_core/campaign_build_proxy.lua")({
  observe=function(req,done) observations[#observations+1]={req,done};return true end,
  query=function(req,done) commands[#commands+1]={req,done};return true end,
})
local first={tool="autotrack",start={x=18,z=20},finish={x=26,z=21}}
assert(not B.preview("Owner","rail",first,1) and #observations==1 and #commands==0 and observations[1][1].peek)
assert(not B.preview("Owner","rail",first,3) and #observations==1)
observations[1][2]({ok=true,value={cost=123,tiles={31},ticket="the displayed plan"}})
assert(B.preview("Owner","rail",first,50).cost==123)
assert(B.commit("Owner","rail",first,function(ok) assert(ok) end))
assert(#commands==1 and commands[1][1].kind=="rail_place" and commands[1][1].ticket=="the displayed plan")
commands[1][2]({ok=true,value={cost=123,tiles={31}}})
B.leave("Owner")
assert(not B.preview("Owner","rail",first,500) and #observations==2)
print("PASS construction previews are bounded read-only observations, not purchase tickets")
do
  local refreshed=0
  observations,commands={},{}
  local R=dofile("mods/luanttd_core/campaign_build_proxy.lua")({
    observe=function(req,done) observations[#observations+1]={req,done};return true end,
    query=function(req,done) commands[#commands+1]={req,done};return true end,
    refresh_scene=function()refreshed=refreshed+1 end,
  })
  local request={tool="drag",first=9,last=13,axis=0,start_half=true,end_half=false}
  local q,why,pending=R.preview("Owner","road",request,1)
  assert(not q and pending and why:find("Checking",1,true))
  local unrelated={tool="drag",first=9,last=11,axis=0,start_half=true,end_half=false}
  assert(not R.preview("Owner","road",unrelated,2) and #observations==1)
  observations[1][2]({ok=true,value={cost=400,tiles={9,10,11,12,13},ticket="exact"}})
  assert(R.preview("Owner","road",request,650050).cost==400 and #observations==2)
  assert(R.preview("Owner","road",request,651010).cost==400 and #observations==2)
  local fresh,_,checking=R.preview("Owner","road",unrelated,651020)
  assert(not fresh and checking and #observations==2)
  assert(R.preview("Owner","road",request,651022).cost==400)
  observations[2][2]({ok=true,value={cost=999,tiles={9},ticket="not-shown"}})
  local receipt
  assert(R.commit("Owner","road",request,function(ok,_,ticket,tiles)
    assert(ok and ticket.cost==400 and #tiles==5);receipt=true
  end))
  assert(#commands==1 and commands[1][1].kind=="road_place" and commands[1][1].quote.ticket=="exact")
  commands[1][2]({ok=true,value={9,10,11,12,13}})
  assert(receipt and refreshed==1)
  assert(not R.preview("Owner","road",request,651021) and #observations==3)
  assert(R.commit("Owner","road",unrelated,function(ok,why_)assert(not ok and why_=="ROAD_QUOTE_CHANGED")end))
  assert(#commands==2 and commands[2][1].quote==nil)
  commands[2][2]({ok=false,why="ROAD_QUOTE_CHANGED"})
  assert(refreshed==1)
  print("PASS pending road previews stay neutral, visible price carried, one authoritative placement request and repaint on success")
end
