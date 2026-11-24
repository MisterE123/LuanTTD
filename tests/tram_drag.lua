local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local slopes=dofile(root.."openttd/road_slope.lua")
local Bridge=dofile(root.."openttd/road_bridge.lua")(dofile(root.."openttd/slope.lua"))
local Tram=dofile(root.."openttd/tram_construction.lua")(slopes,Bridge.roadtypes)
local N=dofile(root.."tram_network.lua")(S,Tram,T)
local s=S.new(1751)
s.sites,s.tiles={},{}
for i=1,S.W*S.H do s.tiles[i]={terrain="grass",h=1,variant=1} end
s.corner_grid=T.new(S.W,S.H,function()return 1 end)
s.road_economy=true
local owner="City ELRL"
local c=S.company(s,owner)
local function id(x,z)return S.id(x,z or 8) end
assert(S.build(s,owner,"road",S.line(id(8),id(15))))
assert(N.construct(s,owner,"road",{id(8)},2,function()return false end))
local make_probe=dofile(root.."tram_occupancy.lua")
local protected={current=function()return {legs={{path={id(13),id(20)}},{path={id(13)}}}} end}
local calls=0
local positions={position=function(_,v) calls=calls+1;return v.tile end}
s.fleet[1]={tile=id(18)}
s.fleet[2]={tile=id(21)}
local probe=make_probe(positions,protected,s)
for _=1,20 do
  assert(probe(id(18)) and probe(id(21)) and probe(id(13)))
  assert(not probe(id(12)))
end
assert(calls==2,"The sweep must not read the fleet again for each selected tile")
local before=c.cash
local req={tool="tram_lay",first=id(9),last=id(14),axis=0,start_half=false,end_half=true}
local M=dofile(root.."campaign_road_construction.lua")(S,s,nil,nil,{tram={net=N,busy_probe=function()return probe end}})
local quote=assert(M.quote(owner,req))
assert(quote.cost==4*380 and #quote.tiles==4)
assert(c.cash==before and not s.tiles[id(9)].tram)
assert(M.commit(owner,req,quote,true))
assert(c.cash==before-4*380 and s.tiles[id(9)].tram.tram_bits==10)
assert(not s.tiles[id(13)].tram and not s.tiles[id(14)].tram)
local free=function()return false end
local q=assert(N.drag_plan(s,owner,{first=id(12),last=id(14),axis=0,start_half=false,end_half=true},free))
assert(#q.changes==2 and q.changes[1].tram_bits==10 and q.changes[2].tram_bits==8)
assert(N.apply_drag(s,owner,q))
assert(s.tiles[id(14)].road_bits==10 and s.tiles[id(14)].tram.tram_bits==8)
-- No outward half is laid just because asphalt, rather than powered
-- track, continues beyond the end of the drag.
assert(not s.tiles[id(15)].tram)
local half=assert(N.drag_plan(s,owner,{first=id(22),axis=0,start_half=false,end_half=false},free))
assert(#half.changes==1 and half.changes[1].tram_bits==8)
print("PASS RC1 ELRL half-clicks, compatible outward attachment, stock obstacle prefix, one occupancy sweep, and untouched asphalt")
