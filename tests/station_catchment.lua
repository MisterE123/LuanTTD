-- SPDX-License-Identifier: GPL-2.0-only
local root="mods/luanttd_core/"
local Packets=dofile(root.."openttd/passengers.lua")
local Rating=dofile(root.."openttd/station_rating.lua")
local Mail=dofile(root.."road_mail_runtime.lua")()
local Road=dofile(root.."road_station_service.lua")()
local C=dofile(root.."openttd/station_catchment.lua")(
  Packets,Rating,Road.house_passenger_acceptance,Mail.house_acceptance)
local function tile(x,y,kind,station) return {x=x,y=y,kind=kind,station=station} end
local function rect(x,y,u,v) return {left=x,top=y,right=u,bottom=v} end
local w,h=24,16
-- One 12-tile-wide station with three facility types. The last dock square
-- covers a house that would not be covered by the land portion on its own.
local multi={id=11,owner=1,town=102,tiles={
  tile(1,2,"bus"),tile(5,3,"rail"),tile(6,3,"rail"),tile(6,4,"rail"),
  tile(11,11,"dock"),tile(12,11,"dock"),tile(8,8,"dock",19),
}}
local a=C.build(multi,w,h)
assert(a.radius==5 and a.station_rect.left==1 and a.station_rect.right==12)
assert(a.bounds.left==0 and a.bounds.top==0 and a.bounds.right==17 and a.bounds.bottom==15)
assert(C.contains(a,0,0) and C.contains(a,17,12) and not C.contains(a,18,12))
assert(not C.contains(a,3,9)) -- inside bounds, outside all genuine squares
assert(not C.contains(a,4,9)) -- covered by only the foreign station within the rect
local legacy=C.build(multi,w,h,false)
assert(legacy.radius==4 and C.contains(legacy,0,6) and not C.contains(a,0,6))
assert(not C.contains(legacy,17,12))
assert(C.radius("bus")==3 and C.radius("truck")==3 and C.radius("rail")==4 and C.radius("dock")==5)
assert(C.radius("buoy",false)==0 and C.radius("waypoint")==0)
assert(C.can_extend(multi,a,rect(11,9,12,11),1))
local ok,why=C.can_extend(multi,a,rect(13,10,13,10),1)
assert(not ok and why=="spread")
ok,why=C.can_extend(multi,a,rect(8,5,8,5),2)
assert(not ok and why=="ownership")
assert(C.can_extend(multi,a,rect(13,10,13,10),1,13))
assert(not C.can_extend(nil,nil,rect(1,1,14,1),1))

local tiles={
  [2+3*w]={id=0x03,town=101,completed=false}, -- bus/rail overlap; only 2,0
  [7+4*w]={id=0x04,town=101,completed=true}, -- rail: 10,4
  [17+12*w]={id=0x01,town=103,completed=false}, -- dock water: 8,3
  [14+14*w]={id=0x07,town=103,completed=true}, -- dock: 6,1
  [4+9*w]={id=0x04,town=104,completed=true}, -- hole
}
local function house_at(x,y) return tiles[x+y*w] end
local p=C.acceptance(a,"passenger",house_at)
assert(p.eighths==26 and p.demand==3 and p.accepts and p.always_accepted)
assert(p.towns[101]==12 and p.towns[103]==14 and not p.towns[104])
local m=C.acceptance(a,"mail",house_at)
assert(m.eighths==8 and m.demand==1 and m.accepts)
assert(not C.acceptance(legacy,"mail",house_at).accepts)
local bus={id=12,owner=2,town=101,tiles={tile(1,3,"bus")}}
local rail={id=13,owner=1,town=101,tiles={tile(2,3,"rail")}}
local dock={id=14,owner=2,town=102,tiles={tile(1,5,"dock")}}
local truck={id=15,owner=2,town=102,tiles={tile(2,5,"truck")}}
local neutral={id=16,owner="neutral",town=102,tiles={tile(0,4,"dock")}}
local by_id={[11]=a}
for _,st in ipairs{bus,rail,dock,truck,neutral} do by_id[st.id]=C.build(st,w,h) end
local function always_house() return {id=0x04,town=1} end
p=C.acceptance(by_id[15],"passenger",always_house)
assert(not p.accepts and p.eighths==0 and p.always_accepted and p.raw_eighths>8)
m=C.acceptance(by_id[12],"mail",always_house)
assert(not m.accepts and m.eighths==0 and m.always_accepted and m.raw_eighths>8)
local goods={}
for _,st in ipairs{multi,bus,rail,dock,truck,neutral} do
  goods[st.id]={passenger=Rating.new(),mail=Rating.new()}
