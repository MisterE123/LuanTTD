local root="mods/luanttd_core/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local Water=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,Water)
local N=dofile(root.."ship_network.lua")(S,Terrain,Water,D)
local Construct=dofile(src.."water_construction.lua")(T,Water)
local C=dofile(root.."ship_water_world.lua")(S,N,Construct)
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function(x)return x<15 and 1 or 0 end)
local function at(x,z)return S.id(x,z)end
for _,t in ipairs(s.tiles) do
  t.terrain="grass";t.owner=nil;t.site=nil;t.house=nil;t.build=nil;t.wood=nil
end
-- RC1 physical water sites are not the same thing as navigable tiles.
-- Case includes both native ship construction and removal: rocks do not
-- come back after the paid clear, while untouched approach rocks remain.
do
  local owner="Quarry QA"
  local shore,pier,head=at(14,7),at(15,7),at(16,7)
  local one,two=at(17,8),at(18,8)
  local buoy=at(18,10)
  for _,i in ipairs({pier,head,one,two,buoy}) do
    s.tiles[i].terrain,s.tiles[i].water_class="water","sea"
  end
  for _,i in ipairs({pier,head,one,buoy}) do s.tiles[i].stock_water_rocks=true end
  local board=N.board(s)
  assert(Water.at(board,head)==0 and Water.at(board,buoy)==0)
  local account=S.company(s,owner)
  local opening=account.cash
  local q=assert(N.quote(s,owner,"dock",shore))
  assert(q.approach==head and q.cost==D.DOCK_BASE_COST+10000)
  assert(s.tiles[pier].stock_water_rocks and account.cash==opening)
  assert(N.build(s,owner,"dock",shore).cost==q.cost)
  assert(not s.tiles[pier].stock_water_rocks and s.tiles[head].stock_water_rocks)
  assert(not board.is_docking(head))
  assert(N.remove(s,owner,shore))
  assert(Water.at(board,pier)~=0 and Water.at(board,head)==0)
  assert(N.build(s,owner,"depot",one,0).cost==D.DEPOT_BASE_COST+10000)
  assert(N.remove(s,owner,one) and Water.at(board,one)~=0)
  assert(N.build(s,owner,"buoy",buoy).cost==D.BUOY_BASE_COST+10000)
  assert(N.remove(s,owner,buoy) and Water.at(board,buoy)~=0)
  assert(account.cash==opening-q.cost-55-D.DEPOT_BASE_COST-10000-90-D.BUOY_BASE_COST-10000-D.BUOY_CLEAR_COST)
  -- Reset only the isolated fixture before the existing canal assertions.
  for _,i in ipairs({pier,head,one,two,buoy}) do
    s.tiles[i].terrain,s.tiles[i].water_class,s.tiles[i].stock_water_rocks="grass",nil,nil
  end
  print("PASS: RC1 rock clearance for dock/depot/buoy, separate blocked approach and exact budget debit")
end
local a,b=at(5,8),at(9,8)
local cash=S.company(s,"A").cash
local q=assert(C.quote(s,"A",a,b))
assert(q.cost==25000 and S.company(s,"A").cash==cash and s.tiles[a].build==nil)
local p=assert(C.build(s,"A",a,b))
local B=N.board(s)
for x=5,9 do
  local id=at(x,8)
  assert(B.tile(id).base==1 and B.tile(id).kind=="canal" and Water.at(B,id)~=0)
end
assert(p.cost==25000 and s.tiles[a].stock_canal and S.company(s,"A").water_infrastructure==5)
local no,why=C.build(s,"B",a,a)
assert(not no and why=="OWNED_BY_ANOTHER")
local no,why=C.build(s,"A",at(11,8),at(16,8))
assert(not no and why=="FLAT_LAND_REQUIRED" and not s.tiles[at(11,8)].stock_canal)
local no,w=C.remove(s,"B",a)
assert(not no and w=="OWNED_BY_ANOTHER")
assert(C.remove(s,"A",a))
assert(B.tile(a).kind=="clear" and S.company(s,"A").water_infrastructure==4)
assert(S.company(s,"A").cash==cash-30000)
print("PASS: atomic elevated canal drag, exact cost and ownership, navigable typed water and safe complete removal")

-- A real one-level canal transition; fresh ends become water and remain
-- water after removal. Wrong-company and occupied checks are read-only.
local lower,middle,upper=at(15,12),at(14,12),at(13,12)
local lock,reason=C.quote_lock(s,"A",middle)
assert(lock,reason)
assert(lock.cost==17500 and lock.lower==lower and lock.upper==upper)
assert(lock.records[middle].slope==12 and lock.records[middle].dir==T.NE)
assert(C.build_lock(s,"A",middle))
assert(B.tile(lower).kind=="lock" and B.tile(lower).part=="lower")
assert(B.tile(middle).part=="middle" and B.tile(middle).base==0 and B.tile(middle).top==1)
assert(B.tile(upper).part=="upper" and B.tile(upper).base==1)
assert(S.company(s,"A").water_infrastructure==12)
local no,why=C.remove_lock(s,"B",lower)
assert(not no and why=="SELECT_OWN_LOCK")
local no,why=C.remove_lock(s,"A",upper,false,function(cell)return cell==middle end)
assert(not no and why=="VEHICLE_IN_THE_WAY")
local dirty,price=C.remove_lock(s,"A",lower,true)
assert(#dirty==3 and price==2000 and B.tile(middle).kind=="lock")
assert(C.remove_lock(s,"A",upper))
assert(B.tile(middle).kind=="clear" and B.tile(lower).kind=="canal" and B.tile(upper).kind=="canal")
assert(S.company(s,"A").water_infrastructure==6)
print("PASS: stock low/center/high lock installation and full removal preserve end canals, ownership and infrastructure counts")
