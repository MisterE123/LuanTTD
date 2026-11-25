local m="mods/luanttd_core/"
local function read(n)return dofile(m..n..".lua")end
local S=read("sim")
local Terrain=read("openttd/terrain")
local T=read("openttd/town_foundation")
local Art=read("stock_town_art")
local Part=read("packed_campaign")
assert(T.autoslope(0,1,7,0)==250)
assert(T.autoslope(7,0,0,1,{autoslope=true,build_on_slopes=false})==250)
assert(T.autoslope(7,0,0,1,{foundation_price=175})==175)
assert(not T.autoslope(7,0,0,1,{autoslope=false}))
assert(not T.autoslope(7,0,0,1,nil,true))
assert(not T.autoslope(0,2,23,0))
assert(not T.autoslope(0,1,7,1))
local s=S.new(1751)
for id in pairs(s.tiles) do s.tiles[id]={terrain="grass",h=1,variant=0} end
s.corner_grid=Terrain.new(S.W,S.H,function()return 1 end)
local x,z=8,9
local owner="Builder"
local c=S.company(s,owner)
local cash=c.cash
for i=0,1 do for j=0,1 do
  local t=s.tiles[S.id(x+i,z+j)]
  t.house=true
  t.source_house={id=0x14+i*2+j,town=1,asset_root=0x14,asset_part=i*2+j,
    root=i+j==0,root_x=x,root_z=z,completed=true,stage=3}
end end
local root=s.tiles[S.id(x,z)].source_house
local ok,cost,q=S.landscape(s,owner,"lower",x+1,z+1,nil,nil,false,"footprint")
assert(ok and cost==1250 and #q.tiles==4 and #q.corners==1 and c.cash==cash)
assert(Terrain.corner(s.corner_grid,x+1,z+1)==1)
assert(S.landscape(s,owner,"lower",x+1,z+1))
assert(Terrain.corner(s.corner_grid,x+1,z+1)==0 and c.cash==cash-1250)
local saved=Part.decode(Part.encode(s))
local parts=assert(Art.footprint(S,saved,root))
for _,part in ipairs(parts) do
  local u,v=S.xy(part.id)
  local shape,base=Terrain.tile(saved.corner_grid,u,v)
  assert(base==0 and T.level(shape,base)==1 and saved.tiles[part.id].h==0)
  assert(part.record.completed and part.record.stage==3)
end
assert(not S.landscape(s,owner,"raise",x,z))
assert(c.cash==cash-1250 and #assert(Art.footprint(S,s,root))==4)
print("PASS stock house autoslope preserves the complete four-part stadium and stock level after checkpoint")
