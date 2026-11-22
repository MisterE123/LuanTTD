local B=dofile("mods/luanttd_core/openttd/road_bridge.lua")(dofile("mods/luanttd_core/openttd/slope.lua"))
local tiles,calls={},{}
local function id(x,z)
  if x<1 or z<1 or x>16 or z>12 then return nil end
  return (z-1)*16+x
end
local function xy(at) return (at-1)%16+1,math.floor((at-1)/16)+1 end
local function cell(x,z,details)
  local tile={kind="clear",base=0,slope=0,max_z=0}
  for k,v in pairs(details or {}) do tile[k]=v end
  tiles[id(x,z)]=tile
  return tile
end
local function reset()
  tiles={};calls={}
  for z=1,12 do for x=1,16 do cell(x,z) end end
end
local board={id=id,xy=xy,tile=function(at) return tiles[at] end}
function board.clear_quote(at,tile,role,owner)
  calls[#calls+1]={id=at,role=role,owner=owner}
  if tile.deny_clear then return nil,"PROTECTED_TILE" end
  return tile.clear_cost or 0
end
local function plan(a,b,n,opts) return B.plan(board,a,b,n,opts or {owner="A",year=1950}) end
local function reject(a,b,n,code,opts)
  local x,r,at=plan(a,b,n,opts)
  assert(not x and r==code,(r or "accepted").." instead of "..code)
  return at
end

reset()
local a,b=id(2,4),id(8,4)
for x=3,7 do cell(x,4,{kind="water"}) end
local X=assert(plan(b,a,2))
assert(X.start==a and X["end"]==b and X.axis==B.AXIS_X and X.deck==1)
assert(X.head.inside_direction==B.SW and X.tail.inside_direction==B.NE)
assert(X.head.road_slope==3 and X.tail.road_slope==12)
assert(B.surface(X,a,0,0)==0 and B.surface(X,a,1,0)==X.deck)
assert(B.surface(X,b,0,1)==X.deck and B.surface(X,b,1,1)==0)
assert(B.surface(X,id(5,4),.5,.5)==1 and B.surface(X,id(5,5),.5,.5)==nil)
assert(#X.middle==5 and X.middle[3]==id(5,4) and #X.clears==2)
assert(X.middle_length==5 and X.total_length==7 and X.owner=="A")
assert(X.roadtype==0 and X.road_owner=="A" and X.tramtype==nil)
assert(X.price==7*2*95+math.floor(B.length_factor(7)*275*144/256))
assert(X.site_cost==0 and X.price==X.road_cost+X.structure_cost)
assert(tiles[id(5,4)].kind=="water","Quoting must not overwrite the landscape")
assert(calls[1].id==a and calls[1].role=="head" and calls[2].id==b)
reject(a,a,0,"BRIDGE_SAME_ENDPOINT")
reject(a,id(9,5),0,"BRIDGE_ENDPOINTS_MUST_ALIGN")
reject(a,-1,0,"BRIDGE_THROUGH_MAP_BORDER")
reject(a,b,1,"BRIDGE_TOO_LONG")
reject(a,b,10,"BRIDGE_UNAVAILABLE")
assert(assert(plan(a,b,99,{query=true,year=1950,owner="A"})).price==0)
reject(a,b,2,"NOT_ENOUGH_CASH",{budget=X.price-1,owner="A"})
local choices=B.quotes(board,a,b,{owner="A",year=1950})
assert(#choices>1 and choices[1].bridge_type==0)
for _,quote in ipairs(choices) do assert(quote.bridge_type<10) end

reset()
a,b=id(4,2),id(4,7)
cell(4,2,{base=2,slope=9,max_z=3})
cell(4,7,{base=2,slope=6,max_z=3})
X=assert(plan(a,b,0,{owner="A",build_on_slopes=false}))
assert(X.axis==B.AXIS_Y and X.deck==3 and X.head.flat_ramp and X.tail.flat_ramp)
assert(X.head.inside_direction==B.SE and X.tail.inside_direction==B.NW)
assert(X.head.foundation=="none" and B.surface(X,a,0,0)==3 and B.surface(X,b,1,1)==3)
cell(4,2,{base=2,slope=6,max_z=3})
assert(reject(a,b,0,"LAND_SLOPED_IN_WRONG_DIRECTION")==a)
cell(4,2,{base=1,slope=3,max_z=2})
X=assert(plan(a,b,0))
assert(X.head.foundation=="leveled" and X.site_cost==250 and X.head.base==2)
reject(a,b,0,"LAND_SLOPED_IN_WRONG_DIRECTION",{build_on_slopes=false})
cell(4,7,{base=3,slope=6,max_z=4})
reject(a,b,0,"BRIDGEHEADS_NOT_SAME_HEIGHT")

reset()
a,b=id(2,5),id(7,5)
local mid=id(4,5)
cell(4,5,{base=0,slope=1,max_z=1})
assert(reject(a,b,0,"BRIDGE_TOO_LOW_FOR_TERRAIN")==mid)
cell(4,5,{kind="road",overhead={axis=B.AXIS_Y,deck=2}})
assert(reject(a,b,0,"MUST_DEMOLISH_BRIDGE_FIRST")==mid)
cell(4,5,{kind="road"})
assert(#assert(plan(a,b,0)).clears==2)
cell(4,5,{kind="object",allow_under_bridge=true,object_height=1,deny_clear=true})
assert(reject(a,b,0,"PROTECTED_TILE")==mid)
cell(4,5,{kind="house",clear_cost=70})
X=assert(plan(a,b,0))
assert(X.site_cost==70 and X.clears[3]==mid)
cell(4,5,{kind="clear"})
cell(2,5,{base=12,max_z=12})
cell(7,5,{base=12,max_z=12})
assert(reject(a,b,0,"BRIDGE_TOO_HIGH_FOR_TERRAIN")==id(3,5))
X=assert(plan(a,b,0,{owner="M",max_height=13,roadtype=1,company=false}))
assert(X.tramtype==1 and X.tram_owner=="M" and not X.roadtype and X.road_cost==6*2*190)
assert(B.roadtypes[0].flags==B.road_flags.town_build)
assert(B.roadtypes[1].flags==B.road_flags.catenary+B.road_flags.no_houses)
assert(B.roadtypes[0].label=="ROAD" and B.roadtypes[1].label=="ELRL")
assert(B.road_clear_cost(0)==40 and B.road_clear_cost(1)==-102)
assert(X.structure_cost==math.floor(6*275*80/256),"Towns bypass the company long-bridge factor")
cell(2,5,{base=12,max_z=12,overhead={axis=B.AXIS_X,deck=17}})
reject(a,b,0,"MUST_DEMOLISH_BRIDGE_FIRST",{max_height=13})
cell(2,5,{base=12,max_z=12,overhead={axis=B.AXIS_Y,deck=13}})
reject(a,b,0,"MUST_DEMOLISH_BRIDGE_FIRST",{max_height=13})
cell(2,5,{base=12,max_z=12,overhead={axis=B.AXIS_Y,deck=15}})
assert(plan(a,b,0,{max_height=13}))

reset()
a,b=id(2,5),id(7,5)
local na=cell(2,5,{kind="bridge",bridge_type=2,transport="road",owner="A",other=b,axis=0,deck=1,roadtype=0,road_owner="A"})
local nb=cell(7,5,{kind="bridge",bridge_type=2,transport="road",owner="A",other=a,axis=0,deck=1,roadtype=0,road_owner="A"})
reject(a,b,2,"ALREADY_BUILT")
reject(a,b,3,"AREA_IS_OWNED_BY_ANOTHER",{owner="B"})
X=assert(plan(a,b,3))
assert(X.replacement and X.owner=="A" and X.road_owner=="A" and X.site_cost==6*(50+2*40))
assert(#X.clears==0 and X.road_cost==6*2*95)
X=assert(plan(a,b,2,{owner="A",roadtype=1,road_build_price={[0]=95,[1]=127}}))
assert(X.roadtype==0 and X.tramtype==1 and X.road_cost==6*2*(95+127) and X.replacement)
na.owner="town";nb.owner="town"
reject(a,b,0,"LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS",{owner="A"})
assert(assert(plan(a,b,0,{owner="A",editor=true})).owner=="town")
reject(a,b,2,"MUST_DEMOLISH_BRIDGE_FIRST",{owner="A",roadtype=7,roadtypes={[7]={type="road"}}})
print("PASS: atomic bridge plan, world ramp geometry, catalog availability, layered obstacles, quotes and bridge replacement")
