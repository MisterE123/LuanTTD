-- SPDX-License-Identifier: GPL-2.0-only
local C=dofile("mods/luanttd_core/openttd/rail_collision.lua")
local function part(chain,x,y,z,len)
  return {kind="train",owner="A",consist=chain,x=x,y=y,z=z,length=len,tile=7}
end
local front=part(1,30,30,0,8)
assert(C.overlap(front,part(2,37,30,5,8)))
assert(not C.overlap(front,part(2,38,30,0,8)))
assert(not C.overlap(front,part(2,35,35,0,8)))
assert(not C.overlap(front,part(2,30,30,6,8))) -- vertically separate bridge
assert(C.overlap(front,part(2,36,30,-5,5)))
assert(not C.overlap(front,part(2,37,30,-5,5))) -- actual wagon size
local own,depot,bus,foreign=part(1,30,30,0,8),part(2,30,30,0,8),part(3,30,30,0,8),part(4,30,30,0,8)
depot.depot,bus.kind,foreign.owner=true,"bus","B"
local left,right=part(5,30,30,0,8),part(6,30,30,0,8)
local seen,tiles,near,dead={}, {},0,{}
local world={
  near=function(x,y,r)
    assert(x==30 and y==30 and r==7);near=near+1
    return {own,depot,bus,foreign,left,left,right}
  end,
  other_end=function(tile) assert(tile==7);return 17 end,
  on_tile=function(tile) tiles[#tiles+1]=tile;return tile==7 and {left,left} or {right} end,
}
local function crash(a,b)
  assert(a==1)
  seen[#seen+1]=b
  local victims=0
  for _,id in ipairs({a,b}) do if not dead[id] then victims=victims+2;dead[id]=true end end
  return victims
end
local collided,victims=C.scan(front,world,crash)
assert(collided and victims==6 and table.concat(seen,",")=="5,5,6" and near==1)
assert(not C.scan(front,world,crash)) -- no twice-crash victim/news event
front.depot=true
assert(not C.scan(front,world,crash) and near==2)
front.depot,front.wormhole,dead=nil,true,{}
collided,victims=C.scan(front,world,crash)
assert(collided and victims==6 and near==2 and table.concat(tiles,",")=="7,17")
print("PASS RC1 rail collision predicates, true body length/vertical clearance, ordered victims, depot and tunnel portals")