end
local function get_goods(st,cargo) return goods[st.id][cargo] end
Rating.observe_loading(goods[11].passenger,280,0,0) -- full vehicle still attempted service
goods[11].passenger.rating=200
Rating.observe_loading(goods[12].passenger,50,10,25)
goods[12].passenger.rating=100
Rating.observe_loading(goods[13].passenger,50,10,25)
goods[13].passenger.rating=100
Rating.observe_loading(goods[15].passenger,50,10,25)
Rating.observe_loading(goods[16].passenger,50,10,25)
assert(C.offer(multi,a,"passenger",17,12,get_goods)==200)
assert(not C.offer(multi,a,"passenger",4,9,get_goods))
assert(not C.offer(dock,by_id[14],"passenger",2,3,get_goods))
assert(C.offer(dock,by_id[14],"passenger",2,3,get_goods,{select_goods=false})==175)
assert(not C.offer(truck,by_id[15],"passenger",2,3,get_goods,{select_goods=false}))
assert(not C.offer(bus,by_id[12],"mail",2,3,get_goods,{select_goods=false}))
local opts={neutral_owner="neutral",town_rights=function(id)
  if id==102 then return {exclusive_counter=5,exclusivity=2} end
end}
assert(not C.offer(multi,a,"passenger",2,3,get_goods,opts))
assert(C.offer(rail,by_id[13],"passenger",2,3,get_goods,opts)==100)
assert(C.offer(neutral,by_id[16],"passenger",2,3,get_goods,opts)==175)
opts.exclusive_owner=2
assert(not C.offer(neutral,by_id[16],"passenger",2,3,get_goods,opts))
assert(C.offer(bus,by_id[12],"passenger",2,3,get_goods,opts)==100)
goods[12].passenger.rating=0
assert(not C.offer(bus,by_id[12],"passenger",2,3,get_goods,{select_goods=false}))
goods[12].passenger.rating=100
local alloc=C.allocate(5,{truck,rail,dock,bus,multi,multi},by_id,"passenger",2,3,get_goods)
assert(#alloc==3 and alloc[1].st.id==11 and alloc[2].st.id==12 and alloc[3].st.id==13)
assert(alloc[1].fixed==447 and alloc[2].fixed==335 and alloc[3].fixed==223)
assert(not C.acceptance(by_id[14],"passenger",function() end).accepts)
assert(C.offer(dock,by_id[14],"passenger",2,3,get_goods,{select_goods=false})==175)

local rating=Rating.new()
local metadata={time_since_load=10,last_vehicle_type="rail"}
C.observe_loading(rating,"road",175,1960,1959,30)
assert(rating.last_speed==87 and rating.last_age==1 and rating.time_since_pickup==0)
C.observe_loading(rating,"rail",260,1960,1960,0)
assert(rating.last_speed==255 and rating.last_age==0)
rating.time_since_pickup=18
C.observe_loading(rating,"ship",95,1960,1950,0)
assert(rating.last_speed==95 and rating.last_age==10 and rating.time_since_pickup==18)
assert(C.may_load(multi,1,{exclusive_counter=5,exclusivity=2},"neutral"))
assert(not C.may_load(neutral,1,{exclusive_counter=5,exclusivity=2},"neutral"))
assert(C.may_load(neutral,2,{exclusive_counter=5,exclusivity=2},"neutral"))
C.loaded(metadata,"ship",0)
assert(metadata.last_vehicle_type=="rail" and metadata.time_since_load==10)
local tickopts={waiting=20,destinations=1,select_goods=true,random_u32=function()return 255 end}
rating.has_rating,rating.rating=true,115
local rail_score=C.rating_step(metadata,rating,tickopts)
C.loaded(metadata,"ship",1)
assert(metadata.last_vehicle_type=="ship" and metadata.time_since_load==0)
local ferry_score=C.rating_step(metadata,rating,tickopts)
assert(ferry_score.rating>rail_score.rating and not tickopts.ship)

if arg and arg[1]=="differential" then
  for line in io.lines() do
    local n={}
    for item in line:gmatch("%S+") do n[#n+1]=tonumber(item) end
    local x,y,modified,select_goods,explicit=n[1],n[2],n[3]==1,n[4]==1,n[5]
    local candidate,idmap={},{}
    for j=1,n[6] do
      local i=7+(j-1)*11
      local kinds={"bus","truck","rail","dock","buoy","waypoint"}
      local st={id=j,owner=n[i],town=j,tiles={
        tile(n[i+3],n[i+4],kinds[n[i+5]]),tile(n[i+6],n[i+7],kinds[n[i+8]]),
      },g={rating=n[i+1],last_speed=n[i+2]},rights={
        exclusive_counter=n[i+9],exclusivity=n[i+10],
      }}
      candidate[j]=st
      idmap[j]=C.build(st,16,16,modified)
    end
    local cargo=n[7+11*n[6]]==1 and "passenger" or "mail"
    local out=C.allocate(7,candidate,idmap,cargo,x,y,function(st) return st.g end,{
      neutral_owner=16,select_goods=select_goods,exclusive_owner=explicit>=0 and explicit or nil,
      town_rights=function(town) return candidate[town].rights end,
    })
    local all={}
    for _,entry in ipairs(out) do all[#all+1]=entry.st.id..":"..entry.fixed end
    local amount={}
    for j=1,#candidate do
      local acceptance=C.acceptance(idmap[j],cargo,function(u,v)
        if u==x and v==y then return {id=(x*16+y)%110,completed=false} end
      end)
      amount[j]=(acceptance.accepts and "1" or "0")..":"..
        (acceptance.always_accepted and "1" or "0")
    end
    print(table.concat(amount,",").." "..table.concat(all,","))
  end
else
  print("PASS: shared station geometry, actual house eighths, rights and selective allocation")
end
