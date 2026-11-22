local root="mods/bayline/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local F=dofile(root.."openttd/yapf_road_follow.lua")
local C=dofile(root.."openttd/yapf_road_cost.lua")(F)
local Search=dofile(root.."openttd/yapf_road_search.lua")(F,C)
local Bridge=dofile(root.."openttd/road_bridge.lua")(dofile(root.."openttd/slope.lua"))
local T=dofile(root.."openttd/tram_construction.lua")(dofile(root.."openttd/road_slope.lua"),Bridge.roadtypes)
local N=dofile(root.."tram_network.lua")(Sim,T,Terrain)
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x>=30 and 1 or 0 end)
s.road_economy=true
for _,t in ipairs(s.tiles) do t.h=0;t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil end
local function at(x,z) return Sim.id(x,z or 10) end
local function fails(expected,f,...)
  local result,reason=f(...)
  assert(result==nil and reason==expected,tostring(reason).." expected "..expected)
end
local owner="Alameda"
local a,b,c,d,e,f=at(5),at(6),at(7),at(8),at(8,11),at(8,12)
local shared=s.tiles[c]
shared.build,shared.road_bits,shared.road_town="road",10,1
local terminal=s.tiles[f]
terminal.build,terminal.road_bits,terminal.owner="road",5,"Blue Bus"
local t0=s.topology
local co=Sim.company(s,owner)
local cash0=co.cash
local route={b,c,d,e,f}
local p,price=N.plan(s,owner,"road",route)
assert(#p==5 and price==1520 and shared.tram==nil and co.cash==cash0 and s.topology==t0)
fails("TRAM_DRAG_NOT_CONNECTED",N.plan,s,owner,"road",{b,f})
fails("INVALID_PARAMETER",N.plan,s,owner,"road",{b,c,b})
fails("VEHICLE_IN_THE_WAY",N.construct,s,owner,"road",route,nil,function(id)return id==c end)
assert(co.cash==cash0 and s.topology==t0 and s.tiles[b].tram==nil)
assert(N.construct(s,owner,"road",route))
assert(co.cash==cash0-price and co.expense==price and co.month_exp==price and s.topology==t0+1)
assert(shared.road_bits==10 and shared.road_town==1 and shared.tram.tram_bits==10 and shared.tram.tram_owner==owner)
fails("ALREADY_BUILT",N.plan,s,owner,"road",route)
fails("PROTECTED_TILE",N.plan,s,owner,"depot",{c},F.NE)
assert(N.construct(s,owner,"depot",{a},F.SW))
assert(N.construct(s,owner,"road",{b},8))
assert(N.construct(s,owner,"drive_stop",{f},F.SE))
local B=N.board(s)
assert(B.tile(f).road_owner=="Blue Bus" and B.tile(f).tram_owner==owner and B.tile(f).owner==owner)
assert(B.tile(c).road_owner=="town" and B.tile(c).owner==nil and B.tile(c).tram_owner==owner)
assert(B.tile(a).dir==F.SW and B.tram_bits(a)==2)
assert(B.tram_bits(d)==12 and B.tram_bits(e)==5 and B.tram_bits(f)==5)
assert(B.center_z(a)==0 and B.center_z(at(31))==8 and B.adjacent(a,F.SW)==b)
assert(B.station_area(f,"bus").tile==f and B.station_area(f,"truck")==nil)
assert(B.tile(at(10))==nil and B.can_build_tram({owner=owner},at(10),1))
s.tiles[at(10)].house=1
fails("PROTECTED_TILE",N.plan,s,owner,"road",{at(10)},3)
fails("TRAM_NEEDS_FLAT_CLEARANCE",N.plan,s,owner,"road",{at(29)},10)
s.bridge_above={[at(12)]=true}
s.tunnel_below={[at(13)]=true}
fails("TRAM_NEEDS_FLAT_CLEARANCE",N.plan,s,owner,"road",{at(12)},10)
fails("TRAM_NEEDS_FLAT_CLEARANCE",N.plan,s,owner,"road",{at(13)},10)
s.tiles[at(14)].terrain="water"
fails("PROTECTED_TILE",N.plan,s,owner,"road",{at(14)},10)
local v={tile=a,owner=owner,tram=true,roadtype=1,compatible={[1]=true},bus=true,display_max_speed=112}
local dest=C.destination(B,v,{kind="station",station=f})
assert(dest)
local ok,best=Search.find(B,v,a,2^F.direction_trackdir(F.SW),dest)
assert(ok)
local course=Search.trace(B,v,dest,best)
assert(#course==6 and course[1].tile==a and course[4].tile==d and course[6].tile==f)
assert(F.tile_trackdirs(B.tile(a),false)==0 and F.tile_trackdirs(B.tile(e),false)==0)
local bus_board=dofile(root.."road_yapf_board.lua")(Sim,s,F)
assert(bus_board.tile(c).road_bits==10 and bus_board.tile(a)==nil and bus_board.tile(e)==nil)
B.tile(c).tram_bits=1
assert(B.tile(c).tram_bits==10,"query record mutated saved data")
local function clone(value)
  if type(value)~="table" then
    assert(({string=true,number=true,boolean=true,["nil"]=true})[type(value)])
    return value
  end
  assert(getmetatable(value)==nil)
  local out={}
  for k,p in pairs(value) do out[k]=clone(p) end
  return out
end
local restored=N.board(clone(s))
local again,target=Search.find(restored,v,a,2^F.direction_trackdir(F.SW),C.destination(restored,v,{kind="station",station=f}))
assert(again and target.cost==best.cost and restored.tile(f).tram_owner==owner)
local funds=co.cash
co.cash=1
fails("NOT_ENOUGH_MONEY",N.construct,s,owner,"road",{at(9)},10)
assert(not s.tiles[at(9)].tram and co.cash==1)
co.cash=funds
print("PASS: stock-priced independent tramway, atomic construction, protected grade, separate depot, through stop and curved stock YAPF route")
