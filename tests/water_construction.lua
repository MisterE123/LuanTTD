local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local Water=dofile(root.."ship_follow.lua")(T)
local C=dofile(root.."water_construction.lua")(T,Water)
local W,H=12,12
local function id(x,z) if x>=0 and z>=0 and x<W and z<H then return z*W+x end end
local function xy(i) return i%W,math.floor(i/W) end
local d={[0]={-1,0},{0,1},{1,0},{0,-1}}
local map,rev={},0
local B={tile_at=id,xy=xy,tile=function(i) return map[i] or {kind="clear",base=0} end,
  version=function() return rev end}
function B.adjacent(i,dir)
  local x,z=xy(i);return id(x+d[dir][1],z+d[dir][2])
end
local function put(i,kind,p) p=p or {};p.kind=kind;map[i]=p;return p end
local function deny(code,f,...)
  local p,why=f(...)
  assert(p==nil and why==code,tostring(why).." vs "..code)
end
local owner="Company"
local o={owner=owner}
local a,b,c=id(3,5),id(4,5),id(5,5)
put(a,"sea",{owner="water",base=0})
put(b,"canal",{owner=nil,base=0,occupied=true}) -- already built is skipped before clear
put(c,"clear",{base=2,clear_cost=40})
local p=assert(C.canal(B,c,a,"canal",o))
assert(p.cost==10040 and #p.tiles==2 and p.tiles[1]==a and p.tiles[2]==c and p.skipped[1]==b)
assert(p.records[a].water_class=="canal" and p.records[c].base==2 and p.records[c].owner==owner)
assert(p.operations[1].op=="clear" and p.operations[1].cost==10000 and not p.operations[1].charged)
assert(p.operations[3].op=="clear" and p.operations[3].charged and p.operations[3].cost==40)
assert(map[a].kind=="sea" and map[b].owner==nil and map[c].kind=="clear" and rev==0)
deny("NOT_ENOUGH_MONEY",C.canal,B,a,c,"canal",{owner=owner,budget=10039})
deny("ALREADY_BUILT",C.canal,B,b,b,"canal",o)
deny("INVALID_PARAMETER",C.canal,B,a,c,"river",o)
deny("INVALID_PARAMETER",C.canal,B,a,c,"sea",o)
deny("INVALID_PARAMETER",C.canal,B,nil,c,"canal",o)
deny("CAN_T_BUILD_ON_WATER",C.canal,B,a,a,"canal",{owner=owner,no_water=true})
put(b,"canal",{owner="Different"})
deny("OWNED_BY_ANOTHER",C.canal,B,b,b,"canal",o)
put(b,"river",{owner="water",occupied=true})
deny("VEHICLE_IN_THE_WAY",C.canal,B,b,b,"canal",o)
put(b,"lock",{owner=owner,water_class="canal",part="lower",dir=2})
deny("LANDSCAPE_CLEAR_REQUIRED",C.canal,B,b,b,"canal",o)
put(b,"river",{owner="water",slope=3,base=1})
deny("FLAT_LAND_REQUIRED",C.canal,B,a,c,"canal",o)
local editor={owner=owner,editor=true}
p=assert(C.canal(B,b,b,"river",editor))
assert(p.cost==5000 and p.records[b].water_class=="river" and p.records[b].owner=="water" and
  p.records[b].top==2 and p.records[b].remove_nearby_desert)
p=assert(C.canal(B,a,a,"sea",editor))
assert(p.records[a].kind=="sea" and p.records[a].owner=="water" and p.cost==5000)
p=assert(C.canal(B,c,c,"sea",editor))
assert(p.records[c].kind=="canal" and p.records[c].owner==owner and p.cost==5040)
put(b,"clear",{base=1,slope=2})
deny("FLAT_LAND_REQUIRED",C.canal,B,b,b,"river",editor)
p=assert(C.canal(B,id(1,1),id(3,1),"canal",{owner=owner,diagonal=true}))
assert(p.cost==25000 and p.tiles[1]==id(3,1) and #p.tiles==5)
assert(#C.area(B,id(1,1),id(3,1),false)==3)

-- All four physical lock orientations, class-owner preservation and
-- correct order of occupancy checks/clear application.
local center=id(8,8)
local slopes={[0]=12,6,3,9}
for dir=0,3 do
  map={}
  local lower,upper=B.adjacent(center,(dir+2)%4),B.adjacent(center,dir)
  put(center,"river",{owner="water",base=0,top=1,slope=slopes[dir]})
  put(lower,"sea",{owner="water",base=0})
  put(upper,"canal",{owner="Other company",base=1})
  local calls={}
  local p=assert(C.lock(B,center,{owner=owner,ensure_empty=function(i) calls[#calls+1]=i;return true end}))
  assert(calls[1]==center and calls[2]==upper and calls[3]==lower)
  assert(p.cost==17500 and p.middle==center and p.lower==lower and p.upper==upper and p.dir==dir)
  assert(p.records[center].kind=="lock" and p.records[center].part=="middle")
  assert(p.records[center].water_class=="river" and p.records[center].owner==owner and p.records[center].top==1)
  assert(p.records[lower].kind=="lock" and p.records[lower].part=="lower" and p.records[lower].owner=="water")
  assert(p.records[upper].water_class=="canal" and p.records[upper].owner=="Other company")
  assert(p.operations[1].op=="clear" and p.operations[1].tile==center)
  assert(p.operations[2].op=="build" and #p.operations==4 and #p.docking==2)
  assert(#p.infrastructure==1 and p.infrastructure[1].delta==6)
  map[upper].occupied=true
  deny("VEHICLE_IN_THE_WAY",C.lock,B,center,o)
  map[upper].occupied=nil;map[upper].overhead=true
  deny("MUST_DEMOLISH_BRIDGE_FIRST",C.lock,B,center,o)
  map[upper].overhead=nil
  put(upper,"clear",{base=1,clear_cost=20})
  put(lower,"coast",{base=0,slope=0})
  p=assert(C.lock(B,center,o))
  assert(p.cost==27560 and p.records[lower].water_class=="canal" and p.records[upper].owner==owner)
  assert(#p.infrastructure==3 and p.infrastructure[1].delta==1 and p.infrastructure[2].delta==1)
  assert(p.operations[2].phase=="lower" and p.operations[3].phase=="upper")
  map[lower].slope=1
  deny("LAND_SLOPED_IN_WRONG_DIRECTION",C.lock,B,center,o)
end

-- Quote is read-only; rejected operations never call the commit adapter.
map={}
put(center,"clear",{base=2,slope=3})
put(B.adjacent(center,0),"sea",{owner="water",base=2})
put(B.adjacent(center,2),"clear",{base=3})
p=assert(C.lock(B,center,o))
assert(p.cost==12500 and p.records[center].water_class=="canal")
local calls=0
function B.commit(plan)
  calls=calls+1
  for _,i in ipairs(plan.tiles) do map[i]=plan.records[i] end
  rev=rev+1
  return true
end
assert(C.apply(B,p) and calls==1 and rev==1)
deny("STALE_PLAN",C.apply,B,p)
assert(calls==1 and map[center].part=="middle")
for _,i in ipairs(p.tiles) do
  assert(Water.at(B,i)==T.trackdirs(1))
end
print("PASS: source canal shape/price/ownership and editor rules, both drag types, pure quote/execute, three directed lock records")
