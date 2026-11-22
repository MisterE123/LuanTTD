local root="mods/luanttd_core/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local Water=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,Water)
local N=dofile(root.."ship_network.lua")(S,Terrain,Water,D)
local Y=dofile(src.."ship_yapf.lua")(T,Water,dofile(src.."yapf_road_search.lua"))
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function(x) return x<9 and 1 or 0 end)
local function id(x,z) return S.id(x,z) end
for i,t in ipairs(s.tiles) do
  local x,z=S.xy(i)
  t.site=nil;t.owner=nil;t.wood=nil;t.house=nil;t.build=nil
  t.terrain=x>=9 and "water" or "grass"
  if x>=9 and z==9 then t.water_class="river" end
end
local left=assert(N.build(s,"Alice","dock",id(8,9)))
local right=assert(N.build(s,"Alice","dock",id(8,16)))
local depot=assert(N.build(s,"Alice","depot",id(12,10),0))
assert(left.dir==T.SW and left.cost==350 and right.water==id(9,16))
assert(depot.cost==700 and depot.tiles[2]==id(13,10))
local B=N.board(s)
assert(Water.water_class(B.tile(id(10,9)))=="river" and s.tiles[id(9,9)].terrain=="water")
assert(B.closest_station_tile(left.id,id(14,10))==left.water)
assert(B.closest_station_tile(left.id,id(5,10))==left.land)
assert(Water.at(B,left.water)==0 and B.is_docking(id(10,9)) and B.is_docking(id(9,10)))
assert(Water.ship_destination(B,id(10,9),left.id) and not Water.ship_destination(B,id(10,9),right.id))
for _,d in ipairs({left,right}) do assert(B.tile(d.water).water_part and not B.tile(d.land).water_part) end
assert(B.ship_depot(id(12,10)).owner=="Alice")
local v={owner="Alice",tile=id(13,10),ocean_speed_frac=0,canal_speed_frac=0}
local destination=Y.destination(B,v,{kind="station",station=right.id})
assert(destination and destination.tile==right.water)
local ok,best=Y.find(B,v,v.tile,2^T.diagonal_trackdir(T.SW),destination)
assert(ok and best.last_tile~=right.water and Water.ship_destination(B,best.last_tile,right.id))
assert(S.company(s,"Alice").expense==1400)
local blocked,why=N.build(s,"Alice","dock",id(8,9))
assert(not blocked and why=="SITE_UNSUITABLE" or not blocked and why=="PROTECTED_TILE")
assert(S.company(s,"Alice").expense==1400)
local no,denied=N.remove(s,"Foreign",left.water)
assert(not no and denied=="SELECT_OWN_FACILITY")
no,denied=N.remove(s,"Alice",left.water,function(tile) return tile==left.water end)
assert(not no and denied=="VEHICLE_IN_THE_WAY")
local dirty,cost=N.remove(s,"Alice",left.water)
assert(#dirty==2 and cost==55 and B.tile(left.water).kind=="river" and not B.is_docking(id(10,9)))
dirty,cost=N.remove(s,"Alice",depot.tiles[2])
assert(#dirty==2 and cost==90 and B.tile(depot.tiles[1]).kind=="sea")
assert(S.company(s,"Alice").expense==1545)
local sea,river,canal=id(18,10),id(18,9),id(18,12)
local canal_tile=s.tiles[canal]
canal_tile.build,canal_tile.owner,canal_tile.water_class,canal_tile.stock_canal="canal","Bob","canal",true
local cash,topo,seq=S.company(s,"Alice").cash,s.topology,s.next_stock_ship_station
for _,case in ipairs({{sea,"sea"},{river,"river"},{canal,"canal","Bob"}}) do
  local cell,class,owner=case[1],case[2],case[3]
  local p=assert(N.quote(s,"Alice","buoy",cell))
  assert(p.tile==cell and #p.tiles==1 and p.cost==350 and p.water_class==class and p.water_owner==owner)
  assert(not s.tiles[cell].ship and S.company(s,"Alice").cash==cash and s.topology==topo
    and s.next_stock_ship_station==seq,"quotes do not mutate the tile, finance, or ID counter")
end
s.bridge_above={[sea]=true}
local n,r=N.build(s,"Alice","buoy",sea)
assert(not n and r=="BRIDGE_ABOVE")
s.bridge_above=nil
s.tiles[id(8,10)].terrain="water" -- flatness comes from corners, not ground label
n,r=N.build(s,"Alice","buoy",id(8,10))
assert(not n and r=="BUOY_NEEDS_OPEN_WATER")
n,r=N.build(s,"Alice","buoy",id(7,10))
assert(not n and r=="BUOY_NEEDS_OPEN_WATER")
s.tiles[id(18,13)].stock_industry=50
n,r=N.build(s,"Alice","buoy",id(18,13))
assert(not n and r=="PROTECTED_TILE")
assert(S.company(s,"Alice").cash==cash and s.topology==topo)
local Bob=S.company(s,"Bob")
local previous=Bob.cash
for _,case in ipairs({{sea,"sea"},{river,"river"},{canal,"canal","Bob"}}) do
  local cell,class,owner=case[1],case[2],case[3]
  local tracks=Water.at(B,cell)
  local p=assert(N.build(s,"Alice","buoy",cell))
  local r=B.tile(cell)
  assert(p.id>right.id and r.kind=="buoy" and r.water_class==class and r.owner==owner and r.station==p.id)
  assert(s.stock_ship_buoys[p.id].tile==cell and not s.stock_ship_buoys[p.id].owner and
    not s.stock_ship_stations[p.id] and #B.station_dock_tiles(p.id)==0 and Water.at(B,cell)==tracks)
  n,why=N.build(s,"Alice","buoy",cell)
  assert(not n and why=="PROTECTED_TILE")
  n,why=N.remove(s,"Bob",cell,function(t)return t==cell end,true)
  assert(not n and why=="VEHICLE_IN_THE_WAY")
  s.stock_coal_ship_run={vehicle={tile=cell}}
  n,why=N.remove(s,"Bob",cell)
  assert(not n and why=="VEHICLE_IN_THE_WAY")
  s.stock_coal_ship_run=nil
  local before=Bob.cash
  local dirty,price=N.remove(s,"Bob",cell,nil,true)
  assert(dirty[1]==cell and #dirty==1 and price==50 and Bob.cash==before and s.tiles[cell].ship)
  Bob.cash=49
  n,why=N.remove(s,"Bob",cell)
  assert(not n and why=="NOT_ENOUGH_MONEY" and Bob.cash==49 and s.tiles[cell].ship)
  Bob.cash=before
  dirty,price=N.remove(s,"Bob",cell)
  assert(dirty[1]==cell and #dirty==1 and price==50 and Bob.cash==before-50)
  n,why=N.remove(s,"Bob",cell)
  assert(not n and not s.stock_ship_buoys[p.id] and not s.tiles[cell].ship and B.tile(cell).kind==class
    and B.tile(cell).owner==owner and Water.at(B,cell)==tracks)
end
assert(canal_tile.stock_canal and canal_tile.build=="canal" and Bob.cash==previous-150
  and S.company(s,"Alice").cash==cash-3*350 and s.topology==topo+6)
print("PASS: saved physical dock pairs, typed water/depot, virtual adjacent berths, and real source routing to a navigable destination")
print("PASS: neutral buoy quotes and removals, occupied and protected defenses, and exact sea/river/foreign canal preservation")
