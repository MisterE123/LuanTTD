local M=dofile("mods/bayline/sim.lua")
local T=dofile("mods/bayline/openttd/terrain.lua")
local s=M.new(1751)
local function id(x,z) return M.id(x,z) end
for z=7,14 do for x=6,23 do
  local t=s.tiles[id(x,z)]
  t.terrain="grass";t.h=0;t.house=nil;t.site=nil;t.wood=nil
end end
local function city(x,z,bits)
  assert(M.seed_town_road(s,x<14 and 1 or 2,id(x,z),bits))
end
for x=10,18 do city(x,12,10) end
local freight,err=M.seed_town_road(s,6,id(12,12),2)
assert(not freight and err=="Invalid town road location.")
local nonintegral,why=M.seed_town_road(s,1,id(12,12),3.5)
assert(not nonintegral and why=="Invalid town road edges.")
for x=10,18 do
  local t=s.tiles[id(x,12)]
  assert(t.road_bits==10 and t.road_town==(x<14 and 1 or 2) and not t.owner)
end
assert(M.road_connected(s,id(13,12),2))
s.corner_grid=T.new(M.W,M.H)
local function build(owner,tool,ids)
  local ok,msg,changes=M.build(s,owner,tool,ids)
  assert(ok,msg)
  return changes
end
local function path(owner,a,b)
  return M.path(s,{tile=a,mode="road",owner=owner},{tile=b,mode="road",owner=owner},"road",owner)
end
local first,last,middle=id(9,12),id(19,12),id(10,12)
build("A","road",{first,id(10,12)})
build("A","road",{id(18,12),last})
build("A","road_station",{first,last})
assert(s.stations[s.tiles[first].station].owner=="A")
assert(s.tiles[first].owner=="A" and not s.tiles[first].road_town)
assert(#assert(path("A",first,last))==11)
build("B","road_station",{middle})
local old=s.tiles[middle].station
assert(s.tiles[middle].owner=="B" and s.tiles[middle].road_town==1)
assert(s.stations[old].owner=="B" and #assert(path("A",first,last))==11)
assert(M.mode_on(s,middle,"road","A"))
assert(not M.mode_on(s,first,"road","B"))
assert(not path("B",first,last))
assert(not M.build(s,"A","clear",{middle}))
assert(not M.build(s,"A","road_station",{middle}))
assert(not M.build(s,"A","road",{id(10,11),middle}))
local c=M.company(s,"A")
local saved_cash=c.cash
local q,cost=M.plan(s,"A","road",M.line(first,last))
assert(q and #q==0 and cost==0 and c.cash==saved_cash)
local approach,join=id(17,11),id(17,12)
build("A","road",{approach,join})
assert(s.tiles[join].road_town==2 and not s.tiles[join].owner)
assert(M.road_connected(s,approach,3) and #assert(path("A",approach,last))==4)
local planted,why=M.build(s,"A","road_station",{join})
assert(not planted and why=="A through stop cannot go on a junction.")
local access,depot=id(11,12),id(11,11)
assert(not M.road_edge(s,access,1))
build("A","road_depot",{depot})
assert(s.tiles[depot].owner=="A" and s.tiles[depot].depot_dir==3 and not s.tiles[depot].road_town)
assert(s.tiles[access].road_town==1 and not s.tiles[access].owner and M.road_connected(s,depot,3))
assert(#assert(path("A",depot,last))==10)
assert(not M.build(s,"A","clear",{access}))
assert(not M.build(s,"A","clear",{id(16,12),approach}))
assert(s.tiles[approach].build=="road") -- failed mixed demolition is atomic
local bus=assert(M.purchase(s,"A","bus","passenger",nil,depot))
assert(M.add_order(s,"A",bus,s.tiles[first].station))
assert(M.add_order(s,"A",bus,s.tiles[last].station))
assert(M.toggle(s,"A",bus))
for _=1,60 do M.daily(s) end
assert(s.fleet[bus].delivered>0)
while M.position(s,s.fleet[bus])==middle do M.daily(s) end
build("B","clear",{middle})
assert(s.stations[old]==nil and s.tiles[middle].build=="road" and s.tiles[middle].road_town==1)
assert(not s.tiles[middle].owner and s.tiles[middle].road_bits==10)
assert(not M.build(s,"B","clear",{middle}))
assert(#assert(path("A",first,last))==11)
-- A B-only link is not usable as an A shortcut even at a public junction.
build("B","road",{id(15,13),id(15,12)})
build("B","road",{id(15,13),id(16,13)})
assert(#assert(path("B",id(15,13),id(18,12)))==5)
assert(M.road_connected(s,id(15,12),3) and not path("A",first,id(16,13)))
-- Accept and complete a municipal half-road, but never overwrite the town.
local half=id(17,13)
city(17,13,8)
local quote,price=M.plan(s,"B","road_station",{half})
assert(quote and price==M.tools.road_station.price+math.ceil(M.tools.road.price/2))
build("B","road_station",{half})
assert(s.tiles[half].road_bits==10 and s.tiles[half].stop_axis==10 and s.tiles[half].road_town==2)
build("B","clear",{half})
assert(s.tiles[half].road_bits==10 and not s.tiles[half].stop_axis and s.tiles[half].road_town==2)
-- Private corners and junctions are incompatible, too.
local private=id(8,11)
build("A","road",{id(7,11),private,id(8,10)})
local can,message=M.build(s,"A","road_station",{private})
assert(not can and message=="A through stop cannot go on a corner.")
build("A","road",{private,id(8,12)})
can,message=M.build(s,"A","road_station",{private})
assert(not can and message=="A through stop cannot go on a junction.")
print("PASS: public roads, independent stop ownership, private access, depot access, protected removal and paid service")
