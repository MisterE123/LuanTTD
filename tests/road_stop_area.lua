local p="mods/luanttd_core/openttd/"
local S=dofile(p.."road_stop_build.lua")
local A=dofile(p.."road_stop_area.lua")(S)
local id=function(x,z) return z*64+x end
local map={}
local near={}
local st={[1]={id=1,owner="Operator",spread={tile=id(10,8),w=2,h=1}},[2]={id=2,owner="Operator"},
  [3]={id=3,owner="Rival"}}
local B={id=id,xy=function(i)return i%64,math.floor(i/64) end,tile=function(i)return map[i] end,
  station=function(i)return st[i] end,surrounding=function()return near end}
local opts={requested_type={kind="road",roadtype=0},company="Operator",clear=function()return 0 end,
  piece_price=function() return 95 end,spread=4,distant_join=true}
for z=9,12 do for x=9,12 do map[id(x,z)]={kind="clear",slope=0,base=2} end end
local req={first=id(11,11),last=id(10,9),dir=0,through=true,stop_type="bus"}
local q=assert(A.quote(B,req,opts))
assert(q.area.tile==id(10,9) and q.area.w==2 and q.area.h==3 and q.cost==390*6)
near={3,1}
q=assert(A.quote(B,req,opts))
assert(q.join==1 and q.spread.tile==id(10,8) and q.spread.w==2 and q.spread.h==4)
near={3,1,2}
assert(select(2,A.quote(B,req,opts))=="ADJOINS_MULTIPLE_STATIONS")
req.adjacent=true
assert(not A.quote(B,req,opts).join)
req.join=1
assert(A.quote(B,req,opts).join==1)
opts.distant_join=false
assert(select(2,A.quote(B,req,opts))=="INVALID_STATION_TO_JOIN")
opts.distant_join=true
req.join=nil
req.through=false
assert(A.quote(B,req,opts).area.w==1)
req.through=true
map[id(10,10)].base=3
assert(select(2,A.quote(B,req,opts))=="FLAT_LAND_REQUIRED")
map[id(10,10)]={kind="station",slope=0,base=2,station=1,through=true,axis=0,stop_type="bus"}
assert(select(2,A.quote(B,req,opts))=="MUST_REMOVE_ROAD_STOP_FIRST")
req.adjacent=false
q=assert(A.quote(B,req,opts))
assert(q.join==1 and q.cost==390*5)
local allow=false
B.authority=function()return allow,"LOCAL_AUTHORITY_REFUSES" end
assert(select(2,A.quote(B,req,opts))=="LOCAL_AUTHORITY_REFUSES")
print("PASS RC1 road stop sizing, area costs, equal foundation height, adjacent/distant joining and spread")
