-- Stock one-emission competition across the same physical station class.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,P,Rating,H=m("sim"),m("openttd/passengers"),m("openttd/station_rating"),m("openttd/town_passengers")
local Mail=m("road_mail_runtime")(Sim,H,P,m("openttd/income"),Rating,m("station_rating_runtime")(Sim,Rating,P))
local Catchment=m("openttd/station_catchment")(P,Rating,nil,Mail.house_acceptance)
local function stop(id,kind,x,z,w,owner)
  local tiles={}
  for i=0,w-1 do tiles[#tiles+1]={x=x+i,y=z,kind=kind} end
  return {id=id,mode=kind,tiles=tiles,owner=owner or "Carrier",town=5,stock={}}
end
local a,b,c=stop(1,"truck",12,13,1),stop(0x4001,"rail",16,13,3),stop(4,"bus",13,13,1)
local mail=Mail.shared_allocator(Catchment,64,64,{b,c,a})
local record={id=5,town=2}
assert(mail.near(b.id,21,13) and not mail.near(b.id,23,13))
assert(mail.offer(34,14,13,record)==0,"Stock selective servicing ignores unserved stations")
mail.loading(a.id,"road",96,1980,1975,22)
mail.loading(b.id,"rail",200,1980,1978,30)
-- Force a last-speed state even on an ineligible bus-only stop.
mail.loading(c.id,"road",96,1980,1975,31)
assert(a.mail_rating_state.last_speed==48 and b.mail_rating_state.last_speed==200)
local received=mail.offer(34,14,13,record)
assert(received>0 and received<34 and Mail.waiting(a)>0 and Mail.waiting(b)>0 and Mail.waiting(c)==0)
assert(Mail.waiting(a)+Mail.waiting(b)==received)
assert(a.stock.mail[1].origin_station==a.id and b.stock.mail[1].origin_station==b.id)
assert(a.stock.mail[1].source==record.town and b.stock.mail[1].source==record.town)
local function house(x,z) return (x==16 or x==17) and z==14 and {id=4,town=5} or nil end
assert(mail.acceptance(b.id,house).accepts and not mail.acceptance(c.id,house).accepts)
local d=stop(5,"truck",12,13,1,"Competitor")
local held=Mail.shared_allocator(Catchment,64,64,{a,d},{exclusive_owner="Carrier"})
held.loading(d.id,"road",96,1980,1979,22)
assert(held.offer(20,14,13,record)>0 and Mail.waiting(d)==0)
print("PASS a single stock house Mail emission shares road/rail ratings, exact station footprints and cargo filters")
