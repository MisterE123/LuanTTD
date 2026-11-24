local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
s.sites,s.tiles={},{}
for i=1,S.W*S.H do s.tiles[i]={h=1,terrain="grass",variant=1} end
s.corner_grid=T.new(S.W,S.H,function()return 1 end)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
local n="Auto Timing"
local c=S.company(s,n)
local C=dofile(root.."campaign_road_construction.lua")(S,s)
local function id(x,z) return S.id(x,z) end
local function auto(tile,kind)
  return {tool="stock_terminal_auto",first=tile,kind=kind}
end
local function place(request,price)
  local cash=c.cash
  local q=assert(C.quote(n,request))
  if price then assert(q.cost==price,q.cost) end
  assert(c.cash==cash)
  assert(C.commit(n,request,q))
  assert(c.cash==cash-q.cost)
  return q
end
assert(S.build(s,n,"road",S.line(id(7,9),id(20,9))))
local a,b=id(11,9),id(12,9)
place(auto(a,"bus"),200)
place(auto(b,"truck"),200)
local group=s.tiles[a].station
assert(s.tiles[b].station==group and s.stations[group].bus_tile==a and s.stations[group].truck_tile==b)
assert(s.tiles[a].stop_axis==10 and s.tiles[b].stop_axis==10)
local chooser=assert(C.join_choices(n,auto(id(19,9),"bus")))
assert(chooser.choices[2].id==group and chooser.cost==200)
local d=id(10,8)
place(auto(d,"depot"))
assert(s.tiles[d].depot_dir==3 and S.road_bits(s,id(10,9))==11)
local corner=id(20,9)
assert(S.build(s,n,"road",S.line(corner,id(20,12))))
assert(select(2,C.quote(n,auto(corner,"bus"))):find("corner",1,true))
local free=id(18,8)
place(auto(free,"bus"))
assert(s.tiles[free].build=="road_station" and s.tiles[free].stop_axis==nil and s.tiles[free].road_bits==4)
local moving=id(14,9)
local request=auto(moving,"truck")
local visible=assert(C.quote(n,request))
s.tiles[moving].road_bits=5
local before=c.cash
assert(not C.commit(n,request,visible,true))
assert(c.cash==before and not s.tiles[moving].station)
print("PASS Auto uses stock prices and joins mixed facilities, scans nearby candidates, and attaches correctly oriented road bays and depots")
