local root="mods/bayline/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local W=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,W)
local N=dofile(root.."ship_network.lua")(S,Terrain,W,D)
local Bridge=dofile(src.."road_bridge.lua")(dofile(src.."slope.lua"))
local Aqua=dofile(src.."aqueduct.lua")(Bridge)
local A=dofile(root.."ship_aqueduct_world.lua")(S,Terrain,Aqua)
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function(x) return (x<=5 or x>=10) and 1 or 0 end)
for _,t in ipairs(s.tiles) do t.terrain="grass";t.house=nil;t.site=nil;t.build=nil;t.wood=nil;t.owner=nil end
local function id(x,z) return S.id(x,z) end
local west,east,beneath=id(5,10),id(9,10),id(7,10)
s.tiles[beneath].terrain="water";s.tiles[beneath].water_class="river"
s.tiles[id(6,10)].build="road"
s.tiles[id(8,10)].build="stock_rail";s.tiles[id(8,10)].rail_tracks=2
s.tiles[id(4,10)].build="canal";s.tiles[id(10,10)].build="canal"
local company=S.company(s,"Alice")
local cash=company.cash
local p,why=A.quote(s,"Alice",west,east)
assert(p,why)
assert(p.deck==1 and p.middle_length==3 and p.price>0 and company.cash==cash)
assert(A.build(s,"Alice",west,east))
assert(company.cash==cash-p.price and s.aqueduct_above[beneath])
local B=N.board(s)
assert(B.tile(beneath).kind=="river" and W.water_class(B.tile(beneath))=="river")
assert(B.tile(west).kind=="aqueduct" and B.tile(east).kind=="aqueduct")
local link=W.follow(B,{},west,8)
assert(link.ok and link.bridge and link.skip==3 and link.tile==east)
assert(W.follow(B,{},east,0).tile==west)
assert(s.tiles[id(6,10)].build=="road" and s.tiles[id(8,10)].rail_tracks==2)
assert(not A.remove(s,"Foreign",east))
local dirty,price=A.remove(s,"Alice",east,true)
assert(#dirty==5 and price==10000 and s.aqueduct_above[beneath])
assert(A.remove(s,"Alice",east))
assert(company.cash==cash-p.price-price and not s.aqueduct_above[beneath])
assert(B.tile(beneath).kind=="river" and B.tile(west).kind=="clear")
print("PASS: layered aqueduct build and removal, stock paired ship heads, exact arched-span cost and untouched lower road, rail and river")
