local root="mods/luanttd_core/"
local R=dofile(root.."openttd/station_rating.lua")
local Campaign=dofile(root.."openttd/town_advertising_rc1.lua")
local support={
  xy=function(id)return id,1 end,
  passenger_rating=function()end,
  road_passenger_acceptance=function()return 0 end,
}
local W=dofile(root.."town_advertising_world.lua")(support,R)
local shared={rating=185,has_rating=true}
local idle={rating=175,has_rating=false}
local own_boundary={rating=158}
local outside={rating=173,has_rating=true}
local enemy={rating=24,has_rating=true}
local freight={rating=40,last_month=true}
local stock={stations={
  {mode="road",tile=1,owner="me",passenger_rating_state=shared,mail_rating_state=idle},
  {mode="road",tile=11,owner="me",passenger_rating_state=own_boundary,passenger_acceptance=8,goods={wood=freight}},
  {mode="road",tile=12,owner="me",passenger_rating_state=outside},
  {mode="road",tile=1,owner="rival",passenger_rating_state=enemy},
}}
stock.stock_ship_commercial={service={stations={{
  owner="me",sign={x=1,y=1},passenger_rating_state=shared,mail_rating_state=idle,
}}}}
local q=assert(Campaign.quote("small"))
assert(q.cost==7812 and q.bonus==64 and q.radius==10)
assert(W.apply(stock,"me",1,1,q.bonus,q.radius)==3)
assert(shared.rating==249 and own_boundary.rating==222 and freight.rating==104)
assert(idle.rating==175 and outside.rating==173 and enemy.rating==24)
q=assert(Campaign.quote("medium"))
assert(q.cost==15625 and q.bonus==112 and q.radius==15)
assert(W.apply(stock,"me",1,1,q.bonus,q.radius)==4)
assert(shared.rating==255 and outside.rating==255 and enemy.rating==24)
q=assert(Campaign.quote("large"))
assert(q.cost==35156 and q.bonus==160 and q.radius==20)
assert(Campaign.quote("unsupported")==nil)
print("PASS RC1 advertising prices, Manhattan radii, active GoodsEntries, rivals and shared station deduplication")
