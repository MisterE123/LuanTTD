local dir="mods/bayline/openttd/"
local Follow=dofile(dir.."yapf_road_follow.lua")
local Cost=dofile(dir.."yapf_road_cost.lua")(Follow)
local Search=dofile(dir.."yapf_road_search.lua")(Follow,Cost)
local R=dofile(dir.."road_oneway.lua")(dofile(dir.."road_slope.lua"),Follow)
local function check(val,want) assert(val==want,tostring(val).." != "..tostring(want)) end
local function road(bits,owner,old)
  return {kind="road",roadtype=0,road_bits=bits,owner=owner,disallowed=old or 0}
end
local mine={company="my company"}
local t=road(10,"my company")
local r=assert(R.tile(t,10,R.NORTHBOUND,mine))
check(r.cost,0);check(r.disallowed,2);check(t.disallowed,0)
r=assert(R.tile(r,10,R.SOUTHBOUND,mine));check(r.disallowed,3)
r.occupied=true
local u=assert(R.tile(r,10,R.NORTHBOUND,mine));check(u.disallowed,1)
u.occupied=true
assert(R.tile(u,10,R.SOUTHBOUND,mine).disallowed==0)
local function rejects(expected,...)
  local result,err=R.tile(...)
  check(result,nil);check(err,expected)
end
rejects("VEHICLE_IN_THE_WAY",u,10,R.BOTH,mine) -- 1→2 replaces bits, not a decrease
rejects("VEHICLE_IN_THE_WAY",u,10,R.NORTHBOUND,mine)
rejects("OWNED_BY",road(10,"town"),10,R.NORTHBOUND,mine)
rejects("OWNED_BY",road(10,"other"),10,R.NORTHBOUND,mine)
assert(R.tile(road(10),8,R.NORTHBOUND,mine).disallowed==2)
rejects("ONEWAY_JUNCTION",road(15),8,R.NORTHBOUND,mine)
rejects("ONEWAY_JUNCTION",road(2),2,R.NORTHBOUND,mine)
rejects("ONEWAY_JUNCTION",road(10,nil,R.BOTH),4,R.NONE,mine) -- ordinary build must honor signs
rejects("ALREADY_BUILT",road(10),10,R.NONE,mine)
rejects("UNSUPPORTED_TILE",{kind="crossing",road_bits=10},10,R.SOUTHBOUND,mine)
rejects("UNSUPPORTED_TILE",{kind="drive_stop",road_bits=10},10,R.SOUTHBOUND,mine)
rejects("UNSUPPORTED_ROADTYPE",road(10),10,R.NORTHBOUND,{tram=true})
local fresh=assert(R.tile({kind="clear"},2,R.SOUTHBOUND,mine))
assert(fresh.cost==95 and fresh.disallowed==0 and fresh.road_bits==2)
assert(R.tile(fresh,8,R.SOUTHBOUND,mine).disallowed==R.SOUTHBOUND)
local mixed=road(10);mixed.tram_bits=10;mixed.tramtype=1
local sign=assert(R.tile(mixed,2,R.SOUTHBOUND,mine))
mixed.disallowed=sign.disallowed
check(Follow.status(mixed,true),257) -- one-way modifies the carriageway only
check(Follow.status(mixed,false),256)
check(R.after_remove(2,false),0)
check(R.after_remove(2,true),2)
check(R.arrow(10,1),Follow.SW);check(R.arrow(10,2),Follow.NE)
check(R.arrow(5,1),Follow.NW);check(R.arrow(5,2),Follow.SE)
check(select(2,R.arrow(5,3)),"no-entry")

local tiles={}
local function id(x,y) return y*16+x end
local function xy(i) return i%16,math.floor(i/16) end
local board={tile=function(i) return tiles[i] end,xy=xy,
  adjacent=function(i,d) return i+({[0]=-1,16,1,-16})[d] end,center_z=function() return 0 end}
local function apply(p)
  for _,e in ipairs(p.changes) do tiles[e.tile]=e end
end
local function drag(a,b,axis,expected_sign)
  local p=assert(R.plan(board,a,b,axis,mine))
  check(p.cost,0)
  check(p.drag.toggle,expected_sign)
  check(p.drag.requests[1].tile,a)
  check(p.drag.requests[#p.drag.requests].tile,b)
  return p
end
for x=1,7 do tiles[id(x,4)]=road(10,mine.company) end
local a,b=id(2,4),id(6,4)
local v={owner=mine.company,display_max_speed=112,compatible={[0]=true}}
local function reaches(start,last,td)
  local d=Cost.destination(board,v,{kind="tile",tile=last})
  return Search.find(board,v,start,2^td,d)
end
assert(reaches(id(1,4),id(7,4),8) and reaches(id(7,4),id(1,4),0))
apply(drag(a,b,R.X,R.SOUTHBOUND))
assert(reaches(id(1,4),id(7,4),8) and not reaches(id(7,4),id(1,4),0))
apply(drag(b,a,R.X,R.NORTHBOUND))
assert(not reaches(id(1,4),id(7,4),8) and not reaches(id(7,4),id(1,4),0))
apply(drag(a,b,R.X,R.SOUTHBOUND))
assert(not reaches(id(1,4),id(7,4),8) and reaches(id(7,4),id(1,4),0))
apply(drag(b,a,R.X,R.NORTHBOUND))
assert(reaches(id(1,4),id(7,4),8) and reaches(id(7,4),id(1,4),0))

for y=1,7 do tiles[id(8,y)]=road(5,mine.company) end
local south,north=Follow.direction_trackdir(Follow.SE),Follow.direction_trackdir(Follow.NW)
a,b=id(8,2),id(8,6)
apply(drag(a,b,R.Y,R.NORTHBOUND))
assert(reaches(id(8,1),id(8,7),south) and not reaches(id(8,7),id(8,1),north))
apply(drag(a,b,R.Y,R.NORTHBOUND))
apply(drag(b,a,R.Y,R.SOUTHBOUND))
assert(not reaches(id(8,1),id(8,7),south) and reaches(id(8,7),id(8,1),north))

for x=1,7 do tiles[id(x,10)]={kind="clear"} end
local p=assert(R.plan(board,id(2,10),id(6,10),R.X,mine))
check(p.changes[1].road_bits,2);check(p.changes[1].disallowed,0)
check(p.changes[5].road_bits,8);check(p.changes[5].disallowed,0)
check(p.changes[3].road_bits,10);check(p.changes[3].disallowed,1)
check(p.cost,8*95)
tiles[id(2,10)]={kind="crossing"};tiles[id(5,10)]={kind="crossing"}
p=assert(R.plan(board,id(2,10),id(6,10),R.X,mine))
check(#p.changes,2);check(#p.skipped,2);check(p.stopped_at,id(5,10))
local dont,why=R.plan(board,id(2,10),id(6,10),R.X,{company=mine.company,ai=true})
assert(not dont and why=="UNSUPPORTED_TILE" and tiles[id(3,10)].kind=="clear")
print("PASS one-way road XOR/occupancy, GUI drag, and directed YAPF both axes")
